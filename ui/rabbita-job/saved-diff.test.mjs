import test from 'node:test'
import assert from 'node:assert/strict'
import { webcrypto } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { parseSavedDiff, selectedDiffText } from './saved-diff.js'
import { readPacket } from './source-brief.js'
import { mountSourceBrief, bindSourceBrief } from './source-brief-controls.js'
if (!globalThis.crypto) globalThis.crypto = webcrypto
const header = 'diff --git a/hello.mbt b/hello.mbt\nindex 123..456 100644\n--- a/hello.mbt\n+++ b/hello.mbt\n'
const first = '@@ -1,2 +1,2 @@ greet\n context\n-old\n+new\n'
const second = '@@ -20 +20 @@ later\n-unused\n+omitted\n'
const addedHeader = 'diff --git a/new.txt b/new.txt\nnew file mode 100644\n--- /dev/null\n+++ b/new.txt\n'
const added = '@@ -0,0 +1 @@\n+東京\n\\ No newline at end of file\n'
const binary = 'diff --git a/image.png b/image.png\nBinary files a/image.png and b/image.png differ\n'
const patch = header + first + second + addedHeader + added + binary
const file = (text = patch) => { const bytes = new TextEncoder().encode(text); return { name: 'review.patch', size: bytes.length, arrayBuffer: async () => bytes.buffer } }

test('saved Git diff offers separate files/hunks and exact contextual selection in patch order', async () => {
  const parsed = parseSavedDiff(patch)
  assert.equal(parsed.files.length, 3); assert.equal(parsed.hunkCount, 3)
  assert.equal(parsed.files[0].hunks[0].content, first); assert.equal(parsed.files[0].hunks[1].content, second)
  assert.match(parsed.files[2].note, /Binary change/)
  assert.equal(selectedDiffText(parsed, ['1:0', '0:0']), header + first + addedHeader + added)
  assert.doesNotMatch(selectedDiffText(parsed, ['0:0']), /omitted|image.png|東京/)
  const shipped = parseSavedDiff(await readFile(new URL('../../docs/examples/saved-diff-demo.patch', import.meta.url), 'utf8'))
  assert.equal(shipped.hunkCount, 3); assert.equal(shipped.files.length, 2)
  const chosen = selectedDiffText(shipped, ['0:0', '1:0']); assert.match(chosen, /Hello, Moon/); assert.doesNotMatch(chosen, /Unrelated/)
})
test('CRLF, deleted files, rename metadata, zero counts and missing final newline remain exact', () => {
  const raw = 'diff --git "a/old name" "b/new name"\r\nsimilarity index 80%\r\nrename from old name\r\nrename to new name\r\n--- "a/old name"\r\n+++ "b/new name"\r\n@@ -1 +1 @@\r\n-old\r\n+new\r\n\\ No newline at end of file'
  assert.equal(selectedDiffText(parseSavedDiff(raw), ['0:0']), raw)
  const deleted = 'diff --git a/gone b/gone\n--- a/gone\n+++ /dev/null\n@@ -1 +0,0 @@\n-gone\n'
  assert.equal(selectedDiffText(parseSavedDiff(deleted), ['0:0']), deleted)
  const metadata = parseSavedDiff('diff --git a/a b/b\nsimilarity index 100%\nrename from a\nrename to b\n')
  assert.equal(metadata.hunkCount, 0); assert.match(metadata.files[0].note, /Metadata-only/)
})
test('incomplete and combined hunks explain unsupported input; no partial inferred hunk', () => {
  assert.throws(() => parseSavedDiff(header + '@@ -1,2 +1,2 @@\n-old\n+new\n'), /Incomplete/)
  assert.throws(() => parseSavedDiff(header + '@@@ -1 -1 +1 @@@\n'), /Combined/)
  for (const kind of ['cc', 'combined']) {
    const combined = `diff --${kind} merged.mbt\nindex 123,456..789\n--- a/merged.mbt\n+++ b/merged.mbt\n@@@ -1,1 -1,1 +1,1 @@@\n++merged\n`
    assert.throws(() => parseSavedDiff(combined), /Combined Git diffs are unsupported/)
    assert.throws(() => parseSavedDiff(header + first + combined), /Combined Git diffs are unsupported/)
  }
  assert.throws(() => parseSavedDiff('ordinary notes'), /No Git unified diff/)
  assert.throws(() => selectedDiffText(parseSavedDiff(patch), []), /Choose/)
})

