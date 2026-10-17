import test from 'node:test'
import assert from 'node:assert/strict'
import { webcrypto } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { parseCSV, readTableFile, TableSelection, columnLabel, matchingRecords, validateTablePacket, readTablePacket, composeTable, removeTable, BEGIN, END } from './table-input.js'
import { mountTableInput, bindTableInput, installTableInput } from './table-input-controls.js'
import { sha256 } from './book-outcome.js'
import { byteLength, readPacket } from './source-brief.js'
import { mountSourceBrief, bindSourceBrief } from './source-brief-controls.js'
import { sourceKey } from './retained-sources.js'
if (!globalThis.crypto) globalThis.crypto = webcrypto
const csv = '\ufeffItem,Note,Note,,Private\r\n001,"First line\r\nsecond, line","say ""hello""",=SUM(A1),private-A\r\n002,Later,€,  spaced  ,private-B\r\n003,Ready,😀,,private-C'
const file = (name = 'table.csv', text = csv) => { const bytes = new TextEncoder().encode(text); return { name, size: bytes.byteLength, arrayBuffer: async () => bytes.buffer } }
const context = () => ({ session_key: 'thread-A', cwd: '/work', cwd_override: '' })
async function selected(text = csv) { const selection = new TableSelection(await readTableFile(file('table.csv', text))); selection.add('records', 3); selection.add('records', 2); selection.add('columns', 2); selection.add('columns', 1); return selection }
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
function surface(bind = true) {
  const document = { nodes: new Map(), getElementById(id) { return this.nodes.get(id) || null }, createElement(tag) { return new Node(this, tag) } }
  const add = id => { const node = document.createElement('div'); node.id = id; return node }
  const anchor = add('claw-procedure-panel'), ctx = add('claw-procedure-context'), composer = add('claw-procedure-composer')
  ctx.textContent = JSON.stringify(context()); composer.value = 'Compare selected work items. Do not execute formulas.\n'
  const root = bind ? mountTableInput(document, anchor) : null, get = key => document.getElementById('claw-table-' + key)
  let epoch = 0, inputEvents = 0; composer.addEventListener('input', () => inputEvents++)
  const ui = { document, anchor, context: ctx, composer, root, get, get inputEvents() { return inputEvents }, changeAccess() { epoch++ }, transport: () => ({ base: () => 'http://fixture', epoch: () => epoch }) }
  if (bind) ui.binding = bindTableInput(document, ui)
  return ui
}
async function importUI(ui, value = file()) { ui.get('file').files = [value]; await ui.get('file').fire('change') }
async function addUI(ui, kind, id) { ui.get(kind).value = String(id); await ui.get(kind).fire('change'); await ui.get('add-' + kind).fire('click') }
async function selectUI(ui) { await importUI(ui); await addUI(ui, 'column', 2); await addUI(ui, 'column', 1); await addUI(ui, 'record', 3); await addUI(ui, 'record', 2); ui.get('purpose').value = 'Compare the exact selected notes in this order'; await ui.get('purpose').fire('input') }

test('column filters combine literal exact/contains/empty predicates without coercion or incidental other-column matches', async () => {
  const table = await readTableFile(file('filter.csv', 'ID,Status,Owner,Note,Note\n001,waiting,Alex,ready,\n002,ready,Alex,waiting, \n003,waiting,Sam,ready,\n004,Waiting,Alex,waiting,\n005,waiting,Alex,"a\nb",'))
  const filters = [{ column: 2, operator: 'equals', value: 'waiting' }, { column: 3, operator: 'equals', value: 'Alex' }]
  assert.deepEqual(matchingRecords(table, '', filters).map(row => row.record_number), [2, 6])
  assert.deepEqual(matchingRecords(table, 'A\nB', filters).map(row => row.record_number), [6])
  assert.deepEqual(matchingRecords(table, '', [{ column: 5, operator: 'blank', value: 'ignored' }]).map(row => row.record_number), [2, 4, 5, 6])
  assert.deepEqual(matchingRecords(table, '', [{ column: 4, operator: 'contains', value: 'a\nb' }]).map(row => row.record_number), [6])
  assert.equal(matchingRecords(table, '', [{ column: 1, operator: 'equals', value: '1' }]).length, 0)
  assert.throws(() => matchingRecords(table, '', [...Array(9)].map(() => filters[0])), /eight/)
  assert.throws(() => matchingRecords(table, '', [{ column: 0, operator: 'equals', value: '' }]), /column/)
})

