import test from 'node:test'
import assert from 'node:assert/strict'
import { webcrypto } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { readJSONFile } from './json-input.js'
import { JSONChanges, compareLocations, validateChangesPacket, composeChanges, readChangesPacket, removeChanges, BEGIN } from './json-changes.js'
import { mountJSONChanges, bindJSONChanges, installJSONChanges } from './json-changes-controls.js'
import { mountJSONInput, bindJSONInput } from './json-input-controls.js'
import { readJSONPacket, nodeId } from './json-input.js'
if (!globalThis.crypto) globalThis.crypto = webcrypto
const file = (name, content) => { const bytes = new TextEncoder().encode(content); return { name, size: bytes.length, arrayBuffer: async () => bytes.buffer } }
const oldText = '{"id":9007199254740993,"gone":null,"empty":null,"same":true,"a/b~c":-0,"items":[{"id":"A"},{"id":"B"}],"secret":"old-private"}'
const newText = '{"id":9007199254740994,"added":null,"empty":"null","same":true,"a/b~c":0,"items":[{"id":"B"},{"id":"A"}],"secret":"new-private"}'
const context = () => ({ session_key: 'A', cwd: '/work' })
async function model() { return new JSONChanges(await readJSONFile(file('old.json',oldText), 'json'), await readJSONFile(file('new.json',newText), 'json')) }
class Node {
  constructor(document, tag) { this.document = document; this.tagName = tag; this._value = ''; this.textContent = ''; this.dataset = {}; this.isConnected = true; this.events = new Map(); this.children = []; this.files = []; this.attributes = {} }
  set value(value) { this._value = this.tagName === 'select' && !this.children.some(node => node.value === value) ? '' : value } get value() { return this._value }
  set id(value) { this._id = value; this.document.nodes.set(value, this) } get id() { return this._id }
  setAttribute(key, value) { this.attributes[key] = value }
  appendChild(node) { this.children.push(node) }
  replaceChildren() { this.children = []; this.value = '' }
  insertAdjacentElement(_, node) { this.after = node }
  remove() { this.isConnected = false; this.document.nodes.delete(this.id) }
  addEventListener(type, fn, options = {}) { const handlers = this.events.get(type) || []; handlers.push(fn); this.events.set(type, handlers); options.signal?.addEventListener('abort', () => this.events.set(type, (this.events.get(type) || []).filter(item => item !== fn)), { once: true }) }
  dispatchEvent(event) { for (const fn of this.events.get(event.type) || []) fn(event); return true }
  async fire(type) { for (const fn of this.events.get(type) || []) await fn() }
}
function surface(bind = true) {
  const document = { nodes: new Map(), getElementById(id) { return this.nodes.get(id) || null }, createElement(tag) { return new Node(this, tag) } }
  const add = id => { const node = document.createElement('div'); node.id = id; return node }
  const anchor = add('claw-procedure-panel'), ctx = add('claw-procedure-context'), composer = add('claw-procedure-composer')
  ctx.textContent = JSON.stringify(context()); composer.value = 'Explain the selected observations.\n'
  const root = bind ? mountJSONChanges(document, anchor) : null, get = key => document.getElementById('claw-json-changes-' + key)
  let epoch = 0, inputEvents = 0; composer.addEventListener('input', () => inputEvents++)
  const ui = { document, anchor, context: ctx, composer, root, get, get inputEvents() { return inputEvents }, changeAccess() { epoch++ }, transport: () => ({ base: () => 'http://fixture', epoch: () => epoch }) }
  if (bind) ui.binding = bindJSONChanges(document, ui)
  return ui
}
async function importUI(ui, side, text, format = 'json') { ui.get(side + '-format').value = format; ui.get(side + '-file').files = [file(side + '.' + format, text)]; await ui.get(side + '-file').fire('change') }
async function choose(ui, oldPointer, newPointer = oldPointer, oldDocument = 1, newDocument = 1) {
  for (const [key, value] of [['old-pointer',oldPointer],['new-pointer',newPointer],['old-document',String(oldDocument)],['new-document',String(newDocument)]]) { ui.get(key).value = value; await ui.get(key).fire('input') }
  await ui.get('inspect').fire('click'); await ui.get('add').fire('click')
}
async function ready(ui) { await importUI(ui,'old',oldText); await importUI(ui,'new',newText); await choose(ui,'/id'); ui.get('purpose').value = 'Explain this exact identifier change'; await ui.get('purpose').fire('input') }

