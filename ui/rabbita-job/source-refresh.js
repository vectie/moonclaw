// Refresh one local snapshot without guessing which changed passages the task needs.
import { SourceBrief, linesOf } from './source-brief.js'
import { sourceKey } from './retained-sources.js'
import { exportSourceProject, openSourceProject } from './source-project.js'

export const REFRESH_LINE_LIMIT = 2000
const need = (ok, message) => { if (!ok) throw new Error(message) }
const lines = text => text === '' ? [] : linesOf(text)

// KMP matches complete exact lines, including their original endings. Repeated
// passages remain separate candidates; neither offsets nor nearby text choose one.
function exactRanges(haystack, content) {
  const pattern = lines(content), prefix = new Uint32Array(pattern.length), found = []
  for (let i = 1, j = 0; i < pattern.length; i++) {
    while (j && pattern[i] !== pattern[j]) j = prefix[j - 1]
    if (pattern[i] === pattern[j]) j++
    prefix[i] = j
  }
  for (let i = 0, j = 0; i < haystack.length; i++) {
    while (j && haystack[i] !== pattern[j]) j = prefix[j - 1]
    if (haystack[i] === pattern[j]) j++
    if (j === pattern.length) { found.push({ start_line: i - j + 2, end_line: i + 1 }); j = prefix[j - 1] }
  }
  return found
}

export async function prepareSourceRefresh(session, key, replacement) {
  const originalSources = structuredClone(session.sources), baseline = await exportSourceProject(session)
  const old = JSON.parse(baseline), before = old.sources.find(source => sourceKey(source) === key)
  need(before && !before.provenance, 'Select a local source to refresh; retained outputs use their exact gateway inspector')
  need(replacement && !replacement.provenance && replacement.name === before.name, 'Choose a revised local file with the same name as the selected source')
  const stored = { name: replacement.name, content_utf8: replacement.content, bytes: replacement.bytes, sha256: replacement.sha256 }
  const check = new SourceBrief(); check.import([replacement]); await exportSourceProject(check)
  const oldLines = lines(before.content_utf8), newLines = lines(stored.content_utf8)
  need(oldLines.length <= REFRESH_LINE_LIMIT && newLines.length <= REFRESH_LINE_LIMIT, 'Refresh supports at most 2000 lines per snapshot; use ordinary import and manual excerpts for larger files. Nothing was truncated')
  const rows = old.excerpts.flatMap((item, index) => item.source_key !== key ? [] : [{ index, ...item, content_utf8: oldLines.slice(item.start_line - 1, item.end_line).join('') }])
  for (const row of rows) row.candidates = exactRanges(newLines, row.content_utf8)
  return { baseline, key, before, replacement: stored, originalSources, rows }
}

export async function previewSourceRefresh(plan, decisions) {
  need(Array.isArray(decisions) && decisions.length === plan.rows.length && decisions.every(Boolean), 'Review every old excerpt: choose an exact match, a replacement range, or explicitly drop it')
  const project = JSON.parse(plan.baseline), choices = new Map()
  plan.rows.forEach((row, i) => {
    const decision = decisions[i]
    if (decision.mode === 'drop') choices.set(row.index, null)
    else if (decision.mode === 'exact') {
      need(Number.isInteger(decision.candidate) && row.candidates[decision.candidate], 'Choose an exact candidate range for this excerpt')
      choices.set(row.index, { source_key: plan.key, ...row.candidates[decision.candidate], purpose: row.purpose })
    } else {
      need(decision.mode === 'range', 'Unknown refresh decision')
      choices.set(row.index, { source_key: plan.key, start_line: decision.start_line, end_line: decision.end_line, purpose: decision.purpose })
    }
  })
  project.sources = project.sources.map(source => sourceKey(source) === plan.key ? plan.replacement : source)
  project.excerpts = project.excerpts.flatMap((item, index) => choices.has(index) ? choices.get(index) ? [choices.get(index)] : [] : [item])
  const next = await openSourceProject(JSON.stringify(project))
  // Preserve real local/retained origins and reopened labels on untouched sources.
  next.sources = next.sources.map(source => Object.freeze(sourceKey(source) === plan.key
    ? { name: source.name, content: source.content, bytes: source.bytes, sha256: source.sha256 }
    : structuredClone(plan.originalSources.find(old => sourceKey(old) === sourceKey(source)))))
  const raw = await exportSourceProject(next)
  return { next, raw, baseline: plan.baseline }
}

export async function acceptSourceRefresh(session, preview) {
  need(preview && await exportSourceProject(session) === preview.baseline, 'Source working set changed; choose the revised file and review its excerpts again')
  need(await exportSourceProject(preview.next) === preview.raw, 'Refresh preview changed; preview again before replacing the source')
  return preview.next
}

export function describeSourceRefresh(plan) {
  return `${plan.before.name}\nBefore: ${plan.before.bytes} bytes · ${plan.before.sha256}\nRevised: ${plan.replacement.bytes} bytes · ${plan.replacement.sha256}\n${plan.rows.length} old excerpts need an explicit decision. Exact matches preserve selected bytes, not their meaning or surrounding context. Review the complete revised snapshot below. File freshness and authenticity remain unverified.`
}

export function quoteSourceLines(content) {
  return lines(content).map((line, index) => `${index + 1}: ${JSON.stringify(line)}`).join('\n') || '(empty source)'
}