test('bulk selection appends new matching IDs in source order and fails atomically above the existing bound', async () => {
  const selection = new TableSelection(await readTableFile(file('many.csv', 'ID,Status\n' + Array.from({ length: 51 }, (_, i) => `${i},${i < 49 ? 'waiting' : 'done'}`).join('\n'))))
  selection.add('records', 50)
  assert.equal(selection.addMatching('', [{ column: 2, operator: 'equals', value: 'waiting' }]), 48)
  assert.deepEqual(selection.records, [50, ...Array.from({ length: 48 }, (_, i) => i + 2)])
  const before = [...selection.records]
  assert.throws(() => selection.addMatching('', []), /Nothing was added/)
  assert.deepEqual(selection.records, before)
  assert.equal(selection.addMatching('no match', []), 0)
  assert.equal(selection.addMatching('', [{ column: 2, operator: 'equals', value: 'waiting' }]), 0)
})

test('operator imports fixture, filters two columns, inspects matches, bulk-selects, and applies exact ordinary task input', async () => {
  const ui = surface(), text = await readFile(new URL('../../docs/examples/table-filter/work-items.csv', import.meta.url), 'utf8')
  await importUI(ui, file('work-items.csv', text))
  for (const [column, value] of [[2, 'waiting'], [3, 'Alex']]) {
    ui.get('filter-column').value = String(column); await ui.get('filter-column').fire('change')
    ui.get('filter-value').value = value; await ui.get('filter-value').fire('input')
    await ui.get('add-filter').fire('click')
  }
  assert.match(ui.get('matches').textContent, /^2 of 4/)
  const inspected = JSON.parse(ui.get('matching-text').textContent)
  assert.deepEqual(inspected.matching_records.map(row => row.record_number), [2, 5])
  assert.deepEqual(ui.binding.selection.records, [])
  await ui.get('add-matches').fire('click')
  await addUI(ui, 'column', 1); await addUI(ui, 'column', 4)
  ui.get('purpose').value = 'Summarize the waiting tasks assigned to Alex'; await ui.get('purpose').fire('input')
  await ui.get('preview').fire('click'); assert.equal(ui.get('apply').disabled, false)
  await ui.get('apply').fire('click')
  const packet = await readTablePacket(ui.composer.value)
  assert.deepEqual(packet.records.map(row => row.record_number), [2, 5])
  assert.deepEqual(packet.columns.map(column => column.column_number), [1, 4])
  assert.equal(packet.authority_granted, false)
  assert.doesNotMatch(JSON.stringify(packet.records), /Alex|Sam/)
  const draft = ui.composer.value
  await ui.get('clear-filters').fire('click'); assert.deepEqual(ui.binding.selection.records, [2, 5]); assert.equal(ui.composer.value, draft)
  await ui.get('preview').fire('click')
  ui.get('filter-value').value = 'new'; await ui.get('filter-value').fire('input'); assert.equal(ui.get('apply').disabled, true)
  ui.context.textContent = JSON.stringify({ ...context(), session_key: 'other' }); ui.binding.sync()
  assert.equal(ui.get('selected-filter').children.length, 1); assert.equal(ui.binding.selection, null)
})

test('filter removal and rejected bulk action preserve selected records and composer', async () => {
  const ui = surface(); await importUI(ui, file('many.csv', 'ID,Status\n' + Array.from({ length: 51 }, (_, i) => `${i},waiting`).join('\n')))
  await addUI(ui, 'record', 3)
  const draft = ui.composer.value
  await ui.get('add-matches').fire('click')
  assert.match(ui.get('status').textContent, /Nothing was added/); assert.deepEqual(ui.binding.selection.records, [3]); assert.equal(ui.composer.value, draft)
  ui.get('filter-column').value = '1'; ui.get('filter-value').value = '1'; await ui.get('add-filter').fire('click')
  assert.match(ui.get('matches').textContent, /^1 of 51/)
  ui.get('selected-filter').value = '1'; await ui.get('remove-filter').fire('click')
  assert.match(ui.get('matches').textContent, /^51 of 51/)
  assert.deepEqual(ui.binding.selection.records, [3])
})

