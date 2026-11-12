"""Synthetic byte-only protocol fixtures, never runtime/model evidence."""
import base64,hashlib,json
from pathlib import Path
import decode_s24 as decoder

def cap(raw):return {'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'base64':base64.b64encode(raw).decode()}

def valid(directory,binding):
 directory.mkdir(parents=True,exist_ok=True)
 identity={'event':'identity','binding':binding,'device':{'model':'SC-51E','api':36,'soc':'SM8650','build':'synthetic-byte-fixture'},'required_case_ids':list(decoder.CASES),'injected_runtime_factory':False,'backend_override':False,'public_finish':'not_exposed_by_default_service'}
 rows=[identity];sequence=0
 def event(case,name,**values):
  nonlocal sequence
  rows.append({'sequence':sequence,'case_id':case,'event':name,**values});sequence+=1
 execution=decoder.digest(json.dumps(binding,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode())
 def native(case,mode):
  event(case,'case_started');records=[]
  def record(name,**values):records.append({'schema':1,'binding':execution,'case_id':case,'pid':123,'sequence':len(records),'event':name,**values})
  record('started',mode=mode)
  if mode in ('cpu','gpu'):
   record('maps',raw_hex=b'synthetic maps'.hex())
   for fixture,text in [('hello','hello'),('arithmetic','7')]:
    raw=json.dumps({'content':[{'type':'text','text':text}]}).encode()
    record('generation',fixture=fixture,native_json_hex=raw.hex())
    record('generation',fixture=fixture,input_tokens=1,output_tokens=1)
   record('finished',engine_deleted=True)
  else:record('finished',**({'model_free_launch':True} if mode=='probe' else {'guard_refused':True,'native_error':'synthetic refusal'}))
  out=b''.join(json.dumps(row).encode()+b'\n' for row in records);err=b'synthetic stderr'
  target=directory/case;target.mkdir();(target/'stdout.jsonl').write_bytes(out);(target/'stderr.log').write_bytes(err)
  receipt={'binding':execution,'case_id':case,'pid':123,'exit_code':0,'timed_out':False,'capture_limit_exceeded':False,'capture_failed':False,'elapsed_ms':1,
   'files':{name:{key:value for key,value in cap(raw).items() if key!='base64'} for name,raw in [('stdout.jsonl',out),('stderr.log',err)]}}
  event(case,'owned_child_capture',receipt=receipt,stdout=cap(out),stderr=cap(err))
  if mode in ('cpu','gpu'):
   for fixture,text in [('hello',b'hello'),('arithmetic',b'7')]:event(case,'native_answer_observation',fixture=fixture,answer_capture=cap(text))
  event(case,'case_result',status='PASS')
 native('s24.native.launch','probe');native('s24.native.gpu-guard','guard')
 case='public.legacy.gpu-refusal';event(case,'case_started');event(case,'public_refusal',typed_unsupported=True)
 event(case,'native_stderr',capture=cap(b''));(directory/(case+'.stderr')).write_bytes(b'');event(case,'case_result',status='PASS')
 native('s24.native.cpu-corrected','cpu')
 for route in ('cpu-corrected','auto-legacy','auto-corrected'):
  if route=='auto-corrected':native('s24.native.gpu-corrected','gpu')
  for lifetime in (1,2):
   prefix=f'{route}.{lifetime}';event(None,'lifetime_started',lifetime_id=prefix,native_log_empty=True)
   for fixture,text in [('hello',b'hello'),('arithmetic',b'7')]:
    case=prefix+'.'+fixture;event(case,'case_started');event(case,'public_chunk',capture=cap(text))
    event(case,'public_observation',answer_capture=cap(text),native_finish='not_exposed_by_default_service',native_settlement='settled',native_stderr=cap(b''),mappings={'capture':cap(b'synthetic maps')})
    event(case,'semantic_oracle',passed=True,legacy_observation_only=route=='auto-legacy');event(case,'case_result',status='PASS')
   if lifetime==1:
    case=route+'.cancel';event(case,'case_started');event(case,'public_chunk',capture=cap(b'1'))
    event(case,'public_cancel',answer_capture=cap(b'1'),native_finish='not_exposed_by_default_service',native_settlement='settled',cancel_sent=True);event(case,'case_result',status='PASS')
   event(case,'lifetime_closed',route=route,lifetime=lifetime,native_stderr=cap(b''));(directory/(prefix+'.lifetime.stderr')).write_bytes(b'')
 final={'event':'complete','case_statuses':{case:'PASS' for case in decoder.CASES},'unexecuted_required_cases':[],'failed_cases':[],'legacy_semantic_failures':[],
  'gpu_per_request_execution_qualified':False,'public_finish':'not_exposed_by_default_service'}
 rows.append(final)
 return rows

def write(path,rows):path.write_bytes(b''.join(json.dumps(row).encode()+b'\n' for row in rows))

def resequence(rows):
 sequence=0
 for row in rows:
  if 'sequence' in row:row['sequence']=sequence;sequence+=1
