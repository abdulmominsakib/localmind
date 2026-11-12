"""Synthetic complete producer journal for reader tests; no device evidence.

Call only with a test-owned TemporaryDirectory. No staging paths or model files
are used; all native logs are synthetic embedded bytes.
"""
import base64
import copy
import json
from pathlib import Path
import pixel_qwen35_decoder as d


def cap(raw):return {'bytes':len(raw),'sha256':d.digest(raw),'base64':base64.b64encode(raw).decode()}


def fixture(directory,binding_bytes,app_sha):
    directory=Path(directory);directory.mkdir(parents=True,exist_ok=True);binding=json.loads(binding_bytes)
    native='/data/app/~~fixture/com.example.llamadart_chat_example-fixture/lib/arm64';pid=12345;nonce='12345678-1234-1234-1234-123456789abc';rows=[];steps=[];completed=[];notrun=[];correct=[];restrictions=[]
    def record(event,**fields):rows.append({'t_ms':len(rows)*10,'event':event,**fields})
    def stage(name,seconds=90):
        i=len(steps);steps.append(name);record('stage_started',pid=pid,nonce=nonce,step=f'{i}:{name}',timeout_ms=seconds*1000)
    dev={'pid':pid,'nonce':nonce,'run_id':d.PRODUCER_RUN,'binding_sha256':d.digest(binding_bytes),'native_directory':native,'watchdog':'/data/user/0/com.example.llamadart_chat_example/cache/pixel_qwen35_guard_watchdog.json','output':'/storage/emulated/0/Android/data/com.example.llamadart_chat_example/files/'+d.PRODUCER_RUN,'device_model':'Pixel 9 Pro','device':'caiman','android_api':35,'device_build':'synthetic producer fixture only','soc_model':'Tensor G4'}
    record('start',device=dev,binding=binding,historical_gpu_failure='repeated 8; retained FAIL',retained_cpu_reference_failure='Cedar17 versus cedar17; retained FAIL',scope='restriction assertions and prospective correctness only',required_cases=d.CASES);stage('input-and-payload-check')
    def arithmetic(case,lifetime):
        isref=case=='cpu-original'
        stage(case+'.C04.arithmetic',120);text='4';prompt='synthetic public template from producer-shape fixture only';e={'content':text,'visible_output_utf8':list(text.encode()),'visible_output_retokenization_ids':[19],'thinking':'','messages':copy.deepcopy(d.REQUEST),'request_settings':copy.deepcopy(d.CONFIG),'rendered_prompt':prompt,'rendered_prompt_sha256':d.digest(prompt.encode()),'rendered_input_ids':list(range(29)),'input_tokenize_add_special':True,'visible_output_tokenize_add_special':False,'native_usage_counts':{'prompt_tokens':29,'completion_tokens':2,'total_tokens':31},'finish_reason':'stop','stream_completed':True,'ordered_terminal':True}
        record('C04_result',case_id=case,status='PASS',failures=[],reference_case=None if isref else 'cpu-original',token_evidence='public rendered input and visible-output retokenization; not sampled native IDs/EOG',requested_micro_batch=d.size(lifetime),**e)
        completed.append(case)
    def refusal(case):
        stage(case,30);diagnostic=case not in ('media.video','speculation.external-pre-io','embedding.content','embedding.content-batch');fields={}
        if not case.startswith('gpu-refuse-'):fields['requires_qwen35_diagnostic']=diagnostic
        record('restriction_result',case_id=case,status='PASS',error_type='LlamaUnsupportedException',message='Android/Vulkan #948 restricted prospective fixture',**fields);completed.append(case)
    for lifetime in d.LIFETIMES:
        gpu=lifetime=='gpu-default' or lifetime.startswith('gpu-size-');refused=lifetime.startswith('gpu-refuse-');size=d.size(lifetime);stage(lifetime+'.load')
        if refused:
            # Refused loads have no generation stage or native context.
            record('restriction_result',case_id=lifetime,status='PASS',error_type='LlamaUnsupportedException',message='Android/Vulkan #948 restricted prospective fixture');completed.append(lifetime)
        else:
            backend='vulkan' if gpu or lifetime.startswith('vulkan-') else 'cpu';names=['libllamadart.so','libllama.so']+(['libggml-vulkan.so'] if gpu else []);paths={n:native+'/'+n for n in names};maps=(''.join('1000-2000 r-xp 00000000 00:00 1 '+p+'\n' for p in paths.values())).encode()
            record('load',case_id=lifetime,backend='Vulkan0' if gpu else 'CPU',gpu_layers=25 if gpu else 0,architecture='qwen35',micro_batch=size,requested_backend=backend,requested_gpu_layers=0 if not gpu else 999,requested_device='auto' if lifetime=='vulkan-zero-layers-size-32' else 'gpu' if backend=='vulkan' else 'cpu',mappings={'capture':cap(maps),'verified_paths':paths})
            arithmetic(lifetime,lifetime)
            if lifetime in ('cpu-original','gpu-default'):
                stage(lifetime+'.C06.history',120);case=lifetime+'.C06.history'
                record('correctness_result',case_id=case,status='FAIL',expected='cedar17',content='Cedar17',messages=copy.deepcopy(d.HISTORY),effective_config={**d.CONFIG,'backend':'vulkan' if gpu else 'cpu','gpu_layers_hint':999 if gpu else 0},usage={'prompt_tokens':51,'completion_tokens':4,'total_tokens':55},finish_reason='stop');completed.append(case)
                correct.append(case)
            if lifetime=='gpu-default':
                record('capabilities',vision=False,audio=False,speculative_strategies=[],embedding={'text':False,'image':False,'audio':False})
                for case in d.REFUSALS[5:]:refusal(case)
                arithmetic('gpu-default.C04.post-refusal',lifetime)
        stage(lifetime+'.dispose',30)
        ub=[] if refused else [size or 512]
        text='' if refused else 'llama_context: n_ctx = 1024\nllama_context: n_seq_max = 1\nllama_context: n_ubatch = '+str(ub[0])+'\n'
        if gpu:text+='using device Vulkan0 (Mali-G715 fixture)\nload_tensors: offloaded 25/25 layers to GPU\nVulkan0 compute buffer size = 64.00 MiB\n'
        raw=text.encode()
        facts=['Android Vulkan text prompt decode is capped at 8 tokens per call ("Mali-G715" (API 1.3, loader 1.3, subgroup size 16))'] if gpu else []
        record('lifetime_complete',case_id=lifetime,is_disposed=True,is_ready=False,stderr={'schema':'pixel-native-stderr.v1','file':lifetime+'.stderr.log',**cap(raw)},positive_vulkan_placement=True if gpu else None,device_fact_logs=facts,observed_native_n_ubatch=ub,unexpected_context_on_refused_load=False)
    record('complete',restriction_failures=restrictions,correctness_failures=correct,completed_cases=completed,not_run_cases=notrun,unexecuted_required_cases=[c for c in d.CASES if c not in completed],restriction_assertions_pass=True,correctness_pass=not correct,qualified=False)
    (directory/'binding.json').write_bytes(binding_bytes);(directory/'cpuinfo.txt').write_text('synthetic fixture CPU facts\n');(directory/'vkjson.json').write_text('{"synthetic_fixture":true}\n');(directory/'getprop.txt').write_text('[ro.product.device]: [caiman]\n[ro.product.model]: [Pixel 9 Pro]\n[ro.build.version.sdk]: [35]\n');(directory/'app_apk.sha256').write_text(app_sha+'  /data/app/~~fixture/com.example.llamadart_chat_example-fixture/base.apk\n');(directory/'watchdog.done').write_bytes(b'done')
    path=directory/'journal.jsonl';write(path,rows);return path,rows


def write(path,rows):path.write_text(''.join(json.dumps(r,separators=(',',':'))+'\n' for r in rows))
