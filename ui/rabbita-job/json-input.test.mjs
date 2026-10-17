import test from 'node:test'
import assert from 'node:assert/strict'
import { webcrypto } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { parseJSONSource, readJSONFile, JSONSelection, nodeId, matchingJSONNodes, validateJSONPacket, readJSONPacket, composeJSON, removeJSON, BEGIN, END } from './json-input.js'
import { mountJSONInput, bindJSONInput, installJSONInput } from './json-input-controls.js'
import { mountTableInput, bindTableInput } from './table-input-controls.js'
import { readTablePacket } from './table-input.js'
import { sha256 } from './book-outcome.js'
if (!globalThis.crypto) globalThis.crypto = webcrypto
const sample = '\ufeff{\r\n  "items": [{"id":9007199254740993,"ready":true,"note":"a\\nb","private":"omitted"},{"id":-0,"ready":false}],\r\n  "a/b~c":{"":null},"decimal":1.2300e+400,"escaped":"\\u20ac"\r\n}\r\n'
const file = (name = 'tasks.json', content = sample) => { const bytes = new TextEncoder().encode(content); return { name, size: bytes.byteLength, arrayBuffer: async () => bytes.buffer } }
const context = () => ({ session_key: 'thread-A', cwd: '/work', cwd_override: '' })
async function selection() { const value = new JSONSelection(await readJSONFile(file(), 'json')); value.add(nodeId(1, '/items/0/id')); value.add(nodeId(1, '/items/1/ready')); return value }
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
  ctx.textContent = JSON.stringify(context()); composer.value = 'Explain the selected observations.\n'
  const root = bind ? mountJSONInput(document, anchor) : null, get = key => document.getElementById('claw-json-' + key)
  let epoch = 0, inputEvents = 0; composer.addEventListener('input', () => inputEvents++)
  const ui = { document, anchor, context: ctx, composer, root, get, get inputEvents() { return inputEvents }, changeAccess() { epoch++ }, transport: () => ({ base: () => 'http://fixture', epoch: () => epoch }) }
  if (bind) ui.binding = bindJSONInput(document, ui)
  return ui
}
async function importUI(ui, value = file()) { ui.get('file').files = [value]; await ui.get('file').fire('change') }
async function addUI(ui, pointer, document = 1) { ui.get('node').value = nodeId(document, pointer); await ui.get('node').fire('change'); await ui.get('add').fire('click') }
async function selectUI(ui) { await importUI(ui); await addUI(ui, '/items/0/id'); await addUI(ui, '/items/1/ready'); ui.get('purpose').value = 'Explain these selected observations without inferring missing context'; await ui.get('purpose').fire('input') }

