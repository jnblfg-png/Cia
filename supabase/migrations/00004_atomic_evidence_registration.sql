-- ChainMark: Atomic evidence registration with custody genesis
-- Migration 00004: Adds a stored procedure that inserts evidence and first custody_log
-- entry in a single database transaction (all-or-nothing).

-- register_evidence_atomic(
--   p_agency_id, p_case_id, p_captured_by, p_media_type, p_file_path, p_file_hash,
--   p_file_size, p_mime_type, p_gps_latitude, p_gps_longitude, p_gps_accuracy,
--   p_gps_source, p_captured_at, p_device_clock_time, p_rfc3161_timestamp,
--   p_secure_enclave_signature, p_metadata
-- )
-- Returns JSONB with evidence and custody_log entries on success.
-- Rolls back the entire transaction if either insert fails.

CREATE OR REPLACE FUNCTION public.register_evidence_atomic(
    p_agency_id              UUID,
    p_case_id                UUID,
    p_captured_by            UUID,
    p_media_type             TEXT,
    p_file_path              TEXT,
    p_file_hash              TEXT,
    p_file_size              BIGINT DEFAULT NULL,
    p_mime_type              TEXT DEFAULT NULL,
    p_gps_latitude           DOUBLE PRECISION DEFAULT NULL,
    p_gps_longitude          DOUBLE PRECISION DEFAULT NULL,
    p_gps_accuracy           DOUBLE PRECISION DEFAULT NULL,
    p_gps_source             TEXT DEFAULT NULL,
    p_captured_at            TIMESTAMPTZ,
    p_device_clock_time      TIMESTAMPTZ DEFAULT NULL,
    p_rfc3161_timestamp      TEXT DEFAULT NULL,
    p_secure_enclave_signature TEXT DEFAULT NULL,
    p_metadata               JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_evidence    public.evidence_items;
    v_custody     public.custody_log;
    v_zero_hash   CONSTANT TEXT := '0000000000000000000000000000000000000000000000000000000000000000';
    v_current_hash TEXT;
BEGIN
    -- 1. Insert the evidence item
    INSERT INTO public.evidence_items (
        agency_id, case_id, captured_by, media_type, file_path, file_hash,
        file_size, mime_type, gps_latitude, gps_longitude, gps_accuracy,
        gps_source, captured_at, device_clock_time, rfc3161_timestamp,
        secure_enclave_signature, metadata, is_sealed
    ) VALUES (
        p_agency_id, p_case_id, p_captured_by, p_media_type, p_file_path, p_file_hash,
        p_file_size, p_mime_type, p_gps_latitude, p_gps_longitude, p_gps_accuracy,
        p_gps_source, p_captured_at, p_device_clock_time, p_rfc3161_timestamp,
        p_secure_enclave_signature, p_metadata, true
    )
    RETURNING * INTO v_evidence;

    -- 2. Compute the first custody hash from evidence data
    v_current_hash := encode(
        digest(
            v_zero_hash || 'captured' || p_captured_by::TEXT || p_captured_at::TEXT || p_file_hash,
            'sha256'
        ),
        'hex'
    );

    -- 3. Insert the first custody log entry
    INSERT INTO public.custody_log (
        evidence_id, agency_id, event_type, performed_by,
        previous_hash, current_hash, payload
    ) VALUES (
        v_evidence.id, p_agency_id, 'captured', p_captured_by,
        v_zero_hash, v_current_hash,
        jsonb_build_object(
            'media_type', p_media_type,
            'file_hash', p_file_hash,
            'gps_accuracy', p_gps_accuracy,
            'app_version', p_metadata -> 'app_version'
        )
    )
    RETURNING * INTO v_custody;

    -- 4. Return both results (transaction auto-commits if we reach here)
    RETURN jsonb_build_object(
        'evidence', jsonb_build_object(
            'id', v_evidence.id,
            'case_id', v_evidence.case_id,
            'media_type', v_evidence.media_type,
            'file_hash', v_evidence.file_hash,
            'captured_at', v_evidence.captured_at,
            'is_sealed', v_evidence.is_sealed
        ),
        'custody', jsonb_build_object(
            'entry_id', v_custody.id,
            'event_type', v_custody.event_type,
            'current_hash', v_custody.current_hash
        )
    );
END;
$$;

-- Grant execute to authenticated users and service_role
GRANT EXECUTE ON FUNCTION public.register_evidence_atomic(
    UUID, UUID, UUID, TEXT, TEXT, TEXT,
    BIGINT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION,
    TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, JSONB
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.register_evidence_atomic(
    UUID, UUID, UUID, TEXT, TEXT, TEXT,
    BIGINT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION,
    TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, JSONB
) TO service_role;