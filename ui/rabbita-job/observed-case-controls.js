import { readRun, textArtifacts, readSource } from './artifact-rework.js'
import { sourceLines, sourceExcerpt, createObservedCase, exportObservedCases, downloadObservedCases } from './observed-cases.js'
const need = (ok, message) => { if (!ok) throw new Error(message) }
const fields = ['kind', 'name', 'input', 'revised', 'required', 'forbidden', 'start', 'end']
export function mountObservedCases(document, anchor) {
  const panel = document.createElement('details'); panel.id = 'claw-cases-panel'; panel.className = 'procedure-panel'
  const add = (tag, key, text) => { const node = document.createElement(tag); if (key) node.id = 'claw-cases-' + key; node.textContent = text; panel.appendChild(node); return node }
  const button = (key, text) => { const node = add('button', key, text); node.type = 'button' }
  add('summary', '', 'Teach from observed outputs')
  add('p', '', 'Turn exact retained outputs into 1–6 operator-labeled examples for MoonBook correction rehearsal. Choose useful or adverse yourself; runtime success does not decide either. This exports a local CSV for explicit import, without creating an accepted lesson.')
  button('load', 'Load linked case outputs')
  const choiceLabel = add('label', '', 'Retained output'); choiceLabel.htmlFor = 'claw-cases-choice'; add('select', 'choice', '')
  button('inspect', 'Inspect case source')
  add('pre', 'evidence', 'Choose a terminal linked run and inspect a retained UTF-8 output of at most 32 KiB.')
  add('pre', 'original', '')
  for (const [key, title] of [['start', 'First source line'], ['end', 'Last source line']]) { const label = add('label', '', title); label.htmlFor = 'claw-cases-' + key; const input = add('input', key, ''); input.type = 'number'; input.min = '1'; input.step = '1' }
  button('excerpt', 'Preview exact source lines')
  add('pre', 'excerpt-preview', '')
  const kindLabel = add('label', '', 'Observed outcome'); kindLabel.htmlFor = 'claw-cases-kind'; const kind = add('select', 'kind', '')
  for (const [value, text] of [['', 'Choose an observed outcome'], ['useful', 'Useful example'], ['adverse', 'Adverse example']]) { const option = document.createElement('option'); option.value = value; option.textContent = text; kind.appendChild(option) }
  for (const [key, title, max] of [['name', 'Case name', 80], ['input', 'Observed task input (copy the actual task)', 8192], ['revised', 'Revised output (optional; leave blank until available)', 8192], ['required', 'Required literal fragments (one per line)', 5140], ['forbidden', 'Forbidden literal fragments (one per line)', 5140]]) {
    const label = add('label', '', title); label.htmlFor = 'claw-cases-' + key; const node = add('textarea', key, ''); node.maxLength = max
  }
  button('add', 'Add inspected case')
  add('div', 'list', '')
  button('preview', 'Preview MoonBook case CSV')
  add('pre', 'csv', '')
  button('download', 'Download inspected case CSV')
  button('cancel', 'Cancel pending case read')
  button('clear', 'Clear case set')
  const status = add('p', 'status', 'Unexported cases remain only in this page and current work context; reload discards them.'); status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite')
  add('p', '', 'In MoonBook, open an existing lesson correction → contrasting revision rehearsal → Import a CSV teaching-case set. Open the CSV as text, then paste, preview and explicitly import it. Formula-looking data is preserved literally, not neutralized for spreadsheets. Book requires useful and adverse coverage plus revised outputs for comparison. Literal checks are narrow operator observations; review remains separate. Source identity is included in each case name as text, not Book-verified provenance. Review private text before sharing the file.')
  anchor.insertAdjacentElement('afterend', panel); return panel
}
export function bindObservedCases(document, options = {}) {
  const node = key => document.getElementById('claw-cases-' + key), root = node('panel')
  if (!root || root.dataset.bound) return null
  root.dataset.bound = 'true'
  const contextText = () => document.getElementById('claw-procedure-context')?.textContent || ''
  const transport = options.transport || (() => globalThis.__moonclawTransport)
  const base = () => transport()?.base?.() || '', epoch = () => transport()?.epoch?.() || 0
  const events = new AbortController(), listen = (target, type, fn) => target.addEventListener(type, fn, { signal: events.signal })
  let detail = null, source = null, cases = [], preview = '', generation = 0, pending = false, controller = null, scope = contextText(), gateway = base(), access = epoch()
  const status = message => { if (node('status').textContent !== message) node('status').textContent = message }
  const cancel = () => { generation++; pending = false; controller?.abort(); controller = null }
  const invalidate = () => { preview = ''; node('csv').textContent = '' }
  const renderCases = () => {
    node('list').replaceChildren()
    for (const item of cases) {
      const section = document.createElement('details'), summary = document.createElement('summary'), text = document.createElement('pre'), remove = document.createElement('button')
      summary.textContent = item.row.kind + ' · ' + item.row.name; text.textContent = JSON.stringify(item.row, null, 2); remove.textContent = 'Remove case ' + item.fields.name; remove.type = 'button'
      remove.addEventListener('click', () => { sync(); if (!cases.includes(item)) return; cancel(); cases = cases.filter(entry => entry !== item); invalidate(); renderCases(); status('Case removed. Preview the changed set again.') }, { signal: events.signal })
      section.appendChild(summary); section.appendChild(text); section.appendChild(remove); node('list').appendChild(section)
    }
  }
  const clearSource = () => { detail = null; source = null; node('choice').replaceChildren(); node('original').textContent = ''; node('excerpt-preview').textContent = ''; node('evidence').textContent = 'Load and inspect the current linked output.' }
  const clear = () => { cancel(); clearSource(); cases = []; invalidate(); renderCases(); for (const key of fields) node(key).value = '' }
  const sync = () => { if (scope !== contextText() || gateway !== base() || access !== epoch()) { clear(); scope = contextText(); gateway = base(); access = epoch(); status('Work thread, run, folder or access changed. The old case set was cleared; load the current output.') } }
  const get = async (url, signal) => { const response = await (options.fetch || globalThis.fetch)(url, { cache: 'no-store', redirect: 'error', signal }); const result = await response.json(); need(response.ok, result.error?.message || 'Could not read retained output'); return result }
  const run = async (ctx, base, signal) => readRun(await get(base + '/v1/jobs/runs/' + encodeURIComponent(ctx.run_id), signal), ctx)
  const artifact = async (base, id, detail, signal) => readSource(await get(base + '/v1/artifacts/' + encodeURIComponent(id), signal), detail, id)
  const perform = operation => async () => {
    sync(); if (pending) return
    pending = true; const ticket = ++generation, text = contextText(), startBase = base(), startEpoch = epoch(); controller = new AbortController(); const signal = controller.signal
    const valid = () => need(ticket === generation && root.isConnected !== false && text === contextText() && startBase === base() && startEpoch === epoch() && !signal.aborted, 'Case context changed; operation cancelled')
    try { const ctx = JSON.parse(text); need(startBase && ctx.run_id, 'Select a work thread with a linked run and connect the gateway'); need(!ctx.cwd_override || ctx.cwd_override === ctx.cwd, 'Save the work folder change first'); await operation(ctx, startBase, signal, valid); valid() }
    catch (error) { if (ticket === generation && root.isConnected !== false) status(error.message || 'Could not prepare cases') }
    finally { if (ticket === generation) { pending = false; controller = null } }
  }
  const selectedFields = () => ({ ...Object.fromEntries(fields.map(key => [key, node(key).value])), start: Number(node('start').value), end: Number(node('end').value) })
  listen(node('load'), 'click', perform(async (ctx, base, signal, valid) => {
    clearSource(); const fresh = await run(ctx, base, signal); valid(); detail = fresh
    const placeholder = document.createElement('option'); placeholder.value = ''; placeholder.textContent = 'Choose an output'; node('choice').appendChild(placeholder)
    for (const item of textArtifacts(detail)) { const option = document.createElement('option'); option.value = item.id; option.textContent = item.id + ' · revision ' + item.version; node('choice').appendChild(option) }
    status(`Run ${detail.run.id}: ${detail.run.status}. Choose and inspect an output; queued cases are preserved.`)
  }))
  listen(node('choice'), 'change', () => { sync(); cancel(); source = null; node('original').textContent = ''; node('excerpt-preview').textContent = ''; status('Inspect the selected source before adding a case.') })
  listen(node('inspect'), 'click', perform(async (ctx, base, signal, valid) => {
    need(detail, 'Load linked outputs first'); source = null; node('original').textContent = ''; node('excerpt-preview').textContent = ''
    const selected = await artifact(base, node('choice').value, detail, signal); valid(); source = selected
    node('original').textContent = source.content_utf8; node('start').value = '1'; node('end').value = String(sourceLines(source).length)
    node('evidence').textContent = `${source.run_id} / ${source.artifact_id} @${source.version}\n${source.sha256}\nRecorded run status: ${detail.run.status}. This does not establish usefulness or acceptance.`
    status('Select source lines up to 8,192 characters, name the observed task and outcome, and specify literal checks.')
  }))
  listen(node('excerpt'), 'click', () => { sync(); try { need(source, 'Inspect a source first'); node('excerpt-preview').textContent = sourceExcerpt(source, Number(node('start').value), Number(node('end').value)); status('Exact source lines shown. No text was truncated or normalized.') } catch (error) { node('excerpt-preview').textContent = ''; status(error.message) } })
  for (const key of fields) listen(node(key), key === 'kind' ? 'change' : 'input', () => { sync(); cancel(); invalidate(); if (['start', 'end'].includes(key)) node('excerpt-preview').textContent = ''; status('Inputs changed. Add the inspected case, then preview the case set.') })
  listen(node('add'), 'click', perform(async (ctx, base, signal, valid) => {
    need(source, 'Inspect a retained source first'); need(cases.length < 6, 'Export at most six cases')
    const item = await createObservedCase(ctx, detail, source, selectedFields()); valid()
    need(!cases.some(other => other.row.input.trim() === item.row.input.trim()), 'This task input is already in the case set. Remove its old case before replacing it.')
    cases.push(item); invalidate(); renderCases(); status(`${cases.length} observed case(s) queued. Preview the exact CSV before downloading.`)
  }))
  listen(node('preview'), 'click', perform(async (ctx, base, signal, valid) => { const csv = await exportObservedCases(cases); valid(); preview = csv; node('csv').textContent = csv; status('Review the exact case CSV. Download rechecks every retained source before requesting a local file.') }))
  listen(node('download'), 'click', perform(async (ctx, base, signal, valid) => {
    need(preview, 'Preview the current case CSV before downloading'); const exact = preview, selected = [...cases]
    const freshRun = await run(ctx, base, signal); valid()
    for (const item of selected) {
      need(freshRun.run.status === item.detail.run.status, 'Run status changed; inspect and rebuild the case set')
      const fresh = await artifact(base, item.source.artifact_id, freshRun, signal); valid()
      need(JSON.stringify(fresh) === JSON.stringify(item.source), 'A selected source changed; the old case set is preserved. Remove that case and inspect the new revision.')
    }
    need(await exportObservedCases(selected) === exact, 'Case preview changed; preview again'); valid()
    ;(options.download || (csv => downloadObservedCases(csv, document)))(exact)
    status('Local CSV download requested. Check browser downloads, then paste into MoonBook’s CSV teaching-case import and review there. No lesson was submitted or accepted.')
  }))
  listen(node('cancel'), 'click', () => { cancel(); status('Pending case read cancelled. Current source, fields and queued cases are preserved.') })
  listen(node('clear'), 'click', () => { clear(); status('Case set cleared. No files, runs or Book records were changed.') })
  return { sync, get cases() { return structuredClone(cases) }, get source() { return source }, dispose() { cancel(); events.abort(); delete root.dataset.bound } }
}
export function installObservedCases(document) {
  let anchor = null, root = null, binding = null
  const sync = () => { const next = document.getElementById('claw-procedure-panel'); if (next !== anchor || (root && root.isConnected === false)) { binding?.dispose(); root?.remove(); anchor = next; root = next ? mountObservedCases(document, next) : null; binding = root ? bindObservedCases(document) : null } binding?.sync() }
  sync(); const observer = new MutationObserver(sync); observer.observe(document.body, { childList: true, subtree: true, characterData: true })
  return () => { observer.disconnect(); binding?.dispose(); root?.remove() }
}
