// Execution is observed evidence. Operators author cases; MoonBook owns review.
import { readRun } from './artifact-rework.js'
import { sha256 } from './book-outcome.js'
export const caseHeader = ['kind', 'name', 'input', 'original', 'revised', 'required', 'forbidden']
const need = (ok, message) => { if (!ok) throw new Error(message) }
const encoder = new TextEncoder()
const validText = (value, limit, label, blank = false) => {
  need(typeof value === 'string' && value.length <= limit && (blank ? value === '' || value.trim() : value.trim()), `${label} needs ${blank ? 'empty or nonblank' : 'nonblank'} text within ${limit} characters`)
  need(!/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]|\r(?!\n)/.test(value), `${label} contains unsupported controls or bare CR; use LF or CRLF`)
  need(new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(encoder.encode(value)) === value, `${label} contains invalid Unicode`)
  return value
}
export function sourceLines(source) { return source.content_utf8.match(/[^\n]*\n|[^\n]+$/g) || [''] }
export function sourceExcerpt(source, start, end) {
  const lines = sourceLines(source)
  need(Number.isSafeInteger(start) && Number.isSafeInteger(end) && start >= 1 && end >= start && end <= lines.length, `Choose an exact line range from 1 to ${lines.length}`)
  return validText(lines.slice(start - 1, end).join(''), 8192, 'Original output excerpt')
}
export async function createObservedCase(context, detail, source, fields) {
  readRun(detail, context)
  need(source && detail.artifacts.some(item => item.id === source.artifact_id && item.version === source.version && item.run_id === source.run_id && item.job_id === source.job_id), 'Selected source does not belong to the retained run revision')
  need(await sha256(source.content_utf8) === source.sha256, 'Retained source bytes changed')
  need(['useful', 'adverse'].includes(fields.kind), 'Explicitly label the observed case useful or adverse; run success is not an outcome judgment')
  const original = sourceExcerpt(source, fields.start, fields.end)
  const name = validText(fields.name, 80, 'Case name') + ` [${detail.run.status} run=${source.run_id} artifact=${source.artifact_id} v${source.version} L${fields.start}-${fields.end} ${source.sha256}]`
  validText(name, 256, 'Case name with exact source identity')
  const row = { kind: fields.kind, name, input: validText(fields.input, 8192, 'Observed task input'), original, revised: validText(fields.revised, 8192, 'Revised output', true), required: validText(fields.required, 5140, 'Required fragments', true), forbidden: validText(fields.forbidden, 5140, 'Forbidden fragments', true) }
  const parts = key => row[key] === '' ? [] : row[key].split(/\r?\n/)
  const required = parts('required'), forbidden = parts('forbidden'), all = [...required, ...forbidden]
  need(all.length >= 1 && all.length <= 20, 'Supply 1–20 literal checks in total')
  for (const values of [required, forbidden]) need(values.every(item => item.length && item.length <= 256 && item.trim() === item) && new Set(values).size === values.length, 'Checks need distinct nonblank lines within 256 characters, without surrounding whitespace')
  need(!required.some(value => forbidden.some(no => value.includes(no))), 'A required fragment contains a forbidden fragment')
  return structuredClone({ context, detail, source, fields, row })
}
export async function exportObservedCases(cases) {
  need(Array.isArray(cases) && cases.length >= 1 && cases.length <= 6, 'Choose 1–6 observed cases')
  const rows = [], seen = new Set()
  for (const item of cases) {
    const verified = await createObservedCase(item.context, item.detail, item.source, item.fields)
    need(JSON.stringify(verified.row) === JSON.stringify(item.row), 'A queued case changed; remove it and add the inspected source again')
    need(!seen.has(item.row.input.trim()), 'Case task inputs must be distinct; remove the repeated input before exporting')
    seen.add(item.row.input.trim()); rows.push(item.row)
  }
  const cell = value => '"' + value.replaceAll('"', '""') + '"'
  const csv = caseHeader.join(',') + '\r\n' + rows.map(row => caseHeader.map(key => cell(row[key])).join(',')).join('\r\n') + '\r\n'
  need(encoder.encode(csv).length <= 131072, 'Case CSV exceeds the MoonBook 128 KiB import limit; no text was truncated')
  return csv
}
export function downloadObservedCases(csv, document = globalThis.document, url = globalThis.URL) {
  const href = url.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' })), link = document.createElement('a')
  try { link.href = href; link.download = 'moonclaw-observed-cases.csv'; document.body.appendChild(link); link.click() }
  finally { link.remove(); setTimeout(() => url.revokeObjectURL(href), 1000) }
}
