import test from 'node:test'
import assert from 'node:assert/strict'
import { webcrypto } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { SourceBrief, readLocalFiles, readPacket, byteLength, FILE_LIMIT } from './source-brief.js'
import { sourceKey, retainedSnapshot } from './retained-sources.js'
import { sha256 } from './book-outcome.js'
import { exportSourceProject, openSourceProject, readSourceProjectFile, checkSourceProjectContext, describeSourceProject, downloadSourceProject, PROJECT_LIMIT } from './source-project.js'
import { mountSourceBrief, bindSourceBrief } from './source-brief-controls.js'
if (!globalThis.crypto) globalThis.crypto = webcrypto
const content = '\ufeffResearch notes\r\nExact fact €😀\r\nOmitted private context\r\nFinal observation'
const file = (name, text = content) => { const bytes = new TextEncoder().encode(text); return { name, size: bytes.byteLength, arrayBuffer: async () => bytes.buffer } }
const ctx = () => ({ session_key: 'thread-A', cwd: '/private/work-folder', cwd_override: '', run_id: 'run-original' })
const record = () => ({ id: 'retained-report', run_id: ctx().run_id, job_id: 'job-original', version: 2, content_type: 'text/markdown', logical_key: ['report'] })
async function retained(status = 'Failed') {
  const detail = { run: { id: ctx().run_id, job_id: 'job-original', status }, artifacts: [record()] }
  const payload = { artifact: record(), content: [content], revision_source: { run_id: ctx().run_id, parent_version: 2, parent_digest: await sha256(content) } }
  return { detail, payload, source: await retainedSnapshot(payload, detail, record().id) }
}
async function selected() {
  const session = new SourceBrief(); session.import(await readLocalFiles([file('notes.txt'), file('second.md', '# Second source\nUseful comparison\n'), file('empty.txt', '')]))
  session.setBudget(4096); session.put('notes.txt', 2, 2, 'Supports the quantity'); session.put('second.md', 1, 2, 'Independent comparison'); session.put('notes.txt', 4, 4, 'Closing detail'); session.move(2, -2)
  return session
}
class Node {
  constructor(document, tag) { this.document = document; this.tagName = tag; this._value = ''; this.textContent = ''; this.dataset = {}; this.isConnected = true; this.events = new Map(); this.children = []; this.files = []; this.attributes = {} }
  set value(value) { this._value = this.tagName === 'select' && !this.children.some(node => node.value === value) ? '' : value } get value() { return this._value }
  set id(value) { this._id = value; this.document.nodes.set(value, this) } get id() { return this._id }
  setAttribute(key, value) { this.attributes[key] = value }
  appendChild(node) { this.children.push(node) }
  replaceChildren() { this.children = []; this.value = '' }
  insertAdjacentElement(_, node) { this.after = node }
  remove() { this.isConnected = false; this.document.nodes.delete(this.id) }
  addEventListener(type, fn, options = {}) { const handlers = this.events.get(type) || []; handlers.push(fn); this.events.set(type, handlers); options.signal?.addEventListener('abort', () => this.events.set(type, (this.events.get(type) || []).filter(item => item !== fn)), { once: true }) }
  dispatchEvent(event) { for (const fn of this.events.get(event.type) || []) fn(event); return true }
  async fire(type) { for (const fn of this.events.get(type) || []) await fn() }
}
function surface(fixture) {
  const document = { nodes: new Map(), getElementById(id) { return this.nodes.get(id) || null }, createElement(tag) { return new Node(this, tag) } }
  const add = id => { const node = document.createElement('div'); node.id = id; return node }
  const anchor = add('claw-procedure-panel'), context = add('claw-procedure-context'), composer = add('claw-procedure-composer')
  context.textContent = JSON.stringify(ctx()); composer.value = 'Compare these sources; do not publish.\n'
  const root = mountSourceBrief(document, anchor), get = key => document.getElementById('claw-sources-' + key)
  let epoch = 0, inputEvents = 0
  composer.addEventListener('input', () => inputEvents++)
  const ui = { document, context, composer, root, get, saved: [], calls: [], fixture, get inputEvents() { return inputEvents }, changeAccess() { epoch++ }, transport: () => ({ base: () => 'http://fixture', epoch: () => epoch }) }
  ui.downloadProject = raw => ui.saved.push(raw)
  ui.fetch = async (url, init) => { ui.calls.push({ url, init }); assert.ok(ui.fixture, 'local project must not use network'); return { ok: true, json: async () => structuredClone(url.includes('/artifacts/') ? ui.fixture.payload : ui.fixture.detail) } }
  ui.binding = bindSourceBrief(document, ui); return ui
}
async function importUI(ui, files = [file('notes.txt'), file('second.md', '# Second source\nUseful comparison\n')]) { ui.get('files').files = files; await ui.get('files').fire('change') }
async function addUI(ui, name, start, end, purpose) { ui.get('source').value = sourceKey({ name }); await ui.get('source').fire('change'); ui.get('start').value = String(start); ui.get('end').value = String(end); ui.get('purpose').value = purpose; await ui.get('add').fire('click') }
async function openUI(ui, raw) { ui.get('project-file').files = [file('project.json', raw)]; await ui.get('project-file').fire('change') }

