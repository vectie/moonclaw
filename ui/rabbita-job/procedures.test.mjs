import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { webcrypto } from 'node:crypto'
import { sha256 } from './book-outcome.js'
import { readProcedures, describeProcedure, matchingProcedures, chooseProcedure, composeProcedureDraft, readChoice, compareProcedure, ProcedureSession, BEGIN, END } from './procedures.js'
import { bindProcedures } from './procedure-controls.js'
if (!globalThis.crypto) globalThis.crypto = webcrypto
const encode = text => new TextEncoder().encode(text)
const context = () => ({ session_key: 'work:fixture', cwd: '/fixture/book', cwd_override: '', request_text: '', run_id: '' })
const nativeVectors = JSON.parse(await readFile(new URL('../../internal/book_learning/testdata/accepted-memory-v1.json', import.meta.url), 'utf8'))
const actual = nativeVectors.desk_imported_records.find(record => record.path.startsWith('memory/procedures/'))
const record = { path: actual.path, category: 'procedure', format: 'text', content_utf8: actual.content, size_bytes: encode(actual.content).length, sha256: actual.sha256 }
const fixtureRecord = async (fields = {}) => {
  const content = JSON.stringify({ status: 'accepted', title: 'Fixture-only source comparison', applicability: 'Comparable source sets; inspect contradictions', outcome_summary: 'Synthetic prior evidence retained, not a quality claim', effort: { runtime_ms: 100, tokens: 'unknown' }, verification: 'Open both original citations', ...fields })
  return { path: 'memory/procedures/source-comparison.json', category: 'procedure', format: 'json', content_utf8: content, size_bytes: encode(content).length, sha256: await sha256(content) }
}
const inventory = async (records = [record]) => ({ contract_version: 'moonclaw.cowork-procedures.v1', session_key: context().session_key, cwd: context().cwd, status: records.length ? 'ready' : 'empty', content_digest: await sha256(JSON.stringify(records)), records, reasons: [], source_scope: 'selected_work_thread_folder', authority_granted: false })
const choose = async (records = [record]) => { const list = await inventory(records); return chooseProcedure(list, records[0].path, 'The fixture concerns this exact source and bounded task', 'A reviewable comparison with exact retained citations', list) }
const result = (id = 'run-fixture', status = 'Succeeded') => ({ run: { id, job_id: 'job-fixture', status, started_at: [100], finished_at: [250], summary: ['Synthetic result: citations retained'], error: [] }, artifacts: [{ id: 'artifact-fixture', run_id: id, job_id: 'job-fixture', logical_key: ['report'], version: 2 }] })

test('real frozen Book-produced procedure bytes survive browsing, selection and durable plan round-trip', async () => {
  const list = await readProcedures(await inventory(), context())
  assert.equal(list.records[0].sha256, await sha256(actual.content))
  assert.equal(list.records[0].content_utf8, actual.content)
  const choice = await choose(), draft = await composeProcedureDraft('Compare the permitted evidence', choice)
  const reopened = await readChoice(draft)
  assert.equal(reopened.record.content_utf8, actual.content)
  assert.equal(reopened.record.sha256, actual.sha256)
  assert.equal(reopened.authority_granted, false)
  assert.match(draft, /grants no tools, permissions, budget/)
  assert.match(describeProcedure(record).effort, /Not recorded/)
  assert.match(describeProcedure(record).outcome, /Not recorded/)
})

test('operator discovery shows recorded outcomes and effort without inventing applicability or measurements', async () => {
  const measured = await fixtureRecord(), list = [record, measured]
  assert.equal(matchingProcedures(list, 'source contradictions').length, 1)
  assert.equal(matchingProcedures(list, 'does-not-match').length, 0)
  assert.match(describeProcedure(measured).effort, /100/)
  assert.match(describeProcedure(measured).outcome, /Synthetic/)
  const empty = await readProcedures(await inventory([]), context())
  assert.equal(empty.records.length, 0)
  for (const status of ['unavailable', 'over_budget']) assert.equal((await readProcedures({ ...empty, status }, context())).records.length, 0)
})

