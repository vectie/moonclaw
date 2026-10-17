import { sha256 } from './book-outcome.js'
const need = (ok, message) => { if (!ok) throw new Error(message) }
const option = value => Array.isArray(value) ? value[0] : value
const phases = new Set(['draft', 'uncertain', 'submitted', 'superseded'])
const statuses = new Set(['Pending', 'Running', 'WaitingForInput', 'Succeeded', 'Failed', 'Cancelled'])

export function readRecovery(value, context) {
  need(value?.contract_version === 'moonclaw.blocked-recovery.v1' && value.session_key === context.session_key && value.run_id === context.run_id && value.cwd === context.cwd, 'Recovery belongs to another work thread, folder or run')
  need(typeof value.checkpoint === 'string' && /^sha256:[0-9a-f]{64}$/.test(value.checkpoint) && statuses.has(value.status) && Number.isSafeInteger(value.observed_at) && typeof value.can_resume === 'boolean', 'Invalid recovery checkpoint')
  need(typeof value.launch_pending === 'boolean' && (!value.can_resume || !value.launch_pending), 'Recovery has an active launch; refresh before continuing')
  if (value.resume_receipt !== null) need(value.resume_receipt && /^sha256:[0-9a-f]{64}$/.test(option(value.resume_receipt.checkpoint)) && /^sha256:[0-9a-f]{64}$/.test(value.resume_receipt.content_digest) && typeof value.resume_receipt.message_id === 'string' && value.resume_receipt.message_id.trim(), 'Invalid recovery receipt')
  need(Array.isArray(value.steps) && value.steps.length <= 10000 && Array.isArray(value.artifacts) && value.artifacts.length <= 10000, 'Invalid recovery evidence')
  const ids = new Set()
  for (const step of value.steps) {
    need(typeof step.id === 'string' && typeof step.step_id === 'string' && !ids.has(step.id) && statuses.has(step.status), 'Invalid or duplicate recovery step')
    ids.add(step.id)
  }
  const waiting = value.steps.filter(step => step.status === 'WaitingForInput')
  need(!value.can_resume || (value.status === 'WaitingForInput' && waiting.length === 1 && value.steps.every(step => ['Succeeded', 'Pending', 'WaitingForInput'].includes(step.status))), 'Recovery does not establish a safe input checkpoint')
  need(value.artifacts.every(item => typeof item.id === 'string' && Number.isSafeInteger(item.version)), 'Invalid retained artifact')
  return structuredClone(value)
}

export function describeRecovery(snapshot) {
  const text = value => option(value) || 'Not recorded'
  return [
    `Run ${snapshot.run_id} · ${snapshot.status}`,
    `Observed ${new Date(snapshot.observed_at).toISOString()} · refresh before continuing`,
    ...snapshot.steps.map(step => `${step.status === 'Succeeded' ? 'Retained completed work' : step.status === 'WaitingForInput' ? 'Needs your input' : step.status}: ${step.step_id}\n${text(step.summary)}${option(step.error) ? '\n' + text(step.error) : ''}`),
    'Retained artifacts: ' + (snapshot.artifacts.map(item => `${option(item.logical_key) || item.id} @${item.version}`).join(', ') || 'None recorded'),
    snapshot.guidance,
    'Execution status does not establish acceptance. Unknown external effects require their existing reconciliation workflow.'
  ].join('\n\n')
}

export class BlockedRecovery {
  constructor(saved = null) {
    this.snapshot = null
    this.state = { checkpoint: '', draft: '', phase: 'draft', answer_digest: '' }
    if (saved !== null) {
      need(saved && typeof saved.checkpoint === 'string' && typeof saved.draft === 'string' && saved.draft.length <= 16000 && phases.has(saved.phase), 'Saved answer is unreadable; it was kept in browser storage')
      this.state = { checkpoint: saved.checkpoint, draft: saved.draft, phase: saved.phase, answer_digest: typeof saved.answer_digest === 'string' ? saved.answer_digest : '' }
    }
  }
  observe(value, context) {
    this.snapshot = readRecovery(value, context)
    const receipt = value.resume_receipt
    if (this.state.phase === 'uncertain' && option(receipt?.checkpoint) === this.state.checkpoint) {
      if (receipt.content_digest === this.state.answer_digest) this.state.phase = 'submitted'
      else this.state.phase = 'superseded'
    }
    if (!this.state.checkpoint && this.state.phase === 'draft') this.state.checkpoint = value.checkpoint
    return this.snapshot
  }
  edit(draft) {
    need(this.state.phase === 'draft', 'Reconcile the submitted answer before editing it')
    need(draft.length <= 16000, 'Keep the recovery answer within 16,000 characters')
    this.state.draft = draft
  }
  adopt() {
    need(this.snapshot?.can_resume, 'Refresh a resumable input checkpoint first')
    need(this.state.phase !== 'uncertain', 'Submission outcome remains uncertain; refresh or retry the same checkpoint')
    need(this.state.phase !== 'submitted' || this.snapshot.checkpoint !== this.state.checkpoint, 'This answer was already recorded; inspect its run rather than resubmitting')
    this.state = { ...this.state, checkpoint: this.snapshot.checkpoint, phase: 'draft' }
  }
  request() {
    need(this.snapshot?.can_resume && this.snapshot.checkpoint === this.state.checkpoint, 'The checkpoint changed; review its new evidence before using the retained answer')
    need(['draft', 'uncertain'].includes(this.state.phase), 'Review the current checkpoint before using an already resolved answer')
    need(this.state.draft.trim(), 'Supply the missing input before continuing')
    return { content: this.state.draft.trim(), expected_checkpoint: this.state.checkpoint }
  }
  async prepare() { return sha256(this.state.draft.trim()) }
  sending(answerDigest) { this.state.answer_digest = answerDigest; this.state.phase = 'uncertain' }
  acknowledged() { this.state.phase = 'submitted' }
}
