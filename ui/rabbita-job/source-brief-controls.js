import { SourceBrief, readLocalFiles, findLines, composeBrief, removeBrief } from './source-brief.js'
import { compareSources, comparisonCurrent, changeRange, formatChange } from './source-comparison.js'
import { textArtifacts } from './artifact-rework.js'
import { sourceKey, retainedReader } from './retained-sources.js'
import { exportSourceProject, readSourceProjectFile, checkSourceProjectContext, describeSourceProject, downloadSourceProject } from './source-project.js'
import { mountSourceRefresh, bindSourceRefresh } from './source-refresh-controls.js'
const need = (ok, message) => { if (!ok) throw new Error(message) }
export function mountSourceBrief(document, anchor) {
  const root = document.createElement('details'); root.id = 'claw-sources-panel'; root.className = 'procedure-panel'
  const add = (tag, key, value) => { const node = document.createElement(tag); if (key) node.id = 'claw-sources-' + key; node.textContent = value; root.appendChild(node); return node }
  const field = (tag, key, title) => { const label = add('label', '', title); label.htmlFor = 'claw-sources-' + key; return add(tag, key, '') }
  const button = (key, label) => { const node = add('button', key, label); node.type = 'button'; return node }
  add('summary', '', 'Choose focused source excerpts')
  add('p', '', 'Bring local UTF-8 text and passages from this thread’s retained outputs into the next task. Inspect numbered lines, keep the relevant ranges, and preview exactly what you will add. Unsent work stays in this tab unless you explicitly download a source project.')
  const files = field('input', 'files', 'Import local text files (up to eight, 256 KiB each)'); files.type = 'file'; files.multiple = true
  button('load-retained', 'Load linked run outputs')
  field('select', 'retained', 'Retained text output (up to 32 KiB)')
  button('inspect-retained', 'Inspect and add retained source')
  add('p', 'retained-info', 'Load the linked terminal run to choose exact retained text. Local files do not require a gateway.')
  add('h4', '', 'Find changed passages before planning the next task')
  add('p', '', 'Compare two distinct imported snapshots. Before and after are your chosen ordering, not a claim of chronology or correctness. Local files stay frozen; retained sources are reread for comparison and range selection.')
  field('select', 'compare-before', 'Before snapshot'); field('select', 'compare-after', 'After snapshot')
  button('compare', 'Compare imported snapshots')
  add('p', 'compare-info', 'Import two snapshots to find changed passages.')
  field('select', 'change', 'Changed passage')
  add('pre', 'change-text', '')
  button('choose-before', 'Inspect before lines in excerpt editor').disabled = true
  button('choose-after', 'Inspect after lines in excerpt editor').disabled = true
  field('select', 'source', 'Imported source')
  button('remove-source', 'Remove selected source')
  field('input', 'query', 'Find literal text in this source')
  add('p', 'source-info', 'No source imported.')
  add('pre', 'lines', '')
  for (const [key, title] of [['start', 'First line (inclusive)'], ['end', 'Last line (inclusive)']]) { const node = field('input', key, title); node.type = 'number'; node.min = '1'; node.step = '1'; node.value = '1' }
  field('textarea', 'purpose', 'Why is this excerpt relevant to the task?')
  const budget = field('input', 'budget', 'Excerpt content budget in UTF-8 bytes (not tokens)'); budget.type = 'number'; budget.min = '1024'; budget.max = '16384'; budget.step = '1'; budget.value = '8192'
  button('add', 'Add excerpt')
  field('select', 'excerpt', 'Selected excerpts, in task order')
  button('update', 'Update selected excerpt'); button('up', 'Move excerpt up'); button('down', 'Move excerpt down'); button('remove', 'Remove excerpt')
  add('pre', 'selection', '')
  add('p', 'budget-info', '0 / 8192 selected bytes')
  mountSourceRefresh(document, root)
  const projectPanel = add('details', 'project-panel', '')
  const projectSummary = document.createElement('summary'); projectSummary.textContent = 'Save or reopen source preparation'; projectPanel.appendChild(projectSummary)
  const projectNode = (tag, key, text) => { const element = document.createElement(tag); element.id = 'claw-sources-' + key; element.textContent = text; projectPanel.appendChild(element); return element }
  const projectButton = (key, text) => { const element = projectNode('button', key, text); element.type = 'button'; return element }
  projectNode('p', 'project-help', 'Save all imported text snapshots, excerpt ranges, notes, order and byte budget to a local JSON file. This includes full sources, even text omitted from the task. Review private text before saving or sharing. Reopening first previews the file, then explicitly replaces only the unsent source working set. It never restores a task draft, approval or live-file connection.')
  projectButton('project-preview-save', 'Preview source project for saving')
  projectButton('project-download', 'Download previewed source project').disabled = true
  const projectLabel = projectNode('label', 'project-file-label', 'Open a saved source project (UTF-8 JSON, at most 8 MiB)'); projectLabel.htmlFor = 'claw-sources-project-file'
  const projectFile = projectNode('input', 'project-file', ''); projectFile.type = 'file'; projectFile.accept = '.json,application/json'
  projectNode('p', 'project-info', 'A saved project contains frozen snapshots. File authenticity and disk freshness are unverified.')
  const projectContents = projectNode('details', 'project-contents', ''), projectContentsSummary = document.createElement('summary'), projectText = document.createElement('pre')
  projectContentsSummary.textContent = 'Inspect complete project JSON, including every source byte'; projectContents.appendChild(projectContentsSummary)
  projectText.id = 'claw-sources-project-text'; projectContents.appendChild(projectText)
  projectButton('project-restore', 'Replace working set with opened project').disabled = true
  button('preview', 'Preview source brief'); add('pre', 'preview-text', '')
  button('apply', 'Put previewed sources in draft').disabled = true
  button('detach', 'Remove source block from draft')
  button('cancel', 'Interrupt pending preparation')
  const status = add('p', 'status', 'Unsent sources and excerpts are lost on reload or leaving this Work thread unless you save a source project.'); status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite')
  add('p', '', 'Local snapshots are not live disk reads. Retained revisions are reread before preview and apply; their correctness and acceptance are not established. Omitted lines may contain relevant context. The byte budget covers selected text only; metadata and other runtime context are additional. Use ordinary Plan, Preview, Promote and Confirm to review work and authority.')
  anchor.insertAdjacentElement('afterend', root); return root
}
export function bindSourceBrief(document, options = {}) {
  const node = key => document.getElementById('claw-sources-' + key), root = node('panel')
  if (!root || root.dataset.bound) return null
  root.dataset.bound = 'true'
  const composer = () => document.getElementById('claw-procedure-composer')
  const contextText = () => document.getElementById('claw-procedure-context')?.textContent || ''
  const transport = options.transport || (() => globalThis.__moonclawTransport)
  const ownership = () => JSON.stringify([contextText(), transport()?.base?.() || '', transport()?.epoch?.() || 0])
  const events = new AbortController(), listen = (target, type, handler) => target.addEventListener(type, handler, { signal: events.signal })
  let session = new SourceBrief(), scope = ownership(), generation = 0, pending = false, preview = null, detail = null, controller = null, comparison = null, projectPreview = null, refresh = null
  const status = message => { if (node('status').textContent !== message) node('status').textContent = message }
  const invalidate = (keepRefresh = false) => { controller?.abort(); controller = null; generation++; pending = false; preview = null; node('preview-text').textContent = ''; node('apply').disabled = true; projectPreview = null; node('project-text').textContent = ''; node('project-info').textContent = 'Preview a source project to save or reopen it. Saved snapshots have unverified freshness.'; node('project-download').disabled = true; node('project-restore').disabled = true; refresh?.invalidate(keepRefresh) }
  const selectOptions = (target, entries, selected) => {
    target.replaceChildren()
    for (const [value, label] of [['', 'Choose…'], ...entries]) { const option = document.createElement('option'); option.value = value; option.textContent = label; target.appendChild(option) }
    target.value = entries.some(([value]) => value === selected) ? selected : ''
  }
  const clearComparison = () => {
    comparison = null; node('change').replaceChildren(); node('change-text').textContent = ''
    node('choose-before').disabled = true; node('choose-after').disabled = true
    node('compare-info').textContent = 'Choose two snapshots and compare their exact changed lines.'
  }
  const comparedSources = () => [session.source(node('compare-before').value), session.source(node('compare-after').value)]
  const changeView = () => {
    const chosen = node('change').value === '' ? null : comparison?.changes[Number(node('change').value)]
    node('change-text').textContent = chosen ? formatChange(chosen) : ''
    for (const side of ['before', 'after']) node('choose-' + side).disabled = !chosen?.[side]
  }
  const sourceView = () => {
    const source = session.source(node('source').value)
    if (!source) { node('source-info').textContent = 'No source selected.'; node('lines').textContent = ''; return }
    const found = findLines(source, node('query').value)
    node('source-info').textContent = source.name + (source.provenance ? ' · retained output @' + source.provenance.version + ' · run ' + source.provenance.run_id + ' (' + source.provenance.original_run_status + ') · job ' + source.provenance.job_id + ' · ' : ' · frozen local snapshot · ') + (source.restored_from_project ? 'reopened saved snapshot; freshness unverified · ' : '') + source.bytes + ' bytes · ' + found.total + ' lines\n' + source.sha256 + '\nShowing ' + found.shown.length + ' of ' + found.matches + ' matching lines (first 100). Narrow the search to inspect later lines.'
    node('lines').textContent = found.shown.map(line => line.number + ': ' + line.text.replace(/\r?\n$/, '')).join('\n')
  }
  const render = () => {
    const sources = session.sources.map(file => [sourceKey(file), file.name + (file.provenance ? ' · retained @' + file.provenance.version + ' · run ' + file.provenance.run_id : ' · local')])
    for (const side of ['before', 'after']) selectOptions(node('compare-' + side), sources, node('compare-' + side).value)
    if (comparison && !comparisonCurrent(comparison, ...comparedSources())) clearComparison()
    selectOptions(node('source'), session.sources.map(file => [sourceKey(file), file.name + (file.provenance ? ' · retained @' + file.provenance.version : ' · local') + (file.restored_from_project ? ' · reopened' : '') + ' · ' + file.bytes + ' bytes']), node('source').value)
    selectOptions(node('excerpt'), session.excerpts.map((item, index) => [String(index), (index + 1) + '. ' + item.name + (item.provenance ? ' @' + item.provenance.version : ' (local)') + ':' + item.start_line + '–' + item.end_line]), node('excerpt').value)
    node('selection').textContent = session.excerpts.map((item, index) => (index + 1) + '. ' + item.name + (item.provenance ? ' @' + item.provenance.version + ' · run ' + item.provenance.run_id + ' · job ' + item.provenance.job_id + ' · ' + item.provenance.original_run_status + '\n' + item.source_sha256 : ' · local') + ' lines ' + item.start_line + '–' + item.end_line + '\nRelevance: ' + item.purpose + '\n' + item.content_utf8).join('\n\n')
    node('budget-info').textContent = session.bytes + ' / ' + session.budget + ' selected bytes' + (session.bytes > session.budget ? ' · over budget; shorten or remove excerpts before previewing' : '')
    sourceView()
  }
  const sync = () => {
    if (scope !== ownership()) {
      invalidate(); clearComparison(); session = new SourceBrief(); detail = null; node('retained').replaceChildren(); node('retained-info').textContent = 'Reload linked outputs for this Work thread.'; scope = ownership()
      for (const key of ['files', 'project-file', 'query', 'purpose']) node(key).value = ''
      node('start').value = '1'; node('end').value = '1'; node('budget').value = '8192'; render()
      status('Work thread, folder or gateway access changed. Import sources for this task again; the main draft was kept.')
    }
  }
  const guard = () => { sync(); need(root.isConnected !== false, 'This Work thread was closed'); const ctx = JSON.parse(contextText()); need(ctx.session_key && typeof ctx.cwd === 'string', 'Choose a Work thread first'); need(!ctx.cwd_override || ctx.cwd_override === ctx.cwd, 'Save the work folder change first'); return ctx }
  const action = (operation, keepRefresh = false) => () => { try { guard(); invalidate(keepRefresh); operation() } catch (error) { status(error.message || 'Preparation failed; draft kept') } finally { render() } }
  const get = async (url, signal) => {
    const response = await (options.fetch || globalThis.fetch)(url, { cache: 'no-store', redirect: 'error', signal })
    const value = await response.json(); need(response.ok, value.error?.message || 'Could not read retained output; check gateway access'); return value
  }
  const reader = retainedReader(get)
  const base = () => transport()?.base?.() || ''
  const selectedSources = () => session.sources.filter(source => session.excerpts.some(item => sourceKey(item) === sourceKey(source)))
  const perform = (operation, keepRefresh = false) => async () => {
    let ticket
    try {
      const ctx = guard(); if (pending) return
      const prepared = preview, preparedProject = projectPreview
      invalidate(keepRefresh); pending = true; ticket = generation; const owner = ownership(); controller = new AbortController(); const signal = controller.signal
      const valid = () => need(ticket === generation && owner === ownership() && root.isConnected !== false && !signal.aborted, 'Preparation changed or interrupted; draft kept')
      await operation(ctx, valid, signal, prepared, preparedProject); valid()
    } catch (error) { if ((ticket === undefined || ticket === generation) && root.isConnected !== false) status(error.message || 'Preparation failed; draft kept') }
    finally { if (ticket === generation) { pending = false; controller = null } }
  }
  refresh = bindSourceRefresh(document, {
    listen, status, invalidate, action: operation => action(operation, true), perform: operation => perform(operation, true),
    selectedSource: () => node('source').value, getSession: () => session,
    replaceSession: next => { session = next; clearComparison(); node('excerpt').value = ''; node('query').value = ''; node('purpose').value = ''; node('start').value = '1'; node('end').value = '1'; render() },
  })
  for (const side of ['before', 'after']) listen(node('compare-' + side), 'change', action(() => { clearComparison(); status('Snapshot choice changed; compare again before selecting a passage.') }))
  listen(node('compare'), 'click', perform(async (ctx, valid, signal) => {
    clearComparison(); const [before, after] = comparedSources()
    need(before && after, 'Import two sources and choose a before and after snapshot')
    await reader.verify([before, after], ctx, base(), signal, valid); valid()
    const result = await compareSources(before, after); valid()
    need(comparisonCurrent(result, ...comparedSources()), 'Snapshot selection changed; compare again')
    comparison = result
    selectOptions(node('change'), result.changes.map((change, index) => [String(index), (index + 1) + '. ' + change.kind + ' · before ' + (change.before ? change.before.start_line + '–' + change.before.end_line : 'none') + ' → after ' + (change.after ? change.after.start_line + '–' + change.after.end_line : 'none')]), result.changes.length ? '0' : '')
    node('compare-info').textContent = result.changes.length + ' changed passages · ' + result.before_lines + ' → ' + result.after_lines + ' lines.\nBefore: ' + before.name + '\n' + before.sha256 + '\nAfter: ' + after.name + '\n' + after.sha256 + '\nRetained checks describe this read only; local snapshots have unverified disk freshness.'
    changeView(); status(result.changes.length ? 'Inspect a change, then send one side to the excerpt editor. Add your relevance note and use Add excerpt; the task draft is unchanged.' : 'These snapshots have identical text bytes. No changed range to select; the task draft is unchanged.')
  }))
  listen(node('change'), 'change', action(() => changeView()))
  for (const side of ['before', 'after']) listen(node('choose-' + side), 'click', perform(async (ctx, valid, signal) => {
    const compared = comparison, [before, after] = comparedSources(), index = node('change').value
    need(compared && index !== '', 'Compare current snapshots and choose a changed passage first')
    await reader.verify([before, after], ctx, base(), signal, valid); valid()
    const selected = await changeRange(compared, before, after, Number(index), side); valid()
    need(comparison === compared && comparisonCurrent(compared, ...comparedSources()) && index === node('change').value, 'Comparison changed; select again')
    node('source').value = selected.source_key; node('query').value = ''; node('start').value = String(selected.start_line); node('end').value = String(selected.end_line); node('purpose').value = ''; sourceView()
    status('Exact ' + side + ' changed lines are in the excerpt editor. Add your own relevance note, then Add excerpt. Nothing was added to the task or selected excerpts yet.')
  }))
  listen(node('load-retained'), 'click', perform(async (ctx, valid, signal) => {
    detail = null; node('retained').replaceChildren(); node('retained-info').textContent = 'Reading linked run…'
    const fresh = await reader.run(ctx, base(), signal); valid(); detail = fresh
    const outputs = textArtifacts(detail)
    selectOptions(node('retained'), outputs.map(item => [item.id, item.id + ' · revision ' + item.version]), '')
    node('retained-info').textContent = 'Run ' + detail.run.id + ' · job ' + detail.run.job_id + ' · ' + detail.run.status + ' · ' + outputs.length + ' retained text outputs. Inspect one, then select exact passages.'
    status(outputs.length ? 'Choose a retained output to inspect. Existing source selections were kept.' : 'No retained textual outputs in this run. Local source selection is still available.')
  }))
  listen(node('retained'), 'change', action(() => status('Inspect this exact revision before selecting its passages.')))
  listen(node('inspect-retained'), 'click', perform(async (_, valid, signal) => {
    need(detail && node('retained').value, 'Load linked outputs and choose one first')
    const source = await reader.source(base(), detail, node('retained').value, signal); valid()
    const removed = session.import([source]); render(); node('source').value = sourceKey(source); node('query').value = ''; sourceView()
    status('Exact retained source loaded. ' + removed + ' excerpts removed because their source changed. Inspect numbered lines and choose passages; no task was sent.')
  }))
  listen(node('files'), 'change', async () => {
    const files = Array.from(node('files').files || []); invalidate()
    if (!files.length) return
    await perform(async (_, valid) => {
      const sources = await readLocalFiles(files); valid(); const invalidated = session.import(sources)
      node('files').value = ''; render(); node('source').value = sourceKey(sources[0]); sourceView()
      status('Imported ' + sources.length + ' local snapshots. ' + invalidated + ' excerpts removed because their source changed. Inspect lines and select only what the task needs.')
    })()
  })
  for (const key of ['start', 'end', 'purpose', 'budget', 'query']) listen(node(key), 'input', () => { sync(); invalidate(); if (key === 'query') sourceView() })
  listen(composer(), 'input', () => { sync(); invalidate() })
  listen(node('source'), 'change', action(() => { node('query').value = ''; node('start').value = '1'; node('end').value = '1'; node('purpose').value = ''; status('Inspect this source and choose a line range.') }))
  const picked = () => { need(node('excerpt').value !== '', 'Select an excerpt'); return Number(node('excerpt').value) }
  const budget = () => session.setBudget(Number(node('budget').value))
  listen(node('project-preview-save'), 'click', perform(async (_, valid) => {
    budget(); const raw = await exportSourceProject(session); valid()
    projectPreview = { mode: 'save', raw }; node('project-text').textContent = raw; node('project-info').textContent = describeSourceProject(session); node('project-download').disabled = false
    status('Source project ready to save. Inspect its complete JSON: it contains full imported sources, not only selected excerpts. The task draft is unchanged.')
  }))
  listen(node('project-download'), 'click', perform(async (_, valid, _signal, _prepared, preparedProject) => {
    need(preparedProject?.mode === 'save', 'Preview the current source project before downloading')
    const raw = await exportSourceProject(session); valid(); need(raw === preparedProject.raw, 'Source working set changed; preview its project again')
    ;(options.downloadProject || (value => downloadSourceProject(value, document)))(raw)
    status('Local source-project download requested. Check browser downloads before leaving. It contains full source snapshots; the task draft was not saved or changed.')
  }))
  listen(node('project-file'), 'change', async () => {
    const files = Array.from(node('project-file').files || []); invalidate(); if (!files.length) return
    await perform(async (_, valid) => {
      need(files.length === 1, 'Choose exactly one saved source project')
      const opened = await readSourceProjectFile(files[0]); valid()
      projectPreview = { mode: 'open', ...opened }; node('project-file').value = ''; node('project-text').textContent = opened.raw
      node('project-info').textContent = describeSourceProject(opened.session) + ' Replacing will discard the current ' + session.sources.length + ' unsent sources and ' + session.excerpts.length + ' excerpts. Save them first if needed.'
      node('project-restore').disabled = false; status('Saved project inspected; current working set and task draft are unchanged. Review its snapshots, then explicitly replace the unsent working set if wanted.')
    })()
  })
  listen(node('project-restore'), 'click', perform(async (ctx, valid, _signal, _prepared, preparedProject) => {
    need(preparedProject?.mode === 'open', 'Open and inspect a saved source project before replacing the working set')
    checkSourceProjectContext(preparedProject.session, ctx); valid()
    session = preparedProject.session; clearComparison(); detail = null; node('retained').replaceChildren(); node('retained-info').textContent = 'Saved retained provenance is unverified until gateway rereads. Load linked outputs to inspect current revisions.'
    node('query').value = ''; node('purpose').value = ''; node('start').value = '1'; node('end').value = '1'; node('budget').value = String(session.budget); node('excerpt').value = ''; render(); node('source').value = sourceKey(session.sources[0]); sourceView()
    status('Saved source preparation reopened. Edit its ranges, relevance notes and order, then preview the source brief for this task. Snapshots have unverified freshness; retained sources still require gateway rereads. The task draft is unchanged.')
  }))
  const put = index => { budget(); session.put(node('source').value, Number(node('start').value), Number(node('end').value), node('purpose').value, index); status('Excerpt selection updated. Preview before adding it to the task draft.') }
  listen(node('add'), 'click', action(() => put(-1)))
  listen(node('update'), 'click', action(() => put(picked())))
  listen(node('excerpt'), 'change', action(() => {
    const item = session.excerpts[picked()]; need(item, 'Select an excerpt')
    node('source').value = sourceKey(item); node('start').value = String(item.start_line); node('end').value = String(item.end_line); node('purpose').value = item.purpose; node('query').value = ''
  }))
  listen(node('remove-source'), 'click', action(() => { need(node('source').value, 'Select a source'); session.removeSource(node('source').value); status('Source and its excerpts removed from this unsent working set. Any already-applied task draft is unchanged.') }))
  listen(node('remove'), 'click', action(() => { session.remove(picked()); node('excerpt').value = ''; status('Excerpt removed from the unsent working set; preview and apply to update the task draft.') }))
  for (const [key, offset] of [['up', -1], ['down', 1]]) listen(node(key), 'click', action(() => { node('excerpt').value = String(session.move(picked(), offset)) }))
  listen(node('preview'), 'click', perform(async (ctx, valid, signal) => {
    budget(); const draft = composer().value
    await reader.verify(selectedSources(), ctx, base(), signal, valid); valid()
    const packet = await session.packet(ctx); valid()
    const next = await composeBrief(draft, packet); valid(); need(composer().value === draft, 'Main draft changed; preview again')
    preview = { draft, next, scope: ownership() }; node('preview-text').textContent = next; node('apply').disabled = false; render()
    status('Preview ready. Check every included excerpt and relevance note. Apply only adds this exact preview to the draft; it does not send or run it.')
  }))
  listen(node('apply'), 'click', perform(async (ctx, valid, signal, prepared) => {
    need(prepared && prepared.scope === ownership() && composer().value === prepared.draft, 'Preview the current sources and task draft first')
    await reader.verify(selectedSources(), ctx, base(), signal, valid); valid()
    need(composer().value === prepared.draft, 'Main draft changed; preview again')
    const rechecked = selectedSources().some(source => source.provenance)
    composer().value = prepared.next; pending = false
    composer().dispatchEvent(options.inputEvent?.() || new Event('input', { bubbles: true }))
    status('Previewed sources placed in the task draft. ' + (rechecked ? 'Exact retained revisions rechecked. ' : '') + 'Use Plan and Preview, then Promote and Confirm only the work you approve.')
  }))
  listen(node('detach'), 'click', perform(async (_, valid) => {
    const draft = composer().value, next = await removeBrief(draft); valid()
    need(composer().value === draft, 'Main draft changed; remove again when ready')
    composer().value = next; pending = false
    composer().dispatchEvent(options.inputEvent?.() || new Event('input', { bubbles: true }))
    status('Source block removed from this draft. Other task text and unsent source selections were kept.')
  }))
  listen(node('cancel'), 'click', () => { invalidate(); clearComparison(); status('Pending preparation interrupted; sources and the main task draft were kept.') })
  listen(root, 'toggle', () => { if (!root.open) { invalidate(); clearComparison(); status('Source panel closed; pending preparation interrupted. Sources and the main draft were kept.') } })
  render()
  return { sync, get session() { return session }, dispose() { invalidate(); events.abort(); delete root.dataset.bound } }
}
export function installSourceBrief(document) {
  let anchor = null, root = null, binding = null
  const sync = () => {
    const next = document.getElementById('claw-procedure-panel')
    if (next !== anchor || (root && root.isConnected === false)) { binding?.dispose(); root?.remove(); anchor = next; root = next ? mountSourceBrief(document, next) : null; binding = root ? bindSourceBrief(document) : null }
    binding?.sync()
  }
  sync(); const observer = new MutationObserver(sync); observer.observe(document.body, { childList: true, subtree: true, characterData: true })
  return () => { observer.disconnect(); binding?.dispose(); root?.remove() }
}