test('portable project round-trips exact BOM/CRLF/Unicode/no-final-newline snapshots, unselected sources, notes, budget and order', async () => {
  const before = await selected(), raw = await exportSourceProject(before), after = await openSourceProject(raw)
  assert.deepEqual(after.excerpts, before.excerpts); assert.equal(after.budget, 4096); assert.equal(after.sources[0].content, content); assert.equal(after.sources[2].content, '')
  assert.ok(after.sources.every(item => item.restored_from_project)); assert.ok(after.sources.every(Object.isFrozen)); assert.equal(await exportSourceProject(after), raw)
  assert.match(raw, /Omitted private context/); assert.match(describeSourceProject(after), /even omitted lines and unselected sources/)
  assert.doesNotMatch(raw, /thread-A|private\/work-folder|request_text|gateway|token|approval/)
})
test('unfinished source preparation with no excerpts can be saved, reopened and selected later', async () => {
  const session = new SourceBrief(); session.import(await readLocalFiles([file('notes.txt')]))
  const reopened = await openSourceProject(await exportSourceProject(session)); assert.equal(reopened.excerpts.length, 0)
  reopened.put('notes.txt', 2, 2, 'Continue later'); assert.equal((await reopened.packet(ctx())).selected_bytes, byteLength('Exact fact €😀\r\n'))
  await assert.rejects(exportSourceProject(new SourceBrief()), /one to eight/)
})
test('shipped fictional project opens through production controls and resumes into the ordinary task packet', async () => {
  const raw = await readFile(new URL('../../docs/examples/source-project-demo.json', import.meta.url), 'utf8'), ui = surface()
  await openUI(ui, raw); await ui.get('project-restore').fire('click'); assert.equal(ui.binding.session.excerpts.length, 2)
  ui.get('excerpt').value = '1'; await ui.get('excerpt').fire('change'); ui.get('purpose').value = 'Check the stop condition first'; await ui.get('update').fire('click'); await ui.get('up').fire('click')
  await ui.get('preview').fire('click'); await ui.get('apply').fire('click')
  const packet = await readPacket(ui.composer.value); assert.equal(packet.excerpts[0].content_utf8, 'Unknown effects require reconciliation.\n'); assert.equal(packet.excerpts[0].purpose, 'Check the stop condition first')
  await ui.get('project-preview-save').fire('click'); await ui.get('project-download').fire('click'); assert.equal((await openSourceProject(ui.saved[0])).excerpts[0].start_line, 3); ui.binding.dispose()
})
test('local and retained snapshots with the same name preserve distinct identity and failed/cancelled run state', async () => {
  for (const state of ['Failed', 'Cancelled', 'Succeeded']) {
    const fixture = await retained(state), session = new SourceBrief(); session.import([fixture.source, ...await readLocalFiles([file(record().id)])])
    session.put(sourceKey(fixture.source), 2, 2, 'Retained evidence'); session.put(record().id, 4, 4, 'Local evidence')
    const project = JSON.parse(await exportSourceProject(session)); project.sources[0].provenance = Object.fromEntries(Object.entries(project.sources[0].provenance).reverse())
    const reopened = await openSourceProject(JSON.stringify(project)); assert.equal(reopened.sources.length, 2); assert.deepEqual(reopened.excerpts, session.excerpts)
    assert.equal(reopened.excerpts[0].provenance.original_run_status, state); checkSourceProjectContext(reopened, ctx())
    assert.throws(() => checkSourceProjectContext(reopened, { run_id: 'other' }), /another linked run/)
    assert.equal((await reopened.packet(ctx())).authority_granted, false)
  }
})
test('malformed and forged projects reject unknown schemas/fields/claims, invalid bytes/digests and broken source references', async () => {
  const project = JSON.parse(await exportSourceProject(await selected()))
  const changes = [value => { value.contract_version = 'future' }, value => { value.authority_granted = true }, value => { value.disk_freshness_verified = true }, value => { value.accepted_knowledge = true }, value => { value.token = 'must-not-be-imported' }, value => { value.sources[0].bytes++ }, value => { value.sources[0].content_utf8 += 'changed' }, value => { value.sources[0].name = '\ud800' }, value => { value.sources[0].content_utf8 = '\ud800' }, value => { value.sources[0].content_utf8 = 'x\0y' }, value => { value.sources[0].sha256 = 'wrong' }, value => { value.sources[0].credential = 'no' }, value => { value.excerpts[0].source_key = 'missing' }, value => { value.excerpts[0].purpose = '' }, value => { value.excerpts[0].content_utf8 = 'forged excerpt' }, value => { value.excerpts[0].end_line = 100 }, value => { value.excerpts[0].start_line = 1.5 }, value => { value.excerpt_budget_bytes = 1000 }]
  for (const change of changes) { const next = structuredClone(project); change(next); await assert.rejects(openSourceProject(JSON.stringify(next))) }
  for (const raw of ['{', 'null', '[]', '{}', '"string"']) await assert.rejects(openSourceProject(raw))
})
test('duplicates, overlap, missing fields and all source/excerpt/serialized-byte limits fail without truncation', async () => {
  const project = JSON.parse(await exportSourceProject(await selected()))
  for (const change of [value => { value.sources.push(value.sources[0]) }, value => { value.excerpts.push(value.excerpts[0]) }, value => { delete value.sources[0].bytes }, value => { value.sources = Array(9).fill(value.sources[0]) }, value => { value.excerpts = Array(9).fill(value.excerpts[0]) }]) {
    const next = structuredClone(project); change(next); await assert.rejects(openSourceProject(JSON.stringify(next)))
  }
  const large = new SourceBrief(); large.import(await readLocalFiles([file('large', 'é'.repeat(600))])); large.put('large', 1, 1, 'Too much after lowering'); large.setBudget(1024)
  await assert.rejects(exportSourceProject(large), /budget/)
  const huge = { ...project.sources[0], content_utf8: 'x'.repeat(FILE_LIMIT + 1), bytes: FILE_LIMIT + 1 }; huge.sha256 = await sha256(huge.content_utf8)
  await assert.rejects(openSourceProject(JSON.stringify({ ...project, sources: [huge], excerpts: [] })), /256 KiB/)
  const one = { ...huge, content_utf8: 'x'.repeat(FILE_LIMIT), bytes: FILE_LIMIT }; one.sha256 = await sha256(one.content_utf8)
  await assert.rejects(openSourceProject(JSON.stringify({ ...project, sources: Array.from({ length: 5 }, (_, i) => ({ ...one, name: String(i) })), excerpts: [] })), /1 MiB/)
  await assert.rejects(openSourceProject(' '.repeat(PROJECT_LIMIT + 1)), /8 MiB/)
})
test('project file reader bounds reads and rejects invalid UTF-8, changed byte counts and malformed JSON', async () => {
  let read = false
  await assert.rejects(readSourceProjectFile({ size: PROJECT_LIMIT + 1, arrayBuffer: () => { read = true } }), /8 MiB/); assert.equal(read, false)
  await assert.rejects(readSourceProjectFile({ size: 1, arrayBuffer: async () => Uint8Array.of(255).buffer }), /UTF-8/)
  await assert.rejects(readSourceProjectFile({ ...file('project', '{}'), size: 1 }), /changed/)
  const raw = await exportSourceProject(await selected()), opened = await readSourceProjectFile(file('project.json', '\ufeff' + raw))
  assert.equal(opened.session.excerpts.length, 3); assert.equal(opened.raw, raw)
})
test('export catches stale internal selections and takes an immutable snapshot before hashing', async () => {
  const session = await selected(), pending = exportSourceProject(session); session.excerpts[0].purpose = 'Edited later'
  const saved = await openSourceProject(await pending); assert.notEqual(saved.excerpts[0].purpose, session.excerpts[0].purpose)
  session.excerpts[0].content_utf8 = 'different'; await assert.rejects(exportSourceProject(session), /no longer matches/)
})
test('production file import→curate→save→cold reopen→edit/reorder→preview/apply completes with exact task output', async () => {
  const first = surface(); await importUI(first); first.get('budget').value = '4096'
  await addUI(first, 'notes.txt', 2, 2, 'Evidence A'); await addUI(first, 'second.md', 2, 2, 'Evidence B')
  const firstDraft = first.composer.value; await first.get('project-preview-save').fire('click')
  assert.match(first.get('project-info').textContent, /full|All/); assert.match(first.get('project-text').textContent, /Omitted private context/)
  await first.get('project-download').fire('click'); assert.equal(first.saved.length, 1); assert.equal(first.composer.value, firstDraft); assert.equal(first.inputEvents, 0)
  const raw = first.saved[0]; first.binding.dispose()
  const reopened = surface(); await importUI(reopened, [file('existing.txt', 'Keep me unless replaced')]); const old = JSON.stringify(reopened.binding.session)
  await openUI(reopened, raw); assert.equal(JSON.stringify(reopened.binding.session), old); assert.match(reopened.get('project-info').textContent, /discard the current 1 unsent sources/)
  await reopened.get('project-restore').fire('click'); assert.equal(reopened.binding.session.sources.length, 2); assert.equal(reopened.get('budget').value, '4096'); assert.match(reopened.get('source-info').textContent, /reopened saved snapshot; freshness unverified/)
  reopened.get('excerpt').value = '1'; await reopened.get('excerpt').fire('change'); reopened.get('purpose').value = 'Compare this first'; await reopened.get('update').fire('click'); await reopened.get('up').fire('click')
  assert.equal(reopened.binding.session.excerpts[0].name, 'second.md'); assert.equal(reopened.binding.session.excerpts[0].purpose, 'Compare this first')
  await reopened.get('preview').fire('click'); await reopened.get('apply').fire('click')
  const packet = await readPacket(reopened.composer.value); assert.equal(packet.excerpts[0].content_utf8, 'Useful comparison\n'); assert.equal(packet.excerpts[1].content_utf8, 'Exact fact €😀\r\n')
  assert.equal(packet.excerpt_budget_bytes, 4096); assert.equal(packet.session_key, ctx().session_key); assert.equal(packet.disk_freshness_verified, false); assert.doesNotMatch(reopened.composer.value, /Omitted private context/)
  assert.equal(reopened.inputEvents, 1); assert.equal(first.calls.length + reopened.calls.length, 0); reopened.binding.dispose()
})
test('failed project open is atomic and preserves an already-applied task and current curated sources', async () => {
  const ui = surface(); await importUI(ui); await addUI(ui, 'notes.txt', 2, 2, 'Current choice'); await ui.get('preview').fire('click'); await ui.get('apply').fire('click')
  const before = JSON.stringify(ui.binding.session), draft = ui.composer.value, project = JSON.parse(await exportSourceProject(await selected()))
  project.excerpts[2].end_line = 900; await openUI(ui, JSON.stringify(project)); await ui.get('project-restore').fire('click')
  assert.equal(JSON.stringify(ui.binding.session), before); assert.equal(ui.composer.value, draft); assert.equal(ui.inputEvents, 1); assert.equal(ui.get('project-restore').disabled, true); ui.binding.dispose()
})
test('saved and opened project previews are invalidated by every ordinary editor change and cannot be replayed', async () => {
  const ui = surface(); await importUI(ui); await addUI(ui, 'notes.txt', 2, 2, 'Current choice'); const raw = await exportSourceProject(ui.binding.session)
  for (const key of ['purpose', 'start', 'end', 'budget', 'query']) {
    await ui.get('project-preview-save').fire('click'); await ui.get(key).fire('input'); await ui.get('project-download').fire('click'); assert.equal(ui.saved.length, 0)
    await openUI(ui, raw); await ui.get(key).fire('input'); await ui.get('project-restore').fire('click'); assert.equal(ui.binding.session.sources[0].restored_from_project, undefined)
  }
  await ui.get('project-preview-save').fire('click'); await ui.get('project-download').fire('click'); await ui.get('project-download').fire('click'); assert.equal(ui.saved.length, 1)
  await openUI(ui, raw); await ui.composer.fire('input'); await ui.get('project-restore').fire('click'); assert.equal(ui.binding.session.sources[0].restored_from_project, undefined); ui.binding.dispose()
})
test('cancel/new file/close/unmount/dispose/context A→B→A/access changes fence late project reads', async () => {
  const raw = await exportSourceProject(await selected())
  for (const action of ['cancel', 'new-file', 'close', 'unmount', 'dispose', 'context', 'access']) {
    const ui = surface(); let release
    ui.get('project-file').files = [{ ...file('slow.json', raw), arrayBuffer: () => new Promise(resolve => { release = async () => resolve(await file('x', raw).arrayBuffer()) }) }]
    const pending = ui.get('project-file').fire('change')
    if (action === 'cancel') await ui.get('cancel').fire('click')
    if (action === 'new-file') await openUI(ui, await exportSourceProject(await selected()))
    if (action === 'close') { ui.root.open = false; await ui.root.fire('toggle') }
    if (action === 'unmount') ui.root.isConnected = false
    if (action === 'dispose') ui.binding.dispose()
    if (action === 'context') { ui.context.textContent = JSON.stringify({ ...ctx(), session_key: 'B' }); ui.binding.sync(); ui.context.textContent = JSON.stringify(ctx()); ui.binding.sync() }
    if (action === 'access') { ui.changeAccess(); ui.binding.sync() }
    await release(); await pending; assert.equal(ui.binding.session.sources.length, 0); assert.equal(ui.composer.value, 'Compare these sources; do not publish.\n')
    assert.equal(ui.get('project-restore').disabled, action !== 'new-file'); ui.binding.dispose()
  }
})
test('reopening retained sources is offline snapshot curation and preview/apply still reread exact current gateway revision', async () => {
  const fixture = await retained(), session = new SourceBrief(); session.import([fixture.source]); session.put(sourceKey(fixture.source), 2, 2, 'Retained fact')
  const ui = surface(fixture); await openUI(ui, await exportSourceProject(session)); await ui.get('project-restore').fire('click'); assert.equal(ui.calls.length, 0)
  await ui.get('preview').fire('click'); assert.equal(ui.calls.length, 2); assert.equal(ui.get('apply').disabled, false)
  fixture.payload.artifact.version = 3; await ui.get('apply').fire('click'); assert.equal(ui.inputEvents, 0); assert.match(ui.get('status').textContent, /changed/)
  fixture.payload.artifact.version = 2; await ui.get('preview').fire('click'); await ui.get('apply').fire('click'); assert.equal(ui.inputEvents, 1)
  const packet = await readPacket(ui.composer.value); assert.equal(packet.excerpts[0].provenance.original_run_status, 'Failed'); assert.equal(packet.excerpts[0].provenance.version, 2)
  assert.ok(ui.calls.every(call => call.init.cache === 'no-store' && call.init.redirect === 'error')); ui.binding.dispose()
})
test('saved retained provenance cannot cross linked runs or bypass changed bytes, job, logical key, or terminal status', async () => {
  const original = await retained(), session = new SourceBrief(); session.import([original.source]); session.put(sourceKey(original.source), 2, 2, 'Retained fact'); const raw = await exportSourceProject(session)
  const different = surface(); different.context.textContent = JSON.stringify({ ...ctx(), run_id: 'other' }); await openUI(different, raw); await different.get('project-restore').fire('click')
  assert.equal(different.binding.session.sources.length, 0); assert.match(different.get('status').textContent, /another linked run/); different.binding.dispose()
  for (const change of [fixture => { fixture.payload.content = ['changed'] }, fixture => { fixture.payload.artifact.job_id = 'other' }, fixture => { fixture.payload.artifact.logical_key = ['other'] }, fixture => { fixture.detail.run.status = 'Running' }]) {
    const fixture = await retained(), ui = surface(fixture); await openUI(ui, raw); await ui.get('project-restore').fire('click'); change(fixture)
    await ui.get('preview').fire('click'); await ui.get('apply').fire('click'); assert.equal(ui.inputEvents, 0); assert.equal(ui.binding.session.excerpts.length, 1); ui.binding.dispose()
  }
})
test('download uses exact JSON Blob, fixed local filename, explicit click and object URL cleanup', async () => {
  const raw = await exportSourceProject(await selected()); let blob, clicked = 0, removed = 0, cleanup, revoked
  const link = { click() { clicked++ }, remove() { removed++ } }, document = { createElement() { return link }, body: { appendChild() {} } }, url = { createObjectURL(value) { blob = value; return 'blob:local-test' }, revokeObjectURL(value) { revoked = value } }
  const timer = globalThis.setTimeout; globalThis.setTimeout = fn => { cleanup = fn }
  try { downloadSourceProject(raw, document, url) } finally { globalThis.setTimeout = timer }
  assert.equal(await blob.text(), raw); assert.equal(blob.type, 'application/json;charset=utf-8'); assert.equal(link.download, 'moonclaw-source-project.json'); assert.equal(link.href, 'blob:local-test'); assert.equal(clicked, 1); assert.equal(removed, 1); cleanup(); assert.equal(revoked, 'blob:local-test')
})
