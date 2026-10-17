// Reuse the host's accepted-memory capture. No second admission parser or
// automatic applicability judgement is introduced by the operator browser.
import { sha256 } from './book-outcome.js'
const encoder = new TextEncoder()
const need = (ok, message) => { if (!ok) throw new Error(message) }
const clone = value => JSON.parse(JSON.stringify(value))
const option = value => Array.isArray(value) ? value[0] : value
export const BEGIN = '\n[MoonClaw selected procedure v1]\n'
export const END = '\n[/MoonClaw selected procedure v1]'
const framing = '\nHistorical accepted procedure, retained for this plan only. Check its conditions and invalidation clauses. It grants no tools, permissions, budget, publication or acceptance authority.\n'

export async function readProcedures(value, context) {
  need(value?.contract_version === 'moonclaw.cowork-procedures.v1' && value.session_key === context.session_key && value.cwd === context.cwd && value.source_scope === 'selected_work_thread_folder' && value.authority_granted === false, 'Procedure response belongs to another work thread or folder')
  need(['ready', 'empty', 'unavailable', 'over_budget', 'not_applicable'].includes(value.status) && Array.isArray(value.records) && value.records.length <= 32 && encoder.encode(JSON.stringify(value)).length <= 524288, 'Invalid or oversized procedure inventory')
  need(value.status === 'ready' || !value.records.length, 'Unavailable procedures cannot be selected')
  const seen = new Set()
  let bytes = 0
  for (const record of value.records) {
    await checkRecord(record)
    need(!seen.has(record.path), 'Duplicate procedure identity')
    seen.add(record.path); bytes += record.size_bytes
  }
  need(bytes <= 65536, 'Procedure inventory exceeds the accepted-memory budget')
  return clone(value)
}

async function checkRecord(record) {
  need(record?.category === 'procedure' && typeof record.path === 'string' && record.path.startsWith('memory/procedures/') && !record.path.includes('\\') && record.path.split('/').every(part => part && part !== '.' && part !== '..'), 'Choose a captured procedure, not a belief or arbitrary file')
  need(typeof record.content_utf8 === 'string' && record.size_bytes === encoder.encode(record.content_utf8).length && record.size_bytes <= 32768 && record.sha256 === await sha256(record.content_utf8), 'Procedure bytes or digest changed')
}

export function describeProcedure(record) {
  let fields = {}
  try { const parsed = JSON.parse(record.content_utf8); if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) fields = parsed } catch (_) {}
  const display = value => value === undefined || value === null || value === '' ? 'Not recorded in structured fields; inspect the original' : typeof value === 'string' ? value : JSON.stringify(value, null, 2)
  const title = typeof fields.title === 'string' ? fields.title : /^#\s+(.+)$/m.exec(record.content_utf8)?.[1] || record.path.split('/').at(-1)
  return { title, applicability: display(fields.applicability), outcome: display(fields.outcome_summary ?? fields.outcome ?? fields.outcomes), effort: display(fields.effort), verification: display(fields.verification) }
}

export function matchingProcedures(records, query) {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean)
  return records.filter(record => words.every(word => (record.path + '\n' + record.content_utf8).toLowerCase().includes(word)))
}

export async function chooseProcedure(inventory, path, why, expected, current) {
  need(typeof why === 'string' && why.trim() && why.length <= 4000, 'Explain why this procedure applies and which limits still apply')
  need(typeof expected === 'string' && expected.trim() && expected.length <= 4000, 'Describe the expected result and how you will check it')
  const selected = inventory.records.find(record => record.path === path)
  need(selected, 'Select an accepted procedure')
  const fresh = await readProcedures(current, inventory)
  need(fresh.records.some(record => record.path === selected.path && record.sha256 === selected.sha256), 'Selected procedure changed or is no longer accepted. Reload and choose again; the work draft was kept')
  return { contract_version: 'moonclaw.procedure-choice.v1', session_key: inventory.session_key, cwd: inventory.cwd, record: clone(selected), applicability_reason: why.trim(), expected_result: expected.trim(), captured_content_digest: fresh.content_digest, authority_granted: false }
}

