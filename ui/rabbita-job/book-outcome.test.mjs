import assert from 'node:assert/strict'
import test from 'node:test'
import { readFile, writeFile } from 'node:fs/promises'
import { webcrypto } from 'node:crypto'
import { OutcomeSession, exportOutcome, readHandoff, readOutcomeReceipt, readSource, sha256 } from './book-outcome.js'
import { bindBookOutcome } from './book-outcome-controls.js'
if (!globalThis.crypto) globalThis.crypto = webcrypto
const source = JSON.parse(await readFile(process.env.MOONCLAW_BOOK_SOURCE || new URL('./fixtures/book-native-source.json', import.meta.url), 'utf8'))
const parsed = await readSource(source)
const fields = () => ({ observed_at: 1791334800, outcome_summary: 'Synthetic local fixture interpretation: exact native-produced text was retained. No real provider, customer acceptance, cash or production reviewer was exercised.', gaps: Object.fromEntries(['information', 'recognition', 'decisiveness'].map(key => [key, { severity: 0, summary: `Explicit fixture statement: no additional ${key} gap is asserted within this bounded local text-retention check.` }])) })
const packRaw = await exportOutcome(source, fields()), pack = JSON.parse(packRaw), payload = JSON.parse(pack.payload_json)
const receipt = (state, reviews = []) => JSON.stringify({ contract_version: 'moonbook.product-outcome-readback.v1', package_digest: pack.package_digest, package: pack, progress: { submission: payload.submission.submission, title: payload.submission.deliverable_title, state }, reviews, activation_authorized: false, external_side_effects_applied: false })
const changedSource = async text => {
  const changed = structuredClone(source), context = JSON.parse(changed.source_json)
  changed.artifacts[0].text = text; context.artifacts[0].digest = await sha256(text); context.artifacts[0].byte_length = new TextEncoder().encode(text).length
  changed.source_json = JSON.stringify(context); changed.source_digest = await sha256(changed.source_json)
  return changed
}

test('production native completed run bytes become deterministic compatible retained outcome package', async () => {
  assert.equal(parsed.context.run.status, 'Succeeded')
  assert.equal(parsed.context.artifacts[0].record.metadata.origin, 'deterministic-local-fixture')
  assert.equal(parsed.context.artifacts[0].record.metadata.provider_executed, false)
  assert.match(source.artifacts[0].text, /报告 <&>\u0000/)
  assert.ok(source.artifacts[0].text.startsWith('\uFEFF'))
  assert.equal(payload.artifacts[1].text, source.artifacts[0].text)
  assert.equal(await exportOutcome(source, fields()), packRaw)
  assert.equal((await readHandoff(packRaw)).source.source_json, source.source_json)
  assert.equal(payload.submission.source_product, 'moonclaw')
  assert.equal(payload.submission.capability_id, undefined)
  assert.match(payload.submission.deliverable_summary, /does not establish correctness/)
  if (process.env.MOONCLAW_BOOK_PACKAGE_OUTPUT) await writeFile(process.env.MOONCLAW_BOOK_PACKAGE_OUTPUT, packRaw)
})

test('changed source and interpretation get distinct identities; malformed and binary sources are refused', async () => {
  const changed = await changedSource(source.artifacts[0].text + ' new revision')
  assert.notEqual(JSON.parse(JSON.parse(await exportOutcome(changed, fields())).payload_json).submission.submission.record_id, payload.submission.submission.record_id)
  const edited = fields(); edited.outcome_summary += ' Revised interpretation'
  assert.notEqual(JSON.parse(await exportOutcome(source, edited)).package_digest, pack.package_digest)
  const invalid = structuredClone(source); invalid.artifacts[0].text += 'tamper'
  await assert.rejects(readSource(invalid), /bytes changed/)
  const binary = structuredClone(source), context = JSON.parse(binary.source_json)
  context.artifacts[0].record.content_type = 'application/pdf'; binary.source_json = JSON.stringify(context); binary.source_digest = await sha256(binary.source_json)
  await assert.rejects(readSource(binary), /text type/)
  const running = structuredClone(source), runContext = JSON.parse(running.source_json)
  runContext.run.status = 'Running'; running.source_json = JSON.stringify(runContext); running.source_digest = await sha256(running.source_json)
  await assert.rejects(readSource(running), /completed run/)
  await assert.rejects(sha256('\ud800'), /without loss/)
  const huge = await changedSource('x'.repeat(8388608)); await assert.rejects(exportOutcome(huge, fields()), /8 MiB/)
})

