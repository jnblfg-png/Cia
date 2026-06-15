import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

interface InviteUserPayload {
  email: string;
  agency_id: string;
  full_name?: string;
}

serve(async (req: Request) => {
  try {
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } }
    );

    // Get the requesting user from JWT
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(token);

    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Verify the requester is an owner of the agency
    const { data: requesterProfile } = await supabaseAdmin
      .from("profiles")
      .select("role, agency_id")
      .eq("id", user.id)
      .single();

    if (!requesterProfile || requesterProfile.role !== "owner") {
      return new Response(JSON.stringify({ error: "Only agency owners can invite users" }), {
        status: 403,
        headers: { "Content-Type": "application/json" },
      });
    }

    const payload: InviteUserPayload = await req.json();

    if (!payload.email || !payload.agency_id) {
      return new Response(
        JSON.stringify({ error: "email and agency_id are required" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Verify the agency exists
    const { data: agency, error: agencyError } = await supabaseAdmin
      .from("agencies")
      .select("id, name, max_investigators")
      .eq("id", payload.agency_id)
      .single();

    if (agencyError || !agency) {
      return new Response(JSON.stringify({ error: "Agency not found" }), {
        status: 404,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Check investigator limit
    const { count: currentCount } = await supabaseAdmin
      .from("profiles")
      .select("id", { count: "exact", head: true })
      .eq("agency_id", payload.agency_id)
      .eq("role", "investigator");

    if (currentCount && currentCount >= agency.max_investigators) {
      return new Response(
        JSON.stringify({ error: `Agency investigator limit (${agency.max_investigators}) reached` }),
        { status: 403, headers: { "Content-Type": "application/json" } }
      );
    }

    // Check if user already exists in the system
    const { data: existingUsers } = await supabaseAdmin.auth.admin.listUsers();
    const existingUser = existingUsers?.users?.find(u => u.email === payload.email);

    if (existingUser) {
      // User exists — check if they already belong to this agency
      const { data: existingProfile } = await supabaseAdmin
        .from("profiles")
        .select("id, agency_id")
        .eq("id", existingUser.id)
        .single();

      if (existingProfile?.agency_id === payload.agency_id) {
        return new Response(JSON.stringify({ error: "User already belongs to this agency" }), {
          status: 409,
          headers: { "Content-Type": "application/json" },
        });
      }

      // User exists in another agency — update profile to join this one
      const { data: profile, error: profileError } = await supabaseAdmin
        .from("profiles")
        .upsert({
          id: existingUser.id,
          agency_id: payload.agency_id,
          role: "investigator",
          full_name: payload.full_name ?? existingUser.email?.split("@")[0] ?? "New Investigator",
          is_active: true,
        })
        .select()
        .single();

      if (profileError) {
        return new Response(JSON.stringify({ error: `Failed to add user: ${profileError.message}` }), {
          status: 500,
          headers: { "Content-Type": "application/json" },
        });
      }

      // Update JWT claims
      await supabaseAdmin.auth.admin.updateUserById(existingUser.id, {
        app_metadata: { agency_id: payload.agency_id, role: "investigator" },
      });

      return new Response(
        JSON.stringify({
          message: "User added to agency",
          profile: { id: profile.id, role: profile.role, full_name: profile.full_name },
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    // User doesn't exist — send invite via Supabase Auth
    const { data: invite, error: inviteError } = await supabaseAdmin.auth.admin.inviteUserByEmail(
      payload.email,
      {
        data: {
          full_name: payload.full_name ?? payload.email.split("@")[0],
          agency_id: payload.agency_id,
          invited_by: user.id,
        },
      }
    );

    if (inviteError) {
      return new Response(JSON.stringify({ error: `Failed to send invite: ${inviteError.message}` }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Pre-create the profile so it's ready when the user accepts
    await supabaseAdmin.from("profiles").upsert({
      id: invite.user.id,
      agency_id: payload.agency_id,
      role: "investigator",
      full_name: payload.full_name ?? payload.email.split("@")[0],
      is_active: true,
    }).select().single();

    return new Response(
      JSON.stringify({
        message: "Invitation sent",
        email: payload.email,
        agency_id: payload.agency_id,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: `Internal error: ${err.message}` }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});