import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { performance } from 'node:perf_hooks';
import test from 'node:test';
import vm from 'node:vm';

// Executes the shipped FFI bodies, with no network or listeners. Virtual-clock
// results model browser scheduling; perf_hooks measures only test CPU work.
const sourcePath = fileURLToPath(new URL('./main/routing_effects.mbt', import.meta.url));
const source = readFileSync(sourcePath, 'utf8');

function ffi(name, text = source) {
  const start = text.indexOf(`extern "js" fn ${name}(`);
  assert.notEqual(start, -1, `Missing FFI ${name}`);
  const block = text.slice(start).split('\n///|')[0];
  return block.split('\n').filter(line => line.trimStart().startsWith('#|'))
    .map(line => line.slice(line.indexOf('#|') + 2)).join('\n');
}

function harness(kind, text = source) {
  let now = 0;
  let nextId = 0;
  let scheduled = 0;
  let fired = 0;
  const timers = new Map();
  const sources = [];
  const window = {};
  class EventSource {
    constructor(url) { this.url = url; this.handlers = new Map(); this.closed = false; sources.push(this); }
    addEventListener(name, fn) { this.handlers.set(name, fn); }
    close() { this.closed = true; }
    emit(name, data = '') { this.handlers.get(name)?.({ data }); }
  }
  const context = vm.createContext({
    window, EventSource, JSON,
    setTimeout(fn, delay) { const id = ++nextId; scheduled++; timers.set(id, { at: now + delay, fn }); return id; },
    clearTimeout(id) { timers.delete(id); },
  });
  const prefix = kind === 'job' ? 'job' : 'acp';
  const start = vm.runInContext(`(${ffi(`start_${prefix}_ui_event_stream`, text)})`, context);
  const stop = vm.runInContext(`(${ffi(`stop_${prefix}_ui_event_stream`, text)})`, context);
  const take = vm.runInContext(`(${ffi(`drain_${prefix}_ui_event_stream`, text)})`, context);
  return {
    start, stop, take: () => JSON.parse(take()), sources,
    get now() { return now; }, get pending() { return timers.size; },
    get scheduled() { return scheduled; }, get fired() { return fired; },
    advance(target) {
      for (;;) {
        const next = [...timers].filter(([, timer]) => timer.at <= target).sort((a, b) => a[1].at - b[1].at || a[0] - b[0])[0];
        if (!next) break;
        const [id, timer] = next; timers.delete(id); now = timer.at; fired++; timer.fn();
      }
      now = target;
    },
  };
}

for (const kind of ['job', 'acp']) {
  const event = `${kind}_ui_event`;
  const complete = `${kind}_ui_complete`;
  test(`${kind}: idle stream schedules nothing; burst drains once in order`, () => {
    const h = harness(kind); const calls = [];
    h.start('/events', () => calls.push({ at: h.now, payload: h.take() }));
    h.advance(5000);
    assert.equal(h.scheduled, 0);
    const rows = Array.from({ length: 1000 }, (_, i) => JSON.stringify({ id: i }));
    for (const row of rows) h.sources[0].emit(event, row);
    assert.equal(h.scheduled, 1);
    h.advance(5015); assert.equal(calls.length, 0);
    h.advance(5016); assert.equal(calls.length, 1);
    assert.deepEqual(calls[0].payload, { entries: rows, closed: false, error: null });
    h.advance(20000); assert.equal(h.pending, 0); assert.equal(h.scheduled, 1);
  });
  test(`${kind}: completion drains final queued event before disposal`, () => {
    const h = harness(kind); const calls = [];
    h.start('/events', () => calls.push(h.take()));
    h.sources[0].emit(event, 'last'); h.sources[0].emit(complete);
    assert.equal(h.sources[0].closed, true);
    h.advance(16);
    assert.deepEqual(calls, [{ entries: ['last'], closed: true, error: null }]);
    assert.deepEqual(h.take(), { entries: [], closed: true, error: null });
    h.advance(10000); assert.equal(calls.length, 1); assert.equal(h.pending, 0);
  });
  test(`${kind}: replacement and stop cancel pending callbacks and stale events`, () => {
    const h = harness(kind); const calls = [];
    h.start('/old', () => calls.push('old'));
    const old = h.sources[0]; old.emit(event, 'old');
    h.start('/new', () => calls.push(h.take()));
    assert.equal(old.closed, true); old.emit(event, 'late'); old.onerror();
    h.advance(20); assert.deepEqual(calls, []);
    h.sources[1].emit(event, 'new'); h.advance(36);
    assert.deepEqual(calls, [{ entries: ['new'], closed: false, error: null }]);
    h.sources[1].emit(event, 'stopped'); h.stop(); h.advance(10000);
    assert.equal(calls.length, 1); assert.equal(h.pending, 0);
    h.sources[1].emit(event, 'after-stop'); h.advance(20000);
    assert.equal(calls.length, 1); assert.equal(h.pending, 0);
  });
  test(`${kind}: error is delivered once without idle retry drains`, () => {
    const h = harness(kind); const calls = [];
    h.start('/events', () => calls.push(h.take()));
    h.sources[0].emit(event, 'queued'); h.sources[0].onerror();
    h.advance(16);
    assert.deepEqual(calls, [{ entries: ['queued'], closed: true, error: 'stream_error' }]);
    h.advance(10000); assert.equal(calls.length, 1); assert.equal(h.pending, 0);
  });
  test(`${kind}: sustained 50-event/s delivery has bounded callbacks and 16ms modeled delay`, () => {
    const h = harness(kind); const deliveries = [];
    h.start('/events', () => {
      for (const row of h.take().entries) deliveries.push({ emitted: Number(row), at: h.now });
    });
    for (let i = 0; i < 500; i++) { const time = 35 + i * 20; h.advance(time); h.sources[0].emit(event, String(time)); }
    h.advance(11000);
    assert.equal(deliveries.length, 500);
    assert.ok(deliveries.every(row => row.at - row.emitted === 16));
    assert.equal(h.scheduled, 500); assert.equal(h.fired, 500); assert.equal(h.pending, 0);
  });
  test(`${kind}: callback CPU replay for 10,000 events in 100 bursts`, () => {
    const h = harness(kind); let received = 0;
    h.start('/events', () => { received += h.take().entries.length; });
    const start = performance.now();
    for (let burst = 0; burst < 100; burst++) {
      h.advance(burst * 100);
      for (let i = 0; i < 100; i++) h.sources[0].emit(event, 'delta');
      h.advance(burst * 100 + 16);
    }
    const elapsed = performance.now() - start;
    assert.equal(received, 10000); assert.equal(h.fired, 100); assert.equal(h.pending, 0);
    console.log(JSON.stringify({ kind: 'isolated-ffi-cpu-replay-not-browser-frame-time', stream: kind, events: received, callbacks: h.fired, cpu_wall_ms: elapsed, modeled_queue_delay_ms: 16 }));
  });
}

