#!/usr/bin/env python3
"""Retain synthetic discover/open fixtures and compare machine results."""
import hashlib, json, pathlib, subprocess, sys
binary, explorer, destination = sys.argv[1:]
out = pathlib.Path(destination).resolve(); out.mkdir(parents=True, exist_ok=False)
def write(name, data):
    p = out / name; p.write_text(data, encoding='utf-8'); return p
calls=[]
def call(name, args, expected=0, executable=binary):
    result = subprocess.run([executable, *map(str, args)], capture_output=True)
    (out/(name+'.stdout')).write_bytes(result.stdout); (out/(name+'.stderr')).write_bytes(result.stderr)
    calls.append({'name':name, 'command':[executable,*map(str,args)], 'exit':result.returncode})
    assert result.returncode==expected, (name,result.returncode,result.stderr.decode())
    if expected:
        assert not result.stdout and result.stderr
        return None
    return result.stdout.decode()
def event(run, job, ts, message, **extra):
    return dict(run_id=run,job_id=job,timestamp=ts,event_type='observation',message=message,data={'synthetic':True},**extra)
def journal(name, events): return write(name,'\n'+'\n'.join(json.dumps(x,ensure_ascii=False) for x in events)+'\n')
a=journal('primary.jsonl', [event('research','job-1',5,'Find cost report',status='Running'),event('research','job-1',15,'step complete',step_id='s',status='Succeeded'),event('unique','job-2',20,'receipt unknown',status={'future':'Unknown'}),event('collision','job-1',30,'<script>note</script>',status=None)])
b=journal('secondary.jsonl',[event('research','job-1',15,'tie from second source'),event('collision','job-2',30,'other collision'),event('nostatus','job-3',1,'started step',step_id='s',status='Running')])
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [a,b]}
all_runs=json.loads(call('directory',[a,b,'--limit','100']))
assert all_runs['total_runs']==5 and all_runs['total_events']==7
pairs=[(c['job_id'],c['run_id']) for c in all_runs['runs']]
assert pairs==[('job-1','collision'),('job-2','collision'),('job-2','unique'),('job-1','research'),('job-3','nostatus')]
# Derived struct Option fields are omitted when absent and unwrapped when present.
assert all_runs['runs'][0]['last_run_status'] is None
assert 'last_run_status' not in all_runs['runs'][1]
assert all_runs['runs'][0]['ambiguous_run_id'] and all_runs['runs'][1]['ambiguous_run_id']
research=all_runs['runs'][3]
assert research['last_run_status']=='Running' and research['events']==3
assert research['status_source']['line']==2 and research['last_event']['source']==str(b)
filtered=json.loads(call('query',[a,b,'--query','COST','--job','job-1']))
assert filtered['matched_runs']==1 and filtered['runs'][0]['events']==3
narrow=json.loads(call('collision-filter',[a,b,'--job','job-1']))
assert narrow['runs'][0]['ambiguous_run_id']
first=json.loads(call('first',[a,b,'--limit','2'])); second=json.loads(call('second',[a,b,'--limit','2','--offset','2'])); third=json.loads(call('third',[a,b,'--limit','2','--offset','4']))
assert first['next_offset']==2 and second['next_offset']==4 and 'next_offset' not in third
assert [x['run_id'] for x in first['runs']+second['runs']+third['runs']]==[x['run_id'] for x in all_runs['runs']]
opened=json.loads(call('open-discovered',[a,b,'--run',all_runs['runs'][2]['run_id']],executable=explorer))
assert opened['matched_events']==1 and opened['entries'][0]['record']['message']=='receipt unknown'
markdown=call('markdown',[a,b,'--markdown']); assert '&lt;script&gt;' in markdown and 'Ambiguous run ID' in markdown
assert json.loads(call('no-matches',[a,b,'--query','absent']))['runs']==[]
assert json.loads(call('huge-offset',[a,b,'--offset','2147483647']))['runs']==[]
empty=write('empty.jsonl','\n'); assert json.loads(call('empty',[empty]))['total_runs']==0
many=journal('many.jsonl',[event('r'+str(i),'j',i,'batch') for i in range(101)])
assert json.loads(call('many-page-1',[many,'--limit','100']))['next_offset']==100
assert len(json.loads(call('many-page-2',[many,'--offset','100']))['runs'])==1
bad=write('bad.jsonl',a.read_text()+'{"job_id":"ignored"}\n')
call('invalid-filtered-record',[bad,'--job','not-found'],1)
for name,args in [('no-input',[]),('limit-zero',[a,'--limit','0']),('limit-high',[a,'--limit','101']),('offset-negative',[a,'--offset','-1']),('missing-value',[a,'--query']),('duplicate-flag',[a,'--job','j','--job','j']),('duplicate-file',[a,a]),('unknown',[a,'--since','2']),('unreadable',[out/'missing.jsonl'])]: call(name,args,1)
assert 'Usage:' in call('help',['--help'])
assert hashes=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [a,b]}
(out/'receipt.json').write_text(json.dumps({'result':'PASS','calls':calls,'input_sha256':hashes,'checks':['whole-pair discovery','run status provenance','step status exclusion','collisions','stable ordering/ties','whole-history filters','pagination','101 runs','existing explorer handoff','inert Markdown','malformed filtered input','visible errors','unchanged inputs']},indent=2)+'\n')
print('PASS', len(calls), 'native invocations;', out)
