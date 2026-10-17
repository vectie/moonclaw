import test from 'node:test'
import assert from 'node:assert/strict'
import { webcrypto } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { sha256 } from './book-outcome.js'
import { readRun, readSource, createPacket, composeRework, readPacket, BEGIN, END, LIMIT } from './artifact-rework.js'
import { mountRework, bindRework, installRework } from './artifact-rework-controls.js'
if (!globalThis.crypto) globalThis.crypto = webcrypto
const ctx = () => ({ session_key: 'thread-fixture', cwd: '/fixture/book', cwd_override: '', run_id: 'run-fixture', request_text: 'Original request' })
const record = () => ({ id: 'artifact-fixture', run_id: 'run-fixture', job_id: 'job-fixture', version: 2, content_type: 'text/markdown', logical_key: ['report'] })
const detail = (status = 'Succeeded') => ({ run: { id: 'run-fixture', job_id: 'job-fixture', status }, artifacts: [record()] })
const payload = async (text = '# Fixture report\nIncorrect total: 10\nSource: retained fixture.\n') => ({ artifact: record(), content: text, revision_source: { run_id: 'run-fixture', parent_version: 2, parent_digest: await sha256(text) } })
const packet = async () => createPacket(ctx(), detail(), await readSource(await payload(), detail(), record().id), 'Correct the total using supplied figures', 'Keep the citations; do not publish', 'Check total against the permitted figures')
class Node {
  constructor(document, tag) { this.document = document; this.tagName = tag; this.value = ''; this.textContent = ''; this.dataset = {}; this.isConnected = true; this.events = new Map(); this.children = []; this.attributes = {} }
  set id(value) { this._id = value; this.document.nodes.set(value, this) } get id() { return this._id }
  setAttribute(key, value) { this.attributes[key] = value }
  appendChild(node) { this.children.push(node) }
  replaceChildren() { this.children = []; this.value = '' }
  insertAdjacentElement(where, node) { this.after = node }
  remove() { this.isConnected = false; this.document.nodes.delete(this.id) }
  addEventListener(type, handler, options = {}) { const handlers = this.events.get(type) || []; handlers.push(handler); this.events.set(type, handlers); options.signal?.addEventListener('abort', () => this.events.set(type, (this.events.get(type) || []).filter(fn => fn !== handler)), { once: true }) }
  dispatchEvent(event) { for (const fn of this.events.get(event.type) || []) fn(event); return true }
  async fire(type) { for (const fn of this.events.get(type) || []) await fn() }
}
function surface() {
  const document = { nodes: new Map(), getElementById(id) { return this.nodes.get(id) || null }, createElement(tag) { return new Node(this, tag) } }
  const add = id => { const node = document.createElement('div'); node.id = id; return node }
  const anchor = add('claw-procedure-panel'), context = add('claw-procedure-context'), composer = add('claw-procedure-composer')
  context.textContent = JSON.stringify(ctx()); composer.value = 'Revise the report using only supplied figures.'
  const root = mountRework(document, anchor), get = key => document.getElementById('claw-rework-' + key)
  get('changes').value = 'Correct the total'; get('preserve').value = 'Keep citations and do not publish'; get('verify').value = 'Recalculate total'
  let epoch = 0, inputEvents = 0; composer.addEventListener('input', () => { inputEvents++ })
  return { document, root, anchor, get, composer, context, transport: () => ({ base: () => 'http://fixture', epoch: () => epoch }), changeAccess() { epoch++ }, get inputEvents() { return inputEvents } }
}
async function controller(ui, overrides = {}) {
  const calls = [], source = await payload()
  const fetch = async (url, init) => { calls.push({ url, init }); return { ok: true, json: async () => url.includes('/artifacts/') ? source : detail() } }
  const binding = bindRework(ui.document, { ...ui, fetch, ...overrides })
  return { binding, calls, source }
}
async function select(ui) { await ui.get('load').fire('click'); ui.get('choice').value = record().id; await ui.get('choice').fire('change'); await ui.get('inspect').fire('click') }