test('mounted ordered fields preview every record cell and apply exact record-major values in a flat v1 packet', async () => {
  const ui = surface(), source = await readFile(new URL('../../docs/examples/json-projection/record-fields.json', import.meta.url), 'utf8')
  await importUI(ui, file('records.json', source)); const draft = ui.composer.value
  await addUI(ui, '/items/2/id')
  ui.get('node').value = nodeId(1, '/items'); await ui.get('node').fire('change')
  ui.get('projection-pointer').value = '["/id","/a~1b~0"]'; await ui.get('projection-pointer').fire('input')
  ui.get('cohort-type').value = 'boolean'; ui.get('cohort-pointer').value = '/ready'; ui.get('cohort-value').value = 'true'
  await ui.get('projection-preview').fire('click'); const projected = JSON.parse(ui.get('projection-text').textContent)
  assert.deepEqual(projected.fields, ['/id', '/a~1b~0']); assert.equal(projected.records, 3); assert.equal(projected.excluded_records, 1); assert.equal(projected.missing, 1)
  assert.deepEqual(projected.rows.map(row => row.record_pointer), ['/items/0', '/items/1', '/items/2'])
  assert.deepEqual(projected.rows.map(row => row.cells.map(cell => cell.state)), [['present', 'null'], ['present', 'missing'], ['present', 'present']])
  assert.equal(projected.rows[0].cells[1].json_text, 'null'); assert.equal(projected.rows[1].cells[1].present, false); assert.equal(Object.hasOwn(projected.rows[1].cells[1], 'json_text'), false)
  assert.equal(projected.rows[0].cells[0].json_text, '9007199254740993123'); assert.match(projected.packet_shape, /flat/)
  assert.deepEqual(ui.binding.selection.ids, [nodeId(1, '/items/2/id')]); assert.equal(ui.composer.value, draft); assert.equal(ui.inputEvents, 0)
  await ui.get('projection-add').fire('click')
  assert.deepEqual(ui.binding.selection.selected().map(value => value.json_text), ['1.2300e+400', '9007199254740993123', 'null', '-0', '"\\u0061"'])
  await ui.get('projection-preview').fire('click'); await ui.get('projection-add').fire('click'); assert.equal(ui.binding.selection.ids.length, 5)
  assert.equal(ui.composer.value, draft); ui.get('purpose').value = 'Compare exact selected record fields'; await ui.get('purpose').fire('input')
  await ui.get('preview').fire('click'); assert.equal(ui.composer.value, draft); await ui.get('apply').fire('click')
  const packet = await readJSONPacket(ui.composer.value)
  assert.equal(packet.contract_version, 'moonclaw.selected-json.v1'); assert.equal(Object.hasOwn(packet, 'records'), false)
  assert.deepEqual(packet.values.map(value => [value.document, value.pointer, value.json_text]), [[1, '/items/2/id', '1.2300e+400'], [1, '/items/0/id', '9007199254740993123'], [1, '/items/0/a~1b~0', 'null'], [1, '/items/1/id', '-0'], [1, '/items/2/a~1b~0', '"\\u0061"']])
  assert.equal(packet.authority_granted, false); assert.equal(packet.accepted_knowledge, false); assert.equal(packet.source_freshness_verified, false)
  assert.doesNotMatch(ui.composer.value, /private|not selected|ready/); assert.equal(ui.inputEvents, 1); ui.binding.dispose()
})
test('mounted JSONL fields preserve document identity, chosen field order, escaped keys and missing/null gaps', async () => {
  const ui = surface(); ui.get('format').value = 'jsonl'
  await importUI(ui, file('records.jsonl', '{"id":9007199254740993,"line\\nbreak":null}\n{"id":2,"line\\nbreak":"\\u20ac"}\nnull\n{"id":3}'))
  ui.get('projection-mode').value = 'jsonl'; ui.get('projection-pointer').value = '["/line\\nbreak","/id"]'
  await ui.get('projection-preview').fire('click'); const projected = JSON.parse(ui.get('projection-text').textContent)
  assert.equal(projected.missing, 3); assert.deepEqual(projected.rows[2].cells.map(cell => cell.state), ['missing', 'missing'])
  assert.equal(projected.rows[1].cells[0].pointer, '/line\nbreak')
  await ui.get('projection-add').fire('click'); ui.get('purpose').value = 'Compare supplied fields'; await ui.get('preview').fire('click'); await ui.get('apply').fire('click')
  const packet = await readJSONPacket(ui.composer.value)
  assert.deepEqual(packet.values.map(value => [value.document, value.json_text]), [[1, 'null'], [1, '9007199254740993'], [2, '"\\u20ac"'], [2, '2'], [4, '3']])
  assert.deepEqual(packet.values.map(value => value.start_line), [1, 1, 2, 2, 4]); ui.binding.dispose()
})
test('mounted multi-field duplicate/overlap, count and byte failures keep the entire selection and draft', async () => {
  for (const pointers of ['["/id","/id"]', '["/id","/id/x"]', '["","/id"]', '["/absent","/absent"]', '["/bad~2","/id"]']) {
    const ui = surface(); await importUI(ui); const draft = ui.composer.value; await addUI(ui, '/decimal'); const before = [...ui.binding.selection.ids]
    ui.get('node').value = nodeId(1, '/items'); ui.get('projection-pointer').value = pointers
    await ui.get('projection-preview').fire('click'); assert.equal(ui.get('projection-add').disabled, true)
    await ui.get('projection-add').fire('click'); assert.deepEqual(ui.binding.selection.ids, before); assert.equal(ui.composer.value, draft); ui.binding.dispose()
  }
  for (const kind of ['count', 'bytes', 'parent']) {
    const ui = surface(), source = kind === 'count' ? '[' + Array(17).fill('{"id":1,"note":null}').join(',') + ']' : '[{"id":1,"note":"' + 'é'.repeat(510) + '"},{"id":2,"note":null}]'
    await importUI(ui, file('bounded.json', source)); await addUI(ui, kind === 'parent' ? '/1' : '/1/id'); const prior = [...ui.binding.selection.ids], draft = ui.composer.value
    ui.get('node').value = nodeId(1, ''); ui.get('projection-pointer').value = '["/id","/note"]'; ui.get('budget').value = '1024'
    await ui.get('projection-preview').fire('click'); await ui.get('projection-add').fire('click')
    assert.match(ui.get('status').textContent, kind === 'count' ? /32 selected/ : kind === 'bytes' ? /byte budget/ : /overlaps/)
    assert.deepEqual(ui.binding.selection.ids, prior); assert.equal(ui.composer.value, draft); assert.equal(ui.inputEvents, 0); ui.binding.dispose()
  }
})
test('mounted multi-field previews refuse stale field, selection, composer, import and scope changes', async () => {
  for (const change of ['field', 'silent-field', 'field-reorder', 'silent-draft', 'draft-event', 'silent-budget', 'silent-purpose', 'selection', 'import', 'bad-import', 'context', 'access', 'cancel', 'close']) {
    const ui = surface(); await importUI(ui); ui.get('node').value = nodeId(1, '/items'); ui.get('projection-pointer').value = '["/id","/ready"]'
    await ui.get('projection-preview').fire('click')
    if (change === 'field') await ui.get('projection-pointer').fire('input')
    if (change === 'silent-field') ui.get('projection-pointer').value = '["/id","/note"]'
    if (change === 'field-reorder') ui.get('projection-pointer').value = '["/ready","/id"]'
    if (change === 'silent-draft') ui.composer.value += ' Keep restrictions.'
    if (change === 'draft-event') await ui.composer.fire('input')
    if (change === 'silent-budget') ui.get('budget').value = '1024'
    if (change === 'silent-purpose') ui.get('purpose').value = 'New purpose'
    if (change === 'selection') ui.binding.selection.add(nodeId(1, '/decimal'))
    if (change === 'import') await importUI(ui, file('new.json', '[]'))
    if (change === 'bad-import') await importUI(ui, file('bad.json', '{'))
    if (change === 'context') ui.context.textContent = JSON.stringify({ ...context(), session_key: 'other' })
    if (change === 'access') ui.changeAccess()
    if (change === 'cancel') await ui.get('cancel').fire('click')
    if (change === 'close') { ui.root.open = false; await ui.root.fire('toggle') }
    const draft = ui.composer.value; await ui.get('projection-add').fire('click')
    assert.equal(ui.binding.selection?.ids.length || 0, change === 'selection' ? 1 : 0, change); assert.equal(ui.composer.value, draft, change); ui.binding.dispose()
  }
})
test('mounted task packet preview refuses silent ordered-field, budget, purpose and selection edits', async () => {
  for (const change of ['fields', 'budget', 'purpose', 'selection']) {
    const ui = surface(); await selectUI(ui); const draft = ui.composer.value; await ui.get('preview').fire('click')
    if (change === 'fields') ui.get('projection-pointer').value = '["/id","/ready"]'
    if (change === 'budget') ui.get('budget').value = '1024'
    if (change === 'purpose') ui.get('purpose').value = 'Changed reason'
    if (change === 'selection') ui.binding.selection.add(nodeId(1, '/decimal'))
    await ui.get('apply').fire('click'); assert.equal(ui.composer.value, draft, change); assert.equal(ui.inputEvents, 0); ui.binding.dispose()
  }
})

