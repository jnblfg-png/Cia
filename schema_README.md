# ChainMark — Database Schema

## Overview

Field-evidence and reporting tool for private investigators. Evidence is cryptographically sealed at capture and stored with an append-only, hash-chained custody log.

## Tables

| Table | Description | Write Semantics |
|-------|-------------|----------------|
| `agencies` | Tenant root | Normal CRUD |
| `profiles` | Extends `auth.users` | Created on signup, updated by user |
| `cases` | Investigation cases | Normal CRUD (scoped to agency) |
| `evidence_items` | Captured media | **INSERT + SELECT only** (write-once) |
| `observations` | Investigator notes | Normal CRUD |
| `observation_evidence` | M2M bridge | Insert/delete only |
| `reports` | AI/manual reports | Normal CRUD |
| `custody_log` | Hash-chained audit trail | **INSERT + SELECT only** (append-only) |

## Enums
- `user_role`: owner, investigator
- `case_status`: active, closed, archived
- `report_status`: draft, finalized
- `evidence_event_type`: captured, accessed, transferred, exported, verified, finalized, derivative_created, supervisor_action

## Key Invariants

- **Evidence write-once**: RLS blocks UPDATE/DELETE on `evidence_items`
- **Custody log append-only**: triggers + RLS block UPDATE/DELETE on `custody_log`
- **Tenant isolation**: All queries scoped to `agency_id` via `get_user_agency_id()` RLS helper
- **Hash chain**: Each custody_log entry has `previous_hash` → `current_hash` chain per evidence item

## Migrations

1. `00001_chainmark_schema.sql` — Full schema (enums, tables, RLS, triggers)
2. `00002_seed_test_data.sql` — Test data for development
3. `00003_schema_refinements_and_verify.sql` — Column additions + verify_custody_chain()