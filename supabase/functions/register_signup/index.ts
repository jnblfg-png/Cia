import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

interface RegisterSignupPayload {
  full_name: string;
  agency_name: string;
}

serve(async (req: Request) => {
  try {
    // Create Supabase client with service_role key (bypasses RLS)
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } }
    );

    // Get the authenticated user from the JWT
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(token);

    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const payload: RegisterSignupPayload = await req.json();

    if (!payload.full_name || !payload.agency_name) {
      return new Response(
        JSON.stringify({ error: "full_name and agency_name are required" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Generate a unique slug from agency name
    const baseSlug = payload.agency_name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "");
    const slug = `${baseSlug}-${crypto.randomUUID().substring(0, 8)}`;

    // 1. Create the agency
    const { data: agency, error: agencyError } = await supabaseAdmin
      .from("agencies")
      .insert({
        name: payload.agency_name,
        slug,
        subscription_tier: "free",
        max_investigators: 1,
        storage_bytes_limit: 1073741824, // 1 GB
      })
      .select()
      .single();

    if (agencyError) {
      return new Response(JSON.stringify({ error: `Failed to create agency: ${agencyError.message}` }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    // 2. Create/update the user profile with agency_id and owner role
    const { data: profile, error: profileError } = await supabaseAdmin
      .from("profiles")
      .upsert({
        id: user.id,
        agency_id: agency.id,
        role: "owner",
        full_name: payload.full_name,
        is_active: true,
      })
      .select()
      .single();

    if (profileError) {
      // Rollback: delete the agency if profile creation fails
      await supabaseAdmin.from("agencies").delete().eq("id", agency.id);
      return new Response(JSON.stringify({ error: `Failed to create profile: ${profileError.message}` }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    // 3. Set agency_id in the user's app_metadata (JWT claims)
    const { error: metadataError } = await supabaseAdmin.auth.admin.updateUserById(
      user.id,
      { app_metadata: { agency_id: agency.id, role: "owner" } }
    );

    if (metadataError) {
      console.error("Failed to update user metadata:", metadataError);
      // Non-fatal — profile and agency exist, metadata can be refreshed later
    }

    return new Response(
      JSON.stringify({
        agency: { id: agency.id, name: agency.name, slug: agency.slug },
        profile: { id: profile.id, role: profile.role, full_name: profile.full_name },
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