"""Read retained v2 producer bytes only; never create missing producer evidence."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re

PRODUCER_RUN = 'core018-pixel-supported-cases-20261104'
STRATEGIES = ['backendDefault','mtp','ngramSimple','draftSimple','draftEagle3','draftDflash','ngramMapK','ngramMapK4v','ngramMod','ngramCache','draftDspark']
LIFETIMES = ['cpu-original','gpu-default'] + [f'gpu-size-{n}' for n in range(1,9)] + [f'gpu-refuse-{n}' for n in (9,32,33,64,512)] + ['cpu-size-32','vulkan-zero-layers-size-32']
ARITHMETIC = ['cpu-original','gpu-default'] + [f'gpu-size-{n}' for n in range(1,9)] + ['cpu-size-32','vulkan-zero-layers-size-32','gpu-default.C04.post-refusal']
REFUSALS = [f'gpu-refuse-{n}' for n in (9,32,33,64,512)] + ['media.image','media.audio','media.video','speculation.legacy'] + ['speculation.'+s for s in STRATEGIES] + ['speculation.mixed','speculation.external-pre-io','embedding.single','embedding.batch','embedding.content','embedding.content-batch']
CASES = ['cpu-original','cpu-original.C06.history','gpu-default','gpu-default.C06.history'] + [f'gpu-size-{n}' for n in range(1,9)] + [f'gpu-refuse-{n}' for n in (9,32,33,64,512)] + ['cpu-size-32','vulkan-zero-layers-size-32','gpu-default.C04.post-refusal'] + REFUSALS[5:]
REQUEST = [{'role':'user','content':'What is 2 + 2? Reply with only the number.'}]
HISTORY = [{'role':role,'content':content} for role,content in [('system','Remember the secret code exactly.'),('user','The secret code is cedar17.'),('assistant','I will remember the code.'),('user','What is the secret code? Reply with only the code.')]]
CONFIG = {'context_size':1024,'threads':4,'batch_threads':4,'max_tokens':32,'sampling_application':'requested_sampler','effective_npu_sampler':None,'temperature':0,'seed':1,'top_k':40,'top_p':0.9,'min_p':0,'repeat_penalty':1.1,'presence_penalty':0,'stop_sequences':[],'enable_thinking':False,'execution_path':'public_api','reuse_prompt_prefix':False,'stream_batch_tokens':8,'stream_batch_bytes':512,'speculative_decoding':False,'grammar':None,'thinking_budget':None,'activation_type':None,'prefill_chunk_size':None,'dispatch_dir':None,'batch_size':0,'micro_batch_size':0,'flash_attention':'auto','cache_type_k':'f16','cache_type_v':'f16','kv_unified':None,'use_mmap':True,'use_mlock':False,'load_mtp':False,'split_mode':'layer','main_gpu':0,'loras':[],'max_parallel_sequences':1,'speculative_rollback_token_max':0,'rope_frequency_base':None,'rope_frequency_scale':None,'prefer_memory64':None,'parallel_file_section_loading':None,'runtime_defaults':'resolved by the recorded runtime artifact','native_log_level':'info','cache_behavior':'fresh request; runtime cache unknown'}
PARITY = ['content','visible_output_utf8','visible_output_retokenization_ids','messages','request_settings','rendered_prompt','rendered_input_ids','native_usage_counts','finish_reason']

def require(value,message):
    if not value: raise ValueError(message)

def digest(raw): return hashlib.sha256(raw).hexdigest()

def unique(pairs):
    result={}
    for k,v in pairs:
        require(k not in result,'Duplicate JSON key: '+k);result[k]=v
    return result

def loads(raw):
    return json.loads(raw,object_pairs_hook=unique,parse_constant=lambda v: (_ for _ in ()).throw(ValueError('Nonfinite JSON: '+v)))

def bounded(path,maximum):
    require(path.is_file() and not path.is_symlink(),'Missing/unsafe producer file: '+path.name)
    require(path.stat().st_size<=maximum,'Producer file cap: '+path.name)
    raw=path.read_bytes();require(len(raw)<=maximum,'Producer file grew past bound');return raw

def capture(value):
    require(type(value['bytes']) is int and 0<=value['bytes']<=8*1024*1024,'Capture size')
    require(isinstance(value['base64'],str) and len(value['base64'])==((value['bytes']+2)//3)*4,'Capture base64 bound')
    raw=base64.b64decode(value['base64'],validate=True)
    require(base64.b64encode(raw).decode()==value['base64'] and len(raw)==value['bytes'] and digest(raw)==value['sha256'],'Capture hash/length/encoding')
    return raw

def native_stderr(directory,case,lock):
    require(lock.get('schema')=='pixel-native-stderr.v1','Missing exact embedded native stderr proof')
    require(lock['file']==case+'.stderr.log','Unsafe stderr path')
    raw=capture(lock)
    sibling=directory/lock['file']
    if sibling.exists() or sibling.is_symlink():require(bounded(sibling,8*1024*1024)==raw,'Raw/embedded stderr conflict')
    return raw

def positive(value): return type(value) is int and value>0

def ids(value): return isinstance(value,list) and bool(value) and all(type(n) is int and n>=0 for n in value)

def size(case):
    if case in ('cpu-size-32','vulkan-zero-layers-size-32'):return 32
    if case.startswith(('gpu-size-','gpu-refuse-')):return int(case.rsplit('-',1)[1])
    return 0

def arithmetic_failures(row,reference):
    fail=[]
    if not isinstance(row.get('content'),str) or re.fullmatch(r'4[.!]?',row['content'].strip()) is None:fail.append('semantic')
    if row.get('thinking')!='':fail.append('thinking')
    if row.get('stream_completed') is not True or row.get('ordered_terminal') is not True:fail.append('stream')
    if row.get('finish_reason')!='stop':fail.append('finish')
    u=row.get('native_usage_counts')
    if not isinstance(u,dict) or not positive(u.get('prompt_tokens')) or not positive(u.get('completion_tokens')):fail.append('usage')
    if not ids(row.get('rendered_input_ids')) or len(row['rendered_input_ids'])<=8 or not isinstance(row.get('rendered_prompt'),str) or not row['rendered_prompt']:fail.append('geometry')
    if not ids(row.get('visible_output_retokenization_ids')):fail.append('visible_output_ids')
    if reference is not None:
        fail += ['parity.'+k for k in PARITY if row.get(k)!=reference.get(k)]
    return fail

def placement(log):
    if re.search(r'llvmpipe|lavapipe|SwiftShader|software',log,re.I):return False
    offloads=re.findall(r'load_tensors: offloaded (\d+)/(\d+) layers to GPU',log)
    devices=set(re.findall(r'using device Vulkan(\d+) \(Mali-G715[^\r\n]*\)',log))
    buffers=re.findall(r'Vulkan(\d+) compute buffer size =\s*([0-9.]+) (?:MiB|MB)',log)
    return len(offloads)==1 and 0<int(offloads[0][0])<=int(offloads[0][1]) and len(devices)==1 and bool(buffers) and all(d in devices and float(n)>0 for d,n in buffers)

def capped(messages):
    decisions=[]
    for message in messages:
        m=re.search(r'Android Vulkan text prompt decode is (?:capped at (\d+) tokens per call|not capped) \((.*)\)',message,re.S)
        if m:
            devices=re.findall(r'"(.*?)" \(API (\d+\.\d+), loader (\d+\.\d+), subgroup size (\d+)\)',m[2],re.S)
            decisions.append(m[1]=='8' and bool(m[2]) and (not devices or any('Mali-G715' in d[0] and int(d[3])!=8 and int(d[3])<32 for d in devices)))
    return bool(decisions) and all(decisions)

def decode(path,binding,binding_sha,app_sha):
    raw=bounded(path,8*1024*1024);require(raw.endswith(b'\n'),'Truncated JSONL')
    lines=raw.decode('utf-8').splitlines();require(lines and all(0<len(x.encode())<=8*1024*1024 for x in lines),'Invalid JSONL line')
    rows=[loads(x) for x in lines];require(all(isinstance(r,dict) for r in rows),'Non-object record')
    require(rows[0].get('event')=='start' and sum(r.get('event')=='start' for r in rows)==1,'Missing/duplicate start')
    start=rows[0];require(start['binding']==binding and start['required_cases']==CASES,'Wrong binding/case inventory')
    require(start['historical_gpu_failure']=='repeated 8; retained FAIL' and start['retained_cpu_reference_failure']=='Cedar17 versus cedar17; retained FAIL','Historical failures removed')
    dev=start['device'];pid=dev['pid'];nonce=dev['nonce'];directory=dev['native_directory']
    require(positive(pid) and re.fullmatch(r'[0-9a-f-]{36}',nonce) and dev['run_id']==PRODUCER_RUN and dev['binding_sha256']==binding_sha,'Wrong PID/nonce/producer binding')
    require(dev['device']=='caiman' and dev['device_model']=='Pixel 9 Pro' and dev['android_api']==35 and dev['device_build'] and dev['soc_model'],'Wrong producer device')
    require(re.fullmatch(r'/data/app/[A-Za-z0-9_~+=./-]+/lib/arm64',directory),'Unsafe installed native directory')
    require(dev['output']=='/storage/emulated/0/Android/data/com.example.llamadart_chat_example/files/'+PRODUCER_RUN or dev['output']=='/sdcard/Android/data/com.example.llamadart_chat_example/files/'+PRODUCER_RUN,'Wrong producer output')
    require(dev['watchdog'].endswith('/cache/pixel_qwen35_guard_watchdog.json'),'Wrong watchdog path')
    require(bounded(path.parent/'binding.json',1024*1024) and digest(bounded(path.parent/'binding.json',1024*1024))==binding_sha,'Retained binding bytes mismatch')
    installed=bounded(path.parent/'app_apk.sha256',4096).decode().split()
    require(len(installed)==2 and installed[0]==app_sha and re.fullmatch(r'/data/app/[A-Za-z0-9_~+=./-]+/base.apk',installed[1]),'Installed APK hash/path mismatch')
    for name in ('cpuinfo.txt','getprop.txt','vkjson.json'):require(bounded(path.parent/name,8*1024*1024).strip(),'Missing raw device fact '+name)
    getprop=bounded(path.parent/'getprop.txt',8*1024*1024).decode()
    for k,v in [('ro.product.device','caiman'),('ro.product.model','Pixel 9 Pro'),('ro.build.version.sdk','35')]:require(f'[{k}]: [{v}]' in getprop,'Device property mismatch '+k)
    require(not(path.parent/'watchdog-failure.json').exists(),'Producer watchdog failure retained')
    complete=[r for r in rows if r.get('event')=='complete'];failed=[r for r in rows if r.get('event')=='execution_failed']
    require(len(complete)<=1 and len(failed)<=1,'Duplicate terminal records')
    require(not complete or rows[-1] is complete[0],'Events follow complete')
    times=[r['t_ms'] for r in rows];require(all(type(n) is int and 0<=n<=1200000 for n in times) and times==sorted(times),'Journal clock/order bound')
    stages=[r for r in rows if r.get('event')=='stage_started']
    for i,r in enumerate(stages):
        require(r['pid']==pid and r['nonce']==nonce and r['step'].startswith(str(i)+':') and type(r['timeout_ms']) is int and 0<r['timeout_ms']<=120000,'Watchdog sequence/PID/nonce/bound')
        require(r['t_ms']<1080000 or r['step'].endswith('.dispose'),'New device work after 18 minutes')
    require(stages and stages[0]['step']=='0:input-and-payload-check','Payload check stage missing')
    capabilities=[r for r in rows if r['event']=='capabilities'];require(len(capabilities)<=1,'Duplicate capability observation')
    known={'start','stage_started','dart_log','load','C04_result','correctness_result','restriction_result','capabilities','lifetime_complete','complete','execution_failed','unexpected_restricted_output'}
    require(all(r.get('event') in known for r in rows),'Unknown producer event')
    results={};loads_by={};life={};reference=None;computed_correct=[];computed_restrictions=[];not_run=[];semantic=[]
    active=None;lifetimes_started=[]
    for r in rows:
        event=r['event'];case=r.get('case_id')
        if event=='stage_started' and r['step'].split(':',1)[1].endswith('.load'):
            active=r['step'].split(':',1)[1][:-5];require(active in LIFETIMES and active not in lifetimes_started,'Unexpected/duplicate lifetime');lifetimes_started.append(active)
        if event=='load':
            require(case==active and case in LIFETIMES and not case.startswith('gpu-refuse-') and case not in loads_by,'Load identity/lifetime')
            gpu=case=='gpu-default' or case.startswith('gpu-size-');backend='vulkan' if gpu or case.startswith('vulkan-') else 'cpu'
            require(r['architecture']=='qwen35' and r['micro_batch']==size(case) and r['requested_backend']==backend and r['requested_device']==('auto' if case=='vulkan-zero-layers-size-32' else 'gpu' if backend=='vulkan' else 'cpu'),'Load requested geometry')
            require(r['requested_gpu_layers']==(0 if case.startswith('vulkan-') or backend=='cpu' else 999),'Requested GPU layers changed')
            require(('vulkan' if gpu else 'cpu') in r['backend'].lower() and (positive(r['gpu_layers']) if gpu else r['gpu_layers']==0),'Actual backend/layers')
            maps=capture(r['mappings']['capture']).decode();paths=r['mappings']['verified_paths'];inventory=binding['libraries']
            required={'libllamadart.so','libllama.so'}|({'libggml-vulkan.so'} if gpu else set())
            require(required<=set(paths) and set(paths)<=set(inventory),'Incomplete native maps')
            for name,p in paths.items():require(p==directory+'/'+name and any(line.endswith(' '+p) for line in maps.splitlines()),'Mapped native path mismatch')
            for line in maps.splitlines():
                for name in inventory:
                    if re.search(r'/'+re.escape(name)+r'(?: \(deleted\))?$',line):require(line.endswith(' '+directory+'/'+name),'Unbound/deleted mapping')
            loads_by[case]=r
        if event in ('C04_result','correctness_result','restriction_result'):
            require(case in CASES and case not in results,'Unknown/duplicate result');results[case]=r
            require(r['status'] in ('PASS','FAIL','NOT_RUN'),'Unknown status')
            if event=='C04_result':
                require(case in ARITHMETIC and (active==case or case=='gpu-default.C04.post-refusal' and active=='gpu-default'),'Arithmetic lifetime mismatch')
                if r['status']=='NOT_RUN':require(reference is None and case!='cpu-original' and r['reason']=='cpu_reference_not_passed','Invented NOT_RUN');not_run.append(case);continue
                require(active in loads_by and r['requested_micro_batch']==size(active),'Arithmetic load/size missing')
                u=r.get('native_usage_counts')
                require(u is None or set(u)=={'prompt_tokens','completion_tokens','total_tokens'} and all(type(v) is int and v>=0 for v in u.values()) and u['total_tokens']==u['prompt_tokens']+u['completion_tokens'],'Usage total/types contradict observer')
                require(r['messages']==REQUEST and r['request_settings']==CONFIG and r['input_tokenize_add_special'] is True and r['visible_output_tokenize_add_special'] is False,'Canonical C04 request/config changed')
                require(r['visible_output_utf8']==list(r['content'].encode()) and r['rendered_prompt_sha256']==digest(r['rendered_prompt'].encode()),'Visible/rendered bytes/hash mismatch')
                require(r['token_evidence']=='public rendered input and visible-output retokenization; not sampled native IDs/EOG','Token evidence overclaim')
                require(r['reference_case']==(None if case=='cpu-original' else 'cpu-original'),'Wrong C04 reference')
                f=arithmetic_failures(r,reference if case!='cpu-original' else None)
                require(case=='cpu-original' or reference is not None,'Dependent generation without CPU reference')
                require(r['failures']==f and r['status']==('FAIL' if f else 'PASS'),'Producer C04 oracle contradicts bytes')
                if f:computed_correct.append(case)
                elif case=='cpu-original':reference=r
            elif event=='correctness_result':
                require(case in ('cpu-original.C06.history','gpu-default.C06.history') and case==active+'.C06.history','C06 lifetime')
                require(r['expected']=='cedar17' and r['messages']==HISTORY,'Strict C06 fixture changed')
                config={**CONFIG,'backend':'cpu' if active=='cpu-original' else 'vulkan','gpu_layers_hint':0 if active=='cpu-original' else 999}
                require(r['effective_config']==config,'C06 settings changed')
                u=r.get('usage') or {};passed=r['content'].strip()=='cedar17' and positive(u.get('prompt_tokens')) and positive(u.get('completion_tokens'))
                require(r['status']==('PASS' if passed else 'FAIL'),'Strict C06 oracle mismatch')
                if not passed:computed_correct.append(case)
            else:
                require(case in REFUSALS and (active==case if case.startswith('gpu-refuse-') else active=='gpu-default'),'Refusal lifetime')
                diagnostic=case not in ('media.video','speculation.external-pre-io','embedding.content','embedding.content-batch')
                if 'requires_qwen35_diagnostic' in r:require(r['requires_qwen35_diagnostic'] is diagnostic,'Refusal diagnostic policy changed')
                passed=r['error_type']=='LlamaUnsupportedException' and (not diagnostic or isinstance(r.get('message'),str) and 'Android/Vulkan' in r['message'] and '948' in r['message'])
                require(r['status']==('PASS' if passed else 'FAIL'),'Typed refusal claim contradicts error')
                if not passed:computed_restrictions.append(case)
        if event=='capabilities':require(active=='gpu-default' and r['vision'] is False and r['audio'] is False and r['speculative_strategies']==[] and r['embedding']=={'text':False,'image':False,'audio':False},'Restriction capabilities mismatch')
        if event=='unexpected_restricted_output':capture(r['capture']);semantic.append('restricted-output')
        if event=='lifetime_complete':
            require(case==active and case not in life and case in LIFETIMES,'Lifetime completion identity')
            stderr=native_stderr(path.parent,case,r['stderr']);text=stderr.decode(errors='replace')
            require(r['is_disposed'] is True and r['is_ready'] is False,'Engine disposal incomplete')
            ub=[int(n) for n in re.findall(r'n_ubatch\s*=\s*(\d+)',text)];require(r['observed_native_n_ubatch']==ub,'Native microbatch observation mismatch')
            refused=case.startswith('gpu-refuse-');unexpected=refused and re.search(r'llama_context:|(?:sched_reserve|reserve_compute_meta):.*compute buffer',text) is not None
            require(r['unexpected_context_on_refused_load'] is unexpected,'Refusal context observation mismatch')
            if unexpected:computed_restrictions.append(case+'.native-context-created')
            gpu=case=='gpu-default' or case.startswith('gpu-size-')
            if not refused:
                contexts=[int(n) for n in re.findall(r'\bn_ctx\s*=\s*(\d+)',text)]
                sequences=[int(n) for n in re.findall(r'\bn_seq_max\s*=\s*(\d+)',text)]
                if not contexts or any(n!=1024 for n in contexts) or not sequences or any(n!=1 for n in sequences):semantic.append(case+'.actual-context-config')
                if not ub or size(case)>0 and any(n!=size(case) for n in ub):semantic.append(case+'.actual-microbatch')
            if gpu:
                require(r['positive_vulkan_placement'] is placement(text),'Positive placement flag contradicts raw logs')
                if not placement(text):semantic.append(case+'.actual-placement')
                if not capped(r['device_fact_logs']):semantic.append(case+'.actual-cap-facts')
            else:require(r['positive_vulkan_placement'] is None,'NonGPU lifetime claims placement')
            life[case]=r;active=None
    complete_seen=bool(complete)
    if complete_seen:
        final=complete[0];completed=[c for c,r in results.items() if r['status']!='NOT_RUN']
        require(set(results)==set(CASES) and lifetimes_started==LIFETIMES and set(life)==set(LIFETIMES) and len(capabilities)==1,'Incomplete required producer inventory')
        expected_stages=['input-and-payload-check']
        for lifetime in LIFETIMES:
            expected_stages.append(lifetime+'.load')
            if not lifetime.startswith('gpu-refuse-'):
                if results[lifetime]['status']!='NOT_RUN':expected_stages.append(lifetime+'.C04.arithmetic')
                if lifetime in ('cpu-original','gpu-default'):expected_stages.append(lifetime+'.C06.history')
                if lifetime=='gpu-default':
                    expected_stages+=REFUSALS[5:]
                    if results['gpu-default.C04.post-refusal']['status']!='NOT_RUN':expected_stages.append('gpu-default.C04.post-refusal.C04.arithmetic')
            expected_stages.append(lifetime+'.dispose')
        require([r['step'].split(':',1)[1] for r in stages]==expected_stages,'Required stage operations missing/out of order')
        for r in stages:
            step=r['step'].split(':',1)[1];seconds=30 if step.endswith('.dispose') or step in REFUSALS[5:] else 120 if step.endswith(('.C04.arithmetic','.C06.history')) else 90
            require(r['timeout_ms']==seconds*1000,'Exact per-stage timeout differs')
        require(final['completed_cases']==completed and final['not_run_cases']==not_run and final['unexecuted_required_cases']==[c for c in CASES if c not in completed],'Complete inventory contradicts rows')
        require(final['correctness_failures']==computed_correct and final['restriction_failures']==computed_restrictions and final['correctness_pass'] is (not computed_correct) and final['restriction_assertions_pass'] is (not computed_restrictions) and final['qualified'] is False,'Complete flags contradict independent assessment')
        require(bounded(path.parent/'watchdog.done',32)==b'done','Missing actual watchdog completion')
    return {'qualified':False,'strict_raw_decode_complete':complete_seen,'journal_sha256':digest(raw),'case_statuses':{c:results[c]['status'] if c in results else 'NOT_RUN' for c in CASES},'correctness_failures':computed_correct,'restriction_failures':computed_restrictions,'not_run_cases':[c for c in CASES if c not in results or results[c]['status']=='NOT_RUN'],'raw_semantic_or_placement_failures':semantic,'supported_C04_pass':complete_seen and all(results.get(c,{}).get('status')=='PASS' for c in ARITHMETIC) and not semantic,'restriction_assertions_pass':complete_seen and not computed_restrictions and not semantic,'all_current_cases_pass':complete_seen and not(computed_correct or computed_restrictions or semantic or not_run),'historical_failures_retained':{'CPU':'Cedar17 versus cedar17: FAIL','GPU':'repeated 8: FAIL'},'token_evidence_limit':'Public visible-output retokenization, not sampled-native IDs/EOG parity','execution_failed_present':bool(failed),'lifetimes':len(life)}

COLLECTION_JOURNAL = Path('caiman-35-en-portrait/artifacts/sdcard/Android/data/com.example.llamadart_chat_example/files') / PRODUCER_RUN / 'journal.jsonl'

def collection_journal(directory):
    require(directory.is_dir() and not directory.is_symlink(),'Unsafe collection root')
    canonical=directory/COLLECTION_JOURNAL
    alias=canonical.parent/PRODUCER_RUN/'journal.jsonl'
    # Never accept another run/device, a second nesting level, or a symlinked parent.
    for entry in directory.rglob('*'):
        require(not entry.is_symlink(),'Symlink in collected producer tree')
    journals=list(directory.rglob('journal.jsonl'))
    require(canonical in journals and set(journals)<=set((canonical,alias)),'Missing/ambiguous canonical journal')
    raw=bounded(canonical,8*1024*1024)
    if alias in journals:
        duplicate=bounded(alias,8*1024*1024)
        require(len(duplicate)==len(raw) and digest(duplicate)==digest(raw) and duplicate==raw,'Conflicting nested journal alias')
    return canonical

def inspect_collection(directory,plan):
    report={'qualified':False,'journal_present':False,'strict_raw_decode_complete':False}
    try:
        journal=collection_journal(directory)
        report['journal_present']=True
        return {**report,**decode(journal,loads(Path(plan['binding']['path']).read_text()),plan['binding']['sha256'],plan['apk']['app.apk']['sha256'])}
    except (ValueError,KeyError,TypeError,UnicodeError,OSError) as e:return {**report,'decode_error':str(e)}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('directory',type=Path);p.add_argument('--plan',type=Path,required=True);a=p.parse_args();print(json.dumps(inspect_collection(a.directory,loads(a.plan.read_text())),indent=2))
