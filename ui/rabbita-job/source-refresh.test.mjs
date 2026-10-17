import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { webcrypto } from 'node:crypto'
import { SourceBrief, readLocalFiles, readPacket } from './source-brief.js'
import { sourceKey, retainedSnapshot } from './retained-sources.js'
import { sha256 } from './book-outcome.js'
import { exportSourceProject, openSourceProject } from './source-project.js'
import { prepareSourceRefresh, previewSourceRefresh, acceptSourceRefresh, quoteSourceLines } from './source-refresh.js'
import { mountSourceBrief, bindSourceBrief } from './source-brief-controls.js'
if (!globalThis.crypto) globalThis.crypto = webcrypto
const file = (name, text) => { const bytes = new TextEncoder().encode(text); return { name, size: bytes.byteLength, arrayBuffer: async () => bytes.buffer } }
const source = async (text, name = 'notes.txt') => (await readLocalFiles([file(name, text)]))[0]
const exact = (candidate = 0) => ({ mode: 'exact', candidate })
const range = (start_line, end_line, purpose = 'Updated relevance') => ({ mode: 'range', start_line, end_line, purpose })
const drop = () => ({ mode: 'drop' })
const context = () => ({ session_key: 'refresh-thread', cwd: '/work', cwd_override: '', run_id: 'run-1' })
async function selection(text = 'Header\nKeep this €😀\nChange me\nDrop me\n') {
  const session = new SourceBrief(); session.import([await source(text), await source('Other source\n', 'other.txt')]); session.setBudget(4096)
  session.put('notes.txt', 2, 2, 'Exact retained note'); session.put('other.txt', 1, 1, 'Independent source'); session.put('notes.txt', 3, 3, 'Old relevance'); session.put('notes.txt', 4, 4, 'No longer needed')
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
function surface(fixture = null) {
  const document = { nodes: new Map(), getElementById(id) { return this.nodes.get(id) || null }, createElement(tag) { return new Node(this, tag) } }
  const add = id => { const node = document.createElement('div'); node.id = id; return node }
  const anchor = add('claw-procedure-panel'), ctx = add('claw-procedure-context'), composer = add('claw-procedure-composer')
  ctx.textContent = JSON.stringify(context()); composer.value = 'Explain the revised evidence. Do not run any commands.\n'
  const root = mountSourceBrief(document, anchor), get = key => document.getElementById('claw-sources-' + key)
  let epoch = 0, inputEvents = 0
  composer.addEventListener('input', () => inputEvents++)
  const ui = { document, ctx, composer, root, get, r: key => get('refresh-' + key), saved: [], calls: [], get inputEvents() { return inputEvents }, changeAccess() { epoch++ }, transport: () => ({ base: () => 'http://fixture', epoch: () => epoch }) }
  ui.downloadProject = raw => ui.saved.push(raw)
  ui.fetch = async (url, init) => { ui.calls.push({ url, init }); assert.ok(fixture, 'local refresh must not use network'); return { ok: true, json: async () => structuredClone(url.includes('/artifacts/') ? fixture.payload : fixture.detail) } }
  ui.binding = bindSourceBrief(document, ui); return ui
}
async function openUI(ui, session) {
  ui.get('project-file').files = [file('project.json', typeof session === 'string' ? session : await exportSourceProject(session))]
  await ui.get('project-file').fire('change'); await ui.get('project-restore').fire('click')
}
async function refreshUI(ui, text, name = 'notes.txt') { ui.r('file').files = [file(name, text)]; await ui.r('file').fire('change') }
async function chooseUI(ui, index, decision) {
  ui.r('excerpt').value = String(index); await ui.r('excerpt').fire('change')
  if (decision.mode === 'exact') { ui.r('candidate').value = String(decision.candidate); await ui.r('candidate').fire('change') }
  if (decision.mode === 'range') { ui.r('start').value = String(decision.start_line); ui.r('end').value = String(decision.end_line); ui.r('purpose').value = decision.purpose; await ui.r('purpose').fire('input') }
  await ui.r(decision.mode).fire('click')
}

test('refresh maps exact shifted passages, revises changed excerpts, drops obsolete ones and retains interleaved order and notes', async () => {
  const session = await selection(), before = await exportSourceProject(session), plan = await prepareSourceRefresh(session, sourceKey(session.sources[0]), await source('New heading\nHeader\nKeep this €😀\nChanged finding\n'))
  assert.deepEqual(plan.rows.map(row => row.candidates), [[{ start_line: 3, end_line: 3 }], [], []])
  assert.equal(await exportSourceProject(session), before)
  const preview = await previewSourceRefresh(plan, [exact(), range(4, 4), drop()]), next = await acceptSourceRefresh(session, preview)
  assert.deepEqual(next.excerpts.map(item => [item.name, item.start_line, item.purpose]), [['notes.txt', 3, 'Exact retained note'], ['other.txt', 1, 'Independent source'], ['notes.txt', 4, 'Updated relevance']])
  assert.equal(next.excerpts[0].content_utf8, session.excerpts[0].content_utf8); assert.notEqual(next.excerpts[0].source_sha256, session.excerpts[0].source_sha256)
  assert.equal(next.budget, 4096); assert.equal(next.sources[0].restored_from_project, undefined); assert.equal(await exportSourceProject(session), before)
  assert.deepEqual((await openSourceProject(preview.raw)).excerpts, next.excerpts)
})
test('repeated passages require explicit selection, even when one candidate occupies the old offset', async () => {
  const session = new SourceBrief(); session.import([await source('Keep\n')]); session.put('notes.txt', 1, 1, 'Context matters')
  const plan = await prepareSourceRefresh(session, sourceKey(session.sources[0]), await source('Keep\nBetween\nKeep\n'))
  assert.deepEqual(plan.rows[0].candidates, [{ start_line: 1, end_line: 1 }, { start_line: 3, end_line: 3 }])
  await assert.rejects(previewSourceRefresh(plan, [null]), /every old excerpt/)
  await assert.rejects(previewSourceRefresh(plan, [exact(2)]), /candidate/)
  assert.equal((await previewSourceRefresh(plan, [exact(1)])).next.excerpts[0].start_line, 3)
})
test('exact matching preserves BOM, Unicode, CRLF, bare CR, whitespace and final newline distinctions', async () => {
  const session = new SourceBrief(), text = '\ufeffFirst\r\n€😀\r\nBare\rCR\nFinal'
  session.import([await source(text)]); session.put('notes.txt', 1, 2, 'Exact bytes'); session.put('notes.txt', 4, 4, 'No final newline')
  const plan = await prepareSourceRefresh(session, sourceKey(session.sources[0]), await source('Heading\n' + text))
  const next = (await previewSourceRefresh(plan, [exact(), exact()])).next
  assert.equal(next.excerpts[0].content_utf8, '\ufeffFirst\r\n€😀\r\n'); assert.equal(next.excerpts[1].content_utf8, 'Final')
  const changed = await prepareSourceRefresh(session, sourceKey(session.sources[0]), await source(text.replaceAll('\r\n', '\n') + '\n'))
  assert.deepEqual(changed.rows.map(row => row.candidates), [[], []]); assert.match(quoteSourceLines(text), /\\r\\n/)
})
test('unresolved, invalid, overlapping and over-budget decisions reject atomically', async () => {
  const session = await selection(), saved = await exportSourceProject(session), plan = await prepareSourceRefresh(session, sourceKey(session.sources[0]), await source('Keep this €😀\nChanged\n' + 'X'.repeat(5000) + '\n'))
  for (const decisions of [[], [exact()], [exact(), null, drop()], [exact(-1), drop(), drop()], [exact(0.5), drop(), drop()], [{ mode: 'guess' }, drop(), drop()], [range(0, 1), drop(), drop()], [range(2, 1), drop(), drop()], [range(1, 10), drop(), drop()], [range(1.5, 2), drop(), drop()], [range(1, 1, ''), drop(), drop()], [exact(), range(1, 2), drop()], [range(3, 3), drop(), drop()]]) await assert.rejects(previewSourceRefresh(plan, decisions))
  assert.equal(await exportSourceProject(session), saved)
})
test('refresh supports no excerpts, identical bytes and empty replacement only when selected excerpts are dropped', async () => {
  const session = new SourceBrief(); session.import([await source('x\n')])
  let plan = await prepareSourceRefresh(session, sourceKey(session.sources[0]), await source(''))
  assert.equal((await previewSourceRefresh(plan, [])).next.sources[0].content, '')
  session.put('notes.txt', 1, 1, 'Keep')
  plan = await prepareSourceRefresh(session, sourceKey(session.sources[0]), await source('x\n'))
  assert.equal((await previewSourceRefresh(plan, [exact()])).next.excerpts[0].content_utf8, 'x\n')
  plan = await prepareSourceRefresh(session, sourceKey(session.sources[0]), await source(''))
  await assert.rejects(previewSourceRefresh(plan, [range(1, 1)]), /empty/)
  assert.equal((await previewSourceRefresh(plan, [drop()])).next.excerpts.length, 0)
})
test('refresh refuses renamed, retained, corrupted and oversized snapshots and bounds total source bytes', async () => {
  const session = new SourceBrief(); session.import([await source('x\n')]); const key = sourceKey(session.sources[0])
  await assert.rejects(prepareSourceRefresh(session, key, await source('y', 'renamed.txt')), /same name/)
  await assert.rejects(prepareSourceRefresh(session, 'missing', await source('y')), /Select a local source/)
  await assert.rejects(prepareSourceRefresh(session, key, { ...await source('y'), bytes: 9 }), /byte count/)
  await assert.rejects(prepareSourceRefresh(session, key, { ...await source('y'), sha256: 'wrong' }), /fingerprint/)
  await assert.rejects(prepareSourceRefresh(session, key, { ...await source('y'), content: '\0' }), /NUL/)
  for (let i = 0; i < 4; i++) session.import([await source('a'.repeat(262143), 'large' + i)])
  const plan = await prepareSourceRefresh(session, key, await source('a'.repeat(262144)))
  await assert.rejects(previewSourceRefresh(plan, []), /1 MiB/)
})
test('bounded matcher exposes all repeated candidates and overlapping exact pattern occurrences', async () => {
  const session = new SourceBrief(); session.import([await source('A\nA\n')]); session.put('notes.txt', 1, 2, 'Repeated lines')
  const plan = await prepareSourceRefresh(session, sourceKey(session.sources[0]), await source('A\n'.repeat(2000)))
  assert.equal(plan.rows[0].candidates.length, 1999); assert.deepEqual(plan.rows[0].candidates.at(-1), { start_line: 1999, end_line: 2000 })
  await assert.rejects(prepareSourceRefresh(session, sourceKey(session.sources[0]), await source('A\n'.repeat(2001))), /2000 lines/)
  session.import([await source('A\n'.repeat(2001))]); await assert.rejects(prepareSourceRefresh(session, sourceKey(session.sources[0]), await source('A\n')), /2000 lines/)
})
test('accept refuses changed working sets and changed prepared results without overwriting either', async () => {
  const session = await selection(), plan = await prepareSourceRefresh(session, sourceKey(session.sources[0]), await source('Header\nKeep this €😀\nChange me\nDrop me\n'))
  const preview = await previewSourceRefresh(plan, [exact(), exact(), exact()])
  session.move(0, 1); await assert.rejects(acceptSourceRefresh(session, preview), /working set changed/); session.move(1, -1)
  preview.next.put('notes.txt', 2, 2, 'Edited after preview', 0); await assert.rejects(acceptSourceRefresh(session, preview), /preview changed/)
})
test('production cold-reopen→refresh→review→replace→task preview/apply→save/reopen→refresh again journey', async () => {
  const first = surface(); await openUI(first, await selection()); await first.get('preview').fire('click'); await first.get('apply').fire('click')
  const applied = first.composer.value, old = await exportSourceProject(first.binding.session)
  await first.get('project-preview-save').fire('click'); await first.get('project-download').fire('click'); first.binding.dispose()
  const ui = surface(); await openUI(ui, first.saved[0]); ui.composer.value = applied
  await refreshUI(ui, 'New heading\nHeader\nKeep this €😀\nChanged finding\n')
  assert.equal(await exportSourceProject(ui.binding.session), old); assert.equal(ui.r('candidate').value, ''); assert.match(ui.r('lines').textContent, /4: "Changed finding\\n"/)
  await chooseUI(ui, 0, exact()); await chooseUI(ui, 1, range(4, 4, 'Inspect revised finding')); await chooseUI(ui, 2, drop())
  await ui.r('preview').fire('click'); assert.equal(ui.r('apply').disabled, false); assert.match(ui.r('preview-text').textContent, /Inspect revised finding/)
  await ui.r('apply').fire('click'); assert.equal(ui.composer.value, applied); assert.equal(ui.inputEvents, 0); assert.equal(ui.binding.session.excerpts.length, 3)
  await ui.r('apply').fire('click'); assert.equal(ui.inputEvents, 0); assert.equal(ui.binding.session.excerpts.length, 3)
  await ui.get('preview').fire('click'); await ui.get('apply').fire('click')
  const packet = await readPacket(ui.composer.value); assert.equal(packet.excerpts[0].start_line, 3); assert.equal(packet.excerpts[2].content_utf8, 'Changed finding\n'); assert.equal(packet.authority_granted, false); assert.equal(packet.disk_freshness_verified, false)
  await ui.get('project-preview-save').fire('click'); await ui.get('project-download').fire('click'); ui.binding.dispose()
  const next = surface(); await openUI(next, ui.saved[0]); await refreshUI(next, 'Another heading\nNew heading\nHeader\nKeep this €😀\nChanged again\n')
  await chooseUI(next, 0, exact()); await chooseUI(next, 1, range(5, 5, 'Second refresh')); await next.r('preview').fire('click'); await next.r('apply').fire('click')
  assert.deepEqual(next.binding.session.excerpts.map(item => item.start_line), [4, 1, 5]); assert.equal(next.binding.session.excerpts[0].purpose, 'Exact retained note')
  assert.equal(ui.calls.length + first.calls.length + next.calls.length, 0); next.binding.dispose()
})
test('UI requires every choice, invalidates edited previews, permits changing decisions and preserves old state on invalid ranges', async () => {
  const ui = surface(); await openUI(ui, await selection()); const old = await exportSourceProject(ui.binding.session)
  await refreshUI(ui, 'Keep this €😀\nChanged\n'); await ui.r('preview').fire('click'); assert.equal(ui.r('apply').disabled, true)
  await ui.r('exact').fire('click'); assert.match(ui.get('status').textContent, /Choose an exact/)
  await chooseUI(ui, 0, exact()); await chooseUI(ui, 1, range(2, 2)); await chooseUI(ui, 2, drop()); await ui.r('preview').fire('click')
  await ui.r('purpose').fire('input'); await ui.r('apply').fire('click'); assert.equal(await exportSourceProject(ui.binding.session), old)
  await chooseUI(ui, 1, range(1, 2)); await ui.r('preview').fire('click'); assert.match(ui.get('status').textContent, /overlaps/); assert.equal(await exportSourceProject(ui.binding.session), old)
  await chooseUI(ui, 1, range(2, 2)); await ui.r('preview').fire('click'); await ui.r('apply').fire('click'); assert.notEqual(await exportSourceProject(ui.binding.session), old); ui.binding.dispose()
})
test('UI source selection, edits, cancellation, close and save/reopen actions discard staged refresh previews', async () => {
  for (const action of ['source', 'purpose', 'budget', 'query', 'composer', 'cancel', 'close', 'refresh-close', 'save', 'project', 'remove-source']) {
    const ui = surface(), original = await selection(); await openUI(ui, original)
    await refreshUI(ui, 'Keep this €😀\nChange me\nDrop me\n'); await chooseUI(ui, 0, exact()); await chooseUI(ui, 1, exact()); await chooseUI(ui, 2, exact()); await ui.r('preview').fire('click')
    assert.equal(ui.r('apply').disabled, false)
    if (action === 'source') await ui.get('source').fire('change')
    if (['purpose', 'budget', 'query'].includes(action)) await ui.get(action).fire('input')
    if (action === 'composer') await ui.composer.fire('input')
    if (action === 'cancel') await ui.get('cancel').fire('click')
    if (action === 'close') { ui.root.open = false; await ui.root.fire('toggle') }
    if (action === 'refresh-close') { ui.r('panel').open = false; await ui.r('panel').fire('toggle') }
    if (action === 'save') await ui.get('project-preview-save').fire('click')
    if (action === 'project') await openUI(ui, original)
    if (action === 'remove-source') await ui.get('remove-source').fire('click')
    const current = await exportSourceProject(ui.binding.session); await ui.r('apply').fire('click'); assert.equal(await exportSourceProject(ui.binding.session), current); assert.equal(ui.r('apply').disabled, true); ui.binding.dispose()
  }
})
test('late revised-file reads cannot replace new picks, edits, closed panels, disposed views or changed context/access', async () => {
  for (const action of ['cancel', 'new-file', 'edit', 'close', 'refresh-close', 'unmount', 'dispose', 'context', 'access']) {
    const ui = surface(); await openUI(ui, await selection()); const old = await exportSourceProject(ui.binding.session); let release
    const slow = file('notes.txt', 'Slow\nKeep this €😀\nChange me\nDrop me\n')
    ui.r('file').files = [{ ...slow, arrayBuffer: () => new Promise(resolve => { release = async () => resolve(await slow.arrayBuffer()) }) }]
    const pending = ui.r('file').fire('change')
    if (action === 'cancel') await ui.get('cancel').fire('click')
    if (action === 'new-file') await refreshUI(ui, 'Newer\nKeep this €😀\nChange me\nDrop me\n')
    if (action === 'edit') await ui.get('purpose').fire('input')
    if (action === 'close') { ui.root.open = false; await ui.root.fire('toggle') }
    if (action === 'refresh-close') { ui.r('panel').open = false; await ui.r('panel').fire('toggle') }
    if (action === 'unmount') ui.root.isConnected = false
    if (action === 'dispose') ui.binding.dispose()
    if (action === 'context') { ui.ctx.textContent = JSON.stringify({ ...context(), session_key: 'other' }); ui.binding.sync(); ui.ctx.textContent = JSON.stringify(context()); ui.binding.sync() }
    if (action === 'access') { ui.changeAccess(); ui.binding.sync() }
    await release(); await pending
    assert.doesNotMatch(ui.r('lines').textContent, /Slow/); assert.equal(ui.r('apply').disabled, true)
    if (action === 'new-file') assert.match(ui.r('lines').textContent, /Newer/)
    if (['context', 'access'].includes(action)) assert.equal(ui.binding.session.sources.length, 0); else assert.equal(await exportSourceProject(ui.binding.session), old)
    assert.equal(ui.inputEvents, 0); ui.binding.dispose()
  }
})
test('refresh leaves same-name retained provenance untouched and ordinary task preview still checks its gateway revision', async () => {
  const text = 'Exact retained\n', artifact = { id: 'notes.txt', run_id: 'run-1', job_id: 'job-1', version: 2, content_type: 'text/plain', logical_key: ['notes'] }
  const fixture = { detail: { run: { id: 'run-1', job_id: 'job-1', status: 'Failed' }, artifacts: [artifact] }, payload: { artifact, content: [text], revision_source: { run_id: 'run-1', parent_version: 2, parent_digest: await sha256(text) } } }
  const retained = await retainedSnapshot(fixture.payload, fixture.detail, artifact.id), session = new SourceBrief(); session.import([await source('Local\n'), retained]); session.put('notes.txt', 1, 1, 'Local note'); session.put(sourceKey(retained), 1, 1, 'Retained note')
  await assert.rejects(prepareSourceRefresh(session, sourceKey(retained), await source('New')), /local source/)
  const ui = surface(fixture); await openUI(ui, session); await refreshUI(ui, 'Heading\nLocal\n'); await chooseUI(ui, 0, exact()); await ui.r('preview').fire('click'); await ui.r('apply').fire('click')
  assert.deepEqual(ui.binding.session.excerpts[1], session.excerpts[1]); assert.equal(ui.calls.length, 0)
  await ui.get('preview').fire('click'); assert.equal(ui.calls.length, 2)
  fixture.payload.content = ['Changed remotely\n']; await ui.get('apply').fire('click'); assert.equal(ui.inputEvents, 0); assert.match(ui.get('status').textContent, /changed/); ui.binding.dispose()
})

test('portable demonstration files reproduce the reviewed source project through the production mounted entrypoint', async () => {
  const base = new URL('../../docs/examples/source-refresh/', import.meta.url)
  const before = await readFile(new URL('before.json', base), 'utf8'), revised = await readFile(new URL('research-note.txt', base), 'utf8'), choices = JSON.parse(await readFile(new URL('decisions.json', base), 'utf8')), expected = await readFile(new URL('after.json', base), 'utf8')
  const ui = surface(); await openUI(ui, before); await refreshUI(ui, revised, 'research-note.txt')
  for (let index = 0; index < choices.length; index++) await chooseUI(ui, index, choices[index])
  await ui.r('preview').fire('click'); await ui.r('apply').fire('click'); assert.deepEqual(JSON.parse(await exportSourceProject(ui.binding.session)), JSON.parse(expected))
  await ui.get('preview').fire('click'); await ui.get('apply').fire('click'); const packet = await readPacket(ui.composer.value)
  assert.deepEqual(packet.excerpts.map(item => [item.start_line, item.end_line, item.content_utf8]), [[3, 3, 'The queue now retries only after confirmed no effect.\n'], [4, 4, 'Unknown effects require reconciliation.\n']]); assert.equal(ui.inputEvents, 1); ui.binding.dispose()
})
