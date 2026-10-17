import { readTableFile, positions, compareTables, ChangeSelection, composeChanges, removeChanges } from './table-changes.js'

const need = (ok, message) => { if (!ok) throw new Error(message) }
export function mountTableChanges(document, anchor) {
  const root = document.createElement('details'); root.id = 'claw-changes-panel'; root.className = 'procedure-panel'
  const add = (tag, key, text = '') => { const node = document.createElement(tag); if (key) node.id = 'claw-changes-' + key; node.textContent = text; root.appendChild(node); return node }
  const field = (tag, key, label) => { const name = add('label', '', label); name.setAttribute('for', 'claw-changes-' + key); return add(tag, key) }
  const button = (key, label) => { const node = add('button', key, label); node.type = 'button'; return node }
  add('summary', '', 'Prepare a task from CSV changes')
  add('p', '', 'Compare two frozen local snapshots using identifying columns you choose. Inspect and select changes before placing any cells in the ordinary task draft. No files are uploaded and no task starts.')
  for (const side of ['before', 'after']) {
    const file = field('input', side + '-file', side === 'before' ? 'Before CSV snapshot' : 'After CSV snapshot'); file.type = 'file'; file.accept = '.csv,text/csv,text/plain'
    add('pre', side + '-identity', 'No ' + side + ' snapshot imported.')
    field('input', side + '-keys', side + ' identifying column numbers, in matching order (for example 1, 3)')
    field('input', side + '-columns', side + ' comparison column numbers, in matching order')
  }
  add('p', '', 'Columns map pairwise in the entered order, by original position. Headers may be duplicate, blank or renamed. Keys use exact literal cell values; blank or duplicate keys require different identifying columns. No row matches are guessed.')
  button('compare', 'Compare selected columns'); add('p', 'counts')
  const kind = field('select', 'kind', 'Show changes of this kind')
  for (const [value, label] of [['all', 'All changes'], ['changed', 'Changed'], ['added', 'Added'], ['removed', 'Removed']]) { const option = document.createElement('option'); option.value = value; option.textContent = label; kind.appendChild(option) }
  kind.value = 'all'
  field('select', 'record', 'Compared change to inspect'); add('pre', 'record-text'); button('add', 'Add inspected change')
  field('select', 'selected', 'Selected changes in task order'); button('up', 'Move selected change up'); button('down', 'Move selected change down'); button('remove', 'Remove selected change')
  field('textarea', 'purpose', 'Why should these changes inform this task?')
  const budget = field('input', 'budget', 'Selected headers, keys and cells: UTF-8 byte budget'); budget.type = 'number'; budget.min = '1024'; budget.max = '16384'; budget.step = '1'; budget.value = '8192'
  add('pre', 'selection'); button('preview', 'Preview selected changes in task'); add('pre', 'preview-text'); button('apply', 'Put previewed changes in draft').disabled = true
  button('detach', 'Remove CSV change block from draft'); button('clear', 'Clear unsent CSV comparison'); button('cancel', 'Interrupt preparation')
  const status = add('p', 'status', 'Import both snapshots and choose columns. Nothing is selected automatically. Unsent comparison is lost on reload or leaving this Work thread.'); status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite')
  add('p', '', 'Each input uses the existing 256 KiB / 2000-record / 128-column CSV limits. Choose at most 32 distinct key and comparison columns per side, and 50 changes per task. Changes to omitted columns are not compared. Formulas and dates remain literal strings. Review through the existing Plan, Preview, Promote and Confirm controls.')
  anchor.insertAdjacentElement('afterend', root); return root
}

