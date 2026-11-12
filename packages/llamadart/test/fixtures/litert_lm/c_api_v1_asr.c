// ASR ABI1 fixture: asr_abi1.h is byte-identical to owner5129cd0's bridge header.
#include "c_api_v1_client.c"
#include "asr_abi1.h"

struct LitertLmAsrEngine { int preset; };
struct LitertLmAsrSession { size_t samples; int finished, cancelled, final_sent; };
static int asr_fault, asr_engines, asr_sessions, asr_strings, asr_results;
static int asr_preset, asr_backend, asr_threads, asr_buffers;
static float asr_overlap;
static char asr_model[128], asr_tokenizer[128];
void fixture_asr_fault(int value) { asr_fault=value; }
int fixture_asr_engines(void) { return asr_engines; }
int fixture_asr_sessions(void) { return asr_sessions; }
int fixture_asr_strings(void) { return asr_strings; }
int fixture_asr_results(void) { return asr_results; }
int fixture_asr_preset(void) { return asr_preset; }
int fixture_asr_backend(void) { return asr_backend; }
int fixture_asr_threads(void) { return asr_threads; }
int fixture_asr_buffers(void) { return asr_buffers; }
float fixture_asr_overlap(void) { return asr_overlap; }
const char* fixture_asr_model(void) { return asr_model; }
const char* fixture_asr_tokenizer(void) { return asr_tokenizer; }
static char* asr_string(const char* text) { asr_strings++;return strdup(text); }
static LitertLmAsrStatus asr_error(char** out, const char* text) { *out=asr_string(text);return LITERT_LM_ASR_STATUS_INTERNAL; }
uint32_t litert_lm_asr_abi_version(void) { return asr_fault==1?2:1; }
size_t litert_lm_asr_config_size(void) { return sizeof(LitertLmAsrConfig)+(asr_fault==2?8:0); }
size_t litert_lm_asr_result_size(void) { return sizeof(LitertLmAsrResult)+(asr_fault==3?8:0); }
LitertLmAsrStatus litert_lm_asr_config_init_for_model_preset(LitertLmAsrConfig* c,LitertLmAsrModelPreset preset) {
 if(asr_fault==4)return LITERT_LM_ASR_STATUS_INVALID_ARGUMENT;
 memset(c,0,sizeof(*c));c->struct_size=sizeof(*c);c->abi_version=1;c->sample_rate_hz=16000;c->num_channels=1;asr_preset=preset;return LITERT_LM_ASR_STATUS_OK;
}
void litert_lm_asr_result_init(LitertLmAsrResult* r) { memset(r,0,sizeof(*r));r->struct_size=sizeof(*r);asr_results++; }
// Keep accounting local: ELF can interpose an earlier runtime's public export.
static void asr_release_string(char* s) { if(s){memset(s,'X',strlen(s));free(s);asr_strings--;} }
void litert_lm_asr_free_string(char* s) { asr_release_string(s); }
void litert_lm_asr_result_release(LitertLmAsrResult* r) { asr_release_string(r->confirmed_text);asr_release_string(r->unconfirmed_text);memset(r,0,sizeof(*r));asr_results--; }
LitertLmAsrStatus litert_lm_asr_engine_create(const LitertLmAsrConfig* c,LitertLmAsrEngine** out,char** error) {
 *out=NULL;*error=NULL;asr_backend=c->backend;asr_threads=c->num_threads;asr_buffers=c->max_buffered_audio_milliseconds;asr_overlap=c->overlap_ratio;
 snprintf(asr_model,sizeof(asr_model),"%s",c->model_path);snprintf(asr_tokenizer,sizeof(asr_tokenizer),"%s",c->tokenizer_path);
 if(asr_fault==7)return LITERT_LM_ASR_STATUS_OK;
 *out=calloc(1,sizeof(**out));asr_engines++;
 if(asr_fault==5)return asr_error(error,"fixture engine failure");
 return LITERT_LM_ASR_STATUS_OK;
}
void litert_lm_asr_engine_delete(LitertLmAsrEngine* e) { if(e){free(e);asr_engines--;} }
LitertLmAsrStatus litert_lm_asr_session_create(LitertLmAsrEngine* e,LitertLmAsrSession** out,char** error) {
 *out=NULL;*error=NULL;if(!e)return asr_error(error,"fixture null engine reached session");
 if(asr_fault==8)return LITERT_LM_ASR_STATUS_OK;
 *out=calloc(1,sizeof(**out));asr_sessions++;
 if(asr_fault==6)return asr_error(error,"fixture session failure");
 return LITERT_LM_ASR_STATUS_OK;
}
void litert_lm_asr_session_delete(LitertLmAsrSession* s) { if(s){free(s);asr_sessions--;} }
LitertLmAsrStatus litert_lm_asr_session_push_audio_f32(LitertLmAsrSession* s,const float* audio,size_t count,size_t* accepted,char** error) {
 *accepted=0;*error=NULL;if(asr_fault==9)return asr_error(error,"fixture push failure");
 if(asr_fault==10){*accepted=sizeof(size_t)>4?(size_t)UINT32_MAX+count+1:count+1;return LITERT_LM_ASR_STATUS_OK;}
 if(!s || !audio)return LITERT_LM_ASR_STATUS_INVALID_ARGUMENT;
 *accepted=count>3?3:count;s->samples+=*accepted;
 return *accepted<count?LITERT_LM_ASR_STATUS_WOULD_BLOCK:LITERT_LM_ASR_STATUS_OK;
}
LitertLmAsrStatus litert_lm_asr_session_finish_audio(LitertLmAsrSession* s,char** error) { *error=NULL;if(asr_fault==14)return asr_error(error,"fixture finish failure");s->finished=1;return LITERT_LM_ASR_STATUS_OK; }
LitertLmAsrStatus litert_lm_asr_session_process_next(LitertLmAsrSession* s,LitertLmAsrResult* r,char** error) {
 *error=NULL;if(asr_fault==11){r->confirmed_text=asr_string("do not expose");return asr_error(error,"fixture process failure");}
 if(s->cancelled)return asr_error(error,"fixture cancelled");
 if(s->final_sent)return LITERT_LM_ASR_STATUS_END_OF_STREAM;
 if(!s->samples&&!s->finished)return LITERT_LM_ASR_STATUS_NEEDS_MORE_AUDIO;
 if(s->finished){r->confirmed_text=asr_string("final café");r->unconfirmed_text=asr_string("");r->is_final=1;s->final_sent=1;}
 else{r->confirmed_text=asr_string("part");r->unconfirmed_text=asr_string("pending");}
 s->samples=0;return LITERT_LM_ASR_STATUS_OK;
}
#ifndef OMIT_ASR_CANCEL
LitertLmAsrStatus litert_lm_asr_session_cancel(LitertLmAsrSession* s) { if(asr_fault==12)return LITERT_LM_ASR_STATUS_INTERNAL;s->cancelled=1;return LITERT_LM_ASR_STATUS_OK; }
#endif
LitertLmAsrStatus litert_lm_asr_session_reset(LitertLmAsrSession* s,char** error) { *error=NULL;if(asr_fault==13)return asr_error(error,"fixture reset failure");memset(s,0,sizeof(*s));return LITERT_LM_ASR_STATUS_OK; }