test('mounted typed cohort narrows forty records and applies only chosen exact fields to ordinary draft', async () => {
  const ui = surface(), source = '[' + Array.from({ length: 40 }, (_, i) => '{"status":' + (i % 10 === 0 ? '"\\u0072eady"' : '"later"') + ',"id":' + (i === 0 ? '9007199254740993123' : i) + ',"private":"omitted"}').join(',') + ']'
  await importUI(ui, file('cohort.json', source)); ui.get('node').value = nodeId(1, ''); await ui.get('node').fire('change')
  ui.get('projection-pointer').value = '/id'; await ui.get('projection-pointer').fire('input'); await ui.get('projection-preview').fire('click'); await ui.get('projection-add').fire('click')
  assert.match(ui.get('status').textContent, /32 selected/); assert.deepEqual(ui.binding.selection.ids, [])
  ui.get('cohort-type').value = 'string'; await ui.get('cohort-type').fire('change'); ui.get('cohort-pointer').value = '/status'; await ui.get('cohort-pointer').fire('input'); ui.get('cohort-value').value = '"ready"'; await ui.get('cohort-value').fire('input')
  await ui.get('projection-preview').fire('click'); const preview = JSON.parse(ui.get('projection-text').textContent)
  assert.equal(preview.total_records, 40); assert.equal(preview.records, 4); assert.equal(preview.excluded_records, 36); assert.deepEqual(preview.rows.map(row => row.record_pointer), ['/0', '/10', '/20', '/30'])
  await ui.get('projection-add').fire('click'); ui.get('purpose').value = 'Inspect ready identifiers'; await ui.get('purpose').fire('input'); await ui.get('preview').fire('click'); await ui.get('apply').fire('click')
  const packet = await readJSONPacket(ui.composer.value); assert.deepEqual(packet.values.map(value => value.json_text), ['9007199254740993123', '10', '20', '30']); assert.doesNotMatch(ui.composer.value, /private|omitted|status/); assert.equal(packet.authority_granted, false)
  await ui.get('clear').fire('click'); assert.equal(ui.get('cohort-type').value, 'all'); assert.equal(ui.get('cohort-value').value, ''); ui.binding.dispose()
})
test('mounted cohort fields invalidate previews, including silent changes, and reject wrong types', async () => {
  for (const key of ['cohort-type', 'cohort-pointer', 'cohort-value']) for (const silent of [false, true]) {
    const ui = surface(); await importUI(ui); ui.get('node').value = nodeId(1, '/items'); await ui.get('node').fire('change'); ui.get('projection-pointer').value = '/id'
    ui.get('cohort-type').value = 'boolean'; ui.get('cohort-pointer').value = '/ready'; ui.get('cohort-value').value = 'true'; await ui.get('projection-preview').fire('click')
    ui.get(key).value = key === 'cohort-type' ? 'null' : key === 'cohort-pointer' ? '/id' : 'false'
    if (!silent) await ui.get(key).fire(key === 'cohort-type' ? 'change' : 'input')
    await ui.get('projection-add').fire('click'); assert.deepEqual(ui.binding.selection.ids, [], key); ui.binding.dispose()
  }
  const ui = surface(); await importUI(ui); ui.get('node').value = nodeId(1, '/items'); ui.get('cohort-type').value = 'number'; ui.get('cohort-value').value = '"1"'; await ui.get('projection-preview').fire('click'); assert.match(ui.get('status').textContent, /matching the chosen type/); assert.equal(ui.get('projection-add').disabled, true); ui.binding.dispose()
})

