// Portable source-authoring work, never a saved approval or a live-file reference.
import { SourceBrief, byteLength, FILE_LIMIT, SOURCE_LIMIT } from './source-brief.js'
import { sha256 } from './book-outcome.js'
import { sourceKey, validateProvenance } from './retained-sources.js'

export const PROJECT_LIMIT = 8 * 1024 * 1024
const VERSION = 'moonclaw.source-project.v1'
const PROVENANCE_KEYS = ['run_id', 'job_id', 'artifact_id', 'version', 'content_type', 'logical_key', 'sha256', 'original_run_status']
const need = (ok, message) => { if (!ok) throw new Error(message) }
const keys = (value, allowed, label) => need(value && typeof value === 'object' && !Array.isArray(value) && Object.keys(value).every(key => allowed.includes(key)), 'Invalid ' + label + ' fields')
const utf8 = value => typeof value === 'string' && new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(new TextEncoder().encode(value)) === value

// Rebuild through the ordinary editor's range/overlap/budget checks. No caller's
// working set changes until the whole project has been decoded and validated.
export async function openSourceProject(raw) {
  need(utf8(raw) && byteLength(raw) <= PROJECT_LIMIT, 'Source project must be valid UTF-8 and at most 8 MiB')
  const project = JSON.parse(raw)
  keys(project, ['contract_version', 'authority_granted', 'accepted_knowledge', 'disk_freshness_verified', 'excerpt_budget_bytes', 'sources', 'excerpts'], 'source project')
  need(project.contract_version === VERSION && project.authority_granted === false && project.accepted_knowledge === false && project.disk_freshness_verified === false, 'Unsupported source project or authority/freshness claims')
  need(Array.isArray(project.sources) && project.sources.length > 0 && project.sources.length <= 8, 'A source project needs one to eight sources')
  need(Array.isArray(project.excerpts) && project.excerpts.length <= 8, 'A source project allows at most eight excerpts')
  const session = new SourceBrief(), seen = new Set(); let total = 0
  session.setBudget(project.excerpt_budget_bytes)
  for (const stored of project.sources) {
    keys(stored, ['name', 'content_utf8', 'bytes', 'sha256', 'origin', 'provenance'], 'source')
    need(utf8(stored.name) && stored.name.trim() && byteLength(stored.name) <= 1024, 'Invalid source name')
    need(utf8(stored.content_utf8) && !stored.content_utf8.includes('\0'), 'Source content must be valid UTF-8 without binary NUL bytes')
    need(Number.isSafeInteger(stored.bytes) && stored.bytes === byteLength(stored.content_utf8) && stored.bytes <= FILE_LIMIT, 'Source byte count changed or exceeds 256 KiB')
    total += stored.bytes; need(total <= SOURCE_LIMIT, 'Source project exceeds 1 MiB of source content')
    need(/^sha256:[a-f0-9]{64}$/.test(stored.sha256) && stored.sha256 === await sha256(stored.content_utf8), 'Source fingerprint does not match its saved bytes')
    if (stored.provenance !== undefined) keys(stored.provenance, PROVENANCE_KEYS, 'retained provenance')
    validateProvenance({ ...stored, source_sha256: stored.sha256, source_bytes: stored.bytes })
    const source = Object.freeze({ name: stored.name, content: stored.content_utf8, bytes: stored.bytes, sha256: stored.sha256, ...(stored.origin ? { origin: stored.origin } : {}), ...(stored.provenance ? { provenance: Object.freeze(Object.fromEntries(PROVENANCE_KEYS.map(key => [key, stored.provenance[key]]))) } : {}), restored_from_project: true })
    const key = sourceKey(source)
    need(!seen.has(key), 'Duplicate source identity in saved project'); seen.add(key)
    session.import([source])
  }
  for (const item of project.excerpts) {
    keys(item, ['source_key', 'start_line', 'end_line', 'purpose'], 'excerpt')
    need(typeof item.source_key === 'string' && seen.has(item.source_key), 'Excerpt references a missing source')
    need(utf8(item.purpose) && item.purpose.trim() === item.purpose, 'Invalid saved relevance note')
    session.put(item.source_key, item.start_line, item.end_line, item.purpose)
  }
  return session
}

export async function exportSourceProject(session) {
  // Copy all state before the first await, including untouched imported sources.
  const snapshot = structuredClone({ sources: session.sources, excerpts: session.excerpts, budget: session.budget })
  const project = {
    contract_version: VERSION, authority_granted: false, accepted_knowledge: false, disk_freshness_verified: false,
    excerpt_budget_bytes: snapshot.budget,
    sources: snapshot.sources.map(source => ({ name: source.name, content_utf8: source.content, bytes: source.bytes, sha256: source.sha256, ...(source.origin ? { origin: source.origin } : {}), ...(source.provenance ? { provenance: source.provenance } : {}) })),
    excerpts: snapshot.excerpts.map(item => ({ source_key: sourceKey(item), start_line: item.start_line, end_line: item.end_line, purpose: item.purpose })),
  }
  const raw = JSON.stringify(project, null, 2), rebuilt = await openSourceProject(raw)
  need(JSON.stringify(rebuilt.excerpts) === JSON.stringify(snapshot.excerpts), 'An excerpt no longer matches its source; inspect and select again')
  return raw
}

export async function readSourceProjectFile(file) {
  need(file && Number.isSafeInteger(file.size) && file.size > 0 && file.size <= PROJECT_LIMIT, 'Choose one source-project JSON file of at most 8 MiB')
  const bytes = await file.arrayBuffer()
  need(bytes.byteLength === file.size && bytes.byteLength <= PROJECT_LIMIT, 'Project bytes changed while reading; choose the file again')
  let raw
  try { raw = new TextDecoder('utf-8', { fatal: true }).decode(bytes) }
  catch { throw new Error('Source project file must be UTF-8 JSON') }
  return { session: await openSourceProject(raw), raw }
}

export function checkSourceProjectContext(session, context) {
  need(session.sources.every(source => !source.provenance || source.provenance.run_id === context.run_id), 'This project contains retained snapshots from another linked run. Open its original Work thread; no sources or draft were replaced')
}

export function describeSourceProject(session) {
  const retained = session.sources.filter(source => source.provenance).length
  return `${session.sources.length} saved snapshots (${retained} retained), ${session.excerpts.length} ordered excerpts, ${session.bytes} / ${session.budget} selected UTF-8 bytes. All ${session.sources.reduce((sum, item) => sum + item.bytes, 0)} source bytes are included, even omitted lines and unselected sources. File authenticity and disk freshness are unverified. Retained provenance is a stored claim until the existing gateway rereads succeed. The task draft and approvals are not saved.`
}

export function downloadSourceProject(raw, document = globalThis.document, url = globalThis.URL) {
  const href = url.createObjectURL(new Blob([raw], { type: 'application/json;charset=utf-8' })), link = document.createElement('a')
  try { link.href = href; link.download = 'moonclaw-source-project.json'; document.body.appendChild(link); link.click() }
  finally { link.remove(); setTimeout(() => url.revokeObjectURL(href), 1000) }
}
