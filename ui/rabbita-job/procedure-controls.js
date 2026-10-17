import { ProcedureSession, readProcedures, describeProcedure, matchingProcedures, chooseProcedure, composeProcedureDraft, compareProcedure } from './procedures.js'
const need = (ok, message) => { if (!ok) throw new Error(message) }

export function bindProcedures(document, options = {}) {
  const node = key => document.getElementById('claw-procedure-' + key)
  const root = node('panel')
  if (!root || root.dataset.bound) return null
  root.dataset.bound = 'true'
  const events = new AbortController(), session = new ProcedureSession()
  const listen = (target, event, fn) => target.addEventListener(event, fn, { signal: events.signal })
  const transport = options.transport || (() => globalThis.__moonclawTransport)
  const contextText = () => node('context')?.textContent || ''
  const context = () => JSON.parse(contextText())
  const base = () => transport()?.base?.() || ''
  const epoch = () => transport()?.epoch?.() || 0
  let controller = null, boundContext = contextText(), boundEpoch = epoch()
  const status = message => { node('status').textContent = message }
  const evidence = () => {
    const record = session.inventory?.records.find(item => item.path === node('choice').value)
    if (!record) { node('evidence').textContent = 'No matching procedure selected'; node('original').textContent = ''; return }
    const description = describeProcedure(record)
    node('evidence').textContent = description.title + '\nApplicability: ' + description.applicability + '\nRecorded outcome: ' + description.outcome + '\nRecorded effort: ' + description.effort + '\nVerification: ' + description.verification + '\nExact record: ' + record.path + '\n' + record.sha256
    node('original').textContent = record.content_utf8
  }
  const choices = () => {
    const selected = node('choice').value
    node('choice').replaceChildren()
    const records = matchingProcedures(session.inventory?.records || [], node('query').value)
    for (const [value, label] of [['', records.length ? 'Choose a procedure after inspecting its conditions' : 'No matching accepted procedure'], ...records.map(record => [record.path, describeProcedure(record).title])]) {
      const option = document.createElement('option'); option.value = value; option.textContent = label; node('choice').appendChild(option)
    }
    node('choice').value = records.some(record => record.path === selected) ? selected : ''
    evidence()
  }
  const readJSON = async (url, signal) => {
    const response = await (options.fetch || globalThis.fetch)(url, { cache: 'no-store', redirect: 'error', signal })
    const value = await response.json()
    need(response.ok, value.error?.message || 'Could not read the selected work context; check gateway access')
    return value
  }
  const inventory = (ctx, gateway, signal) => readJSON(gateway + '/v1/cowork/sessions/' + encodeURIComponent(ctx.session_key) + '/procedures', signal)
  const perform = operation => async () => {
    const text = contextText(), ctx = context(), gateway = base(), startedEpoch = epoch()
    if (session.pending) return
    const activeController = new AbortController()
    controller = activeController
    const signal = activeController.signal
    const current = () => need(root.isConnected !== false && contextText() === text && base() === gateway && epoch() === startedEpoch && !signal.aborted, 'Work thread, folder or gateway access changed; the draft was kept')
    try {
      need(gateway, 'Connect the current gateway first')
      need(!ctx.cwd_override || ctx.cwd_override === ctx.cwd, 'Save the work folder change before loading or selecting a procedure')
      await session.transaction(async valid => { const checked = () => { valid(); current() }; await operation(ctx, gateway, signal, checked); checked() })
    } catch (error) {
      if (root.isConnected !== false) {
        if (node('comparison').textContent === 'Refreshing the exact linked result…') node('comparison').textContent = 'Comparison unavailable; retained work is unchanged. See the status below'
        status(error.message || 'Read failed; draft kept')
      }
    } finally { if (controller === activeController) controller = null }
  }
  listen(node('load'), 'click', perform(async (ctx, gateway, signal, valid) => {
    session.inventory = null; choices()
    const value = await readProcedures(await inventory(ctx, gateway, signal), ctx); valid()
    session.inventory = value; choices()
    status(value.records.length ? 'Inspect the original method, select it, then explain applicability and expected result' : 'No accepted procedure available (' + value.status + '). Ordinary work remains available; no method was invented')
  }))
  listen(node('query'), 'input', () => { session.cancel(); controller?.abort(); choices() })
  listen(node('choice'), 'change', () => { session.cancel(); controller?.abort(); evidence() })
  for (const key of ['why', 'expected', 'composer']) listen(node(key), 'input', () => { if (session.pending) { session.cancel(); controller?.abort() } })
  listen(node('apply'), 'click', perform(async (ctx, gateway, signal, valid) => {
    need(session.inventory, 'Load accepted procedures first')
    const draft = node('composer').value, path = node('choice').value, why = node('why').value, expected = node('expected').value
    const choice = await chooseProcedure(session.inventory, path, why, expected, await inventory(ctx, gateway, signal)); valid()
    const composed = await composeProcedureDraft(draft, choice); valid()
    need(node('composer').value === draft, 'Work draft changed during the read; apply again when ready')
    // Dispatch the same input event handled by the existing Rabbita composer.
    node('composer').value = composed
    session.pending = false
    node('composer').dispatchEvent(options.inputEvent?.() || new Event('input', { bubbles: true }))
    status('Approach placed in the work draft with its exact source. Choose Plan, inspect Preview, Promote, then Confirm only the work you approve')
  }))
  listen(node('compare'), 'click', perform(async (ctx, gateway, signal, valid) => {
    node('comparison').textContent = 'Refreshing the exact linked result…'
    need(ctx.run_id, 'Confirm the reviewed proposal and wait for its linked run')
    const detail = await readJSON(gateway + '/v1/jobs/runs/' + encodeURIComponent(ctx.run_id), signal)
    const result = await compareProcedure(ctx, detail); valid()
    const prior = describeProcedure(result.choice.record)
    node('comparison').textContent = 'Selected approach: ' + prior.title + '\nWhy it applies: ' + result.choice.applicability_reason + '\nExpected: ' + result.choice.expected_result + '\nHistorical recorded outcome: ' + prior.outcome + '\nHistorical recorded effort: ' + prior.effort + '\nCurrent run: ' + ctx.run_id + ' · ' + result.status + '\nDelivered summary: ' + result.summary + (result.error ? '\nError: ' + result.error : '') + '\nRecorded elapsed runtime: ' + (result.elapsed_ms === null ? 'Unknown' : result.elapsed_ms + ' ms') + '\nTokens and cost: not measured by this comparison\nRetained artifacts: ' + (result.artifacts.map(item => item.logical_key + ' @' + item.version).join(', ') || 'None recorded') + '\n' + result.assessment
    status(result.terminal ? 'Compare the expected result with the retained artifacts in the Artifacts tab. Book learning and final acceptance still require their own review' : 'The linked run is still pending; refresh the comparison after it finishes')
  }))
  listen(node('cancel'), 'click', () => { session.cancel(); controller?.abort(); status('Pending read interrupted; your work draft is unchanged') })
  return { session, sync() {
    if (boundContext !== contextText() || boundEpoch !== epoch()) {
      session.cancel(); controller?.abort(); session.inventory = null; choices()
      node('comparison').textContent = 'Context changed. Refresh the linked result; earlier observations are not current'
      boundContext = contextText(); boundEpoch = epoch()
    }
  }, dispose() { session.cancel(); controller?.abort(); events.abort(); delete root.dataset.bound } }
}

export function installProcedures(document) {
  let binding = null, mounted = null
  const sync = () => {
    const root = document.getElementById('claw-procedure-panel')
    if (root !== mounted) { binding?.dispose(); mounted = root; binding = root ? bindProcedures(document) : null }
    binding?.sync()
  }
  sync()
  const observer = new MutationObserver(sync)
  observer.observe(document.body, { childList: true, subtree: true, characterData: true })
  return () => { observer.disconnect(); binding?.dispose() }
}
