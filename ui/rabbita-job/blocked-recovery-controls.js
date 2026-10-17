import { BlockedRecovery, describeRecovery } from './blocked-recovery.js'
const need = (ok, message) => { if (!ok) throw new Error(message) }

export function bindBlockedRecovery(document, options = {}) {
  const node = key => document.getElementById('claw-recovery-' + key)
  const root = node('panel')
  if (!root || root.dataset.bound) return null
  root.dataset.bound = 'true'
  const events = new AbortController()
  const listen = (key, type, callback) => node(key).addEventListener(type, callback, { signal: events.signal })
  const transport = options.transport || (() => globalThis.__moonclawTransport)
  const base = () => transport()?.base?.() || ''
  const epoch = () => transport()?.epoch?.() || 0
  const contextText = () => node('context')?.textContent || ''
  let scope = '', session = null, pending = false, controller = null, generation = 0, access = epoch(), storageError = '', storageBlocked = false
  let storage = options.storage
  if (!storage) { try { storage = globalThis.sessionStorage } catch (_) {} }
  const status = message => { node('status').textContent = message + (storageError ? '\n' + storageError : '') }
  const key = () => 'moonclaw-blocked-recovery:' + base() + ':' + contextText()
  const persist = () => {
    if (storageBlocked) return
    try { need(storage, 'storage unavailable'); storage.setItem(key(), JSON.stringify(session.state)); storageError = '' }
    catch (_) { storageError = 'Browser storage is unavailable. Keep a copy of the answer before closing this page; reload recovery is not guaranteed.' }
  }
  const render = () => {
    node('answer').value = session.state.draft
    node('answer').readOnly = session.state.phase !== 'draft'
    node('evidence').textContent = session.snapshot ? describeRecovery(session.snapshot) : 'Refresh to inspect the exact retained run. No execution is started by loading.'
    node('resume').disabled = pending || !session.snapshot?.can_resume || session.snapshot.checkpoint !== session.state.checkpoint || !['draft', 'uncertain'].includes(session.state.phase)
    node('resume').textContent = session.state.phase === 'uncertain' ? 'Retry same checkpoint safely' : 'Continue this blocked step'
    node('adopt').disabled = pending || !session.snapshot?.can_resume || session.state.phase === 'uncertain' || (session.state.phase === 'submitted' && session.snapshot.checkpoint === session.state.checkpoint)
  }
  const interrupt = () => { generation++; controller?.abort(); controller = null; pending = false }
  const sync = () => {
    const next = base() + ':' + contextText()
    if (next === scope && access === epoch()) return
    interrupt(); scope = next; access = epoch()
    let saved = null
    try { const raw = storage?.getItem(key()); if (raw) saved = JSON.parse(raw); session = new BlockedRecovery(saved); storageError = ''; storageBlocked = false }
    catch (_) { session = new BlockedRecovery(); storageBlocked = true; storageError = 'Saved answer could not be read and was left untouched. Do not submit until its earlier outcome is checked.'; session.state.phase = 'uncertain' }
    render(); status(session.state.phase === 'uncertain' ? 'An earlier submission may have reached the gateway. Refresh to reconcile it before doing anything else.' : 'Your answer is kept for this gateway, work thread and run in this browser tab.')
  }
  const request = async (url, init) => {
    const response = await (options.fetch || globalThis.fetch)(url, { cache: 'no-store', redirect: 'error', ...init })
    const value = await response.json()
    if (!response.ok) { const error = new Error(value.error?.message || 'Gateway request failed; refresh the retained run'); error.code = value.error?.code; throw error }
    return value
  }
  const perform = fn => async () => {
    sync()
    if (pending) return
    pending = true; const ticket = ++generation, text = contextText(), gateway = base(), startedEpoch = epoch()
    controller = new AbortController(); const signal = controller.signal
    const valid = () => need(ticket === generation && root.isConnected !== false && contextText() === text && base() === gateway && epoch() === startedEpoch && !signal.aborted, 'Context or gateway access changed; the answer was kept')
    render()
    try {
      const context = JSON.parse(text)
      need(gateway && context.run_id, 'Choose an existing linked run and connect its gateway')
      need(!context.cwd_override || context.cwd_override === context.cwd, 'Save the work-folder change before continuing')
      const path = gateway + '/v1/cowork/sessions/' + encodeURIComponent(context.session_key) + '/runs/' + encodeURIComponent(context.run_id)
      await fn({ context, path, signal, valid }); valid()
    } catch (error) { if (ticket === generation && root.isConnected !== false) status(error.message + (session.state.phase === 'uncertain' ? '\nSubmission may have reached the gateway. Refresh before retrying; never start a replacement run.' : '')) }
    finally { if (ticket === generation) { pending = false; controller = null; render() } }
  }
  listen('refresh', 'click', perform(async ({ context, path, signal, valid }) => {
    const value = await request(path + '/recovery', { signal, headers: { 'X-Moonclaw-Recovery-Checkpoint': session.state.checkpoint } }); valid()
    session.observe(value, context); persist(); render()
    status(session.state.phase === 'superseded' ? 'A different answer was recorded for the earlier checkpoint. Your answer is retained; review the current checkpoint before using it.' : session.state.phase === 'submitted' ? 'The gateway recorded this answer. Inspect the same run for actual progress; a saved answer alone does not prove execution.' : session.state.checkpoint !== value.checkpoint ? 'The checkpoint changed. Your earlier answer is retained; inspect the new evidence before using it.' : session.state.phase === 'uncertain' ? 'The original checkpoint is still current. You may explicitly retry the same conditional submission; a duplicate or changed checkpoint will be refused.' : 'Checkpoint refreshed. Check what is missing, then supply only the permitted input.')
  }))
  listen('answer', 'input', () => {
    if (pending) interrupt()
    try { session.edit(node('answer').value); persist(); render() } catch (error) { status(error.message) }
  })
  listen('adopt', 'click', () => {
    if (pending) return
    try { session.adopt(); persist(); render(); status('Answer is now scoped to the reviewed checkpoint. Edit it as needed, then explicitly continue.') } catch (error) { status(error.message) }
  })
  listen('resume', 'click', perform(async ({ context, path, signal, valid }) => {
    // Fresh read and server-side compare-and-submit protect against a newer wait.
    const fresh = await request(path + '/recovery', { signal, headers: { 'X-Moonclaw-Recovery-Checkpoint': session.state.checkpoint } }); valid()
    session.observe(fresh, context); persist()
    const body = session.request(); valid()
    const beforeSend = session.state.phase
    const digest = await session.prepare(); valid()
    session.sending(digest); persist(); render(); status('Submitting to the same run. If interrupted, refresh to reconcile the answer.')
    let value
    try { value = await request(path + '/resume', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal }) }
    catch (error) {
      valid()
      if (beforeSend === 'draft' && error.code === 'resume_not_submitted') { session.state.phase = 'draft'; persist() }
      throw error
    }
    valid()
    const detail = value.session
    need(detail?.session?.session_key === context.session_key && (Array.isArray(detail.linked_run) ? detail.linked_run[0] : detail.linked_run)?.id === context.run_id, 'Resume acknowledgement belongs to another run')
    session.acknowledged(); persist(); render(); status('Answer recorded and continuation requested for the same run. Refresh to inspect progress; completed artifacts remain available.')
  }))
  listen('cancel', 'click', () => { interrupt(); render(); status(session.state.phase === 'uncertain' ? 'Stopped waiting for the response. This does not cancel execution. Refresh the same run before retrying.' : 'Read interrupted. Your answer is retained.') })
  sync()
  return { get session() { return session }, sync, dispose() { interrupt(); events.abort(); delete root.dataset.bound } }
}

export function installBlockedRecovery(document) {
  let binding = null, mounted = null
  const sync = () => {
    const root = document.getElementById('claw-recovery-panel')
    if (root !== mounted) { binding?.dispose(); mounted = root; binding = root ? bindBlockedRecovery(document) : null }
    binding?.sync()
  }
  sync()
  const observer = new MutationObserver(sync)
  observer.observe(document.body, { childList: true, subtree: true, characterData: true })
  return () => { observer.disconnect(); binding?.dispose() }
}
