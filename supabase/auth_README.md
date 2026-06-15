# ChainMark — Auth Flow

## Overview

ChainMark uses Supabase Auth for user authentication. The auth flow has two paths:

### Path A: Signup (creates a new agency)
```
User signs up → on_auth_user_created trigger (placeholder profile)
              → register_signup Edge Function (creates agency, sets owner)
              → JWT claims updated with agency_id + role
```

### Path B: Invite (joins existing agency)
```
Owner calls invite_user → Edge Function sends auth invite
User accepts invite      → on_auth_user_created trigger (placeholder profile)
                         → Profile already has agency_id (pre-created by invite)
                         → JWT claims set via app_metadata
```

## Edge Functions

### `register_signup`
- **Location:** `supabase/functions/register_signup/index.ts`
- **Purpose:** Called after user signs up to bootstrap their agency
- **Payload:** `{ full_name: string, agency_name: string }`
- **Flow:**
  1. Verifies the JWT from auth header
  2. Generates a unique slug from agency_name + random suffix
  3. Creates a new row in `agencies` table
  4. Updates the user's profile (created by trigger) with agency_id + role=owner
  5. Sets `app_metadata.agency_id` and `app_metadata.role` in JWT claims
  6. Rolls back agency creation if profile write fails

### `invite_user`
- **Location:** `supabase/functions/invite_user/index.ts`
- **Purpose:** Allows an agency owner to invite new investigators
- **Payload:** `{ email: string, agency_id: string, full_name?: string }`
- **Flow:**
  1. Verifies the requester is an owner of the specified agency
  2. Checks agency investigator limit
  3. If user exists in auth system with another agency → updates their profile
  4. If user doesn't exist → creates auth invite + pre-creates profile
  5. Updates JWT claims for the invited user

### `get_profile`
- **Location:** `supabase/functions/get_profile/index.ts`
- **Purpose:** Returns the current user's profile + agency info (for iOS app)
- **Flow:**
  1. Verifies the JWT
  2. Queries `profiles` with a join to `agencies`
  3. Returns user info, profile (role, name), and agency details

## Database Triggers

### `on_auth_user_created`
- Created in migration 00001
- Fires AFTER INSERT on `auth.users`
- Creates a minimal placeholder profile with `full_name` from `raw_user_meta_data`
- The Edge Function `register_signup` later sets `agency_id` and `role`

## JWT Claims

Agency context is stored in Supabase JWT `app_metadata`:
```json
{
  "app_metadata": {
    "agency_id": "uuid-of-agency",
    "role": "owner" | "investigator",
    "provider": "email"
  }
}
```

The RLS helper function `get_user_agency_id()` reads from the `profiles` table
(not from JWT) to ensure consistency. JWT claims are a convenience for the
iOS app to read agency context without a DB query.

## RLS Integration

All tables have RLS policies scoped to `agency_id = get_user_agency_id()`.
The helper function looks up the user's profile row. This works because:
1. The `on_auth_user_created` trigger creates a profile row on signup
2. Edge Functions set the `agency_id` on the profile
3. RLS policies reference `auth.uid()` to find the user's row

## Deployment

```bash
# Deploy all functions
supabase functions deploy register_signup
supabase functions deploy invite_user
supabase functions deploy get_profile

# Set required secrets
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=<your-key>
```

## Testing

See `supabase/migrations/00002_seed_test_data.sql` for test data.
Use the Supabase Dashboard SQL Editor to test queries with real auth users.