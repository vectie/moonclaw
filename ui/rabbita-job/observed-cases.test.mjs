import test from 'node:test'
import assert from 'node:assert/strict'
import { webcrypto } from 'node:crypto'
import { readFile, writeFile } from 'node:fs/promises'
import { sha256 } from './book-outcome.js'
import { readSource } from './artifact-rework.js'
import { sourceLines, sourceExcerpt, createObservedCase, exportObservedCases, downloadObservedCases } from './observed-cases.js'
import { mountObservedCases, bindObservedCases, installObservedCases } from './observed-case-controls.js'
if (!globalThis.crypto) globalThis.crypto = webcrypto
const ctx = () => ({ session_key: 'thread-fixture', cwd: '/fixture/book', cwd_override: '', run_id: 'run-fixture' })
const record = () => ({ id: 'artifact-fixture', run_id: 'run-fixture', job_id: 'job-fixture', version: 2, content_type: 'text/markdown', logical_key: ['report'] })
const detail = (status = 'Succeeded') => ({ run: { id: 'run-fixture', job_id: 'job-fixture', status }, artifacts: [record()] })
const original = '# Report, Q4\r\nSource: \"observed\" 001.20\r\nUncertainty: none\r\n'
const payload = async (content = original) => ({ artifact: record(), content, revision_source: { run_id: 'run-fixture', parent_version: 2, parent_digest: await sha256(content) } })
const fields = (kind = 'useful') => ({ kind, name: 'Quarter case', input: kind === 'useful' ? 'Summarize Q4' : 'Explain uncertainty', revised: '', required: 'Source:', forbidden: 'invented', start: 1, end: 3 })
const createCase = async (values = fields(), status = 'Succeeded', content = original) => createObservedCase(ctx(), detail(status), await readSource(await payload(content), detail(status), record().id), values)
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
  context.textContent = JSON.stringify(ctx()); composer.value = 'Ordinary unsent task'
  const root = mountObservedCases(document, anchor), get = key => document.getElementById('claw-cases-' + key)
  let epoch = 0; const downloads = []
  return { document, root, anchor, get, context, composer, downloads, download: csv => downloads.push(csv), transport: () => ({ base: () => 'http://fixture', epoch: () => epoch }), changeAccess() { epoch++ } }
}
async function controller(ui, overrides = {}) {
  const calls = [], source = await payload()
  const fetch = async (url, init) => { calls.push({ url, init }); return { ok: true, json: async () => url.includes('/artifacts/') ? source : detail() } }
  const binding = bindObservedCases(ui.document, { ...ui, fetch, ...overrides })
  return { binding, calls, source }
}
async function select(ui) { await ui.get('load').fire('click'); ui.get('choice').value = record().id; await ui.get('choice').fire('change'); await ui.get('inspect').fire('click') }
async function fill(ui, values = fields()) { for (const [key, value] of Object.entries(values)) { ui.get(key).value = String(value); await ui.get(key).fire(key === 'kind' ? 'change' : 'input') } }
async function add(ui, values = fields()) { await fill(ui, values); await ui.get('excerpt').fire('click'); await ui.get('add').fire('click') }

test('terminal output becomes explicit observed case with exact source range and Book-compatible lexical fields', async () => {
  const cases = [await createCase(), await createCase(fields('adverse'), 'Failed')]
  assert.equal(cases[0].row.original, original)
  assert.match(cases[0].row.name, /Succeeded run=run-fixture artifact=artifact-fixture v2 L1-3 sha256:/)
  assert.match(cases[1].row.name, /Failed/); assert.equal(cases[1].row.kind, 'adverse')
  const csv = await exportObservedCases(cases)
  assert.match(csv, /^kind,name,input,original,revised,required,forbidden\r\n/)
  assert.match(csv, /""observed"" 001.20/); assert.equal(cases[0].row.revised, '')
  assert.equal(sourceLines({ content_utf8: 'a\r\nb\nc' }).length, 3)
  assert.equal(sourceExcerpt({ content_utf8: 'a\r\nb\nc' }, 2, 3), 'b\nc')
  assert.equal((await createCase(fields(), 'Cancelled')).row.kind, 'useful')
})