test('interpretation and all Three-Gap decisions are explicitly authored, with proposal only when required', async () => {
  const empty = fields(); empty.outcome_summary = ''; await assert.rejects(exportOutcome(source, empty), /interpretation/)
  const missing = fields(); delete missing.gaps.information.severity; await assert.rejects(exportOutcome(source, missing), /severity/)
  const present = fields(); present.gaps.information.severity = 2; await assert.rejects(exportOutcome(source, present), /capability ID/)
  present.capability = { id: 'fixture.retention', version: '1', summary: 'Synthetic proposal only; independent Book assessment remains required' }
  assert.equal(JSON.parse(JSON.parse(await exportOutcome(source, present)).payload_json).submission.capability_id, 'fixture.retention')
})

test('receipt return binds exact source and retains rejection, revision and escalation without authority', async () => {
  for (const [state, disposition] of [['deliverable_review_required', 'Revise'], ['deliverable_rejected', 'Reject'], ['deliverable_review_required', 'Escalate'], ['continue_required', 'Accept'], ['assessment_review_required', 'Revise'], ['assessment_rejected', 'Reject'], ['reviewed_source_available', 'Accept']]) {
    const raw = receipt(state, [{ disposition, summary: 'Synthetic fixture decision only' }])
    const loaded = await readOutcomeReceipt(raw, pack.package_digest)
    assert.equal(loaded.source.artifacts[0].text, source.artifacts[0].text)
    assert.equal(loaded.receipt.reviews[0].disposition, disposition)
  }
  await assert.rejects(readOutcomeReceipt(receipt('continue_required'), 'sha256:' + '0'.repeat(64)), /another handoff/)
  const wrong = JSON.parse(receipt('continue_required')); wrong.progress.submission.record_version = '999'
  await assert.rejects(readOutcomeReceipt(JSON.stringify(wrong)), /exact submission/)
  const forged = JSON.parse(receipt('continue_required')); forged.activation_authorized = true
  await assert.rejects(readOutcomeReceipt(JSON.stringify(forged)), /authority/)
})

test('session preserves prior handoff across read failure, source change, editing interruption, old receipt and reload', async () => {
  const session = new OutcomeSession(); session.edit(fields(), source.artifacts.map(item => item.id))
  await session.transaction(valid => session.freeze(source, valid))
  await session.transaction(valid => session.export(async () => source, valid))
  assert.equal(session.state.handoff, packRaw)
  await assert.rejects(session.transaction(valid => session.export(async () => { throw new Error('read failed') }, valid)), /read failed/)
  assert.equal(session.state.handoff, packRaw)
  const changed = await changedSource('changed output')
  await assert.rejects(session.transaction(valid => session.export(async () => changed, valid)), /changed since selection/)
  assert.equal(session.state.handoff, packRaw)
  let release
  const pending = session.transaction(valid => session.export(() => new Promise(resolve => { release = resolve }), valid))
  assert.equal(await session.transaction(() => assert.fail('duplicate action')), false)
  session.edit({ ...fields(), outcome_summary: 'Draft changed while read was pending' }, session.state.selected)
  release(source); await assert.rejects(pending, /interpretation or connection changed/)
  assert.equal(session.state.handoff, packRaw)
  await session.transaction(valid => session.freeze(changed, valid))
  assert.equal(session.state.history[0].handoff, packRaw)
  session.edit(fields(), changed.artifacts.map(item => item.id))
  await session.transaction(valid => session.export(async () => changed, valid))
  await assert.rejects(session.transaction(valid => session.receive(receipt('reviewed_source_available'), valid)), /another handoff/)
  const restored = new OutcomeSession()
  await restored.transaction(valid => restored.restore(JSON.stringify({ contract_version: 'moonclaw.book-draft-recovery.v1', state: session.state }), valid))
  assert.equal(restored.state.handoff, session.state.handoff)
  assert.equal(restored.state.history[0].handoff, packRaw)
  await restored.transaction(valid => restored.open(packRaw, valid))
  await restored.transaction(valid => restored.receive(receipt('continue_required'), valid))
  await restored.transaction(valid => restored.receive(receipt('deliverable_review_required'), valid))
  assert.equal(restored.state.receipts.length, 2, 'Older observation is retained separately, never promoted to current status')
  restored.edit({ ...fields(), outcome_summary: 'A new explicitly authored interpretation' }, source.artifacts.map(item => item.id))
  await restored.transaction(valid => restored.export(async () => source, valid))
  assert.equal(restored.state.receipts.length, 0, 'Book decisions never carry onto a changed interpretation')
  assert.equal(restored.state.history.at(-1).receipts.length, 2)
})

