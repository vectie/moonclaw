import test from 'node:test'
import { webcrypto } from 'node:crypto'
import { sha256 } from './book-outcome.js'
if (!globalThis.crypto) globalThis.crypto = webcrypto
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { BlockedRecovery, readRecovery, describeRecovery } from './blocked-recovery.js'
import { bindBlockedRecovery } from './blocked-recovery-controls.js'
const checkpoint = char => 'sha256:' + char.repeat(64)
const context = () => ({ session_key: 'work:fixture', cwd: '/fixture/book', cwd_override: '', run_id: 'run-fixture' })
const fixture = (patch = {}) => ({ contract_version: 'moonclaw.blocked-recovery.v1', ...context(), job_id: 'job-fixture', status: 'WaitingForInput', observed_at: 1000, checkpoint: checkpoint('a'), can_resume: true, resume_receipt: null, launch_pending: false, steps: [{ id: 'completed', step_id: 'read-sources', status: 'Succeeded', summary: ['Source list retained'], error: [] }, { id: 'waiting', step_id: 'missing-date', status: 'WaitingForInput', summary: ['Which date should the report use?'], error: [] }], artifacts: [{ id: 'artifact', logical_key: ['source-list'], version: 2 }], guidance: 'Supply missing input within existing scope', ...patch })

test('recovery combines retained completion, exact artifact revision and the missing input', () => {
  const value = readRecovery(fixture(), context()), text = describeRecovery(value)
  assert.match(text, /Retained completed work: read-sources/)
  assert.match(text, /Needs your input: missing-date/)
  assert.match(text, /source-list @2/)
  assert.match(text, /1970-01-01T00:00:01.000Z/)
  assert.match(text, /does not establish acceptance/)
  for (const patch of [{ run_id: 'other' }, { session_key: 'other' }, { cwd: '/other' }, { checkpoint: 'made-up' }, { status: 'Unknown' }, { can_resume: true, steps: [] }]) assert.throws(() => readRecovery(fixture(patch), context()))
})

test('saved checkpoint answer survives reload; a newer wait requires explicit review and re-scoping', () => {
  const session = new BlockedRecovery(); session.observe(fixture(), context()); session.edit('Use 12 October. Do not publish.')
  const reopened = new BlockedRecovery(JSON.parse(JSON.stringify(session.state)))
  reopened.observe(fixture({ checkpoint: checkpoint('b') }), context())
  assert.throws(() => reopened.request(), /checkpoint changed/)
  assert.equal(reopened.state.draft, session.state.draft)
  reopened.adopt(); assert.deepEqual(reopened.request(), { content: session.state.draft, expected_checkpoint: checkpoint('b') })
})

test('uncertain acknowledgement reconciles the recorded original answer and refuses blind replay', async () => {
  const session = new BlockedRecovery(); session.observe(fixture(), context()); session.edit('Use verified date'); session.sending(await session.prepare())
  const reopened = new BlockedRecovery(session.state)
  reopened.observe(fixture({ checkpoint: checkpoint('b'), resume_receipt: { checkpoint: [checkpoint('a')], content_digest: await sha256('Use verified date'), message_id: 'saved' } }), context())
  assert.equal(reopened.state.phase, 'submitted')
  assert.throws(() => reopened.request(), /checkpoint changed/)
  assert.equal(reopened.state.draft, 'Use verified date')
  reopened.adopt(); assert.equal(reopened.state.phase, 'draft')
})

test('an unresolved send can only retry the identical conditional checkpoint and text', () => {
  const session = new BlockedRecovery(); session.observe(fixture(), context()); session.edit('Original answer'); const request = session.request(); session.sending()
  assert.throws(() => session.edit('Changed answer'), /Reconcile/)
  assert.throws(() => session.adopt(), /uncertain/)
  assert.deepEqual(session.request(), request)
  session.observe(fixture({ checkpoint: checkpoint('b') }), context())
  assert.throws(() => session.request(), /changed/)
})

