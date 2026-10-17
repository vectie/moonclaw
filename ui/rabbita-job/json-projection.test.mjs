import test from 'node:test'
import assert from 'node:assert/strict'
import { parseJSONSource, JSONSelection, nodeId } from './json-input.js'
import { parseJSONProjectionFields, projectJSONRecordFields, projectJSONRecords, addJSONProjection } from './json-projection.js'
import { scalarKey } from './json-cohort.js'

test('ordered record fields retain exact identity, null and missing cells, and append record-major', () => {
  const snapshot = parseJSONSource('{"rows":[{"id":9007199254740993123,"a/b~":null},{"id":-0},{"id":1.2300e+400,"a/b~":"\\u0061"}]}')
  const fields = ['/a~1b~0', '/id'], projection = projectJSONRecordFields(snapshot, 'array', nodeId(1, '/rows'), fields)
  fields.reverse(); assert.deepEqual(projection.fields, ['/a~1b~0', '/id'])
  assert.deepEqual(projection.rows.map(row => row.cells.map(cell => cell.state)), [['null', 'present'], ['missing', 'present'], ['present', 'present']])
  assert.deepEqual(projection.values.map(value => value.json_text), ['null', '9007199254740993123', '-0', '"\\u0061"', '1.2300e+400'])
  assert.equal(projection.missing, 1); assert.equal(projection.rows[1].cells[0].pointer, '/rows/1/a~1b~0')
  assert.equal(projection.rows[1].cells[0].value, null); assert.equal(projection.rows[0].cells[0].value.type, 'null')
  assert.ok(Object.isFrozen(projection.rows[0].cells)); assert.ok(Object.isFrozen(projection.rows[0].cells[0]))
  const selection = new JSONSelection(snapshot); selection.add(nodeId(1, '/rows/2/id'))
  assert.equal(addJSONProjection(selection, projection), 4)
  assert.deepEqual(selection.selected().map(value => value.json_text), ['1.2300e+400', 'null', '9007199254740993123', '-0', '"\\u0061"'])
  assert.equal(addJSONProjection(selection, projection), 0)
})
test('multi-field JSONL projection shares typed cohort semantics without leaking predicate or excluded data', () => {
  const snapshot = parseJSONSource('{"keep":1e0,"id":9007199254740993,"n":null}\n{"keep":"1","id":2,"n":false}\n{"keep":1.0,"id":3}\n{"id":4,"n":true}', 'jsonl')
  const projection = projectJSONRecordFields(snapshot, 'jsonl', '', ['/id', '/n'], { pointer: '/keep', type: 'number', json_text: '1' })
  assert.equal(projection.total, 4); assert.equal(projection.excluded, 2); assert.equal(projection.predicateMissing, 1)
  assert.deepEqual(projection.rows.map(row => [row.document, row.record_pointer]), [[1, ''], [3, '']])
  assert.deepEqual(projection.values.map(value => [value.document, value.pointer, value.json_text]), [[1, '/id', '9007199254740993'], [1, '/n', 'null'], [3, '/id', '3']])
})
test('ordered field syntax supports exact escaped keys and rejects duplicate, overlap and malformed choices before lookup', () => {
  assert.deepEqual(parseJSONProjectionFields('/id'), ['/id']); assert.deepEqual(parseJSONProjectionFields(''), [''])
  assert.deepEqual(parseJSONProjectionFields('["/id","/line\\nbreak","/a~1b~0","/quote\\\"key"]'), ['/id', '/line\nbreak', '/a~1b~0', '/quote"key'])
  const empty = parseJSONSource('[]'), project = fields => projectJSONRecordFields(empty, 'array', nodeId(1, ''), fields)
  for (const fields of [[], ['/x', '/x'], ['/x', '/x/y'], ['/x/y', '/x'], ['', '/x'], ['/missing', '/missing'], [1], ['/bad~2'], Array.from({ length: 33 }, (_, i) => '/' + i), ['/\ud800'], ['/' + 'x'.repeat(4096)], Array.from({ length: 8 }, (_, i) => '/' + i + 'x'.repeat(2100))]) assert.throws(() => project(fields))
  for (const input of ['["/x",]', '[1]', '["/x","/x"]', '["/a","/a/b"]', 'x', ' '.repeat(16385)]) assert.throws(() => parseJSONProjectionFields(input))
  assert.equal(project(['/a', '/ab']).rows.length, 0)
})
test('multi-field additions reject count, UTF8 byte, and overlap limits without partial mutation', () => {
  const many = parseJSONSource('[' + Array.from({ length: 17 }, (_, i) => '{"id":' + i + ',"n":null}').join(',') + ']')
  const selected = new JSONSelection(many); selected.add(nodeId(1, '/16/id')); const prior = [...selected.ids]
  assert.throws(() => addJSONProjection(selected, projectJSONRecordFields(many, 'array', nodeId(1, ''), ['/id', '/n'])), /32 selected/); assert.deepEqual(selected.ids, prior)
  const snapshot = parseJSONSource('[{"id":1,"s":"' + 'é'.repeat(510) + '"},{"id":2,"s":null}]'), projection = projectJSONRecordFields(snapshot, 'array', nodeId(1, ''), ['/id', '/s']), selection = new JSONSelection(snapshot)
  selection.add(nodeId(1, '/1/id')); const before = [...selection.ids]
  assert.throws(() => addJSONProjection(selection, projection, 1024), /byte budget/); assert.deepEqual(selection.ids, before)
  for (const budget of [0, 1023, 16385, 1024.5, NaN]) { assert.throws(() => addJSONProjection(selection, projection, budget), /budget/); assert.deepEqual(selection.ids, before) }
  assert.equal(addJSONProjection(selection, projection, 1028), 3)
  const blocked = new JSONSelection(snapshot); blocked.add(nodeId(1, '/1')); const parents = [...blocked.ids]
  assert.throws(() => addJSONProjection(blocked, projection), /overlaps/); assert.deepEqual(blocked.ids, parents)
})
test('record-field preview remains bounded and 32 selected values at the exact byte ceiling are permitted', () => {
  const sparse = parseJSONSource('[' + Array(2050).fill('null').join(',') + ']')
  assert.throws(() => projectJSONRecordFields(sparse, 'array', nodeId(1, ''), ['/a', '/b']), /4096 cells/)
  const bounded = parseJSONSource('[' + Array(16).fill('{"a":"' + 'x'.repeat(510) + '","b":"' + 'y'.repeat(510) + '"}').join(',') + ']')
  const selected = new JSONSelection(bounded), projection = projectJSONRecordFields(bounded, 'array', nodeId(1, ''), ['/a', '/b'])
  assert.throws(() => addJSONProjection(selected, projection, 16383), /byte budget/); assert.deepEqual(selected.ids, [])
  assert.equal(addJSONProjection(selected, projection, 16384), 32); assert.equal(selected.ids.length, 32)
})