test('exact host revision becomes a bounded retained request with explicit changes, constraints and checks', async () => {
  const choice = await packet(), request = await composeRework('Revise this report', choice), reopened = await readPacket(JSON.parse(JSON.stringify({ request })).request)
  assert.deepEqual(reopened, choice); assert.equal(reopened.source.sha256, await sha256(reopened.source.content_utf8)); assert.equal(reopened.authority_granted, false); assert.equal(reopened.accepted_output, false)
  assert.match(request, /untrusted historical task data/); assert.match(request, /Produce a new output/)
})
test('terminal failed and cancelled sources remain explicit; running and unknown outcomes are refused', async () => {
  for (const state of ['Succeeded', 'Failed', 'Cancelled']) assert.equal(readRun(detail(state), ctx()).run.status, state)
  for (const state of ['Pending', 'Running', 'WaitingForInput', 'Unknown']) assert.throws(() => readRun(detail(state), ctx()), /terminal/)
  assert.throws(() => readRun(detail(), { ...ctx(), run_id: 'other' }), /another/)
  assert.throws(() => readRun({ ...detail(), artifacts: [record(), record()] }, ctx()), /duplicate/)
})
test('wrong ownership, changed revision, content digest, binary, synthetic and oversize sources are refused', async () => {
  const original = await payload()
  for (const change of [{ run_id: 'other' }, { job_id: 'other' }, { version: 3 }, { content_type: 'application/octet-stream' }]) await assert.rejects(readSource({ ...original, artifact: { ...record(), ...change } }, detail(), record().id), /revision changed/)
  await assert.rejects(readSource({ ...original, content: 'tampered' }, detail(), record().id), /digest/)
  await assert.rejects(readSource({ ...original, revision_source: null }, detail(), record().id), /digest/)
  await assert.rejects(readSource(await payload('é'.repeat(LIMIT)), detail(), record().id), /32 KiB/)
  await assert.rejects(readSource(original, { ...detail(), artifacts: [{ ...record(), id: 'synthetic:x' }] }, 'synthetic:x'))
  assert.equal((await readSource({ ...original, content: [original.content] }, detail(), record().id)).content_utf8, original.content)
})
test('repeat insertion replaces only its own packet and preserves surrounding restrictions exactly', async () => {
  const first = await composeRework('  Revise\n\n', await packet()), suffix = '\nDo not email.  \n', next = { ...await packet(), requested_changes: 'Change only the heading' }
  const updated = await composeRework(first + suffix, next)
  assert.equal(updated.slice(0, updated.indexOf(BEGIN)), first.slice(0, first.indexOf(BEGIN)))
  assert.equal(updated.slice(updated.indexOf(END) + END.length), suffix)
  assert.equal(updated.split(BEGIN).length, 2); assert.equal((await readPacket(updated)).requested_changes, next.requested_changes)
  await assert.rejects(composeRework(first + BEGIN, next), /ambiguous/)
  await assert.rejects(composeRework('', next), /main work draft/)
})
test('empty checklists, authority claims and altered retained source cannot become a draft', async () => {
  const choice = await packet()
  for (const change of [{ authority_granted: true }, { accepted_output: true }, { verification: '' }, { requested_changes: 'a'.repeat(4001) }, { source: { ...choice.source, content_utf8: 'changed' } }]) await assert.rejects(composeRework('Revise', { ...choice, ...change }))
})
test('production DOM controls mount and execute load→inspect→fresh read→ordinary composer input, never POST', async () => {
  const ui = surface(), { binding, calls } = await controller(ui)
  assert.equal(ui.anchor.after.id, 'claw-rework-panel'); assert.equal(ui.get('status').attributes['aria-live'], 'polite')
  await select(ui); assert.match(ui.get('original').textContent, /Incorrect total/); await ui.get('apply').fire('click')
  assert.equal((await readPacket(ui.composer.value)).source.artifact_id, record().id)
  assert.equal(calls.length, 4); assert.ok(calls.every(({ init }) => !init.method && init.cache === 'no-store' && init.redirect === 'error'))
  assert.match(ui.get('status').textContent, /Plan and Preview/)
  // Simulated host uses the same event as SetCoworkComposer; retained packet survives the plan request.
  assert.equal(ui.inputEvents, 1); assert.match(ui.composer.value, /Keep citations and do not publish/)
  binding.dispose()
})
test('source mutation or removal after inspection preserves the existing task draft', async () => {
  const ui = surface(); let changed = false; const original = await payload(), modified = await payload('New source')
  const { binding } = await controller(ui, { fetch: async url => ({ ok: true, json: async () => url.includes('/artifacts/') ? changed ? modified : original : detail() }) })
  await select(ui); const before = ui.composer.value; changed = true; await ui.get('apply').fire('click')
  assert.equal(ui.composer.value, before); assert.match(ui.get('status').textContent, /changed/); binding.dispose()
})
test('duplicate clicks, cancelled reads, changed draft and late A→B→A responses cannot overwrite new work', async () => {
  const ui = surface(); let wait = false, release, count = 0; const original = await payload()
  const { binding } = await controller(ui, { fetch: async url => { count++; if (wait) await new Promise(resolve => { release = resolve }); return { ok: true, json: async () => url.includes('/artifacts/') ? original : detail() } } })
  await select(ui); wait = true; const before = count, applying = ui.get('apply').fire('click'); await ui.get('apply').fire('click'); assert.equal(count, before + 1)
  ui.composer.value = 'New user instruction'; await ui.composer.fire('input'); release(); await applying; assert.equal(ui.composer.value, 'New user instruction')
  const loading = ui.get('load').fire('click'); ui.context.textContent = JSON.stringify({ ...ctx(), session_key: 'B' }); binding.sync(); ui.context.textContent = JSON.stringify(ctx()); binding.sync(); release(); await loading; assert.equal(binding.source, null)
  wait = false; await select(ui); wait = true; const inspect = ui.get('inspect').fire('click'); await ui.get('cancel').fire('click'); release(); await inspect; assert.equal(binding.source, null); binding.dispose()
})
test('access change, saved-folder mismatch, gateway denial and newer form edits fail closed', async () => {
  const ui = surface(); let wait = false, release, denied = false; const original = await payload()
  const { binding } = await controller(ui, { fetch: async url => { if (wait) await new Promise(resolve => { release = resolve }); return { ok: !denied, json: async () => denied ? { error: { message: 'Gateway access denied' } } : url.includes('/artifacts/') ? original : detail() } } })
  await select(ui); const before = ui.composer.value; wait = true; const apply = ui.get('apply').fire('click'); ui.changeAccess(); release(); await apply; assert.equal(ui.composer.value, before); binding.sync(); assert.equal(binding.source, null)
  wait = false; denied = true; await ui.get('load').fire('click'); assert.match(ui.get('status').textContent, /access denied/)
  denied = false; ui.context.textContent = JSON.stringify({ ...ctx(), cwd_override: '/other' }); await ui.get('load').fire('click'); assert.match(ui.get('status').textContent, /Save/)
  ui.context.textContent = JSON.stringify(ctx()); binding.sync(); await select(ui); wait = true; const again = ui.get('apply').fire('click'); ui.get('changes').value = 'New changes'; await ui.get('changes').fire('input'); release(); await again; assert.equal(ui.composer.value, before); binding.dispose()
})
test('installer handles delayed Work mount, remount and cleanup using the actual DOM surface', () => {
  const ui = surface(); ui.root.remove(); let callback
  const prior = globalThis.MutationObserver
  globalThis.MutationObserver = class { constructor(fn) { callback = fn } observe() {} disconnect() {} }
  try { const dispose = installRework(ui.document); assert.ok(ui.document.getElementById('claw-rework-panel')); callback(); assert.equal(ui.anchor.after.id, 'claw-rework-panel'); dispose(); assert.equal(ui.document.getElementById('claw-rework-panel'), null) } finally { globalThis.MutationObserver = prior }
})
test('shipped wiring uses existing authorized transport and unchanged ordinary planning boundary', async () => {
  const [boot, host, transport, handler] = await Promise.all(['./bootstrap.js', './main/cowork_surface.mbt', './main/gateway_transport.mbt', '../../gateway/server/handler.mbt'].map(path => readFile(new URL(path, import.meta.url), 'utf8')))
  assert.match(boot, /installRework\(document\)/); assert.match(host, /id="claw-procedure-composer"/); assert.match(host, /on_input=value => dispatch\(SetCoworkComposer\(value\)\)/)
  assert.match(transport, /__moonclawTransport/); assert.match(handler, /human_revision_source\(artifact.run_id, artifact.id\)/)
})
