import { readJSONFile, JSONSelection, nodeLabel, matchingJSONNodes, composeJSON, removeJSON } from './json-input.js'
import { parseJSONProjectionFields, projectJSONRecordFields, addJSONProjection } from './json-projection.js'
const need = (ok, message) => { if (!ok) throw new Error(message) }

export function mountJSONInput(document, anchor) {
  const root = document.createElement('details'); root.id = 'claw-json-panel'; root.className = 'panel'
  const summary = document.createElement('summary'); summary.textContent = 'Choose nested JSON values for a task'; root.appendChild(summary)
  const add = (tag, key, text = '') => { const node = document.createElement(tag); node.id = 'claw-json-' + key; node.textContent = text; root.appendChild(node); return node }
  const field = (tag, key, title) => { const label = add('label', key + '-label', title); label.htmlFor = 'claw-json-' + key; return add(tag, key) }
  const button = (key, title) => { const node = add('button', key, title); node.type = 'button'; return node }
  add('p', 'help', 'Open a local UTF-8 JSON or JSON Lines export, inspect exact typed values, then select only the paths this task needs. Up to 256 KiB, 4096 nodes and 32 nesting levels. No upload, URL fetch or task starts here. A valid new import replaces the unsent selection only; a failed import keeps it.')
  const format = field('select', 'format', 'Input format (choose before opening a file)')
  for (const [value, title] of [['json', 'JSON: one complete document'], ['jsonl', 'JSON Lines: one complete document per nonblank line']]) { const option = document.createElement('option'); option.value = value; option.textContent = title; format.appendChild(option) }; format.value = 'json'
  const file = field('input', 'file', 'Open one local snapshot'); file.type = 'file'; file.accept = '.json,.jsonl,.ndjson,application/json,text/plain'
  add('p', 'identity', 'No JSON imported.')
  field('input', 'query', 'Find literal text in paths, types or values (selection is unchanged)'); add('p', 'matches')
  field('select', 'node', 'Matching JSON value: document, JSON Pointer and type'); add('pre', 'node-text')
  button('add', 'Add inspected JSON value')
  add('p', 'projection-help', 'Choose ordered exact fields across records: inspect an array above or choose JSON Lines documents below. Enter /id for one field, or ["/id","/details/amount"] for several fields in that order. Empty input or [""] includes complete records. Preview shows each record and every cell, distinguishing missing from null. Nothing is selected automatically.')
  const projectionMode = field('select', 'projection-mode', 'Project records from')
  for (const [value, title] of [['array', 'Immediate items of the inspected array'], ['jsonl', 'All imported JSON Lines documents']]) { const option = document.createElement('option'); option.value = value; option.textContent = title; projectionMode.appendChild(option) }; projectionMode.value = 'array'
  const cohortType = field('select', 'cohort-type', 'Keep records whose field equals a typed scalar (optional)')
  for (const value of ['all', 'string', 'number', 'boolean', 'null']) { const option = document.createElement('option'); option.value = value; option.textContent = value === 'all' ? 'All records (no predicate)' : value; cohortType.appendChild(option) }; cohortType.value = 'all'
  field('input', 'cohort-pointer', 'Cohort field: exact relative JSON Pointer (empty means the record itself)')
  field('input', 'cohort-value', 'Equals JSON scalar: for example "ready", 1, true or null')
  add('p', 'cohort-help', 'Equality keeps types separate. Strings compare decoded text; numbers compare exact decimal values (1, 1.0 and 1e0 match; -0 equals 0). Missing fields never equal null. No expressions or coercion. Original selected JSON spelling is preserved. Preview shows the source-ordered cohort; literal search above is not a record filter.')
  field('textarea', 'projection-pointer', 'Ordered relative JSON Pointers: one pointer or a JSON array of pointer strings')
  button('projection-preview', 'Preview record fields'); add('pre', 'projection-text')
  button('projection-add', 'Add previewed values: record order, then field order').disabled = true
  add('p', 'projection-order', 'New values append record by record, in your chosen field order. Existing selected values keep their positions; already-selected values are not added twice. Missing cells are omitted and explicit null is included. The task packet is still an ordered flat list with exact document and pointer identities, not a structured table or record packet. Duplicate or parent/child field pointers are refused, even when missing.')
  field('select', 'selected', 'Selected values, in task order')
  button('up', 'Move selected value up'); button('down', 'Move selected value down'); button('remove', 'Remove selected value')
  field('textarea', 'purpose', 'Why should these values inform the task?')
  const budget = field('input', 'budget', 'Exact selected JSON text: UTF-8 byte budget, not tokens'); budget.type = 'number'; budget.min = '1024'; budget.max = '16384'; budget.step = '1'; budget.value = '8192'
  add('pre', 'selection'); button('preview', 'Preview selected JSON in task'); add('pre', 'preview-text')
  button('apply', 'Put previewed JSON in draft').disabled = true
  button('detach', 'Remove JSON block from draft'); button('clear', 'Clear unsent JSON'); button('cancel', 'Interrupt preparation')
  const status = add('p', 'status', 'Nothing is selected automatically. Unsent preparation is lost on reload or leaving this Work thread.'); status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite')
  add('p', 'limits', 'Select up to 32 nonoverlapping values with 1024–16384 selected UTF-8 bytes. Selecting an object or array includes all its children; inspect before adding it. JSON Pointer uses ~0 for ~ and ~1 for /; array positions are zero-based. Number spelling, string escapes, null and boolean types are kept exactly. Duplicate object keys are refused. Use the ordinary Plan, Preview, Promote and Confirm controls for work and authority.')
  anchor.insertAdjacentElement('afterend', root); return root
}