test('typed cohorts use exact decimal equality without rounding and preserve original tokens', () => {
  const snapshot = parseJSONSource('[1,1.0,1e0,10e-1,0.01e2,"1",true,9007199254740993,9007199254740992,0,-0,0e999999999999999999999999]')
  const select = json_text => projectJSONRecords(snapshot, 'array', nodeId(1, ''), '', { pointer: '', type: 'number', json_text })
  assert.deepEqual(select('1').values.map(value => value.json_text), ['1', '1.0', '1e0', '10e-1', '0.01e2'])
  assert.deepEqual(select('9007199254740993.0').values.map(value => value.json_text), ['9007199254740993'])
  assert.deepEqual(select('-0').values.map(value => value.json_text), ['0', '-0', '0e999999999999999999999999'])
  const key = text => scalarKey(parseJSONSource(text).nodes[0])
  for (const [a, b] of [['100e999999999999999999999999', '1e1000000000000000000000001'], ['0.01e-999999999999999999999999', '1e-1000000000000000000000001'], ['1e+00002', '100'], ['100e-1', '10'], ['0.01e1', '0.1'], ['10e-2', '0.1'], ['1.00e-0', '1']]) assert.equal(key(a), key(b), a)
  assert.notEqual(key('1e400'), key('2e400')); assert.notEqual(key('1e-400'), key('2e-400'))
  const huge = '9'.repeat(20000)
  assert.equal(key('10e' + huge), key('1e1' + '0'.repeat(20000)))
  for (let coefficient = -40; coefficient <= 40; coefficient++) for (let exponent = -8; exponent <= 8; exponent++) {
    const base = String(coefficient) + 'e' + exponent
    assert.equal(key(base), key(String(coefficient * 10) + 'e' + (exponent - 1)), base)
    assert.equal(key(base), key(String(coefficient) + '.000e' + exponent), base)
  }
})
test('decoded string, boolean and null equality stay separate from missing and container fields', () => {
  const snapshot = parseJSONSource('{"a/b~":"a","id":1}\n{"a/b~":"\\u0061","id":2}\n{"a/b~":null,"id":3}\n{"id":4}\n{"a/b~":false,"id":5}\n{"a/b~":"false","id":6}\n{"a/b~":{},"id":7}', 'jsonl')
  const select = (type, json_text) => projectJSONRecords(snapshot, 'jsonl', '', '/id', { pointer: '/a~1b~0', type, json_text })
  const strings = select('string', '"a"')
  assert.deepEqual(strings.values.map(value => value.document), [1, 2]); assert.equal(strings.total, 7); assert.equal(strings.excluded, 5); assert.equal(strings.predicateMissing, 1)
  assert.deepEqual(select('null', 'null').values.map(value => value.document), [3])
  assert.deepEqual(select('boolean', 'false').values.map(value => value.document), [5])
  assert.equal(select('string', '"absent"').rows.length, 0)
  for (const predicate of [{ pointer: 'id', type: 'number', json_text: '1' }, { pointer: '', type: 'array', json_text: '[]' }, { pointer: '', type: 'number', json_text: '"1"' }, { pointer: '', type: 'number', json_text: '1+1' }, { pointer: '', type: 'string', json_text: '"\\ud800"' }, { pointer: '', type: 'string', json_text: '"' + 'a'.repeat(4096) + '"' }]) assert.throws(() => projectJSONRecords(snapshot, 'jsonl', '', '/id', predicate))
})
test('cohort projection narrows over-limit records and retains atomic overlap/missing behavior', () => {
  const snapshot = parseJSONSource('[' + Array.from({ length: 40 }, (_, i) => JSON.stringify({ id: i, keep: i % 10 === 0 })).join(',') + ']')
  const selection = new JSONSelection(snapshot)
  assert.throws(() => addJSONProjection(selection, projectJSONRecords(snapshot, 'array', nodeId(1, ''), '/id')), /32 selected/)
  const plan = projectJSONRecords(snapshot, 'array', nodeId(1, ''), '/id', { pointer: '/keep', type: 'boolean', json_text: 'true' })
  assert.equal(addJSONProjection(selection, plan), 4); assert.deepEqual(selection.selected().map(value => value.json_text), ['0', '10', '20', '30']); assert.equal(addJSONProjection(selection, plan), 0)
  const absent = projectJSONRecords(snapshot, 'array', nodeId(1, ''), '/absent', plan.cohort)
  assert.equal(absent.missing, 4); assert.throws(() => addJSONProjection(selection, absent), /No values/)
  const blocked = new JSONSelection(snapshot); blocked.add(nodeId(1, '/10')); const prior = [...blocked.ids]
  assert.throws(() => addJSONProjection(blocked, plan), /overlaps/); assert.deepEqual(blocked.ids, prior)
})