test('another workspace, belief, traversal, changed bytes, duplicate identity and authority claims are refused', async () => {
  const list = await inventory()
  for (const patch of [{ session_key: 'other' }, { cwd: '/other' }, { authority_granted: true }]) await assert.rejects(readProcedures({ ...list, ...patch }, context()), /another work thread/)
  for (const patch of [{ category: 'belief' }, { path: 'memory/procedures/../private' }, { content_utf8: 'changed' }]) await assert.rejects(readProcedures({ ...list, records: [{ ...record, ...patch }] }, context()))
  await assert.rejects(readProcedures({ ...list, records: [record, record] }, context()), /Duplicate/)
  await assert.rejects(readProcedures({ ...list, status: 'unavailable' }, context()), /Unavailable/)
})

test('changed or newly rejected procedure cannot enter the draft; independent procedure edits do not block unchanged choice', async () => {
  const list = await inventory(), extra = await fixtureRecord()
  const allowed = await chooseProcedure(list, record.path, 'Applies', 'Exact evidence', await inventory([record, extra]))
  assert.equal(allowed.record.sha256, actual.sha256)
  await assert.rejects(chooseProcedure(list, record.path, 'Applies', 'Exact evidence', await inventory([])), /no longer accepted/)
  const altered = { ...record, content_utf8: record.content_utf8 + '\nChanged', size_bytes: record.size_bytes + 8, sha256: await sha256(record.content_utf8 + '\nChanged') }
  await assert.rejects(chooseProcedure(list, record.path, 'Applies', 'Exact evidence', await inventory([altered])), /changed/)
  await assert.rejects(chooseProcedure(list, record.path, '', 'Expected', list), /Explain/)
  await assert.rejects(chooseProcedure(list, record.path, 'Applies', '', list), /expected result/)
})

test('repeated method choice replaces one source block and retains the original request', async () => {
  const first = await composeProcedureDraft('Keep this request exactly', await choose())
  const changed = await composeProcedureDraft(first, await choose([await fixtureRecord()]))
  assert.ok(changed.startsWith('Keep this request exactly\n'))
  assert.equal(changed.split(BEGIN).length, 2)
  assert.equal((await readChoice(changed)).record.path, 'memory/procedures/source-comparison.json')
  await assert.rejects(composeProcedureDraft('', await choose()), /work request/)
  await assert.rejects(readChoice(first + BEGIN + '{}' + END), /ambiguous/)
  await assert.rejects(readChoice(first.replace(actual.sha256, 'sha256:' + '0'.repeat(64))), /digest changed/)
})

test('same or changed method preserves both surrounding draft spans including trailing authority restrictions', async () => {
  const originalChoice = await choose(), replacement = await choose([await fixtureRecord()])
  const originalDraft = '  Compare only the supplied evidence.\n\n'
  const first = await composeProcedureDraft(originalDraft, originalChoice)
  assert.ok(first.startsWith(originalDraft), 'First selection preserves existing draft whitespace')
  const prefix = 'Owner instructions before the task.\n\n' + first.slice(0, first.indexOf(BEGIN))
  const suffix = '\n\nDo not email or publish this report.\nKeep the original authority limits.\n\n  '
  const authored = 'Owner instructions before the task.\n\n' + first + suffix
  for (const next of [originalChoice, replacement]) {
    const updated = await composeProcedureDraft(authored, next)
    const start = updated.indexOf(BEGIN), end = updated.indexOf(END, start) + END.length
    assert.equal(updated.slice(0, start), prefix)
    assert.equal(updated.slice(end), suffix)
    assert.equal((await readChoice(updated)).record.sha256, next.record.sha256)
    assert.equal(updated.split(BEGIN).length, 2)
  }
})