// The repository's lightweight DOM harness, exercising production mount/bind handlers.
class Node {
  constructor(document, tag) { this.document = document; this.tagName = tag; this._value = ''; this.textContent = ''; this.dataset = {}; this.isConnected = true; this.events = new Map(); this.children = []; this.files = [] }
  set value(value) { this._value = this.tagName === 'select' && !this.children.some(node => node.value === value) ? '' : value } get value() { return this._value }
  set id(value) { this._id = value; this.document.nodes.set(value, this) } get id() { return this._id }
  setAttribute() {}
  appendChild(node) { this.children.push(node) }
  replaceChildren() { this.children = []; this.value = '' }
  insertAdjacentElement(_, node) { this.after = node }
  addEventListener(type, fn, options = {}) { const handlers = this.events.get(type) || []; handlers.push(fn); this.events.set(type, handlers); options.signal?.addEventListener('abort', () => this.events.set(type, (this.events.get(type) || []).filter(item => item !== fn)), { once: true }) }
  dispatchEvent(event) { for (const fn of this.events.get(event.type) || []) fn(event); return true }
  async fire(type) { for (const fn of this.events.get(type) || []) await fn() }
}
function surface() {
  const document = { nodes: new Map(), getElementById(id) { return this.nodes.get(id) || null }, createElement(tag) { return new Node(this, tag) } }
  const add = id => { const n = document.createElement('div'); n.id = id; return n }
  const anchor = add('claw-procedure-panel'), context = add('claw-procedure-context'), composer = add('claw-procedure-composer')
  context.textContent = JSON.stringify({ session_key: 'work-review', cwd: '/fixture/repo', cwd_override: '' }); composer.value = 'Review the greeting change and propose a fix.\n'
  mountSourceBrief(document, anchor)
  let inputs = 0; composer.addEventListener('input', () => inputs++)
  const binding = bindSourceBrief(document, { fetch: () => { throw new Error('Unexpected network call') } })
  return { document, context, composer, binding, get inputs() { return inputs }, diff: key => document.getElementById('claw-diff-' + key), source: key => document.getElementById('claw-sources-' + key) }
}
async function open(ui, raw = patch) { ui.diff('file').files = [file(raw)]; await ui.diff('file').fire('change') }
async function stage(ui) { ui.diff('request').value = 'Review only the chosen changes'; ui.diff('checks').value = 'Check greeting output and Unicode text'; await ui.diff('stage').fire('click') }
test('mounted picker keeps/drops multiple hunks, stages exact selection, previews and applies to ordinary composer', async () => {
  const ui = surface(), initial = ui.composer.value
  await open(ui); assert.equal(ui.composer.value, initial); assert.equal(ui.binding.session.sources.length, 0)
  await ui.diff('keep').fire('click')
  ui.diff('hunk').value = '0:1'; await ui.diff('hunk').fire('change'); await ui.diff('keep').fire('click'); await ui.diff('drop').fire('click')
  ui.diff('path').value = '1'; await ui.diff('path').fire('change'); await ui.diff('keep').fire('click')
  assert.equal(ui.diff('selected').textContent, header + first + addedHeader + added)
  await stage(ui); assert.equal(ui.composer.value, initial); assert.equal(ui.binding.session.excerpts.length, 1)
  assert.equal(ui.binding.session.excerpts[0].content_utf8, header + first + addedHeader + added)
  await ui.source('preview').fire('click'); assert.equal(ui.source('apply').disabled, false); assert.equal(ui.inputs, 0)
  await ui.source('apply').fire('click'); assert.equal(ui.inputs, 1)
  const packet = await readPacket(ui.composer.value)
  assert.equal(packet.excerpts[0].content_utf8, header + first + addedHeader + added)
  assert.match(packet.excerpts[0].purpose, /Request: Review only/); assert.match(packet.excerpts[0].purpose, /Checks: Check greeting/)
  assert.equal(packet.authority_granted, false); assert.ok(ui.composer.value.startsWith(initial)); ui.binding.dispose()
})
test('restaging replaces selected diff; a budget failure preserves the previous working set and draft', async () => {
  const ui = surface(); await open(ui); await ui.diff('keep').fire('click'); await stage(ui)
  ui.diff('hunk').value = '0:1'; await ui.diff('hunk').fire('change'); await ui.diff('keep').fire('click'); await stage(ui)
  assert.equal(ui.binding.session.excerpts.length, 1); assert.equal(ui.binding.session.excerpts[0].content_utf8, header + first + second)
  const before = JSON.stringify(ui.binding.session), draft = ui.composer.value
  await open(ui, header + '@@ -1 +1 @@\n-old\n+' + 'x'.repeat(9000) + '\n'); await ui.diff('keep').fire('click'); await stage(ui)
  assert.match(ui.source('status').textContent, /budget exceeded/); assert.equal(JSON.stringify(ui.binding.session), before); assert.equal(ui.composer.value, draft)
  ui.binding.dispose()
})
test('switching Work thread clears diff preparation; invalid import does not replace a valid opened diff', async () => {
  const ui = surface(); await open(ui); await ui.diff('keep').fire('click'); const selected = ui.diff('selected').textContent
  await open(ui, 'notes'); assert.match(ui.source('status').textContent, /No Git unified diff/); assert.equal(ui.diff('selected').textContent, selected)
  ui.context.textContent = JSON.stringify({ session_key: 'another-thread', cwd: '/other' }); ui.binding.sync()
  assert.equal(ui.diff('selected').textContent, ''); assert.equal(ui.diff('request').value, ''); assert.equal(ui.binding.session.sources.length, 0); ui.binding.dispose()
})
test('production source wiring retains existing composer input and ordinary Plan request path', async () => {
  const [host, update, bootstrap] = await Promise.all(['main/cowork_surface.mbt', 'main/update.mbt', 'bootstrap.js'].map(path => readFile(new URL(path, import.meta.url), 'utf8')))
  assert.match(bootstrap, /installSourceBrief\(document\)/)
  assert.match(host, /id="claw-procedure-composer"/); assert.match(host, /on_input=value => dispatch\(SetCoworkComposer\(value\)\)/)
  assert.match(host, /StartCoworkPlan/)
  const plan = update.slice(update.indexOf('    StartCoworkPlan =>'), update.indexOf('    StartCoworkPlan =>') + 1100)
  assert.match(plan, /cowork_composer_content\(model, model.cowork_composer\)/); assert.match(plan, /\/plan/); assert.match(plan, /"request_text": content/)
})