test('mounted array projection previews missing fields then places exact selected fields in the ordinary task', async () => {
  const source = await readFile(new URL('../../docs/examples/json-projection/work-items.json', import.meta.url), 'utf8')
  const ui = surface(); await importUI(ui, file('work-items.json', source)); const before = ui.composer.value
  ui.get('node').value = nodeId(1, '/items'); await ui.get('node').fire('change')
  ui.get('projection-pointer').value = '/details/amount'; await ui.get('projection-pointer').fire('input')
  await ui.get('projection-preview').fire('click')
  const preview = JSON.parse(ui.get('projection-text').textContent)
  assert.equal(preview.records, 4); assert.equal(preview.matched, 3); assert.equal(preview.missing, 1)
  assert.deepEqual(ui.binding.selection.ids, []); assert.equal(ui.composer.value, before)
  await ui.get('projection-add').fire('click'); assert.equal(ui.binding.selection.ids.length, 3)
  await ui.get('projection-add').fire('click'); assert.equal(ui.binding.selection.ids.length, 3)
  ui.get('purpose').value = 'Compare the supplied amounts, retaining missing context'; await ui.get('purpose').fire('input')
  await ui.get('preview').fire('click'); await ui.get('apply').fire('click')
  const packet = await readJSONPacket(ui.composer.value)
  assert.deepEqual(packet.values.map(value => value.json_text), ['1.2300e+02', '9007199254740993123', 'null'])
  assert.doesNotMatch(ui.composer.value, /private-owner/); assert.equal(ui.inputEvents, 1); assert.equal(packet.authority_granted, false)
  ui.binding.dispose()
})
test('mounted JSONL projection handles missing fields and blank relative pointer explicitly', async () => {
  const ui = surface(); ui.get('format').value = 'jsonl'; await ui.get('format').fire('change')
  await importUI(ui, file('items.jsonl', '{"id":1}\nnull\n{"id":2}'))
  ui.get('projection-mode').value = 'jsonl'; await ui.get('projection-mode').fire('change')
  ui.get('projection-pointer').value = '/id'; await ui.get('projection-pointer').fire('input')
  await ui.get('projection-preview').fire('click'); await ui.get('projection-add').fire('click')
  assert.deepEqual(ui.binding.selection.ids, [nodeId(1, '/id'), nodeId(3, '/id')])
  ui.get('projection-pointer').value = ''; await ui.get('projection-pointer').fire('input'); await ui.get('projection-preview').fire('click'); await ui.get('projection-add').fire('click')
  assert.match(ui.get('status').textContent, /overlaps/); assert.equal(ui.binding.selection.ids.length, 2); ui.binding.dispose()
})
test('projected cohorts cannot apply after changed fields, draft, import, context, cancel or close', async () => {
  for (const change of ['field-input', 'silent-field', 'query', 'draft', 'import', 'context', 'access', 'cancel', 'close']) {
    const ui = surface(); await importUI(ui); ui.get('node').value = nodeId(1, '/items'); await ui.get('node').fire('change')
    ui.get('cohort-type').value = 'boolean'; ui.get('cohort-pointer').value = '/ready'; ui.get('cohort-value').value = 'true'
    ui.get('projection-pointer').value = '/id'; await ui.get('projection-pointer').fire('input'); await ui.get('projection-preview').fire('click')
    if (change === 'field-input') await ui.get('projection-pointer').fire('input')
    if (change === 'silent-field') ui.get('projection-pointer').value = '/ready'
    if (change === 'query') await ui.get('query').fire('input')
    if (change === 'draft') await ui.composer.fire('input')
    if (change === 'import') await importUI(ui, file('new.json', '[]'))
    if (change === 'context') { ui.context.textContent = JSON.stringify({ ...context(), session_key: 'B' }); ui.binding.sync() }
    if (change === 'access') { ui.changeAccess(); ui.binding.sync() }
    if (change === 'cancel') await ui.get('cancel').fire('click')
    if (change === 'close') { ui.root.open = false; await ui.root.fire('toggle') }
    await ui.get('projection-add').fire('click'); assert.equal(ui.binding.selection?.ids.length || 0, 0, change)
    ui.binding.dispose()
  }
})

