-- ChainMark: Complete Supabase Schema
-- Migration 00001: Base schema with enums, tables, FKs, RLS, and hash-chained custody log
--
-- Contents:
--   1. Custom enums
--   2. agencies (tenant root)
--   3. profiles (auth.users extension)
--   4. cases
--   5. evidence_items (write-once sealed evidence)
--   6. observations
--   7. observation_evidence (M2M bridge)
--   8. reports
--   9. custody_log (append-only, hash-chained)
--  10. Indexes
--  11. Append-only enforcement (triggers)
--  12. Row-Level Security policies
--  13. Auto-profile creation trigger (auth.users -> profiles)
--  14. Updated_at triggers

-- ============================================================
-- 1. CUSTOM ENUMS
-- ============================================================
CREATE TYPE public.user_role AS ENUM ('owner', 'investigator');

CREATE TYPE public.case_status AS ENUM ('active', 'closed', 'archived');

CREATE TYPE public.report_status AS ENUM ('draft', 'finalized');

CREATE TYPE public.evidence_event_type AS ENUM (
    'captured',
    'accessed',
    'transferred',
    'exported',
    'verified',
    'finalized'
);

-- ============================================================
-- 2. AGENCIES (tenant root)
-- ============================================================
CREATE TABLE public.agencies (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL,
    slug        TEXT UNIQUE NOT NULL,
    subscription_tier TEXT NOT NULL DEFAULT 'free'
                        CHECK (subscription_tier IN ('free', 'starter', 'professional', 'enterprise')),
    is_active   BOOLEAN NOT NULL DEFAULT true,
    max_investigators INTEGER NOT NULL DEFAULT 1,
    storage_bytes_limit BIGINT NOT NULL DEFAULT 1073741824, -- 1 GB free tier
    settings    JSONB DEFAULT '{}'::jsonb,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 3. PROFILES (extends auth.users)
-- ============================================================
CREATE TABLE public.profiles (
    id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    agency_id   UUID REFERENCES public.agencies(id) ON DELETE CASCADE,  -- Nullable until signup flow completes (Edge Function sets it)
    role        public.user_role NOT NULL DEFAULT 'investigator',
    full_name   TEXT NOT NULL,
    is_active   BOOLEAN NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 4. CASES
-- ============================================================
CREATE TABLE public.cases (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agency_id       UUID NOT NULL REFERENCES public.agencies(id) ON DELETE CASCADE,
    title           TEXT NOT NULL,
    case_number     TEXT,
    description     TEXT,
    status          public.case_status NOT NULL DEFAULT 'active',
    jurisdiction    TEXT,
    consent_obtained BOOLEAN NOT NULL DEFAULT false,
    created_by      UUID NOT NULL REFERENCES public.profiles(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 5. EVIDENCE ITEMS (write-once sealed evidence)
-- ============================================================
CREATE TABLE public.evidence_items (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agency_id           UUID NOT NULL REFERENCES public.agencies(id) ON DELETE CASCADE,
    case_id             UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
    captured_by         UUID NOT NULL REFERENCES public.profiles(id),
    media_type          TEXT NOT NULL CHECK (media_type IN ('photo', 'video', 'audio')),
    file_path           TEXT NOT NULL,
    file_hash           TEXT NOT NULL,                        -- SHA-256 of file content
    file_size           BIGINT,
    mime_type           TEXT,
    gps_latitude        DOUBLE PRECISION,
    gps_longitude       DOUBLE PRECISION,
    gps_accuracy        DOUBLE PRECISION,
    captured_at         TIMESTAMPTZ NOT NULL,                 -- Server/trusted timestamp
    device_clock_time   TIMESTAMPTZ,                          -- Device-reported time (cross-referenced with captured_at for drift detection)
    rfc3161_timestamp   TEXT,                                 -- RFC 3161 cryptographic timestamp token
    secure_enclave_signature TEXT,                             -- Secure Enclave attestation
    metadata            JSONB DEFAULT '{}'::jsonb,
    is_sealed           BOOLEAN NOT NULL DEFAULT true,        -- Write-once: evidence is sealed at capture
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 6. OBSERVATIONS
-- ============================================================
CREATE TABLE public.observations (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agency_id         UUID NOT NULL REFERENCES public.agencies(id) ON DELETE CASCADE,
    case_id           UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
    created_by        UUID NOT NULL REFERENCES public.profiles(id),
    timestamp         TIMESTAMPTZ NOT NULL,
    description       TEXT NOT NULL,
    gps_latitude      DOUBLE PRECISION,
    gps_longitude     DOUBLE PRECISION,
    observation_type  TEXT CHECK (observation_type IN ('surveillance', 'interview', 'site_visit', 'other')),
    metadata          JSONB DEFAULT '{}'::jsonb,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 7. OBSERVATION-EVIDENCE M2M
-- ============================================================
CREATE TABLE public.observation_evidence (
    observation_id UUID NOT NULL REFERENCES public.observations(id) ON DELETE CASCADE,
    evidence_id    UUID NOT NULL REFERENCES public.evidence_items(id) ON DELETE CASCADE,
    notes          TEXT,
    PRIMARY KEY (observation_id, evidence_id)
);

-- ============================================================
-- 8. REPORTS
-- ============================================================
CREATE TABLE public.reports (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agency_id       UUID NOT NULL REFERENCES public.agencies(id) ON DELETE CASCADE,
    case_id         UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
    created_by      UUID NOT NULL REFERENCES public.profiles(id),
    title           TEXT NOT NULL,
    content         TEXT,
    status          public.report_status NOT NULL DEFAULT 'draft',
    ai_model        TEXT,
    ai_prompt_version TEXT,
    finalized_at    TIMESTAMPTZ,
    finalized_by    UUID REFERENCES public.profiles(id),
    metadata        JSONB DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- 9. CUSTODY LOG (append-only, hash-chained)
-- ============================================================
CREATE TABLE public.custody_log (
    id              BIGSERIAL,
    evidence_id     UUID NOT NULL REFERENCES public.evidence_items(id) ON DELETE CASCADE,
    agency_id       UUID NOT NULL REFERENCES public.agencies(id) ON DELETE CASCADE,
    event_type      public.evidence_event_type NOT NULL,
    performed_by    UUID NOT NULL REFERENCES public.profiles(id),
    previous_hash   TEXT NOT NULL,
    current_hash    TEXT NOT NULL,
    payload         JSONB,
    timestamp       TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (evidence_id, id),

    CONSTRAINT custody_log_unique_hash UNIQUE (current_hash)
);

-- ============================================================
-- 10. INDEXES
-- ============================================================
CREATE INDEX idx_profiles_agency     ON public.profiles(agency_id);
CREATE INDEX idx_cases_agency        ON public.cases(agency_id);
CREATE INDEX idx_cases_status        ON public.cases(status);
CREATE INDEX idx_evidence_agency     ON public.evidence_items(agency_id);
CREATE INDEX idx_evidence_case       ON public.evidence_items(case_id);
CREATE INDEX idx_evidence_captured_by ON public.evidence_items(captured_by);
CREATE INDEX idx_observations_case   ON public.observations(case_id);
CREATE INDEX idx_observations_agency ON public.observations(agency_id);
CREATE INDEX idx_reports_case        ON public.reports(case_id);
CREATE INDEX idx_reports_agency      ON public.reports(agency_id);
CREATE INDEX idx_reports_status      ON public.reports(status);
CREATE INDEX idx_custody_log_evidence ON public.custody_log(evidence_id);
CREATE INDEX idx_custody_log_agency   ON public.custody_log(agency_id);
CREATE INDEX idx_custody_log_event    ON public.custody_log(event_type);

-- ============================================================
-- 11. APPEND-ONLY ENFORCEMENT FOR custody_log
-- ============================================================
CREATE OR REPLACE FUNCTION public.prevent_custody_log_update()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'custody_log is append-only: updates are forbidden';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_custody_log_prevent_update
    BEFORE UPDATE ON public.custody_log
    FOR EACH ROW
    EXECUTE FUNCTION public.prevent_custody_log_update();

CREATE OR REPLACE FUNCTION public.prevent_custody_log_delete()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'custody_log is append-only: deletes are forbidden';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_custody_log_prevent_delete
    BEFORE DELETE ON public.custody_log
    FOR EACH ROW
    EXECUTE FUNCTION public.prevent_custody_log_delete();

-- ============================================================
-- 12. ROW-LEVEL SECURITY
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_user_agency_id()
RETURNS UUID
LANGUAGE SQL
STABLE
SECURITY DEFINER
AS $$
    SELECT agency_id FROM public.profiles WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.user_belongs_to_agency(target_agency_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND agency_id = target_agency_id AND is_active = true
    );
$$;

ALTER TABLE public.agencies            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cases               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.evidence_items      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.observations        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.observation_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.custody_log         ENABLE ROW LEVEL SECURITY;

-- AGENCIES
CREATE POLICY agencies_select_own ON public.agencies
    FOR SELECT
    USING (id = public.get_user_agency_id());

CREATE POLICY agencies_select_auth ON public.agencies
    FOR SELECT
    TO authenticated
    USING (true);

-- PROFILES
CREATE POLICY profiles_select_agency ON public.profiles
    FOR SELECT
    USING (agency_id = public.get_user_agency_id());

CREATE POLICY profiles_update_own ON public.profiles
    FOR UPDATE
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

-- CASES
CREATE POLICY cases_select_agency ON public.cases
    FOR SELECT
    USING (agency_id = public.get_user_agency_id());

CREATE POLICY cases_insert_agency ON public.cases
    FOR INSERT
    WITH CHECK (agency_id = public.get_user_agency_id());

CREATE POLICY cases_update_agency ON public.cases
    FOR UPDATE
    USING (agency_id = public.get_user_agency_id())
    WITH CHECK (agency_id = public.get_user_agency_id());

CREATE POLICY cases_delete_agency ON public.cases
    FOR DELETE
    USING (agency_id = public.get_user_agency_id());

-- EVIDENCE ITEMS (write-once: only INSERT + SELECT)
CREATE POLICY evidence_select_agency ON public.evidence_items
    FOR SELECT
    USING (agency_id = public.get_user_agency_id());

CREATE POLICY evidence_insert_agency ON public.evidence_items
    FOR INSERT
    WITH CHECK (agency_id = public.get_user_agency_id());

CREATE POLICY evidence_block_update ON public.evidence_items
    FOR UPDATE
    USING (false);

CREATE POLICY evidence_block_delete ON public.evidence_items
    FOR DELETE
    USING (false);

-- OBSERVATIONS
CREATE POLICY observations_select_agency ON public.observations
    FOR SELECT
    USING (agency_id = public.get_user_agency_id());

CREATE POLICY observations_insert_agency ON public.observations
    FOR INSERT
    WITH CHECK (agency_id = public.get_user_agency_id());

CREATE POLICY observations_update_agency ON public.observations
    FOR UPDATE
    USING (agency_id = public.get_user_agency_id())
    WITH CHECK (agency_id = public.get_user_agency_id());

CREATE POLICY observations_delete_agency ON public.observations
    FOR DELETE
    USING (agency_id = public.get_user_agency_id());

-- OBSERVATION-EVIDENCE M2M
CREATE POLICY obs_evidence_select_agency ON public.observation_evidence
    FOR SELECT
    USING (
        EXISTS (SELECT 1 FROM public.evidence_items e WHERE e.id = evidence_id AND e.agency_id = public.get_user_agency_id())
        OR
        EXISTS (SELECT 1 FROM public.observations o WHERE o.id = observation_id AND o.agency_id = public.get_user_agency_id())
    );

CREATE POLICY obs_evidence_insert_agency ON public.observation_evidence
    FOR INSERT
    WITH CHECK (
        EXISTS (SELECT 1 FROM public.evidence_items e WHERE e.id = evidence_id AND e.agency_id = public.get_user_agency_id())
        AND
        EXISTS (SELECT 1 FROM public.observations o WHERE o.id = observation_id AND o.agency_id = public.get_user_agency_id())
    );

CREATE POLICY obs_evidence_delete_agency ON public.observation_evidence
    FOR DELETE
    USING (
        EXISTS (SELECT 1 FROM public.evidence_items e WHERE e.id = evidence_id AND e.agency_id = public.get_user_agency_id())
    );

-- REPORTS
CREATE POLICY reports_select_agency ON public.reports
    FOR SELECT
    USING (agency_id = public.get_user_agency_id());

CREATE POLICY reports_insert_agency ON public.reports
    FOR INSERT
    WITH CHECK (agency_id = public.get_user_agency_id());

CREATE POLICY reports_update_agency ON public.reports
    FOR UPDATE
    USING (agency_id = public.get_user_agency_id())
    WITH CHECK (agency_id = public.get_user_agency_id());

CREATE POLICY reports_delete_agency ON public.reports
    FOR DELETE
    USING (agency_id = public.get_user_agency_id());

-- CUSTODY LOG (append-only: only INSERT + SELECT)
CREATE POLICY custody_log_select_agency ON public.custody_log
    FOR SELECT
    USING (agency_id = public.get_user_agency_id());

CREATE POLICY custody_log_insert_agency ON public.custody_log
    FOR INSERT
    WITH CHECK (agency_id = public.get_user_agency_id());

CREATE POLICY custody_log_block_update ON public.custody_log
    FOR UPDATE
    USING (false);

CREATE POLICY custody_log_block_delete ON public.custody_log
    FOR DELETE
    USING (false);

-- ============================================================
-- 13. AUTO-PROFILE CREATION ON SIGNUP
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_profile_for_user(
    p_user_id        UUID,
    p_agency_id      UUID,
    p_role           public.user_role,
    p_full_name      TEXT
)
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_profile public.profiles;
BEGIN
    INSERT INTO public.profiles (id, agency_id, role, full_name)
    VALUES (p_user_id, p_agency_id, p_role, p_full_name)
    RETURNING * INTO v_profile;
    RETURN v_profile;
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user_auto()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name)
    VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data ->> 'full_name', 'Unnamed User'))
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user_auto();

-- ============================================================
-- 14. UPDATED_AT TRIGGERS
-- ============================================================
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_agencies_updated_at
    BEFORE UPDATE ON public.agencies
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_cases_updated_at
    BEFORE UPDATE ON public.cases
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_observations_updated_at
    BEFORE UPDATE ON public.observations
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_reports_updated_at
    BEFORE UPDATE ON public.reports
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();