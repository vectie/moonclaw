// Test adapter for the actual shipped controls. Only DOM/download storage is
// simulated; fetch, authentication, source freezing and serialization are real.
import assert from 'node:assert/strict'
import { webcrypto } from 'node:crypto'
import { bindBookOutcome } from './book-outcome-controls.js'
import { readHandoff } from './book-outcome.js'
if (!globalThis.crypto) globalThis.crypto = webcrypto
class Node {
  constructor() { this.value = ''; this.textContent = ''; this.dataset = {}; this.files = []; this.checked = false; this.isConnected = true; this.events = new Map() }
  addEventListener(key, fn) { this.events.set(key, fn) }
  async fire(key) { return this.events.get(key)?.() }
}
export async function verifyGatewayBookHandoff(base) {
  const nodes = new Map(), downloads = [], saved = new Map()
  const document = { getElementById(id) { if (!nodes.has(id)) nodes.set(id, new Node()); return nodes.get(id) } }
  const node = id => document.getElementById('claw-book-' + id)
  node('context').textContent = JSON.stringify({ run_id: 'run-book-http', status: 'Succeeded', artifacts: [{ id: 'book-text' }] })
  const binding = bindBookOutcome(document, { storage: { getItem: key => saved.get(key), setItem: (key, value) => saved.set(key, value) }, download: raw => downloads.push(raw) })
  node('choose-0').checked = true
  node('summary').value = 'Native HTTP fixture retained exact text; synthetic completed record, no external provider, customer or real reviewer exercised.'
  node('observed').value = '2026-10-07T01:00:00Z'
  for (const gap of ['information', 'recognition', 'decisiveness']) { node(gap + '-severity').value = '0'; node(gap + '-summary').value = 'Explicitly absent within this bounded retention fixture; no broader finding asserted.' }
  await node('choose-0').fire('change')
  await node('freeze').fire('click')
  assert.equal(binding.session.state.source, null, 'Unauthenticated source must not freeze')
  globalThis.__moonclawTransport.setToken(base, 'fixture-only-token')
  await node('freeze').fire('click')
  assert.ok(binding.session.state.source, node('status').textContent)
  assert.equal(binding.session.state.source.artifacts[0].text, '\uFEFFNative gateway text 报告\u0000<&>\n')
  await node('export').fire('click')
  assert.equal(downloads.length, 1, node('status').textContent)
  assert.equal((await readHandoff(downloads[0])).source.artifacts[0].text, '\uFEFFNative gateway text 报告\u0000<&>\n')
  const same = binding.session.state.handoff
  globalThis.__moonclawTransport.clear()
  await node('export').fire('click')
  assert.equal(downloads.length, 1)
  assert.equal(binding.session.state.handoff, same)
}
