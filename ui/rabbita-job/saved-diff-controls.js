import { readLocalFiles, linesOf } from './source-brief.js'
import { parseSavedDiff, selectedDiffText, selectedDiffSource } from './saved-diff.js'
const need = (ok, message) => { if (!ok) throw new Error(message) }
export function mountSavedDiff(document, root) {
  const add = (tag, key, text) => { const n = document.createElement(tag); n.id = 'claw-diff-' + key; n.textContent = text; root.appendChild(n); return n }
  const field = (tag, key, title) => { add('label', key + '-label', title).htmlFor = 'claw-diff-' + key; return add(tag, key, '') }
  const button = (key, text) => { const n = add('button', key, text); n.type = 'button'; return n }
  add('h4', 'title', 'Plan from a saved Git diff')
  add('p', 'help', 'Open a UTF-8 .patch or .diff (up to 256 KiB), inspect files and exact hunks, and keep only relevant changes. This reads a frozen file; it never applies patches. Binary and metadata-only changes are listed but cannot be selected.')
  const input = field('input', 'file', 'Open saved Git diff'); input.type = 'file'; input.accept = '.patch,.diff,text/plain'
  field('select', 'path', 'Changed file'); field('select', 'hunk', 'Hunk in this file')
  add('pre', 'text', ''); button('keep', 'Keep this hunk'); button('drop', 'Remove this hunk from selection')
  add('p', 'info', 'No diff opened.'); add('pre', 'selected', '')
  field('textarea', 'request', 'Request for the selected changes (keep the overall objective in the main task draft)')
  field('textarea', 'checks', 'Expected result and checks')
  button('stage', 'Add selected diff to source brief')
}
export function bindSavedDiff(document, api) {
  const node = key => document.getElementById('claw-diff-' + key)
  let original = null, parsed = null, selected = new Set()
  const options = (target, entries) => { target.replaceChildren(); for (const [value, text] of entries) { const n = document.createElement('option'); n.value = value; n.textContent = text; target.appendChild(n) }; target.value = entries[0]?.[0] || '' }
  const file = () => parsed?.files.find(item => item.id === node('path').value)
  const hunk = () => file()?.hunks.find(item => item.id === node('hunk').value)
  const render = () => {
    node('text').textContent = file() ? file().header + (hunk()?.content || file().note) : ''
    node('selected').textContent = selected.size ? selectedDiffText(parsed, selected) : ''
    node('info').textContent = parsed ? `${parsed.files.length} files · ${parsed.hunkCount} text hunks · ${selected.size} selected. Selection preview includes complete file headers and hunk context, in original patch order.` : 'No diff opened.'
  }
  const paths = () => { options(node('hunk'), (file()?.hunks || []).map(item => [item.id, item.label])); render() }
  api.listen(node('file'), 'change', async () => {
    const files = Array.from(node('file').files || [])
    if (!files.length) return
    await api.perform(async (_, valid) => {
      need(files.length === 1, 'Choose one saved Git diff')
      const [source] = await readLocalFiles(files), next = parseSavedDiff(source.content); valid()
      original = source; parsed = next; selected = new Set(); node('file').value = ''
      options(node('path'), parsed.files.map(item => [item.id, item.label + ' · ' + item.hunks.length + ' hunks'])); paths()
      api.status('Diff opened. Inspect and keep exact hunks; the draft and source brief are unchanged.')
    })()
  })
  api.listen(node('path'), 'change', api.action(paths))
  api.listen(node('hunk'), 'change', api.action(render))
  for (const [key, keep] of [['keep', true], ['drop', false]]) api.listen(node(key), 'click', api.action(() => { need(hunk(), 'Choose a text hunk'); keep ? selected.add(hunk().id) : selected.delete(hunk().id); render() }))
  for (const key of ['request', 'checks']) api.listen(node(key), 'input', api.action(() => {}))
  api.listen(node('stage'), 'click', api.perform(async (_, valid) => {
    need(original && parsed, 'Open a saved Git diff first')
    const request = node('request').value.trim(), checks = node('checks').value.trim()
    need(request && checks, 'Describe the request and expected checks for these hunks')
    const source = await selectedDiffSource(original, parsed, selected); valid()
    const purpose = `Saved diff ${original.name}; original SHA-256 ${original.sha256}. Only selected hunks; omitted changes may matter. Request: ${request}\nChecks: ${checks}`
    api.stage(source, linesOf(source.content).length, purpose)
    api.status('Selected hunks added as a source excerpt. Review the source brief preview, put it in the draft, then use ordinary Plan. No patch was applied.')
  }))
  return { reset() { original = null; parsed = null; selected = new Set(); for (const key of ['file', 'request', 'checks']) node(key).value = ''; options(node('path'), []); options(node('hunk'), []); render() } }
}
