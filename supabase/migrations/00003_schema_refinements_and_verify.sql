-- ChainMark: Schema refinements + hash-chain verification
-- Migration 00003: Add columns, extend enum, build verify_custody_chain()

-- ============================================================
-- 1. EXTEND evidence_event_type ENUM
-- ============================================================
DO $$
BEGIN
    ALTER TYPE public.evidence_event_type ADD VALUE 'derivative_created';
EXCEPTION
    WHEN duplicate_object THEN NULL;
END;
$$;

DO $$
BEGIN
    ALTER TYPE public.evidence_event_type ADD VALUE 'supervisor_action';
EXCEPTION
    WHEN duplicate_object THEN NULL;
END;
$$;

-- ============================================================
-- 2. ADD source_audio_path TO observations
-- ============================================================
ALTER TABLE public.observations
    ADD COLUMN IF NOT EXISTS source_audio_path TEXT;

COMMENT ON COLUMN public.observations.source_audio_path
    IS 'Path to the original audio recording of this observation (voice notes, dictation)';

-- ============================================================
-- 3. ADD injury_type TO cases
-- ============================================================
ALTER TABLE public.cases
    ADD COLUMN IF NOT EXISTS injury_type TEXT;

COMMENT ON COLUMN public.cases.injury_type
    IS 'Type of injury claimed/investigated (e.g., soft_tissue, fracture, psychological). Null for non-injury cases.';

-- ============================================================
-- 4. ADD gps_source TO evidence_items
-- ============================================================
ALTER TABLE public.evidence_items
    ADD COLUMN IF NOT EXISTS gps_source TEXT;

COMMENT ON COLUMN public.evidence_items.gps_source
    IS 'Origin of GPS coordinates: device_gps (iPhone GPS), manual_entry (user-typed), geotag (embedded in file metadata)';

-- ============================================================
-- 5. HASH-CHAIN VERIFICATION FUNCTION
-- ============================================================
CREATE OR REPLACE FUNCTION public.verify_custody_chain(p_evidence_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
AS $$
DECLARE
    v_rec              RECORD;
    v_prev_rec         RECORD;
    v_first            BOOLEAN := true;
    v_entries_checked  INT := 0;
    v_breach_detail    TEXT := NULL;
    v_first_hash       TEXT := NULL;
    v_last_hash        TEXT := NULL;
    v_zero_hash        CONSTANT TEXT := '0000000000000000000000000000000000000000000000000000000000000000';
    v_result           JSONB;
BEGIN
    FOR v_rec IN
        SELECT id, evidence_id, event_type, previous_hash, current_hash, timestamp
        FROM public.custody_log
        WHERE evidence_id = p_evidence_id
        ORDER BY id ASC
    LOOP
        v_entries_checked := v_entries_checked + 1;

        IF v_first THEN
            v_first_hash := v_rec.current_hash;
            IF v_rec.previous_hash != v_zero_hash THEN
                v_breach_detail := 'First entry previous_hash is not the zero-hash: '
                    || 'expected 64 zeros, got ' || v_rec.previous_hash;
                EXIT;
            END IF;
            v_first := false;
        ELSE
            IF v_rec.previous_hash != v_prev_rec.current_hash THEN
                v_breach_detail := 'Hash chain broken at entry ' || v_rec.id::TEXT
                    || ': previous_hash (' || v_rec.previous_hash
                    || ') does not match prior entry current_hash (' || v_prev_rec.current_hash || ')';
                EXIT;
            END IF;
        END IF;

        v_prev_rec := v_rec;
    END LOOP;

    IF v_breach_detail IS NULL AND v_prev_rec IS NOT NULL THEN
        v_last_hash := v_prev_rec.current_hash;
    END IF;

    IF v_entries_checked = 0 THEN
        v_result := jsonb_build_object(
            'status', 'empty',
            'evidence_id', p_evidence_id,
            'entries_checked', 0,
            'detail', 'No custody log entries found for this evidence'
        );
    ELSIF v_breach_detail IS NOT NULL THEN
        v_result := jsonb_build_object(
            'status', 'breached',
            'evidence_id', p_evidence_id,
            'entries_checked', v_entries_checked,
            'breach_detail', v_breach_detail,
            'last_valid_hash', COALESCE(v_prev_rec.current_hash, NULL)
        );
    ELSE
        v_result := jsonb_build_object(
            'status', 'valid',
            'evidence_id', p_evidence_id,
            'entries_checked', v_entries_checked,
            'first_hash', v_first_hash,
            'last_hash', v_last_hash
        );
    END IF;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_custody_chain(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_custody_chain(UUID) TO service_role;

-- ============================================================
-- 6. UPDATE SEED DATA
-- ============================================================
UPDATE public.evidence_items
SET gps_source = 'device_gps'
WHERE agency_id = 'a0000000-0000-0000-0000-000000000001'
  AND gps_source IS NULL;