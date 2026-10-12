// Completed output is evidence. Book alone owns its existing review decisions.
// All hashing covers exact UTF-8 bytes; retained output is never normalized.
export const PACKAGE_LIMIT = 8 * 1024 * 1024
export const FILE_LIMIT = 16 * 1024 * 1024
const encoder = new TextEncoder()
const need = (ok, message) => { if (!ok) throw new Error(message) }
const json = value => JSON.stringify(value, null, 2) + '\n'
const clone = value => JSON.parse(JSON.stringify(value))
const stable = value => Array.isArray(value) ? value.map(stable) : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(key => [key, stable(value[key])])) : value
const same = (left, right) => JSON.stringify(stable(left)) === JSON.stringify(stable(right))
const string = (value, label) => { need(typeof value === 'string' && value.trim() && value.length <= 4000, `Enter ${label} (up to 4000 characters)`); return value.trim() }
const option = value => Array.isArray(value) ? value[0] : value
const textType = media => typeof media === 'string' && (media.startsWith('text/') || media === 'application/json')
export async function sha256(text) {
  need(typeof text === 'string', 'Expected retained UTF-8 text')
  // Reject unpaired UTF-16 surrogates, which TextEncoder would silently replace.
  need(new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(encoder.encode(text)) === text, 'Retained text cannot round-trip to UTF-8 without loss')
  const bytes = new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(text)))
  return 'sha256:' + [...bytes].map(value => value.toString(16).padStart(2, '0')).join('')
}

export async function readSource(value) {
  const source = typeof value === 'string' ? JSON.parse(value) : clone(value)
  need(source?.contract_version === 'moonclaw.book-outcome-source.v1' && typeof source.source_json === 'string', 'Choose a frozen completed Claw source')
  need(encoder.encode(JSON.stringify(source)).length <= PACKAGE_LIMIT && await sha256(source.source_json) === source.source_digest, 'Frozen source changed or exceeds the Book 8 MiB limit')
  const context = JSON.parse(source.source_json), run = context.run
  need(context.contract_version === 'moonclaw.completed-text-source.v1' && typeof run?.id === 'string' && typeof run.job_id === 'string' && ['Succeeded', 'Failed', 'Cancelled'].includes(run.status) && Number.isSafeInteger(option(run.finished_at)), 'Source needs an exact completed run and recorded finish time')
  need(Array.isArray(context.artifacts) && context.artifacts.length > 0 && context.artifacts.length <= 32 && Array.isArray(source.artifacts) && source.artifacts.length === context.artifacts.length, 'Retain every selected source exactly once')
  const seen = new Set()
  for (let index = 0; index < context.artifacts.length; index++) {
    const item = context.artifacts[index], record = item.record, retained = source.artifacts[index]
    need(typeof record?.id === 'string' && !record.id.startsWith('synthetic:') && !seen.has(record.id) && record.run_id === run.id && record.job_id === run.job_id && Number.isSafeInteger(record.version) && record.version > 0 && textType(record.content_type) && retained?.id === record.id && typeof retained.text === 'string', 'Retained artifact identity, version, owner or text type does not match')
    seen.add(record.id)
    need(encoder.encode(retained.text).length === item.byte_length && await sha256(retained.text) === item.digest, 'Retained artifact bytes changed; no truncation or conversion is allowed')
  }
  return { source, context }
}

