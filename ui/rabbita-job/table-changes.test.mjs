import test from 'node:test'
import assert from 'node:assert/strict'
import { webcrypto } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { readTableFile, positions, compareTables, ChangeSelection, validateChangesPacket, readChangesPacket, composeChanges, removeChanges, BEGIN, END } from './table-changes.js'
import { mountTableChanges, bindTableChanges, installTableChanges } from './table-changes-controls.js'
import { sha256 } from './book-outcome.js'
import { TableSelection, composeTable, readTablePacket } from './table-input.js'
if (!globalThis.crypto) globalThis.crypto = webcrypto
const oldText = 'ID,Status,Note,Private\n001,waiting,"First line\nsecond, line",old-private\n002,ready,unchanged,private-2\n003,closed,remove,private-3\n'
const newText = 'Memo,Item,Private,State\nunchanged,002,changed-private,ready\n"First line\nnew line",001,new-private,active\n=SUM(A1),004,private-4,new\n'
const mapping = { beforeKeys: [1], afterKeys: [2], beforeColumns: [2, 3], afterColumns: [4, 1] }
const context = () => ({ session_key: 'thread-A', cwd: '/work', cwd_override: '' })
const file = (name, value) => { const bytes = new TextEncoder().encode(value); return { name, size: bytes.byteLength, arrayBuffer: async () => bytes.buffer } }
async function comparison(a = oldText, b = newText, mapped = mapping) { return compareTables(await readTableFile(file('before.csv', a)), await readTableFile(file('after.csv', b)), mapped) }
async function selected() { const selection = new ChangeSelection(await comparison()); for (const row of selection.comparison.records) selection.add(row.id); return selection }

class Node {
  constructor(document, tag) { this.document = document; this.tagName = tag; this._value = ''; this.textContent = ''; this.dataset = {}; this.isConnected = false; this.events = new Map(); this.children = []; this.files = []; this.attributes = {} }
  set value(value) { this._value = this.tagName === 'select' && !this.children.some(node => node.value === value) ? '' : value } get value() { return this._value }
  set id(value) { this._id = value; this.document.nodes.set(value, this) } get id() { return this._id }
  setAttribute(key, value) { this.attributes[key] = value }
  setConnected(value) { this.isConnected = value; for (const child of this.children) child.setConnected(value) }
  appendChild(node) { this.children.push(node); node.setConnected(this.isConnected) }
  replaceChildren() { for (const node of this.children) node.setConnected(false); this.children = []; this.value = '' }
  insertAdjacentElement(_, node) { this.after = node; node.setConnected(this.isConnected) }
  remove() { this.setConnected(false); this.document.nodes.delete(this.id) }
  addEventListener(type, fn, options = {}) { const handlers = this.events.get(type) || []; handlers.push(fn); this.events.set(type, handlers); options.signal?.addEventListener('abort', () => this.events.set(type, (this.events.get(type) || []).filter(item => item !== fn)), { once: true }) }
  dispatchEvent(event) { for (const fn of this.events.get(event.type) || []) fn(event); return true }
  async fire(type) { for (const fn of this.events.get(type) || []) await fn() }
}
function surface(bind = true) {
  const document = { nodes: new Map(), getElementById(id) { const node = this.nodes.get(id); return node?.isConnected ? node : null }, createElement(tag) { return new Node(this, tag) } }
  const add = id => { const node = document.createElement('div'); node.id = id; node.setConnected(true); return node }
  const anchor = add('claw-procedure-panel'), ctx = add('claw-procedure-context'), composer = add('claw-procedure-composer'); ctx.textContent = JSON.stringify(context()); composer.value = 'Summarize selected changes. Do not execute formulas.\n'
  const root = bind ? mountTableChanges(document, anchor) : null, get = key => document.getElementById('claw-changes-' + key)
  let epoch = 0, inputEvents = 0; composer.addEventListener('input', () => inputEvents++)
  const ui = { document, anchor, context: ctx, composer, root, get, get inputEvents() { return inputEvents }, changeAccess() { epoch++ }, transport: () => ({ base: () => '/gateway', epoch: () => epoch }), inputEvent: () => ({ type: 'input' }) }
  if (bind) ui.binding = bindTableChanges(document, ui)
  return ui
}
async function importUI(ui, side, value, name = side + '.csv') { ui.get(side + '-file').files = [file(name, value)]; await ui.get(side + '-file').fire('change') }
async function prepare(ui) {
  await importUI(ui, 'before', oldText); await importUI(ui, 'after', newText)
  for (const [name, value] of [['before-keys', '1'], ['after-keys', '2'], ['before-columns', '2,3'], ['after-columns', '4,1']]) { ui.get(name).value = value; await ui.get(name).fire('input') }
  await ui.get('compare').fire('click')
  for (const row of ui.binding.selection.comparison.records) { ui.get('record').value = row.id; await ui.get('record').fire('change'); await ui.get('add').fire('click') }
  ui.get('purpose').value = 'Explain these selected changes'; await ui.get('purpose').fire('input')
}

