\set ON_ERROR_STOP off
\echo '===== E2E TEST: ChainMark backend ====='

-- Two agencies, two users (owner A, owner B), simulating signup edge fn results.
INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
 ('11111111-0000-0000-0000-000000000001','ownerA@a.com','{"full_name":"Owner A"}'),
 ('22222222-0000-0000-0000-000000000002','ownerB@b.com','{"full_name":"Owner B"}');
-- trigger auto-creates profiles; signup edge fn sets agency + role:
INSERT INTO public.agencies (id,name,slug) VALUES
 ('aaaa1111-0000-0000-0000-000000000001','Agency A','agency-a'),
 ('bbbb2222-0000-0000-0000-000000000002','Agency B','agency-b');
UPDATE public.profiles SET agency_id='aaaa1111-0000-0000-0000-000000000001', role='owner' WHERE id='11111111-0000-0000-0000-000000000001';
UPDATE public.profiles SET agency_id='bbbb2222-0000-0000-0000-000000000002', role='owner' WHERE id='22222222-0000-0000-0000-000000000002';

-- invite/join: second investigator in Agency A
INSERT INTO auth.users (id,email,raw_user_meta_data) VALUES ('11111111-0000-0000-0000-00000000000a','invA@a.com','{"full_name":"Inv A2"}');
UPDATE public.profiles SET agency_id='aaaa1111-0000-0000-0000-000000000001', role='investigator' WHERE id='11111111-0000-0000-0000-00000000000a';

-- Case for agency A (created by owner A)
INSERT INTO public.cases (id,agency_id,title,case_number,jurisdiction,created_by)
 VALUES ('ca5e1111-0000-0000-0000-000000000001','aaaa1111-0000-0000-0000-000000000001','Test Surveillance','TST-1','California, USA','11111111-0000-0000-0000-000000000001');

\echo '--- TEST 1: register_evidence_atomic (A4 atomic evidence+custody) ---'
SELECT public.register_evidence_atomic(
  'aaaa1111-0000-0000-0000-000000000001','ca5e1111-0000-0000-0000-000000000001',
  '11111111-0000-0000-0000-000000000001','photo','/ev/p1.jpg',
  'a'||repeat('b',63), now(),
  204800,'image/jpeg',34.05,-118.24,5.0,'device_gps', now(), NULL, NULL,
  '{"app_version":"1.0.0"}'::jsonb
) AS register_result;

\echo '--- TEST 2: custody_log row exists, hash-chained (genesis previous_hash = zeros) ---'
SELECT event_type, previous_hash='0000000000000000000000000000000000000000000000000000000000000000' AS genesis_zero_prev,
       length(current_hash)=64 AS hash_64 FROM public.custody_log;

\echo '--- TEST 3: verify_custody_chain reports valid ---'
SELECT public.verify_custody_chain(id)->>'status' AS chain_status FROM public.evidence_items LIMIT 1;

\echo '--- TEST 4: evidence is write-once (UPDATE blocked by RLS for agency user) ---'
SELECT test.login('11111111-0000-0000-0000-000000000001');
UPDATE public.evidence_items SET file_hash='hacked' WHERE agency_id='aaaa1111-0000-0000-0000-000000000001';
\echo '(0 rows updated above = write-once enforced)'
RESET ROLE;

\echo '--- TEST 5: custody_log append-only — UPDATE must RAISE ---'
UPDATE public.custody_log SET current_hash='tamper';
\echo '--- TEST 5b: custody_log append-only — DELETE must RAISE ---'
DELETE FROM public.custody_log;

\echo '--- TEST 6: RLS tenant isolation — Owner B cannot see Agency A evidence/cases ---'
SELECT test.login('22222222-0000-0000-0000-000000000002');
SELECT count(*) AS b_sees_a_evidence FROM public.evidence_items;
SELECT count(*) AS b_sees_a_cases FROM public.cases;
SELECT count(*) AS b_sees_a_custody FROM public.custody_log;
RESET ROLE;

\echo '--- TEST 7: RLS — Owner A CAN see own agency evidence ---'
SELECT test.login('11111111-0000-0000-0000-000000000001');
SELECT count(*) AS a_sees_own_evidence FROM public.evidence_items;
RESET ROLE;

\echo '--- TEST 8: report draft -> finalize state transition (simulating edge fns) ---'
INSERT INTO public.reports (id,agency_id,case_id,created_by,title,content,status,ai_model,ai_prompt_version)
 VALUES ('5eb05111-0000-0000-0000-000000000001','aaaa1111-0000-0000-0000-000000000001','ca5e1111-0000-0000-0000-000000000001','11111111-0000-0000-0000-000000000001','Draft','{}','draft','claude-3-haiku-20240307','1.0.0');
UPDATE public.reports SET status='finalized', finalized_at=now(), finalized_by='11111111-0000-0000-0000-000000000001' WHERE id='5eb05111-0000-0000-0000-000000000001';
SELECT status, finalized_by IS NOT NULL AS has_finalizer FROM public.reports;
\echo '===== E2E COMPLETE ====='
