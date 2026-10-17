import { nodeId, LIMITS } from './json-input.js'
import { prepareJSONCohort, scalarKey } from './json-cohort.js'
import { byteLength } from './source-brief.js'

const need = (ok, message) => { if (!ok) throw new Error(message) }
const validPointer = pointer => typeof pointer === 'string' && pointer.isWellFormed() && /^(?:\/(?:[^~]|~[01])*)?$/u.test(pointer)
const overlap = (a, b) => a.document === b.document && (a.pointer === b.pointer || a.pointer === '' || b.pointer === '' || a.pointer.startsWith(b.pointer + '/') || b.pointer.startsWith(a.pointer + '/'))

const validateFields = relatives => {
  need(Array.isArray(relatives) && relatives.length > 0 && relatives.length <= LIMITS.selected, 'Choose one to 32 ordered relative JSON Pointers')
  for (let i = 0; i < relatives.length; i++) {
    const pointer = relatives[i]
    need(validPointer(pointer) && byteLength(pointer) <= 4096, 'Use an exact relative JSON Pointer: empty for each record, /field for a member, ~0 for ~ and ~1 for /.')
    need(!relatives.slice(0, i).some(old => overlap({ document: 1, pointer: old }, { document: 1, pointer })), 'Duplicate or overlapping field pointers; choose separate fields. Nothing was added')
  }
  need(byteLength(JSON.stringify(relatives)) <= 16384, 'Ordered field pointers exceed 16384 UTF-8 bytes')
  return Object.freeze([...relatives])
}

// The input is either the original exact pointer or a JSON array of pointers.
// JSON string syntax also permits fields containing literal newlines or quotes.
export function parseJSONProjectionFields(input) {
  need(typeof input === 'string' && input.isWellFormed() && byteLength(input) <= 16384, 'Use at most 16384 UTF-8 bytes for ordered field pointers')
  let fields = [input]
  if (input.trimStart().startsWith('[')) {
    try { fields = JSON.parse(input) } catch { throw new Error('Enter an exact pointer or a JSON array of pointer strings, for example ["/id","/amount"]') }
  }
  return validateFields(fields)
}

// Exact fields only: no expressions, wildcards or imported code are evaluated.
// Each record owns an ordered cell list, including absent fields and actual nulls.
export function projectJSONRecordFields(snapshot, mode, collectionId, relatives, predicate = null) {
  const fields = validateFields(relatives)
  need(['array', 'jsonl'].includes(mode), 'Choose array items or JSON Lines documents')
  let records
  if (mode === 'jsonl') {
    need(snapshot.format === 'jsonl', 'Import JSON Lines before projecting its documents')
    records = snapshot.nodes.filter(node => node.pointer === '')
  } else {
    const collection = snapshot.nodes.find(node => node.id === collectionId)
    need(collection?.type === 'array', 'Inspect an array to use its immediate items as records')
    const prefix = collection.pointer + '/'
    records = snapshot.nodes.filter(node => node.document === collection.document && node.pointer.startsWith(prefix) && !node.pointer.slice(prefix.length).includes('/'))
  }
  const byId = new Map(snapshot.nodes.map(node => [node.id, node]))
  const cohort = prepareJSONCohort(predicate), total = records.length
  let predicateMissing = 0
  if (cohort) records = records.filter(record => {
    const value = byId.get(nodeId(record.document, record.pointer + cohort.pointer))
    if (!value) predicateMissing++
    return value?.type === cohort.type && scalarKey(value) === cohort.key
  })
  need(records.length * fields.length <= LIMITS.nodes, 'Record-field preview exceeds 4096 cells; narrow the typed cohort or choose fewer fields. Nothing was added')
  const rows = records.map(record => {
    const cells = fields.map(relative => {
      const pointer = record.pointer + relative, value = byId.get(nodeId(record.document, pointer)) || null
      return Object.freeze({ relative, pointer, state: value ? value.type === 'null' ? 'null' : 'present' : 'missing', value })
    })
    return Object.freeze({ document: record.document, record_pointer: record.pointer, cells: Object.freeze(cells) })
  })
  const cells = rows.flatMap(row => row.cells), values = cells.filter(cell => cell.value).map(cell => cell.value)
  return Object.freeze({ snapshot, mode, collectionId, fields, cohort, total, excluded: total - records.length, predicateMissing, rows: Object.freeze(rows), values: Object.freeze(values), missing: cells.length - values.length })
}

// Preserve the existing one-field API for callers that consume row.value.
export function projectJSONRecords(snapshot, mode, collectionId, relative, predicate = null) {
  const projection = projectJSONRecordFields(snapshot, mode, collectionId, [relative], predicate)
  return Object.freeze({ ...projection, relative, rows: Object.freeze(projection.rows.map(row => Object.freeze({ ...row, pointer: row.cells[0].pointer, value: row.cells[0].value }))) })
}

export function addJSONProjection(selection, projection, budget = 16384) {
  need(projection && projection.snapshot === selection.snapshot, 'Preview a projection from the current JSON snapshot first')
  const current = projectJSONRecordFields(selection.snapshot, projection.mode, projection.collectionId, projection.fields, projection.cohort)
  need(current.values.length > 0, 'No values matched. Inspect the missing paths or change the relative pointer')
  const selected = selection.selected(), additions = current.values.filter(value => !selection.ids.includes(value.id))
  need(selected.length + additions.length <= LIMITS.selected, 'Projection exceeds 32 selected values; narrow the typed cohort or select individual values. Nothing was added')
  const next = [...selected]
  for (const value of additions) {
    need(!next.some(old => overlap(old, value)), 'Projection overlaps a selected parent or child; remove that selection first. Nothing was added')
    next.push(value)
  }
  need(Number.isSafeInteger(budget) && budget >= 1024 && budget <= 16384, 'Choose a selected JSON byte budget from 1024 to 16384. Nothing was added')
  need(next.reduce((sum, value) => sum + byteLength(value.json_text), 0) <= budget, 'Projection exceeds the selected JSON byte budget; narrow the fields or cohort, remove values, or raise the bounded budget. Nothing was added')
  // Assign only after the entire cohort passes; retain existing order and append
  // new values in record-major then chosen-field order. Missing cells are omitted;
  // the packet remains an ordered flat list. Repeated addition is idempotent.
  selection.ids = next.map(value => value.id)
  return additions.length
}
