// Exact retained revisions share the focused-source curation flow, never authority.
import { readRun, readSource, LIMIT } from './artifact-rework.js'
const need = (ok, message) => { if (!ok) throw new Error(message) }
const bytes = value => new TextEncoder().encode(value).length
export const sourceKey = source => JSON.stringify(source.provenance ? ['retained', source.provenance.run_id, source.provenance.job_id, source.provenance.artifact_id] : ['local', source.name])
export const sameSource = (left, right) => sourceKey(left) === sourceKey(right) && left.sha256 === right.sha256 && left.bytes === right.bytes && JSON.stringify(left.provenance || null) === JSON.stringify(right.provenance || null)
export function validateProvenance(item) {
  const value = item.provenance
  if (!value) { need(item.origin === undefined || item.origin === 'local_file_snapshot', 'Invalid source origin'); return }
  need(item.origin === 'retained_run_output', 'Invalid retained source origin')
  for (const key of ['run_id', 'job_id', 'artifact_id', 'content_type', 'logical_key']) need(typeof value[key] === 'string' && value[key].trim() && bytes(value[key]) <= (key === 'logical_key' ? 4000 : 1024), 'Invalid retained source identity')
  need(!value.artifact_id.startsWith('synthetic:') && /^(text\/|application\/json(?:;|$))/.test(value.content_type), 'Choose a retained textual output')
  need(Number.isSafeInteger(value.version) && value.version > 0 && ['Succeeded', 'Failed', 'Cancelled'].includes(value.original_run_status), 'Invalid retained source revision or run state')
  need(value.sha256 === item.source_sha256 && /^sha256:[a-f0-9]{64}$/.test(value.sha256) && item.source_bytes <= LIMIT && item.name === value.artifact_id, 'Invalid retained source fingerprint')
}
export async function retainedSnapshot(payload, detail, id) {
  readRun(detail, { session_key: 'source-inspection', run_id: detail?.run?.id })
  const exact = await readSource(payload, detail, id)
  need(!exact.content_utf8.includes('\0') && new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(new TextEncoder().encode(exact.content_utf8)) === exact.content_utf8, 'Choose valid UTF-8 text without binary NUL bytes')
  const { content_utf8, ...identity } = exact
  const provenance = Object.freeze({ ...identity, original_run_status: detail.run.status })
  const snapshot = { name: exact.artifact_id, content: content_utf8, bytes: bytes(content_utf8), sha256: exact.sha256, origin: 'retained_run_output', provenance }
  validateProvenance({ ...snapshot, source_sha256: snapshot.sha256, source_bytes: snapshot.bytes })
  return Object.freeze(snapshot)
}
// Caller supplies an existing read-only transport. No fallback endpoint or effect.
export function retainedReader(get) {
  return {
    async run(context, base, signal) { need(base && context.run_id, 'Choose a Work thread with a linked run and connect the gateway'); return readRun(await get(base + '/v1/jobs/runs/' + encodeURIComponent(context.run_id), signal), context) },
    async source(base, detail, id, signal) { return retainedSnapshot(await get(base + '/v1/artifacts/' + encodeURIComponent(id), signal), detail, id) },
    async verify(sources, context, base, signal, valid) {
      const selected = sources.filter(source => source.provenance)
      if (!selected.length) return
      need(selected.every(source => source.provenance.run_id === context.run_id), 'Retained source belongs to another linked run')
      const detail = await this.run(context, base, signal); valid()
      for (const selectedSource of selected) {
        const fresh = await this.source(base, detail, selectedSource.provenance.artifact_id, signal); valid()
        need(sameSource(fresh, selectedSource), 'Retained source changed; reload and inspect the revision again. Draft kept')
      }
    }
  }
}
