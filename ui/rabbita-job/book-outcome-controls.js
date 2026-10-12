import { FILE_LIMIT, OutcomeSession, readSource } from './book-outcome.js'

const need = (ok, message) => { if (!ok) throw new Error(message) }
const prefix = 'claw-book-'
const gaps = ['information', 'recognition', 'decisiveness']
const fieldNames = ['summary', 'observed', ...gaps.flatMap(key => [key + '-severity', key + '-summary']), 'capability-id', 'capability-version', 'capability-summary']
const pretty = value => JSON.stringify(value, null, 2)
const inMemory = new Map()

export function bindBookOutcome(document, options = {}) {
  const node = key => document.getElementById(prefix + key)
  const root = node('panel')
  if (!root || root.dataset.bound) return null
  root.dataset.bound = 'true'
  const events = new AbortController()
  const listen = (target, event, fn) => target.addEventListener(event, fn, { signal: events.signal })
  const transport = options.transport || (() => globalThis.__moonclawTransport)
  let storage = options.storage
  if (!storage) { try { storage = globalThis.sessionStorage } catch (_) {} }
  const download = options.download || ((raw, name, type = 'application/json') => {
    const url = URL.createObjectURL(new Blob([raw], { type }))
    const link = document.createElement('a'); link.href = url; link.download = name; link.click()
    setTimeout(() => URL.revokeObjectURL(url), 30000)
  })
  const status = text => { node('status').textContent = text }
  const contextText = () => node('context').textContent
  const context = () => JSON.parse(contextText())
  const gateway = () => transport()?.base?.() || ''
  const epoch = () => transport()?.epoch?.() || 0
  const key = () => 'moonclaw-book-draft-v1:' + gateway() + ':' + context().run_id
  const initialKey = key()
  let saved = inMemory.get(initialKey), storageWarning = ''
  if (!saved) { try { saved = JSON.parse(storage?.getItem(initialKey) || 'null') } catch (_) { storageWarning = 'Saved draft could not be read. Open a previously downloaded handoff to recover it.' } }
  if (saved && (!saved.fields || !Array.isArray(saved.selected) || !Array.isArray(saved.receipts) || !Array.isArray(saved.history))) { saved = null; storageWarning = 'Saved draft could not be decoded. Open a downloaded handoff or recovery file.' }
  const session = new OutcomeSession(saved)
  let controller = null, initialContext = contextText(), initialEpoch = epoch()
  const persist = () => {
    inMemory.set(initialKey, session.state)
    try { need(storage, 'No browser storage'); storage.setItem(initialKey, JSON.stringify(session.state)); storageWarning = '' } catch (_) { storageWarning = 'Browser draft storage is full or unavailable. Download the saved handoff or draft recovery before closing this page.' }
  }
  const refreshFields = () => {
    const fields = session.state.fields
    node('summary').value = fields.outcome_summary || ''
    node('observed').value = Number.isSafeInteger(fields.observed_at) ? new Date(fields.observed_at * 1000).toISOString().replace('.000Z', 'Z') : ''
    for (const gap of gaps) { node(gap + '-severity').value = fields.gaps?.[gap]?.severity ?? ''; node(gap + '-summary').value = fields.gaps?.[gap]?.summary || '' }
    for (const field of ['id', 'version', 'summary']) node('capability-' + field).value = fields.capability?.[field] || ''
    context().artifacts.forEach((item, index) => { const choice = node('choose-' + index); if (choice) choice.checked = session.state.selected.includes(item.id) })
  }
  const refreshRetained = () => {
    const source = session.state.source
    node('identity').textContent = source ? 'Frozen source ' + source.source_digest + '\n' + source.source_json : 'No source frozen yet'
    node('original').textContent = source ? source.artifacts.map(item => 'Artifact ' + item.id + '\n' + item.text).join('\n\n') : 'Freeze or open a saved handoff to inspect exact source text'
    node('saved').textContent = session.state.handoff ? 'Saved immutable handoff: ' + JSON.parse(session.state.handoff).package_digest : 'No exported handoff saved'
    node('history').textContent = session.state.history.map((entry, index) => `${index}: ${entry.source?.source_digest || 'draft only'} · ${entry.handoff ? 'saved handoff available' : 'unexported source draft'}`).join('\n') || 'No earlier source snapshots yet'
    if (session.state.receipts.length) {
      const receipts = session.state.receipts.map(raw => JSON.parse(raw))
      node('readback').textContent = receipts.map((receipt, index) => `Historical Book observation ${index + 1}: ${receipt.progress.state}\n${receipt.progress.title || ''}\n${pretty(receipt.reviews)}`).join('\n\n') + '\nUnsigned local observations, shown in import order, not a claim of current Book status. Reopen Book and refresh before relying on any decision. No authority is granted here.'
    } else node('readback').textContent = 'No Book disposition opened for this handoff'
  }
  const readFields = () => {
    const observed = node('observed').value.trim()
    const timestamp = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(observed) ? Date.parse(observed) / 1000 : null
    const fields = { outcome_summary: node('summary').value, observed_at: Number.isSafeInteger(timestamp) ? timestamp : null, gaps: {}, capability: {} }
    for (const gap of gaps) { const raw = node(gap + '-severity').value.trim(); fields.gaps[gap] = { severity: raw === '' ? null : Number(raw), summary: node(gap + '-summary').value } }
    for (const field of ['id', 'version', 'summary']) fields.capability[field] = node('capability-' + field).value
    const selected = context().artifacts.filter((_, index) => node('choose-' + index)?.checked).map(item => item.id)
    session.edit(fields, selected); persist()
  }
  const perform = operation => async () => {
    const ticketContext = contextText(), ticketEpoch = epoch(), ticketGateway = gateway()
    if (session.pending) return
    status('Reading and validating exact source… You can interrupt this read; the prior saved handoff is kept')
    controller = new AbortController()
    const signal = controller.signal
    const current = () => { need(!signal.aborted && root.isConnected !== false && contextText() === ticketContext && gateway() === ticketGateway && epoch() === ticketEpoch, 'Run, source list or gateway access changed; the interrupted draft and prior handoff were kept') }
    try {
      await session.transaction(async valid => {
        const checked = () => { current(); valid() }
        await operation(checked, signal, ticketGateway); checked(); persist(); refreshRetained()
      })
      if (storageWarning) status(storageWarning)
    } catch (error) {
      if (root.isConnected !== false) status((error.message || 'Read failed') + ' · Current draft and earlier saved sources were kept')
    } finally { controller = null }
  }
  const requestSource = async (run, ids, signal, base) => {
    need(base, 'Connect the current Claw gateway before freezing a source')
    const response = await (options.fetch || globalThis.fetch)(base + '/v1/jobs/runs/' + encodeURIComponent(run) + '/book-outcome-source', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ artifact_ids: ids }), cache: 'no-store', redirect: 'error', signal })
    const result = await response.json()
    need(response.ok, result.error?.message || 'Source read failed. Refresh the completed run and retry')
    return result
  }
  fieldNames.forEach(name => listen(node(name), 'input', readFields))
  context().artifacts.forEach((_, index) => { if (node('choose-' + index)) listen(node('choose-' + index), 'change', readFields) })
  listen(node('freeze'), 'click', perform(async (valid, signal, base) => {
    const current = context()
    need(['Succeeded', 'Failed', 'Cancelled'].includes(current.status), 'Choose a completed run; no result is inferred while it is pending')
    need(session.state.selected.length, 'Select the real UTF-8 output(s) to retain')
    const candidate = await requestSource(current.run_id, session.state.selected, signal, base)
    valid(); const parsed = await readSource(candidate); valid()
    need(parsed.context.run.id === current.run_id && pretty(parsed.source.artifacts.map(item => item.id)) === pretty(session.state.selected), 'Gateway returned a different run or artifact selection')
    await session.freeze(candidate, valid)
    status('Selected text and run identity are frozen. Inspect the source details, describe your interpretation, then export for Book')
  }))
  listen(node('export'), 'click', perform(async (valid, signal, base) => {
    need(session.state.fields.observed_at !== null, 'Enter observation time in UTC, for example 2026-10-07T01:00:00Z')
    const source = session.state.source
    need(source, 'Freeze the selected completed text outputs first')
    const original = JSON.parse(source.source_json)
    need(original.run.id === context().run_id && pretty(source.artifacts.map(item => item.id)) === pretty(session.state.selected), 'Selection changed; freeze the new selected source explicitly')
    const raw = await session.export(() => requestSource(original.run.id, source.artifacts.map(item => item.id), signal, base), valid)
    valid(); download(raw, 'moonclaw-book-outcome.json')
    status('Saved and exported the exact handoff. Import it in Book → Product outcomes, then use Book’s existing review controls. Book acceptance is pending')
  }))
  listen(node('open'), 'change', perform(async valid => {
    const file = node('open').files?.[0]; need(file && file.size <= FILE_LIMIT, 'Choose a saved handoff up to 16 MiB')
    await session.open(await file.text(), valid); refreshFields()
    status('Opened the original saved handoff and exact retained text. This does not replace any live run or imply a current Book decision')
  }))
  listen(node('receipt'), 'change', perform(async valid => {
    const file = node('receipt').files?.[0]; need(file && file.size <= FILE_LIMIT, 'Choose a Book disposition receipt up to 16 MiB')
    await session.receive(await file.text(), valid)
    status('Opened Book’s exact returned handoff, disposition and retained original text. Older receipts remain historical; refresh in Book for current status')
  }))
  listen(node('download'), 'click', () => { if (!session.state.handoff) return status('Export or open a saved handoff first'); download(session.state.handoff, 'moonclaw-book-outcome.json'); status('Downloaded the unchanged saved handoff, including its original source version') })
  listen(node('download-source'), 'click', () => {
    if (!session.state.source) return status('Freeze or open an original source first')
    // One explicit click per artifact; no lossy conversion or concatenation.
    const index = Number(node('source-index').value)
    const artifact = session.state.source.artifacts[index]
    if (!Number.isSafeInteger(index) || !artifact) return status('Choose an original source index from 0 to ' + (session.state.source.artifacts.length - 1))
    download(artifact.text, 'moonclaw-original-' + index + '.txt', 'text/plain;charset=utf-8')
    status('Downloaded the exact original UTF-8 bytes for ' + artifact.id)
  })
  listen(node('recovery'), 'click', () => { download(pretty({ contract_version: 'moonclaw.book-draft-recovery.v1', state: session.state }), 'moonclaw-book-draft-recovery.json'); status('Downloaded the current draft and earlier source snapshots. Open saved handoffs individually to import their Book receipts') })
  listen(node('recovery-open'), 'change', perform(async valid => {
    const file = node('recovery-open').files?.[0]; need(file && file.size <= 64 * 1024 * 1024, 'Choose a draft recovery file up to 64 MiB')
    await session.restore(await file.text(), valid); refreshFields(); status('Recovered draft, saved handoff and earlier sources. No live run or Book state was changed')
  }))
  listen(node('history-open'), 'click', perform(async valid => {
    const index = Number(node('history-index').value), entry = session.state.history[index]
    need(Number.isSafeInteger(index) && entry, 'Choose an earlier source index shown above')
    const candidate = JSON.parse(JSON.stringify(entry))
    const history = JSON.parse(JSON.stringify(session.state.history))
    await session.restore(JSON.stringify({ contract_version: 'moonclaw.book-draft-recovery.v1', state: { ...candidate, selected: candidate.source?.artifacts.map(item => item.id) || [], history: [] } }), valid)
    // restore retains current work and existing history before opening earlier work.
    need(session.state.history.length >= history.length, 'Earlier source history must remain available')
    refreshFields(); status('Reopened that exact earlier source and its saved handoff. Later work remains in history; any Book receipt must match this handoff')
  }))
  listen(node('cancel'), 'click', () => { controller?.abort(); session.cancel(); persist(); status('Interrupted read/export. The draft, original source and saved handoff were kept') })
  refreshFields(); refreshRetained()
  if (storageWarning) status(storageWarning)
  const binding = {
    session,
    changed() {
      if (root.isConnected === false || initialContext !== contextText() || initialEpoch !== epoch() || key() !== initialKey) {
        controller?.abort(); events.abort(); session.cancel(); persist(); root.dataset.bound = ''; return true
      }
      return false
    },
  }
  return binding
}

export function installBookOutcome(document) {
  let binding = null
  const bind = () => { if (binding?.changed()) binding = null; if (!binding) binding = bindBookOutcome(document) }
  new MutationObserver(bind).observe(document.documentElement, { childList: true, subtree: true })
  bind()
}