test('literal key matching survives reorder and header remapping; omitted-column changes are not compared', async () => {
  const value = await comparison(); assert.equal(value.unchanged, 1)
  assert.deepEqual(value.records.map(row => [row.key, row.kind]), [[['001'], 'changed'], [['003'], 'removed'], [['004'], 'added']])
  assert.deepEqual(value.records[0].before.cells, ['waiting', 'First line\nsecond, line'])
  assert.deepEqual(value.records[0].after.cells, ['active', 'First line\nnew line'])
  assert.deepEqual(value.records[0].before, { record_number: 2, start_line: 2, end_line: 3, cells: ['waiting', 'First line\nsecond, line'] })
  assert.equal(value.records[0].after.record_number, 3)
  assert.equal(value.records[2].after.cells[1], '=SUM(A1)')
  assert.deepEqual(value.keys, [{ before: { column_number: 1, header: 'ID' }, after: { column_number: 2, header: 'Item' } }])
})
test('composite keys are exact and collision-free, with duplicate/blank headers and literal whitespace', async () => {
  const value = await comparison(',,Text\n"a,b",c,x\na,"b,c",y\n 01 ,z,old', ',,Text\na,"b,c",Y\n"a,b",c,x\n01,z,new', { beforeKeys: [1, 2], afterKeys: [1, 2], beforeColumns: [3], afterColumns: [3] })
  assert.equal(value.unchanged, 1); assert.deepEqual(value.records.map(row => row.kind), ['changed', 'removed', 'added'])
  assert.deepEqual(value.records[0].key, ['a', 'b,c'])
  assert.deepEqual(positions(' 1, 3 '), [1, 3])
  for (const invalid of ['', '0', '1,1', '1,,2', '-1', '1.5', '1e2', '1,', '9007199254740992']) assert.throws(() => positions(invalid))
})
test('blank, repeated and ambiguous keys reject instead of matching by position', async () => {
  const map = { beforeKeys: [1], afterKeys: [1], beforeColumns: [2], afterColumns: [2] }
  await assert.rejects(comparison('ID,V\na,x\na,y', 'ID,V\na,z', map), /before records 2 and 3/)
  await assert.rejects(comparison('ID,V\na,x', 'ID,V\na,z\na,q', map), /after records 2 and 3/)
  await assert.rejects(comparison('ID,V\n ,x', 'ID,V\na,z', map), /blank key/)
  await assert.rejects(comparison(oldText, newText, { ...mapping, afterKeys: [99] }), /does not exist/)
  await assert.rejects(comparison(oldText, newText, { ...mapping, afterKeys: [2, 1] }), /same nonzero/)
  await assert.rejects(comparison(oldText, newText, { ...mapping, beforeColumns: [2, 2] }), /distinct/)
})
test('unchanged tables and pure reorder produce no selectable changes', async () => {
  const value = await comparison('ID,V\na,one\nb,two', 'ID,V\nb,two\na,one', { beforeKeys: [1], afterKeys: [1], beforeColumns: [2], afterColumns: [2] })
  assert.equal(value.unchanged, 2); assert.deepEqual(value.records, [])
  await assert.rejects(new ChangeSelection(value).packet(context(), 'Explain', 1024), /at least one/)
})
test('selection preserves both original identities and only chosen keys/cells, order, literal Unicode and formulas', async () => {
  const selection = await selected(); selection.move(selection.ids[2], -1); selection.remove(selection.ids[2])
  const packet = await selection.packet(context(), 'Explain', 1024)
  assert.deepEqual(packet.records.map(row => row.key), [['001'], ['004']]); assert.equal(packet.records[1].after.cells[1], '=SUM(A1)')
  assert.equal(packet.before_source.sha256, await sha256(oldText)); assert.equal(packet.after_source.sha256, await sha256(newText))
  assert.doesNotMatch(JSON.stringify(packet), /old-private|private-2|private-3|new-private|private-4|changed-private/)
  assert.equal(packet.authority_granted, false); assert.equal(packet.accepted_knowledge, false)
  assert.throws(() => selection.add(selection.ids[0]), /Already/); assert.throws(() => selection.add('missing'))
  const pending = selection.packet(context(), 'Captured', 1024); selection.ids.reverse(); assert.deepEqual((await pending).records[0].key, ['001'])
})
test('byte, row and column bounds refuse without silent truncation', async () => {
  const map = { beforeKeys: [1], afterKeys: [1], beforeColumns: [2], afterColumns: [2] }
  const changes = await comparison('ID,V\n' + Array.from({ length: 51 }, (_, i) => i + ',old').join('\n'), 'ID,V\n' + Array.from({ length: 51 }, (_, i) => i + ',new').join('\n'), map)
  const selection = new ChangeSelection(changes); for (const row of changes.records.slice(0, 50)) selection.add(row.id); assert.throws(() => selection.add(changes.records[50].id), /50/)
  const unicode = new ChangeSelection(await comparison('ID,V\na,x', 'ID,V\na,' + '€'.repeat(342), map)); unicode.add(unicode.comparison.records[0].id)
  await assert.rejects(unicode.packet(context(), 'Explain', 1024), /budget/); assert.equal((await unicode.packet(context(), 'Explain', 2048)).records.length, 1)
  for (const budget of [1023, 16385, 1024.5, NaN]) await assert.rejects(unicode.packet(context(), 'Explain', budget))
  const wide = Array.from({ length: 33 }, (_, i) => 'h' + i).join(',') + '\n' + Array(33).fill('v').join(',')
  await assert.rejects(comparison(wide, wide, { beforeKeys: [33], afterKeys: [33], beforeColumns: Array.from({ length: 32 }, (_, i) => i + 1), afterColumns: Array.from({ length: 32 }, (_, i) => i + 1) }), /32 distinct/)
})
test('packet validation rejects tampered identities, keys, positions, claims and kinds', async () => {
  const packet = await (await selected()).packet(context(), 'Explain', 2048)
  for (const change of [p => { p.records[0].after.cells[0] = 'tamper' }, p => { p.authority_granted = true }, p => { p.before_source.name = '/private/file' }, p => { p.after_source.sha256 = 'bad' }, p => { p.extra = true }, p => { p.records[0].kind = 'added' }, p => { p.records[0].before.record_number = 1 }, p => { p.records.push(p.records[0]) }, p => { p.records[0].key = [''] }, p => { p.key_columns[0].after.column_number = 99 }, p => { p.selected_bytes++ }, p => { p.records[0].after.cells = ['short'] }]) { const next = structuredClone(packet); change(next); await assert.rejects(validateChangesPacket(next)) }
})
test('composing/reapplying/removing changes preserves surrounding task and existing selected-table packet', async () => {
  const comparison = await selected(), packet = await comparison.packet(context(), 'Explain', 2048)
  const table = new TableSelection(comparison.comparison.before); table.add('columns', 1); table.add('records', 2)
  const oldPacket = await table.packet(context(), 'Single table', 1024), original = await composeTable('  Work\r\n', oldPacket)
  const first = await composeChanges(original, packet), suffix = '\n Do not publish. \r\n', second = await composeChanges(first + suffix, { ...packet, purpose: 'Revised reason' })
  assert.equal(second.split(BEGIN).length, 2); assert.ok(second.endsWith(suffix)); assert.deepEqual(await readTablePacket(second), oldPacket)
  assert.equal((await readChangesPacket(second)).purpose, 'Revised reason')
  const removed = await removeChanges(second); assert.equal(await readChangesPacket(removed), null); assert.deepEqual(await readTablePacket(removed), oldPacket)
  for (const invalid of ['Task' + BEGIN, 'Task' + END, first + first, 'Task' + BEGIN + '{}' + END]) await assert.rejects(composeChanges(invalid, packet))
})
test('mounted production journey imports, maps, compares, inspects, selects, reorders and applies exact task input', async () => {
  const ui = surface(); await prepare(ui); const original = ui.composer.value
  assert.match(ui.get('counts').textContent, /1 added · 1 removed · 1 changed · 1 unchanged/)
  const added = ui.binding.selection.ids[2]; ui.get('selected').value = added; await ui.get('up').fire('click')
  ui.get('kind').value = 'changed'; await ui.get('kind').fire('change'); assert.equal(ui.get('record').children.length, 2); assert.equal(ui.binding.selection.ids.length, 3)
  await ui.get('preview').fire('click'); assert.equal(ui.get('apply').disabled, false); assert.equal(ui.composer.value, original); assert.doesNotMatch(ui.get('preview-text').textContent, /old-private|new-private/)
  await ui.get('apply').fire('click'); const packet = await readChangesPacket(ui.composer.value); assert.deepEqual(packet.records.map(row => row.kind), ['changed', 'added', 'removed']); assert.equal(ui.inputEvents, 1)
  await ui.get('apply').fire('click'); assert.equal(ui.inputEvents, 1)
  await ui.get('detach').fire('click'); assert.equal(await readChangesPacket(ui.composer.value), null); assert.equal(ui.binding.selection.ids.length, 3)
  const draft = ui.composer.value; await ui.get('clear').fire('click'); assert.equal(ui.binding.selection, null); assert.equal(ui.composer.value, draft); ui.binding.dispose()
})
test('mapping edits invalidate comparison; other authoring and composer events invalidate previews', async () => {
  const ui = surface(); await prepare(ui)
  for (const key of ['purpose', 'budget']) { await ui.get('preview').fire('click'); await ui.get(key).fire('input'); await ui.get('apply').fire('click'); assert.equal(ui.inputEvents, 0) }
  for (const key of ['kind', 'record', 'selected']) { await ui.get('preview').fire('click'); await ui.get(key).fire('change'); await ui.get('apply').fire('click'); assert.equal(ui.inputEvents, 0) }
  await ui.get('preview').fire('click'); ui.composer.value += 'New restriction'; await ui.composer.fire('input'); await ui.get('apply').fire('click'); assert.equal(ui.inputEvents, 1)
  await ui.get('before-keys').fire('input'); assert.equal(ui.binding.selection, null); await ui.get('preview').fire('click'); assert.match(ui.get('status').textContent, /Compare the current/); ui.binding.dispose()
})
test('invalid replacement preserves snapshots and selections; valid replacement requires new comparison', async () => {
  const ui = surface(); await prepare(ui); const selection = ui.binding.selection, before = ui.binding.before, draft = ui.composer.value
  await importUI(ui, 'before', 'ID,V\na'); assert.equal(ui.binding.before, before); assert.equal(ui.binding.selection, selection); assert.equal(ui.composer.value, draft)
  await importUI(ui, 'after', 'ID,V\na,b'); assert.equal(ui.binding.selection, null); assert.equal(ui.binding.before, before); assert.equal(ui.composer.value, draft); ui.binding.dispose()
})
test('late file reads cannot win after cancel, newer input, close, unmount, dispose, context or access changes', async () => {
  for (const action of ['cancel', 'new-file', 'close', 'unmount', 'dispose', 'context', 'access']) {
    const ui = surface(); await prepare(ui); const old = ui.binding.before, draft = ui.composer.value; let release
    ui.get('before-file').files = [{ ...file('slow.csv', oldText), arrayBuffer: () => new Promise(resolve => { release = async () => resolve(await file('slow.csv', oldText).arrayBuffer()) }) }]
    const pending = ui.get('before-file').fire('change')
    if (action === 'cancel') await ui.get('cancel').fire('click')
    if (action === 'new-file') await importUI(ui, 'before', 'ID,V\na,b', 'new.csv')
    if (action === 'close') { ui.root.open = false; await ui.root.fire('toggle') }
    if (action === 'unmount') ui.root.isConnected = false
    if (action === 'dispose') ui.binding.dispose()
    if (action === 'context') { ui.context.textContent = JSON.stringify({ ...context(), session_key: 'B' }); ui.binding.sync(); ui.context.textContent = JSON.stringify(context()); ui.binding.sync() }
    if (action === 'access') { ui.changeAccess(); ui.binding.sync() }
    await release(); await pending; assert.equal(ui.composer.value, draft)
    if (action === 'new-file') assert.equal(ui.binding.before.source.name, 'new.csv')
    else if (['context', 'access'].includes(action)) assert.equal(ui.binding.before, null)
    else assert.equal(ui.binding.before, old)
    ui.binding.dispose()
  }
})
test('cancelled hashes and newer composer text never apply a stale preview', async () => {
  const ui = surface(); await prepare(ui); const draft = ui.composer.value
  const pending = ui.get('preview').fire('click'); await ui.get('cancel').fire('click'); await pending; await ui.get('apply').fire('click'); assert.equal(ui.composer.value, draft)
  const next = ui.get('preview').fire('click'); ui.composer.value += ' New restriction'; await ui.composer.fire('input'); await next; await ui.get('apply').fire('click'); assert.equal(ui.composer.value, draft + ' New restriction'); ui.binding.dispose()
})
test('all bounded changed records remain inspectable; no first-page cutoff', async () => {
  const ui = surface(); await importUI(ui, 'before', 'ID,V\n' + Array.from({ length: 2000 }, (_, i) => i + ',old').join('\n')); await importUI(ui, 'after', 'ID,V\n' + Array.from({ length: 2000 }, (_, i) => i + ',new').join('\n'))
  for (const side of ['before', 'after']) { ui.get(side + '-keys').value = '1'; ui.get(side + '-columns').value = '2' }
  await ui.get('compare').fire('click'); assert.equal(ui.get('record').children.length, 2001); ui.get('record').value = '["1999"]'; await ui.get('add').fire('click'); assert.deepEqual(ui.binding.selection.ids, ['["1999"]']); ui.binding.dispose()
})
test('mount/install/dispose tracks replacement Work anchors without duplicate controls', () => {
  const prior = globalThis.MutationObserver; let update, disconnected = false
  globalThis.MutationObserver = class { constructor(fn) { update = fn } observe() {} disconnect() { disconnected = true } }
  try { const ui = surface(false), stop = installTableChanges(ui.document), first = ui.get('panel'); assert.ok(first); update(); assert.equal(ui.get('panel'), first); const anchor = ui.document.createElement('details'); anchor.id = 'claw-procedure-panel'; anchor.setConnected(true); update(); assert.notEqual(ui.get('panel'), first); assert.equal(first.isConnected, false); stop(); assert.equal(disconnected, true); assert.equal(ui.get('panel'), null) } finally { globalThis.MutationObserver = prior }
})
test('document ID lookup cannot see detached descendants while the CSV-change surface is constructed', () => {
  const ui = surface(false), detached = ui.document.createElement('details'), child = ui.document.createElement('select'); child.id = 'detached-kind'; detached.appendChild(child)
  assert.equal(ui.document.getElementById('detached-kind'), null)
  const root = mountTableChanges(ui.document, ui.anchor)
  assert.equal(root.isConnected, true); assert.equal(ui.get('kind').children.length, 4); assert.equal(ui.get('kind').value, 'all')
  root.remove(); assert.equal(ui.get('kind'), null)
})
test('portable example files produce the documented selected change packet through production', async () => {
  const before = await readFile(new URL('../../docs/examples/table-changes/before.csv', import.meta.url), 'utf8'), after = await readFile(new URL('../../docs/examples/table-changes/after.csv', import.meta.url), 'utf8')
  const selection = new ChangeSelection(await comparison(before, after)); for (const row of selection.comparison.records) selection.add(row.id)
  const packet = await selection.packet(context(), 'Explain selected changes; omit private owner notes.', 2048)
  assert.deepEqual(packet.records.map(row => row.kind), ['changed', 'removed', 'added']); assert.doesNotMatch(JSON.stringify(packet), /private-owner/)
  console.log('TABLE_CHANGES_SAMPLE=' + JSON.stringify(packet))
})