export async function exportOutcome(sourceValue, fields) {
  const { source, context } = await readSource(sourceValue)
  need(Number.isSafeInteger(fields.observed_at) && fields.observed_at >= 0 && fields.observed_at <= 2147483647, 'Enter observation time as whole UTC epoch seconds')
  const statement = { contract_version: 'moonclaw.completed-output-interpretation.v1', source_digest: source.source_digest, outcome_summary: string(fields.outcome_summary, 'your output interpretation and limits'), observed_at: fields.observed_at, gaps: {} }
  for (const key of ['information', 'recognition', 'decisiveness']) {
    const gap = fields.gaps?.[key]
    need(Number.isSafeInteger(gap?.severity) && gap.severity >= 0 && gap.severity <= 5, `Choose ${key} gap severity 0–5 explicitly`)
    statement.gaps[key] = { present: gap.severity > 0, severity: gap.severity, summary: string(gap.summary, `${key} gap explanation, including why absent when zero`) }
  }
  if (Object.values(statement.gaps).some(gap => gap.present) || fields.capability?.id || fields.capability?.version || fields.capability?.summary) {
    statement.capability = { id: string(fields.capability?.id, 'proposed capability ID'), version: string(fields.capability?.version, 'proposed capability version'), summary: string(fields.capability?.summary, 'proposed capability change') }
  }
  const statementText = json(statement), identity = await sha256(statementText)
  const prefix = 'moonclaw-' + source.source_digest.slice(7)
  const route = 'moonclaw://runs/' + encodeURIComponent(context.run.id)
  const evidence = async (id, text, media_type, provenance_ref) => ({ reference: { reference_id: id, reference_version: '1', digest: await sha256(text), provenance_ref }, text, media_type })
  const artifacts = [await evidence(prefix + '-context', source.source_json, 'application/json', route)]
  for (let index = 0; index < source.artifacts.length; index++) {
    const retained = source.artifacts[index], record = context.artifacts[index].record
    artifacts.push(await evidence(prefix + '-output-' + index, retained.text, record.content_type, route + '/artifacts/' + encodeURIComponent(record.id) + '/versions/' + record.version))
  }
  artifacts.push(await evidence(prefix + '-interpretation-' + identity.slice(7), statementText, 'application/json', route + '/operator-interpretation'))
  const submission = {
    contract_version: 'moonbook.bookkeeper.product_outcome_submission.v1',
    submission: { record_id: prefix + '-outcome-' + identity.slice(7), record_version: '1', record_digest: identity },
    source_product: 'moonclaw', deliverable_title: `Completed Claw output · ${context.run.id}`,
    deliverable_summary: `Recorded run status: ${context.run.status}. ${source.artifacts.length} selected UTF-8 artifact(s), retained with exact source identity. Run completion does not establish correctness, customer acceptance, cash or capability activation.`,
    outcome_summary: statement.outcome_summary, owner_route: route,
    evidence_refs: artifacts.map(item => item.reference), decision_evidence_id: artifacts.at(-1).reference.reference_id,
    observed_at: fields.observed_at, recorded_at: fields.observed_at,
  }
  for (const key of ['information', 'recognition', 'decisiveness']) submission[key + '_gap'] = { ...statement.gaps[key], evidence_refs: artifacts.map(item => item.reference.reference_id) }
  if (statement.capability) Object.assign(submission, { capability_id: statement.capability.id, capability_version: statement.capability.version, capability_change_digest: await sha256(JSON.stringify(statement.capability)), capability_summary: statement.capability.summary })
  const payload_json = json({ submission, artifacts })
  need(encoder.encode(payload_json).length <= PACKAGE_LIMIT, 'Retained output, interpretation and context exceed the Book 8 MiB package limit; no bytes were omitted')
  return json({ contract_version: 'moonbook.product-outcome-package.v1', package_digest: await sha256(payload_json), payload_json })
}

export async function readHandoff(raw) {
  need(typeof raw === 'string' && encoder.encode(raw).length <= FILE_LIMIT, 'Choose a saved handoff up to 16 MiB')
  const pack = JSON.parse(raw)
  need(pack.contract_version === 'moonbook.product-outcome-package.v1' && typeof pack.payload_json === 'string' && encoder.encode(pack.payload_json).length <= PACKAGE_LIMIT && await sha256(pack.payload_json) === pack.package_digest, 'Handoff bytes changed or its contract is unsupported')
  const payload = JSON.parse(pack.payload_json), submission = payload.submission, artifacts = payload.artifacts
  need(submission?.source_product === 'moonclaw' && Array.isArray(artifacts) && artifacts.length >= 3 && artifacts.length <= 34, 'Handoff is missing original Claw sources')
  const contextArtifact = artifacts[0], statementArtifact = artifacts.at(-1)
  const context = JSON.parse(contextArtifact.text), statement = JSON.parse(statementArtifact.text)
  need(statement.contract_version === 'moonclaw.completed-output-interpretation.v1' && Array.isArray(context.artifacts) && context.artifacts.length === artifacts.length - 2, 'Source context and interpretation do not match')
  const source = { contract_version: 'moonclaw.book-outcome-source.v1', source_digest: statement.source_digest, source_json: contextArtifact.text, artifacts: context.artifacts.map((item, index) => ({ id: item.record.id, text: artifacts[index + 1].text })) }
  const fields = { outcome_summary: statement.outcome_summary, observed_at: statement.observed_at, gaps: statement.gaps, capability: statement.capability }
  const reconstructed = JSON.parse(await exportOutcome(source, fields))
  need(same(reconstructed, pack), 'Handoff source, evidence references or authored interpretation changed')
  return { raw, pack, source, context, statement, fields }
}