test('linked delivered result uses the reviewed proposal source, exact run identity and honest unmeasured dimensions', async () => {
  const ctx = { ...context(), request_text: await composeProcedureDraft('Compare sources', await choose()), run_id: 'run-fixture' }
  const comparison = await compareProcedure(ctx, result())
  assert.equal(comparison.choice.record.sha256, actual.sha256)
  assert.equal(comparison.elapsed_ms, 150)
  assert.equal(comparison.artifacts[0].version, 2)
  assert.match(comparison.assessment, /Human review required/)
  assert.equal(comparison.cost, undefined)
  const pending = await compareProcedure(ctx, result('run-fixture', 'Running'))
  assert.equal(pending.elapsed_ms, null); assert.equal(pending.terminal, false)
  for (const status of ['Failed', 'Cancelled']) assert.equal((await compareProcedure(ctx, result('run-fixture', status))).status, status)
  const unknown = result(); unknown.run.started_at = []; assert.equal((await compareProcedure(ctx, unknown)).elapsed_ms, null)
  await assert.rejects(compareProcedure(ctx, result('wrong-run')), /another run/)
  const unrelated = result(); unrelated.artifacts[0].job_id = 'other'; await assert.rejects(compareProcedure(ctx, unrelated), /another run/)
  await assert.rejects(compareProcedure({ ...ctx, request_text: 'no selected procedure' }, result()), /no matching/)
})

class Node {
  constructor() { this.value = ''; this.textContent = ''; this.dataset = {}; this.isConnected = true; this.events = new Map(); this.children = [] }
  addEventListener(type, handler, options = {}) { this.events.set(type, handler); options.signal?.addEventListener('abort', () => this.events.delete(type), { once: true }) }
  replaceChildren() { this.children = []; this.value = '' }
  appendChild(node) { this.children.push(node) }
  dispatchEvent(event) { this.events.get(event.type)?.(event); return true }
  async fire(event) { return this.events.get(event)?.() }
}
function surface() {
  const nodes = new Map()
  const document = { getElementById(id) { if (!nodes.has(id)) nodes.set(id, new Node()); return nodes.get(id) }, createElement() { return new Node() } }
  const get = key => document.getElementById('claw-procedure-' + key)
  get('context').textContent = JSON.stringify(context()); get('composer').value = 'Compare the allowed sources'
  let epoch = 0
  return { document, get, transport: () => ({ base: () => 'http://fixture', epoch: () => epoch }), changeAccess() { epoch++ } }
}

test('shipped operator controls execute load → inspect → apply → existing draft input → linked result comparison', async () => {
  const ui = surface(), calls = [], list = await inventory([await fixtureRecord()])
  const fetch = async url => { calls.push(url); return { ok: true, json: async () => url.endsWith('/procedures') ? list : result() } }
  const binding = bindProcedures(ui.document, { ...ui, fetch })
  await ui.get('load').fire('click')
  ui.get('choice').value = list.records[0].path; await ui.get('choice').fire('change')
  assert.match(ui.get('evidence').textContent, /Recorded effort/)
  assert.equal(ui.get('original').textContent, list.records[0].content_utf8)
  ui.get('why').value = 'Same bounded source comparison'; ui.get('expected').value = 'Inspect exact citations'
  await ui.get('apply').fire('click')
  const draft = ui.get('composer').value
  assert.ok(await readChoice(draft)); assert.match(ui.get('status').textContent, /Choose Plan/)
  assert.equal(calls.length, 2, 'Applying performs a fresh read, never a job mutation')
  assert.ok(calls.every(url => url.endsWith('/procedures')))
  ui.get('context').textContent = JSON.stringify({ ...context(), request_text: draft, run_id: 'run-fixture' }); binding.sync()
  await ui.get('compare').fire('click')
  assert.match(ui.get('comparison').textContent, /Expected: Inspect exact citations/)
  assert.match(ui.get('comparison').textContent, /150 ms/)
  assert.match(ui.get('comparison').textContent, /Tokens and cost: not measured/)
  assert.match(ui.get('comparison').textContent, /Human review required/)
  binding.dispose()
})

