import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

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

    // Insert evidence + custody_log atomically via stored procedure
    // This runs in a single DB transaction — all-or-nothing
    const { data: result, error: rpcError } = await supabaseAdmin.rpc(
      "register_evidence_atomic",
      {
        p_agency_id: profile.agency_id,
        p_case_id: payload.case_id,
        p_captured_by: user.id,
        p_media_type: payload.media_type,
        p_file_path: payload.file_path,
        p_file_hash: payload.file_hash,
        p_file_size: payload.file_size ?? null,
        p_mime_type: payload.mime_type ?? null,
        p_gps_latitude: payload.gps_latitude ?? null,
        p_gps_longitude: payload.gps_longitude ?? null,
        p_gps_accuracy: payload.gps_accuracy ?? null,
        p_gps_source: payload.gps_source ?? null,
        p_captured_at: payload.captured_at,
        p_device_clock_time: payload.device_clock_time ?? null,
        p_rfc3161_timestamp: payload.rfc3161_timestamp ?? null,
        p_secure_enclave_signature: payload.secure_enclave_signature ?? null,
        p_metadata: payload.metadata ?? {},
      }
    );

    if (rpcError || !result) {
      return new Response(JSON.stringify({
        error: "Failed to register evidence atomically",
        detail: rpcError?.message ?? "unknown error",
      }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({
        evidence: result.evidence,
        custody: result.custody,
      }),
      { status: 201, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: `Internal error: ${err.message}` }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
});