class Node {
  constructor() { this.value = ''; this.textContent = ''; this.dataset = {}; this.files = []; this.checked = false; this.isConnected = true; this.events = new Map() }
  addEventListener(event, fn, options = {}) { this.events.set(event, fn); options.signal?.addEventListener('abort', () => this.events.delete(event), { once: true }) }
  async fire(event) { return this.events.get(event)?.() }
}
function surface() {
  const nodes = new Map(), saved = new Map(), downloads = []
  const document = { getElementById(id) { if (!nodes.has(id)) nodes.set(id, new Node()); return nodes.get(id) } }
  const get = key => document.getElementById('claw-book-' + key)
  get('context').textContent = JSON.stringify({ run_id: parsed.context.run.id, status: parsed.context.run.status, artifacts: parsed.context.artifacts.map(item => ({ id: item.record.id })) })
  const storage = { getItem: key => saved.get(key), setItem: (key, value) => saved.set(key, value) }
  let version = 0
  const transport = () => ({ base: () => 'http://fixture', epoch: () => version })
  return { document, get, storage, downloads, transport, invalidate() { version++ }, download: (raw, name) => downloads.push({ raw, name }) }
}

test('shipped controls preserve draft on duplicate clicks, connection change, read failure and file reopens', async () => {
  const ui = surface(), replies = []; let calls = 0
  const fetch = async () => { calls++; if (replies.length) await replies.shift(); return { ok: true, json: async () => source } }
  const binding = bindBookOutcome(ui.document, { ...ui, fetch })
  const value = fields(); ui.get('summary').value = value.outcome_summary; ui.get('observed').value = new Date(value.observed_at * 1000).toISOString().replace('.000Z', 'Z')
  for (const key of Object.keys(value.gaps)) { ui.get(key + '-severity').value = '0'; ui.get(key + '-summary').value = value.gaps[key].summary }
  ui.get('choose-0').checked = true; await ui.get('choose-0').fire('change')
  let release; replies.push(new Promise(resolve => { release = resolve }))
  const first = ui.get('freeze').fire('click'); await ui.get('freeze').fire('click'); release(); await first
  assert.equal(calls, 1); assert.ok(binding.session.state.source)
  await ui.get('export').fire('click'); assert.equal(ui.downloads.length, 1)
  assert.equal(ui.downloads[0].raw, packRaw)
  replies.push(new Promise(resolve => { release = resolve }))
  const interrupted = ui.get('export').fire('click'); ui.invalidate(); release(); await interrupted
  assert.equal(ui.downloads.length, 1); assert.match(ui.get('status').textContent, /gateway access changed/)
  ui.get('receipt').files = [{ size: 100, text: async () => receipt('deliverable_rejected') }]
  await ui.get('receipt').fire('change'); assert.match(ui.get('readback').textContent, /deliverable_rejected/)
  ui.get('receipt').files = [{ size: 10, text: async () => { throw new Error('file read failure') } }]
  await ui.get('receipt').fire('change'); assert.match(ui.get('readback').textContent, /deliverable_rejected/)
  assert.equal(binding.session.state.handoff, packRaw)
  await ui.get('download').fire('click'); assert.equal(ui.downloads.at(-1).raw, packRaw)
  assert.ok(ui.storage.getItem('moonclaw-book-draft-v1:http://fixture:' + parsed.context.run.id))
})

test('actual Book production CLI and fixture-governed receipts reopen exact native Claw bytes', { skip: !process.env.MOONCLAW_BOOK_RECEIPT_DIR }, async () => {
  for (const name of ['cli-import', 'cli-read', 'accepted', 'rejected', 'revision', 'escalation']) {
    const raw = await readFile(process.env.MOONCLAW_BOOK_RECEIPT_DIR + '/' + name + '.json', 'utf8')
    const wrapper = JSON.parse(raw), receiptRaw = wrapper.result ? JSON.stringify(wrapper.result) : raw
    const returned = await readOutcomeReceipt(receiptRaw, pack.package_digest)
    assert.equal(returned.source.artifacts[0].text, source.artifacts[0].text)
    if (name === 'accepted') assert.equal(returned.receipt.progress.state, 'reviewed_source_available')
    if (name === 'rejected') assert.equal(returned.receipt.progress.state, 'deliverable_rejected')
  }
})
