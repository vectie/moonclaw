import { readLocalFiles, linesOf } from './source-brief.js'
import { prepareSourceRefresh, previewSourceRefresh, acceptSourceRefresh, describeSourceRefresh, quoteSourceLines } from './source-refresh.js'
const need = (ok, message) => { if (!ok) throw new Error(message) }

export function mountSourceRefresh(document, root) {
  const panel = document.createElement('details'); panel.id = 'claw-sources-refresh-panel'; root.appendChild(panel)
  const add = (tag, key, text) => { const node = document.createElement(tag); if (key) node.id = 'claw-sources-refresh-' + key; node.textContent = text; panel.appendChild(node); return node }
  const field = (tag, key, title) => { const label = add('label', '', title); label.htmlFor = 'claw-sources-refresh-' + key; return add(tag, key, '') }
  const button = (key, text) => { const node = add('button', key, text); node.type = 'button'; return node }
  add('summary', '', 'Refresh a local source and review its excerpts')
  add('p', '', 'Select a local source in the editor above, then choose its revised same-name file here. Review each old excerpt against the new snapshot. Nothing changes until you preview and replace the unsent working set. Save a source project first if you want to retain the old snapshot.')
  field('input', 'file', 'Choose the revised file (same local name, at most 256 KiB)').type = 'file'
  add('p', 'info', 'Choose a local source above, then its revised file.')
  const contents = add('details', 'contents', ''), summary = document.createElement('summary'), text = document.createElement('pre')
  summary.textContent = 'Inspect every revised line, with exact whitespace and line endings'; contents.appendChild(summary); text.id = 'claw-sources-refresh-lines'; contents.appendChild(text)
  field('select', 'excerpt', 'Old excerpt to review')
  add('pre', 'old', '')
  field('select', 'candidate', 'Exact matching range (no automatic choice)')
  button('exact', 'Keep chosen exact match')
  for (const [key, label] of [['start', 'Revised first line'], ['end', 'Revised last line']]) { const node = field('input', key, label); node.type = 'number'; node.min = '1'; node.step = '1' }
  field('textarea', 'purpose', 'Relevance note for a replacement range')
  button('range', 'Use revised line range')
  button('drop', 'Drop this excerpt from the refreshed selection')
  add('pre', 'decisions', '')
  button('preview', 'Preview refreshed working set')
  add('pre', 'preview-text', '')
  button('apply', 'Replace source with previewed refresh').disabled = true
  return panel
}