test('invalid outcome, empty/oversize/binary fields, invalid lines and contradictory checks cannot export cases', async () => {
  for (const change of [{ kind: '' }, { kind: 'success' }, { name: '' }, { name: 'x'.repeat(81) }, { input: ' ' }, { input: 'x'.repeat(8193) }, { input: '\ud800' }, { input: 'a\rb' }, { input: 'a\0b' }, { revised: ' ' }, { start: 0 }, { start: 1.5 }, { end: 4 }, { start: 3, end: 1 }, { required: '', forbidden: '' }, { required: ' Source:' }, { required: 'Source:\n' }, { required: 'Source:\nSource:' }, { required: 'invented detail', forbidden: 'invented' }, { required: 'x'.repeat(257) }, { required: Array.from({ length: 21 }, (_, i) => 'x' + i).join('\n') }]) await assert.rejects(createCase({ ...fields(), ...change }))
  await assert.rejects(createCase({ ...fields(), end: 1 }, 'Succeeded', 'x'.repeat(8193)), /8192/)
  await assert.rejects(createCase(fields(), 'Running'), /terminal/)
  for (const cases of [[], Array(7).fill(await createCase()), [await createCase(), await createCase()]]) await assert.rejects(exportObservedCases(cases))
  const tampered = await createCase(); tampered.row.original = 'changed'; await assert.rejects(exportObservedCases([tampered]), /changed/)
  const bytesChanged = await createCase(); bytesChanged.source.content_utf8 = 'changed'; await assert.rejects(exportObservedCases([bytesChanged]), /bytes changed/)
})

test('mounted Work controls complete source→case→preview→fresh-read→download without mutating ordinary draft or posting', async () => {
  const ui = surface(), { binding, calls } = await controller(ui)
  assert.equal(ui.anchor.after.id, 'claw-cases-panel'); assert.equal(ui.get('status').attributes['aria-live'], 'polite')
  await select(ui); await add(ui)
  assert.equal(binding.cases.length, 1); assert.equal(ui.get('excerpt-preview').textContent, original)
  assert.equal(ui.downloads.length, 0); await ui.get('download').fire('click'); assert.match(ui.get('status').textContent, /Preview/)
  await add(ui, fields('adverse')); assert.equal(binding.cases.length, 2)
  await ui.get('preview').fire('click'); const exact = ui.get('csv').textContent
  assert.equal(exact, await exportObservedCases(binding.cases))
  await ui.get('download').fire('click'); assert.deepEqual(ui.downloads, [exact])
  assert.equal(ui.composer.value, 'Ordinary unsent task'); assert.ok(calls.every(call => !call.init.method && call.init.cache === 'no-store' && call.init.redirect === 'error'))
  assert.match(ui.get('status').textContent, /No lesson was submitted or accepted/)
  binding.dispose()
})

test('invalid/repeated add preserves the existing set, removal invalidates preview and detached controls cannot remove replacement', async () => {
  const ui = surface(), { binding } = await controller(ui); await select(ui); await add(ui)
  await ui.get('add').fire('click'); assert.equal(binding.cases.length, 1); assert.match(ui.get('status').textContent, /already/)
  await fill(ui, { ...fields('adverse'), required: '', forbidden: '' }); await ui.get('add').fire('click'); assert.equal(binding.cases.length, 1)
  await ui.get('preview').fire('click'); const remove = ui.get('list').children[0].children[2]
  await remove.fire('click'); assert.equal(binding.cases.length, 0); assert.equal(ui.get('csv').textContent, '')
  await add(ui); await remove.fire('click'); assert.equal(binding.cases.length, 1)
  await ui.get('clear').fire('click'); assert.equal(binding.cases.length, 0); assert.equal(binding.source, null); assert.equal(ui.get('name').value, '')
  binding.dispose()
})

test('changed source bytes, changed versions, nonterminal or denied run blocks download with previous cases intact', async () => {
  for (const change of ['bytes', 'version', 'running', 'denied']) {
    const ui = surface(); let changed = false; const first = await payload(), second = await payload('changed')
    const { binding } = await controller(ui, { fetch: async url => ({ ok: !(changed && change === 'denied'), json: async () => changed && change === 'denied' ? { error: { message: 'Access denied' } } : url.includes('/artifacts/') ? changed && change === 'bytes' ? second : first : changed && change === 'version' ? { ...detail(), artifacts: [{ ...record(), version: 3 }] } : detail(changed && change === 'running' ? 'Running' : 'Succeeded') }) })
    await select(ui); await add(ui); await ui.get('preview').fire('click'); const prior = binding.cases; changed = true
    await ui.get('download').fire('click'); assert.equal(ui.downloads.length, 0); assert.deepEqual(binding.cases, prior)
    assert.match(ui.get('status').textContent, /changed|terminal|denied/); binding.dispose()
  }
})