test('Rabbita updater no longer restarts stream drain timers', () => {
  const update = readFileSync(new URL('./main/update.mbt', import.meta.url), 'utf8');
  assert.doesNotMatch(update, /@rabbita\.delay\(dispatch\(Pump(?:AcpStream|Stream\(run_id\))\)/);
  assert.doesNotMatch(source, /@rabbita\.delay\(dispatch\(Pump(?:AcpStream|Stream\(run_id\))\)/);
});

// Optional retained-baseline comparison: point this variable at the frozen
// preimage of routing_effects.mbt. No product configuration is read.
if (process.env.STREAM_DRAIN_BASELINE_SOURCE) {
  const baseline = readFileSync(process.env.STREAM_DRAIN_BASELINE_SOURCE, 'utf8');
  for (const [name, arrivals, horizon] of [
    ['idle-60s', [], 60000],
    ['50-events-per-second-10s', Array.from({ length: 500 }, (_, i) => 35 + i * 20), 11000],
    ['100-bursts-of-100-events', Array.from({ length: 10000 }, (_, i) => 35 + Math.floor(i / 100) * 700), 70000],
  ]) {
    test(`retained baseline comparison: ${name}`, () => {
      const results = [];
      for (const [label, text] of [['baseline', baseline], ['candidate', source]]) {
        const h = harness('job', text); const delays = []; let drains = 0;
        const drain = () => { drains++; for (const row of h.take().entries) delays.push(h.now - Number(row)); };
        h.start('/events', drain);
        const start = performance.now();
        if (label === 'baseline') {
          let next = 500;
          for (const arrival of arrivals) {
            while (next <= arrival) { h.advance(next); drain(); next += 500; }
            h.advance(arrival); h.sources[0].emit('job_ui_event', String(arrival));
          }
          while (next <= horizon) { h.advance(next); drain(); next += 500; }
        } else {
          for (const arrival of arrivals) { h.advance(arrival); h.sources[0].emit('job_ui_event', String(arrival)); }
          h.advance(horizon);
        }
        const cpuWallMs = performance.now() - start;
        delays.sort((a, b) => a - b);
        assert.equal(delays.length, arrivals.length);
        results.push({ label, callbacks: drains, ffi_timer_callbacks: h.fired, pending_timers: h.pending,
          mean_modeled_queue_ms: delays.length ? delays.reduce((a, b) => a + b, 0) / delays.length : 0,
          p95_modeled_queue_ms: delays[Math.floor(delays.length * .95)] ?? 0, isolated_ffi_cpu_wall_ms: cpuWallMs });
      }
      console.log(JSON.stringify({ kind: 'retained-source-ffi-comparison-not-e2e', workload: name, events: arrivals.length, results }));
    });
  }
}
