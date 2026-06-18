-- Bootstrap: recreate the parts of the Supabase platform that ChainMark migrations
-- depend on, so migrations 00001-00004 apply unchanged against vanilla Postgres 15.
--
-- Supabase provides: pgcrypto (digest), the auth schema, auth.users, auth.uid(),
-- and the roles anon / authenticated / service_role. We recreate equivalents.

-- 1. pgcrypto for digest()/sha256 used by custody hashing
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2. Roles that RLS policies / GRANTs reference
DO $$ BEGIN CREATE ROLE anon NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE authenticated NOLOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE ROLE service_role NOLOGIN BYPASSRLS; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 3. auth schema + minimal auth.users (mirrors Supabase GoTrue's table shape we use)
CREATE SCHEMA IF NOT EXISTS auth;

CREATE TABLE IF NOT EXISTS auth.users (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email                TEXT UNIQUE,
    raw_user_meta_data   JSONB DEFAULT '{}'::jsonb,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. auth.uid(): Supabase reads the JWT 'sub' claim. We simulate the "currently
--    logged-in user" via a session GUC (request.jwt.claim.sub) so tests can switch
--    identity with: SET LOCAL request.jwt.claim.sub = '<user-uuid>';
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

-- Helper used by tests to "log in" as a user under the authenticated role + RLS.
-- Usage: SELECT test.login('<uuid>');  then run queries; RESET ROLE to go back.
CREATE SCHEMA IF NOT EXISTS test;
CREATE OR REPLACE FUNCTION test.login(p_uid UUID)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM set_config('request.jwt.claim.sub', p_uid::text, false);
    EXECUTE 'SET ROLE authenticated';
END;
$$;
