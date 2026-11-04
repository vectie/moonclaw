// Saved Git patches are quoted task inputs, never instructions to apply a patch.
import { linesOf, byteLength } from './source-brief.js'
import { sha256 } from './book-outcome.js'
const need = (ok, message) => { if (!ok) throw new Error(message) }
export function parseSavedDiff(content) {
  const lines = linesOf(content), files = []
  need(!lines.some(line => /^diff --(?:cc|combined) /.test(line)), 'Combined Git diffs are unsupported; save a normal Git unified diff')
  let i = 0
  while (i < lines.length) {
    if (!lines[i].startsWith('diff --git ')) { i++; continue }
    const start = i++, file = { id: String(files.length), label: lines[start].replace(/\r?\n$/, '').slice(11), header: '', hunks: [], note: '' }
    while (i < lines.length && !lines[i].startsWith('diff --git ') && !lines[i].startsWith('@@')) i++
    file.header = lines.slice(start, i).join('')
    while (i < lines.length && lines[i].startsWith('@@')) {
      const hstart = i, match = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/.exec(lines[i++])
      need(match, 'Combined or malformed diff hunks are unsupported; save a normal Git unified diff')
      need(/^--- /m.test(file.header) && /^\+\+\+ /m.test(file.header), 'A text hunk is missing its file headers')
      const oldCount = Number(match[2] ?? 1), newCount = Number(match[4] ?? 1)
      let old = 0, next = 0
      while (i < lines.length) {
        const line = lines[i]
        if (line.startsWith('\\ No newline at end of file')) { i++; continue }
        if (old === oldCount && next === newCount) break
        if (line.startsWith(' ')) { old++; next++ }
        else if (line.startsWith('-')) old++
        else if (line.startsWith('+')) next++
        else throw new Error('Incomplete diff hunk; save the full unified diff with context')
        need(old <= oldCount && next <= newCount, 'Diff hunk line counts do not match its header')
        i++
      }
      need(old === oldCount && next === newCount, 'Incomplete diff hunk; save the full unified diff with context')
      file.hunks.push({ id: file.id + ':' + file.hunks.length, label: lines[hstart].replace(/\r?\n$/, ''), content: lines.slice(hstart, i).join(''), start_line: hstart + 1, end_line: i })
    }
    if (!file.hunks.length) file.note = /GIT binary patch|Binary files /.test(file.header) ? 'Binary change: no selectable text hunks' : 'Metadata-only change: no selectable text hunks'
    files.push(file)
  }
  need(files.length, 'No Git unified diff found. Save git diff output as a .patch or .diff file')
  return { files, hunkCount: files.reduce((n, file) => n + file.hunks.length, 0) }
}
export function selectedDiffText(parsed, selected) {
  const ids = new Set(selected), available = parsed.files.flatMap(file => file.hunks.map(hunk => hunk.id))
  need(ids.size && [...ids].every(id => available.includes(id)), 'Choose at least one text hunk')
  return parsed.files.map(file => {
    const hunks = file.hunks.filter(hunk => ids.has(hunk.id))
    return hunks.length ? file.header + hunks.map(hunk => hunk.content).join('') : ''
  }).join('')
}
export async function selectedDiffSource(original, parsed, selected) {
  const content = selectedDiffText(parsed, selected)
  return Object.freeze({ name: original.name + ' (selected Git hunks)', content, bytes: byteLength(content), sha256: await sha256(content) })
}