export function bindTableChanges(document, options = {}) {
  const node = key => document.getElementById('claw-changes-' + key), root = node('panel')
  if (!root || root.dataset.bound) return null
  root.dataset.bound = 'true'
  const composer = () => document.getElementById('claw-procedure-composer'), contextText = () => document.getElementById('claw-procedure-context')?.textContent || ''
  const transport = options.transport || (() => globalThis.__moonclawTransport), ownership = () => JSON.stringify([contextText(), transport()?.base?.() || '', transport()?.epoch?.() || 0])
  const events = new AbortController(), listen = (target, type, handler) => target.addEventListener(type, handler, { signal: events.signal })
  let before = null, after = null, selection = null, scope = ownership(), generation = 0, pending = false, preview = null
  const status = message => { if (node('status').textContent !== message) node('status').textContent = message }
  const invalidate = () => { generation++; pending = false; preview = null; node('preview-text').textContent = ''; node('apply').disabled = true }
  const choices = (key, entries) => {
    const target = node(key), old = target.value; target.replaceChildren()
    for (const [value, label] of [['', 'Choose…'], ...entries]) { const option = document.createElement('option'); option.value = value; option.textContent = label; target.appendChild(option) }
    target.value = entries.some(([value]) => value === old) ? old : ''
  }
  const label = row => row.kind + ' · key ' + JSON.stringify(row.key)
  const inspect = () => {
    const row = selection?.comparison.records.find(row => row.id === node('record').value)
    node('record-text').textContent = row ? JSON.stringify({ key_columns: selection.comparison.keys, columns: selection.comparison.columns, change: row }, null, 2) : 'Choose a change to inspect its exact mapped headers, key, before/after cells and original record/line positions.'
  }
  const render = () => {
    for (const [side, table] of [['before', before], ['after', after]]) node(side + '-identity').textContent = table ? table.source.name + '\nSHA-256: ' + table.source.sha256 + '\n' + table.source.bytes + ' bytes · ' + table.records.length + ' records\n' + table.header.cells.map((header, index) => 'Column ' + (index + 1) + ': ' + JSON.stringify(header)).join('\n') : 'No ' + side + ' snapshot imported.'
    const rows = selection?.comparison.records || [], kind = node('kind').value
    choices('record', rows.filter(row => kind === 'all' || row.kind === kind).map(row => [row.id, label(row)]))
    choices('selected', (selection?.ids || []).map((id, index) => [id, (index + 1) + '. ' + label(rows.find(row => row.id === id))]))
    node('counts').textContent = selection ? ['added', 'removed', 'changed'].map(kind => rows.filter(row => row.kind === kind).length + ' ' + kind).join(' · ') + ' · ' + selection.comparison.unchanged + ' unchanged in the compared columns. Nothing was matched by row position.' : 'Choose corresponding key and comparison columns, then compare.'
    node('selection').textContent = selection ? selection.ids.length + ' selected changes. Keys and only the mapped comparison columns enter the task.' : ''
    inspect()
  }
  const clear = () => { before = null; after = null; selection = null; for (const side of ['before', 'after']) { node(side + '-file').value = ''; node(side + '-keys').value = ''; node(side + '-columns').value = '' } node('purpose').value = ''; node('budget').value = '8192'; node('kind').value = 'all'; render() }
  const sync = () => { if (scope !== ownership()) { invalidate(); scope = ownership(); clear(); status('Work thread, folder or gateway access changed. Choose CSV snapshots again; the main draft was kept.') } }
  const guard = () => {
    sync(); need(root.isConnected !== false && composer(), 'This Work thread was closed')
    const context = JSON.parse(contextText()); need(context.session_key && typeof context.cwd === 'string', 'Choose a Work thread first'); need(!context.cwd_override || context.cwd_override === context.cwd, 'Save the work folder change first'); return context
  }
  const action = operation => () => { try { guard(); invalidate(); operation() } catch (error) { status(error.message || 'CSV change preparation failed; draft kept') } }
  const perform = operation => async () => {
    let ticket
    try {
      const context = guard(); if (pending) return
      const prepared = preview; invalidate(); pending = true; ticket = generation; const owner = ownership()
      const valid = () => need(ticket === generation && owner === ownership() && root.isConnected !== false, 'CSV change preparation changed or interrupted; draft kept')
      await operation(context, valid, prepared); valid()
    } catch (error) { if ((ticket === undefined || ticket === generation) && root.isConnected !== false) status(error.message || 'CSV change preparation failed; draft kept') }
    finally { if (ticket === generation) pending = false }
  }
  for (const side of ['before', 'after']) {
    listen(node(side + '-file'), 'change', async () => {
      const files = Array.from(node(side + '-file').files || []); invalidate(); if (!files.length) return
      await perform(async (_, valid) => {
        need(files.length === 1, 'Choose one CSV file for each snapshot'); const table = await readTableFile(files[0]); valid()
        if (side === 'before') before = table; else after = table
        selection = null; render(); status('Snapshot imported. Review corresponding column positions and compare again. The main draft is unchanged.')
      })()
    })
    for (const name of ['keys', 'columns']) listen(node(side + '-' + name), 'input', action(() => { selection = null; render() }))
  }
  listen(node('compare'), 'click', action(() => {
    need(before && after, 'Import both CSV snapshots first')
    const comparison = compareTables(before, after, { beforeKeys: positions(node('before-keys').value), afterKeys: positions(node('after-keys').value), beforeColumns: positions(node('before-columns').value), afterColumns: positions(node('after-columns').value) })
    selection = new ChangeSelection(comparison); render(); status('Compared exact literal values. Inspect and select changes in the order your task needs; unchanged records are not offered.')
  }))
  for (const name of ['purpose', 'budget']) listen(node(name), 'input', action(() => {}))
  listen(node('kind'), 'change', action(render)); listen(node('record'), 'change', action(inspect))
  listen(node('selected'), 'change', action(() => { node('kind').value = 'all'; render(); node('record').value = node('selected').value; inspect() }))
  const current = () => { need(selection, 'Compare the current snapshots and columns first'); return selection }
  listen(node('add'), 'click', action(() => { current().add(node('record').value); render() }))
  listen(node('remove'), 'click', action(() => { current().remove(node('selected').value); render() }))
  for (const [name, offset] of [['up', -1], ['down', 1]]) listen(node(name), 'click', action(() => { current().move(node('selected').value, offset); render() }))
  listen(composer(), 'input', () => { sync(); invalidate() })
  listen(node('preview'), 'click', perform(async (context, valid) => {
    const draft = composer().value, packet = await current().packet(context, node('purpose').value, Number(node('budget').value)); valid()
    const next = await composeChanges(draft, packet); valid(); need(composer().value === draft, 'Main draft changed; preview again')
    preview = { draft, next, scope: ownership() }; node('preview-text').textContent = next; node('apply').disabled = false; status('Complete task preview ready: ' + packet.selected_bytes + ' / ' + packet.cell_budget_bytes + ' selected UTF-8 bytes. Nothing has been sent.')
  }))
  listen(node('apply'), 'click', perform(async (_, valid, prepared) => {
    need(prepared && prepared.scope === ownership() && composer().value === prepared.draft, 'Preview the current CSV changes and task draft first'); valid(); composer().value = prepared.next; pending = false
    composer().dispatchEvent(options.inputEvent?.() || new Event('input', { bubbles: true })); status('Previewed changes placed in the ordinary draft. Review work through Plan, Preview, Promote and Confirm.')
  }))
  listen(node('detach'), 'click', perform(async (_, valid) => { const draft = composer().value, next = await removeChanges(draft); valid(); need(composer().value === draft, 'Main draft changed; remove again'); composer().value = next; pending = false; composer().dispatchEvent(options.inputEvent?.() || new Event('input', { bubbles: true })); status('CSV change block removed. Other draft text and unsent comparison were kept.') }))
  listen(node('clear'), 'click', action(() => { clear(); status('Unsent comparison cleared; the task draft was kept.') }))
  listen(node('cancel'), 'click', () => { invalidate(); status('Pending preparation interrupted; snapshots, selections and draft kept.') })
  listen(root, 'toggle', () => { if (!root.open) invalidate() })
  render(); return { sync, get selection() { return selection }, get before() { return before }, get after() { return after }, dispose() { invalidate(); events.abort(); delete root.dataset.bound } }
}

export function installTableChanges(document) {
  let anchor = null, root = null, binding = null
  const sync = () => { const next = document.getElementById('claw-procedure-panel'); if (next !== anchor || (root && root.isConnected === false)) { binding?.dispose(); root?.remove(); anchor = next; root = next ? mountTableChanges(document, next) : null; binding = root ? bindTableChanges(document) : null } binding?.sync() }
  sync(); const observer = new MutationObserver(sync); observer.observe(document.body, { childList: true, subtree: true, characterData: true })
  return () => { observer.disconnect(); binding?.dispose(); root?.remove() }
}