// The host owns context/generation cancellation and its ordinary composer. This
// panel only prepares a new SourceBrief; it never sends or edits a task itself.
export function bindSourceRefresh(document, host) {
  const node = key => document.getElementById('claw-sources-refresh-' + key)
  let plan = null, decisions = [], preview = null
  const options = (target, entries) => {
    target.replaceChildren()
    for (const [value, label] of [['', 'Choose…'], ...entries]) { const option = document.createElement('option'); option.value = value; option.textContent = label; target.appendChild(option) }
    target.value = ''
  }
  const picked = () => { const value = node('excerpt').value; need(plan && value !== '' && plan.rows[Number(value)], 'Choose an old excerpt to review'); return Number(value) }
  const decisionView = () => { node('decisions').textContent = plan ? plan.rows.map((row, index) => `${index + 1}. Old lines ${row.start_line}–${row.end_line}: ${decisions[index] ? JSON.stringify(decisions[index]) : 'needs review'}`).join('\n') || 'No old excerpts. Preview to replace only the source snapshot.' : '' }
  const rowView = () => {
    const index = picked(), row = plan.rows[index]
    node('old').textContent = `Old lines ${row.start_line}–${row.end_line}\nRelevance: ${row.purpose}\nExact old text: ${JSON.stringify(row.content_utf8)}\n${row.candidates.length} exact matches. ${row.candidates.length ? 'Inspect surrounding revised lines before choosing.' : 'The passage changed or disappeared. Select revised lines with a relevance note, or explicitly drop it.'}`
    options(node('candidate'), row.candidates.map((range, i) => [String(i), `Lines ${range.start_line}–${range.end_line}`]))
    node('start').value = ''; node('end').value = ''; node('purpose').value = row.purpose
  }
  const invalidate = keepPlan => {
    preview = null; node('preview-text').textContent = ''; node('apply').disabled = true
    if (keepPlan) return
    plan = null; decisions = []; node('file').value = ''; node('info').textContent = 'Choose a local source above, then its revised file.'
    for (const key of ['old', 'lines', 'decisions']) node(key).textContent = ''
    for (const key of ['excerpt', 'candidate']) options(node(key), [])
    for (const key of ['start', 'end', 'purpose']) node(key).value = ''
  }
  host.listen(node('file'), 'change', async () => {
    const files = Array.from(node('file').files || []); host.invalidate()
    if (!files.length) return
    await host.perform(async (_, valid) => {
      need(files.length === 1, 'Choose exactly one revised source file')
      const key = host.selectedSource(), [replacement] = await readLocalFiles(files); valid()
      const prepared = await prepareSourceRefresh(host.getSession(), key, replacement); valid()
      plan = prepared; decisions = plan.rows.map(() => null); node('info').textContent = describeSourceRefresh(plan); node('lines').textContent = quoteSourceLines(plan.replacement.content_utf8)
      options(node('excerpt'), plan.rows.map((row, index) => [String(index), `${index + 1}. Old lines ${row.start_line}–${row.end_line} · ${row.candidates.length} exact matches`]))
      if (plan.rows.length) { node('excerpt').value = '0'; rowView() }
      decisionView(); host.status('Revised snapshot loaded for review. Choose a decision for every old excerpt, then preview. Sources and the task draft are unchanged.')
    })()
  })
  host.listen(node('excerpt'), 'change', host.action(rowView))
  for (const [key, event] of [['candidate', 'change'], ['start', 'input'], ['end', 'input'], ['purpose', 'input']]) host.listen(node(key), event, host.action(() => {}))
  for (const mode of ['exact', 'range', 'drop']) host.listen(node(mode), 'click', host.action(() => {
    const index = picked(), row = plan.rows[index]
    if (mode === 'exact') { need(node('candidate').value !== '' && row.candidates[Number(node('candidate').value)], 'Choose an exact matching range'); decisions[index] = { mode, candidate: Number(node('candidate').value) } }
    if (mode === 'range') {
      const check = { mode, start_line: Number(node('start').value), end_line: Number(node('end').value), purpose: node('purpose').value.trim() }
      need(Number.isSafeInteger(check.start_line) && check.start_line >= 1 && Number.isSafeInteger(check.end_line) && check.end_line >= check.start_line && plan.replacement.content_utf8 !== '' && check.end_line <= linesOf(plan.replacement.content_utf8).length && check.purpose, 'Choose valid revised line numbers and a relevance note')
      decisions[index] = check
    }
    if (mode === 'drop') decisions[index] = { mode }
    decisionView(); host.status('Refresh decision recorded for this excerpt. Review all decisions and preview before replacing the source.')
  }))
  host.listen(node('preview'), 'click', host.perform(async (_, valid) => {
    need(plan, 'Choose a revised file first')
    const result = await previewSourceRefresh(plan, decisions); valid(); preview = result
    node('preview-text').textContent = 'Complete proposed source project, including every source byte and the final ordered excerpts:\n' + result.raw; node('apply').disabled = false
    host.status('Refreshed working set ready for inspection. Replacing updates only unsent sources and excerpts; any existing task draft remains unchanged.')
  }))
  host.listen(node('apply'), 'click', () => {
    const prepared = preview
    return host.perform(async (_, valid) => {
      const next = await acceptSourceRefresh(host.getSession(), prepared); valid(); host.replaceSession(next); invalidate(false)
      host.status('Local source and reviewed excerpts replaced. Notes and task order were retained for kept excerpts. Preview and apply the ordinary source brief to update the task draft; save a source project to keep this revision.')
    })()
  })
  host.listen(node('panel'), 'toggle', () => { if (!node('panel').open) host.invalidate() })
  return { invalidate }
}
