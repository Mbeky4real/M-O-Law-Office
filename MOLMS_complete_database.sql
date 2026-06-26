-- ═══════════════════════════════════════════════════════════════
-- MOLMS — Complete Database Schema
-- M&O Law Office Management System
-- All 33 migrations combined in correct deployment order
-- 
-- HOW TO USE:
--   1. Go to Supabase Dashboard → SQL Editor
--   2. Paste this entire file
--   3. Click Run
--   4. Done — entire database is deployed
-- ═══════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 001_extensions_enums.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 001: Extensions & Custom Types
-- Project: M&O Law Office Management System
-- Platform: Supabase (PostgreSQL 15+)
-- ═══════════════════════════════════════════════════════════════

-- ─── Extensions ───────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";    -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "pg_trgm";     -- trigram indexes for ILIKE search
CREATE EXTENSION IF NOT EXISTS "unaccent";    -- accent-insensitive search

-- ─── Custom Types (Enums) ──────────────────────────────────────

-- User roles — fixed three-tier model
CREATE TYPE molms_role AS ENUM (
  'administrator',
  'partner',
  'member'
);

-- User / member account status
CREATE TYPE user_status AS ENUM (
  'active',
  'inactive'
);

-- Matter lifecycle statuses
CREATE TYPE matter_status AS ENUM (
  'open',
  'in_progress',
  'awaiting_action',
  'under_review',
  'completed',
  'closed'
);

-- Matter priority
CREATE TYPE matter_priority AS ENUM (
  'low',
  'normal',
  'high',
  'urgent'
);

-- Matter type discriminator
CREATE TYPE matter_type_code AS ENUM (
  'litigation',
  'non_litigation'
);

-- Entity types for matter_entities
CREATE TYPE entity_type AS ENUM (
  'plaintiff',
  'defendant',
  'opposing_counsel',
  'government_agency',
  'company',
  'law_firm',
  'witness',
  'other'
);

-- Note classification types
CREATE TYPE note_type AS ENUM (
  'general',
  'partner',
  'court_update',
  'internal'
);

-- Hearing / court appearance types
CREATE TYPE hearing_type AS ENUM (
  'mention',
  'hearing',
  'ruling',
  'directions',
  'other'
);

-- Daily report workflow statuses
CREATE TYPE report_status AS ENUM (
  'draft',
  'submitted',
  'returned',
  'reviewed'
);

-- Diary / calendar event types
CREATE TYPE event_type AS ENUM (
  'hearing',
  'deadline',
  'meeting',
  'reminder',
  'general'
);

-- InterCom thread types
CREATE TYPE thread_type AS ENUM (
  'announcement',
  'discussion',
  'notice'
);

-- Document category codes
CREATE TYPE doc_category_code AS ENUM (
  'pleadings',
  'contracts',
  'correspondence',
  'court_orders',
  'evidence',
  'conveyancing',
  'corporate',
  'statutory',
  'legal_opinions',
  'land_documents',
  'employment',
  'internal_memos',
  'miscellaneous'
);

-- Audit action types
CREATE TYPE audit_action AS ENUM (
  'RECORD_CREATED',
  'RECORD_UPDATED',
  'RECORD_ARCHIVED',
  'RECORD_RESTORED',
  'ROLE_CHANGED',
  'LOGIN_SUCCESS',
  'LOGIN_FAILED',
  'PERMISSION_CHANGED',
  'BACKUP_CREATED',
  'DOCUMENT_DOWNLOADED'
);

-- Activity feed event types
CREATE TYPE activity_event_type AS ENUM (
  'MATTER_CREATED',
  'MATTER_UPDATED',
  'MATTER_ASSIGNED',
  'MATTER_STATUS_CHANGED',
  'MATTER_ARCHIVED',
  'MATTER_RESTORED',
  'NOTE_ADDED',
  'HEARING_ADDED',
  'ENTITY_ADDED',
  'REPORT_SUBMITTED',
  'REPORT_REVIEWED',
  'DOCUMENT_UPLOADED',
  'DOCUMENT_VERSION_UPLOADED',
  'DIARY_EVENT_CREATED',
  'INTERCOM_ANNOUNCEMENT',
  'MEMBER_ADDED'
);

-- Backup operation statuses
CREATE TYPE backup_status AS ENUM (
  'pending',
  'completed',
  'failed'
);

COMMENT ON TYPE molms_role     IS 'Three-tier role model for MOLMS access control.';
COMMENT ON TYPE matter_status  IS 'Approved matter lifecycle workflow statuses.';
COMMENT ON TYPE matter_priority IS 'Matter urgency classification.';



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 002_users.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 002: Users Table
-- Maps 1:1 with Supabase Auth users (same UUID).
-- Profile data merged — no separate profile table.
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.users (
  id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  email           TEXT          NOT NULL UNIQUE,
  name            TEXT          NOT NULL,
  role            molms_role    NOT NULL DEFAULT 'member',
  position        TEXT,
  department      TEXT,
  phone           TEXT,
  avatar_url      TEXT,
  status          user_status   NOT NULL DEFAULT 'active',
  last_login_at   TIMESTAMPTZ,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
  created_by      UUID          REFERENCES public.users(id) ON DELETE RESTRICT,
  updated_by      UUID          REFERENCES public.users(id) ON DELETE RESTRICT,
  archived_at     TIMESTAMPTZ,
  archived_by     UUID          REFERENCES public.users(id) ON DELETE RESTRICT,
  archive_reason  TEXT,

  CONSTRAINT users_email_lowercase CHECK (email = lower(email))
);

-- ─── Indexes ───────────────────────────────────────────────────
CREATE UNIQUE INDEX idx_users_email        ON public.users(email);
CREATE        INDEX idx_users_role         ON public.users(role);
CREATE        INDEX idx_users_status       ON public.users(status);
CREATE        INDEX idx_users_role_status  ON public.users(role, status);

-- Trigram index for name search
CREATE INDEX idx_users_name_trgm ON public.users USING GIN (name gin_trgm_ops);

-- ─── Trigger: keep updated_at current ─────────────────────────
CREATE OR REPLACE FUNCTION public.fn_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

COMMENT ON TABLE public.users IS 
  'All MOLMS system members. Maps 1:1 with Supabase Auth user UUIDs. '
  'Profile data merged per Phase 3 amendment (no separate member_profiles table).';



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 003_matter_types_lookups.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 003: Matter Types & Status Lookup Tables
-- Seeded lookup data — administrator-managed.
-- ═══════════════════════════════════════════════════════════════

-- ─── Matter Types ──────────────────────────────────────────────
CREATE TABLE public.matter_types (
  id          UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
  type_code   matter_type_code  NOT NULL UNIQUE,
  label       TEXT              NOT NULL,
  description TEXT,
  is_active   BOOLEAN           NOT NULL DEFAULT TRUE,
  sort_order  INTEGER           NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ       NOT NULL DEFAULT now()
);

CREATE INDEX idx_matter_types_active ON public.matter_types(is_active);

COMMENT ON TABLE public.matter_types IS 
  'Discriminator table for matter type (litigation / non_litigation). '
  'Extensible for future matter categories without schema changes.';