test('shipped controls retain draft across duplicate clicks, interrupted reads, changed context, stale records and access failure', async () => {
  const ui = surface(), list = await inventory(); let release, blocker = null, calls = 0, response = list, ok = true
  const fetch = async () => { calls++; if (blocker) await blocker; return { ok, json: async () => response } }
  const binding = bindProcedures(ui.document, { ...ui, fetch })
  blocker = new Promise(resolve => { release = resolve })
  const first = ui.get('load').fire('click'); await ui.get('load').fire('click'); assert.equal(calls, 1)
  await ui.get('cancel').fire('click'); release(); await first; blocker = null
  assert.equal(binding.session.inventory, null)
  await ui.get('load').fire('click'); ui.get('choice').value = record.path; ui.get('why').value = 'Applies'; ui.get('expected').value = 'Expected'
  const draft = ui.get('composer').value
  response = await inventory([]); await ui.get('apply').fire('click'); assert.equal(ui.get('composer').value, draft); assert.match(ui.get('status').textContent, /no longer accepted/)
  response = list; blocker = new Promise(resolve => { release = resolve })
  const applying = ui.get('apply').fire('click'); ui.changeAccess(); release(); await applying; blocker = null
  assert.equal(ui.get('composer').value, draft)
  binding.sync(); assert.equal(binding.session.inventory, null)
  response = { error: { message: 'Gateway bearer token required' } }; ok = false
  await ui.get('load').fire('click'); assert.match(ui.get('status').textContent, /token required/)
  assert.equal(ui.get('composer').value, draft)
  binding.dispose()
})

test('shipped reapply action preserves user restrictions appended after the selected procedure', async () => {
  const ui = surface(), list = await inventory([record, await fixtureRecord()])
  const binding = bindProcedures(ui.document, { ...ui, fetch: async () => ({ ok: true, json: async () => list }) })
  await ui.get('load').fire('click'); ui.get('choice').value = record.path
  ui.get('why').value = 'Applies'; ui.get('expected').value = 'Review exact evidence'
  await ui.get('apply').fire('click')
  const restriction = '\n\nDo not email or publish this report.\n\n'
  ui.get('composer').value += restriction
  await ui.get('composer').fire('input')
  const prefix = ui.get('composer').value.slice(0, ui.get('composer').value.indexOf(BEGIN))
  for (const selected of list.records) {
    ui.get('choice').value = selected.path; await ui.get('choice').fire('change')
    await ui.get('apply').fire('click')
    const updated = ui.get('composer').value
    assert.equal(updated.slice(0, updated.indexOf(BEGIN)), prefix)
    assert.equal(updated.slice(updated.indexOf(END) + END.length), restriction)
    assert.equal((await readChoice(updated)).record.sha256, selected.sha256)
  }
  binding.dispose()
})

test('pending controller operations cannot write into a replaced work thread or changed draft', async () => {
  const ui = surface(), list = await inventory(); let pending = false, release
  const fetch = async () => { if (pending) await new Promise(resolve => { release = resolve }); return { ok: true, json: async () => list } }
  const binding = bindProcedures(ui.document, { ...ui, fetch }); await ui.get('load').fire('click')
  ui.get('choice').value = record.path; ui.get('why').value = 'Applies'; ui.get('expected').value = 'Expected'
  pending = true; const apply = ui.get('apply').fire('click')
  ui.get('composer').value = 'Newer user draft'; await ui.get('composer').fire('input'); release(); await apply
  assert.equal(ui.get('composer').value, 'Newer user draft')
  const load = ui.get('load').fire('click'); ui.get('context').textContent = JSON.stringify({ ...context(), session_key: 'another' }); binding.sync(); release(); await load
  assert.equal(binding.session.inventory, null)
  binding.dispose()
})

test('source wiring reaches actual Work screen, existing capture reader and normal review controls', async () => {
  const [surfaceSource, bootstrap, gateway, route] = await Promise.all(['./main/cowork_surface.mbt', './bootstrap.js', '../../gateway/server/cowork_procedures.mbt', '../../gateway/server/request.mbt'].map(path => readFile(new URL(path, import.meta.url), 'utf8')))
  assert.match(surfaceSource, /render_cowork_procedures\(model\)/)
  assert.match(surfaceSource, /on_input=value => dispatch\(SetCoworkComposer\(value\)\)/)
  assert.match(bootstrap, /installProcedures\(document\)/)
  assert.match(gateway, /@book_learning.capture\(binding, current_time_ms\(\)\)/)
  assert.match(gateway, /self.sessions.get\(session_key\)/)
  assert.match(gateway, /self.auth.token is Some\(token\)/)
  assert.match(route, /self.handle_cowork_procedures\(w, session_key.to_owned\(\)\)/)
})
