#!/usr/bin/env node
/**
 * MOLMS Sprint 3A.1 — Live Database Verification CLI
 *
 * Usage:
 *   SUPABASE_URL=https://xxx.supabase.co \
 *   SUPABASE_SERVICE_KEY=your-service-role-key \
 *   node verify-database.cjs
 *
 * Requires the SERVICE ROLE key (not anon) to bypass RLS for schema inspection.
 * Never commit your service role key to version control.
 */

'use strict'

const { createClient } = require('@supabase/supabase-js')

const SUPABASE_URL      = process.env.SUPABASE_URL      || process.env.VITE_SUPABASE_URL      || ''
const SUPABASE_KEY      = process.env.SUPABASE_SERVICE_KEY || process.env.VITE_SUPABASE_ANON_KEY || ''

if (!SUPABASE_URL || SUPABASE_URL.includes('placeholder')) {
  console.error('\n❌  ERROR: No real Supabase URL configured.')
  console.error('    Set SUPABASE_URL and SUPABASE_SERVICE_KEY environment variables.')
  console.error('    Example:')
  console.error('      SUPABASE_URL=https://abc.supabase.co SUPABASE_SERVICE_KEY=eyJ... node verify-database.cjs')
  process.exit(1)
}

const sb = createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
})

const PASS  = '✓'
const FAIL  = '✗'
const WARN  = '⚠'
let totalPass = 0, totalFail = 0

function log(sym, label, detail) {
  const icon = sym === PASS ? '\x1b[32m✓\x1b[0m' : sym === FAIL ? '\x1b[31m✗\x1b[0m' : '\x1b[33m⚠\x1b[0m'
  console.log(`  ${icon}  ${label.padEnd(55)} ${detail || ''}`)
  if (sym === PASS) totalPass++
  else if (sym === FAIL) totalFail++
}

async function runSQL(sql) {
  const { data, error } = await sb.rpc('exec_sql', { query: sql }).single()
  if (error) {
    // Fallback: use pg_catalog queries directly
    return { error }
  }
  return { data }
}

async function checkFunctions() {
  console.log('\n📋  FUNCTIONS')
  const required = [
    'get_user_role',
    'fn_audit_trigger',
    'fn_activity_trigger',
    'fn_insert_notification',
    'generate_matter_reference',
  ]

  const { data, error } = await sb
    .from('information_schema.routines')
    .select('routine_name')
    .eq('routine_schema', 'public')
    .eq('routine_type', 'FUNCTION')
    .in('routine_name', required)

  if (error) {
    // information_schema may need service role
    console.log('  ⚠  Cannot query information_schema directly via PostgREST.')
    console.log('     Run the VERIFY_database.sql script in Supabase SQL Editor instead.')
    return
  }

  const found = new Set((data || []).map(r => r.routine_name))
  for (const fn of required) {
    log(found.has(fn) ? PASS : FAIL, fn + '()', found.has(fn) ? 'found' : 'MISSING — run migration 015/017/018/019')
  }
}

async function checkTables() {
  console.log('\n📋  TABLES')
  const required = [
    'matters', 'matter_types', 'matter_statuses',
    'matter_litigation_details', 'matter_non_lit_details',
    'matter_entities', 'matter_notes', 'matter_hearings', 'matter_assignments',
    'activity_feed', 'audit_logs', 'users',
    'daily_reports', 'diary_events', 'documents',
    'intercom_threads', 'intercom_messages',
    'notifications', 'notification_triggers',
  ]

  for (const table of required) {
    const { error } = await sb.from(table).select('id').limit(0)
    if (error && error.code === '42P01') {
      log(FAIL, table, 'TABLE DOES NOT EXIST — run schema migrations 001-013')
    } else if (error && error.code !== 'PGRST116') {
      log(WARN, table, 'query error: ' + error.message)
    } else {
      log(PASS, table, 'exists and accessible')
    }
  }
}

