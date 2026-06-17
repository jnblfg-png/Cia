import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { crypto } from "https://deno.land/std@0.177.0/crypto/mod.ts";

interface RegisterEvidencePayload {
  case_id: string;
  media_type: "photo" | "video" | "audio";
  file_path: string;
  file_hash: string;
  file_size?: number;
  mime_type?: string;
  gps_latitude?: number;
  gps_longitude?: number;
  gps_accuracy?: number;
  gps_source?: "device_gps" | "manual_entry" | "geotag" | "unknown";
  captured_at: string;
  device_clock_time?: string;
  rfc3161_timestamp?: string;
  secure_enclave_signature?: string;
  metadata?: Record<string, unknown>;
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

    const payload: RegisterEvidencePayload = await req.json();

    // Validation
    if (!payload.case_id || !payload.media_type || !payload.file_path || !payload.file_hash || !payload.captured_at) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: case_id, media_type, file_path, file_hash, captured_at" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    if (!["photo", "video", "audio"].includes(payload.media_type)) {
      return new Response(
        JSON.stringify({ error: "media_type must be photo, video, or audio" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    if (!/^[a-f0-9]{64}$/i.test(payload.file_hash)) {
      return new Response(
        JSON.stringify({ error: "file_hash must be a 64-char hex SHA-256" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Use service_role for write operations (bypass RLS)
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } }
    );

    // Get user's profile to verify agency
    const { data: profile, error: profileError } = await supabaseAdmin
      .from("profiles")
      .select("id, agency_id, role, full_name")
      .eq("id", user.id)
      .single();

    if (profileError || !profile) {
      return new Response(JSON.stringify({ error: "Profile not found" }), {
        status: 404, headers: { "Content-Type": "application/json" },
      });
    }

    // Verify user belongs to the case's agency
    const { data: caseData, error: caseError } = await supabaseAdmin
      .from("cases")
      .select("id, agency_id")
      .eq("id", payload.case_id)
      .single();

    if (caseError || !caseData) {
      return new Response(JSON.stringify({ error: "Case not found" }), {
        status: 404, headers: { "Content-Type": "application/json" },
      });
    }

    if (caseData.agency_id !== profile.agency_id) {
      return new Response(JSON.stringify({ error: "Case does not belong to your agency" }), {
        status: 403, headers: { "Content-Type": "application/json" },
      });
    }

    // Insert the evidence item
    const { data: evidence, error: evidenceError } = await supabaseAdmin
      .from("evidence_items")
      .insert({
        agency_id: profile.agency_id,
        case_id: payload.case_id,
        captured_by: user.id,
        media_type: payload.media_type,
        file_path: payload.file_path,
        file_hash: payload.file_hash,
        file_size: payload.file_size ?? null,
        mime_type: payload.mime_type ?? null,
        gps_latitude: payload.gps_latitude ?? null,
        gps_longitude: payload.gps_longitude ?? null,
        gps_accuracy: payload.gps_accuracy ?? null,
        gps_source: payload.gps_source ?? null,
        captured_at: payload.captured_at,
        device_clock_time: payload.device_clock_time ?? null,
        rfc3161_timestamp: payload.rfc3161_timestamp ?? null,
        secure_enclave_signature: payload.secure_enclave_signature ?? null,
        metadata: payload.metadata ?? {},
        is_sealed: true,
      })
      .select()
      .single();

    if (evidenceError) {
      return new Response(JSON.stringify({ error: `Failed to register evidence: ${evidenceError.message}` }), {
        status: 500, headers: { "Content-Type": "application/json" },
      });
    }

    // Create first custody_log entry
    const zeroHash = "0000000000000000000000000000000000000000000000000000000000000000";
    const hashInput = `${zeroHash}|captured|${user.id}|${payload.captured_at}|${payload.file_hash}`;
    const hashBuffer = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(hashInput));
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const firstHash = hashArray.map(b => b.toString(16).padStart(2, "0")).join("");

    const { data: custodyEntry, error: custodyError } = await supabaseAdmin
      .from("custody_log")
      .insert({
        evidence_id: evidence.id,
        agency_id: profile.agency_id,
        event_type: "captured",
        performed_by: user.id,
        previous_hash: zeroHash,
        current_hash: firstHash,
        payload: {
          device_info: payload.metadata?.device ?? null,
          app_version: payload.metadata?.app_version ?? null,
          gps_accuracy: payload.gps_accuracy ?? null,
          media_type: payload.media_type,
          file_hash: payload.file_hash,
        },
      })
      .select()
      .single();

    if (custodyError || !custodyEntry) {
      // Hard error: rollback the evidence creation — custody chain integrity is mandatory
      await supabaseAdmin.from("evidence_items").delete().eq("id", evidence.id);
      return new Response(JSON.stringify({
        error: "Failed to create custody log entry — evidence registration rolled back",
        detail: custodyError?.message ?? "unknown custody error",
      }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({
        evidence: {
          id: evidence.id,
          case_id: evidence.case_id,
          media_type: evidence.media_type,
          file_hash: evidence.file_hash,
          captured_at: evidence.captured_at,
          is_sealed: evidence.is_sealed,
        },
        custody: custodyEntry ? {
          entry_id: custodyEntry.id,
          event_type: custodyEntry.event_type,
          current_hash: custodyEntry.current_hash,
        } : null,
      }),
      { status: 201, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: `Internal error: ${err.message}` }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
});