test('array field projection preserves exact values and distinguishes absent from null', () => {
  const snapshot = parseJSONSource('{"rows":[{"a/b~":{"id":9007199254740993123}},{"a/b~":{"id":null}},{"a/b~":{}},false,{"a/b~":{"id":-0}}]}')
  const projection = projectJSONRecords(snapshot, 'array', nodeId(1, '/rows'), '/a~1b~0/id')
  assert.equal(projection.rows.length, 5); assert.equal(projection.missing, 2)
  assert.deepEqual(projection.values.map(value => value.json_text), ['9007199254740993123', 'null', '-0'])
  assert.deepEqual(projection.values.map(value => value.pointer), ['/rows/0/a~1b~0/id', '/rows/1/a~1b~0/id', '/rows/4/a~1b~0/id'])
})
test('JSON Lines documents have distinct identities and scalar roots can be projected whole', () => {
  const snapshot = parseJSONSource('{"id":1e+03}\n{"id":"\\u0061"}\nnull\n{"id":false}', 'jsonl')
  const fields = projectJSONRecords(snapshot, 'jsonl', '', '/id')
  assert.equal(fields.missing, 1); assert.deepEqual(fields.values.map(value => [value.document, value.json_text]), [[1, '1e+03'], [2, '"\\u0061"'], [4, 'false']])
  const roots = projectJSONRecords(snapshot, 'jsonl', '', '')
  assert.equal(roots.values.length, 4); assert.equal(roots.values[2].type, 'null')
})
test('only immediate array items are records; empty and missing collections are explicit', () => {
  const snapshot = parseJSONSource('[[{"x":1}],{"x":2},[],{"x":3}]')
  assert.equal(projectJSONRecords(snapshot, 'array', nodeId(1, ''), '').rows.length, 4)
  assert.equal(projectJSONRecords(snapshot, 'array', nodeId(1, '/2'), '').values.length, 0)
  assert.equal(projectJSONRecords(snapshot, 'array', nodeId(1, ''), '/x').missing, 2)
  for (const [mode, id, pointer] of [['array', nodeId(1, '/1'), ''], ['array', '', ''], ['jsonl', '', ''], ['invalid', '', ''], ['array', nodeId(1, ''), 'x'], ['array', nodeId(1, ''), '/bad~2']]) assert.throws(() => projectJSONRecords(snapshot, mode, id, pointer))
})
test('bulk addition is ordered, idempotent and all-or-nothing for overlaps and limits', () => {
  const snapshot = parseJSONSource('[{"id":1},{"id":2},{"id":3}]'), selection = new JSONSelection(snapshot)
  selection.add(nodeId(1, '/2/id'))
  const plan = projectJSONRecords(snapshot, 'array', nodeId(1, ''), '/id')
  assert.equal(addJSONProjection(selection, plan), 2)
  assert.deepEqual(selection.ids, [nodeId(1, '/2/id'), nodeId(1, '/0/id'), nodeId(1, '/1/id')]); assert.equal(addJSONProjection(selection, plan), 0)
  const overlap = new JSONSelection(snapshot); overlap.add(nodeId(1, '/1')); const prior = [...overlap.ids]
  assert.throws(() => addJSONProjection(overlap, plan), /overlaps/); assert.deepEqual(overlap.ids, prior)
  const many = parseJSONSource('[' + Array(33).fill('0').join(',') + ']'), bounded = new JSONSelection(many)
  bounded.add(nodeId(1, '/32')); assert.throws(() => addJSONProjection(bounded, projectJSONRecords(many, 'array', nodeId(1, ''), '')), /32 selected/)
  assert.deepEqual(bounded.ids, [nodeId(1, '/32')])
  assert.throws(() => addJSONProjection(selection, projectJSONRecords(snapshot, 'array', nodeId(1, ''), '/absent')), /No values/)
  assert.throws(() => addJSONProjection(selection, { ...plan, snapshot: parseJSONSource('[]') }), /current JSON/)
})
