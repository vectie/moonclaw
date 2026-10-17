import { readRun, textArtifacts, readSource, createPacket, composeRework } from './artifact-rework.js'
const need = (ok, message) => { if (!ok) throw new Error(message) }
const fields = ['changes', 'preserve', 'verify']
export function mountRework(document, anchor) {
  const panel = document.createElement('details'); panel.id = 'claw-rework-panel'; panel.className = 'procedure-panel'
  const add = (tag, key, text) => { const node = document.createElement(tag); if (key) node.id = 'claw-rework-' + key; node.textContent = text; panel.appendChild(node); return node }
  add('summary', '', 'Revise an exact output')
  add('p', '', 'Inspect a retained result and turn specific changes into a new reviewed task. Original outputs stay unchanged. Failed and cancelled runs remain labelled as such.')
  const button = (key, label) => { const node = add('button', key, label); node.type = 'button' }
  button('load', 'Load linked outputs')
  const label = add('label', '', 'Retained text output'); label.htmlFor = 'claw-rework-choice'; add('select', 'choice', '')
  button('inspect', 'Inspect selected revision')
  add('pre', 'evidence', 'Load the linked run, then inspect a text output of at most 32 KiB.')
  add('pre', 'original', '')
  for (const [key, title] of [['changes', 'What should change?'], ['preserve', 'What must stay unchanged?'], ['verify', 'How will you check the revised result?']]) { const label = add('label', '', title); label.htmlFor = 'claw-rework-' + key; add('textarea', key, '') }
  button('apply', 'Put revision task in draft')
  button('cancel', 'Interrupt pending read')
  const status = add('p', 'status', 'Unsent selections and form fields are lost on reload. Sent packets persist with the ordinary plan request.'); status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite')
  add('p', '', 'Use Plan, Preview, Promote and Confirm to approve the new task. This panel only reads and prepares a draft; it never starts a run or accepts output.')
  anchor.insertAdjacentElement('afterend', panel)
  return panel
}
export function bindRework(document, options = {}) {
  const node = key => document.getElementById('claw-rework-' + key), root = node('panel')
  if (!root || root.dataset.bound) return null
  root.dataset.bound = 'true'
  const composer = () => document.getElementById('claw-procedure-composer')
  const contextText = () => document.getElementById('claw-procedure-context')?.textContent || ''
  const transport = options.transport || (() => globalThis.__moonclawTransport)
  const base = () => transport()?.base?.() || '', epoch = () => transport()?.epoch?.() || 0
  const events = new AbortController(), listen = (target, type, fn) => target.addEventListener(type, fn, { signal: events.signal })
  let detail = null, source = null, generation = 0, pending = false, controller = null, scope = contextText(), gateway = base(), access = epoch()
  const status = message => { if (node('status').textContent !== message) node('status').textContent = message }
  const cancel = () => { generation++; pending = false; controller?.abort(); controller = null }
  const clear = () => { detail = null; source = null; node('choice').replaceChildren(); node('original').textContent = ''; node('evidence').textContent = 'Reload and inspect the current linked output.' }
  const sync = () => { if (scope !== contextText() || gateway !== base() || access !== epoch()) { cancel(); clear(); for (const key of fields) node(key).value = ''; scope = contextText(); gateway = base(); access = epoch(); status('Work thread, proposal, folder or access changed. Select and inspect the current output again.') } }
  const get = async (url, signal) => { const response = await (options.fetch || globalThis.fetch)(url, { cache: 'no-store', redirect: 'error', signal }); const value = await response.json(); need(response.ok, value.error?.message || 'Could not read retained output; check gateway access'); return value }
  const perform = operation => async () => {
    sync(); if (pending) return
    pending = true; const ticket = ++generation, text = contextText(), startBase = base(), startEpoch = epoch(); controller = new AbortController(); const signal = controller.signal
    const valid = () => need(ticket === generation && root.isConnected !== false && text === contextText() && startBase === base() && startEpoch === epoch() && !signal.aborted, 'Context or input changed; draft kept')
    try { const ctx = JSON.parse(text); need(startBase && ctx.run_id, 'Choose a work thread with an existing linked run and connect the gateway'); need(!ctx.cwd_override || ctx.cwd_override === ctx.cwd, 'Save the work folder change first'); await operation(ctx, startBase, signal, valid); valid() }
    catch (error) { if (ticket === generation && root.isConnected !== false) status(error.message || 'Read failed; draft kept') }
    finally { if (ticket === generation) { pending = false; controller = null } }
  }
  const run = async (ctx, base, signal) => readRun(await get(base + '/v1/jobs/runs/' + encodeURIComponent(ctx.run_id), signal), ctx)
  const artifact = async (base, id, detail, signal) => readSource(await get(base + '/v1/artifacts/' + encodeURIComponent(id), signal), detail, id)
  listen(node('load'), 'click', perform(async (ctx, base, signal, valid) => {
    clear(); const fresh = await run(ctx, base, signal); valid(); detail = fresh
    const placeholder = document.createElement('option'); placeholder.value = ''; placeholder.textContent = 'Choose an output'; node('choice').appendChild(placeholder)
    for (const item of textArtifacts(detail)) { const option = document.createElement('option'); option.value = item.id; option.textContent = item.id + ' · revision ' + item.version; node('choice').appendChild(option) }
    status('Run ' + detail.run.id + ': ' + detail.run.status + '. ' + textArtifacts(detail).length + ' retained text outputs. Inspect one before requesting changes.')
  }))
  listen(node('choice'), 'change', () => { cancel(); source = null; node('original').textContent = ''; status('Inspect the selected revision before preparing its task.') })
  listen(node('inspect'), 'click', perform(async (ctx, base, signal, valid) => {
    need(detail, 'Load linked outputs first'); const id = node('choice').value; source = null; node('original').textContent = ''; node('evidence').textContent = 'Reading the selected exact revision…'
    const selected = await artifact(base, id, detail, signal); valid(); source = selected
    node('original').textContent = source.content_utf8
    node('evidence').textContent = source.artifact_id + ' @' + source.version + '\n' + source.sha256 + '\nRun state: ' + detail.run.status + '; correctness and acceptance are not established.'
    status('Inspect the exact source above, then describe changes, preserved constraints and verification.')
  }))
  for (const key of fields) listen(node(key), 'input', () => { if (pending) { cancel(); status('Input changed; pending read stopped. Apply again when ready.') } })
  listen(composer(), 'input', () => { if (pending) cancel() })
  listen(node('apply'), 'click', perform(async (ctx, base, signal, valid) => {
    need(source, 'Inspect a retained revision first'); const selected = source, draft = composer().value, values = fields.map(key => node(key).value)
    const freshRun = await run(ctx, base, signal); valid()
    const freshSource = await artifact(base, selected.artifact_id, freshRun, signal); valid()
    need(JSON.stringify(freshSource) === JSON.stringify(selected), 'Selected source changed; load and inspect again. Draft kept')
    const packet = await createPacket(ctx, freshRun, freshSource, ...values); valid()
    const next = await composeRework(draft, packet); valid(); need(composer().value === draft, 'Main draft changed; apply again')
    composer().value = next; pending = false
    composer().dispatchEvent(options.inputEvent?.() || new Event('input', { bubbles: true }))
    status('Exact source and revision instructions placed in the draft. Review Plan and Preview, then Promote and Confirm only the new work you approve.')
  }))
  listen(node('cancel'), 'click', () => { cancel(); status('Pending read interrupted; main work draft unchanged.') })
  return { sync, get source() { return source }, dispose() { cancel(); events.abort(); delete root.dataset.bound } }
}
export function installRework(document) {
  let anchor = null, root = null, binding = null
  const sync = () => {
    const next = document.getElementById('claw-procedure-panel')
    if (next !== anchor || (root && root.isConnected === false)) { binding?.dispose(); root?.remove(); anchor = next; root = next ? mountRework(document, next) : null; binding = root ? bindRework(document) : null }
    binding?.sync()
  }
  sync(); const observer = new MutationObserver(sync); observer.observe(document.body, { childList: true, subtree: true, characterData: true })
  return () => { observer.disconnect(); binding?.dispose(); root?.remove() }
}
