#!/usr/bin/env python3
"""Bounded local integration test; retains all synthetic inputs and CLI outputs."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

binary = Path(sys.argv[1]).resolve()
root = Path(sys.argv[2]).resolve()
root.mkdir(parents=True, exist_ok=False)
receipts = []

def event(run, time, step=None, status=None, kind='step.observed', message='observed', job='job'):
    result = dict(run_id=run, job_id=job, timestamp=time, event_type=kind,
                  message=message, data={'attempt': 'fixture', 'output_ref': 'never-open-this'}, future_field=['kept', 42])
    if step is not None:
        result['step_id'] = step
    if status is not None:
        result['status'] = status
    return result

def write(name, entries, blank=False):
    path = root / name
    path.write_text(('\n' if blank else '') + '\n'.join(json.dumps(e, ensure_ascii=False) for e in entries) + '\n')
    return path

def invoke(label, args, expected=0):
    command = [str(binary), *map(str, args)]
    result = subprocess.run(command, text=True, capture_output=True, timeout=20)
    (root / (label + '.stdout')).write_text(result.stdout)
    (root / (label + '.stderr')).write_text(result.stderr)
    receipts.append(dict(label=label, command=command, exit=result.returncode,
                         stdout_sha256=hashlib.sha256(result.stdout.encode()).hexdigest()))
    assert result.returncode == expected, (label, result.returncode, result.stderr)
    if expected:
        assert result.stdout == '' and result.stderr.startswith('compare_runs:'), label
    return result.stdout

baseline = write('baseline.jsonl', [
    event('baseline', 50, 'compile', 'Succeeded', 'step.completed', 'built artifact'),
    event('baseline', 0, kind='run.started'),
    event('baseline', 10, 'compile', 'Running', 'step.started'),
    event('baseline', 60, 'removed', 'Succeeded'),
], blank=True)
candidate = write('candidate.jsonl', [
    event('candidate', 100, kind='run.started'),
    event('candidate', 110, 'compile', 'Running', 'step.started'),
    event('candidate', 190, 'compile', 'Unknown', 'step.unknown', 'missing acknowledgement'),
    event('candidate', 195, 'compile', kind='step.note', message='awaiting reconcile'),
    event('candidate', 200, 'added', 'Succeeded'),
])
other = write('other.jsonl', [event('unselected', -100)])
original = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in [baseline, candidate, other]}
args = [baseline, candidate, other, '--baseline', 'baseline', '--candidate', 'candidate']
report = json.loads(invoke('compare', args))
assert report['schema'] == 'moonclaw.job-run-comparison.v1'
assert report['baseline']['events'] == 4 and report['candidate']['events'] == 5
assert report['span_delta'] == '40'
steps = {s['step_id']: s for s in report['steps']}
assert list(steps) == ['added', 'compile', 'removed']
assert steps['added']['presence'] == 'added' and steps['removed']['presence'] == 'removed'
assert steps['compile']['span_delta'] == '45'
assert steps['compile']['status_changed'] is True
assert steps['compile']['event_counts_changed'] is True
assert steps['compile']['candidate']['last_status'] == 'Unknown'
assert steps['compile']['candidate']['status_source']['line'] == 3
assert steps['compile']['candidate']['last']['line'] == 4
assert report['baseline']['first']['line'] == 3
assert report['candidate']['last']['record']['future_field'] == ['kept', 42]
markdown = invoke('markdown', args + ['--markdown'])
assert 'missing acknowledgement' not in markdown  # Last message differs; full status record remains in JSON.
assert 'awaiting reconcile' in markdown and 'Unknown' in markdown
assert 'not measured execution duration' in markdown
reverse = json.loads(invoke('reverse', [baseline, candidate, '--baseline', 'candidate', '--candidate', 'baseline']))
assert reverse['span_delta'] == '-40'
assert {s['step_id']: s for s in reverse['steps']}['removed']['presence'] == 'added'
assert 'Usage:' in invoke('help', ['--help'])
for label, bad in [
    ('missing-run', [baseline, '--baseline', 'baseline', '--candidate', 'missing']),
    ('same-run', [baseline, '--baseline', 'baseline', '--candidate', 'baseline']),
    ('missing-option', [baseline, '--baseline', 'baseline']),
    ('repeated-option', args + ['--baseline', 'baseline']),
    ('repeated-markdown', args + ['--markdown', '--markdown']),
    ('repeated-file', args + [baseline]),
    ('unknown-option', args + ['--live']),
    ('no-files', ['--baseline', 'baseline', '--candidate', 'candidate']),
    ('missing-file', [root/'absent.jsonl', '--baseline', 'baseline', '--candidate', 'candidate']),
]:
    invoke(label, bad, 1)
conflict = write('conflict.jsonl', [event('baseline', 999, job='wrong-job')])
invoke('ambiguous-identity', args + [conflict], 1)
malformed = root / 'malformed.jsonl'
malformed.write_text('{"run_id": "unselected"}\n')
invoke('invalid-unselected-event', args + [malformed], 1)
partial = root / 'partial.jsonl'
partial.write_text('{"run_id":')
invoke('partial-event', args + [partial], 1)
assert all(hashlib.sha256(p.read_bytes()).hexdigest() == digest for p, digest in original.items())
(root/'input-hashes.json').write_text(json.dumps({str(p): digest for p, digest in original.items()}, indent=2)+'\n')
(root/'cli-receipts.json').write_text(json.dumps(receipts, indent=2)+'\n')
print(f'{len(receipts)} compiled CLI invocations passed; original journals unchanged')