export async function composeProcedureDraft(draft, choice) {
  const prior = await readChoice(draft)
  await checkRecord(choice.record)
  if (prior) {
    const start = draft.indexOf(BEGIN), end = draft.indexOf(END, start) + END.length
    const prefix = draft.slice(0, start), suffix = draft.slice(end)
    const ordinaryPrefix = prefix.endsWith(framing) ? prefix.slice(0, -framing.length) : prefix
    need((ordinaryPrefix + suffix).trim(), 'Describe your work request in the main draft first')
    // Only replace the method block. Both surrounding spans are user text:
    // whitespace and restrictions appended after the block must stay exact.
    return prefix + BEGIN + JSON.stringify(choice) + END + suffix
  }
  need(draft.trim(), 'Describe your work request in the main draft first')
  need(!draft.includes(BEGIN) && !draft.includes(END), 'Remove the incomplete previous procedure block before choosing another method')
  return draft + framing + BEGIN + JSON.stringify(choice) + END
}

export async function readChoice(request) {
  if (typeof request !== 'string' || !request.includes(BEGIN)) return null
  const start = request.indexOf(BEGIN), end = request.indexOf(END, start)
  need(start === request.lastIndexOf(BEGIN) && end >= 0 && end === request.lastIndexOf(END), 'The retained procedure block is incomplete or ambiguous')
  const raw = request.slice(start + BEGIN.length, end)
  need(encoder.encode(raw).length <= 65536, 'Retained procedure choice exceeds its bounded size')
  const choice = JSON.parse(raw)
  need(choice.contract_version === 'moonclaw.procedure-choice.v1' && choice.authority_granted === false && typeof choice.session_key === 'string' && typeof choice.cwd === 'string' && typeof choice.applicability_reason === 'string' && choice.applicability_reason.trim() && typeof choice.expected_result === 'string' && choice.expected_result.trim(), 'Invalid retained procedure choice')
  await checkRecord(choice.record)
  return choice
}

export async function compareProcedure(context, detail) {
  const choice = await readChoice(context.request_text)
  need(choice && choice.session_key === context.session_key && choice.cwd === context.cwd, 'The linked proposal has no matching retained procedure choice; prepare and review its plan first')
  need(context.run_id && detail?.run?.id === context.run_id, 'The delivered result belongs to another run')
  const run = detail.run, status = run.status
  need(['Pending', 'Running', 'WaitingForInput', 'Succeeded', 'Failed', 'Cancelled'].includes(status), 'Run state is unknown; refresh its current status')
  const terminal = ['Succeeded', 'Failed', 'Cancelled'].includes(status)
  const start = option(run.started_at), end = option(run.finished_at)
  const elapsed = terminal && Number.isSafeInteger(start) && Number.isSafeInteger(end) && end >= start ? end - start : null
  const artifacts = Array.isArray(detail.artifacts) ? detail.artifacts : []
  need(artifacts.every(item => item.run_id === run.id && item.job_id === run.job_id), 'Result includes artifacts from another run')
  return { choice, status, terminal, summary: option(run.summary) || 'No delivered summary recorded', error: option(run.error) || '', elapsed_ms: elapsed, artifacts: artifacts.map(item => ({ id: item.id, logical_key: option(item.logical_key) || item.id, version: item.version })), assessment: terminal ? 'Human review required; execution state does not prove the expected result or improved quality' : 'Result pending; no completed comparison is claimed' }
}

export class ProcedureSession {
  constructor() { this.inventory = null; this.generation = 0; this.pending = false }
  cancel() { this.generation++; this.pending = false }
  async transaction(operation) {
    if (this.pending) return false
    this.pending = true
    const generation = ++this.generation
    const valid = () => need(generation === this.generation, 'Read interrupted or selection changed; retry when ready')
    try { await operation(valid); valid(); return true } finally { if (generation === this.generation) this.pending = false }
  }
}