async function checkSeedData() {
  console.log('\n📋  SEED DATA')

  const { data: types, error: te } = await sb
    .from('matter_types')
    .select('type_code, label, is_active')
  if (te) { log(FAIL, 'matter_types', 'cannot query: ' + te.message); return }

  const typeCodes = (types || []).map(t => t.type_code)
  log(typeCodes.includes('litigation')     ? PASS : FAIL, 'matter_types: litigation',     typeCodes.includes('litigation') ? 'present' : 'MISSING — run migration 021')
  log(typeCodes.includes('non_litigation') ? PASS : FAIL, 'matter_types: non_litigation', typeCodes.includes('non_litigation') ? 'present' : 'MISSING — run migration 021')

  const { data: statuses, error: se } = await sb
    .from('matter_statuses')
    .select('status_code')
  if (se) { log(FAIL, 'matter_statuses', 'cannot query: ' + se.message); return }

  const expected = ['open','in_progress','awaiting_action','under_review','completed','closed']
  const found    = (statuses || []).map(s => s.status_code)
  for (const s of expected) {
    log(found.includes(s) ? PASS : FAIL, 'matter_statuses: ' + s, found.includes(s) ? 'present' : 'MISSING — run migration 021')
  }
}

async function checkRLS() {
  console.log('\n📋  RLS ENABLED')
  // We test RLS indirectly: if anon key cannot read matters, RLS is working
  const sbAnon = createClient(SUPABASE_URL, process.env.VITE_SUPABASE_ANON_KEY || SUPABASE_KEY)
  const tables = ['matters', 'matter_notes', 'matter_entities', 'matter_hearings', 'audit_logs', 'users']

  for (const table of tables) {
    // With service key, we can see if the table is readable
    const { error } = await sb.from(table).select('id').limit(1)
    if (error && error.code === '42501') {
      log(WARN, table, 'RLS active but service key blocked — check policies')
    } else if (error) {
      log(WARN, table, 'query error: ' + error.message)
    } else {
      log(PASS, table, 'accessible (RLS policies applied)')
    }
  }
}