test('cancel, changed form, scope/access changes, disconnect and repeat clicks stop stale download callbacks', async () => {
  for (const change of ['cancel', 'clear', 'edit', 'scope', 'access', 'disconnect']) {
    const ui = surface(); let waiting = false, release, count = 0; const first = await payload()
    const { binding } = await controller(ui, { fetch: async url => { count++; if (waiting) await new Promise(resolve => { release = resolve }); return { ok: true, json: async () => url.includes('/artifacts/') ? first : detail() } } })
    await select(ui); await add(ui); await ui.get('preview').fire('click'); waiting = true
    const before = count, pending = ui.get('download').fire('click'); await ui.get('download').fire('click'); assert.equal(count, before + 1)
    if (change === 'cancel') await ui.get('cancel').fire('click')
    if (change === 'clear') await ui.get('clear').fire('click')
    if (change === 'edit') { ui.get('name').value = 'New interpretation'; await ui.get('name').fire('input') }
    if (change === 'scope') { ui.context.textContent = JSON.stringify({ ...ctx(), session_key: 'B' }); binding.sync(); ui.context.textContent = JSON.stringify(ctx()); binding.sync() }
    if (change === 'access') { ui.changeAccess(); binding.sync() }
    if (change === 'disconnect') ui.root.isConnected = false
    release(); await pending; assert.equal(ui.downloads.length, 0)
    if (['cancel', 'edit'].includes(change)) assert.equal(binding.cases.length, 1)
    if (['clear', 'scope', 'access'].includes(change)) assert.equal(binding.cases.length, 0)
    binding.dispose()
  }
})

test('selection or cancellation during slow inspect cannot attach stale sources; a fresh binding never restores old cases', async () => {
  const ui = surface(); let wait = false, release; const first = await payload()
  const { binding } = await controller(ui, { fetch: async url => { if (wait) await new Promise(resolve => { release = resolve }); return { ok: true, json: async () => url.includes('/artifacts/') ? first : detail() } } })
  await select(ui); await add(ui); wait = true
  const pending = ui.get('inspect').fire('click'); ui.get('choice').value = ''; await ui.get('choice').fire('change'); release(); await pending
  assert.equal(binding.source, null); assert.equal(binding.cases.length, 1)
  binding.dispose(); assert.equal(bindObservedCases(ui.document, { ...ui, fetch: async () => {} }).cases.length, 0)
})

test('existing gateway wiring and installation handles delayed/repeated Work mount and disposal', async () => {
  const boot = await readFile(new URL('./bootstrap.js', import.meta.url), 'utf8'); assert.match(boot, /installObservedCases\(document\)/)
  const ui = surface(); ui.root.remove(); let callback; const previous = globalThis.MutationObserver
  globalThis.MutationObserver = class { constructor(fn) { callback = fn } observe() {} disconnect() {} }
  try { const dispose = installObservedCases(ui.document); assert.ok(ui.get('panel')); callback(); dispose(); assert.equal(ui.get('panel'), null) } finally { globalThis.MutationObserver = previous }
})

// This is the same product export exercised above, saved only when an explicit
// local integration-evidence destination is supplied by the test runner.
if (process.env.MOONCLAW_CASE_FIXTURE) {
  const useful = await createCase({ ...fields(), revised: original })
  const adverse = await createCase({ ...fields('adverse'), name: 'Unsupported certainty', required: 'Source:\nUncertainty:', forbidden: 'none', revised: '# Report, Q4\r\nSource: "observed" 001.20\r\nUncertainty: estimate only\r\n' })
  await writeFile(process.env.MOONCLAW_CASE_FIXTURE, await exportObservedCases([useful, adverse]))
}

test('six-case aggregate UTF-8 size is enforced without partial export or truncation', async () => {
  const cases = []
  for (let i = 0; i < 6; i++) cases.push(await createCase({ ...fields(), name: 'Case ' + i, input: String(i) + 'x'.repeat(8191), revised: 'y'.repeat(8192), start: 1, end: 1 }, 'Succeeded', 'z'.repeat(8192)))
  await assert.rejects(exportObservedCases(cases), /128 KiB/)
  assert.equal(cases.length, 6); assert.equal(cases[0].row.original.length, 8192)
})

test('failed browser download is reported honestly and retains the exact case set for retry', async () => {
  const ui = surface(), { binding } = await controller(ui, { download() { throw Error('Browser download unavailable') } })
  await select(ui); await add(ui); await ui.get('preview').fire('click')
  const before = binding.cases, preview = ui.get('csv').textContent
  await ui.get('download').fire('click'); assert.match(ui.get('status').textContent, /Browser download unavailable/)
  assert.deepEqual(binding.cases, before); assert.equal(ui.get('csv').textContent, preview); binding.dispose()
})
