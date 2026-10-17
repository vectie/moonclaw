import { readJSONFile } from './json-input.js'
import { JSONChanges, composeChanges, removeChanges } from './json-changes.js'
const need = (ok, message) => { if (!ok) throw new Error(message) }
export function mountJSONChanges(document, anchor) {
  const root = document.createElement('details'); root.id = 'claw-json-changes-panel'; root.className = 'panel'
  const add = (tag, key, text = '') => { const n = document.createElement(tag); n.id = 'claw-json-changes-' + key; n.textContent = text; root.appendChild(n); return n }
  const field = (tag, key, title) => { add('label', key + '-label', title).htmlFor = 'claw-json-changes-' + key; return add(tag, key) }
  const button = (key, title) => { const n = add('button', key, title); n.type = 'button'; return n }
  add('summary', 'title', 'Compare explicitly chosen JSON locations')
  add('p', 'help', 'Import old and new local frozen snapshots, then explicitly choose a document and JSON Pointer on each side. Empty pointer means root. Use ~1 for / and ~0 for ~. A missing path is absent, not null. No pairing, record identity or array matching is inferred. JSON Lines document numbers are locations only. Nothing is sent or executed here.')
  for (const side of ['old', 'new']) {
    const format = field('select', side + '-format', side + ' input format (for next import)')
    for (const value of ['json', 'jsonl']) { const o = document.createElement('option'); o.value = value; o.textContent = value; format.appendChild(o) }; format.value = 'json'
    const file = field('input', side + '-file', 'Open ' + side + ' snapshot'); file.type = 'file'; file.accept = '.json,.jsonl,.ndjson,application/json,text/plain'
    add('pre', side + '-identity', 'No snapshot imported.')
    const doc = field('input', side + '-document', side + ' document number (explicitly choose, starting at 1)'); doc.type = 'number'; doc.min = '1'
    field('input', side + '-pointer', side + ' JSON Pointer (empty = root)')
  }
  button('inspect', 'Inspect this explicit pair'); add('pre', 'inspection'); button('add', 'Choose inspected change')
  field('select', 'selected', 'Chosen changes'); button('remove', 'Remove chosen change'); add('pre', 'selection')
  field('textarea', 'purpose', 'Why should these changes inform the task?')
  const budget = field('input', 'budget', 'Combined old/new selected JSON bytes (1024–16384)'); budget.type = 'number'; budget.min = '1024'; budget.max = '16384'; budget.value = '8192'
  button('preview', 'Preview chosen changes in task'); add('pre', 'preview-text'); button('apply', 'Put previewed changes in draft').disabled = true
  button('detach', 'Remove comparison block from draft'); button('clear', 'Clear unsent comparison'); button('cancel', 'Interrupt preparation')
  const status = add('p', 'status', 'No changes chosen. Exact text comparison includes number spelling, string escapes and subtree whitespace. Choosing an object or array includes its entire subtree. Up to 256 KiB per source and 32 chosen changes.'); status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite')
  anchor.insertAdjacentElement('afterend', root); return root
}
export function bindJSONChanges(document, options = {}) {
  const node = key => document.getElementById('claw-json-changes-' + key), root = node('panel')
  if (!root || root.dataset.bound) return null
  root.dataset.bound = 'true'
  const composer = () => document.getElementById('claw-procedure-composer')
  const contextText = () => document.getElementById('claw-procedure-context')?.textContent || ''
  const transport = options.transport || (() => globalThis.__moonclawTransport)
  const ownership = () => JSON.stringify([contextText(), transport()?.base?.() || '', transport()?.epoch?.() || 0])
  const events = new AbortController(), listen = (target, type, handler) => target.addEventListener(type, handler, { signal: events.signal })
  let snapshots = { old: null, new: null }, selection = null, inspected = null, preview = null, scope = ownership(), generation = 0, pending = false
  const status = message => { if (node('status').textContent !== message) node('status').textContent = message }
  const invalidate = () => { generation++; pending = false; preview = null; node('preview-text').textContent = ''; node('apply').disabled = true }
  const forgetInspection = () => { inspected = null; node('inspection').textContent = '' }
  const paths = () => [Number(node('old-document').value), node('old-pointer').value, Number(node('new-document').value), node('new-pointer').value]
  const render = () => {
    for (const side of ['old','new']) { const s = snapshots[side]; node(side + '-identity').textContent = s ? s.source.name + ' · ' + s.format + ' · ' + s.documents + ' documents · ' + s.source.bytes + ' bytes\n' + s.source.sha256 + '\nFrozen; authenticity and disk freshness unverified.' : 'No snapshot imported.' }
    const target = node('selected'), prior = target.value; target.replaceChildren()
    for (const [i, change] of (selection?.changes || []).entries()) { const o = document.createElement('option'); o.value = String(i); o.textContent = (i + 1) + '. ' + change.status + ': document ' + change.old.document + ' ' + (change.old.pointer || '(root)') + ' → document ' + change.new.document + ' ' + (change.new.pointer || '(root)'); target.appendChild(o) }
    target.value = prior; node('selection').textContent = JSON.stringify(selection?.changes || [], null, 2)
  }
  const clear = () => { snapshots = { old: null, new: null }; selection = null; forgetInspection(); for (const key of ['old-file','new-file','old-document','new-document','old-pointer','new-pointer','purpose']) node(key).value = ''; render() }
  const sync = () => { if (scope !== ownership()) { invalidate(); scope = ownership(); clear(); status('Work context or gateway changed. Import snapshots again; main draft kept.') } }
  const guard = () => { sync(); need(root.isConnected !== false && composer(), 'This Work thread was closed'); const ctx = JSON.parse(contextText()); need(ctx.session_key && typeof ctx.cwd === 'string', 'Choose a Work thread first'); need(!ctx.cwd_override || ctx.cwd_override === ctx.cwd, 'Save the work folder change first'); return ctx }
  const action = operation => () => { try { guard(); invalidate(); operation() } catch (e) { status(e.message || 'Comparison failed; draft kept') } }
  const perform = operation => async () => {
    let ticket
    try {
      const ctx = guard(); if (pending) return
      const prepared = preview; invalidate(); pending = true; ticket = generation; const owner = ownership()
      const valid = () => need(ticket === generation && owner === ownership() && root.isConnected !== false, 'Comparison changed or interrupted; draft kept')
      await operation(ctx, valid, prepared); valid()
    } catch (e) { if ((ticket === undefined || ticket === generation) && root.isConnected !== false) status(e.message || 'Comparison failed; draft kept') }
    finally { if (ticket === generation) pending = false }
  }
  for (const side of ['old','new']) {
    listen(node(side + '-file'), 'change', async () => {
      const files = Array.from(node(side + '-file').files || []), format = node(side + '-format').value; invalidate(); forgetInspection(); if (!files.length) return
      await perform(async (_, valid) => { need(files.length === 1, 'Choose one snapshot'); const snapshot = await readJSONFile(files[0], format); valid(); snapshots[side] = snapshot; selection = snapshots.old && snapshots.new ? new JSONChanges(snapshots.old, snapshots.new) : null; node(side + '-document').value = ''; node(side + '-pointer').value = ''; render(); status('Frozen snapshot imported. Existing unsent pairs cleared. Explicitly choose both document numbers and pointers; draft kept.') })()
    })
    listen(node(side + '-format'), 'change', action(() => { forgetInspection(); status('Format applies to the next import. Existing snapshot keeps its format.') }))
    for (const key of ['document','pointer']) listen(node(side + '-' + key), 'input', action(forgetInspection))
  }
  listen(composer(), 'input', () => { sync(); invalidate() })
  for (const key of ['purpose','budget']) listen(node(key), 'input', action(() => {}))
  listen(node('selected'), 'change', action(() => {}))
  listen(node('inspect'), 'click', action(() => { need(selection, 'Import both snapshots first'); inspected = selection.inspect(...paths()); node('inspection').textContent = JSON.stringify(inspected, null, 2); status('Inspect exact types and tokens. Only added, removed or changed pairs can be chosen; no identity is inferred.') }))
  listen(node('add'), 'click', action(() => { need(selection && inspected && JSON.stringify(inspected) === JSON.stringify(selection.inspect(...paths())), 'Inspect the current explicit pair first'); selection.add(...paths()); render(); status('Chosen change added. Preview to update the ordinary task draft.') }))
  listen(node('remove'), 'click', action(() => { need(selection && node('selected').value !== '', 'Choose a change to remove'); selection.remove(Number(node('selected').value)); render() }))
  listen(node('preview'), 'click', perform(async (ctx, valid) => {
    need(selection, 'Import both snapshots first'); const draft = composer().value, packet = await selection.packet(ctx, node('purpose').value, Number(node('budget').value)); valid()
    const next = await composeChanges(draft, packet); valid(); need(composer().value === draft, 'Task changed; preview again'); preview = { draft, next, scope: ownership() }; node('preview-text').textContent = next; node('apply').disabled = false; status('Complete task preview ready. Only chosen pairs are included. Nothing sent.')
  }))
  listen(node('apply'), 'click', perform(async (_, valid, prepared) => {
    need(prepared && prepared.scope === ownership() && composer().value === prepared.draft, 'Preview the current comparison and draft first'); valid(); composer().value = prepared.next; pending = false; composer().dispatchEvent(options.inputEvent?.() || new Event('input', { bubbles: true })); status('Chosen changes placed in ordinary draft. Use Plan and Preview, then Promote and Confirm only approved work.')
  }))
  listen(node('detach'), 'click', perform(async (_, valid) => { const draft = composer().value, next = await removeChanges(draft); valid(); need(composer().value === draft, 'Task changed; remove again'); composer().value = next; pending = false; composer().dispatchEvent(options.inputEvent?.() || new Event('input', { bubbles: true })); status('Comparison block removed; other task text kept.') }))
  listen(node('clear'), 'click', action(() => { clear(); status('Unsent comparison cleared; main task draft kept.') }))
  listen(node('cancel'), 'click', () => { invalidate(); status('Preparation interrupted; draft kept.') })
  listen(root, 'toggle', () => { if (!root.open) invalidate() })
  render(); return { sync, get selection() { return selection }, dispose() { invalidate(); events.abort(); delete root.dataset.bound } }
}
export function installJSONChanges(document) {
  let anchor = null, root = null, binding = null
  const sync = () => { const next = document.getElementById('claw-procedure-panel'); if (next !== anchor || (root && root.isConnected === false)) { binding?.dispose(); root?.remove(); anchor = next; root = next ? mountJSONChanges(document, next) : null; binding = root ? bindJSONChanges(document) : null }; binding?.sync() }
  sync(); const observer = new MutationObserver(sync); observer.observe(document.body, { childList: true, subtree: true, characterData: true })
  return () => { observer.disconnect(); binding?.dispose(); root?.remove() }
}
