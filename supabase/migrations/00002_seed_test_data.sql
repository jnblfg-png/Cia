-- ChainMark: Seed Test Data
-- Migration 00002: Insert test agencies, profiles, cases, evidence, and custody log
INSERT INTO public.agencies (id, name, slug, subscription_tier, is_active, max_investigators)
VALUES
    ('a0000000-0000-0000-0000-000000000001', 'Alpha Investigations', 'alpha-inv', 'professional', true, 5),
    ('a0000000-0000-0000-0000-000000000002', 'Bravo Detective Agency', 'bravo-det', 'starter', true, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.cases (id, agency_id, title, case_number, description, status, jurisdiction, consent_obtained, created_by)
SELECT
    'c0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000001',
    'Smith Family Surveillance',
    'CA-2024-001',
    'Child custody evaluation — observe parenting behaviors over 30 days.',
    'active',
    'California, USA',
    true,
    id
FROM public.profiles
WHERE agency_id = 'a0000000-0000-0000-0000-000000000001' AND role = 'owner'
LIMIT 1;

INSERT INTO public.cases (id, agency_id, title, case_number, description, status, jurisdiction, consent_obtained, created_by)
SELECT
    'c0000000-0000-0000-0000-000000000002',
    'a0000000-0000-0000-0000-000000000001',
    'Warehouse Theft Investigation',
    'CA-2024-002',
    'Internal theft at Acme Corp warehouse — identify suspects.',
    'active',
    'Texas, USA',
    true,
    id
FROM public.profiles
WHERE agency_id = 'a0000000-0000-0000-0000-000000000001' AND role = 'owner'
LIMIT 1;

INSERT INTO public.evidence_items (id, agency_id, case_id, captured_by, media_type, file_path, file_hash, file_size, mime_type, gps_latitude, gps_longitude, captured_at, device_clock_time, is_sealed)
SELECT
    'e0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000001',
    'c0000000-0000-0000-0000-000000000001',
    id,
    'photo',
    'evidence/ca-2024-001/photo_001.jpeg',
    'abc123def456abc123def456abc123def456abc123def456abc123def456abc123de',
    4194304,
    'image/jpeg',
    34.0522,
    -118.2437,
    now() - interval '3 days',
    now() - interval '3 days' - interval '2 seconds',
    true
FROM public.profiles
WHERE agency_id = 'a0000000-0000-0000-0000-000000000001' AND role = 'investigator'
LIMIT 1;

INSERT INTO public.evidence_items (id, agency_id, case_id, captured_by, media_type, file_path, file_hash, file_size, mime_type, gps_latitude, gps_longitude, captured_at, device_clock_time, is_sealed)
SELECT
    'e0000000-0000-0000-0000-000000000002',
    'a0000000-0000-0000-0000-000000000001',
    'c0000000-0000-0000-0000-000000000001',
    id,
    'video',
    'evidence/ca-2024-001/video_001.mp4',
    'fed654fed654fed654fed654fed654fed654fed654fed654fed654fed654fed654fe',
    52428800,
    'video/mp4',
    34.0525,
    -118.2440,
    now() - interval '2 days',
    now() - interval '2 days' - interval '1 second',
    true
FROM public.profiles
WHERE agency_id = 'a0000000-0000-0000-0000-000000000001' AND role = 'investigator'
LIMIT 1;

INSERT INTO public.observations (id, agency_id, case_id, created_by, timestamp, description, gps_latitude, gps_longitude, observation_type)
SELECT
    'o0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000001',
    'c0000000-0000-0000-0000-000000000001',
    id,
    now() - interval '3 days',
    'Subject exited residence at 08:15 AM. Drove silver Toyota Camry (ABC-1234) west on Main St.',
    34.0522,
    -118.2437,
    'surveillance'
FROM public.profiles
WHERE agency_id = 'a0000000-0000-0000-0000-000000000001' AND role = 'investigator'
LIMIT 1;

INSERT INTO public.observations (id, agency_id, case_id, created_by, timestamp, description, gps_latitude, gps_longitude, observation_type)
SELECT
    'o0000000-0000-0000-0000-000000000002',
    'a0000000-0000-0000-0000-000000000001',
    'c0000000-0000-0000-0000-000000000001',
    id,
    now() - interval '2 days',
    'Subject met with unknown male at Starbucks, 123 Main St. Brief exchange of documents.',
    34.0530,
    -118.2445,
    'surveillance'
FROM public.profiles
WHERE agency_id = 'a0000000-0000-0000-0000-000000000001' AND role = 'investigator'
LIMIT 1;

INSERT INTO public.observation_evidence (observation_id, evidence_id, notes)
VALUES
    ('o0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'Photo of subject leaving residence'),
    ('o0000000-0000-0000-0000-000000000002', 'e0000000-0000-0000-0000-000000000002', 'Video of Starbucks meeting');

INSERT INTO public.custody_log (evidence_id, agency_id, event_type, performed_by, previous_hash, current_hash, payload)
SELECT
    'e0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000001',
    'captured',
    id,
    '0000000000000000000000000000000000000000000000000000000000000000',
    'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2',
    '{"device": "iPhone 15 Pro", "app_version": "1.0.0", "gps_accuracy": 5.0}'::jsonb
FROM public.profiles
WHERE agency_id = 'a0000000-0000-0000-0000-000000000001' AND role = 'investigator'
LIMIT 1;

INSERT INTO public.custody_log (evidence_id, agency_id, event_type, performed_by, previous_hash, current_hash, payload)
SELECT
    'e0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000001',
    'accessed',
    id,
    'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2',
    'b2c3d4e5f6a7b2c3d4e5f6a7b2c3d4e5f6a7b2c3d4e5f6a7b2c3d4e5f6a7b2c3',
    '{"reviewer": "Alice Johnson", "reason": "Case review"}'::jsonb
FROM public.profiles
WHERE agency_id = 'a0000000-0000-0000-0000-000000000001' AND role = 'owner'
LIMIT 1;

INSERT INTO public.reports (id, agency_id, case_id, created_by, title, content, status, ai_model, ai_prompt_version)
SELECT
    'r0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000001',
    'c0000000-0000-0000-0000-000000000001',
    id,
    'Smith Family Surveillance — Interim Report',
    '# Surveillance Report — Smith Family\n## Case CA-2024-001\n## Period: June 1–15, 2026\n\n## Observations\nSubject was observed on three separate occasions...',
    'draft',
    'claude-3-opus-20240229',
    '1.0.0'
FROM public.profiles
WHERE agency_id = 'a0000000-0000-0000-0000-000000000001' AND role = 'owner'
LIMIT 1;