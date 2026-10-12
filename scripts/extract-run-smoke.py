#!/usr/bin/env python3
"""Retained native CLI evidence. Explicit build and new evidence directory only."""
import hashlib, json, pathlib, subprocess, sys
build, out = map(pathlib.Path, sys.argv[1:])
assert build.is_absolute() and out.is_absolute()
out.mkdir(parents=True, exist_ok=False)
extract = build / 'native/debug/build/cmd/extract_run/extract_run.exe'
explore = build / 'native/debug/build/cmd/run_journal/run_journal.exe'
for executable in [extract, explore]: assert executable.is_file(), executable
receipts = []
def invoke(name, executable, args, success=True):
    result = subprocess.run([str(executable), *map(str,args)], capture_output=True)
    (out / (name + '.stdout')).write_bytes(result.stdout)
    (out / (name + '.stderr')).write_bytes(result.stderr)
    receipts.append(dict(name=name, command=[str(executable), *map(str,args)], exit=result.returncode))
    (out/'invocations.json').write_text(json.dumps(receipts, indent=2)+'\n')
    if success: assert result.returncode == 0, result.stderr
    else: assert result.returncode == 1 and result.stdout == b'', (name, result)
    return result.stdout

def event(job, run, ts, msg, **extra):
    return dict(job_id=job, run_id=run, timestamp=ts, event_type='recorded', message=msg, data={'value':'雪\n"quoted"'}, **extra)
a=event('one', 'shared', 20, 'later', status=None, step_id='', future={'nested':[None, True]})
b=event('two', 'shared', 1, 'wrong job')
c=event('one', 'shared', -3, 'first', status={'UnknownFuture':['opaque']})
d=event('one', 'other', 2, 'wrong run')
e=event('one', 'shared', 20, 'tied')
first=out/'first.jsonl'; second=out/'second.jsonl'
first.write_text('\n'+ '\n'.join(json.dumps(x,ensure_ascii=False) for x in [a,b,c,d])+'\n')
second.write_text('\n'.join(json.dumps(x) for x in [e,a])+'\n')
originals={p:hashlib.sha256(p.read_bytes()).hexdigest() for p in [first,second]}
args=[first,second,'--job','one','--run','shared']
raw=invoke('exact-pair',extract,args)
assert [json.loads(x) for x in raw.splitlines()]==[c,a,e,a]
selected=out/'selected.jsonl'; selected.write_bytes(raw)
view=json.loads(invoke('reopen',explore,[selected,'--run','shared']))
assert view['total_events']==4 and [x['record'] for x in view['entries']]==[c,a,e,a]
assert all(x['source']==str(selected) for x in view['entries'])
assert invoke('reextract',extract,[selected,'--job','one','--run','shared'])==raw
assert json.loads(invoke('other-job',extract,[first,second,'--job','two','--run','shared']))==b
invoke('absent-pair',extract,[first,'--job','missing','--run','shared'],False)
invoke('missing-job',extract,[first,'--run','shared'],False)
invoke('missing-run',extract,[first,'--job','one'],False)
invoke('repeat-option',extract,args+['--job','one'],False)
invoke('duplicate-input',extract,[first,first,'--job','one','--run','shared'],False)
invoke('unknown-option',extract,args+['--query','later'],False)
invoke('missing-file',extract,[out/'absent.jsonl','--job','one','--run','shared'],False)
malformed=out/'malformed.jsonl'; malformed.write_text(json.dumps(b)+'\n'+json.dumps({'job_id':'unselected'})+'\n')
invoke('invalid-unselected',extract,[first,malformed,'--job','one','--run','shared'],False)
many=out/'many.jsonl'; many.write_text((json.dumps(c)+'\n')*1001)
assert len(invoke('beyond-page',extract,[many,'--job','one','--run','shared']).splitlines())==1001
# Each input is readable, while their combined selected output exceeds reimport size.
big1=out/'big1.jsonl'; big2=out/'big2.jsonl'
big_record=event('large','run',1,'x'*1100000)
big1.write_text((json.dumps(big_record)+'\n')*2)
big2.write_text((json.dumps(big_record)+'\n')*2)
invoke('reimport-size-bound',extract,[big1,big2,'--job','large','--run','run'],False)
invoke('help',extract,['--help'])
assert all(hashlib.sha256(p.read_bytes()).hexdigest()==h for p,h in originals.items())
receipt=dict(result='PASS',invocations=len(receipts),input_sha256={str(p):h for p,h in originals.items()},output_sha256=hashlib.sha256(raw).hexdigest(),binaries={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [extract,explore]})
(out/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt,indent=2))
