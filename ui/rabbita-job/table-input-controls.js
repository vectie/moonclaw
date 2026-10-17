import { readTableFile, TableSelection, columnLabel, matchingRecords, composeTable, removeTable } from './table-input.js'
const need = (ok, message) => { if (!ok) throw new Error(message) }

export function mountTableInput(document, anchor) {
  const root = document.createElement('details'); root.id = 'claw-table-panel'; root.className = 'panel'
  const summary = document.createElement('summary'); summary.textContent = 'Choose CSV records and columns'; root.appendChild(summary)
  const add = (tag, key, text = '') => { const node = document.createElement(tag); node.id = 'claw-table-' + key; node.textContent = text; root.appendChild(node); return node }
  const field = (tag, key, title) => { const label = add('label', key + '-label', title); label.htmlFor = 'claw-table-' + key; return add(tag, key) }
  const button = (key, title) => { const node = add('button', key, title); node.type = 'button'; return node }
  add('p', 'help', 'Choose a local UTF-8 comma-separated CSV with a header, up to 256 KiB, 2000 data records and 128 columns. Quoted multiline cells, duplicate/blank headers and literal formula-like text are supported. Importing replaces only this unsent table selection after successful parsing. No upload or task is sent.')
  const file = field('input', 'file', 'Open one CSV table'); file.type = 'file'; file.accept = '.csv,text/csv,text/plain'
  add('p', 'identity', 'No table imported.')
  field('input', 'query', 'Find literal text in any cell (selection is unchanged)')
  field('select', 'filter-column', 'Filter one original column')
  const operator = field('select', 'filter-operator', 'Literal comparison (case-sensitive; no trimming)')
  for (const [value, title] of [['equals', 'Equals'], ['contains', 'Contains'], ['blank', 'Is empty (zero characters)']]) { const option = document.createElement('option'); option.value = value; option.textContent = title; operator.appendChild(option) }
  operator.value = 'equals'
  field('textarea', 'filter-value', 'Exact filter text; ignored for Is empty')
  button('add-filter', 'Add column filter (AND)')
  field('select', 'selected-filter', 'Active column filters')
  button('remove-filter', 'Remove selected filter'); button('clear-filters', 'Clear column filters')
  add('p', 'filter-help', 'All active filters and the any-cell search must match. Filters do not select or remove records. Inspect the matching cells below before adding them; selected records remain unchanged when filters change.')
  add('p', 'matches')
  add('pre', 'matching-text')
  button('add-matches', 'Add all matching records in source order')
  field('select', 'record', 'Matching data record (header is logical record 1)')
  add('pre', 'record-text')
  button('add-record', 'Add inspected record')
  field('select', 'selected-record', 'Selected records, in task order')
  button('record-up', 'Move selected record up'); button('record-down', 'Move selected record down'); button('remove-record', 'Remove selected record')
  field('select', 'column', 'Source column (identified by its original position)')
  button('add-column', 'Add column')
  field('select', 'selected-column', 'Selected columns, in task order')
  button('column-up', 'Move selected column left'); button('column-down', 'Move selected column right'); button('remove-column', 'Remove selected column')
  field('textarea', 'purpose', 'Why should these records and columns inform the task?')
  const budget = field('input', 'budget', 'Selected headers and cells: UTF-8 byte budget, not tokens'); budget.type = 'number'; budget.min = '1024'; budget.max = '16384'; budget.step = '1'; budget.value = '8192'
  add('pre', 'selection')
  button('preview', 'Preview selected table in task'); add('pre', 'preview-text')
  button('apply', 'Put previewed table in draft').disabled = true
  button('detach', 'Remove table block from draft'); button('clear', 'Clear unsent table'); button('cancel', 'Interrupt preparation')
  const status = add('p', 'status', 'Select columns and records explicitly. Nothing is selected automatically. Unsent table preparation is lost on reload or leaving this Work thread.'); status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite')
  add('p', 'limits', 'Up to 50 records and 32 columns per task, with 1024–16384 selected UTF-8 bytes. Preview shows the complete resulting task, including other existing task text. Omitted cells may contain important context. Values are not converted to numbers, dates or formulas. Use the ordinary Plan, Preview, Promote and Confirm controls to review work and authority.')
  anchor.insertAdjacentElement('afterend', root); return root
}

