import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

interface GenerateReportPayload {
  case_id: string;
  title?: string;
}

const SYSTEM_PROMPT = `You are ChainMark's report generator for private investigation case files.

Your ONLY job: produce a factual, structured surveillance report from the evidence and observations provided.

STRICT RULES - NEVER VIOLATE:
1. NEVER invent facts, names, dates, locations, or events not present in the evidence data.
2. NEVER make assumptions about what happened.
3. If the evidence is insufficient for a claim, state "No evidence available" — do not speculate.
4. Every statement in the report must be traceable to a specific observation or evidence item ID.
5. NEVER add opinions, inferences, or conclusions. Report only what was observed and captured.
6. If video/photo evidence is referenced, cite the evidence ID.
7. Use present tense for general observations, past tense for specific events.

Output format — valid JSON only, no markdown fences:

{
  "title": "Surveillance Report Title",
  "case_id": "uuid",
  "period": { "from": "ISO8601", "to": "ISO8601" },
  "summary": "Brief factual summary of what was observed (1-3 sentences, no speculation)",
  "observations": [
    {
      "observation_id": "uuid",
      "timestamp": "ISO8601",
      "description": "Factual description of what was observed",
      "location": { "latitude": null, "longitude": null },
      "evidence_ids": ["uuid1", "uuid2"]
    }
  ],
  "evidence_catalog": [
    {
      "evidence_id": "uuid",
      "media_type": "photo|video|audio",
      "captured_at": "ISO8601",
      "file_hash": "sha256-hex",
      "gps": { "latitude": null, "longitude": null }
    }
  ],
  "disclaimer": "This report was automatically generated from sealed evidence. All facts are derived from captured observations and evidence items. No external facts or inferences have been added."
}`;

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

    const payload: GenerateReportPayload = await req.json();

    if (!payload.case_id) {
      return new Response(JSON.stringify({ error: "case_id is required" }), {
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

    // Verify case belongs to user's agency
    const { data: caseData, error: caseError } = await supabaseAdmin
      .from("cases")
      .select("id, agency_id, title, case_number, description, jurisdiction")
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

    // Fetch observations for this case
    const { data: observations, error: obsError } = await supabaseAdmin
      .from("observations")
      .select("id, timestamp, description, gps_latitude, gps_longitude, observation_type, created_at")
      .eq("case_id", payload.case_id)
      .eq("agency_id", profile.agency_id)
      .order("timestamp", { ascending: true });

    if (obsError) {
      return new Response(JSON.stringify({ error: "Failed to fetch observations" }), {
        status: 500, headers: { "Content-Type": "application/json" },
      });
    }

    // Fetch evidence for this case
    const { data: evidence, error: evError } = await supabaseAdmin
      .from("evidence_items")
      .select("id, media_type, file_hash, captured_at, gps_latitude, gps_longitude, metadata")
      .eq("case_id", payload.case_id)
      .eq("agency_id", profile.agency_id)
      .order("captured_at", { ascending: true });

    if (evError) {
      return new Response(JSON.stringify({ error: "Failed to fetch evidence" }), {
        status: 500, headers: { "Content-Type": "application/json" },
      });
    }

    // Get observation-evidence links
    const obsIds = (observations || []).map(o => o.id);
    const evIds = (evidence || []).map(e => e.id);

    let obsEvidenceLinks: Array<{ observation_id: string; evidence_id: string }> = [];
    if (obsIds.length > 0 && evIds.length > 0) {
      const { data: links } = await supabaseAdmin
        .from("observation_evidence")
        .select("observation_id, evidence_id")
        .in("observation_id", obsIds);
      obsEvidenceLinks = links || [];
    }

    // Calculate period
    let fromDate: string | null = null;
    let toDate: string | null = null;
    if (observations && observations.length > 0) {
      fromDate = observations[0].timestamp;
      toDate = observations[observations.length - 1].timestamp;
    } else if (evidence && evidence.length > 0) {
      fromDate = evidence[0].captured_at;
      toDate = evidence[evidence.length - 1].captured_at;
    }

    // Build evidence-by-observation mapping
    const evByObs: Record<string, string[]> = {};
    for (const link of obsEvidenceLinks) {
      if (!evByObs[link.observation_id]) evByObs[link.observation_id] = [];
      evByObs[link.observation_id].push(link.evidence_id);
    }

    // Build the prompt with actual data
    const evidenceBlock = (evidence || []).map(e =>
      `- Evidence ID: ${e.id} (${e.media_type})\n  File hash: ${e.file_hash}\n  Captured: ${e.captured_at}\n  GPS: ${e.gps_latitude ?? "N/A"}, ${e.gps_longitude ?? "N/A"}`
    ).join("\n");

    const observationsBlock = (observations || []).map(o =>
      `- Observation ID: ${o.id}\n  Time: ${o.timestamp}\n  Type: ${o.observation_type ?? "N/A"}\n  Description: ${o.description}\n  GPS: ${o.gps_latitude ?? "N/A"}, ${o.gps_longitude ?? "N/A"}\n  Linked Evidence: ${(evByObs[o.id] || []).join(", ") || "None"}`
    ).join("\n\n");

    const userMessage = `Generate a surveillance report for case "${caseData.title}" (${caseData.case_number ?? "No case number"}).\n\nJurisdiction: ${caseData.jurisdiction ?? "Not specified"}\n\nOBSERVATIONS:\n${observationsBlock}\n\nEVIDENCE:\n${evidenceBlock}\n\nReport title: ${payload.title ?? `Surveillance Report: ${caseData.title}`}`;

    // Call Claude API
    const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
    if (!ANTHROPIC_API_KEY) {
      return new Response(JSON.stringify({ error: "ANTHROPIC_API_KEY not configured" }), {
        status: 500, headers: { "Content-Type": "application/json" },
      });
    }

    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-3-haiku-20240307",
        max_tokens: 4000,
        system: SYSTEM_PROMPT,
        messages: [{ role: "user", content: userMessage }],
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error("Claude API error:", response.status, errorText);
      return new Response(JSON.stringify({
        error: "AI generation failed",
        detail: `Claude API returned ${response.status}`
      }), { status: 502, headers: { "Content-Type": "application/json" } });
    }

    const claudeData = await response.json();
    const reportContent = claudeData.content?.[0]?.text ?? "";

    // Try to parse as JSON, fall back to raw text
    let reportJson: Record<string, unknown>;
    try {
      reportJson = JSON.parse(reportContent);
    } catch {
      reportJson = { raw_content: reportContent };
    }

    // Create the report row
    const { data: report, error: reportError } = await supabaseAdmin
      .from("reports")
      .insert({
        agency_id: profile.agency_id,
        case_id: payload.case_id,
        created_by: user.id,
        title: payload.title ?? `Surveillance Report: ${caseData.title}`,
        content: reportContent,
        status: "draft",
        ai_model: "claude-3-haiku-20240307",
        ai_prompt_version: "1.0.0",
      })
      .select()
      .single();

    if (reportError) {
      return new Response(JSON.stringify({
        error: "Failed to save report",
        detail: reportError.message,
        generated_content: reportContent,
      }), { status: 500, headers: { "Content-Type": "application/json" } });
    }

    return new Response(
      JSON.stringify({
        report: {
          id: report.id,
          title: report.title,
          status: report.status,
          case_id: report.case_id,
          created_at: report.created_at,
          ai_model: report.ai_model,
        },
        content: reportJson,
        evidence_count: (evidence || []).length,
        observation_count: (observations || []).length,
      }),
      { status: 201, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: `Internal error: ${err.message}` }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
});