-- ─── Matter Statuses ───────────────────────────────────────────
CREATE TABLE public.matter_statuses (
  id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  status_code matter_status NOT NULL UNIQUE,
  label       TEXT          NOT NULL,
  description TEXT,
  sort_order  INTEGER       NOT NULL DEFAULT 0,
  is_terminal BOOLEAN       NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX idx_matter_statuses_sort ON public.matter_statuses(sort_order);

COMMENT ON TABLE public.matter_statuses IS
  'Approved matter lifecycle statuses. is_terminal=TRUE prevents further '
  'edits without reopening. Ordered by sort_order for UI display.';

-- ─── Document Categories ───────────────────────────────────────
CREATE TABLE public.document_categories (
  id            UUID              PRIMARY KEY DEFAULT gen_random_uuid(),
  category_code doc_category_code NOT NULL UNIQUE,
  label         TEXT              NOT NULL,
  description   TEXT,
  is_active     BOOLEAN           NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ       NOT NULL DEFAULT now()
);

-- ─── Notification Triggers (lookup) ───────────────────────────
CREATE TABLE public.notification_triggers (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  trigger_code TEXT        NOT NULL UNIQUE,
  label        TEXT        NOT NULL,
  description  TEXT,
  module       TEXT        NOT NULL,
  is_active    BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_notification_triggers_active ON public.notification_triggers(is_active);

-- ─── System Settings ───────────────────────────────────────────
CREATE TABLE public.system_settings (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  key         TEXT        NOT NULL UNIQUE,
  value       TEXT        NOT NULL,
  description TEXT,
  updated_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_system_settings_key ON public.system_settings(key);

-- ─── Tags (shared across documents and matters) ────────────────
CREATE TABLE public.tags (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT        NOT NULL UNIQUE,
  created_by UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_tags_name ON public.tags(lower(name));



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 004_matters.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 004: Matters — Core Table
-- Central entity of the entire MOLMS system.
-- Unified architecture: all matter types share this table.
-- Discriminated by matter_type_id.
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.matters (
  id                     UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  reference_number       TEXT          NOT NULL UNIQUE,
  title                  TEXT          NOT NULL,
  description            TEXT,

  -- Type and status via FK to lookup tables
  matter_type_id         UUID          NOT NULL
    REFERENCES public.matter_types(id) ON DELETE RESTRICT,
  matter_status_id       UUID          NOT NULL
    REFERENCES public.matter_statuses(id) ON DELETE RESTRICT,

  priority               matter_priority NOT NULL DEFAULT 'normal',

  -- Assignment
  assigned_to            UUID
    REFERENCES public.users(id) ON DELETE RESTRICT,
  supervising_partner_id UUID          NOT NULL
    REFERENCES public.users(id) ON DELETE RESTRICT,

  -- Accountability
  created_by             UUID          NOT NULL
    REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at             TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_by             UUID          NOT NULL
    REFERENCES public.users(id) ON DELETE RESTRICT,
  updated_at             TIMESTAMPTZ   NOT NULL DEFAULT now(),

  -- Archive model (no hard delete)
  is_archived            BOOLEAN       NOT NULL DEFAULT FALSE,
  archived_by            UUID
    REFERENCES public.users(id) ON DELETE RESTRICT,
  archived_at            TIMESTAMPTZ,
  archive_reason         TEXT,

  -- Optimistic locking counter
  version                INTEGER       NOT NULL DEFAULT 1,

  -- Full-text search (populated by trigger)
  search_vector          TSVECTOR,

  -- Flexible extension field
  metadata               JSONB,

  -- Constraints
  CONSTRAINT matters_archive_consistency CHECK (
    (is_archived = FALSE AND archived_by IS NULL AND archived_at IS NULL)
    OR
    (is_archived = TRUE AND archived_by IS NOT NULL AND archived_at IS NOT NULL)
  ),
  CONSTRAINT matters_archive_reason_required CHECK (
    is_archived = FALSE OR archive_reason IS NOT NULL
  )
);

-- ─── Indexes ───────────────────────────────────────────────────

-- Primary filtering indexes
CREATE UNIQUE INDEX idx_matters_ref            ON public.matters(reference_number);
CREATE        INDEX idx_matters_type_arch      ON public.matters(matter_type_id, is_archived);
CREATE        INDEX idx_matters_status_arch    ON public.matters(matter_status_id, is_archived);
CREATE        INDEX idx_matters_assigned       ON public.matters(assigned_to, is_archived);
CREATE        INDEX idx_matters_partner        ON public.matters(supervising_partner_id);
CREATE        INDEX idx_matters_priority       ON public.matters(priority, is_archived);
CREATE        INDEX idx_matters_created_at     ON public.matters(created_at DESC);
CREATE        INDEX idx_matters_updated_at     ON public.matters(updated_at DESC);

-- Full-text search
CREATE INDEX idx_matters_search ON public.matters USING GIN(search_vector);

-- Dashboard aggregate index: type + status + archived in one scan
CREATE INDEX idx_matters_dashboard ON public.matters(matter_type_id, matter_status_id, is_archived);

-- ─── Updated_at trigger ─────────────────────────────────────────
CREATE TRIGGER trg_matters_updated_at
  BEFORE UPDATE ON public.matters
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

COMMENT ON TABLE public.matters IS
  'Unified matter table. Cause List and Non-Litigation matters share this table. '
  'Discriminated by matter_type_id FK. Extension details in '
  'matter_litigation_details and matter_non_lit_details.';



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 005_matter_litigation_details.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 005: Litigation Details
-- Extension table for Cause List matters.
-- One-to-one with matters WHERE type = litigation.
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.matter_litigation_details (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  matter_id         UUID        NOT NULL UNIQUE
    REFERENCES public.matters(id) ON DELETE RESTRICT,

  court_name        TEXT,
  case_number       TEXT,
  judge_name        TEXT,
  opposing_counsel  TEXT,
  filing_date       DATE,
  next_hearing_date DATE,

  created_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_mld_matter         ON public.matter_litigation_details(matter_id);
CREATE INDEX idx_mld_next_hearing   ON public.matter_litigation_details(next_hearing_date)
  WHERE next_hearing_date IS NOT NULL;

CREATE TRIGGER trg_mld_updated_at
  BEFORE UPDATE ON public.matter_litigation_details
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

COMMENT ON TABLE public.matter_litigation_details IS
  'Litigation-specific extension table. One-to-one with matters. '
  'Only populated for matters where matter_types.type_code = litigation.';



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 006_matter_non_lit_details.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 006: Non-Litigation Details
-- Extension table for Non-Litigation matters.
-- transaction_value column intentionally omitted per Phase 3 amendment:
-- MOLMS contains no financial functionality.
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.matter_non_lit_details (
  id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  matter_id          UUID        NOT NULL UNIQUE
    REFERENCES public.matters(id) ON DELETE RESTRICT,

  transaction_type   TEXT,
  advisory_category  TEXT,
  completion_date    DATE,

  created_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_mnld_matter ON public.matter_non_lit_details(matter_id);

CREATE TRIGGER trg_mnld_updated_at
  BEFORE UPDATE ON public.matter_non_lit_details
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

COMMENT ON TABLE public.matter_non_lit_details IS
  'Non-litigation-specific extension table. One-to-one with matters. '
  'No financial fields — MOLMS has no accounting or billing module.';



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 007_matter_entities.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 007: Matter Entities
-- All persons and organisations related to a matter.
-- Renamed from matter_parties per Phase 3 amendment.
-- Supports: Plaintiff, Defendant, Opposing Counsel,
--           Government Agency, Company, Law Firm, Witness, Other.
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.matter_entities (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  matter_id       UUID        NOT NULL
    REFERENCES public.matters(id) ON DELETE RESTRICT,

  entity_type     entity_type NOT NULL,
  name            TEXT        NOT NULL,
  organisation    TEXT,
  contact_details TEXT,
  notes           TEXT,

  -- Accountability
  created_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Archive model
  is_archived    BOOLEAN     NOT NULL DEFAULT FALSE,
  archived_by    UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
  archived_at    TIMESTAMPTZ,
  archive_reason TEXT
);

CREATE INDEX idx_me_matter      ON public.matter_entities(matter_id);
CREATE INDEX idx_me_matter_type ON public.matter_entities(matter_id, entity_type);
CREATE INDEX idx_me_archived    ON public.matter_entities(matter_id, is_archived);

CREATE TRIGGER trg_me_updated_at
  BEFORE UPDATE ON public.matter_entities
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

COMMENT ON TABLE public.matter_entities IS
  'All parties and organisations related to a matter. '
  'Does not imply CRM functionality — contact_details is a free-text note field only.';



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 008_matter_assignments.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 008: Matter Assignments
-- Immutable append-only log of all assignment changes.
-- Who was assigned, when, by whom, and why.
-- Never updated or deleted.
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.matter_assignments (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  matter_id   UUID        NOT NULL
    REFERENCES public.matters(id) ON DELETE RESTRICT,
  assigned_to UUID        NOT NULL
    REFERENCES public.users(id) ON DELETE RESTRICT,
  assigned_by UUID        NOT NULL
    REFERENCES public.users(id) ON DELETE RESTRICT,
  assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  reason      TEXT
);

CREATE INDEX idx_ma_matter      ON public.matter_assignments(matter_id);
CREATE INDEX idx_ma_assigned_to ON public.matter_assignments(assigned_to);
CREATE INDEX idx_ma_date        ON public.matter_assignments(assigned_at DESC);

COMMENT ON TABLE public.matter_assignments IS
  'Append-only assignment history. Every assignment change creates a new row. '
  'No UPDATE or DELETE operations permitted. Historical record is permanent.';



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 009_matter_notes.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 009: Matter Notes
-- Internal progress notes attached to matters.
-- Supports Partner review/acknowledgement workflow.
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.matter_notes (
  id         UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
  matter_id  UUID      NOT NULL
    REFERENCES public.matters(id) ON DELETE RESTRICT,

  note_type  note_type NOT NULL DEFAULT 'general',
  content    TEXT      NOT NULL,

  -- Partner review workflow
  is_reviewed BOOLEAN     NOT NULL DEFAULT FALSE,
  reviewed_by UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
  reviewed_at TIMESTAMPTZ,

  -- Accountability
  created_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Archive model
  is_archived    BOOLEAN     NOT NULL DEFAULT FALSE,
  archived_by    UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
  archived_at    TIMESTAMPTZ,
  archive_reason TEXT,

  CONSTRAINT notes_review_consistency CHECK (
    (is_reviewed = FALSE AND reviewed_by IS NULL AND reviewed_at IS NULL)
    OR
    (is_reviewed = TRUE AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
  )
);

CREATE INDEX idx_mn_matter       ON public.matter_notes(matter_id);
CREATE INDEX idx_mn_created_by   ON public.matter_notes(created_by);
CREATE INDEX idx_mn_reviewed     ON public.matter_notes(matter_id, is_reviewed)
  WHERE is_archived = FALSE;
CREATE INDEX idx_mn_type         ON public.matter_notes(matter_id, note_type)
  WHERE is_archived = FALSE;

CREATE TRIGGER trg_mn_updated_at
  BEFORE UPDATE ON public.matter_notes
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

COMMENT ON TABLE public.matter_notes IS
  'Internal notes on matters. Partners can mark notes as reviewed. '
  'Types: general, partner, court_update, internal. Archived notes hidden by default.';



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 010_matter_hearings.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 010: Matter Hearings
-- Court hearing dates and outcomes. Litigation matters only.
-- Updates matter_litigation_details.next_hearing_date via trigger.
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.matter_hearings (
  id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  matter_id     UUID         NOT NULL
    REFERENCES public.matters(id) ON DELETE RESTRICT,

  hearing_date  TIMESTAMPTZ  NOT NULL,
  hearing_type  hearing_type,
  court_name    TEXT,
  judge_name    TEXT,
  venue         TEXT,
  outcome       TEXT,
  adjourned_to  DATE,
  notes         TEXT,

  -- Accountability
  created_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Archive model
  is_archived    BOOLEAN     NOT NULL DEFAULT FALSE,
  archived_by    UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
  archived_at    TIMESTAMPTZ,
  archive_reason TEXT
);

CREATE        INDEX idx_mh_matter       ON public.matter_hearings(matter_id);
CREATE        INDEX idx_mh_date         ON public.matter_hearings(hearing_date);
-- NOTE: a partial index predicate cannot reference now() — now() is STABLE,
-- not IMMUTABLE, and PostgreSQL requires IMMUTABLE expressions in index
-- predicates (the predicate is evaluated once at index-build time, not
-- per-query). A plain (non-partial) index on hearing_date is used instead;
-- the application-level "upcoming hearings" filter (hearing_date >= now())
-- is applied at query time and still uses idx_mh_date efficiently.
CREATE        INDEX idx_mh_outstanding  ON public.matter_hearings(matter_id, hearing_date)
  WHERE outcome IS NULL AND is_archived = FALSE;

CREATE TRIGGER trg_mh_updated_at
  BEFORE UPDATE ON public.matter_hearings
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

-- ─── Trigger: keep next_hearing_date cache current ─────────────
CREATE OR REPLACE FUNCTION public.fn_update_next_hearing_date()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_next_date DATE;
BEGIN
  -- Find the next upcoming hearing for this matter
  SELECT DATE(hearing_date)
  INTO v_next_date
  FROM public.matter_hearings
  WHERE matter_id = COALESCE(NEW.matter_id, OLD.matter_id)
    AND hearing_date >= now()
    AND is_archived = FALSE
    AND outcome IS NULL
  ORDER BY hearing_date ASC
  LIMIT 1;

  -- Update the denormalised cache on litigation_details
  UPDATE public.matter_litigation_details
  SET next_hearing_date = v_next_date
  WHERE matter_id = COALESCE(NEW.matter_id, OLD.matter_id);

  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_update_next_hearing
  AFTER INSERT OR UPDATE OR DELETE ON public.matter_hearings
  FOR EACH ROW EXECUTE FUNCTION public.fn_update_next_hearing_date();

COMMENT ON TABLE public.matter_hearings IS
  'Court hearing log for litigation matters. Trigger keeps '
  'matter_litigation_details.next_hearing_date synchronised.';



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 011_daily_reports.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 011: Daily Reports
-- Member daily work logs with Partner review workflow.
-- One report per member per working day.
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.daily_reports (
  id               UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  reference_number TEXT          NOT NULL UNIQUE,

  submitted_by     UUID          NOT NULL
    REFERENCES public.users(id) ON DELETE RESTRICT,
  report_date      DATE          NOT NULL,
  status           report_status NOT NULL DEFAULT 'draft',

  summary          TEXT,
  reviewer_notes   TEXT,
  reviewed_by      UUID          REFERENCES public.users(id) ON DELETE RESTRICT,
  reviewed_at      TIMESTAMPTZ,

  -- Accountability
  created_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Archive model
  is_archived    BOOLEAN     NOT NULL DEFAULT FALSE,
  archived_by    UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
  archived_at    TIMESTAMPTZ,
  archive_reason TEXT,

  version INTEGER NOT NULL DEFAULT 1,

  -- One report per member per day
  CONSTRAINT daily_reports_unique_day UNIQUE(submitted_by, report_date),

  CONSTRAINT daily_reports_review_consistency CHECK (
    (status != 'reviewed' AND reviewed_by IS NULL)
    OR (status = 'reviewed' AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
  )
);

CREATE INDEX idx_dr_submitted_by   ON public.daily_reports(submitted_by);
CREATE INDEX idx_dr_date           ON public.daily_reports(report_date DESC);
CREATE INDEX idx_dr_status         ON public.daily_reports(status, is_archived);
CREATE INDEX idx_dr_pending_review ON public.daily_reports(status)
  WHERE status = 'submitted' AND is_archived = FALSE;

CREATE TRIGGER trg_dr_updated_at
  BEFORE UPDATE ON public.daily_reports
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

-- ─── Report Line Items ─────────────────────────────────────────
CREATE TABLE public.daily_report_items (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id   UUID        NOT NULL
    REFERENCES public.daily_reports(id) ON DELETE RESTRICT,
  matter_id   UUID        REFERENCES public.matters(id) ON DELETE RESTRICT,

  description TEXT        NOT NULL,
  time_spent  TEXT,
  sort_order  INTEGER     NOT NULL DEFAULT 0,

  -- Accountability
  created_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_dri_report   ON public.daily_report_items(report_id);
CREATE INDEX idx_dri_matter   ON public.daily_report_items(matter_id);
CREATE INDEX idx_dri_sort     ON public.daily_report_items(report_id, sort_order);

CREATE TRIGGER trg_dri_updated_at
  BEFORE UPDATE ON public.daily_report_items
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

COMMENT ON TABLE public.daily_reports IS
  'Daily work reports. One per member per day. '
  'Workflow: draft → submitted → reviewed (or returned for correction).';
COMMENT ON TABLE public.daily_report_items IS
  'Individual work line items within a daily report. '
  'Optionally linked to a matter by FK.';



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 012_legal_diary.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 012: Legal Diary
-- Firm-wide event calendar: hearings, deadlines, meetings, reminders.
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE public.diary_events (
  id             UUID       PRIMARY KEY DEFAULT gen_random_uuid(),
  title          TEXT       NOT NULL,
  description    TEXT,
  event_type     event_type NOT NULL DEFAULT 'general',

  start_datetime TIMESTAMPTZ NOT NULL,
  end_datetime   TIMESTAMPTZ,
  is_all_day     BOOLEAN     NOT NULL DEFAULT FALSE,
  location       TEXT,

  -- Optional matter linkage
  matter_id      UUID        REFERENCES public.matters(id) ON DELETE RESTRICT,

  -- Accountability
  created_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Archive model
  is_archived    BOOLEAN     NOT NULL DEFAULT FALSE,
  archived_by    UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
  archived_at    TIMESTAMPTZ,
  archive_reason TEXT,

  -- Search
  search_vector TSVECTOR,

  CONSTRAINT diary_end_after_start CHECK (
    end_datetime IS NULL OR end_datetime >= start_datetime
  )
);

CREATE INDEX idx_de_start       ON public.diary_events(start_datetime);
CREATE INDEX idx_de_matter      ON public.diary_events(matter_id)
  WHERE matter_id IS NOT NULL;
CREATE INDEX idx_de_type        ON public.diary_events(event_type, is_archived);
-- NOTE: now() is STABLE, not IMMUTABLE — cannot be used in a partial index
-- predicate. A plain index on start_datetime (idx_de_start, above) is used
-- instead; the "upcoming events" filter (start_datetime >= now()) is applied
-- at query time and still benefits from idx_de_start.
CREATE INDEX idx_de_search      ON public.diary_events USING GIN(search_vector);

CREATE TRIGGER trg_de_updated_at
  BEFORE UPDATE ON public.diary_events
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

-- ─── Event Members (many-to-many) ─────────────────────────────
CREATE TABLE public.diary_event_members (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id      UUID        NOT NULL
    REFERENCES public.diary_events(id) ON DELETE RESTRICT,
  user_id       UUID        NOT NULL
    REFERENCES public.users(id) ON DELETE RESTRICT,
  role_in_event TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT diary_event_members_unique UNIQUE(event_id, user_id)
);

CREATE INDEX idx_dem_event ON public.diary_event_members(event_id);
CREATE INDEX idx_dem_user  ON public.diary_event_members(user_id);

COMMENT ON TABLE public.diary_events IS
  'Firm-wide event calendar. All members see all events. '
  'Types: hearing, deadline, meeting, reminder, general.';
COMMENT ON TABLE public.diary_event_members IS
  'Many-to-many: members associated with a diary event.';



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 013_documents.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 013: Documents & Versioning
-- Document metadata only. Files stored in Supabase Storage.
-- Full version history preserved — no version is ever deleted.
-- ═══════════════════════════════════════════════════════════════

-- ─── Documents (metadata) ─────────────────────────────────────
CREATE TABLE public.documents (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  reference_number TEXT        NOT NULL UNIQUE,

  title            TEXT        NOT NULL,
  description      TEXT,
  file_path        TEXT        NOT NULL,  -- path in Supabase Storage
  file_name        TEXT        NOT NULL,
  file_size_bytes  BIGINT,
  mime_type        TEXT,

  -- Classification
  category_id      UUID        REFERENCES public.document_categories(id) ON DELETE RESTRICT,
  matter_id        UUID        REFERENCES public.matters(id) ON DELETE RESTRICT,

  -- Versioning
  version_number   INTEGER     NOT NULL DEFAULT 1,

  -- Accountability
  uploaded_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_by   UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by   UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Archive model
  is_archived    BOOLEAN     NOT NULL DEFAULT FALSE,
  archived_by    UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
  archived_at    TIMESTAMPTZ,
  archive_reason TEXT,

  -- Full-text search
  search_vector TSVECTOR
);

CREATE UNIQUE INDEX idx_doc_ref      ON public.documents(reference_number);
CREATE        INDEX idx_doc_matter   ON public.documents(matter_id, is_archived)
  WHERE matter_id IS NOT NULL;
CREATE        INDEX idx_doc_category ON public.documents(category_id, is_archived);
CREATE        INDEX idx_doc_uploader ON public.documents(uploaded_by);
CREATE        INDEX idx_doc_search   ON public.documents USING GIN(search_vector);

CREATE TRIGGER trg_doc_updated_at
  BEFORE UPDATE ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

-- ─── Document Versions (append-only) ─────────────────────────
CREATE TABLE public.document_versions (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id     UUID        NOT NULL
    REFERENCES public.documents(id) ON DELETE RESTRICT,
  version_number  INTEGER     NOT NULL,
  file_path       TEXT        NOT NULL,
  file_name       TEXT        NOT NULL,
  file_size_bytes BIGINT,
  change_notes    TEXT,
  uploaded_by     UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  uploaded_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT doc_versions_unique UNIQUE(document_id, version_number)
);

CREATE INDEX idx_dv_document ON public.document_versions(document_id, version_number);

-- ─── Document Tag Map ──────────────────────────────────────────
CREATE TABLE public.document_tag_map (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  document_id UUID        NOT NULL REFERENCES public.documents(id) ON DELETE RESTRICT,
  tag_id      UUID        NOT NULL REFERENCES public.tags(id) ON DELETE RESTRICT,
  created_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT document_tag_unique UNIQUE(document_id, tag_id)
);

CREATE INDEX idx_dtm_doc ON public.document_tag_map(document_id);
CREATE INDEX idx_dtm_tag ON public.document_tag_map(tag_id);

-- ─── Templates ────────────────────────────────────────────────
CREATE TABLE public.templates (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  title       TEXT        NOT NULL,
  description TEXT,
  module      TEXT        NOT NULL,
  file_path   TEXT,
  created_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_archived BOOLEAN     NOT NULL DEFAULT FALSE,
  archived_by UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
  archived_at TIMESTAMPTZ,
  archive_reason TEXT
);

CREATE INDEX idx_templates_module ON public.templates(module, is_archived);

CREATE TRIGGER trg_templates_updated_at
  BEFORE UPDATE ON public.templates
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

-- ─── Backups log ──────────────────────────────────────────────
CREATE TABLE public.backups (
  id           UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  label        TEXT          NOT NULL,
  storage_path TEXT,
  status       backup_status NOT NULL DEFAULT 'pending',
  notes        TEXT,
  created_by   UUID          NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at   TIMESTAMPTZ   NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.documents IS
  'Document metadata. Files stored in Supabase Storage bucket. '
  'Version history preserved in document_versions. No files ever deleted.';



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 014_intercom_notifications_audit.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 014: InterCom, Notifications, Activity Feed,
--                       Audit Logs
-- ═══════════════════════════════════════════════════════════════

-- ─── InterCom Threads ─────────────────────────────────────────
CREATE TABLE public.intercom_threads (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  title        TEXT        NOT NULL,
  thread_type  thread_type NOT NULL DEFAULT 'discussion',
  is_pinned    BOOLEAN     NOT NULL DEFAULT FALSE,
  is_mandatory BOOLEAN     NOT NULL DEFAULT FALSE,
  expires_at   TIMESTAMPTZ,

  -- Accountability
  created_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Archive model
  is_archived    BOOLEAN     NOT NULL DEFAULT FALSE,
  archived_by    UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
  archived_at    TIMESTAMPTZ,
  archive_reason TEXT
);

CREATE INDEX idx_it_type       ON public.intercom_threads(thread_type, is_archived);
CREATE INDEX idx_it_pinned     ON public.intercom_threads(is_pinned, created_at DESC);
CREATE INDEX idx_it_mandatory  ON public.intercom_threads(is_mandatory)
  WHERE is_mandatory = TRUE AND is_archived = FALSE;

CREATE TRIGGER trg_it_updated_at
  BEFORE UPDATE ON public.intercom_threads
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

-- ─── InterCom Messages ────────────────────────────────────────
CREATE TABLE public.intercom_messages (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id         UUID        NOT NULL
    REFERENCES public.intercom_threads(id) ON DELETE RESTRICT,
  content           TEXT        NOT NULL,
  parent_message_id UUID        REFERENCES public.intercom_messages(id) ON DELETE RESTRICT,

  -- Accountability
  created_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by  UUID        NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Archive model
  is_archived    BOOLEAN     NOT NULL DEFAULT FALSE,
  archived_by    UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
  archived_at    TIMESTAMPTZ,
  archive_reason TEXT,

  search_vector TSVECTOR
);

CREATE INDEX idx_im_thread  ON public.intercom_messages(thread_id, created_at);
CREATE INDEX idx_im_parent  ON public.intercom_messages(parent_message_id)
  WHERE parent_message_id IS NOT NULL;
CREATE INDEX idx_im_search  ON public.intercom_messages USING GIN(search_vector);

CREATE TRIGGER trg_im_updated_at
  BEFORE UPDATE ON public.intercom_messages
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

-- ─── Notifications ────────────────────────────────────────────
CREATE TABLE public.notifications (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  trigger_id   UUID        NOT NULL
    REFERENCES public.notification_triggers(id) ON DELETE RESTRICT,
  recipient_id UUID        NOT NULL
    REFERENCES public.users(id) ON DELETE RESTRICT,
  actor_id     UUID        REFERENCES public.users(id) ON DELETE RESTRICT,
  target_table TEXT,
  target_id    UUID,
  target_label TEXT,
  message      TEXT        NOT NULL,
  is_read      BOOLEAN     NOT NULL DEFAULT FALSE,
  read_at      TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Critical performance index: unread count query
CREATE INDEX idx_notif_unread ON public.notifications(recipient_id, is_read)
  WHERE is_read = FALSE;
CREATE INDEX idx_notif_list   ON public.notifications(recipient_id, created_at DESC);

-- ─── Activity Feed ────────────────────────────────────────────
-- INSERT-only. 90-day retention (pg_cron purge job).
-- User-facing dashboard stream — distinct from audit_logs.
CREATE TABLE public.activity_feed (
  id           UUID                    PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type   activity_event_type     NOT NULL,
  module       TEXT                    NOT NULL,
  -- Nullable: system-generated events (e.g. bootstrap user creation,
  -- scheduled jobs) have no human actor. NULL renders as "System" in the UI.
  actor_id     UUID
    REFERENCES public.users(id) ON DELETE RESTRICT,
  target_table TEXT,
  target_id    UUID,
  target_label TEXT,
  message      TEXT                    NOT NULL,
  created_at   TIMESTAMPTZ             NOT NULL DEFAULT now()
);

CREATE INDEX idx_af_created  ON public.activity_feed(created_at DESC);
CREATE INDEX idx_af_actor    ON public.activity_feed(actor_id);
CREATE INDEX idx_af_module   ON public.activity_feed(module);
CREATE INDEX idx_af_target   ON public.activity_feed(target_id)
  WHERE target_id IS NOT NULL;

-- ─── Audit Logs ───────────────────────────────────────────────
-- Partitioned by performed_at for performance at 500k+ rows.
-- IMMUTABLE: no UPDATE or DELETE permitted.
-- INSERT only via SECURITY DEFINER trigger.
CREATE TABLE public.audit_logs (
  id              UUID         NOT NULL DEFAULT gen_random_uuid(),
  action_type     audit_action NOT NULL,
  module          TEXT         NOT NULL,
  target_table    TEXT         NOT NULL,
  target_id       UUID,
  target_label    TEXT,
  -- Nullable: genuine system/bootstrap actions (no auth.uid() session,
  -- e.g. the first Administrator created via RLS-bypassed SQL) have no
  -- real actor. A placeholder UUID would still need to satisfy the FK
  -- below, which defeats the purpose — NULL is the honest representation
  -- and renders as "System" in the UI.
  performed_by    UUID
    REFERENCES public.users(id) ON DELETE RESTRICT,
  performed_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
  ip_address      INET,
  user_agent      TEXT,
  before_snapshot JSONB,
  after_snapshot  JSONB,
  notes           TEXT
) PARTITION BY RANGE (performed_at);

-- Initial partitions — add monthly via pg_cron (migration 022)
CREATE TABLE public.audit_logs_2026_q1
  PARTITION OF public.audit_logs
  FOR VALUES FROM ('2026-01-01') TO ('2026-04-01');

CREATE TABLE public.audit_logs_2026_q2
  PARTITION OF public.audit_logs
  FOR VALUES FROM ('2026-04-01') TO ('2026-07-01');

CREATE TABLE public.audit_logs_2026_q3
  PARTITION OF public.audit_logs
  FOR VALUES FROM ('2026-07-01') TO ('2026-10-01');

CREATE TABLE public.audit_logs_2026_q4
  PARTITION OF public.audit_logs
  FOR VALUES FROM ('2026-10-01') TO ('2027-01-01');

CREATE TABLE public.audit_logs_2027
  PARTITION OF public.audit_logs
  FOR VALUES FROM ('2027-01-01') TO ('2028-01-01');

CREATE TABLE public.audit_logs_2028_onwards
  PARTITION OF public.audit_logs
  FOR VALUES FROM ('2028-01-01') TO ('2100-01-01');

-- Indexes on audit_logs (applied to partitioned table)
CREATE INDEX idx_al_performed  ON public.audit_logs(performed_at DESC);
CREATE INDEX idx_al_by         ON public.audit_logs(performed_by);
CREATE INDEX idx_al_target     ON public.audit_logs(target_table, target_id);
CREATE INDEX idx_al_action     ON public.audit_logs(action_type);

COMMENT ON TABLE public.audit_logs IS
  'Central immutable compliance audit trail. Partitioned by performed_at. '
  'INSERT-only via SECURITY DEFINER trigger. No UPDATE or DELETE ever permitted.';
COMMENT ON TABLE public.activity_feed IS
  'User-facing firm activity stream for Dashboard. INSERT-only. '
  'Purged after 90 days by scheduled pg_cron job.';



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 015_functions.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 015: Core SQL Helper Functions
-- ═══════════════════════════════════════════════════════════════

-- ─── get_user_role() ──────────────────────────────────────────
-- Returns the role of the currently authenticated user.
-- CRITICAL: used in all RLS policies. Must exist before migration 020.
-- SECURITY DEFINER: runs with elevated privileges to read users table.
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS TEXT
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role::TEXT FROM public.users WHERE id = auth.uid();
$$;

GRANT EXECUTE ON FUNCTION public.get_user_role() TO authenticated;

-- ─── generate_matter_reference() ─────────────────────────────
-- Generates a collision-safe sequential reference number.
-- Format: {PREFIX}-{YEAR}-{NNN} e.g. CL-2026-001
-- Uses advisory lock to prevent race conditions under concurrent inserts.
CREATE OR REPLACE FUNCTION public.generate_matter_reference(p_matter_type_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type_code  TEXT;
  v_prefix     TEXT;
  v_year       TEXT;
  v_max_seq    INTEGER;
  v_reference  TEXT;
BEGIN
  SELECT type_code::TEXT INTO v_type_code
  FROM public.matter_types WHERE id = p_matter_type_id;

  IF v_type_code IS NULL THEN
    RAISE EXCEPTION 'Unknown matter_type_id: %', p_matter_type_id;
  END IF;

  v_prefix := CASE v_type_code
    WHEN 'litigation'     THEN 'CL'
    WHEN 'non_litigation' THEN 'NL'
    ELSE 'MT'
  END;

  v_year := EXTRACT(YEAR FROM now())::TEXT;

  -- Acquire advisory lock scoped to this type+year to serialise concurrent inserts
  PERFORM pg_advisory_xact_lock(hashtext(v_prefix || v_year));

  -- Find the highest existing sequence number for this type/year
  SELECT COALESCE(MAX(
    CAST(
      NULLIF(SPLIT_PART(reference_number, '-', 3), '') AS INTEGER
    )
  ), 0)
  INTO v_max_seq
  FROM public.matters
  WHERE matter_type_id = p_matter_type_id
    AND reference_number LIKE v_prefix || '-' || v_year || '-%';

  v_reference := v_prefix || '-' || v_year || '-' || LPAD((v_max_seq + 1)::TEXT, 3, '0');
  RETURN v_reference;
END;
$$;

GRANT EXECUTE ON FUNCTION public.generate_matter_reference(UUID) TO authenticated;

-- ─── generate_report_reference() ──────────────────────────────
CREATE OR REPLACE FUNCTION public.generate_report_reference()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_year    TEXT;
  v_max_seq INTEGER;
BEGIN
  v_year := EXTRACT(YEAR FROM now())::TEXT;
  PERFORM pg_advisory_xact_lock(hashtext('DR' || v_year));
  SELECT COALESCE(MAX(
    CAST(NULLIF(SPLIT_PART(reference_number, '-', 3), '') AS INTEGER)
  ), 0) INTO v_max_seq
  FROM public.daily_reports
  WHERE reference_number LIKE 'DR-' || v_year || '-%';

  RETURN 'DR-' || v_year || '-' || LPAD((v_max_seq + 1)::TEXT, 3, '0');
END;
$$;

GRANT EXECUTE ON FUNCTION public.generate_report_reference() TO authenticated;

-- ─── generate_document_reference() ────────────────────────────
CREATE OR REPLACE FUNCTION public.generate_document_reference()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_year    TEXT;
  v_max_seq INTEGER;
BEGIN
  v_year := EXTRACT(YEAR FROM now())::TEXT;
  PERFORM pg_advisory_xact_lock(hashtext('DOC' || v_year));
  SELECT COALESCE(MAX(
    CAST(NULLIF(SPLIT_PART(reference_number, '-', 4), '') AS INTEGER)
  ), 0) INTO v_max_seq
  FROM public.documents
  WHERE reference_number LIKE 'DOC-' || v_year || '-%';

  RETURN 'DOC-' || v_year || '-' || LPAD((v_max_seq + 1)::TEXT, 4, '0');
END;
$$;

GRANT EXECUTE ON FUNCTION public.generate_document_reference() TO authenticated;

-- ─── fn_set_updated_at() ──────────────────────────────────────
-- Already defined in migration 002. Included here as reminder.
-- This function powers all updated_at triggers.
-- CREATE OR REPLACE ensures idempotency.
CREATE OR REPLACE FUNCTION public.fn_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 016_search_vectors.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 016: Full-Text Search Vector Triggers
-- PostgreSQL native full-text search using TSVECTOR.
-- No external search engine required at 50-user scale.
-- Language: English dictionary (stop-word removal + stemming).
-- ═══════════════════════════════════════════════════════════════

-- ─── Matters search vector ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_update_matter_search()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_party_names TEXT := '';
  v_lit_details TEXT := '';
BEGIN
  -- Pull party names from matter_entities for richer search
  SELECT COALESCE(string_agg(name || ' ' || COALESCE(organisation, ''), ' '), '')
  INTO v_party_names
  FROM public.matter_entities
  WHERE matter_id = NEW.id AND is_archived = FALSE;

  -- Pull court details for litigation matters
  SELECT COALESCE(court_name || ' ' || COALESCE(case_number, '') || ' ' || COALESCE(judge_name, ''), '')
  INTO v_lit_details
  FROM public.matter_litigation_details
  WHERE matter_id = NEW.id;

  NEW.search_vector := to_tsvector('english',
    COALESCE(NEW.reference_number, '') || ' ' ||
    COALESCE(NEW.title, '') || ' ' ||
    COALESCE(NEW.description, '') || ' ' ||
    v_party_names || ' ' ||
    v_lit_details
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_matter_search ON public.matters;
CREATE TRIGGER trg_matter_search
  BEFORE INSERT OR UPDATE OF title, description, reference_number
  ON public.matters
  FOR EACH ROW EXECUTE FUNCTION public.fn_update_matter_search();

-- ─── Documents search vector ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_update_document_search()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  NEW.search_vector := to_tsvector('english',
    COALESCE(NEW.reference_number, '') || ' ' ||
    COALESCE(NEW.title, '') || ' ' ||
    COALESCE(NEW.description, '') || ' ' ||
    COALESCE(NEW.file_name, '')
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_document_search ON public.documents;
CREATE TRIGGER trg_document_search
  BEFORE INSERT OR UPDATE OF title, description, file_name, reference_number
  ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.fn_update_document_search();

-- ─── Diary events search vector ────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_update_diary_search()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  NEW.search_vector := to_tsvector('english',
    COALESCE(NEW.title, '') || ' ' ||
    COALESCE(NEW.description, '') || ' ' ||
    COALESCE(NEW.location, '')
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_diary_search ON public.diary_events;
CREATE TRIGGER trg_diary_search
  BEFORE INSERT OR UPDATE OF title, description, location
  ON public.diary_events
  FOR EACH ROW EXECUTE FUNCTION public.fn_update_diary_search();

-- ─── InterCom messages search vector ───────────────────────────
CREATE OR REPLACE FUNCTION public.fn_update_intercom_search()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  NEW.search_vector := to_tsvector('english', COALESCE(NEW.content, ''));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_intercom_search ON public.intercom_messages;
CREATE TRIGGER trg_intercom_search
  BEFORE INSERT OR UPDATE OF content
  ON public.intercom_messages
  FOR EACH ROW EXECUTE FUNCTION public.fn_update_intercom_search();

-- ─── Users search vector (stored separately) ───────────────────
-- Users table doesn't have search_vector column — use trigram index on name
-- already created in migration 002.
-- For global search, query: users WHERE name ILIKE '%query%'



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 017_audit_triggers.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 017: Audit Log Trigger System
-- Every CREATE/UPDATE/ARCHIVE/RESTORE is automatically captured.
-- SECURITY DEFINER bypasses RLS to always write to audit_logs.
-- The audit log itself is protected by RLS (admin-only SELECT).
-- INSERT only — no UPDATE or DELETE on audit_logs ever.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_audit_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  -- Same cross-table hazard as fn_activity_trigger(): this function is
  -- attached to 9 structurally different tables. Every NEW.<column> /
  -- OLD.<column> reference must type-check against whatever table
  -- actually fired the trigger, even inside branches that are logically
  -- unreachable for that table. All field access goes through
  -- to_jsonb(NEW)/to_jsonb(OLD) ->> to avoid binding to a specific
  -- table's row type or column type.
  v_new        JSONB := to_jsonb(NEW);
  v_old        JSONB := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END;

  v_action     audit_action;
  v_before     JSONB := NULL;
  v_after      JSONB := NULL;
  v_actor      UUID  := auth.uid();
  v_label      TEXT  := NULL;
  v_module     TEXT  := TG_TABLE_NAME;
  v_new_id     UUID  := NEW.id;

  v_new_is_archived TEXT := v_new->>'is_archived';
  v_old_is_archived TEXT := v_old->>'is_archived';
  v_new_role        TEXT := v_new->>'role';
  v_old_role        TEXT := v_old->>'role';
BEGIN
  -- ── Determine audit action ────────────────────────────────
  IF TG_OP = 'INSERT' THEN
    v_action := 'RECORD_CREATED';
    v_after  := v_new;

  ELSIF TG_OP = 'UPDATE' THEN
    -- Distinguish archive, restore, role-change, and standard edit
    IF TG_TABLE_NAME != 'users' THEN
      IF v_old_is_archived = 'false' AND v_new_is_archived = 'true' THEN
        v_action := 'RECORD_ARCHIVED';
      ELSIF v_old_is_archived = 'true' AND v_new_is_archived = 'false' THEN
        v_action := 'RECORD_RESTORED';
      ELSE
        v_action := 'RECORD_UPDATED';
      END IF;
    ELSIF TG_TABLE_NAME = 'users' AND v_old_role IS DISTINCT FROM v_new_role THEN
      v_action := 'ROLE_CHANGED';
    ELSE
      v_action := 'RECORD_UPDATED';
    END IF;
    v_before := v_old;
    v_after  := v_new;
  ELSE
    RETURN COALESCE(NEW, OLD); -- Not tracking DELETE (no hard delete in MOLMS)
  END IF;

  -- ── Module and human-readable label ───────────────────────
  CASE TG_TABLE_NAME
    WHEN 'matters' THEN
      v_module := CASE
        WHEN EXISTS (SELECT 1 FROM public.matter_types mt
          WHERE mt.id = (v_new->>'matter_type_id')::UUID AND mt.type_code = 'litigation')
        THEN 'cause_list' ELSE 'non_litigation'
      END;
      v_label := (v_new->>'reference_number') || ': ' || (v_new->>'title');

    WHEN 'daily_reports' THEN
      v_module := 'daily_reports';
      v_label  := v_new->>'reference_number';

    WHEN 'documents' THEN
      v_module := 'documents';
      v_label  := (v_new->>'reference_number') || ': ' || (v_new->>'title');

    WHEN 'diary_events' THEN
      v_module := 'legal_diary';
      v_label  := v_new->>'title';

    WHEN 'intercom_threads' THEN
      v_module := 'intercom';
      v_label  := v_new->>'title';

    WHEN 'intercom_messages' THEN
      v_module := 'intercom';
      v_label  := 'Message in thread ' || (v_new->>'thread_id');

    WHEN 'users' THEN
      v_module := 'members';
      v_label  := (v_new->>'name') || ' (' || (v_new->>'email') || ')';

    WHEN 'matter_notes' THEN
      v_module := 'cause_list';
      v_label  := 'Note on matter ' || (v_new->>'matter_id');

    WHEN 'matter_entities' THEN
      v_module := 'cause_list';
      v_label  := (v_new->>'name') || ' (' || (v_new->>'entity_type') || ')';

    WHEN 'matter_hearings' THEN
      v_module := 'cause_list';
      v_label  := 'Hearing ' || to_char((v_new->>'hearing_date')::TIMESTAMPTZ, 'DD Mon YYYY');

    ELSE
      v_label := v_new->>'id';
  END CASE;

  -- ── Insert into audit_logs ─────────────────────────────────
  INSERT INTO public.audit_logs (
    action_type, module, target_table, target_id,
    target_label, performed_by, performed_at,
    before_snapshot, after_snapshot
  ) VALUES (
    v_action,
    v_module,
    TG_TABLE_NAME,
    v_new_id,
    v_label,
    v_actor, -- NULL for genuine system actions (no auth.uid() session) — see column comment
    now(),
    v_before,
    v_after
  );

  RETURN NEW;
END;
$$;

-- ─── Apply audit trigger to all operational tables ─────────────

DROP TRIGGER IF EXISTS trg_audit_matters           ON public.matters;
DROP TRIGGER IF EXISTS trg_audit_matter_notes      ON public.matter_notes;
DROP TRIGGER IF EXISTS trg_audit_matter_entities   ON public.matter_entities;
DROP TRIGGER IF EXISTS trg_audit_matter_hearings   ON public.matter_hearings;
DROP TRIGGER IF EXISTS trg_audit_daily_reports     ON public.daily_reports;
DROP TRIGGER IF EXISTS trg_audit_documents         ON public.documents;
DROP TRIGGER IF EXISTS trg_audit_diary_events      ON public.diary_events;
DROP TRIGGER IF EXISTS trg_audit_intercom_threads  ON public.intercom_threads;
DROP TRIGGER IF EXISTS trg_audit_users             ON public.users;

CREATE TRIGGER trg_audit_matters
  AFTER INSERT OR UPDATE ON public.matters
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger();

CREATE TRIGGER trg_audit_matter_notes
  AFTER INSERT OR UPDATE ON public.matter_notes
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger();

CREATE TRIGGER trg_audit_matter_entities
  AFTER INSERT OR UPDATE ON public.matter_entities
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger();

CREATE TRIGGER trg_audit_matter_hearings
  AFTER INSERT OR UPDATE ON public.matter_hearings
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger();

CREATE TRIGGER trg_audit_daily_reports
  AFTER INSERT OR UPDATE ON public.daily_reports
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger();

CREATE TRIGGER trg_audit_documents
  AFTER INSERT OR UPDATE ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger();

CREATE TRIGGER trg_audit_diary_events
  AFTER INSERT OR UPDATE ON public.diary_events
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger();

CREATE TRIGGER trg_audit_intercom_threads
  AFTER INSERT OR UPDATE ON public.intercom_threads
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger();

CREATE TRIGGER trg_audit_users
  AFTER INSERT OR UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.fn_audit_trigger();



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 018_activity_triggers.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 018: Activity Feed Trigger System
-- User-facing plain-language activity stream for Dashboard.
-- Distinct from audit_logs: readable by all firm members.
-- INSERT-only. 90-day retention enforced by pg_cron job.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_activity_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  -- This function is attached to 9 structurally different tables
  -- (matters, matter_notes, matter_hearings, matter_entities,
  --  daily_reports, documents, diary_events, intercom_threads, users).
  -- PL/pgSQL resolves NEW.<column> against the ACTUAL firing table's row
  -- type at each invocation — not just the first table it was written
  -- against. Any direct reference to a column that doesn't exist on every
  -- attached table (e.g. NEW.thread_type, only on intercom_threads) or
  -- whose type differs across tables (e.g. NEW.status: matter_status vs
  -- report_status vs user_status) raises an error on the OTHER tables,
  -- even though that branch is logically unreachable for them.
  --
  -- FIX: every field is read through to_jsonb(NEW)/to_jsonb(OLD) and
  -- extracted as TEXT/UUID via ->> / ->. This never fails to compile or
  -- bind regardless of the firing table's actual columns — a missing key
  -- simply yields NULL instead of an error.
  v_new            JSONB := to_jsonb(NEW);
  v_old            JSONB := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END;

  v_actor_name     TEXT;
  v_event_type     activity_event_type;
  v_module         TEXT;
  v_label          TEXT;
  v_message        TEXT;
  v_type_code      TEXT;
  v_status_label   TEXT;
  v_assignee       TEXT;
  v_matter_ref     TEXT;
  v_new_id         UUID := NEW.id;

  v_new_status     TEXT := v_new->>'status';
  v_old_status     TEXT := v_old->>'status';
  v_new_is_archived TEXT := v_new->>'is_archived';
  v_old_is_archived TEXT := v_old->>'is_archived';
  v_new_assigned_to TEXT := v_new->>'assigned_to';
  v_old_assigned_to TEXT := v_old->>'assigned_to';
  v_new_status_id   TEXT := v_new->>'matter_status_id';
  v_old_status_id   TEXT := v_old->>'matter_status_id';
  v_new_thread_type TEXT := v_new->>'thread_type';
BEGIN
  -- Fetch actor name for human-readable messages
  SELECT name INTO v_actor_name FROM public.users WHERE id = auth.uid();
  v_actor_name := COALESCE(v_actor_name, 'System');

  -- ── matters ───────────────────────────────────────────────
  IF TG_TABLE_NAME = 'matters' THEN
    SELECT type_code::TEXT INTO v_type_code
    FROM public.matter_types WHERE id = (v_new->>'matter_type_id')::UUID;

    v_module := CASE COALESCE(v_type_code, '')
      WHEN 'litigation' THEN 'cause_list'
      ELSE 'non_litigation'
    END;
    v_label := v_new->>'reference_number';

    IF TG_OP = 'INSERT' THEN
      v_event_type := 'MATTER_CREATED';
      v_message    := v_actor_name || ' created matter ' || (v_new->>'reference_number');

    ELSIF TG_OP = 'UPDATE' THEN
      IF v_old_is_archived = 'false' AND v_new_is_archived = 'true' THEN
        v_event_type := 'MATTER_ARCHIVED';
        v_message    := v_actor_name || ' archived matter ' || (v_new->>'reference_number');

      ELSIF v_old_is_archived = 'true' AND v_new_is_archived = 'false' THEN
        v_event_type := 'MATTER_RESTORED';
        v_message    := v_actor_name || ' restored matter ' || (v_new->>'reference_number');

      ELSIF v_old_assigned_to IS DISTINCT FROM v_new_assigned_to AND v_new_assigned_to IS NOT NULL THEN
        SELECT name INTO v_assignee FROM public.users WHERE id = v_new_assigned_to::UUID;
        v_event_type := 'MATTER_ASSIGNED';
        v_message    := v_actor_name || ' assigned ' || (v_new->>'reference_number')
                     || ' to ' || COALESCE(v_assignee, 'a member');

      ELSIF v_old_status_id IS DISTINCT FROM v_new_status_id THEN
        SELECT label INTO v_status_label FROM public.matter_statuses WHERE id = v_new_status_id::UUID;
        v_event_type := 'MATTER_STATUS_CHANGED';
        v_message    := (v_new->>'reference_number') || ' moved to ' || COALESCE(v_status_label, 'new status');

      ELSE
        v_event_type := 'MATTER_UPDATED';
        v_message    := v_actor_name || ' updated matter ' || (v_new->>'reference_number');
      END IF;
    END IF;

  -- ── matter_notes ──────────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'matter_notes' AND TG_OP = 'INSERT' THEN
    SELECT reference_number INTO v_matter_ref FROM public.matters WHERE id = (v_new->>'matter_id')::UUID;
    v_event_type := 'NOTE_ADDED';
    v_module     := 'cause_list';
    v_label      := COALESCE(v_matter_ref, 'matter');
    v_message    := v_actor_name || ' added a note to ' || COALESCE(v_matter_ref, 'a matter');

  -- ── matter_hearings ───────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'matter_hearings' AND TG_OP = 'INSERT' THEN
    SELECT reference_number INTO v_matter_ref FROM public.matters WHERE id = (v_new->>'matter_id')::UUID;
    v_event_type := 'HEARING_ADDED';
    v_module     := 'cause_list';
    v_label      := COALESCE(v_matter_ref, 'matter');
    v_message    := v_actor_name || ' added a hearing to ' || COALESCE(v_matter_ref, 'a matter')
                 || ' on ' || to_char((v_new->>'hearing_date')::TIMESTAMPTZ, 'DD Mon YYYY');

  -- ── matter_entities ───────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'matter_entities' AND TG_OP = 'INSERT' THEN
    SELECT reference_number INTO v_matter_ref FROM public.matters WHERE id = (v_new->>'matter_id')::UUID;
    v_event_type := 'ENTITY_ADDED';
    v_module     := 'cause_list';
    v_label      := COALESCE(v_matter_ref, 'matter');
    v_message    := v_actor_name || ' added ' || (v_new->>'name') || ' to ' || COALESCE(v_matter_ref, 'a matter');

  -- ── daily_reports ─────────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'daily_reports' AND TG_OP = 'UPDATE'
    AND v_old_status IS DISTINCT FROM v_new_status
    AND v_new_status = 'submitted' THEN
    v_event_type := 'REPORT_SUBMITTED';
    v_module     := 'daily_reports';
    v_label      := v_new->>'reference_number';
    v_message    := v_actor_name || ' submitted daily report ' || (v_new->>'reference_number');

  ELSIF TG_TABLE_NAME = 'daily_reports' AND TG_OP = 'UPDATE'
    AND v_old_status IS DISTINCT FROM v_new_status
    AND v_new_status = 'reviewed' THEN
    v_event_type := 'REPORT_REVIEWED';
    v_module     := 'daily_reports';
    v_label      := v_new->>'reference_number';
    v_message    := v_actor_name || ' reviewed daily report ' || (v_new->>'reference_number');

  -- ── documents ─────────────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'documents' AND TG_OP = 'INSERT' THEN
    v_event_type := 'DOCUMENT_UPLOADED';
    v_module     := 'documents';
    v_label      := v_new->>'reference_number';
    v_message    := v_actor_name || ' uploaded ' || (v_new->>'title');

  -- ── diary_events ──────────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'diary_events' AND TG_OP = 'INSERT' THEN
    v_event_type := 'DIARY_EVENT_CREATED';
    v_module     := 'legal_diary';
    v_label      := v_new->>'title';
    v_message    := v_actor_name || ' created diary event: ' || (v_new->>'title');

  -- ── intercom_threads ──────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'intercom_threads' AND TG_OP = 'INSERT'
    AND v_new_thread_type = 'announcement' THEN
    v_event_type := 'INTERCOM_ANNOUNCEMENT';
    v_module     := 'intercom';
    v_label      := v_new->>'title';
    v_message    := v_actor_name || ' posted announcement: ' || (v_new->>'title');

  -- ── users (new member added) ───────────────────────────────
  ELSIF TG_TABLE_NAME = 'users' AND TG_OP = 'INSERT' THEN
    v_event_type := 'MEMBER_ADDED';
    v_module     := 'members';
    v_label      := v_new->>'name';
    v_message    := 'New member ' || (v_new->>'name') || ' joined the firm';

  ELSE
    RETURN COALESCE(NEW, OLD); -- Event not tracked in activity feed
  END IF;

  -- Insert the activity entry
  IF v_event_type IS NOT NULL THEN
    INSERT INTO public.activity_feed (
      event_type, module, actor_id,
      target_table, target_id, target_label, message
    ) VALUES (
      v_event_type,
      v_module,
      auth.uid(),
      TG_TABLE_NAME,
      v_new_id,
      v_label,
      v_message
    );
  END IF;

  RETURN NEW;
END;
$$;

-- Apply activity triggers
DROP TRIGGER IF EXISTS trg_activity_matters        ON public.matters;
DROP TRIGGER IF EXISTS trg_activity_notes          ON public.matter_notes;
DROP TRIGGER IF EXISTS trg_activity_hearings       ON public.matter_hearings;
DROP TRIGGER IF EXISTS trg_activity_entities       ON public.matter_entities;
DROP TRIGGER IF EXISTS trg_activity_reports        ON public.daily_reports;
DROP TRIGGER IF EXISTS trg_activity_documents      ON public.documents;
DROP TRIGGER IF EXISTS trg_activity_diary          ON public.diary_events;
DROP TRIGGER IF EXISTS trg_activity_intercom       ON public.intercom_threads;
DROP TRIGGER IF EXISTS trg_activity_users          ON public.users;

CREATE TRIGGER trg_activity_matters
  AFTER INSERT OR UPDATE ON public.matters
  FOR EACH ROW EXECUTE FUNCTION public.fn_activity_trigger();

CREATE TRIGGER trg_activity_notes
  AFTER INSERT ON public.matter_notes
  FOR EACH ROW EXECUTE FUNCTION public.fn_activity_trigger();

CREATE TRIGGER trg_activity_hearings
  AFTER INSERT ON public.matter_hearings
  FOR EACH ROW EXECUTE FUNCTION public.fn_activity_trigger();

CREATE TRIGGER trg_activity_entities
  AFTER INSERT ON public.matter_entities
  FOR EACH ROW EXECUTE FUNCTION public.fn_activity_trigger();

CREATE TRIGGER trg_activity_reports
  AFTER UPDATE OF status ON public.daily_reports
  FOR EACH ROW EXECUTE FUNCTION public.fn_activity_trigger();

CREATE TRIGGER trg_activity_documents
  AFTER INSERT ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.fn_activity_trigger();

CREATE TRIGGER trg_activity_diary
  AFTER INSERT ON public.diary_events
  FOR EACH ROW EXECUTE FUNCTION public.fn_activity_trigger();

CREATE TRIGGER trg_activity_intercom
  AFTER INSERT ON public.intercom_threads
  FOR EACH ROW EXECUTE FUNCTION public.fn_activity_trigger();

CREATE TRIGGER trg_activity_users
  AFTER INSERT ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.fn_activity_trigger();



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 019_notification_triggers.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 019: Notification Trigger System
-- Generates in-app notifications for key firm events.
-- Internal only — no email, no SMS in V1.
-- SECURITY DEFINER: bypasses RLS to write notifications for others.
-- ═══════════════════════════════════════════════════════════════

-- ─── Helper: insert a single notification ─────────────────────
CREATE OR REPLACE FUNCTION public.fn_insert_notification(
  p_trigger_code TEXT,
  p_recipient_id UUID,
  p_actor_id     UUID,
  p_table        TEXT,
  p_target_id    UUID,
  p_label        TEXT,
  p_message      TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_trigger_id UUID;
BEGIN
  SELECT id INTO v_trigger_id
  FROM public.notification_triggers
  WHERE trigger_code = p_trigger_code AND is_active = TRUE;

  IF v_trigger_id IS NULL THEN RETURN; END IF;

  -- Do not notify the actor of their own action
  IF p_recipient_id IS NULL OR p_recipient_id = COALESCE(p_actor_id, gen_random_uuid()) THEN
    RETURN;
  END IF;

  INSERT INTO public.notifications (
    trigger_id, recipient_id, actor_id,
    target_table, target_id, target_label, message
  ) VALUES (
    v_trigger_id, p_recipient_id, p_actor_id,
    p_table, p_target_id, p_label, p_message
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_insert_notification(TEXT,UUID,UUID,TEXT,UUID,TEXT,TEXT) TO authenticated;

-- ─── Matter assignment notification ───────────────────────────
CREATE OR REPLACE FUNCTION public.fn_notify_matter_assignment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.assigned_to IS DISTINCT FROM NEW.assigned_to THEN

    -- Notify the newly assigned member
    IF NEW.assigned_to IS NOT NULL THEN
      PERFORM public.fn_insert_notification(
        'MATTER_ASSIGNED', NEW.assigned_to, auth.uid(),
        'matters', NEW.id, NEW.reference_number,
        'You have been assigned to matter ' || NEW.reference_number || ': ' || NEW.title
      );
    END IF;

    -- Notify the previously assigned member of reassignment
    IF OLD.assigned_to IS NOT NULL THEN
      PERFORM public.fn_insert_notification(
        'MATTER_REASSIGNED', OLD.assigned_to, auth.uid(),
        'matters', NEW.id, NEW.reference_number,
        'Matter ' || NEW.reference_number || ' has been reassigned'
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_matter_assignment ON public.matters;
CREATE TRIGGER trg_notify_matter_assignment
  AFTER UPDATE OF assigned_to ON public.matters
  FOR EACH ROW EXECUTE FUNCTION public.fn_notify_matter_assignment();

-- ─── Matter status change notification ────────────────────────
CREATE OR REPLACE FUNCTION public.fn_notify_matter_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_status_label TEXT;
BEGIN
  IF OLD.matter_status_id IS DISTINCT FROM NEW.matter_status_id
     AND NEW.assigned_to IS NOT NULL THEN

    SELECT label INTO v_status_label
    FROM public.matter_statuses WHERE id = NEW.matter_status_id;

    PERFORM public.fn_insert_notification(
      'MATTER_STATUS_CHANGED', NEW.assigned_to, auth.uid(),
      'matters', NEW.id, NEW.reference_number,
      'Matter ' || NEW.reference_number || ' status changed to ' || COALESCE(v_status_label, 'unknown')
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_matter_status ON public.matters;
CREATE TRIGGER trg_notify_matter_status
  AFTER UPDATE OF matter_status_id ON public.matters
  FOR EACH ROW EXECUTE FUNCTION public.fn_notify_matter_status();

-- ─── Report reviewed notification ─────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_notify_report_reviewed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.status != NEW.status AND NEW.status IN ('reviewed', 'returned') THEN
    PERFORM public.fn_insert_notification(
      'REPORT_REVIEWED', NEW.submitted_by, auth.uid(),
      'daily_reports', NEW.id, NEW.reference_number,
      CASE NEW.status
        WHEN 'reviewed' THEN 'Your report ' || NEW.reference_number || ' has been reviewed'
        WHEN 'returned' THEN 'Your report ' || NEW.reference_number || ' was returned for correction'
      END
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_report_reviewed ON public.daily_reports;
CREATE TRIGGER trg_notify_report_reviewed
  AFTER UPDATE OF status ON public.daily_reports
  FOR EACH ROW EXECUTE FUNCTION public.fn_notify_report_reviewed();

-- ─── Mandatory announcement notification ──────────────────────
CREATE OR REPLACE FUNCTION public.fn_notify_mandatory_announcement()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member RECORD;
BEGIN
  IF TG_OP = 'INSERT' AND NEW.is_mandatory = TRUE THEN
    FOR v_member IN
      SELECT id FROM public.users WHERE status = 'active'
    LOOP
      PERFORM public.fn_insert_notification(
        'INTERCOM_MANDATORY', v_member.id, auth.uid(),
        'intercom_threads', NEW.id, NEW.title,
        'Mandatory notice: ' || NEW.title
      );
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_mandatory ON public.intercom_threads;
CREATE TRIGGER trg_notify_mandatory
  AFTER INSERT ON public.intercom_threads
  FOR EACH ROW EXECUTE FUNCTION public.fn_notify_mandatory_announcement();

-- ─── Diary event member notification ──────────────────────────
CREATE OR REPLACE FUNCTION public.fn_notify_diary_event_member()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_title TEXT;
BEGIN
  SELECT title INTO v_event_title FROM public.diary_events WHERE id = NEW.event_id;
  PERFORM public.fn_insert_notification(
    'DIARY_EVENT_CREATED', NEW.user_id, auth.uid(),
    'diary_events', NEW.event_id, v_event_title,
    'You have been added to event: ' || COALESCE(v_event_title, 'diary event')
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_diary_member ON public.diary_event_members;
CREATE TRIGGER trg_notify_diary_member
  AFTER INSERT ON public.diary_event_members
  FOR EACH ROW EXECUTE FUNCTION public.fn_notify_diary_event_member();

-- ─── Role change notification ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_notify_role_changed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.role IS DISTINCT FROM NEW.role THEN
    PERFORM public.fn_insert_notification(
      'MEMBER_ROLE_CHANGED', NEW.id, auth.uid(),
      'users', NEW.id, NEW.name,
      'Your system role has been changed to ' || NEW.role::TEXT
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_role_change ON public.users;
CREATE TRIGGER trg_notify_role_change
  AFTER UPDATE OF role ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.fn_notify_role_changed();



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 020_rls_policies.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 020: Row Level Security Policies
-- ───────────────────────────────────────────────────────────────
-- DESIGN PRINCIPLE:
--   RLS enforces AUTHORITY, not VISIBILITY.
--   All authenticated users may SELECT all active operational records.
--   Write operations are restricted by role and record ownership.
-- ───────────────────────────────────────────────────────────────
-- PREREQUISITE: migration 015 must be applied first (get_user_role).
-- ═══════════════════════════════════════════════════════════════

-- ─── Enable RLS on all operational tables ─────────────────────
ALTER TABLE public.users                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matters                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matter_types               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matter_statuses            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matter_litigation_details  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matter_non_lit_details     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matter_entities            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matter_notes               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matter_hearings            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.matter_assignments         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_reports              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_report_items         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.diary_events               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.diary_event_members        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_versions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_tag_map           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.intercom_threads           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.intercom_messages          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_feed              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tags                       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.templates                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_settings            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_categories        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_triggers      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.backups                    ENABLE ROW LEVEL SECURITY;

-- ═══════════════════════════════════════════════════════════════
-- LOOKUP TABLES (read-only for all authenticated users)
-- ═══════════════════════════════════════════════════════════════
CREATE POLICY lookups_select ON public.matter_types FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY lookups_select_ms ON public.matter_statuses FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY lookups_select_dc ON public.document_categories FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY lookups_select_nt ON public.notification_triggers FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY lookups_select_tags ON public.tags FOR SELECT TO authenticated USING (TRUE);

-- Only admins manage lookups
CREATE POLICY lookups_insert_admin ON public.matter_types FOR INSERT TO authenticated
  WITH CHECK (get_user_role() = 'administrator');
CREATE POLICY lookups_update_admin ON public.matter_types FOR UPDATE TO authenticated
  USING (get_user_role() = 'administrator');

-- ═══════════════════════════════════════════════════════════════
-- USERS
-- ═══════════════════════════════════════════════════════════════
-- All members see all active users (member directory transparency)
CREATE POLICY users_select_all ON public.users
  FOR SELECT TO authenticated USING (TRUE);

-- Users may update their own profile fields
CREATE POLICY users_update_own ON public.users
  FOR UPDATE TO authenticated USING (auth.uid() = id);

-- Administrators may update any user (role changes, deactivation)
CREATE POLICY users_update_admin ON public.users
  FOR UPDATE TO authenticated USING (get_user_role() = 'administrator');

-- Only administrators create new user records
CREATE POLICY users_insert_admin ON public.users
  FOR INSERT TO authenticated WITH CHECK (get_user_role() = 'administrator');

-- ═══════════════════════════════════════════════════════════════
-- MATTERS
-- ═══════════════════════════════════════════════════════════════
-- All authenticated users see active (non-archived) matters
CREATE POLICY matters_select_active ON public.matters
  FOR SELECT TO authenticated
  USING (is_archived = FALSE);

-- Partners and Administrators see archived matters
CREATE POLICY matters_select_archived ON public.matters
  FOR SELECT TO authenticated
  USING (is_archived = TRUE AND get_user_role() IN ('administrator', 'partner'));

-- All authenticated users may create matters
CREATE POLICY matters_insert ON public.matters
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);

-- Members may edit only their own matters (not archived, not closed)
CREATE POLICY matters_update_own ON public.matters
  FOR UPDATE TO authenticated
  USING (
    auth.uid() = created_by
    AND get_user_role() = 'member'
    AND is_archived = FALSE
  );

-- Partners and Administrators may edit any matter
CREATE POLICY matters_update_authority ON public.matters
  FOR UPDATE TO authenticated
  USING (get_user_role() IN ('administrator', 'partner'));

-- ═══════════════════════════════════════════════════════════════
-- MATTER EXTENSION TABLES
-- ═══════════════════════════════════════════════════════════════
-- Litigation details
CREATE POLICY mld_select ON public.matter_litigation_details
  FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY mld_insert ON public.matter_litigation_details
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY mld_update ON public.matter_litigation_details
  FOR UPDATE TO authenticated USING (auth.uid() IS NOT NULL);

-- Non-litigation details
CREATE POLICY mnld_select ON public.matter_non_lit_details
  FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY mnld_insert ON public.matter_non_lit_details
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY mnld_update ON public.matter_non_lit_details
  FOR UPDATE TO authenticated USING (auth.uid() IS NOT NULL);

-- ═══════════════════════════════════════════════════════════════
-- MATTER ENTITIES
-- ═══════════════════════════════════════════════════════════════
CREATE POLICY me_select ON public.matter_entities
  FOR SELECT TO authenticated USING (TRUE);

CREATE POLICY me_insert ON public.matter_entities
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

-- Only Partner/Admin can archive entities
CREATE POLICY me_update ON public.matter_entities
  FOR UPDATE TO authenticated
  USING (get_user_role() IN ('administrator', 'partner')
         OR auth.uid() = created_by);

-- ═══════════════════════════════════════════════════════════════
-- MATTER NOTES
-- ═══════════════════════════════════════════════════════════════
CREATE POLICY mn_select ON public.matter_notes
  FOR SELECT TO authenticated USING (is_archived = FALSE);

CREATE POLICY mn_insert ON public.matter_notes
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

-- Members edit only their own notes (not yet reviewed)
CREATE POLICY mn_update_own ON public.matter_notes
  FOR UPDATE TO authenticated
  USING (auth.uid() = created_by AND get_user_role() = 'member' AND is_reviewed = FALSE);

-- Partners and Admins can edit/review/archive any note
CREATE POLICY mn_update_authority ON public.matter_notes
  FOR UPDATE TO authenticated
  USING (get_user_role() IN ('administrator', 'partner'));

-- ═══════════════════════════════════════════════════════════════
-- MATTER HEARINGS
-- ═══════════════════════════════════════════════════════════════
CREATE POLICY mh_select ON public.matter_hearings
  FOR SELECT TO authenticated USING (is_archived = FALSE);

CREATE POLICY mh_insert ON public.matter_hearings
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

-- Only Partner/Admin can update/archive existing hearings
CREATE POLICY mh_update ON public.matter_hearings
  FOR UPDATE TO authenticated
  USING (get_user_role() IN ('administrator', 'partner'));

-- ═══════════════════════════════════════════════════════════════
-- MATTER ASSIGNMENTS (append-only)
-- ═══════════════════════════════════════════════════════════════
CREATE POLICY ma_select ON public.matter_assignments
  FOR SELECT TO authenticated USING (TRUE);

CREATE POLICY ma_insert ON public.matter_assignments
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);
-- No UPDATE or DELETE policy — append-only table

-- ═══════════════════════════════════════════════════════════════
-- DAILY REPORTS
-- ═══════════════════════════════════════════════════════════════
-- All members see all reports (firm-wide transparency)
CREATE POLICY dr_select ON public.daily_reports
  FOR SELECT TO authenticated USING (is_archived = FALSE);

-- Users submit only their own reports
CREATE POLICY dr_insert ON public.daily_reports
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = submitted_by);

-- Members edit their own draft reports only
CREATE POLICY dr_update_own ON public.daily_reports
  FOR UPDATE TO authenticated
  USING (auth.uid() = submitted_by AND status = 'draft');

-- Partners/Admin review, return, and archive reports
CREATE POLICY dr_update_authority ON public.daily_reports
  FOR UPDATE TO authenticated
  USING (get_user_role() IN ('administrator', 'partner'));

-- Report items follow parent report ownership
CREATE POLICY dri_select ON public.daily_report_items
  FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY dri_insert ON public.daily_report_items
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY dri_update ON public.daily_report_items
  FOR UPDATE TO authenticated USING (auth.uid() = created_by
    OR get_user_role() IN ('administrator', 'partner'));

-- ═══════════════════════════════════════════════════════════════
-- LEGAL DIARY
-- ═══════════════════════════════════════════════════════════════
CREATE POLICY de_select ON public.diary_events
  FOR SELECT TO authenticated USING (is_archived = FALSE);

CREATE POLICY de_insert ON public.diary_events
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY de_update_own ON public.diary_events
  FOR UPDATE TO authenticated
  USING (auth.uid() = created_by AND get_user_role() = 'member');

CREATE POLICY de_update_authority ON public.diary_events
  FOR UPDATE TO authenticated
  USING (get_user_role() IN ('administrator', 'partner'));

CREATE POLICY dem_select ON public.diary_event_members
  FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY dem_insert ON public.diary_event_members
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY dem_delete ON public.diary_event_members
  FOR DELETE TO authenticated
  USING (get_user_role() IN ('administrator', 'partner'));

-- ═══════════════════════════════════════════════════════════════
-- DOCUMENTS
-- ═══════════════════════════════════════════════════════════════
CREATE POLICY doc_select ON public.documents
  FOR SELECT TO authenticated USING (is_archived = FALSE);

CREATE POLICY doc_insert ON public.documents
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY doc_update_own ON public.documents
  FOR UPDATE TO authenticated
  USING (auth.uid() = uploaded_by AND get_user_role() = 'member');

CREATE POLICY doc_update_authority ON public.documents
  FOR UPDATE TO authenticated
  USING (get_user_role() IN ('administrator', 'partner'));

CREATE POLICY dv_select  ON public.document_versions FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY dv_insert  ON public.document_versions FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY dtm_select ON public.document_tag_map  FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY dtm_insert ON public.document_tag_map  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY dtm_delete ON public.document_tag_map  FOR DELETE TO authenticated
  USING (auth.uid() = created_by OR get_user_role() IN ('administrator', 'partner'));

-- ═══════════════════════════════════════════════════════════════
-- INTERCOM
-- ═══════════════════════════════════════════════════════════════
CREATE POLICY it_select ON public.intercom_threads
  FOR SELECT TO authenticated USING (is_archived = FALSE);

CREATE POLICY it_insert ON public.intercom_threads
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY it_update_own ON public.intercom_threads
  FOR UPDATE TO authenticated
  USING (auth.uid() = created_by AND get_user_role() = 'member');

CREATE POLICY it_update_authority ON public.intercom_threads
  FOR UPDATE TO authenticated
  USING (get_user_role() IN ('administrator', 'partner'));

CREATE POLICY im_select ON public.intercom_messages
  FOR SELECT TO authenticated USING (is_archived = FALSE);

CREATE POLICY im_insert ON public.intercom_messages
  FOR INSERT TO authenticated WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY im_update_own ON public.intercom_messages
  FOR UPDATE TO authenticated
  USING (auth.uid() = created_by AND get_user_role() = 'member');

CREATE POLICY im_update_authority ON public.intercom_messages
  FOR UPDATE TO authenticated
  USING (get_user_role() IN ('administrator', 'partner'));

-- ═══════════════════════════════════════════════════════════════
-- NOTIFICATIONS
-- ═══════════════════════════════════════════════════════════════
-- Users see only their own notifications
CREATE POLICY notif_select ON public.notifications
  FOR SELECT TO authenticated USING (recipient_id = auth.uid());

-- Users mark only their own notifications as read
CREATE POLICY notif_update_own ON public.notifications
  FOR UPDATE TO authenticated USING (recipient_id = auth.uid());

-- INSERT only via SECURITY DEFINER trigger (fn_insert_notification)
-- No client INSERT policy needed

-- ═══════════════════════════════════════════════════════════════
-- ACTIVITY FEED
-- ═══════════════════════════════════════════════════════════════
-- All authenticated users see the firm activity feed
CREATE POLICY af_select ON public.activity_feed
  FOR SELECT TO authenticated USING (TRUE);
-- INSERT only via SECURITY DEFINER trigger

-- ═══════════════════════════════════════════════════════════════
-- AUDIT LOGS
-- ═══════════════════════════════════════════════════════════════
-- Only Administrators may read audit logs
CREATE POLICY al_select ON public.audit_logs
  FOR SELECT TO authenticated
  USING (get_user_role() = 'administrator');
-- INSERT only via SECURITY DEFINER trigger
-- No UPDATE or DELETE — enforced by absence of policies

-- ═══════════════════════════════════════════════════════════════
-- SETTINGS & ADMIN
-- ═══════════════════════════════════════════════════════════════
CREATE POLICY ss_select ON public.system_settings FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY ss_update ON public.system_settings FOR UPDATE TO authenticated
  USING (get_user_role() = 'administrator');

CREATE POLICY tmpl_select ON public.templates FOR SELECT TO authenticated USING (is_archived = FALSE);
CREATE POLICY tmpl_insert ON public.templates FOR INSERT TO authenticated
  WITH CHECK (get_user_role() IN ('administrator', 'partner'));
CREATE POLICY tmpl_update ON public.templates FOR UPDATE TO authenticated
  USING (get_user_role() IN ('administrator', 'partner'));

CREATE POLICY bk_select ON public.backups FOR SELECT TO authenticated
  USING (get_user_role() = 'administrator');
CREATE POLICY bk_insert ON public.backups FOR INSERT TO authenticated
  WITH CHECK (get_user_role() = 'administrator');



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 021_activity_feed_actor_nullable.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 021: Make activity_feed.actor_id nullable
-- ───────────────────────────────────────────────────────────────
-- Patch for already-deployed databases where 014 created actor_id
-- as NOT NULL. System-generated events (bootstrap user creation,
-- scheduled jobs, future automated processes) have no human actor
-- and auth.uid() correctly returns NULL for them — the schema must
-- allow that instead of raising a NOT NULL violation.
-- Safe to run on a fresh deployment too (idempotent no-op if the
-- column is already nullable).
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.activity_feed
  ALTER COLUMN actor_id DROP NOT NULL;



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 022_audit_logs_performed_by_nullable.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 022: Make audit_logs.performed_by nullable
-- ───────────────────────────────────────────────────────────────
-- Patch for already-deployed databases. Mirrors migration 021
-- (activity_feed.actor_id). Genuine system/bootstrap actions have
-- no auth.uid() session and therefore no real performed_by value.
-- The previous design used a placeholder zero-UUID, but that UUID
-- must still satisfy the FK to users(id), which it never does —
-- trading a NOT NULL violation for an FK violation. NULL is the
-- honest, constraint-safe representation.
--
-- Because audit_logs is partitioned, the NOT NULL constraint must
-- be dropped on the parent table; this propagates to all existing
-- and future partitions automatically.
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.audit_logs
  ALTER COLUMN performed_by DROP NOT NULL;



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 023_matter_assignment_lifecycle.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 023: Matter Assignment Lifecycle (Sprint 1)
-- ───────────────────────────────────────────────────────────────
-- Makes matter_assignments a fully DB-owned, deterministic workflow:
--   1. Creating a matter automatically creates its first assignment row.
--   2. Reassigning a matter (changing assigned_to) archives the
--      previous active assignment and inserts a new one — never an
--      UPDATE of assignment data itself, preserving full history.
--   3. Both actions write to audit_logs and activity_feed directly,
--      with human-readable messages.
--
-- The frontend NEVER writes to matter_assignments directly as of this
-- migration — see src/services/matters.service.ts comments. This is
-- the single source of truth for assignment history.
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Schema addition: archived_at pointer ──────────────────────
-- NULL archived_at = currently active assignment for that matter.
-- Non-NULL = historical record, superseded by a later assignment.
-- This is additive only — existing columns (assigned_to, assigned_by,
-- assigned_at, reason) are unchanged; no rename, no data migration
-- needed for already-inserted rows (they remain NULL = active, which
-- is the correct default interpretation for pre-Sprint-1 data).
ALTER TABLE public.matter_assignments
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_ma_active
  ON public.matter_assignments(matter_id)
  WHERE archived_at IS NULL;

COMMENT ON COLUMN public.matter_assignments.archived_at IS
  'NULL = this is the current active assignment for the matter. '
  'Non-NULL = superseded by a later reassignment. Never deleted.';

-- ─── 2. Auto-create assignment on matter creation ─────────────────
CREATE OR REPLACE FUNCTION public.fn_matter_assignment_auto_create()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner UUID;
BEGIN
  -- Prefer the explicitly assigned member; fall back to the creator
  -- if no assignee was set at creation time (e.g. a Member creates a
  -- matter for themselves without picking an "Assigned Member").
  v_owner := COALESCE(NEW.assigned_to, NEW.created_by);

  IF v_owner IS NOT NULL THEN
    INSERT INTO public.matter_assignments (
      matter_id, assigned_to, assigned_by, assigned_at, reason
    ) VALUES (
      NEW.id, v_owner, NEW.created_by, now(), 'Initial assignment on creation'
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_matter_assignment_auto_create ON public.matters;
CREATE TRIGGER trg_matter_assignment_auto_create
  AFTER INSERT ON public.matters
  FOR EACH ROW EXECUTE FUNCTION public.fn_matter_assignment_auto_create();

-- ─── 3. Reassignment function ──────────────────────────────────────
-- Archives the current active assignment row and inserts a new one.
-- Writes directly to audit_logs and activity_feed (these are
-- assignment-specific messages that don't fit the generic shared
-- fn_audit_trigger/fn_activity_trigger branch structure, since
-- matter_assignments has no is_archived boolean — it uses the
-- archived_at timestamp pointer model instead).
CREATE OR REPLACE FUNCTION public.fn_matter_reassign(
  p_matter_id UUID,
  p_user_id   UUID,
  p_actor     UUID,
  p_reason    TEXT DEFAULT 'Reassignment'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_id        UUID;
  v_matter_ref    TEXT;
  v_old_user_name TEXT;
  v_new_user_name TEXT;
  v_actor_name    TEXT;
  v_actor_role    TEXT;
  v_matter_creator UUID;
BEGIN
  -- Authorization check: mirrors the COMBINED effect of the two RLS
  -- policies that already govern direct assigned_to edits on matters
  -- (migration 020): matters_update_authority allows Partner/Admin to
  -- edit any matter, and matters_update_own allows a Member to edit
  -- (including reassign) a matter THEY created. This check must match
  -- both, not just the Partner/Admin half — otherwise a Member who is
  -- legitimately allowed to reassign their own matter via the normal
  -- edit form would be rejected here, which would be a behavior
  -- regression introduced by this function, not a deliberate RLS
  -- tightening (which the Sprint 1 spec explicitly says not to do).
  SELECT role::TEXT INTO v_actor_role FROM public.users WHERE id = p_actor;
  SELECT created_by INTO v_matter_creator FROM public.matters WHERE id = p_matter_id;

  IF NOT (
    v_actor_role IN ('administrator', 'partner')
    OR (v_actor_role = 'member' AND p_actor = v_matter_creator)
  ) THEN
    RAISE EXCEPTION 'Not authorized to reassign this matter (actor role: %)', COALESCE(v_actor_role, 'unknown');
  END IF;

  -- Archive the current active assignment, if one exists.
  -- (A matter may have none yet if assigned_to was NULL on creation
  -- and remained NULL until now — this UPDATE then simply affects 0 rows.)
  UPDATE public.matter_assignments
  SET archived_at = now()
  WHERE matter_id = p_matter_id
    AND archived_at IS NULL;

  -- Insert the new active assignment row.
  INSERT INTO public.matter_assignments (
    matter_id, assigned_to, assigned_by, assigned_at, reason
  ) VALUES (
    p_matter_id, p_user_id, p_actor, now(), p_reason
  )
  RETURNING id INTO v_new_id;

  -- Keep matters.assigned_to in sync with the new active assignment.
  -- This makes fn_matter_reassign() safely callable two ways:
  --   (a) directly as an RPC from the frontend/admin tooling — in which
  --       case this UPDATE is the ONLY thing that changes assigned_to,
  --       and IS exactly what's needed.
  --   (b) via trg_matter_reassignment_dispatch, which fires AFTER
  --       assigned_to was already changed by the original UPDATE.
  --
  -- IMPORTANT — how the recursion guard actually works:
  -- PostgreSQL's "AFTER UPDATE OF column" fires based on whether that
  -- column appears in the UPDATE's SET list for a row that gets
  -- touched — NOT based on whether the value is actually different
  -- (e.g. "SET x = x" DOES fire an "OF x" trigger). The guard below is
  -- NOT relying on "same value = no fire". It relies on the WHERE
  -- clause: when assigned_to already equals p_user_id, the WHERE
  -- condition excludes the row from the UPDATE entirely (0 rows
  -- matched), so there is no row for ANY trigger to fire on — the
  -- statement runs but touches nothing. This is what actually
  -- prevents the infinite loop, not value-comparison semantics on
  -- PostgreSQL's part.
  UPDATE public.matters
  SET assigned_to = p_user_id
  WHERE id = p_matter_id
    AND assigned_to IS DISTINCT FROM p_user_id;

  -- Gather human-readable context for audit/activity messages.
  SELECT reference_number INTO v_matter_ref FROM public.matters WHERE id = p_matter_id;
  SELECT name INTO v_new_user_name FROM public.users WHERE id = p_user_id;
  SELECT name INTO v_actor_name    FROM public.users WHERE id = p_actor;
  v_actor_name := COALESCE(v_actor_name, 'System');

  -- audit_logs: full before/after snapshot for compliance record.
  INSERT INTO public.audit_logs (
    action_type, module, target_table, target_id, target_label,
    performed_by, performed_at, before_snapshot, after_snapshot
  ) VALUES (
    'RECORD_UPDATED',
    'cause_list',
    'matter_assignments',
    v_new_id,
    COALESCE(v_matter_ref, p_matter_id::TEXT),
    p_actor,
    now(),
    jsonb_build_object('matter_id', p_matter_id, 'event', 'reassignment_requested'),
    jsonb_build_object('matter_id', p_matter_id, 'new_assignment_id', v_new_id, 'assigned_to', p_user_id, 'reason', p_reason)
  );

  -- activity_feed: human-readable message for the Dashboard.
  INSERT INTO public.activity_feed (
    event_type, module, actor_id, target_table, target_id, target_label, message
  ) VALUES (
    'MATTER_ASSIGNED',
    'cause_list',
    p_actor,
    'matters',
    p_matter_id,
    COALESCE(v_matter_ref, p_matter_id::TEXT),
    v_actor_name || ' reassigned ' || COALESCE(v_matter_ref, 'a matter') ||
      ' to ' || COALESCE(v_new_user_name, 'a member')
  );

  RETURN v_new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_matter_reassign(UUID, UUID, UUID, TEXT) TO authenticated;

-- ─── 4. Trigger: detect assigned_to change on matters UPDATE ──────
-- Calls fn_matter_reassign() automatically whenever assigned_to
-- changes via a normal UPDATE on matters (which is exactly what the
-- frontend's updateMatter() already does — no new frontend code needed).
CREATE OR REPLACE FUNCTION public.fn_matter_reassignment_dispatch()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.assigned_to IS DISTINCT FROM NEW.assigned_to AND NEW.assigned_to IS NOT NULL THEN
    PERFORM public.fn_matter_reassign(
      NEW.id,
      NEW.assigned_to,
      COALESCE(auth.uid(), NEW.updated_by),
      'Reassignment'
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_matter_reassignment_dispatch ON public.matters;
CREATE TRIGGER trg_matter_reassignment_dispatch
  AFTER UPDATE OF assigned_to ON public.matters
  FOR EACH ROW EXECUTE FUNCTION public.fn_matter_reassignment_dispatch();

-- ─── 5. RLS: no change needed ──────────────────────────────────────
-- matter_assignments remains append-only from the client's perspective:
-- ma_select (SELECT, all authenticated) and ma_insert (INSERT, all
-- authenticated) already exist from migration 020. No client-facing
-- UPDATE policy is added — the archived_at UPDATE inside
-- fn_matter_reassign() runs as SECURITY DEFINER, bypassing RLS
-- entirely, exactly like fn_audit_trigger and fn_activity_trigger do.
-- This keeps "no client UPDATE path to matter_assignments" true at
-- the database level, not just by frontend convention.
--
-- Note: fn_matter_reassign()'s sync write to matters.assigned_to also
-- runs under this same SECURITY DEFINER context, so it bypasses the
-- matters_update_own / matters_update_authority RLS policies from
-- migration 020 at the database-permission level. This is mitigated
-- by the explicit authorization check at the top of fn_matter_reassign()
-- (see Section 3 above), which re-implements the combined effect of
-- both policies in application logic: Partner/Admin may reassign any
-- matter, a Member may reassign only a matter they created. Keep that
-- check in sync with migration 020 if either changes — RLS itself is
-- the source of truth for "what should be allowed"; this function's
-- check is a deliberate, documented re-implementation of it, made
-- necessary because SECURITY DEFINER functions don't inherit caller
-- RLS automatically.



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 024_remove_duplicate_assignment_activity.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 024: Remove duplicate MATTER_ASSIGNED activity entry
-- ───────────────────────────────────────────────────────────────
-- BUG FOUND DURING LIVE SPRINT 1 VERIFICATION:
-- fn_activity_trigger() (migration 018) already had a branch that
-- detects assigned_to changes on matters UPDATE and writes its own
-- generic "<actor> assigned <ref> to <member>" activity_feed entry.
-- Migration 023 added fn_matter_reassign(), which ALSO detects this
-- exact same change (via trg_matter_reassignment_dispatch) and writes
-- a more specific "<actor> reassigned <ref> to <member>" entry, plus
-- a dedicated audit_logs entry targeting matter_assignments.
--
-- Both triggers fire on the same matters UPDATE, so every reassignment
-- now produces TWO MATTER_ASSIGNED activity_feed rows with the same
-- timestamp — confirmed live: "assigned TEST-ASSIGN-001 to Test Member"
-- and "reassigned TEST-ASSIGN-001 to Test Member" both appeared for one
-- single UPDATE statement.
--
-- FIX: remove the assigned_to branch from the generic fn_activity_trigger()
-- entirely. fn_matter_reassign() is now the single authoritative source
-- of MATTER_ASSIGNED activity_feed entries — it has access to richer
-- context (the assignment row, audit trail) than the generic function
-- ever did, and was always the more correct place for this logic to live.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_activity_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new            JSONB := to_jsonb(NEW);
  v_old            JSONB := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END;

  v_actor_name     TEXT;
  v_event_type     activity_event_type;
  v_module         TEXT;
  v_label          TEXT;
  v_message        TEXT;
  v_type_code      TEXT;
  v_status_label   TEXT;
  v_matter_ref     TEXT;
  v_new_id         UUID := NEW.id;

  v_new_status     TEXT := v_new->>'status';
  v_old_status     TEXT := v_old->>'status';
  v_new_is_archived TEXT := v_new->>'is_archived';
  v_old_is_archived TEXT := v_old->>'is_archived';
  v_new_status_id   TEXT := v_new->>'matter_status_id';
  v_old_status_id   TEXT := v_old->>'matter_status_id';
  v_new_thread_type TEXT := v_new->>'thread_type';
BEGIN
  -- Fetch actor name for human-readable messages
  SELECT name INTO v_actor_name FROM public.users WHERE id = auth.uid();
  v_actor_name := COALESCE(v_actor_name, 'System');

  -- ── matters ───────────────────────────────────────────────
  IF TG_TABLE_NAME = 'matters' THEN
    SELECT type_code::TEXT INTO v_type_code
    FROM public.matter_types WHERE id = (v_new->>'matter_type_id')::UUID;

    v_module := CASE COALESCE(v_type_code, '')
      WHEN 'litigation' THEN 'cause_list'
      ELSE 'non_litigation'
    END;
    v_label := v_new->>'reference_number';

    IF TG_OP = 'INSERT' THEN
      v_event_type := 'MATTER_CREATED';
      v_message    := v_actor_name || ' created matter ' || (v_new->>'reference_number');

    ELSIF TG_OP = 'UPDATE' THEN
      IF v_old_is_archived = 'false' AND v_new_is_archived = 'true' THEN
        v_event_type := 'MATTER_ARCHIVED';
        v_message    := v_actor_name || ' archived matter ' || (v_new->>'reference_number');

      ELSIF v_old_is_archived = 'true' AND v_new_is_archived = 'false' THEN
        v_event_type := 'MATTER_RESTORED';
        v_message    := v_actor_name || ' restored matter ' || (v_new->>'reference_number');

      -- NOTE (migration 024): the assigned_to branch that used to live
      -- here was REMOVED. fn_matter_reassign() (migration 023) is now
      -- the single authoritative source of MATTER_ASSIGNED activity
      -- entries, reached via trg_matter_reassignment_dispatch. Leaving
      -- a duplicate detection here produced two activity_feed rows per
      -- reassignment — confirmed in live testing. A matters UPDATE
      -- that ONLY changes assigned_to (no status/archive change) now
      -- correctly falls through to the generic MATTER_UPDATED message
      -- below, while fn_matter_reassign() separately writes the richer
      -- MATTER_ASSIGNED entry. This is intentional, not a regression:
      -- the matter itself was also genuinely "updated" in the sense
      -- that updated_by/updated_at changed, so MATTER_UPDATED is still
      -- an accurate (if generic) description of what fn_activity_trigger
      -- itself directly observed.

      ELSIF v_old_status_id IS DISTINCT FROM v_new_status_id THEN
        SELECT label INTO v_status_label FROM public.matter_statuses WHERE id = v_new_status_id::UUID;
        v_event_type := 'MATTER_STATUS_CHANGED';
        v_message    := (v_new->>'reference_number') || ' moved to ' || COALESCE(v_status_label, 'new status');

      ELSE
        v_event_type := 'MATTER_UPDATED';
        v_message    := v_actor_name || ' updated matter ' || (v_new->>'reference_number');
      END IF;
    END IF;

  -- ── matter_notes ──────────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'matter_notes' AND TG_OP = 'INSERT' THEN
    SELECT reference_number INTO v_matter_ref FROM public.matters WHERE id = (v_new->>'matter_id')::UUID;
    v_event_type := 'NOTE_ADDED';
    v_module     := 'cause_list';
    v_label      := COALESCE(v_matter_ref, 'matter');
    v_message    := v_actor_name || ' added a note to ' || COALESCE(v_matter_ref, 'a matter');

  -- ── matter_hearings ───────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'matter_hearings' AND TG_OP = 'INSERT' THEN
    SELECT reference_number INTO v_matter_ref FROM public.matters WHERE id = (v_new->>'matter_id')::UUID;
    v_event_type := 'HEARING_ADDED';
    v_module     := 'cause_list';
    v_label      := COALESCE(v_matter_ref, 'matter');
    v_message    := v_actor_name || ' added a hearing to ' || COALESCE(v_matter_ref, 'a matter')
                 || ' on ' || to_char((v_new->>'hearing_date')::TIMESTAMPTZ, 'DD Mon YYYY');

  -- ── matter_entities ───────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'matter_entities' AND TG_OP = 'INSERT' THEN
    SELECT reference_number INTO v_matter_ref FROM public.matters WHERE id = (v_new->>'matter_id')::UUID;
    v_event_type := 'ENTITY_ADDED';
    v_module     := 'cause_list';
    v_label      := COALESCE(v_matter_ref, 'matter');
    v_message    := v_actor_name || ' added ' || (v_new->>'name') || ' to ' || COALESCE(v_matter_ref, 'a matter');

  -- ── daily_reports ─────────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'daily_reports' AND TG_OP = 'UPDATE'
    AND v_old_status IS DISTINCT FROM v_new_status
    AND v_new_status = 'submitted' THEN
    v_event_type := 'REPORT_SUBMITTED';
    v_module     := 'daily_reports';
    v_label      := v_new->>'reference_number';
    v_message    := v_actor_name || ' submitted daily report ' || (v_new->>'reference_number');

  ELSIF TG_TABLE_NAME = 'daily_reports' AND TG_OP = 'UPDATE'
    AND v_old_status IS DISTINCT FROM v_new_status
    AND v_new_status = 'reviewed' THEN
    v_event_type := 'REPORT_REVIEWED';
    v_module     := 'daily_reports';
    v_label      := v_new->>'reference_number';
    v_message    := v_actor_name || ' reviewed daily report ' || (v_new->>'reference_number');

  -- ── documents ─────────────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'documents' AND TG_OP = 'INSERT' THEN
    v_event_type := 'DOCUMENT_UPLOADED';
    v_module     := 'documents';
    v_label      := v_new->>'reference_number';
    v_message    := v_actor_name || ' uploaded ' || (v_new->>'title');

  -- ── diary_events ──────────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'diary_events' AND TG_OP = 'INSERT' THEN
    v_event_type := 'DIARY_EVENT_CREATED';
    v_module     := 'legal_diary';
    v_label      := v_new->>'title';
    v_message    := v_actor_name || ' created diary event: ' || (v_new->>'title');

  -- ── intercom_threads ──────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'intercom_threads' AND TG_OP = 'INSERT'
    AND v_new_thread_type = 'announcement' THEN
    v_event_type := 'INTERCOM_ANNOUNCEMENT';
    v_module     := 'intercom';
    v_label      := v_new->>'title';
    v_message    := v_actor_name || ' posted announcement: ' || (v_new->>'title');

  -- ── users (new member added) ───────────────────────────────
  ELSIF TG_TABLE_NAME = 'users' AND TG_OP = 'INSERT' THEN
    v_event_type := 'MEMBER_ADDED';
    v_module     := 'members';
    v_label      := v_new->>'name';
    v_message    := 'New member ' || (v_new->>'name') || ' joined the firm';

  ELSE
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF v_event_type IS NOT NULL THEN
    INSERT INTO public.activity_feed (
      event_type, module, actor_id,
      target_table, target_id, target_label, message
    ) VALUES (
      v_event_type,
      v_module,
      auth.uid(),
      TG_TABLE_NAME,
      v_new_id,
      v_label,
      v_message
    );
  END IF;

  RETURN NEW;
END;
$$;



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 025_matter_timeline_support.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 025: Matter Timeline support
-- ───────────────────────────────────────────────────────────────
-- Sprint 2, Priority 2: Matter Timeline.
--
-- PROBLEM: activity_feed.target_id is always NEW.id of whatever row
-- fired the trigger — correct for matter-level events (MATTER_CREATED,
-- MATTER_UPDATED, MATTER_ASSIGNED, MATTER_ARCHIVED, where target_id IS
-- the matter's own id), but for child-table events it's the CHILD
-- row's id, not the parent matter's id: NOTE_ADDED targets the note's
-- own UUID, HEARING_ADDED targets the hearing's own UUID, ENTITY_ADDED
-- targets the entity's own UUID. A naive "WHERE target_id = matter_id"
-- query for a single-matter timeline would silently show ONLY the
-- matter-level events and miss every note, hearing, and entity entry
-- — an incomplete timeline with no error to signal the gap.
--
-- FIX: add a new, separate column — parent_matter_id — populated
-- explicitly per source table:
--   - matters itself:        parent_matter_id = the matter's own id
--   - matter_notes:          parent_matter_id = NEW.matter_id (NOT NULL on this table)
--   - matter_hearings:       parent_matter_id = NEW.matter_id (NOT NULL on this table)
--   - matter_entities:       parent_matter_id = NEW.matter_id (NOT NULL on this table)
--   - documents:              parent_matter_id = NEW.matter_id (NULLABLE — a document
--                              need not be linked to any matter)
--   - diary_events:           parent_matter_id = NEW.matter_id (NULLABLE — same reason)
--   - daily_reports:          parent_matter_id = NULL (no matter_id column on this table)
--   - intercom_threads:       parent_matter_id = NULL (no matter_id column on this table)
--   - users:                  parent_matter_id = NULL (no matter_id column on this table)
--
-- This makes a single-matter timeline a single indexed query:
--   SELECT * FROM activity_feed WHERE parent_matter_id = :matter_id
--   ORDER BY created_at;
-- with no joins, no per-event-type special-casing in the frontend.
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Additive column ─────────────────────────────────────────
ALTER TABLE public.activity_feed
  ADD COLUMN IF NOT EXISTS parent_matter_id UUID REFERENCES public.matters(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_af_parent_matter
  ON public.activity_feed(parent_matter_id)
  WHERE parent_matter_id IS NOT NULL;

COMMENT ON COLUMN public.activity_feed.parent_matter_id IS
  'The matter this activity entry belongs to, for the Matter Timeline view. '
  'NULL for activity unrelated to any matter (daily_reports, intercom_threads, '
  'users, and documents/diary_events not linked to a matter). Distinct from '
  'target_id, which is always the id of whichever row actually fired the '
  'trigger (a note/hearing/entity row, not the parent matter, for those events).';

-- ─── 2. fn_activity_trigger(): populate parent_matter_id ─────────
-- Full function body, identical to migration 024's version except for
-- the addition of v_parent_matter_id (declared, set per-branch, and
-- included in the final INSERT). No other logic changes.
CREATE OR REPLACE FUNCTION public.fn_activity_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new            JSONB := to_jsonb(NEW);
  v_old            JSONB := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END;

  v_actor_name     TEXT;
  v_event_type     activity_event_type;
  v_module         TEXT;
  v_label          TEXT;
  v_message        TEXT;
  v_type_code      TEXT;
  v_status_label   TEXT;
  v_matter_ref     TEXT;
  v_new_id         UUID := NEW.id;
  v_parent_matter_id UUID := NULL;

  v_new_status     TEXT := v_new->>'status';
  v_old_status     TEXT := v_old->>'status';
  v_new_is_archived TEXT := v_new->>'is_archived';
  v_old_is_archived TEXT := v_old->>'is_archived';
  v_new_status_id   TEXT := v_new->>'matter_status_id';
  v_old_status_id   TEXT := v_old->>'matter_status_id';
  v_new_thread_type TEXT := v_new->>'thread_type';
BEGIN
  -- Fetch actor name for human-readable messages
  SELECT name INTO v_actor_name FROM public.users WHERE id = auth.uid();
  v_actor_name := COALESCE(v_actor_name, 'System');

  -- ── matters ───────────────────────────────────────────────
  IF TG_TABLE_NAME = 'matters' THEN
    -- The matter IS its own parent for timeline purposes.
    v_parent_matter_id := v_new_id;

    SELECT type_code::TEXT INTO v_type_code
    FROM public.matter_types WHERE id = (v_new->>'matter_type_id')::UUID;

    v_module := CASE COALESCE(v_type_code, '')
      WHEN 'litigation' THEN 'cause_list'
      ELSE 'non_litigation'
    END;
    v_label := v_new->>'reference_number';

    IF TG_OP = 'INSERT' THEN
      v_event_type := 'MATTER_CREATED';
      v_message    := v_actor_name || ' created matter ' || (v_new->>'reference_number');

    ELSIF TG_OP = 'UPDATE' THEN
      IF v_old_is_archived = 'false' AND v_new_is_archived = 'true' THEN
        v_event_type := 'MATTER_ARCHIVED';
        v_message    := v_actor_name || ' archived matter ' || (v_new->>'reference_number');

      ELSIF v_old_is_archived = 'true' AND v_new_is_archived = 'false' THEN
        v_event_type := 'MATTER_RESTORED';
        v_message    := v_actor_name || ' restored matter ' || (v_new->>'reference_number');

      -- (migration 024 note carried forward): the assigned_to branch
      -- was intentionally removed here — fn_matter_reassign() is the
      -- single authoritative source of MATTER_ASSIGNED entries.

      ELSIF v_old_status_id IS DISTINCT FROM v_new_status_id THEN
        SELECT label INTO v_status_label FROM public.matter_statuses WHERE id = v_new_status_id::UUID;
        v_event_type := 'MATTER_STATUS_CHANGED';
        v_message    := (v_new->>'reference_number') || ' moved to ' || COALESCE(v_status_label, 'new status');

      ELSE
        v_event_type := 'MATTER_UPDATED';
        v_message    := v_actor_name || ' updated matter ' || (v_new->>'reference_number');
      END IF;
    END IF;

  -- ── matter_notes ──────────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'matter_notes' AND TG_OP = 'INSERT' THEN
    v_parent_matter_id := (v_new->>'matter_id')::UUID;
    SELECT reference_number INTO v_matter_ref FROM public.matters WHERE id = v_parent_matter_id;
    v_event_type := 'NOTE_ADDED';
    v_module     := 'cause_list';
    v_label      := COALESCE(v_matter_ref, 'matter');
    v_message    := v_actor_name || ' added a note to ' || COALESCE(v_matter_ref, 'a matter');

  -- ── matter_hearings ───────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'matter_hearings' AND TG_OP = 'INSERT' THEN
    v_parent_matter_id := (v_new->>'matter_id')::UUID;
    SELECT reference_number INTO v_matter_ref FROM public.matters WHERE id = v_parent_matter_id;
    v_event_type := 'HEARING_ADDED';
    v_module     := 'cause_list';
    v_label      := COALESCE(v_matter_ref, 'matter');
    v_message    := v_actor_name || ' added a hearing to ' || COALESCE(v_matter_ref, 'a matter')
                 || ' on ' || to_char((v_new->>'hearing_date')::TIMESTAMPTZ, 'DD Mon YYYY');

  -- ── matter_entities ───────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'matter_entities' AND TG_OP = 'INSERT' THEN
    v_parent_matter_id := (v_new->>'matter_id')::UUID;
    SELECT reference_number INTO v_matter_ref FROM public.matters WHERE id = v_parent_matter_id;
    v_event_type := 'ENTITY_ADDED';
    v_module     := 'cause_list';
    v_label      := COALESCE(v_matter_ref, 'matter');
    v_message    := v_actor_name || ' added ' || (v_new->>'name') || ' to ' || COALESCE(v_matter_ref, 'a matter');

  -- ── daily_reports ─────────────────────────────────────────
  -- No matter_id column on this table — parent_matter_id stays NULL.
  ELSIF TG_TABLE_NAME = 'daily_reports' AND TG_OP = 'UPDATE'
    AND v_old_status IS DISTINCT FROM v_new_status
    AND v_new_status = 'submitted' THEN
    v_event_type := 'REPORT_SUBMITTED';
    v_module     := 'daily_reports';
    v_label      := v_new->>'reference_number';
    v_message    := v_actor_name || ' submitted daily report ' || (v_new->>'reference_number');

  ELSIF TG_TABLE_NAME = 'daily_reports' AND TG_OP = 'UPDATE'
    AND v_old_status IS DISTINCT FROM v_new_status
    AND v_new_status = 'reviewed' THEN
    v_event_type := 'REPORT_REVIEWED';
    v_module     := 'daily_reports';
    v_label      := v_new->>'reference_number';
    v_message    := v_actor_name || ' reviewed daily report ' || (v_new->>'reference_number');

  -- ── documents ─────────────────────────────────────────────
  -- matter_id is NULLABLE here — a document need not be linked to a
  -- matter. v_parent_matter_id correctly stays NULL in that case.
  ELSIF TG_TABLE_NAME = 'documents' AND TG_OP = 'INSERT' THEN
    v_parent_matter_id := (v_new->>'matter_id')::UUID;
    v_event_type := 'DOCUMENT_UPLOADED';
    v_module     := 'documents';
    v_label      := v_new->>'reference_number';
    v_message    := v_actor_name || ' uploaded ' || (v_new->>'title');

  -- ── diary_events ──────────────────────────────────────────
  -- Same as documents: matter_id is NULLABLE, NULL is correct when absent.
  ELSIF TG_TABLE_NAME = 'diary_events' AND TG_OP = 'INSERT' THEN
    v_parent_matter_id := (v_new->>'matter_id')::UUID;
    v_event_type := 'DIARY_EVENT_CREATED';
    v_module     := 'legal_diary';
    v_label      := v_new->>'title';
    v_message    := v_actor_name || ' created diary event: ' || (v_new->>'title');

  -- ── intercom_threads ──────────────────────────────────────
  -- No matter_id column — parent_matter_id stays NULL.
  ELSIF TG_TABLE_NAME = 'intercom_threads' AND TG_OP = 'INSERT'
    AND v_new_thread_type = 'announcement' THEN
    v_event_type := 'INTERCOM_ANNOUNCEMENT';
    v_module     := 'intercom';
    v_label      := v_new->>'title';
    v_message    := v_actor_name || ' posted announcement: ' || (v_new->>'title');

  -- ── users (new member added) ───────────────────────────────
  -- No matter_id column — parent_matter_id stays NULL.
  ELSIF TG_TABLE_NAME = 'users' AND TG_OP = 'INSERT' THEN
    v_event_type := 'MEMBER_ADDED';
    v_module     := 'members';
    v_label      := v_new->>'name';
    v_message    := 'New member ' || (v_new->>'name') || ' joined the firm';

  ELSE
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF v_event_type IS NOT NULL THEN
    INSERT INTO public.activity_feed (
      event_type, module, actor_id,
      target_table, target_id, target_label, message,
      parent_matter_id
    ) VALUES (
      v_event_type,
      v_module,
      auth.uid(),
      TG_TABLE_NAME,
      v_new_id,
      v_label,
      v_message,
      v_parent_matter_id
    );
  END IF;

  RETURN NEW;
END;
$$;

-- ─── 3. fn_matter_reassign(): populate parent_matter_id too ──────
-- This function (migration 023) writes its own activity_feed entry
-- directly, bypassing fn_activity_trigger() entirely — so it needs
-- the same parent_matter_id treatment, set explicitly here rather
-- than relying on the trigger function above (which never fires for
-- matter_assignments, since that table has no audit/activity trigger
-- of its own by design — see migration 023's Section 5 commentary).
CREATE OR REPLACE FUNCTION public.fn_matter_reassign(
  p_matter_id UUID,
  p_user_id   UUID,
  p_actor     UUID,
  p_reason    TEXT DEFAULT 'Reassignment'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_id         UUID;
  v_matter_ref     TEXT;
  v_old_user_name  TEXT;
  v_new_user_name  TEXT;
  v_actor_name     TEXT;
  v_actor_role     TEXT;
  v_matter_creator UUID;
BEGIN
  SELECT role::TEXT INTO v_actor_role FROM public.users WHERE id = p_actor;
  SELECT created_by INTO v_matter_creator FROM public.matters WHERE id = p_matter_id;

  IF NOT (
    v_actor_role IN ('administrator', 'partner')
    OR (v_actor_role = 'member' AND p_actor = v_matter_creator)
  ) THEN
    RAISE EXCEPTION 'Not authorized to reassign this matter (actor role: %)', COALESCE(v_actor_role, 'unknown');
  END IF;

  UPDATE public.matter_assignments
  SET archived_at = now()
  WHERE matter_id = p_matter_id
    AND archived_at IS NULL;

  INSERT INTO public.matter_assignments (
    matter_id, assigned_to, assigned_by, assigned_at, reason
  ) VALUES (
    p_matter_id, p_user_id, p_actor, now(), p_reason
  )
  RETURNING id INTO v_new_id;

  UPDATE public.matters
  SET assigned_to = p_user_id
  WHERE id = p_matter_id
    AND assigned_to IS DISTINCT FROM p_user_id;

  SELECT reference_number INTO v_matter_ref FROM public.matters WHERE id = p_matter_id;
  SELECT name INTO v_new_user_name FROM public.users WHERE id = p_user_id;
  SELECT name INTO v_actor_name    FROM public.users WHERE id = p_actor;
  v_actor_name := COALESCE(v_actor_name, 'System');

  INSERT INTO public.audit_logs (
    action_type, module, target_table, target_id, target_label,
    performed_by, performed_at, before_snapshot, after_snapshot
  ) VALUES (
    'RECORD_UPDATED',
    'cause_list',
    'matter_assignments',
    v_new_id,
    COALESCE(v_matter_ref, p_matter_id::TEXT),
    p_actor,
    now(),
    jsonb_build_object('matter_id', p_matter_id, 'event', 'reassignment_requested'),
    jsonb_build_object('matter_id', p_matter_id, 'new_assignment_id', v_new_id, 'assigned_to', p_user_id, 'reason', p_reason)
  );

  -- parent_matter_id = p_matter_id, added in migration 025 — this entry
  -- already targets the matter (target_table/target_id = matters/p_matter_id
  -- below), so parent_matter_id here is simply the same id, making this
  -- entry show up correctly in that matter's timeline.
  INSERT INTO public.activity_feed (
    event_type, module, actor_id, target_table, target_id, target_label, message,
    parent_matter_id
  ) VALUES (
    'MATTER_ASSIGNED',
    'cause_list',
    p_actor,
    'matters',
    p_matter_id,
    COALESCE(v_matter_ref, p_matter_id::TEXT),
    v_actor_name || ' reassigned ' || COALESCE(v_matter_ref, 'a matter') ||
      ' to ' || COALESCE(v_new_user_name, 'a member'),
    p_matter_id
  );

  RETURN v_new_id;
END;
$$;



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 026_scheduled_maintenance.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 026: Scheduled Maintenance Jobs (pg_cron)
-- ───────────────────────────────────────────────────────────────
-- Sprint 2, Priority 1.
--
-- BACKGROUND: the codebase has documented, in four separate places
-- (migration 014 comments, migration 018 comments, DATABASE_DIAGRAM.md),
-- that activity_feed has "90-day retention enforced by pg_cron job" —
-- but no such job, and no pg_cron extension, were ever actually
-- created. activity_feed has grown unbounded since Sprint 1. This
-- migration makes the documentation true rather than aspirational.
--
-- It also fixes a related, previously-undetected structural gap: the
-- audit_logs partition table (migration 014) has quarterly partitions
-- through 2026, a yearly partition for 2027, and then a single
-- catch-all partition (audit_logs_2028_onwards) spanning 2028-01-01
-- to 2100-01-01. If left alone, every year from 2028 forward would
-- silently fall into that one partition, defeating the entire point
-- of partitioning by time. This migration adds an annual job that
-- carves a proper year-bounded partition out of the catch-all before
-- that year actually arrives.
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Enable pg_cron ────────────────────────────────────────────
-- Available on all Supabase plans, including free tier (verified).
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ─── 2. activity_feed retention ────────────────────────────────────
-- A plain DELETE, not a stored function with internal scheduling —
-- pg_cron calls this directly. Uses the existing idx_af_created index,
-- so this remains cheap even as the table grows. Designed to be safe
-- if a scheduled run is ever missed (a known, observed pg_cron
-- reliability quirk on some Supabase setups, confirmed via community
-- reports): the WHERE clause is always relative to "now() - 90 days",
-- not "since the last run", so a missed run just means the next
-- successful run deletes a larger backlog — never incorrect, never
-- compounding.
SELECT cron.schedule(
  'molms_purge_activity_feed',
  '0 3 * * *',  -- Daily at 03:00 UTC — low-traffic hours for a Kenya-based firm (06:00 EAT)
  $$
    DELETE FROM public.activity_feed
    WHERE created_at < now() - INTERVAL '90 days';
  $$
);

-- ─── 3. audit_logs annual partition maintenance ────────────────────
-- Runs once a year. Idempotent and safe to run more than once per
-- year if needed (e.g. manual re-run after an incident) — it checks
-- the catch-all partition's current lower bound before doing anything,
-- and does nothing if next year's partition already exists.
CREATE OR REPLACE FUNCTION public.fn_maintain_audit_log_partitions()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_next_year       INTEGER := EXTRACT(YEAR FROM now())::INTEGER + 1;
  v_next_year_start DATE    := make_date(v_next_year, 1, 1);
  v_next_year_end   DATE    := make_date(v_next_year + 1, 1, 1);
  v_new_partition   TEXT    := 'audit_logs_' || v_next_year::TEXT;

  v_catchall_name     TEXT;
  v_catchall_to_text  TEXT;
  v_catchall_to_date  DATE;
  v_far_future_text   TEXT;     -- exact original upper-bound text, preserved verbatim for re-attach
  v_max_to_date       DATE := NULL;
  r                   RECORD;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_class WHERE relname = v_new_partition) THEN
    RAISE NOTICE 'fn_maintain_audit_log_partitions: % already exists, skipping', v_new_partition;
    RETURN;
  END IF;

  -- Find the partition whose UPPER bound is furthest in the future —
  -- that is THE catch-all, regardless of what it happens to be named.
  -- audit_logs.performed_at is TIMESTAMPTZ, so pg_get_expr() renders
  -- bounds as full timestamps with a timezone offset, e.g.
  -- "FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2028-01-01 00:00:00+00')"
  -- — NOT bare dates. The capture group below matches any run of
  -- non-quote characters between TO ('...'), then casts to TIMESTAMPTZ
  -- (parsed correctly regardless of whether the literal includes a
  -- time-of-day and offset) for YEAR COMPARISON ONLY. The original,
  -- full-precision text (v_far_future_text) is kept separately and
  -- passed through verbatim when re-attaching, rather than rebuilding
  -- it from a DATE-truncated value — this avoids any risk of losing
  -- the exact original timestamp/offset precision in the round trip.
  -- This was corrected after a live test against this project's
  -- actual audit_logs table revealed the original pattern (which only
  -- matched digits and hyphens) silently matched nothing against real
  -- TIMESTAMPTZ-formatted bounds, leaving v_catchall_name NULL and
  -- causing every EXECUTE below to fail.
  FOR r IN
    SELECT c.relname AS partname,
           pg_get_expr(c.relpartbound, c.oid) AS bound_expr
    FROM pg_inherits i
    JOIN pg_class c ON c.oid = i.inhrelid
    JOIN pg_class p ON p.oid = i.inhparent
    WHERE p.relname = 'audit_logs'
  LOOP
    v_catchall_to_text := substring(r.bound_expr FROM 'TO \(''([^'']+)''\)');
    IF v_catchall_to_text IS NULL THEN
      CONTINUE; -- not a range partition bound we can parse — skip defensively
    END IF;
    v_catchall_to_date := v_catchall_to_text::TIMESTAMPTZ::DATE;

    IF v_max_to_date IS NULL OR v_catchall_to_date > v_max_to_date THEN
      v_max_to_date      := v_catchall_to_date;
      v_far_future_text  := v_catchall_to_text; -- keep the exact original string
      v_catchall_name    := r.partname;
    END IF;
  END LOOP;

  IF v_catchall_name IS NULL THEN
    RAISE WARNING 'fn_maintain_audit_log_partitions: could not identify a catch-all partition on audit_logs — nothing to split';
    RETURN;
  END IF;

  -- Sanity check: the catch-all's upper bound must be AFTER the year
  -- we're about to carve out, or there's nothing to split (e.g. this
  -- function is being run far later than intended and the catch-all
  -- no longer actually covers next year). Fail loudly rather than
  -- silently creating an overlapping or empty-range partition.
  -- Compares using v_max_to_date (the DATE-truncated value, fine for
  -- this comparison) — but the actual re-attach below uses
  -- v_far_future_text (the untouched original), not this truncated value.
  IF v_max_to_date <= v_next_year_end THEN
    RAISE WARNING 'fn_maintain_audit_log_partitions: catch-all % upper bound % is not after %, skipping to avoid an invalid split',
      v_catchall_name, v_max_to_date, v_next_year_end;
    RETURN;
  END IF;

  -- Detach, carve out next year, re-attach the remainder under a new
  -- name (renamed so a future run of this same function can find THIS
  -- partition again next time it loops — pg_class.relname must stay
  -- unique, so the old name can't be reused).
  EXECUTE format('ALTER TABLE public.audit_logs DETACH PARTITION %I', v_catchall_name);

  EXECUTE format(
    'CREATE TABLE public.%I PARTITION OF public.audit_logs FOR VALUES FROM (%L) TO (%L)',
    v_new_partition, v_next_year_start, v_next_year_end
  );

  EXECUTE format(
    'ALTER TABLE public.%I RENAME TO %I',
    v_catchall_name, 'audit_logs_catchall_' || (v_next_year + 1)::TEXT
  );

  -- v_far_future_text is passed as a plain value to %L (not %I), so
  -- format() will correctly quote it as a string literal regardless
  -- of its exact contents (with or without time-of-day/offset) — this
  -- preserves the original bound exactly, with no DATE round-trip.
  EXECUTE format(
    'ALTER TABLE public.audit_logs ATTACH PARTITION public.%I FOR VALUES FROM (%L) TO (%L)',
    'audit_logs_catchall_' || (v_next_year + 1)::TEXT,
    v_next_year_end,
    v_far_future_text
  );

  RAISE NOTICE 'fn_maintain_audit_log_partitions: created %, remaining catch-all (now %) starts % through %',
    v_new_partition, 'audit_logs_catchall_' || (v_next_year + 1)::TEXT, v_next_year_end, v_far_future_text;
END;
$$;

SELECT cron.schedule(
  'molms_maintain_audit_partitions',
  '0 4 1 1 *',  -- 04:00 UTC on January 1st each year
  $$ SELECT public.fn_maintain_audit_log_partitions(); $$
);

-- ─── 4. Verification helper ────────────────────────────────────────
-- Lets an Administrator confirm both jobs are registered, without
-- needing to know cron internals.
COMMENT ON FUNCTION public.fn_maintain_audit_log_partitions() IS
  'Scheduled annually via pg_cron (molms_maintain_audit_partitions). '
  'Carves a year-bounded partition for next year out of the open-ended '
  'catch-all partition on audit_logs, preventing every future year from '
  'silently accumulating in one unbounded partition.';



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 027_matter_archive_guard.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 027: Matter Archive Guard
-- ───────────────────────────────────────────────────────────────
-- Sprint 2, Priority 2.
--
-- PROBLEM: nothing currently prevents archiving a matter that has a
-- past-due hearing with no recorded outcome — a real compliance gap
-- for a law firm (a hearing happened, or should have, and nobody
-- logged what occurred, yet the matter gets filed away as closed).
--
-- RULE: block archiving when the matter has any non-archived
-- matter_hearings row where hearing_date is in the past AND
-- outcome IS NULL. A FUTURE hearing with no outcome yet is normal
-- (it hasn't happened) and does NOT block — only a past hearing
-- nobody recorded an outcome for does.
--
-- OVERRIDE: Partner/Admin may force the archive through anyway (e.g.
-- a hearing was logged incorrectly, or the matter is being closed for
-- unrelated reasons), with the override explicitly logged.
--
-- DESIGN NOTE — why this is ONE callable function, not a trigger
-- reading a session variable set by a separate call: the original
-- draft of this migration used set_config()/current_setting() to pass
-- an "override acknowledged" flag from the frontend into a BEFORE
-- UPDATE trigger, mirroring how auth.uid() reads request.jwt.claims.
-- That works for auth.uid() because Supabase's PostgREST layer sets
-- those claims AS PART OF the same request/transaction that runs the
-- query. It does NOT work for a value set by one separate supabase-js
-- call and read by a later one: supabase-js does not share a
-- transaction or a database connection across separate .rpc()/.from()
-- calls — each is an independent HTTP request to PostgREST, which can
-- be served by any connection in the pool. A set_config() in one
-- request would have no guaranteed relationship to the connection
-- serving the next request. This was caught before deployment, not
-- after, by checking Supabase's own documentation on transaction
-- behavior rather than assuming the pattern would generalize from
-- auth.uid(). The fix: the override flag and the actual archive write
-- happen inside ONE PL/pgSQL function, invoked through ONE rpc() call
-- — guaranteeing both run in the same transaction, the same pattern
-- already proven correct by fn_matter_reassign() in migration 023.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_archive_matter_with_override(
  p_matter_id      UUID,
  p_actor          UUID,
  p_reason         TEXT,
  p_force_override BOOLEAN DEFAULT FALSE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor_role       TEXT;
  v_unresolved_count INTEGER;
  v_unresolved_list  TEXT;
BEGIN
  -- Authorization: matches matters_update_authority (migration 020)
  -- — archiving has always been Partner/Admin-only, confirmed by the
  -- matters_update_own RLS policy comment ("not archived, not closed").
  -- This function is SECURITY DEFINER, so it does not inherit that
  -- RLS check automatically — re-implemented explicitly here, same
  -- reasoning as fn_matter_reassign()'s authorization check.
  SELECT role::TEXT INTO v_actor_role FROM public.users WHERE id = p_actor;
  IF v_actor_role NOT IN ('administrator', 'partner') THEN
    RAISE EXCEPTION 'Only Partners and Administrators may archive a matter (actor role: %)', COALESCE(v_actor_role, 'unknown');
  END IF;

  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'An archive reason is required.';
  END IF;

  SELECT count(*), string_agg(to_char(hearing_date, 'DD Mon YYYY'), ', ')
  INTO v_unresolved_count, v_unresolved_list
  FROM public.matter_hearings
  WHERE matter_id = p_matter_id
    AND is_archived = FALSE
    AND outcome IS NULL
    AND hearing_date < now();

  IF v_unresolved_count > 0 AND NOT p_force_override THEN
    RAISE EXCEPTION
      'Cannot archive matter: % unresolved hearing(s) with no recorded outcome (%). Record the outcome first, or confirm the override.',
      v_unresolved_count, v_unresolved_list
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.matters
  SET is_archived    = TRUE,
      archived_by    = p_actor,
      archived_at    = now(),
      archive_reason = CASE
        WHEN v_unresolved_count > 0 THEN p_reason || ' [Archived with ' || v_unresolved_count || ' unresolved hearing(s) overridden by ' || v_actor_role || ']'
        ELSE p_reason
      END,
      updated_by = p_actor,
      updated_at = now()
  WHERE id = p_matter_id;

  -- No separate audit/activity write here — the UPDATE above is
  -- captured automatically and in full by the existing
  -- fn_audit_trigger() (RECORD_ARCHIVED, with the complete row
  -- snapshot including the override-annotated archive_reason) and
  -- fn_activity_trigger() (MATTER_ARCHIVED). Both already fire on
  -- this exact UPDATE; this function adds no new logging path, only
  -- the gate in front of it.
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_archive_matter_with_override(UUID, UUID, TEXT, BOOLEAN) TO authenticated;



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 028_documents_storage.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 028: Documents Storage Bucket + Storage RLS
-- ───────────────────────────────────────────────────────────────
-- Sprint 2, Priority 2 (Documents Module, Work Package 1).
--
-- DESIGN DECISION — single bucket, not two:
-- The work package brief specified two buckets (matter-documents,
-- general-documents), split by whether a document is linked to a
-- matter. Documents.matter_id is already nullable and already the
-- correct place to express that distinction. Splitting by bucket too
-- would create two independent representations of the same fact that
-- could silently disagree (a document's bucket location and its
-- matter_id column), and would require writing and verifying every
-- Storage RLS policy TWICE instead of once. A single bucket with
-- matter linkage handled entirely through the existing matter_id
-- column avoids both problems. Approved by the user after this
-- tradeoff was raised explicitly.
--
-- PATH STRUCTURE: {document_id}/{version_number}-{filename}
-- (uploaded via supabase.storage.from('documents').upload(path, file) —
-- the bucket itself, named 'documents', is the top-level container;
-- storage.objects.name does NOT include the bucket name, confirmed
-- via Supabase's own corrected documentation, so the path stored in
-- `name` starts directly at document_id, not at a redundant
-- "documents/" prefix. This was caught and corrected during the
-- architecture verification gate before any code was written.)
-- The document_id segment is what Storage RLS policies key off of to
-- check authorization against the documents table — NOT folder-name
-- parsing tricks tied to user IDs or matter IDs, which Supabase's own
-- community discussions show are fragile (ambiguous column references,
-- the dashboard policy builder silently rewriting expressions). Using
-- the document's own id keeps the policy logic identical to, and as
-- simple as, the existing table-level RLS on `documents` itself.
--
-- AUTHORIZATION — mirrors the EXISTING documents table RLS exactly
-- (migration 020: doc_select, doc_insert, doc_update_own,
-- doc_update_authority), NOT the simplified "Members upload, Partners
-- archive/restore" rule from the work package brief. The existing
-- rule already lets a Member archive/update files THEY uploaded, not
-- just view them — adopting the simpler brief version would have been
-- an unrequested regression, narrowing what Members can already do
-- with their own uploads. Storage policies here are written to match
-- table RLS exactly, not to introduce a parallel, slightly different
-- rule for the same documents.
-- ═══════════════════════════════════════════════════════════════

-- ─── 1. Bucket ──────────────────────────────────────────────────
-- Private (public = false): every access goes through RLS, never a
-- bare public URL. File size limit and allowed MIME types enforced
-- here AND re-validated client-side before upload (defense in depth
-- — a client-side check alone could be bypassed by a direct API call).
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'documents',
  'documents',
  false,
  26214400, -- 25 MB in bytes (25 * 1024 * 1024), matching the work package's stated limit
  ARRAY[
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-powerpoint',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'image/jpeg',
    'image/png'
  ]
)
ON CONFLICT (id) DO UPDATE SET
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- ─── 2. Helper function ─────────────────────────────────────────
-- Resolves "does this user have UPDATE authority over this document"
-- exactly as doc_update_own / doc_update_authority already define it.
-- SECURITY DEFINER + wrapped in (select ...) when called from a
-- policy, per Supabase's own documented RLS performance guidance —
-- this avoids the function being re-evaluated per-row.
CREATE OR REPLACE FUNCTION public.fn_can_modify_document(p_document_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.documents d
    WHERE d.id = p_document_id
      AND (
        (d.uploaded_by = auth.uid() AND get_user_role() = 'member')
        OR get_user_role() IN ('administrator', 'partner')
      )
  );
$$;

-- ─── 3. Storage RLS policies ────────────────────────────────────
-- One policy per operation, per Supabase's own recommendation (never
-- combine multiple operations into one FOR ALL policy).

-- SELECT: any authenticated user may view any non-archived document's
-- file — mirrors doc_select exactly (is_archived = FALSE, no other
-- restriction). storage.foldername(name)[1] extracts the document_id
-- segment from the path "{document_id}/{version}-{filename}" (within
-- the 'documents' bucket — the bucket name itself is never part of
-- the stored object name, confirmed during the verification gate).
CREATE POLICY documents_storage_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'documents'
    AND EXISTS (
      SELECT 1 FROM public.documents d
      WHERE d.id::text = (storage.foldername(name))[1]
        AND d.is_archived = FALSE
    )
  );

-- INSERT: any authenticated user may upload — mirrors doc_insert
-- exactly (auth.uid() IS NOT NULL, no other restriction). The actual
-- documents/document_versions metadata rows are written by the
-- frontend in the same logical operation as the file upload; this
-- policy only governs the file bytes landing in Storage.
CREATE POLICY documents_storage_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'documents'
    AND (select auth.uid()) IS NOT NULL
  );

-- UPDATE: only relevant for Storage metadata changes (rare for this
-- app's flow, since new versions are new objects, not overwrites —
-- see document_versions' append-only design). Mirrors the same
-- modify-authority rule as DELETE below, via the helper function.
-- The CASE construct here is deliberate, not stylistic: 'text'::UUID
-- raises a hard error (22P02) for anything that isn't a valid UUID
-- shape, rather than evaluating to false. PostgreSQL's own
-- documentation explicitly warns that AND does NOT guarantee
-- left-to-right "short-circuit" evaluation the way it does in most
-- programming languages — the planner is free to reorder boolean
-- expressions in a WHERE/USING clause, so "put the regex check
-- first in an AND chain" would NOT reliably protect the UUID cast
-- from being evaluated first. CASE is the documented correct
-- technique for forcing evaluation order in this exact situation.
CREATE POLICY documents_storage_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'documents'
    AND CASE
      WHEN (storage.foldername(name))[1] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN fn_can_modify_document(((storage.foldername(name))[1])::UUID)
      ELSE FALSE
    END
  );

-- DELETE: archiving a document is a metadata operation (is_archived =
-- TRUE on the documents row, per the existing no-hard-delete
-- principle) — actual Storage DELETE is not part of the normal
-- archive/restore flow and is reserved for genuine cleanup, gated by
-- the same modify-authority rule as UPDATE, with the same CASE-forced
-- evaluation order protecting the UUID cast.
CREATE POLICY documents_storage_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'documents'
    AND CASE
      WHEN (storage.foldername(name))[1] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN fn_can_modify_document(((storage.foldername(name))[1])::UUID)
      ELSE FALSE
    END
  );



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 029_hearing_conflict_detection.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 029: Hearing Conflict Detection
-- ───────────────────────────────────────────────────────────────
-- Sprint 2, Priority 2 (Work Package 2).
--
-- BEHAVIOR: warn-only, never blocks. This is a read-only query
-- function, not a trigger — no BEFORE INSERT/UPDATE guard exists on
-- matter_hearings, and none should, since legitimate back-to-back or
-- same-day court appearances are normal for a busy litigation
-- practice. The frontend calls this function to surface a warning;
-- nothing in the database prevents saving a conflicting hearing.
--
-- SCOPE DECISIONS, confirmed with the user before building:
-- "Same advocate" in the work package brief is treated as the same
-- concept as "same assigned member" (matters.assigned_to) — the
-- schema has no separate advocate field, and matter_entities only
-- tracks the OPPOSING side's counsel (entity_type = 'opposing_counsel'),
-- never the firm's own handling advocate as something distinct from
-- the assignee. Inventing a new field for this would create two
-- representations of the same fact that could disagree, with no
-- actual request behind it.
--
-- "Same court date/time" is treated as SAME CALENDAR DAY, not a true
-- overlapping time window — matter_hearings.hearing_date is a single
-- timestamp with no duration or end-time column anywhere in the
-- schema, so true interval overlap isn't computable from existing
-- data without inventing an assumed duration. Same-day is the honest
-- reading of what the data supports, and errs toward over-warning
-- rather than under-warning — correct for a warn-only feature, where
-- a false positive costs a glance and a dismiss, but a false negative
-- defeats the point of the feature entirely.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_check_hearing_conflicts(
  p_hearing_date  TIMESTAMPTZ,
  p_matter_id     UUID,             -- the matter this hearing belongs to (excluded from its own conflict check)
  p_exclude_hearing_id UUID DEFAULT NULL  -- when editing an existing hearing, exclude it from comparing against itself
)
RETURNS TABLE (
  conflicting_hearing_id   UUID,
  conflicting_matter_id    UUID,
  conflicting_matter_ref   TEXT,
  conflicting_matter_title TEXT,
  conflict_hearing_date    TIMESTAMPTZ,
  conflict_reason          TEXT  -- 'same_assigned_member' or 'same_supervising_partner', or both joined
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH this_matter AS (
    SELECT assigned_to, supervising_partner_id
    FROM public.matters
    WHERE id = p_matter_id
  ),
  candidates AS (
    SELECT
      mh.id            AS hearing_id,
      mh.matter_id,
      mh.hearing_date,
      m.reference_number,
      m.title,
      m.assigned_to,
      m.supervising_partner_id
    FROM public.matter_hearings mh
    JOIN public.matters m ON m.id = mh.matter_id
    WHERE mh.is_archived = FALSE
      AND m.is_archived = FALSE
      AND mh.matter_id != p_matter_id  -- never flag a matter's own other hearings as a "conflict" with itself
      AND (p_exclude_hearing_id IS NULL OR mh.id != p_exclude_hearing_id)
      AND DATE(mh.hearing_date) = DATE(p_hearing_date)  -- same calendar day, see header note on overlap definition
  )
  SELECT
    c.hearing_id,
    c.matter_id,
    c.reference_number,
    c.title,
    c.hearing_date,
    CASE
      WHEN c.assigned_to IS NOT NULL AND c.assigned_to = (SELECT assigned_to FROM this_matter)
           AND c.supervising_partner_id = (SELECT supervising_partner_id FROM this_matter)
        THEN 'same_assigned_member_and_partner'
      WHEN c.assigned_to IS NOT NULL AND c.assigned_to = (SELECT assigned_to FROM this_matter)
        THEN 'same_assigned_member'
      WHEN c.supervising_partner_id = (SELECT supervising_partner_id FROM this_matter)
        THEN 'same_supervising_partner'
    END AS conflict_reason
  FROM candidates c
  WHERE
    -- a NULL assigned_to is never treated as matching another NULL
    -- assigned_to — two genuinely unassigned matters aren't a real
    -- scheduling conflict for any actual person.
    (c.assigned_to IS NOT NULL AND c.assigned_to = (SELECT assigned_to FROM this_matter))
    OR c.supervising_partner_id = (SELECT supervising_partner_id FROM this_matter)
  ORDER BY c.hearing_date;
$$;

GRANT EXECUTE ON FUNCTION public.fn_check_hearing_conflicts(TIMESTAMPTZ, UUID, UUID) TO authenticated;

COMMENT ON FUNCTION public.fn_check_hearing_conflicts IS
  'Read-only, warn-only conflict check for hearing scheduling (Sprint 2 WP2). '
  'Does not block any write — callers are expected to surface the result as '
  'a non-blocking warning, never a hard validation failure.';



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 030_matter_reassignment_reason.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 030: Matter Reassignment Reason Support
-- ───────────────────────────────────────────────────────────────
-- Sprint 2, Priority 3 (Work Package 3 — Matter Reassignment UI).
--
-- GAP FOUND while building the Reassignment UI: fn_matter_reassign()
-- (migration 023) accepts a p_reason parameter, but the ONLY caller
-- in the live system is fn_matter_reassignment_dispatch() — a trigger
-- that fires automatically on any UPDATE changing assigned_to, and
-- always passes the hardcoded literal 'Reassignment'. There was no
-- path for a real user-provided reason to reach the function at all,
-- despite the work package explicitly asking for "Provide Reason" as
-- a feature. This is an additive fix, not a redesign: the trigger-
-- based dispatch model from Sprint 1 is preserved exactly as-is (it
-- correctly handles reassignment from ANY code path that updates
-- assigned_to, not just this one new modal) — this migration just
-- gives that existing trigger a real reason to read, instead of only
-- ever seeing the hardcoded default.
--
-- DESIGN: pending_reassignment_reason is a transient, write-only
-- column — set in the SAME UPDATE statement that changes assigned_to,
-- read by the trigger via NEW (the complete proposed row, including
-- this column, per standard PostgreSQL trigger semantics — no
-- cross-request mechanism needed, avoiding the exact set_config
-- pitfall already found and corrected in the Archive Guard work).
--
-- IMPORTANT CORRECTION made while writing this migration, TWICE:
--
-- First draft assumed the trigger could clear this field by setting
-- NEW.pending_reassignment_reason := NULL inside the trigger function.
-- That does nothing: trg_matter_reassignment_dispatch (migration 023)
-- fires AFTER UPDATE, and modifying NEW in an AFTER trigger has no
-- effect on the already-written row.
--
-- Second draft replaced that with an explicit separate UPDATE inside
-- the trigger function to clear the field. That introduced a WORSE
-- problem: matters has two other triggers bound to plain, unscoped
-- "AFTER INSERT OR UPDATE" (fn_audit_trigger, migration 017, and
-- fn_activity_trigger, migration 018) with no guard against logging
-- a no-meaningful-change update. A second top-level UPDATE statement,
-- even one that only clears this one internal bookkeeping column,
-- would fire BOTH of those unconditionally — producing a spurious
-- second RECORD_UPDATED audit row and a second activity_feed entry on
-- every single reassignment, polluting the audit trail with noise
-- nobody asked to see.
--
-- FINAL DESIGN: do not clear the field at all. A stale value sitting
-- in pending_reassignment_reason between reassignments is harmless —
-- it is a write-only field nothing else in the system ever reads or
-- displays; the ONLY place it is read is inside this exact trigger,
-- at the exact moment assigned_to changes, after which a future
-- reassignment will simply overwrite it again. No second UPDATE, no
-- duplicate audit noise, no recursion risk to reason about at all.
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.matters
  ADD COLUMN IF NOT EXISTS pending_reassignment_reason TEXT;

COMMENT ON COLUMN public.matters.pending_reassignment_reason IS
  'Transient, write-only. Set in the same UPDATE that changes '
  'assigned_to; read once by fn_matter_reassignment_dispatch() at the '
  'moment of reassignment. Deliberately NEVER cleared afterward — see '
  'migration 030 header for why a cleanup UPDATE was rejected (it '
  'would fire unscoped audit/activity triggers and create duplicate '
  'log noise on every reassignment). A stale value here is harmless: '
  'nothing else in the system reads or displays this column.';

CREATE OR REPLACE FUNCTION public.fn_matter_reassignment_dispatch()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reason TEXT;
BEGIN
  IF OLD.assigned_to IS DISTINCT FROM NEW.assigned_to AND NEW.assigned_to IS NOT NULL THEN
    v_reason := COALESCE(NEW.pending_reassignment_reason, 'Reassignment');

    PERFORM public.fn_matter_reassign(
      NEW.id,
      NEW.assigned_to,
      COALESCE(auth.uid(), NEW.updated_by),
      v_reason
    );
    -- Deliberately no cleanup of pending_reassignment_reason here —
    -- see migration header for why. The field is read once, above,
    -- and left as-is; the next reassignment will overwrite it.
  END IF;
  RETURN NEW;
END;
$$;

-- Trigger re-creation not needed — CREATE OR REPLACE FUNCTION above
-- updates the function body in place; the existing trigger binding
-- from migration 023 (trg_matter_reassignment_dispatch) already
-- points at this function by name and picks up the new behavior
-- automatically.

-- ───────────────────────────────────────────────────────────────
-- ADDITIONAL FIX, found while live-testing the above: duplicate
-- activity_feed entry on every reassignment (root cause investigation)
-- ───────────────────────────────────────────────────────────────
-- Live testing of the reassignment flow showed TWO activity_feed rows
-- per reassignment: a correct 'MATTER_ASSIGNED' (from fn_matter_reassign,
-- migration 023) and an extra 'MATTER_UPDATED' with the same timestamp.
--
-- Root cause, confirmed by pulling the LIVE pg_get_functiondef() of
-- fn_activity_trigger() directly from the database rather than trusting
-- migration files: migration 024 already removed the assigned_to-
-- specific branch from this function specifically to stop it from
-- producing its OWN, less-detailed 'MATTER_ASSIGNED' duplicate — but
-- migration 024's fix only removed that ONE branch; it did not add a
-- way to skip logging ENTIRELY for that case. The control flow falls
-- through to the generic ELSE branch and logs 'MATTER_UPDATED' instead
-- — replacing one duplicate ('MATTER_ASSIGNED' x2) with a different,
-- still-redundant one ('MATTER_ASSIGNED' + 'MATTER_UPDATED'). Migration
-- 024's own comment called this "intentional, not a regression" on the
-- reasoning that the row was technically also "updated" — true, but it
-- still produces two feed entries for what is, from the user's
-- perspective, one single action, with the second adding no information
-- the first didn't already convey.
--
-- This was tracked down through direct empirical testing (confirming
-- the fn_matter_reassign() idempotency-guard UPDATE touches zero rows
-- in the trigger-dispatched path, ruling it out) and by comparing the
-- LIVE deployed function bodies against migration files via
-- pg_get_functiondef(), which is what actually revealed migration
-- 024's prior, only-partial fix — not visible from migration 018 alone.
--
-- FIX: add an explicit early-exit when assigned_to is the ONLY thing
-- that changed (no archive/restore, no status change) — skip logging
-- from this generic trigger entirely in that one case, since
-- fn_matter_reassign() already logs it with more accurate detail.
-- Rebuilt from the LIVE definition (which already includes
-- parent_matter_id, added by migration 025 — not present in the
-- migration 018/024 file text, since both predate that addition).
CREATE OR REPLACE FUNCTION public.fn_activity_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new            JSONB := to_jsonb(NEW);
  v_old            JSONB := CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END;

  v_actor_name     TEXT;
  v_event_type     activity_event_type;
  v_module         TEXT;
  v_label          TEXT;
  v_message        TEXT;
  v_type_code      TEXT;
  v_status_label   TEXT;
  v_matter_ref     TEXT;
  v_new_id         UUID := NEW.id;
  v_parent_matter_id UUID := NULL;

  v_new_status     TEXT := v_new->>'status';
  v_old_status     TEXT := v_old->>'status';
  v_new_is_archived TEXT := v_new->>'is_archived';
  v_old_is_archived TEXT := v_old->>'is_archived';
  v_new_assigned_to TEXT := v_new->>'assigned_to';
  v_old_assigned_to TEXT := v_old->>'assigned_to';
  v_new_status_id   TEXT := v_new->>'matter_status_id';
  v_old_status_id   TEXT := v_old->>'matter_status_id';
  v_new_thread_type TEXT := v_new->>'thread_type';
BEGIN
  -- Fetch actor name for human-readable messages
  SELECT name INTO v_actor_name FROM public.users WHERE id = auth.uid();
  v_actor_name := COALESCE(v_actor_name, 'System');

  -- ── matters ───────────────────────────────────────────────
  IF TG_TABLE_NAME = 'matters' THEN
    v_parent_matter_id := v_new_id;

    SELECT type_code::TEXT INTO v_type_code
    FROM public.matter_types WHERE id = (v_new->>'matter_type_id')::UUID;

    v_module := CASE COALESCE(v_type_code, '')
      WHEN 'litigation' THEN 'cause_list'
      ELSE 'non_litigation'
    END;
    v_label := v_new->>'reference_number';

    IF TG_OP = 'INSERT' THEN
      v_event_type := 'MATTER_CREATED';
      v_message    := v_actor_name || ' created matter ' || (v_new->>'reference_number');

    ELSIF TG_OP = 'UPDATE' THEN
      IF v_old_is_archived = 'false' AND v_new_is_archived = 'true' THEN
        v_event_type := 'MATTER_ARCHIVED';
        v_message    := v_actor_name || ' archived matter ' || (v_new->>'reference_number');

      ELSIF v_old_is_archived = 'true' AND v_new_is_archived = 'false' THEN
        v_event_type := 'MATTER_RESTORED';
        v_message    := v_actor_name || ' restored matter ' || (v_new->>'reference_number');

      -- THE ACTUAL FIX (migration 030): when assigned_to changed, skip
      -- logging from THIS generic trigger entirely — return early,
      -- inserting nothing. fn_matter_reassign() (migration 023) is the
      -- single authoritative source of the MATTER_ASSIGNED entry for
      -- this case, already fired by trg_matter_reassignment_dispatch
      -- on this exact same UPDATE. Migration 024 already established
      -- this principle but only removed the duplicate-detection
      -- branch, leaving control fall through to the generic
      -- MATTER_UPDATED case below — still a real duplicate row, just
      -- with a less specific label. This RETURN prevents the INSERT
      -- entirely for this one case, rather than re-labeling it.
      ELSIF v_old_assigned_to IS DISTINCT FROM v_new_assigned_to AND v_new_assigned_to IS NOT NULL THEN
        RETURN NEW;

      ELSIF v_old_status_id IS DISTINCT FROM v_new_status_id THEN
        SELECT label INTO v_status_label FROM public.matter_statuses WHERE id = v_new_status_id::UUID;
        v_event_type := 'MATTER_STATUS_CHANGED';
        v_message    := (v_new->>'reference_number') || ' moved to ' || COALESCE(v_status_label, 'new status');

      ELSE
        v_event_type := 'MATTER_UPDATED';
        v_message    := v_actor_name || ' updated matter ' || (v_new->>'reference_number');
      END IF;
    END IF;

  -- ── matter_notes ──────────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'matter_notes' AND TG_OP = 'INSERT' THEN
    v_parent_matter_id := (v_new->>'matter_id')::UUID;
    SELECT reference_number INTO v_matter_ref FROM public.matters WHERE id = v_parent_matter_id;
    v_event_type := 'NOTE_ADDED';
    v_module     := 'cause_list';
    v_label      := COALESCE(v_matter_ref, 'matter');
    v_message    := v_actor_name || ' added a note to ' || COALESCE(v_matter_ref, 'a matter');

  -- ── matter_hearings ───────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'matter_hearings' AND TG_OP = 'INSERT' THEN
    v_parent_matter_id := (v_new->>'matter_id')::UUID;
    SELECT reference_number INTO v_matter_ref FROM public.matters WHERE id = v_parent_matter_id;
    v_event_type := 'HEARING_ADDED';
    v_module     := 'cause_list';
    v_label      := COALESCE(v_matter_ref, 'matter');
    v_message    := v_actor_name || ' added a hearing to ' || COALESCE(v_matter_ref, 'a matter')
                 || ' on ' || to_char((v_new->>'hearing_date')::TIMESTAMPTZ, 'DD Mon YYYY');

  -- ── matter_entities ───────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'matter_entities' AND TG_OP = 'INSERT' THEN
    v_parent_matter_id := (v_new->>'matter_id')::UUID;
    SELECT reference_number INTO v_matter_ref FROM public.matters WHERE id = v_parent_matter_id;
    v_event_type := 'ENTITY_ADDED';
    v_module     := 'cause_list';
    v_label      := COALESCE(v_matter_ref, 'matter');
    v_message    := v_actor_name || ' added ' || (v_new->>'name') || ' to ' || COALESCE(v_matter_ref, 'a matter');

  -- ── daily_reports ─────────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'daily_reports' AND TG_OP = 'UPDATE'
    AND v_old_status IS DISTINCT FROM v_new_status
    AND v_new_status = 'submitted' THEN
    v_event_type := 'REPORT_SUBMITTED';
    v_module     := 'daily_reports';
    v_label      := v_new->>'reference_number';
    v_message    := v_actor_name || ' submitted daily report ' || (v_new->>'reference_number');

  ELSIF TG_TABLE_NAME = 'daily_reports' AND TG_OP = 'UPDATE'
    AND v_old_status IS DISTINCT FROM v_new_status
    AND v_new_status = 'reviewed' THEN
    v_event_type := 'REPORT_REVIEWED';
    v_module     := 'daily_reports';
    v_label      := v_new->>'reference_number';
    v_message    := v_actor_name || ' reviewed daily report ' || (v_new->>'reference_number');

  -- ── documents ─────────────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'documents' AND TG_OP = 'INSERT' THEN
    v_parent_matter_id := (v_new->>'matter_id')::UUID;
    v_event_type := 'DOCUMENT_UPLOADED';
    v_module     := 'documents';
    v_label      := v_new->>'reference_number';
    v_message    := v_actor_name || ' uploaded ' || (v_new->>'title');

  -- ── diary_events ──────────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'diary_events' AND TG_OP = 'INSERT' THEN
    v_parent_matter_id := (v_new->>'matter_id')::UUID;
    v_event_type := 'DIARY_EVENT_CREATED';
    v_module     := 'legal_diary';
    v_label      := v_new->>'title';
    v_message    := v_actor_name || ' created diary event: ' || (v_new->>'title');

  -- ── intercom_threads ──────────────────────────────────────
  ELSIF TG_TABLE_NAME = 'intercom_threads' AND TG_OP = 'INSERT'
    AND v_new_thread_type = 'announcement' THEN
    v_event_type := 'INTERCOM_ANNOUNCEMENT';
    v_module     := 'intercom';
    v_label      := v_new->>'title';
    v_message    := v_actor_name || ' posted announcement: ' || (v_new->>'title');

  -- ── users (new member added) ───────────────────────────────
  ELSIF TG_TABLE_NAME = 'users' AND TG_OP = 'INSERT' THEN
    v_event_type := 'MEMBER_ADDED';
    v_module     := 'members';
    v_label      := v_new->>'name';
    v_message    := 'New member ' || (v_new->>'name') || ' joined the firm';

  ELSE
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF v_event_type IS NOT NULL THEN
    INSERT INTO public.activity_feed (
      event_type, module, actor_id,
      target_table, target_id, target_label, message,
      parent_matter_id
    ) VALUES (
      v_event_type,
      v_module,
      auth.uid(),
      TG_TABLE_NAME,
      v_new_id,
      v_label,
      v_message,
      v_parent_matter_id
    );
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger re-creation not needed for this function either — same
-- reasoning as above, trg_activity_matters (migration 018) already
-- points at fn_activity_trigger() by name.



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 031_hearing_outcome_categorization.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 031: Hearing Outcome Categorization
-- ───────────────────────────────────────────────────────────────
-- Sprint 2, Work Package 4.
--
-- Adds a standardized, filterable outcome_category enum column to
-- matter_hearings, alongside the existing free-text outcome TEXT
-- column (which is preserved unchanged). The two fields are
-- complementary: the category gives reliable, filterable taxonomy
-- for reporting; the free-text field captures richer notes
-- (e.g., "Adjourned to 15 July — judge requested further submissions").
--
-- NOT converting outcome TEXT to an enum: that would risk data loss
-- on any pre-existing free-text values and is an unnecessary
-- structural change. Adding outcome_category as a new, nullable
-- column is purely additive, not a redesign.
--
-- Taxonomy (nine values, per the work package spec):
--   adjourned    — hearing postponed to a later date
--   mention      — brief procedural appearance, no substantive hearing
--   ruling       — court issued a ruling on a specific issue
--   judgment     — final judgment delivered
--   settlement   — matter settled between parties
--   withdrawn    — matter or hearing withdrawn
--   dismissed    — matter dismissed by the court
--   directions   — court gave procedural directions
--   other        — none of the above, details in free-text outcome
-- ═══════════════════════════════════════════════════════════════

CREATE TYPE public.hearing_outcome_category AS ENUM (
  'adjourned',
  'mention',
  'ruling',
  'judgment',
  'settlement',
  'withdrawn',
  'dismissed',
  'directions',
  'other'
);

ALTER TABLE public.matter_hearings
  ADD COLUMN outcome_category public.hearing_outcome_category;

COMMENT ON COLUMN public.matter_hearings.outcome_category IS
  'Standardized hearing outcome category for filtering and reporting. '
  'Nullable — only set when a hearing has concluded. Complements the '
  'free-text outcome column, which is preserved unchanged.';

-- Partial index: only indexes rows that have a category set, matching
-- the typical query pattern ("show all hearings with outcome X") —
-- unresolved hearings (NULL outcome_category) are never in the filter
-- results and do not need to be in this index.
CREATE INDEX idx_mh_outcome_category
  ON public.matter_hearings(matter_id, outcome_category)
  WHERE outcome_category IS NOT NULL;



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 032_realtime_publication.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 032: Enable Realtime Publication for Required Tables
-- ───────────────────────────────────────────────────────────────
-- Sprint 3A: Realtime Layer.
--
-- AUDIT FINDING: the supabase_realtime publication exists with
-- puballtables = false and ZERO tables enrolled (confirmed via
-- pg_publication_tables query against the live production database
-- before any code was written). Every postgres_changes subscription
-- currently returns nothing silently. This migration is the
-- foundational prerequisite for all realtime features.
--
-- TABLES ADDED:
--
--   notifications   — INSERT only. Each user only sees their own
--                     notifications (RLS: recipient_id = auth.uid()).
--                     The frontend subscription filters by recipient_id
--                     so each client only receives their own rows.
--                     Server-side RLS enforces this independently.
--
--   activity_feed   — INSERT only. All authenticated members see all
--                     activity (RLS: TRUE). No client-side filter
--                     needed; any new row is relevant to all users.
--
--   matters         — UPDATE only. INSERT is not needed for realtime
--                     because a newly created matter isn't visible to
--                     other users' active queries until they navigate
--                     to it — invalidating the list query on UPDATE
--                     is sufficient since matter_status changes,
--                     reassignments, and archives are the events
--                     users actually need to see in real time.
--                     INSERT on matters does need to invalidate the
--                     list, but refetchOnWindowFocus + the 2-min
--                     stale time already handles that adequately for
--                     a law firm context (new matters don't appear
--                     multiple times per minute). If INSERT realtime
--                     is needed later, add it here without affecting
--                     the UPDATE subscription logic.
--
--   matter_hearings — INSERT and UPDATE. The Dashboard's "today's
--                     hearings" and "upcoming hearings" widgets need
--                     to reflect new hearing entries and outcome
--                     updates as they happen during a court day.
--
-- TABLES DELIBERATELY NOT ADDED:
--   matter_notes, matter_entities, documents, matter_assignments —
--   these are lower-frequency, not surfaced on the real-time Dashboard
--   widgets, and their parent matter's UPDATE event already signals
--   something changed on that matter to anyone viewing its detail page.
--   Adding them would increase realtime traffic with minimal UX benefit.
--   Can be added in a later migration if requirements change.
-- ═══════════════════════════════════════════════════════════════

ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE public.activity_feed;
ALTER PUBLICATION supabase_realtime ADD TABLE public.matters;
ALTER PUBLICATION supabase_realtime ADD TABLE public.matter_hearings;



-- ═══════════════════════════════════════════════════════════════
-- MIGRATION: 033_dashboard_status_breakdown_rpc.sql
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- MOLMS Migration 033: Dashboard Status Breakdown RPC
-- ───────────────────────────────────────────────────────────────
-- Sprint 3A cleanup item.
--
-- PROBLEM: getMatterStatusBreakdown() in dashboard.service.ts
-- fetched ALL active matter rows (selecting only matter_status_id)
-- and counted them in JavaScript using a Map. At current scale this
-- is invisible as a performance issue. At 10 years of data with 50
-- active users, active matter count could reach several thousand —
-- still manageable, but architecturally wrong. A COUNT with GROUP BY
-- runs entirely in PostgreSQL, uses the existing idx_matters_dashboard
-- composite index, and returns only N rows (one per status) regardless
-- of total matter count. N is small and fixed: the number of
-- non-terminal statuses in matter_statuses, which is a lookup table
-- that rarely changes.
--
-- FIX: a STABLE, SECURITY DEFINER SQL function that performs the
-- GROUP BY server-side and returns typed rows. The frontend service
-- function calls this via .rpc() instead of the two-query pattern.
--
-- This function is STABLE (not VOLATILE) because it only reads data
-- and returns the same result for the same database state within a
-- single transaction. This allows the query planner to cache the
-- result within a single query execution if called multiple times.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_dashboard_status_breakdown()
RETURNS TABLE (
  status_code TEXT,
  label       TEXT,
  sort_order  INTEGER,
  count       INTEGER
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    ms.status_code::TEXT,
    ms.label,
    ms.sort_order,
    COUNT(m.id)::INTEGER AS count
  FROM public.matter_statuses ms
  LEFT JOIN public.matters m
    ON m.matter_status_id = ms.id
    AND m.is_archived = FALSE
  WHERE ms.is_terminal = FALSE
  GROUP BY ms.id, ms.status_code, ms.label, ms.sort_order
  ORDER BY ms.sort_order;
$$;

GRANT EXECUTE ON FUNCTION public.fn_dashboard_status_breakdown() TO authenticated;

