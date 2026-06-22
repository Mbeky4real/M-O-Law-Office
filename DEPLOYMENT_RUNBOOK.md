# MOLMS Sprint 3A.1 — Database Deployment Runbook
## M&O Law Office — Internal Technical Document

---

## SITUATION

A live Supabase instance has not yet been provisioned with real credentials.
The `.env.local` file contains placeholder values:
- `VITE_SUPABASE_URL=https://placeholder.supabase.co`
- `VITE_SUPABASE_ANON_KEY=placeholder-key`

This runbook defines the exact steps to deploy and verify the MOLMS database.

---

## STEP 1 — Create Supabase Project

1. Go to https://supabase.com/dashboard
2. Click "New project"
3. Organisation: M&O Law Office
4. Project name: `molms-production`
5. Database password: generate a strong password and store securely
6. Region: choose nearest to Nairobi (Frankfurt: `eu-central-1`)
7. Pricing tier: **Pro** (required for PITR and connection pooling)
8. Click "Create new project"

---

## STEP 2 — Configure Environment Variables

Copy the project credentials from Settings > API:

```bash
# In /home/claude/molms/.env.local (development)
VITE_SUPABASE_URL=https://<your-project-ref>.supabase.co
VITE_SUPABASE_ANON_KEY=<your-anon-key>

# For verification script (use service role key — never commit this)
SUPABASE_URL=https://<your-project-ref>.supabase.co
SUPABASE_SERVICE_KEY=<your-service-role-key>
```

---

## STEP 3 — Apply Migrations

Apply migrations in order via Supabase Dashboard > SQL Editor.
Copy and paste each file content in sequence:

| Order | File | Description |
|---|---|---|
| 1 | supabase/migrations/20260601_001_extensions.sql | pgcrypto, pg_trgm |
| 2 | supabase/migrations/20260601_002_users.sql | users table |
| 3 | supabase/migrations/20260601_003_lookups.sql | matter_types, matter_statuses, etc. |
| 4 | supabase/migrations/20260601_004_matters.sql | matters core table |
| 5 | supabase/migrations/20260601_005_matter_extensions.sql | litigation/non-lit details, entities, notes, hearings, assignments |
| 6 | supabase/migrations/20260601_006_daily_reports.sql | daily_reports, report_items |
| 7 | supabase/migrations/20260601_007_diary.sql | diary_events, diary_event_members |
| 8 | supabase/migrations/20260601_008_documents.sql | documents, versions, tags |
| 9 | supabase/migrations/20260601_009_intercom.sql | threads, messages |
| 10 | supabase/migrations/20260601_010_notifications.sql | notifications |
| 11 | supabase/migrations/20260601_011_activity_feed.sql | activity_feed |
| 12 | supabase/migrations/20260601_012_audit_logs.sql | audit_logs (partitioned) |
| 13 | supabase/migrations/20260601_013_settings.sql | system_settings, templates, backups |
| 14 | **supabase/migrations/20260601_015_functions.sql** | ⭐ get_user_role(), generate_matter_reference() |
| 15 | **supabase/migrations/20260602_016_search_vectors.sql** | ⭐ search_vector triggers |
| 16 | **supabase/migrations/20260603_017_audit_triggers.sql** | ⭐ fn_audit_trigger on all tables |
| 17 | **supabase/migrations/20260604_018_activity_triggers.sql** | ⭐ fn_activity_trigger on matters/notes/hearings |
| 18 | **supabase/migrations/20260605_019_notification_triggers.sql** | ⭐ fn_notify_matter_assignment |
| 19 | **supabase/migrations/20260606_020_rls_policies.sql** | ⭐ ALL RLS policies |
| 20 | supabase/migrations/20260601_021_seed.sql | Seed data (matter types, statuses, categories) |

⭐ = Generated in Sprint 3A.1. Apply these after the core schema migrations.

---

## STEP 4 — Run Verification

```bash
# From the molms project root
SUPABASE_URL=https://<ref>.supabase.co \
SUPABASE_SERVICE_KEY=<service-role-key> \
node verify-database.cjs
```

Expected output when fully deployed:
```
╔════════════════════════════════════════════════════╗
║  MOLMS Sprint 3A.1 — Database Verification        ║
╚════════════════════════════════════════════════════╝

📋  TABLES
  ✓  matters                                              exists and accessible
  ✓  matter_types                                        exists and accessible
  ...

📋  SEED DATA
  ✓  matter_types: litigation                            present
  ✓  matter_types: non_litigation                        present
  ✓  matter_statuses: open                               present
  ...

📋  LIVE TESTS
  ✓  Test INSERT matter                                  CL-2026-001 created
  ✓  audit_logs trigger fires on INSERT                  RECORD_CREATED: CL-2026-001: MOLMS Verification...
  ✓  activity_feed trigger fires on INSERT               MATTER_CREATED: Kamau created matter CL-2026-001
  ✓  audit_logs trigger on UPDATE                        RECORD_UPDATED captured
  ✓  audit_logs trigger on ARCHIVE                       RECORD_ARCHIVED captured

─────────────────────────────────────────────────────
  Results: 40 passed, 0 failed

  ✅  READY FOR SPRINT 3B
```

---

## STEP 5 — Create First Administrator Account

1. Supabase Dashboard > Authentication > Users > "Add user"
2. Email: admin@mando.law  Password: (strong password)
3. Confirm the user ID (UUID)
4. In SQL Editor, insert the users table row:

```sql
INSERT INTO public.users (id, name, email, role, position, status)
VALUES (
  '<auth-user-uuid>',
  'System Administrator',
  'admin@mando.law',
  'administrator',
  'Administrator',
  'active'
);
```

5. Sign in to MOLMS at the application URL with these credentials.

---

## STEP 6 — Sprint 3B Approval

After the verification script reports 0 failures:
- Sprint 3B may begin
- Matter Core implementation is unblocked