class Node {
  constructor() { this.value = ''; this.textContent = ''; this.dataset = {}; this.isConnected = true; this.events = new Map() }
  addEventListener(type, handler, options = {}) { this.events.set(type, handler); options.signal?.addEventListener('abort', () => this.events.delete(type), { once: true }) }
  async fire(type) { return this.events.get(type)?.() }
}
function surface(storage = new Map()) {
  const nodes = new Map(), document = { getElementById(id) { if (!nodes.has(id)) nodes.set(id, new Node()); return nodes.get(id) } }
  const get = key => document.getElementById('claw-recovery-' + key)
  get('context').textContent = JSON.stringify(context())
  let epoch = 0
  return { document, get, storage: { getItem: key => storage.get(key), setItem: (key, value) => storage.set(key, value) }, transport: () => ({ base: () => 'http://fixture', epoch: () => epoch }), changeAccess() { epoch++ } }
}
const ok = value => ({ ok: true, json: async () => value })
const acknowledgement = () => ({ session: { session: { session_key: context().session_key }, linked_run: [{ id: context().run_id }] } })
async function answer(ui, text = 'Use verified date. Do not publish.') { ui.get('answer').value = text; await ui.get('answer').fire('input') }

test('shipped controls load actual recovery route, preserve answer on reopen, and conditionally resume same run', async () => {
  const storage = new Map(), ui = surface(storage), calls = []
  const fetch = async (url, init) => { calls.push({ url, init }); return ok(url.endsWith('/recovery') ? fixture() : acknowledgement()) }
  let binding = bindBlockedRecovery(ui.document, { ...ui, fetch })
  await ui.get('refresh').fire('click'); await answer(ui)
  assert.equal(calls.length, 1, 'Typing and checkpoint reading never start execution')
  binding.dispose(); binding = bindBlockedRecovery(ui.document, { ...ui, fetch })
  assert.equal(ui.get('answer').value, 'Use verified date. Do not publish.')
  await ui.get('refresh').fire('click'); await ui.get('resume').fire('click')
  const posts = calls.filter(call => call.init.method === 'POST')
  assert.equal(posts.length, 1)
  assert.equal(posts[0].url, 'http://fixture/v1/cowork/sessions/work%3Afixture/runs/run-fixture/resume')
  assert.deepEqual(JSON.parse(posts[0].init.body), { content: 'Use verified date. Do not publish.', expected_checkpoint: checkpoint('a') })
  assert.equal(binding.session.state.phase, 'submitted'); assert.equal(ui.get('resume').disabled, true)
  await ui.get('resume').fire('click'); assert.equal(calls.filter(call => call.init.method === 'POST').length, 1)
  binding.dispose()
})

test('newer wait between inspect and submit prevents POST and keeps answer until deliberate re-review', async () => {
  const ui = surface(); let snapshot = fixture(), posts = 0
  const fetch = async (url, init) => { if (init.method === 'POST') posts++; return ok(snapshot) }
  const binding = bindBlockedRecovery(ui.document, { ...ui, fetch })
  await ui.get('refresh').fire('click'); await answer(ui); snapshot = fixture({ checkpoint: checkpoint('b') })
  await ui.get('resume').fire('click'); assert.equal(posts, 0); assert.match(ui.get('status').textContent, /checkpoint changed/)
  assert.equal(ui.get('answer').value, 'Use verified date. Do not publish.')
  await ui.get('adopt').fire('click'); assert.equal(binding.session.state.checkpoint, checkpoint('b'))
  binding.dispose()
})

test('lost POST acknowledgement is retained across reload and reconciles without a replacement run', async () => {
  const storage = new Map(), ui = surface(storage); let posts = 0, snapshot = fixture()
  const fetch = async (url, init) => { if (init.method === 'POST') { posts++; snapshot = fixture({ checkpoint: checkpoint('b'), resume_receipt: { checkpoint: [checkpoint('a')], content_digest: await sha256('Use verified date. Do not publish.'), message_id: 'saved' } }); throw new Error('connection lost') } return ok(snapshot) }
  let binding = bindBlockedRecovery(ui.document, { ...ui, fetch })
  await ui.get('refresh').fire('click'); await answer(ui); await ui.get('resume').fire('click')
  assert.equal(binding.session.state.phase, 'uncertain'); assert.match(ui.get('status').textContent, /may have reached/)
  binding.dispose(); binding = bindBlockedRecovery(ui.document, { ...ui, fetch }); await ui.get('refresh').fire('click')
  assert.equal(binding.session.state.phase, 'submitted'); assert.equal(posts, 1)
  assert.match(ui.get('status').textContent, /recorded this answer/)
  binding.dispose()
})