test('CSV decodes exact cells, escaped quotes, multiline CRLF and no-final-newline while retaining logical/physical positions', async () => {
  const table = await readTableFile(file())
  assert.equal(table.source.sha256, await sha256(csv)); assert.equal(table.source.bytes, byteLength(csv))
  assert.deepEqual(table.header.cells, ['Item', 'Note', 'Note', '', 'Private'])
  assert.deepEqual(table.records.map(row => [row.record_number, row.start_line, row.end_line]), [[2, 2, 3], [3, 4, 4], [4, 5, 5]])
  assert.deepEqual(table.records[0].cells, ['001', 'First line\r\nsecond, line', 'say "hello"', '=SUM(A1)', 'private-A'])
  assert.equal(table.records[1].cells[3], '  spaced  '); assert.equal(table.records[2].cells[2], '😀')
  assert.equal(columnLabel(table, 2), 'Column 3: Note'); assert.equal(columnLabel(table, 3), 'Column 4: (blank header)')
  assert.ok(Object.isFrozen(table.records[0].cells)); assert.deepEqual(matchingRecords(table, 'SECOND, LINE').map(row => row.record_number), [2])
})
test('CSV accepts empty cells and quoted headers; trailing newline is not an extra record', () => {
  assert.deepEqual(parseCSV('"head\nline",\na,\n').header.cells, ['head\nline', ''])
  assert.deepEqual(parseCSV('"head\nline",\na,\n').records[0], { record_number: 2, start_line: 3, end_line: 3, cells: ['a', ''] })
  assert.equal(parseCSV('header\n\n').records[0].cells[0], '')
  assert.equal(parseCSV('header\n"a\rb"').records[0].cells[0], 'a\rb')
})
test('malformed dialects and unequal widths reject atomically rather than guessing or dropping cells', () => {
  for (const bad of ['', '\ufeff', 'header\n', 'a,b\nx', 'a\nx,y', 'a\n"unclosed', 'a\nx"y', 'a\n"x" y', 'a\rx', 'a\nx\0y', 'a\n\ud800']) assert.throws(() => parseCSV(bad))
  assert.throws(() => parseCSV(Array(129).fill('h').join(',') + '\n' + Array(129).fill('v').join(',')), /128/)
  assert.equal(parseCSV('h\n' + Array(2000).fill('v').join('\n')).records.length, 2000)
  assert.throws(() => parseCSV('h\n' + Array(2001).fill('v').join('\n')), /2000/)
  assert.throws(() => parseCSV('h\n' + 'x'.repeat(262144)), /256 KiB/)
})
test('file reading rejects oversize, changed lengths, invalid UTF-8, binary content and non-basename input', async () => {
  let called = false
  await assert.rejects(readTableFile({ name: 'big.csv', size: 262145, arrayBuffer() { called = true } }), /256 KiB/); assert.equal(called, false)
  await assert.rejects(readTableFile({ ...file(), size: 2 }), /changed/)
  await assert.rejects(readTableFile({ name: 'bad.csv', size: 1, arrayBuffer: async () => Uint8Array.of(255).buffer }), /UTF-8/)
  await assert.rejects(readTableFile(file('bad.csv', 'a\nx\0')), /NUL/)
  await assert.rejects(readTableFile(file('../table.csv')), /basename/)
})
test('ordered row/column selection preserves values and original identity while omitting private columns', async () => {
  const selection = await selected(), packet = await selection.packet(context(), 'Compare these notes', 1024)
  assert.deepEqual(packet.columns, [{ column_number: 2, header: 'Note' }, { column_number: 1, header: 'Item' }])
  assert.deepEqual(packet.records[0], { record_number: 3, start_line: 4, end_line: 4, cells: ['Later', '002'] })
  assert.deepEqual(packet.records[1].cells, ['First line\r\nsecond, line', '001'])
  assert.doesNotMatch(JSON.stringify(packet), /private-A|private-B|private-C|SUM\(A1\)/)
  assert.equal(packet.selected_bytes, byteLength('NoteItemLater002First line\r\nsecond, line001'))
  assert.equal(packet.authority_granted, false); assert.equal(packet.source_freshness_verified, false)
  selection.move('records', 2, -1); selection.move('columns', 1, -1); selection.remove('records', 3)
  const next = await selection.packet(context(), 'Revised reason', 2048)
  assert.deepEqual(next.records[0].cells, ['001', 'First line\r\nsecond, line']); assert.equal(next.records.length, 1)
  assert.throws(() => selection.add('records', 2), /Already/); assert.throws(() => selection.add('columns', 1), /Already/)
  assert.throws(() => selection.add('records', 1)); assert.throws(() => selection.add('columns', 0))
})
test('selection limits and UTF-8 budget are enforced with no silent truncation', async () => {
  const selection = new TableSelection(await readTableFile(file('big.csv', Array(33).fill('h').join(',') + '\n' + Array(51).fill(Array(33).fill('v').join(',')).join('\n'))))
  for (let i = 1; i <= 32; i++) selection.add('columns', i)
  assert.throws(() => selection.add('columns', 33), /32/)
  for (let i = 2; i <= 51; i++) selection.add('records', i)
  assert.throws(() => selection.add('records', 52), /50/)
  await assert.rejects(selection.packet(context(), 'Reason', 1024), /budget/)
  assert.equal((await selection.packet(context(), 'Reason', 2048)).records.length, 50)
  for (const budget of [1, 1023, 16385, 1024.5, NaN]) await assert.rejects(selection.packet(context(), 'Reason', budget))
  await assert.rejects(selection.packet(context(), '', 2048))
  selection.records = []; await assert.rejects(selection.packet(context(), 'Reason', 2048), /at least one/)
  const unicode = new TableSelection(await readTableFile(file('unicode.csv', 'h\n' + '€'.repeat(342)))); unicode.add('records', 2); unicode.add('columns', 1)
  await assert.rejects(unicode.packet(context(), 'Reason', 1024), /budget/)
})
test('packet snapshot is stable across edits during hashing; changed cell/identity/claims fail validation', async () => {
  const selection = await selected(), pending = selection.packet(context(), 'Reason', 2048); selection.records.reverse(); selection.columns.reverse()
  const packet = await pending; assert.equal(packet.records[0].record_number, 3); assert.equal(packet.columns[0].column_number, 2)
  for (const change of [p => { p.authority_granted = true }, p => { p.source_freshness_verified = true }, p => { p.accepted_knowledge = true }, p => { p.token = 'no' }, p => { p.records[0].cells[0] = 'changed' }, p => { p.columns[0].header = 'changed' }, p => { p.records.push(p.records[0]) }, p => { p.columns.push(p.columns[0]) }, p => { p.source.sha256 = 'bad' }, p => { p.source.name = '/private/name' }, p => { p.records[0].record_number = 1 }, p => { p.records[0].start_line = 0 }, p => { p.selected_bytes++ }, p => { delete p.purpose }]) {
    const next = structuredClone(packet); change(next); await assert.rejects(validateTablePacket(next))
  }
})
test('compose/reapply/remove preserves surrounding text and other packets exactly, and blocks ambiguous owned blocks', async () => {
  const selection = await selected(), packet = await selection.packet(context(), 'Reason', 2048)
  const draft = '  Task\r\n[other packet]\r\n', first = await composeTable(draft, packet), suffix = '\n  Later restriction  \r\n'
  const second = await composeTable(first + suffix, { ...packet, purpose: 'Changed reason' })
  assert.equal(second.split(BEGIN).length, 2); assert.ok(second.startsWith(draft)); assert.ok(second.endsWith(suffix))
  assert.equal((await readTablePacket(second)).purpose, 'Changed reason')
  const removed = await removeTable(second); assert.equal(removed, second.slice(0, second.indexOf(BEGIN)) + suffix); assert.equal(await readTablePacket(removed), null)
  for (const bad of [draft + BEGIN, draft + END, first + first, draft + BEGIN + '{}' + END]) await assert.rejects(composeTable(bad, packet))
  await assert.rejects(composeTable(' ', packet), /Describe/); await assert.rejects(composeTable('x'.repeat(131072), packet), /128 KiB/)
})
test('production controls complete compact real CSV→inspect/filter→order/edit→preview/apply→revise→remove journey', async () => {
  const csvSample = await readFile(new URL('../../docs/examples/table-input/work-items.csv', import.meta.url), 'utf8'), expected = JSON.parse(await readFile(new URL('../../docs/examples/table-input/expected-selection.json', import.meta.url), 'utf8'))
  const ui = surface(); await importUI(ui, file('work-items.csv', csvSample)); const draft = ui.composer.value
  assert.equal(ui.binding.selection.records.length, 0); assert.equal(ui.binding.selection.columns.length, 0)
  ui.get('query').value = 'waiting'; await ui.get('query').fire('input'); await addUI(ui, 'record', 3)
  assert.match(ui.get('record-text').textContent, /Record|record/); assert.match(ui.get('record-text').textContent, /private-owner-b/)
  ui.get('query').value = 'multiline'; await ui.get('query').fire('input'); await addUI(ui, 'record', 2)
  await addUI(ui, 'column', 3); await addUI(ui, 'column', 1)
  ui.get('selected-column').value = '1'; await ui.get('column-up').fire('click')
  ui.get('purpose').value = 'Draft a short status summary for these two records. Keep their task order.'; await ui.get('purpose').fire('input')
  assert.equal(ui.composer.value, draft); await ui.get('preview').fire('click'); assert.equal(ui.get('apply').disabled, false)
  assert.doesNotMatch(ui.get('preview-text').textContent, /private-owner/); await ui.get('apply').fire('click')
  const packet = await readTablePacket(ui.composer.value); assert.deepEqual(packet.columns, expected.columns); assert.deepEqual(packet.records, expected.records); assert.equal(ui.inputEvents, 1)
  await ui.get('apply').fire('click'); assert.equal(ui.inputEvents, 1)
  ui.get('selected-record').value = '2'; await ui.get('selected-record').fire('change'); assert.equal(ui.get('query').value, ''); await ui.get('record-up').fire('click')
  ui.get('purpose').value = 'Lead with the multiline record'; await ui.get('purpose').fire('input'); await ui.get('preview').fire('click'); await ui.get('apply').fire('click')
  assert.equal((await readTablePacket(ui.composer.value)).records[0].record_number, 2); assert.equal(ui.composer.value.split(BEGIN).length, 2)
  await ui.get('remove-record').fire('click'); assert.equal(ui.binding.selection.records.length, 1)
  await ui.get('detach').fire('click'); assert.equal(await readTablePacket(ui.composer.value), null); assert.ok(ui.composer.value.startsWith(draft)); assert.equal(ui.binding.selection.records.length, 1)
  const after = ui.composer.value; await ui.get('clear').fire('click'); assert.equal(ui.binding.selection, null); assert.equal(ui.composer.value, after); ui.binding.dispose()
})
test('every authoring or composer change invalidates preview, including edit-and-restore and duplicate selections', async () => {
  const ui = surface(); await selectUI(ui)
  for (const key of ['purpose', 'budget', 'query']) { await ui.get('preview').fire('click'); await ui.get(key).fire('input'); await ui.get('apply').fire('click'); assert.equal(ui.inputEvents, 0) }
  for (const key of ['record', 'column', 'selected-record', 'selected-column']) { await ui.get('preview').fire('click'); await ui.get(key).fire('change'); await ui.get('apply').fire('click'); assert.equal(ui.inputEvents, 0) }
  await ui.get('preview').fire('click'); await ui.composer.fire('input'); await ui.get('apply').fire('click'); assert.equal(ui.inputEvents, 1)
  await addUI(ui, 'record', 2); assert.match(ui.get('status').textContent, /Already/); assert.deepEqual(ui.binding.selection.records, [3, 2])
  ui.binding.dispose()
})
test('invalid import preserves an existing selection and applied draft; a valid replacement clears selection only after success', async () => {
  const ui = surface(); await selectUI(ui); await ui.get('preview').fire('click'); await ui.get('apply').fire('click'); const draft = ui.composer.value, selection = ui.binding.selection
  await importUI(ui, file('invalid.csv', 'a,b\nx')); assert.equal(ui.binding.selection, selection); assert.equal(ui.composer.value, draft); assert.match(ui.get('status').textContent, /column count/)
  await importUI(ui, file('next.csv', 'New\nvalue')); assert.equal(ui.binding.selection.table.source.name, 'next.csv'); assert.deepEqual(ui.binding.selection.records, []); assert.equal(ui.composer.value, draft)
  ui.binding.dispose()
})
test('table and focused-source production controllers coexist and invalidate each other through the ordinary composer event', async () => {
  const ui = surface(); await selectUI(ui)
  mountSourceBrief(ui.document, ui.anchor); const sources = bindSourceBrief(ui.document, ui), get = key => ui.document.getElementById('claw-sources-' + key)
  get('files').files = [file('context.txt', 'Independent note\nKeep the chosen record order.\n')]; await get('files').fire('change')
  get('source').value = sourceKey({ name: 'context.txt' }); await get('source').fire('change'); get('start').value = '2'; get('end').value = '2'; get('purpose').value = 'Ordering context'; await get('add').fire('click')
  await ui.get('preview').fire('click'); await get('preview').fire('click'); await get('apply').fire('click')
  assert.equal(ui.get('apply').disabled, true); assert.equal(await readTablePacket(ui.composer.value), null)
  const sourcePacket = await readPacket(ui.composer.value); assert.equal(sourcePacket.excerpts[0].content_utf8, 'Keep the chosen record order.\n')
  await get('preview').fire('click'); await ui.get('preview').fire('click'); await ui.get('apply').fire('click'); assert.equal(get('apply').disabled, true)
  assert.deepEqual(await readPacket(ui.composer.value), sourcePacket); assert.equal((await readTablePacket(ui.composer.value)).records[0].record_number, 3)
  await ui.get('detach').fire('click'); assert.deepEqual(await readPacket(ui.composer.value), sourcePacket); assert.equal(await readTablePacket(ui.composer.value), null)
  sources.dispose(); ui.binding.dispose()
})
test('cancel/new-file/close/unmount/dispose/context A→B→A/access changes discard late file reads', async () => {
  for (const action of ['cancel', 'new-file', 'close', 'unmount', 'dispose', 'context', 'access']) {
    const ui = surface(); await selectUI(ui); const draft = ui.composer.value, original = ui.binding.selection; let release
    ui.get('file').files = [{ ...file('slow.csv'), arrayBuffer: () => new Promise(resolve => { release = async () => resolve(await file().arrayBuffer()) }) }]
    const pending = ui.get('file').fire('change')
    if (action === 'cancel') await ui.get('cancel').fire('click')
    if (action === 'new-file') await importUI(ui, file('new.csv', 'New\nvalue'))
    if (action === 'close') { ui.root.open = false; await ui.root.fire('toggle') }
    if (action === 'unmount') ui.root.isConnected = false
    if (action === 'dispose') ui.binding.dispose()
    if (action === 'context') { ui.context.textContent = JSON.stringify({ ...context(), session_key: 'B' }); ui.binding.sync(); ui.context.textContent = JSON.stringify(context()); ui.binding.sync() }
    if (action === 'access') { ui.changeAccess(); ui.binding.sync() }
    await release(); await pending; assert.equal(ui.composer.value, draft)
    if (action === 'new-file') assert.equal(ui.binding.selection.table.source.name, 'new.csv')
    else if (['context', 'access'].includes(action)) assert.equal(ui.binding.selection, null)
    else assert.equal(ui.binding.selection, original)
    ui.binding.dispose()
  }
})
test('filtering keeps stable original IDs and every bounded matching record is reachable', async () => {
  const ui = surface(); await importUI(ui, file('many.csv', 'Item\n' + Array.from({ length: 2000 }, (_, i) => 'Value ' + (i + 1)).join('\n')))
  assert.equal(ui.get('record').children.length, 2001); await addUI(ui, 'record', 2001); assert.deepEqual(ui.binding.selection.records, [2001])
  ui.get('query').value = 'no match'; await ui.get('query').fire('input'); assert.equal(ui.get('record').children.length, 1); assert.deepEqual(ui.binding.selection.records, [2001]); ui.binding.dispose()
})
test('preview cancellation and newer draft updates cannot apply asynchronously prepared cells', async () => {
  const ui = surface(); await selectUI(ui); const before = ui.composer.value
  const preparing = ui.get('preview').fire('click'); await ui.get('cancel').fire('click'); await preparing; await ui.get('apply').fire('click'); assert.equal(ui.composer.value, before)
  const preparingAgain = ui.get('preview').fire('click'); ui.composer.value += ' New restriction.'; await ui.composer.fire('input'); await preparingAgain; await ui.get('apply').fire('click'); assert.equal(ui.composer.value, before + ' New restriction.'); ui.binding.dispose()
})
test('mount/install/dispose follows replaced Work anchors without duplicating controllers', () => {
  const previous = globalThis.MutationObserver; let update, disconnected = false
  globalThis.MutationObserver = class { constructor(fn) { update = fn } observe() {} disconnect() { disconnected = true } }
  try {
    const ui = surface(false), stop = installTableInput(ui.document), first = ui.get('panel'); assert.ok(first); update(); assert.equal(ui.get('panel'), first)
    const secondAnchor = ui.document.createElement('details'); secondAnchor.id = 'claw-procedure-panel'; update(); assert.notEqual(ui.get('panel'), first); assert.equal(first.isConnected, false)
    stop(); assert.equal(disconnected, true); assert.equal(ui.get('panel'), null)
  } finally { globalThis.MutationObserver = previous }
})