test('exact typed tokens distinguish absent, null, added, removed, type changes and unchanged values', async () => {
  const m = await model()
  assert.equal(m.inspect(1,'/id',1,'/id').old.json_text,'9007199254740993')
  for (const [pointer,status] of [['/id','changed'],['/added','added'],['/gone','removed'],['/empty','changed'],['/same','unchanged'],['/missing','both_absent'],['/a~1b~0c','changed']]) assert.equal(m.inspect(1,pointer,1,pointer).status,status)
  const added = m.inspect(1,'/added',1,'/added'); assert.deepEqual(added.old,{document:1,pointer:'/added',present:false}); assert.equal(added.new.type,'null')
  assert.throws(() => m.add(1,'/same',1,'/same'),/no change/)
  assert.throws(() => m.inspect(2,'/id',1,'/id'),/existing document/)
  assert.throws(() => m.inspect(1,'/bad~2',1,'/id'),/valid JSON Pointer/)
  m.add(1,'/id',1,'/id'); assert.throws(() => m.add(1,'/id',1,'/id'),/already/)
  const packet = await m.packet(context(),'Inspect exact numbers',1024); assert.doesNotMatch(JSON.stringify(packet),/private|secret/); assert.notEqual(packet.old_source.sha256,packet.new_source.sha256)
})
test('explicit cross-document and cross-array pointers never infer record identity', async () => {
  const m = await model(); assert.equal(m.inspect(1,'/items/0/id',1,'/items/1/id').status,'unchanged'); assert.equal(m.inspect(1,'/items/0/id',1,'/items/0/id').status,'changed')
  const old = await readJSONFile(file('old.jsonl','{"n":1e0}\n{"n":-0}'),'jsonl'), next = await readJSONFile(file('new.jsonl','{"n":0}\n{"n":1.0}'),'jsonl')
  const pair = compareLocations(old,next,1,'/n',2,'/n'); assert.equal(pair.status,'changed'); assert.equal(pair.old.json_text,'1e0'); assert.equal(pair.new.json_text,'1.0'); assert.equal(pair.new.start_line,2)
  const root = compareLocations(old,next,2,'',1,''); assert.equal(root.old.type,'object'); assert.equal(root.status,'changed')
})
test('packet validation and task replacement preserve other content and reject altered claims', async () => {
  const m = await model(); m.add(1,'/added',1,'/added'); m.add(1,'/id',1,'/id'); const p = await m.packet(context(),'Inspect chosen changes',1024)
  for (const alter of [p=>p.authority_granted=true,p=>p.changes[0].status='changed',p=>p.changes[1].old.json_text='9',p=>p.selected_bytes++,p=>p.changes[0].old.pointer='',p=>p.new_source.documents=0]) { const changed=structuredClone(p); alter(changed); await assert.rejects(validateChangesPacket(changed)) }
  const draft='  Task\r\n[Other block]\n', first=await composeChanges(draft,p), second=await composeChanges(first+'\nTail',{...p,purpose:'New purpose'})
  assert.equal((await readChangesPacket(second)).purpose,'New purpose'); assert.equal(await removeChanges(second),draft+'\nTail'); assert.equal(second.split(BEGIN).length,2)
  await assert.rejects(composeChanges(draft+BEGIN,p),/ambiguous/)
  const big = new JSONChanges(await readJSONFile(file('o.json','{"x":"'+ 'a'.repeat(1200)+'"}'),'json'), await readJSONFile(file('n.json','{"x":"b"}'),'json')); big.add(1,'/x',1,'/x'); await assert.rejects(big.packet(context(),'Reason',1024),/budget/)
})
test('mounted production panel imports, explicitly inspects, chooses, previews, applies and detaches', async () => {
  const ui=surface(); await ready(ui); const original=ui.composer.value
  assert.equal(ui.binding.selection.changes.length,1); assert.match(ui.get('inspection').textContent,/9007199254740993/)
  await choose(ui,'/added'); await ui.get('preview').fire('click'); assert.equal(ui.get('apply').disabled,false); assert.equal(ui.composer.value,original); assert.doesNotMatch(ui.get('preview-text').textContent,/private|secret/)
  await ui.get('apply').fire('click'); const packet=await readChangesPacket(ui.composer.value); assert.deepEqual(packet.changes.map(c=>c.status),['changed','added']); assert.equal(ui.inputEvents,1)
  await ui.get('apply').fire('click'); assert.equal(ui.inputEvents,1)
  ui.get('selected').value='0'; await ui.get('remove').fire('click'); assert.equal(ui.binding.selection.changes.length,1)
  await ui.get('preview').fire('click'); await ui.get('apply').fire('click'); assert.equal((await readChangesPacket(ui.composer.value)).changes.length,1)
  await ui.get('detach').fire('click'); assert.equal(ui.composer.value,original); ui.binding.dispose()
})
test('explicit document selection is required and changing paths invalidates inspection', async () => {
  const ui=surface(); await importUI(ui,'old',oldText); await importUI(ui,'new',newText)
  await ui.get('inspect').fire('click'); assert.match(ui.get('status').textContent,/existing document/); assert.equal(ui.binding.selection.changes.length,0)
  await choose(ui,'/id'); ui.get('old-pointer').value='/gone'; await ui.get('old-pointer').fire('input'); await ui.get('add').fire('click'); assert.match(ui.get('status').textContent,/Inspect/); assert.equal(ui.binding.selection.changes.length,1); ui.binding.dispose()
})
test('source replacements and draft/context edits invalidate stale previews', async () => {
  const ui=surface(); await ready(ui); const draft=ui.composer.value
  await ui.get('preview').fire('click'); ui.get('purpose').value='Revised'; await ui.get('purpose').fire('input'); await ui.get('apply').fire('click'); assert.equal(ui.composer.value,draft)
  await ui.get('preview').fire('click'); await ui.composer.fire('input'); await ui.get('apply').fire('click'); assert.equal(ui.composer.value,draft)
  const selected=ui.binding.selection; await importUI(ui,'new','{bad}'); assert.equal(ui.binding.selection,selected); assert.equal(ui.get('apply').disabled,true)
  await importUI(ui,'new','{}'); assert.equal(ui.binding.selection.changes.length,0); assert.equal(ui.composer.value,draft)
  await ready(ui); await ui.get('preview').fire('click'); ui.changeAccess(); ui.binding.sync(); await ui.get('apply').fire('click'); assert.equal(ui.binding.selection,null); assert.equal(ui.composer.value,draft); ui.binding.dispose()
})
test('interrupted asynchronous imports cannot overwrite frozen selection', async () => {
  const ui=surface(); await ready(ui); const selected=ui.binding.selection; let release
  ui.get('old-file').files=[{...file('slow.json','{}'),arrayBuffer:()=>new Promise(resolve=>{release=()=>resolve(new TextEncoder().encode('{}').buffer)})}]
  const pending=ui.get('old-file').fire('change'); await ui.get('cancel').fire('click'); release(); await pending
  assert.equal(ui.binding.selection,selected); ui.binding.dispose()
})
test('shipped bootstrap installs the controller and installer follows the live Work anchor', async () => {
  const bootstrap=await readFile(new URL('./bootstrap.js',import.meta.url),'utf8'); assert.match(bootstrap,/import \{ installJSONChanges \} from '\.\/json-changes-controls.js'/); assert.match(bootstrap,/installJSONChanges\(document\)/)
  const previous=globalThis.MutationObserver; let update
  globalThis.MutationObserver=class {constructor(fn){update=fn} observe(){} disconnect(){}}
  try { const ui=surface(false), stop=installJSONChanges(ui.document); const first=ui.get('panel'); assert.ok(first); update(); assert.equal(ui.get('panel'),first); const anchor=ui.document.createElement('details'); anchor.id='claw-procedure-panel'; update(); assert.equal(first.isConnected,false); assert.notEqual(ui.get('panel'),first); stop(); assert.equal(ui.get('panel'),null) } finally {globalThis.MutationObserver=previous}
})

