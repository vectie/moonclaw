// Bounded exact line comparison of already imported snapshots. No execution or authority.
import { linesOf, byteLength, FILE_LIMIT } from './source-brief.js'
import { sourceKey, sameSource, validateProvenance } from './retained-sources.js'
import { sha256 } from './book-outcome.js'
export const COMPARISON_LINE_LIMIT = 2000
export const COMPARISON_CELL_LIMIT = 1000000
const need = (ok, message) => { if (!ok) throw new Error(message) }
const lines = value => value === '' ? [] : linesOf(value)
const identity = source => ({ name: source.name, sha256: source.sha256, bytes: source.bytes, ...(source.provenance ? { origin: source.origin, provenance: structuredClone(source.provenance) } : {}) })
async function validate(source) {
  need(source && typeof source.name === 'string' && source.name.trim() && typeof source.content === 'string', 'Choose two imported text snapshots')
  need(!source.content.includes('\0') && byteLength(source.content) === source.bytes && source.bytes <= FILE_LIMIT && new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(new TextEncoder().encode(source.content)) === source.content, 'Source bytes are invalid; import the snapshot again')
  need(source.sha256 === await sha256(source.content), 'Source fingerprint changed; import the snapshot again')
  validateProvenance({ ...source, source_sha256: source.sha256, source_bytes: source.bytes })
  const result = lines(source.content)
  need(result.length <= COMPARISON_LINE_LIMIT, 'Comparison supports at most 2000 lines per snapshot; select smaller source files or inspect excerpts manually. Nothing was truncated')
  return result
}
const span = (sourceLines, start, end) => end === start ? null : ({ start_line: start + 1, end_line: end, content_utf8: sourceLines.slice(start, end).join('') })
export async function compareSources(before, after) {
  need(before && after && sourceKey(before) !== sourceKey(after), 'Choose two distinct imported source identities')
  const [left, right] = await Promise.all([validate(before), validate(after)])
  let prefix = 0, tail = 0
  while (prefix < left.length && prefix < right.length && left[prefix] === right[prefix]) prefix++
  while (tail < left.length - prefix && tail < right.length - prefix && left[left.length - tail - 1] === right[right.length - tail - 1]) tail++
  const a = left.slice(prefix, left.length - tail), b = right.slice(prefix, right.length - tail)
  need((a.length + 1) * (b.length + 1) <= COMPARISON_CELL_LIMIT, 'The changed region exceeds the bounded comparison limit (1000000 cells). Inspect smaller snapshots or select passages manually. Nothing was truncated')
  const width = b.length + 1, grid = new Uint16Array((a.length + 1) * width)
  for (let i = a.length - 1; i >= 0; i--) for (let j = b.length - 1; j >= 0; j--) grid[i * width + j] = a[i] === b[j] ? 1 + grid[(i + 1) * width + j + 1] : Math.max(grid[(i + 1) * width + j], grid[i * width + j + 1])
  const changes = []; let i = 0, j = 0, startI = 0, startJ = 0
  const flush = () => {
    if (i === startI && j === startJ) return
    const old = span(left, prefix + startI, prefix + i), next = span(right, prefix + startJ, prefix + j)
    changes.push({ kind: old ? next ? 'replaced' : 'removed' : 'added', before: old, after: next, before_context: { preceding: span(left, Math.max(0, prefix + startI - 2), prefix + startI), following: span(left, prefix + i, Math.min(left.length, prefix + i + 2)) }, after_context: { preceding: span(right, Math.max(0, prefix + startJ - 2), prefix + startJ), following: span(right, prefix + j, Math.min(right.length, prefix + j + 2)) } })
  }
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] === b[j]) { flush(); i++; j++; startI = i; startJ = j }
    else if (i < a.length && (j === b.length || grid[(i + 1) * width + j] >= grid[i * width + j + 1])) i++
    else j++
  }
  flush()
  return { before: identity(before), after: identity(after), changes, before_lines: left.length, after_lines: right.length, algorithm: 'bounded_exact_line_lcs', cells: grid.length }
}
export function comparisonCurrent(result, before, after) {
  return !!result && !!before && !!after && sameSource(result.before, before) && sameSource(result.after, after)
}
export async function changeRange(result, before, after, index, side) {
  need(comparisonCurrent(result, before, after), 'Compared snapshots changed; compare again before choosing a range')
  need(Number.isInteger(index) && index >= 0 && index < result.changes.length && ['before', 'after'].includes(side), 'Choose a comparison change and side')
  const source = side === 'before' ? before : after, sourceLines = await validate(source), selected = result.changes[index][side]
  need(selected, 'This side has no changed lines; choose the other side')
  need(sourceLines.slice(selected.start_line - 1, selected.end_line).join('') === selected.content_utf8, 'Compared range changed; compare again')
  return { source_key: sourceKey(source), ...selected }
}
export function formatChange(change) {
  const show = (title, value, marker) => title + '\n' + (value ? lines(value.content_utf8).map((line, i) => marker + ' ' + (value.start_line + i) + ': ' + JSON.stringify(line)).join('\n') : '(no lines)')
  return ['Exact changed lines are quoted so whitespace and line endings remain visible. Nearby context is only for inspection and is not selected.', show('BEFORE context', change.before_context.preceding, ' '), show('BEFORE changed', change.before, '-'), show('BEFORE following', change.before_context.following, ' '), show('AFTER context', change.after_context.preceding, ' '), show('AFTER changed', change.after, '+'), show('AFTER following', change.after_context.following, ' ')].join('\n\n')
}