test('repeated clicks share one request and cancel during POST never claims execution stopped', async () => {
  const ui = surface(); let release, posts = 0
  const fetch = async (url, init) => { if (init.method === 'POST') { posts++; await new Promise(resolve => { release = resolve }); return ok(acknowledgement()) } return ok(fixture()) }
  const binding = bindBlockedRecovery(ui.document, { ...ui, fetch })
  await ui.get('refresh').fire('click'); await answer(ui)
  const submit = ui.get('resume').fire('click'); while (!release) await new Promise(resolve => setImmediate(resolve))
  await ui.get('resume').fire('click'); assert.equal(posts, 1)
  await ui.get('cancel').fire('click'); assert.match(ui.get('status').textContent, /does not cancel execution/)
  release(); await submit; assert.equal(binding.session.state.phase, 'uncertain')
  binding.dispose()
})

test('navigation and access changes discard stale reads without crossing answers between runs', async () => {
  for (const change of ['run', 'access', 'unmount']) {
    const ui = surface(); let release, hold = false
    const fetch = async () => { if (hold) await new Promise(resolve => { release = resolve }); return ok(fixture()) }
    const binding = bindBlockedRecovery(ui.document, { ...ui, fetch })
    await ui.get('refresh').fire('click'); await answer(ui); hold = true
    const read = ui.get('refresh').fire('click')
    if (change === 'run') { ui.get('context').textContent = JSON.stringify({ ...context(), run_id: 'other' }); binding.sync() }
    if (change === 'access') { ui.changeAccess(); binding.sync() }
    if (change === 'unmount') ui.get('panel').isConnected = false
    release(); await read
    if (change === 'run') assert.equal(binding.session.state.draft, '')
    if (change === 'access') { assert.equal(binding.session.snapshot, null); assert.equal(binding.session.state.draft, 'Use verified date. Do not publish.') }
    binding.dispose()
  }
})

test('authentication, malformed evidence, mixed failures and offline storage fail visibly without mutation', async () => {
  for (const response of [{ ok: false, json: async () => ({ error: { message: 'Bearer token required' } }) }, ok(fixture({ run_id: 'wrong' })), ok(fixture({ can_resume: false, status: 'Failed' }))]) {
    const ui = surface(), calls = [], binding = bindBlockedRecovery(ui.document, { ...ui, fetch: async (url, init) => { calls.push(init); return response } })
    await ui.get('refresh').fire('click'); await answer(ui); await ui.get('resume').fire('click')
    assert.equal(calls.filter(call => call.method === 'POST').length, 0); assert.equal(ui.get('answer').value, 'Use verified date. Do not publish.'); binding.dispose()
  }
  const ui = surface(); ui.storage.setItem = () => { throw new Error('full') }
  const binding = bindBlockedRecovery(ui.document, { ...ui, fetch: async () => ok(fixture()) })
  await ui.get('refresh').fire('click'); await answer(ui); await ui.get('cancel').fire('click')
  assert.match(ui.get('status').textContent, /storage is unavailable/); binding.dispose()
})

test('feature is wired to existing Work surface, guarded resume handler, retained session and bootstrap', async () => {
  const read = path => readFile(new URL(path, import.meta.url), 'utf8')
  assert.match(await read('./main/cowork_surface.mbt'), /render_cowork_blocked_recovery\(model\)/)
  assert.match(await read('./bootstrap.js'), /installBlockedRecovery\(document\)/)
  const handler = await read('../../gateway/server/cowork.mbt')
  assert.match(handler, /session.linked_run_id == Some\(run_id\)/)
  assert.match(handler, /actual == expected/)
  assert.match(handler, /recovery_resume_pending/)
  const part = handler.slice(handler.indexOf('async fn Gateway::handle_cowork_resume_run'))
  assert.ok(part.indexOf('self.save_session_detail') < part.indexOf('self.launch_job_run'))
})