test('documented fixtures preserve exact numbers and omit unrelated fields in chosen packet', async () => {
  const before=await readFile(new URL('../../docs/examples/json-changes/before.jsonl',import.meta.url),'utf8'), after=await readFile(new URL('../../docs/examples/json-changes/after.jsonl',import.meta.url),'utf8')
  const ui=surface(); await importUI(ui,'old',before,'jsonl'); await importUI(ui,'new',after,'jsonl')
  for (const pointer of ['/count','/retired','/receipt']) await choose(ui,pointer,pointer,1,2)
  ui.get('purpose').value='Explain only the explicitly paired alpha observations'; await ui.get('preview').fire('click'); await ui.get('apply').fire('click')
  const packet=await readChangesPacket(ui.composer.value); assert.deepEqual(packet.changes.map(c=>c.status),['changed','removed','added']); assert.equal(packet.changes[0].old.json_text,'9007199254740993'); assert.equal(packet.changes[0].new.document,2); assert.doesNotMatch(JSON.stringify(packet),/private_note|queued|running/); ui.binding.dispose()
})

test('ordinary JSON selection and comparison share composer invalidation without replacing each other', async () => {
  const ui=surface(); await ready(ui); mountJSONInput(ui.document,ui.anchor); const other=bindJSONInput(ui.document,ui), get=key=>ui.document.getElementById('claw-json-'+key)
  get('file').files=[file('context.json','{"reason":"reported observation"}')]; await get('file').fire('change'); get('node').value=nodeId(1,'/reason'); await get('add').fire('click'); get('purpose').value='Context for comparison'
  await ui.get('preview').fire('click'); await get('preview').fire('click'); await get('apply').fire('click'); assert.equal(ui.get('apply').disabled,true)
  const single=await readJSONPacket(ui.composer.value); await ui.get('preview').fire('click'); await ui.get('apply').fire('click'); assert.deepEqual(await readJSONPacket(ui.composer.value),single); assert.ok(await readChangesPacket(ui.composer.value))
  await ui.get('detach').fire('click'); assert.deepEqual(await readJSONPacket(ui.composer.value),single); assert.equal(await readChangesPacket(ui.composer.value),null); other.dispose(); ui.binding.dispose()
})