export function bindJSONInput(document, options = {}) {
  const node = key => document.getElementById('claw-json-' + key), root = node('panel')
  if (!root || root.dataset.bound) return null
  root.dataset.bound = 'true'
  const composer = () => document.getElementById('claw-procedure-composer')
  const contextText = () => document.getElementById('claw-procedure-context')?.textContent || ''
  const transport = options.transport || (() => globalThis.__moonclawTransport)
  const ownership = () => JSON.stringify([contextText(), transport()?.base?.() || '', transport()?.epoch?.() || 0])
  const events = new AbortController(), listen = (target, type, handler) => target.addEventListener(type, handler, { signal: events.signal })
  let selection = null, scope = ownership(), generation = 0, pending = false, preview = null, projection = null
  const status = message => { if (node('status').textContent !== message) node('status').textContent = message }
  const invalidate = () => { generation++; pending = false; preview = null; projection = null; node('projection-text').textContent = ''; node('projection-add').disabled = true; node('preview-text').textContent = ''; node('apply').disabled = true }
  const choices = (key, entries) => {
    const target = node(key), value = target.value; target.replaceChildren()
    for (const [id, label] of [['', 'Choose…'], ...entries]) { const option = document.createElement('option'); option.value = id; option.textContent = label; target.appendChild(option) }
    target.value = entries.some(([id]) => id === value) ? value : ''
  }
  const inspect = () => {
    const value = selection?.snapshot.nodes.find(item => item.id === node('node').value)
    node('node-text').textContent = value ? nodeLabel(value) + ' · physical lines ' + value.start_line + '–' + value.end_line + '\nExact JSON text (' + new TextEncoder().encode(value.json_text).length + ' bytes):\n' + value.json_text : 'Choose a matching value to inspect. Objects and arrays include their complete subtree.'
  }
  const render = () => {
    const snapshot = selection?.snapshot, matches = snapshot ? matchingJSONNodes(snapshot, node('query').value) : []
    choices('node', matches.map(value => [value.id, nodeLabel(value)]))
    choices('selected', (selection?.selected() || []).map((value, index) => [value.id, (index + 1) + '. ' + nodeLabel(value)]))
    node('identity').textContent = snapshot ? snapshot.source.name + ' · ' + snapshot.format + ' · ' + snapshot.source.bytes + ' bytes · ' + snapshot.documents + ' documents · ' + snapshot.nodes.length + ' nodes\n' + snapshot.source.sha256 + '\nFrozen snapshot; authenticity and disk freshness unverified.' : 'No JSON imported.'
    node('matches').textContent = matches.length + ' of ' + (snapshot?.nodes.length || 0) + ' nodes match. Every bounded match is reachable; filtering never selects or removes values.'
    node('selection').textContent = (selection?.selected() || []).map((value, index) => (index + 1) + '. ' + nodeLabel(value) + '\n' + value.json_text).join('\n\n')
    inspect()
  }
  const clear = () => { selection = null; for (const key of ['file', 'query', 'purpose', 'projection-pointer', 'cohort-pointer', 'cohort-value']) node(key).value = ''; node('cohort-type').value = 'all'; node('projection-mode').value = 'array'; node('budget').value = '8192'; render() }
  const sync = () => { if (scope !== ownership()) { invalidate(); scope = ownership(); clear(); status('Work thread, folder or gateway access changed. Choose JSON inputs again; the main task draft was kept.') } }
  const guard = () => {
    sync(); need(root.isConnected !== false && composer(), 'This Work thread was closed')
    const context = JSON.parse(contextText()); need(context.session_key && typeof context.cwd === 'string', 'Choose a Work thread first')
    need(!context.cwd_override || context.cwd_override === context.cwd, 'Save the work folder change first'); return context
  }
  const action = operation => () => { try { guard(); const prepared = projection; invalidate(); operation(prepared) } catch (error) { status(error.message || 'JSON preparation failed; draft kept') } }
  const perform = operation => async () => {
    let ticket
    try {
      const context = guard(); if (pending) return
      const prepared = preview; invalidate(); pending = true; ticket = generation; const owner = ownership()
      const valid = () => need(ticket === generation && owner === ownership() && root.isConnected !== false, 'JSON preparation changed or interrupted; draft kept')
      await operation(context, valid, prepared); valid()
    } catch (error) { if ((ticket === undefined || ticket === generation) && root.isConnected !== false) status(error.message || 'JSON preparation failed; draft kept') }
    finally { if (ticket === generation) pending = false }
  }
  listen(node('file'), 'change', async () => {
    const files = Array.from(node('file').files || []), format = node('format').value; invalidate(); if (!files.length) return
    await perform(async (_, valid) => { need(files.length === 1, 'Choose one JSON file'); const snapshot = await readJSONFile(files[0], format); valid(); clear(); selection = new JSONSelection(snapshot); render(); status('Snapshot imported. Inspect and select the paths the task needs. The draft is unchanged.') })()
  })
  listen(node('format'), 'change', action(() => { status('Format changed for the next import. Existing imported values retain their original format; reopen a file to reinterpret it.') }))
  for (const key of ['query', 'purpose', 'budget']) listen(node(key), 'input', action(() => { if (key === 'query') render() }))
  listen(composer(), 'input', () => { sync(); invalidate() })
  listen(node('node'), 'change', action(inspect))
  const requireSelection = () => { need(selection, 'Import a JSON snapshot first'); return selection }
  listen(node('projection-mode'), 'change', action(() => {}))
  listen(node('projection-pointer'), 'input', action(() => {}))
  listen(node('cohort-type'), 'change', action(() => {}))
  for (const key of ['cohort-pointer', 'cohort-value']) listen(node(key), 'input', action(() => {}))
  const cohortInput = () => node('cohort-type').value === 'all' ? null : { pointer: node('cohort-pointer').value, type: node('cohort-type').value, json_text: node('cohort-value').value }
  // Event invalidation catches edit-and-restore. The signatures also catch direct
  // field/composer changes by other controllers before an event is dispatched.
  const inputSignature = () => JSON.stringify([ownership(), composer()?.value, selection?.ids, ...['format', 'query', 'node', 'projection-mode', 'projection-pointer', 'cohort-type', 'cohort-pointer', 'cohort-value', 'purpose', 'budget'].map(key => node(key).value)])
  let projectedInputSignature = null
  listen(node('projection-preview'), 'click', action(() => {
    projection = projectJSONRecordFields(requireSelection().snapshot, node('projection-mode').value, node('node').value, parseJSONProjectionFields(node('projection-pointer').value), cohortInput())
    projectedInputSignature = inputSignature()
    node('projection-text').textContent = JSON.stringify({ total_records: projection.total, excluded_records: projection.excluded, missing_predicate_fields: projection.predicateMissing, predicate: cohortInput(), records: projection.rows.length, matched: projection.values.length, missing: projection.missing,
      fields: projection.fields, append_order: 'record-major, then chosen field order; existing selection positions retained', packet_shape: 'ordered flat values; missing cells omitted',
      rows: projection.rows.map(row => ({ document: row.document, record_pointer: row.record_pointer, cells: row.cells.map(cell => ({ relative_pointer: cell.relative, pointer: cell.pointer, state: cell.state, present: !!cell.value, ...(cell.value ? { type: cell.value.type, json_text: cell.value.json_text } : {}) })) })) }, null, 2)
    node('projection-add').disabled = projection.values.length === 0
    status(projection.rows.length + ' of ' + projection.total + ' records in cohort; ' + projection.fields.length + ' fields per record; ' + projection.values.length + ' projected values; ' + projection.missing + ' missing cells omitted. Inspect every cell before adding. Existing selection and task draft are unchanged.')
  }))
  listen(node('projection-add'), 'click', action(prepared => {
    need(prepared && projectedInputSignature === inputSignature(), 'Projection fields, selection or draft changed; preview again before adding')
    const count = addJSONProjection(requireSelection(), prepared, Number(node('budget').value)); render()
    status(count + ' projected values added in record order, then field order; ' + prepared.missing + ' missing cells omitted. Existing selected values kept their positions. Preview the complete task before applying.')
  }))
  listen(node('add'), 'click', action(() => { requireSelection().add(node('node').value); render(); status('Value added. Preview the full task before applying it.') }))
  listen(node('selected'), 'change', action(() => { if (node('selected').value) { const id = node('selected').value; node('query').value = ''; render(); node('node').value = id; inspect() } }))
  listen(node('remove'), 'click', action(() => { requireSelection().remove(node('selected').value); render(); status('Value removed from unsent selection. Preview and apply to update an existing task block.') }))
  for (const [direction, offset] of [['up', -1], ['down', 1]]) listen(node(direction), 'click', action(() => { requireSelection().move(node('selected').value, offset); render() }))
  listen(node('preview'), 'click', perform(async (context, valid) => {
    const draft = composer().value, signature = inputSignature(), snapshot = requireSelection().snapshot, packet = await requireSelection().packet(context, node('purpose').value, Number(node('budget').value)); valid()
    const next = await composeJSON(draft, packet); valid(); need(composer().value === draft, 'Main draft changed; preview again')
    need(signature === inputSignature() && snapshot === selection?.snapshot, 'JSON inputs changed; preview again')
    preview = { draft, next, scope: ownership(), signature, snapshot }; node('preview-text').textContent = next; node('apply').disabled = false
    status('Full task preview ready: ' + packet.selected_bytes + ' / ' + packet.value_budget_bytes + ' selected JSON bytes. Inspect complete subtrees and omitted context. Nothing has been sent.')
  }))
  listen(node('apply'), 'click', perform(async (_, valid, prepared) => {
    need(prepared && prepared.scope === ownership() && composer().value === prepared.draft && prepared.signature === inputSignature() && prepared.snapshot === selection?.snapshot, 'Preview the current JSON and task draft first'); valid()
    composer().value = prepared.next; pending = false; composer().dispatchEvent(options.inputEvent?.() || new Event('input', { bubbles: true }))
    status('Previewed JSON placed in the ordinary task draft. Use Plan and Preview, then Promote and Confirm only the work you approve.')
  }))
  listen(node('detach'), 'click', perform(async (_, valid) => {
    const draft = composer().value, next = await removeJSON(draft); valid(); need(composer().value === draft, 'Main draft changed; remove again')
    composer().value = next; pending = false; composer().dispatchEvent(options.inputEvent?.() || new Event('input', { bubbles: true })); status('JSON block removed. Other task text and unsent selections were kept.')
  }))
  listen(node('clear'), 'click', action(() => { clear(); status('Unsent JSON cleared; the existing task draft was kept.') }))
  listen(node('cancel'), 'click', () => { invalidate(); status('Pending preparation interrupted; selections and task draft were kept.') })
  listen(root, 'toggle', () => { if (!root.open) { invalidate(); status('JSON panel closed; pending preparation interrupted. The task draft was kept.') } })
  render(); return { sync, get selection() { return selection }, dispose() { invalidate(); events.abort(); delete root.dataset.bound } }
}
export function installJSONInput(document) {
  let anchor = null, root = null, binding = null
  const sync = () => {
    const next = document.getElementById('claw-procedure-panel')
    if (next !== anchor || (root && root.isConnected === false)) { binding?.dispose(); root?.remove(); anchor = next; root = next ? mountJSONInput(document, next) : null; binding = root ? bindJSONInput(document) : null }
    binding?.sync()
  }
  sync(); const observer = new MutationObserver(sync); observer.observe(document.body, { childList: true, subtree: true, characterData: true })
  return () => { observer.disconnect(); binding?.dispose(); root?.remove() }
}