export function bindTableInput(document, options = {}) {
  const node = key => document.getElementById('claw-table-' + key), root = node('panel')
  if (!root || root.dataset.bound) return null
  root.dataset.bound = 'true'
  const composer = () => document.getElementById('claw-procedure-composer')
  const contextText = () => document.getElementById('claw-procedure-context')?.textContent || ''
  const transport = options.transport || (() => globalThis.__moonclawTransport)
  const ownership = () => JSON.stringify([contextText(), transport()?.base?.() || '', transport()?.epoch?.() || 0])
  const events = new AbortController(), listen = (target, type, handler) => target.addEventListener(type, handler, { signal: events.signal })
  let selection = null, filters = [], scope = ownership(), generation = 0, pending = false, preview = null
  const status = message => { if (node('status').textContent !== message) node('status').textContent = message }
  const invalidate = () => { generation++; pending = false; preview = null; node('preview-text').textContent = ''; node('apply').disabled = true }
  const choices = (key, entries) => {
    const target = node(key), value = target.value; target.replaceChildren()
    for (const [id, label] of [['', 'Choose…'], ...entries]) { const option = document.createElement('option'); option.value = String(id); option.textContent = label; target.appendChild(option) }
    target.value = entries.some(([id]) => String(id) === value) ? value : ''
  }
  const inspect = () => {
    const record = selection?.table.records.find(item => String(item.record_number) === node('record').value)
    node('record-text').textContent = record ? 'Original logical record ' + record.record_number + ' · physical lines ' + record.start_line + '–' + record.end_line + '\n' + record.cells.map((cell, index) => columnLabel(selection.table, index) + '\n' + JSON.stringify(cell)).join('\n\n') : 'Choose a matching record to inspect all its exact cell values.'
  }
  const render = () => {
    const table = selection?.table, matches = table ? matchingRecords(table, node('query').value, filters) : []
    // All bounded matches stay reachable; no hidden first-page selection limit.
    choices('record', matches.map(record => [record.record_number, 'Record ' + record.record_number + ' · lines ' + record.start_line + '–' + record.end_line]))
    choices('column', table ? table.header.cells.map((_, index) => [index + 1, columnLabel(table, index)]) : [])
    choices('filter-column', table ? table.header.cells.map((_, index) => [index + 1, columnLabel(table, index)]) : [])
    choices('selected-filter', filters.map((filter, index) => [index + 1, columnLabel(table, filter.column - 1) + ' ' + filter.operator + (filter.operator === 'blank' ? '' : ' ' + JSON.stringify(filter.value))]))
    choices('selected-record', (selection?.records || []).map((id, index) => [id, (index + 1) + '. Original record ' + id]))
    choices('selected-column', (selection?.columns || []).map((id, index) => [id, (index + 1) + '. ' + columnLabel(table, id - 1)]))
    node('identity').textContent = table ? table.source.name + ' · ' + table.source.bytes + ' bytes · ' + table.records.length + ' data records · ' + table.header.cells.length + ' columns\n' + table.source.sha256 + '\nFrozen local snapshot; authenticity and disk freshness unverified.' : 'No table imported.'
    node('matches').textContent = matches.length + ' of ' + (table?.records.length || 0) + ' data records match. Filtering does not change selected rows or columns.'
    node('matching-text').textContent = table ? JSON.stringify({ headers: table.header.cells, matching_records: matches }, null, 2) : ''
    node('selection').textContent = selection ? JSON.stringify({ columns: selection.columns.map(id => ({ column_number: id, header: table.header.cells[id - 1] })), records: selection.records.map(id => ({ record_number: id, cells: selection.columns.map(column => table.records[id - 2].cells[column - 1]) })) }, null, 2) : ''
    inspect()
  }
  const clear = () => { selection = null; filters = []; for (const key of ['file', 'query', 'purpose', 'filter-value']) node(key).value = ''; node('filter-operator').value = 'equals'; node('budget').value = '8192'; render() }
  const sync = () => {
    if (scope !== ownership()) { invalidate(); scope = ownership(); clear(); status('Work thread, folder or gateway access changed. Choose table inputs again; the main task draft was kept.') }
  }
  const guard = () => {
    sync(); need(root.isConnected !== false && composer(), 'This Work thread was closed')
    const context = JSON.parse(contextText()); need(context.session_key && typeof context.cwd === 'string', 'Choose a Work thread first')
    need(!context.cwd_override || context.cwd_override === context.cwd, 'Save the work folder change first')
    return context
  }
  const action = operation => () => { try { guard(); invalidate(); operation() } catch (error) { status(error.message || 'Table preparation failed; draft kept') } }
  const perform = operation => async () => {
    let ticket
    try {
      const context = guard(); if (pending) return
      const prepared = preview; invalidate(); pending = true; ticket = generation; const owner = ownership()
      const valid = () => need(ticket === generation && owner === ownership() && root.isConnected !== false, 'Table preparation changed or interrupted; draft kept')
      await operation(context, valid, prepared); valid()
    } catch (error) { if ((ticket === undefined || ticket === generation) && root.isConnected !== false) status(error.message || 'Table preparation failed; draft kept') }
    finally { if (ticket === generation) pending = false }
  }
  listen(node('file'), 'change', async () => {
    const files = Array.from(node('file').files || []); invalidate(); if (!files.length) return
    await perform(async (_, valid) => {
      need(files.length === 1, 'Choose one CSV file')
      const table = await readTableFile(files[0]); valid()
      clear(); selection = new TableSelection(table); render()
      status('CSV imported. Inspect records, then select columns and rows in the order the task should see. The draft is unchanged.')
    })()
  })
  for (const key of ['query', 'purpose', 'budget']) listen(node(key), 'input', action(() => { if (key === 'query') render() }))
  listen(composer(), 'input', () => { sync(); invalidate() })
  listen(node('record'), 'change', action(inspect))
  listen(node('column'), 'change', action(() => {}))
  const requireSelection = () => { need(selection, 'Import a CSV table first'); return selection }
  for (const key of ['filter-column', 'filter-operator', 'selected-filter']) listen(node(key), 'change', action(() => {}))
  listen(node('filter-value'), 'input', action(() => {}))
  listen(node('add-filter'), 'click', action(() => {
    const table = requireSelection().table, next = [...filters, { column: Number(node('filter-column').value), operator: node('filter-operator').value, value: node('filter-value').value }]
    matchingRecords(table, node('query').value, next); filters = next; render(); status('Filter added. Inspect all matching records before adding them; existing selection was kept.')
  }))
  listen(node('remove-filter'), 'click', action(() => {
    const index = Number(node('selected-filter').value) - 1; need(index >= 0 && index < filters.length, 'Choose an active filter')
    filters.splice(index, 1); render()
  }))
  listen(node('clear-filters'), 'click', action(() => { filters = []; render(); status('Column filters cleared; selected records kept.') }))
  listen(node('add-matches'), 'click', action(() => {
    const count = requireSelection().addMatching(node('query').value, filters); render()
    status(count + ' matching records added after the existing selection in original source order. Already selected records were kept in their positions. Preview the task before applying.')
  }))
  for (const kind of ['record', 'column']) {
    const plural = kind + 's'
    listen(node('add-' + kind), 'click', action(() => { requireSelection().add(plural, Number(node(kind).value)); render(); status('Selection updated; preview the task before applying it.') }))
    listen(node('selected-' + kind), 'change', action(() => {
      if (kind === 'record' && node('selected-record').value) { node('query').value = ''; filters = []; render(); node('record').value = node('selected-record').value; inspect() }
    }))
    listen(node('remove-' + kind), 'click', action(() => { requireSelection().remove(plural, Number(node('selected-' + kind).value)); render(); status('Item removed from unsent selection. Preview and apply to update an already-applied draft.') }))
    for (const [direction, offset] of [['up', -1], ['down', 1]]) listen(node(kind + '-' + direction), 'click', action(() => { requireSelection().move(plural, Number(node('selected-' + kind).value), offset); render() }))
  }
  listen(node('preview'), 'click', perform(async (context, valid) => {
    const draft = composer().value, packet = await requireSelection().packet(context, node('purpose').value, Number(node('budget').value)); valid()
    const next = await composeTable(draft, packet); valid(); need(composer().value === draft, 'Main draft changed; preview again')
    preview = { draft, next, scope: ownership() }; node('preview-text').textContent = next; node('apply').disabled = false
    status('Full task preview ready: ' + packet.selected_bytes + ' / ' + packet.cell_budget_bytes + ' selected header/cell bytes. Review omitted columns/records and the exact included cells. Nothing has been sent.')
  }))
  listen(node('apply'), 'click', perform(async (_, valid, prepared) => {
    need(prepared && prepared.scope === ownership() && composer().value === prepared.draft, 'Preview the current table and task draft first'); valid()
    composer().value = prepared.next; pending = false
    composer().dispatchEvent(options.inputEvent?.() || new Event('input', { bubbles: true }))
    status('Previewed table placed in the ordinary task draft. Use Plan and Preview, then Promote and Confirm only the work you approve.')
  }))
  listen(node('detach'), 'click', perform(async (_, valid) => {
    const draft = composer().value, next = await removeTable(draft); valid(); need(composer().value === draft, 'Main draft changed; remove again')
    composer().value = next; pending = false; composer().dispatchEvent(options.inputEvent?.() || new Event('input', { bubbles: true }))
    status('Table block removed. Other task text and unsent table selections were kept.')
  }))
  listen(node('clear'), 'click', action(() => { clear(); status('Unsent table cleared; the existing task draft was kept.') }))
  listen(node('cancel'), 'click', () => { invalidate(); status('Pending table preparation interrupted; selections and task draft were kept.') })
  listen(root, 'toggle', () => { if (!root.open) { invalidate(); status('Table panel closed; pending preparation interrupted. The task draft was kept.') } })
  render(); return { sync, get selection() { return selection }, dispose() { invalidate(); events.abort(); delete root.dataset.bound } }
}
export function installTableInput(document) {
  let anchor = null, root = null, binding = null
  const sync = () => {
    const next = document.getElementById('claw-procedure-panel')
    if (next !== anchor || (root && root.isConnected === false)) { binding?.dispose(); root?.remove(); anchor = next; root = next ? mountTableInput(document, next) : null; binding = root ? bindTableInput(document) : null }
    binding?.sync()
  }
  sync(); const observer = new MutationObserver(sync); observer.observe(document.body, { childList: true, subtree: true, characterData: true })
  return () => { observer.disconnect(); binding?.dispose(); root?.remove() }
}