test('two different answers for the same checkpoint are never falsely reconciled as this answer', async () => {
  const session = new BlockedRecovery(); session.observe(fixture(), context()); session.edit('Answer from this tab'); session.sending(await session.prepare())
  session.observe(fixture({ checkpoint: checkpoint('b'), resume_receipt: { checkpoint: [checkpoint('a')], content_digest: await sha256('Different answer from another tab'), message_id: 'other' } }), context())
  assert.equal(session.state.phase, 'superseded'); assert.equal(session.state.draft, 'Answer from this tab')
  assert.throws(() => session.request(), /checkpoint changed/)
  session.adopt(); assert.equal(session.state.phase, 'draft')
})

test('receipt lookup requests the original checkpoint even after later resumptions', async () => {
  const storage = new Map(), ui = surface(storage); let snapshot = fixture(), header, lose = true
  const fetch = async (url, init) => {
    if (init.method === 'POST' && lose) { lose = false; throw new Error('lost acknowledgement') }
    header = init.headers?.['X-Moonclaw-Recovery-Checkpoint']; return ok(snapshot)
  }
  const binding = bindBlockedRecovery(ui.document, { ...ui, fetch })
  await ui.get('refresh').fire('click'); await answer(ui); await ui.get('resume').fire('click')
  snapshot = fixture({ checkpoint: checkpoint('c'), resume_receipt: { checkpoint: [checkpoint('a')], content_digest: await sha256('Use verified date. Do not publish.'), message_id: 'original' } })
  await ui.get('refresh').fire('click')
  assert.equal(header, checkpoint('a')); assert.equal(binding.session.state.phase, 'submitted'); binding.dispose()
})

test('definite first-submit refusal retains editable answer while genuine transport uncertainty stays locked', async () => {
  const ui = surface()
  const fetch = async (url, init) => init.method === 'POST' ? { ok: false, json: async () => ({ error: { code: 'resume_not_submitted', message: 'Checkpoint changed before submit' } }) } : ok(fixture())
  const binding = bindBlockedRecovery(ui.document, { ...ui, fetch })
  await ui.get('refresh').fire('click'); await answer(ui); await ui.get('resume').fire('click')
  assert.equal(binding.session.state.phase, 'draft'); assert.equal(ui.get('answer').readOnly, false)
  assert.equal(ui.get('answer').value, 'Use verified date. Do not publish.'); binding.dispose()
})

test('request and saved answer digest use exactly the same normalized UTF-8 text', async () => {
  const session = new BlockedRecovery(); session.observe(fixture(), context()); session.edit('\u00a0  Verified 世界\n\u00a0')
  assert.equal(session.request().content, 'Verified 世界')
  assert.equal(await session.prepare(), await sha256(session.request().content))
})

test('malformed receipts and an active launch cannot settle or unlock an uncertain answer', async () => {
  const session = new BlockedRecovery(); session.observe(fixture(), context()); session.edit('Original answer'); session.sending(await session.prepare())
  for (const receipt of [{ checkpoint: [checkpoint('a')] }, { checkpoint: [checkpoint('a')], content_digest: 'invalid', message_id: 'one' }, { checkpoint: [checkpoint('a')], content_digest: await sha256('Other'), message_id: '' }, { checkpoint: 'invalid', content_digest: await sha256('Other'), message_id: 'one' }]) {
    assert.throws(() => session.observe(fixture({ resume_receipt: receipt }), context()), /Invalid recovery receipt/)
    assert.equal(session.state.phase, 'uncertain')
    assert.throws(() => session.adopt(), /uncertain/)
  }
  assert.throws(() => session.observe(fixture({ launch_pending: true }), context()), /active launch/)
  assert.equal(session.state.phase, 'uncertain')
})

test('corrupt tab storage is preserved exactly and cannot be overwritten by refresh or submission', async () => {
  const ui = surface(); let writes = 0, posts = 0
  ui.storage.getItem = () => '{broken saved answer'
  ui.storage.setItem = () => { writes++ }
  const binding = bindBlockedRecovery(ui.document, { ...ui, fetch: async (_url, init) => { if (init.method === 'POST') posts++; return ok(fixture()) } })
  await ui.get('refresh').fire('click'); await ui.get('resume').fire('click')
  assert.equal(writes, 0); assert.equal(posts, 0); assert.equal(binding.session.state.phase, 'uncertain')
  assert.match(ui.get('status').textContent, /left untouched/)
  binding.dispose()
})
