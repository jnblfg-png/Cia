import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { crypto } from "https://deno.land/std@0.177.0/crypto/mod.ts";

interface FinalizeReportPayload {
  report_id: string;
}

serve(async (req: Request) => {
  try {
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    );

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser(token);

    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401, headers: { "Content-Type": "application/json" },
      });
    }

    const payload: FinalizeReportPayload = await req.json();

    if (!payload.report_id) {
      return new Response(JSON.stringify({ error: "report_id is required" }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } }
    );

    // Verify user's agency
    const { data: profile } = await supabaseAdmin
      .from("profiles")
      .select("id, agency_id, full_name")
      .eq("id", user.id)
      .single();

    if (!profile) {
      return new Response(JSON.stringify({ error: "Profile not found" }), {
        status: 404, headers: { "Content-Type": "application/json" },
      });
    }

    // Fetch report
    const { data: report, error: reportError } = await supabaseAdmin
      .from("reports")
      .select("id, agency_id, case_id, status, content, created_at")
      .eq("id", payload.report_id)
      .single();

    if (reportError || !report) {
      return new Response(JSON.stringify({ error: "Report not found" }), {
        status: 404, headers: { "Content-Type": "application/json" },
      });
    }

    if (report.agency_id !== profile.agency_id) {
      return new Response(JSON.stringify({ error: "Report does not belong to your agency" }), {
        status: 403, headers: { "Content-Type": "application/json" },
      });
    }

    // Validate status transition
    if (report.status === "finalized") {
      return new Response(JSON.stringify({ error: "Report is already finalized" }), {
        status: 409, headers: { "Content-Type": "application/json" },
      });
    }

    if (report.status !== "draft") {
      return new Response(JSON.stringify({ error: `Cannot finalize report in status: ${report.status}` }), {
        status: 409, headers: { "Content-Type": "application/json" },
      });
    }

    // Update report to finalized — atomic write
    const now = new Date().toISOString();
    const { data: finalizedReport, error: updateError } = await supabaseAdmin
      .from("reports")
      .update({
        status: "finalized",
        finalized_at: now,
        finalized_by: user.id,
      })
      .eq("id", payload.report_id)
      .eq("agency_id", profile.agency_id)
      .select()
      .single();

    if (updateError || !finalizedReport) {
      return new Response(JSON.stringify({ error: "Failed to finalize report" }), {
        status: 500, headers: { "Content-Type": "application/json" },
      });
    }

    // Create audit trail via the case's evidence items (valid FK to evidence_items)
    // Find the first evidence item in this case to anchor the finalization audit
    const { data: caseEvidence } = await supabaseAdmin
      .from("evidence_items")
      .select("id")
      .eq("case_id", report.case_id)
      .eq("agency_id", profile.agency_id)
      .limit(1)
      .single();

    // Get the last custody entry globally for hash chaining
    const { data: lastCustody } = await supabaseAdmin
      .from("custody_log")
      .select("current_hash")
      .order("id", { ascending: false })
      .limit(1)
      .single();

    if (caseEvidence) {
      const previousHash = lastCustody?.current_hash ?? "0000000000000000000000000000000000000000000000000000000000000000";
      const hashInput = `${previousHash}|finalized|${user.id}|${now}|${report.id}|${report.case_id}`;
      const hashBuffer = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(hashInput));
      const hashArray = Array.from(new Uint8Array(hashBuffer));
      const currentHash = hashArray.map(b => b.toString(16).padStart(2, "0")).join("");

      const { error: custodyError } = await supabaseAdmin
        .from("custody_log")
        .insert({
          evidence_id: caseEvidence.id,
          agency_id: profile.agency_id,
          event_type: "finalized",
          performed_by: user.id,
          previous_hash: previousHash,
          current_hash: currentHash,
          payload: {
            report_id: report.id,
            case_id: report.case_id,
            finalized_by: user.id,
            finalized_at: now,
            type: "report_finalization",
          },
        })
        .select()
        .single();

      if (custodyError) {
        // Rollback: revert the report status to draft if custody write fails
        await supabaseAdmin
          .from("reports")
          .update({ status: "draft", finalized_at: null, finalized_by: null })
          .eq("id", payload.report_id);

        return new Response(JSON.stringify({ error: "Audit trail creation failed — report update reverted" }), {
          status: 500, headers: { "Content-Type": "application/json" },
        });
      }
    }

    return new Response(
      JSON.stringify({
        report: {
          id: finalizedReport.id,
          case_id: finalizedReport.case_id,
          title: finalizedReport.title,
          status: finalizedReport.status,
          finalized_at: finalizedReport.finalized_at,
          finalized_by: finalizedReport.finalized_by,
        },
        custody: custodyEntry ? {
          entry_id: custodyEntry.id,
          event_type: custodyEntry.event_type,
          current_hash: custodyEntry.current_hash,
        } : null,
        message: "Report finalized. Status locked — no further edits allowed.",
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: `Internal error: ${err.message}` }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
});