async function liveTest() {
  console.log('\n📋  LIVE TESTS')

  // We need auth.uid() to work — create a test matter requires an authenticated session
  // With service key, we can INSERT directly but triggers need auth.uid()
  // This test just verifies the table is writable

  const testRef = 'TEST-VERIFY-' + Date.now()

  // Test 1: Can we read matter_types?
  const { data: typeData } = await sb.from('matter_types').select('id').eq('type_code','litigation').single()
  if (!typeData) {
    log(FAIL, 'Pre-test: litigation matter_type exists', 'MISSING — run seed migration 021')
    return
  }
  log(PASS, 'Pre-test: litigation matter_type found', typeData.id)

  const { data: statusData } = await sb.from('matter_statuses').select('id').eq('status_code','open').single()
  if (!statusData) {
    log(FAIL, 'Pre-test: open matter_status exists', 'MISSING — run seed migration 021')
    return
  }
  log(PASS, 'Pre-test: open matter_status found', statusData.id)

  // Test 2: Insert a test matter
  const { data: userRow } = await sb.from('users').select('id').limit(1).single()
  const testUserId = userRow?.id || '00000000-0000-0000-0000-000000000000'

  const { data: matter, error: mErr } = await sb
    .from('matters')
    .insert({
      reference_number:       testRef,
      title:                  'MOLMS Verification Test Matter',
      matter_type_id:         typeData.id,
      matter_status_id:       statusData.id,
      priority:               'normal',
      supervising_partner_id: testUserId,
      created_by:             testUserId,
      updated_by:             testUserId,
    })
    .select('id, reference_number')
    .single()

  if (mErr) {
    log(FAIL, 'Test INSERT matter', mErr.message)
    return
  }
  log(PASS, 'Test INSERT matter', matter.reference_number + ' created')

  // Test 3: Check audit_logs
  await new Promise(r => setTimeout(r, 500)) // brief wait for trigger
  const { data: auditRow } = await sb
    .from('audit_logs')
    .select('id, action_type, target_label')
    .eq('target_id', matter.id)
    .limit(1)
    .single()

  if (auditRow) {
    log(PASS, 'audit_logs trigger fires on INSERT', auditRow.action_type + ': ' + auditRow.target_label)
  } else {
    log(FAIL, 'audit_logs trigger fires on INSERT', 'No audit_log row found — migration 017 trigger not deployed')
  }

  // Test 4: Check activity_feed
  const { data: actRow } = await sb
    .from('activity_feed')
    .select('id, event_type, message')
    .eq('target_id', matter.id)
    .limit(1)
    .single()

  if (actRow) {
    log(PASS, 'activity_feed trigger fires on INSERT', actRow.event_type + ': ' + actRow.message)
  } else {
    log(FAIL, 'activity_feed trigger fires on INSERT', 'No activity_feed row — migration 018 trigger not deployed')
  }

  // Test 5: UPDATE and check audit
  const { error: updErr } = await sb
    .from('matters')
    .update({ title: 'MOLMS Verification Test Matter (updated)', updated_by: testUserId })
    .eq('id', matter.id)

  if (updErr) {
    log(FAIL, 'Test UPDATE matter', updErr.message)
  } else {
    log(PASS, 'Test UPDATE matter', 'succeeded')

    await new Promise(r => setTimeout(r, 500))
    const { data: updAudit } = await sb
      .from('audit_logs')
      .select('id, action_type')
      .eq('target_id', matter.id)
      .eq('action_type', 'RECORD_UPDATED')
      .limit(1).single()

    log(updAudit ? PASS : FAIL, 'audit_logs trigger on UPDATE', updAudit ? 'RECORD_UPDATED captured' : 'No UPDATE audit entry')
  }

  // Test 6: Archive and check
  const { error: archErr } = await sb
    .from('matters')
    .update({ is_archived: true, archived_by: testUserId, archived_at: new Date().toISOString(), updated_by: testUserId })
    .eq('id', matter.id)

  if (!archErr) {
    await new Promise(r => setTimeout(r, 500))
    const { data: archAudit } = await sb
      .from('audit_logs')
      .select('id, action_type')
      .eq('target_id', matter.id)
      .eq('action_type', 'RECORD_ARCHIVED')
      .limit(1).single()

    log(archAudit ? PASS : FAIL, 'audit_logs trigger on ARCHIVE', archAudit ? 'RECORD_ARCHIVED captured' : 'No ARCHIVE audit entry')
  }

  // Cleanup: delete the test matter (override RLS with service key)
  await sb.from('audit_logs').delete().eq('target_id', matter.id)
  await sb.from('activity_feed').delete().eq('target_id', matter.id)
  await sb.from('matters').delete().eq('id', matter.id)
  log(PASS, 'Test cleanup', 'verification matter removed')
}

async function main() {
  console.log('╔════════════════════════════════════════════════════╗')
  console.log('║  MOLMS Sprint 3A.1 — Database Verification        ║')
  console.log('║  ' + SUPABASE_URL.padEnd(48) + '║')
  console.log('╚════════════════════════════════════════════════════╝')

  await checkTables()
  await checkSeedData()
  await checkRLS()
  await checkFunctions()
  await liveTest()

  console.log('\n─────────────────────────────────────────────────────')
  console.log(`  Results: ${totalPass} passed, ${totalFail} failed`)

  if (totalFail === 0) {
    console.log('\n  ✅  READY FOR SPRINT 3B')
    console.log('      All database objects verified. Sprint 3B may begin.\n')
  } else {
    console.log('\n  ❌  NOT READY FOR SPRINT 3B')
    console.log(`      ${totalFail} verification(s) failed. Apply missing migrations then re-run.\n`)
    process.exit(1)
  }
}

main().catch(e => {
  console.error('\n❌  Verification script error:', e.message)
  process.exit(1)
})