export async function readOutcomeReceipt(raw, expectedDigest = null) {
  need(typeof raw === 'string' && encoder.encode(raw).length <= FILE_LIMIT, 'Choose a Book disposition receipt up to 16 MiB')
  const receipt = JSON.parse(raw)
  need(receipt.contract_version === 'moonbook.product-outcome-readback.v1' && receipt.activation_authorized === false && receipt.external_side_effects_applied === false && receipt.package_digest === receipt.package?.package_digest, 'Unsupported Book receipt or authority claim')
  const handoff = await readHandoff(json(receipt.package))
  need(!expectedDigest || receipt.package_digest === expectedDigest, 'Receipt belongs to another handoff; open its saved handoff separately to inspect the older source')
  const submission = JSON.parse(handoff.pack.payload_json).submission
  need(same(receipt.progress?.submission, submission.submission) && ['deliverable_review_required', 'deliverable_rejected', 'continue_required', 'assessment_review_required', 'assessment_rejected', 'reviewed_source_available'].includes(receipt.progress.state) && Array.isArray(receipt.reviews), 'Receipt progress is not bound to this exact submission')
  return { ...handoff, receipt, rawReceipt: raw }
}

// Testable transaction state, shared by the shipped controller and its tests.
export class OutcomeSession {
  constructor(saved = null) {
    this.state = saved || { fields: {}, selected: [], source: null, handoff: null, receipts: [], history: [] }
    this.version = 0; this.pending = false; this.generation = 0
  }
  edit(fields, selected) { this.state.fields = clone(fields); this.state.selected = [...selected]; this.version++ }
  cancel() { this.generation++; this.pending = false }
  async transaction(operation) {
    if (this.pending) return false
    this.pending = true
    const generation = ++this.generation, version = this.version
    const valid = () => { need(generation === this.generation && version === this.version, 'Selection, interpretation or connection changed; retry when ready') }
    try { await operation(valid); valid(); return true } finally { if (generation === this.generation) this.pending = false }
  }
  keepPrevious() {
    if (this.state.source || this.state.handoff) this.state.history.push(clone({ source: this.state.source, handoff: this.state.handoff, fields: this.state.fields, receipts: this.state.receipts }))
  }
  async freeze(value, valid) {
    const parsed = await readSource(value); valid()
    if (this.state.source?.source_digest !== parsed.source.source_digest) { this.keepPrevious(); this.state.source = parsed.source; this.state.handoff = null; this.state.receipts = [] }
  }
  async export(readCurrent, valid) {
    need(this.state.source, 'Freeze selected completed text outputs first')
    const original = clone(this.state.source), fields = clone(this.state.fields)
    const current = await readSource(await readCurrent(original)); valid()
    need(same(current.source, original), 'Run or artifact changed since selection; old saved handoff is preserved. Freeze the new version explicitly')
    const raw = await exportOutcome(original, fields); valid()
    if (this.state.handoff && this.state.handoff !== raw) { this.keepPrevious(); this.state.receipts = [] }
    this.state.handoff = raw
    return raw
  }
  async open(raw, valid) {
    const loaded = await readHandoff(raw); valid(); this.keepPrevious()
    this.state.source = loaded.source; this.state.handoff = raw; this.state.fields = loaded.fields; this.state.selected = loaded.source.artifacts.map(item => item.id); this.state.receipts = []
    return loaded
  }
  async receive(raw, valid) {
    need(this.state.handoff, 'Open the matching saved handoff before importing its Book receipt')
    const digest = JSON.parse(this.state.handoff).package_digest
    const loaded = await readOutcomeReceipt(raw, digest); valid()
    if (!this.state.receipts.includes(raw)) this.state.receipts.push(raw)
    return loaded
  }
  async restore(raw, valid) {
    need(typeof raw === 'string' && encoder.encode(raw).length <= 64 * 1024 * 1024, 'Choose draft recovery up to 64 MiB')
    const recovery = JSON.parse(raw), state = recovery.state
    need(recovery.contract_version === 'moonclaw.book-draft-recovery.v1' && state && Array.isArray(state.selected) && state.fields && Array.isArray(state.history) && Array.isArray(state.receipts), 'Unsupported draft recovery')
    for (const entry of [state, ...state.history]) {
      if (entry.source) await readSource(entry.source)
      if (entry.handoff) {
        const handoff = await readHandoff(entry.handoff)
        need(same(handoff.source, entry.source), 'Recovery source does not match its saved handoff')
        for (const receipt of entry.receipts || []) await readOutcomeReceipt(receipt, handoff.pack.package_digest)
      } else need(!entry.receipts?.length, 'Recovery receipt has no original handoff')
    }
    valid(); this.keepPrevious()
    const previous = this.state.history
    this.state = clone(state)
    this.state.history = previous.concat(this.state.history)
  }
}

export { installBookOutcome } from './book-outcome-controls.js'