test('exact JSON selection retains large numeric lexemes, escapes, types, physical spans and RFC6901 paths', async () => {
  const snapshot = await readJSONFile(file(), 'json'), find = pointer => snapshot.nodes.find(value => value.pointer === pointer)
  assert.equal(snapshot.source.sha256, await sha256(sample)); assert.equal(snapshot.documents, 1)
  assert.equal(find('/items/0/id').json_text, '9007199254740993'); assert.equal(find('/items/1/id').json_text, '-0')
  assert.equal(find('/decimal').json_text, '1.2300e+400'); assert.equal(find('/escaped').json_text, '"\\u20ac"')
  assert.equal(find('/a~1b~0c/').json_text, 'null'); assert.equal(find('/a~1b~0c/').type, 'null')
  assert.equal(find('/items/0/note').json_text, '"a\\nb"'); assert.equal(find('/items/0/id').start_line, 2)
  assert.equal(find('').start_line, 1); assert.equal(find('').end_line, 4); assert.ok(Object.isFrozen(find('')))
  assert.equal(parseJSONSource('"😀"').nodes[0].type, 'string'); assert.equal(parseJSONSource('[]').nodes[0].type, 'array')
})
test('JSON Lines gives each physical document a separate root and never guesses the format', () => {
  const lines = '\ufeff{"id":1}\r\n{"id":2}\nnull\n'
  const result = parseJSONSource(lines, 'jsonl'); assert.equal(result.documents, 3)
  assert.deepEqual(result.nodes.filter(value => value.pointer === '').map(value => [value.document, value.start_line, value.json_text]), [[1, 1, '{"id":1}'], [2, 2, '{"id":2}'], [3, 3, 'null']])
  assert.throws(() => parseJSONSource(lines, 'json'), /Unexpected content/)
  for (const invalid of ['\n{}', '{}\n\n{}', '{}\n\n', '{\n"id":1\n}', '']) assert.throws(() => parseJSONSource(invalid, 'jsonl'))
})
test('strict grammar rejects ambiguity, lossy Unicode and non-JSON syntax without partial results', () => {
  for (const bad of ['', ' ', '{} {}', '{"x":1,"x":2}', '{"a":1,"\\u0061":2}', '[1,]', '{"x":1,}', '{x:1}', 'NaN', 'Infinity', '01', '+1', '1.', '1e', 'truefalse', '"\\ud800"', '"\udfff"', '"a\nb"', '"\\q"', '/*c*/{}', '{"a":}', '[', '"a', '{}\0']) assert.throws(() => parseJSONSource(bad), bad)
  assert.equal(parseJSONSource('{"__proto__":{"polluted":true},"constructor":0}').nodes.length, 4)
  assert.equal({}.polluted, undefined)
})
test('depth, node, document, path and byte bounds reject instead of truncating', () => {
  assert.equal(parseJSONSource('['.repeat(32) + '0' + ']'.repeat(32)).nodes.length, 33)
  assert.throws(() => parseJSONSource('['.repeat(33) + '0' + ']'.repeat(33)), /32 levels/)
  assert.equal(parseJSONSource('[' + Array(4095).fill('0').join(',') + ']').nodes.length, 4096)
  assert.throws(() => parseJSONSource('[' + Array(4096).fill('0').join(',') + ']'), /4096/)
  assert.equal(parseJSONSource(Array(1000).fill('null').join('\n'), 'jsonl').documents, 1000)
  assert.throws(() => parseJSONSource(Array(1001).fill('null').join('\n'), 'jsonl'), /1000/)
  assert.throws(() => parseJSONSource('{"' + 'a'.repeat(4096) + '":0}'), /pointer/)
  assert.throws(() => parseJSONSource('"' + 'x'.repeat(262144) + '"'), /256 KiB/)
})
test('file validation rejects invalid UTF8, changed lengths and non-basename input before adoption', async () => {
  let read = false
  await assert.rejects(readJSONFile({ name: 'large.json', size: 262145, arrayBuffer() { read = true } }, 'json')); assert.equal(read, false)
  await assert.rejects(readJSONFile({ ...file(), size: 1 }, 'json'), /changed/)
  await assert.rejects(readJSONFile({ name: 'bad.json', size: 1, arrayBuffer: async () => Uint8Array.of(255).buffer }, 'json'), /UTF-8/)
  await assert.rejects(readJSONFile(file('../data.json'), 'json'), /basename/)
})
test('ordered selection omits unselected siblings and parent-child overlap without conflating JSONL documents', async () => {
  const selected = await selection(); assert.throws(() => selected.add(nodeId(1, '/items')), /overlap/)
  assert.throws(() => selected.add(nodeId(1, '/items/0/id')), /Already/); selected.move(nodeId(1, '/items/1/ready'), -1)
  const packet = await selected.packet(context(), 'Review only these', 1024)
  assert.deepEqual(packet.values.map(value => value.json_text), ['false', '9007199254740993']); assert.doesNotMatch(JSON.stringify(packet), /omitted|private/)
  assert.equal(packet.authority_granted, false); assert.equal(packet.accepted_knowledge, false)
  selected.remove(nodeId(1, '/items/1/ready')); assert.equal(selected.ids.length, 1)
  const jsonl = new JSONSelection(await readJSONFile(file('runs.jsonl', '{"x":0}\n{"x":1}'), 'jsonl'))
  jsonl.add(nodeId(2, '')); jsonl.add(nodeId(1, '/x')); assert.equal((await jsonl.packet(context(), 'Compare', 1024)).values.length, 2)
})
test('selection packet validates fields, claimed types/spans, hashes, budget and context', async () => {
  const packet = await (await selection()).packet(context(), 'Reason', 1024)
  for (const change of [p => { p.extra = true }, p => { p.authority_granted = true }, p => { p.source.format = 'yaml' }, p => { p.values[0].type = 'string' }, p => { p.values[0].json_text = '0' }, p => { p.values[0].pointer = '/bad~2' }, p => { p.values[0].end_line++ }, p => { p.values[0].document = 2 }, p => { p.selected_bytes++ }, p => { p.value_budget_bytes = 100 }, p => { p.session_key = '' }]) { const next = structuredClone(packet); change(next); await assert.rejects(validateJSONPacket(next)) }
  const oversized = new JSONSelection(await readJSONFile(file('large.json', '{"text":"' + 'x'.repeat(2000) + '"}'), 'json')); oversized.add(nodeId(1, '/text')); await assert.rejects(oversized.packet(context(), 'Reason', 1024), /budget/)
})
test('compose, replace and detach preserve task whitespace and unrelated blocks; malformed owned blocks stay untouched', async () => {
  const packet = await (await selection()).packet(context(), 'Reason', 1024), draft = '  Task\r\n[Other packet]\n', first = await composeJSON(draft, packet), suffix = '\r\n Later restriction '
  const second = await composeJSON(first + suffix, { ...packet, purpose: 'New reason' })
  assert.equal(second.split(BEGIN).length, 2); assert.ok(second.startsWith(draft)); assert.ok(second.endsWith(suffix)); assert.equal((await readJSONPacket(second)).purpose, 'New reason')
  assert.equal(await removeJSON(second), second.slice(0, second.indexOf(BEGIN)) + suffix)
  for (const bad of [draft + BEGIN, draft + END, first + first, draft + BEGIN + '{}' + END]) await assert.rejects(composeJSON(bad, packet))
  await assert.rejects(composeJSON(' ', packet), /Describe/); await assert.rejects(composeJSON('x'.repeat(131072), packet), /128 KiB/)
})
test('detach restores the exact original task and repeated attach-detach never accumulates owned notices', async () => {
  const packet = await (await selection()).packet(context(), 'Reason', 1024)
  const original = '  User task\r\n[Unrelated packet]\nKeep this literal user-authored source-data warning.  '
  let draft = original
  for (let cycle = 0; cycle < 3; cycle++) {
    draft = await composeJSON(draft, packet)
    assert.equal(draft.split('Selected JSON values below').length, 2)
    assert.ok(draft.indexOf(BEGIN) < draft.indexOf('Selected JSON values below'))
    draft = await removeJSON(draft); assert.equal(draft, original)
  }
  const ui = surface(); await selectUI(ui); const before = ui.composer.value
  await ui.get('preview').fire('click'); await ui.get('apply').fire('click'); await ui.get('detach').fire('click')
  assert.equal(ui.composer.value, before); ui.binding.dispose()
})
test('production mounted controls complete sample import, search, inspect, select, reorder, preview, apply, edit and detach', async () => {
  const source = await readFile(new URL('../../docs/examples/json-input/work-items.json', import.meta.url), 'utf8')
  const ui = surface(); await importUI(ui, file('work-items.json', source)); const before = ui.composer.value
  assert.equal(ui.binding.selection.ids.length, 0)
  ui.get('query').value = 'uncertain'; await ui.get('query').fire('input'); await addUI(ui, '/items/1/status'); assert.match(ui.get('node-text').textContent, /"uncertain"/)
  ui.get('query').value = '9007199254740993'; await ui.get('query').fire('input'); await addUI(ui, '/items/0/id')
  ui.get('selected').value = nodeId(1, '/items/0/id'); await ui.get('up').fire('click')
  ui.get('purpose').value = 'Keep the exact identifier and describe the reported status'; await ui.get('purpose').fire('input')
  await ui.get('preview').fire('click'); assert.equal(ui.get('apply').disabled, false); assert.equal(ui.composer.value, before)
  assert.doesNotMatch(ui.get('preview-text').textContent, /private-owner/); await ui.get('apply').fire('click'); assert.equal(ui.inputEvents, 1)
  assert.deepEqual((await readJSONPacket(ui.composer.value)).values.map(value => [value.pointer, value.json_text]), [['/items/0/id', '9007199254740993'], ['/items/1/status', '"uncertain"']])
  await ui.get('apply').fire('click'); assert.equal(ui.inputEvents, 1)
  ui.get('selected').value = nodeId(1, '/items/0/id'); await ui.get('selected').fire('change'); assert.equal(ui.get('query').value, ''); await ui.get('down').fire('click')
  await ui.get('preview').fire('click'); await ui.get('apply').fire('click'); assert.equal((await readJSONPacket(ui.composer.value)).values[0].pointer, '/items/1/status')
  await ui.get('remove').fire('click'); assert.equal(ui.binding.selection.ids.length, 1)
  await ui.get('detach').fire('click'); assert.equal(await readJSONPacket(ui.composer.value), null); assert.ok(ui.composer.value.startsWith(before))
  const after = ui.composer.value; await ui.get('clear').fire('click'); assert.equal(ui.binding.selection, null); assert.equal(ui.composer.value, after); ui.binding.dispose()
})
test('format selection opens JSON Lines and can select whole independent documents', async () => {
  const ui = surface(); ui.get('format').value = 'jsonl'; await ui.get('format').fire('change'); await importUI(ui, file('runs.jsonl', '{"ready":false}\n{"ready":true}'))
  await addUI(ui, '', 2); ui.get('purpose').value = 'Inspect the second observation'; await ui.get('purpose').fire('input'); await ui.get('preview').fire('click'); await ui.get('apply').fire('click')
  assert.equal((await readJSONPacket(ui.composer.value)).values[0].document, 2)
  ui.get('format').value = 'json'; await ui.get('format').fire('change'); assert.equal(ui.binding.selection.snapshot.format, 'jsonl'); assert.match(ui.get('status').textContent, /next import/); ui.binding.dispose()
})
test('every authoring, filtering and composer edit invalidates preview, even edit and restore', async () => {
  const ui = surface(); await selectUI(ui)
  for (const key of ['purpose', 'budget', 'query', 'cohort-pointer', 'cohort-value']) { await ui.get('preview').fire('click'); await ui.get(key).fire('input'); await ui.get('apply').fire('click'); assert.equal(ui.inputEvents, 0) }
  for (const key of ['node', 'selected', 'format', 'cohort-type']) { await ui.get('preview').fire('click'); await ui.get(key).fire('change'); await ui.get('apply').fire('click'); assert.equal(ui.inputEvents, 0) }
  await ui.get('preview').fire('click'); await ui.composer.fire('input'); await ui.get('apply').fire('click'); assert.equal(ui.inputEvents, 1); ui.binding.dispose()
})
test('invalid replacement preserves previous selection and draft; valid replacement starts unselected', async () => {
  const ui = surface(); await selectUI(ui); const old = ui.binding.selection, draft = ui.composer.value
  await importUI(ui, file('bad.json', '{"a":1,"a":2}')); assert.equal(ui.binding.selection, old); assert.equal(ui.composer.value, draft); assert.match(ui.get('status').textContent, /Duplicate/)
  await importUI(ui, file('new.json', '{}')); assert.equal(ui.binding.selection.snapshot.source.name, 'new.json'); assert.deepEqual(ui.binding.selection.ids, []); assert.equal(ui.composer.value, draft); ui.binding.dispose()
})
test('late file reads cannot survive cancel, newer import, close, detach, context or gateway changes', async () => {
  for (const action of ['cancel', 'new-file', 'close', 'unmount', 'dispose', 'context', 'access', 'format']) {
    const ui = surface(); await selectUI(ui); const draft = ui.composer.value, old = ui.binding.selection; let release
    ui.get('file').files = [{ ...file('slow.json'), arrayBuffer: () => new Promise(resolve => { release = async () => resolve(await file().arrayBuffer()) }) }]
    const pending = ui.get('file').fire('change')
    if (action === 'cancel') await ui.get('cancel').fire('click')
    if (action === 'new-file') await importUI(ui, file('new.json', '{}'))
    if (action === 'close') { ui.root.open = false; await ui.root.fire('toggle') }
    if (action === 'unmount') ui.root.isConnected = false
    if (action === 'dispose') ui.binding.dispose()
    if (action === 'context') { ui.context.textContent = JSON.stringify({ ...context(), session_key: 'B' }); ui.binding.sync(); ui.context.textContent = JSON.stringify(context()); ui.binding.sync() }
    if (action === 'access') { ui.changeAccess(); ui.binding.sync() }
    if (action === 'format') { ui.get('format').value = 'jsonl'; await ui.get('format').fire('change') }
    await release(); await pending; assert.equal(ui.composer.value, draft)
    if (action === 'new-file') assert.equal(ui.binding.selection.snapshot.source.name, 'new.json')
    else if (['context', 'access'].includes(action)) assert.equal(ui.binding.selection, null)
    else assert.equal(ui.binding.selection, old)
    ui.binding.dispose()
  }
})
test('preview interruption or a newer task restriction cannot apply an obsolete packet', async () => {
  const ui = surface(); await selectUI(ui); const draft = ui.composer.value
  const pending = ui.get('preview').fire('click'); await ui.get('cancel').fire('click'); await pending; await ui.get('apply').fire('click'); assert.equal(ui.composer.value, draft)
  const next = ui.get('preview').fire('click'); ui.composer.value += ' Keep source caveats.'; await ui.composer.fire('input'); await next; await ui.get('apply').fire('click'); assert.equal(ui.composer.value, draft + ' Keep source caveats.'); ui.binding.dispose()
})
test('JSON and CSV mounted controllers coexist and invalidate previews via the real composer event', async () => {
  const ui = surface(); await selectUI(ui); mountTableInput(ui.document, ui.anchor); const table = bindTableInput(ui.document, ui), get = key => ui.document.getElementById('claw-table-' + key)
  get('file').files = [file('table.csv', 'Name\nexample')]; await get('file').fire('change'); get('record').value = '2'; await get('add-record').fire('click'); get('column').value = '1'; await get('add-column').fire('click'); get('purpose').value = 'Extra context'
  await ui.get('preview').fire('click'); await get('preview').fire('click'); await get('apply').fire('click'); assert.equal(ui.get('apply').disabled, true)
  const csv = await readTablePacket(ui.composer.value); assert.ok(csv); await ui.get('preview').fire('click'); await ui.get('apply').fire('click'); assert.deepEqual(await readTablePacket(ui.composer.value), csv)
  await ui.get('detach').fire('click'); assert.deepEqual(await readTablePacket(ui.composer.value), csv); assert.equal(await readJSONPacket(ui.composer.value), null); table.dispose(); ui.binding.dispose()
})
test('all bounded nodes remain reachable and selected paths survive an empty filter', async () => {
  const ui = surface(); await importUI(ui, file('many.json', '[' + Array(4095).fill('0').join(',') + ']'))
  assert.equal(ui.get('node').children.length, 4097); await addUI(ui, '/4094'); ui.get('query').value = 'no-match'; await ui.get('query').fire('input')
  assert.equal(ui.get('node').children.length, 1); assert.deepEqual(ui.binding.selection.ids, [nodeId(1, '/4094')]); assert.equal(matchingJSONNodes(ui.binding.selection.snapshot, '/4094').length, 1); ui.binding.dispose()
})
test('install and dispose follows Work anchors without retaining detached controls', () => {
  const previous = globalThis.MutationObserver; let update, disconnected = false
  globalThis.MutationObserver = class { constructor(fn) { update = fn } observe() {} disconnect() { disconnected = true } }
  try { const ui = surface(false), stop = installJSONInput(ui.document), first = ui.get('panel'); assert.ok(first); update(); assert.equal(ui.get('panel'), first)
    const anchor = ui.document.createElement('details'); anchor.id = 'claw-procedure-panel'; update(); assert.notEqual(ui.get('panel'), first); assert.equal(first.isConnected, false); stop(); assert.equal(disconnected, true); assert.equal(ui.get('panel'), null)
  } finally { globalThis.MutationObserver = previous }
})
