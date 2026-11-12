#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>
#include <stdio.h>

static int live = 0, failure = 0;
static char copied[128];
static char last_error[256] = "candidate failure /secret/models/m.litertlm";
static int settings_values[9], engine_values[9], calls[100], speculative_live;
static char settings_text[6][256], engine_text[6][256];
int fixture_value(int index) { return engine_values[index]; }
int fixture_calls(int index) { return calls[index]; }
const char *fixture_text(int index) { return engine_text[index]; }
void fixture_reset_settings(void) {
  assert(live == 0); memset(calls, 0, sizeof calls);
  memset(engine_values, 0, sizeof engine_values);
  memset(engine_text, 0, sizeof engine_text);
}
static int status(int stage) {
  ++calls[stage];
  if (failure != stage) return 0;
  snprintf(last_error, sizeof last_error, "stage%d /secret/models/m.litertlm /secret/cache /secret/dispatch", stage);
  return 13;
}
static void copy_path(int index, const char *value) {
  snprintf(settings_text[index], sizeof settings_text[index], "%s", value ? value : "<unset>");
}
void fixture_fail(int stage) { failure = stage; }
int fixture_live(void) { return live; }
const char *litert_lm_get_last_error_message(void) { return last_error; }
#ifndef OMIT_CLEAR_LAST_ERROR
void litert_lm_clear_last_error(void) { last_error[0] = 0; }
#endif
int litert_lm_get_api_version(int *a, int *b, int *c) { *a=1;*b=0;*c=0;return 0; }
static int create(int stage, void **out) {
  *out = NULL;
  if (failure == 12 && stage == 9) return 0;
  if ((failure == 60 && stage == 4) || (failure == 61 && stage == 6) || (failure == 62 && stage == 13) || (failure == 63 && stage == 15)) return 0;
  if ((failure == 31 && stage == 22) || (failure == 32 && stage == 1) || (failure == 33 && stage == 3)) return 0;
  if (status(stage)) return 13;
  *out = malloc(sizeof(int)); ++live; return 0;
}
static void drop(void *p) { if (p) { --live; free(p); strcpy(last_error, "cleanup overwrote last error"); } }
int litert_lm_engine_settings_create(const char *m,const char *b,const char *v,const char *a,void **o) {
  for (int i = 0; i < 9; ++i) settings_values[i] = -1;
  settings_values[5] = settings_values[8] = 0;
  for (int i = 0; i < 6; ++i) copy_path(i, NULL);
  copy_path(0,m);copy_path(1,b);copy_path(2,v);copy_path(3,a);
  return create(1,o);
}
void litert_lm_engine_settings_delete(void *p) { drop(p); }
int litert_lm_engine_settings_set_num_threads(void *p,int n) { assert(p);if(status(2))return 13;settings_values[1]=n;return 0; }
int litert_lm_engine_settings_set_max_num_tokens(void *p,int n) { assert(p);if(status(20))return 13;settings_values[0]=n;return 0; }
int litert_lm_engine_settings_set_cache_dir(void *p,const char *s) { assert(p && s);if(status(21))return 13;copy_path(4,s);return 0; }
int litert_lm_engine_create(void *s,void **o) {
  assert(s && speculative_live == 0);
  int result = create(3,o);
  if (!result && *o) { memcpy(engine_values,settings_values,sizeof engine_values);memcpy(engine_text,settings_text,sizeof engine_text); }
  return result;
}
void litert_lm_engine_delete(void *p) { drop(p); }
int litert_lm_session_config_create(void **o) { return create(4,o); }
void litert_lm_session_config_delete(void *p) { drop(p); }
static int output_tokens;
int fixture_output_tokens(void) { return output_tokens; }
int litert_lm_session_config_set_max_output_tokens(void *p,int n) { assert(p);if(status(5))return 13;output_tokens=n;return 0; }
int litert_lm_session_config_set_sampler_params(void *p,void *s) { assert(p && s);return status(39); }
int litert_lm_sampler_params_create(int type,void **o) { if(type!=2) abort();return create(6,o); }
void litert_lm_sampler_params_delete(void *p) { drop(p); }
int litert_lm_engine_create_session(void *e,void *c,void **o) { (void)e;(void)c;return create(7,o); }
void litert_lm_session_delete(void *p) { drop(p); }
int litert_lm_input_data_create(int type,const void *data,size_t size,void **o) {
  if(type!=0 || size>=sizeof copied) abort();
  memcpy(copied,data,size);copied[size]=0;return create(8,o);
}
void litert_lm_input_data_delete(void *p) { drop(p); }
int litert_lm_session_generate_content(void *s,void *const *inputs,size_t n,void **o) {
  (void)s;if(n!=1 || !inputs[0]) abort();return create(9,o);
}
int litert_lm_responses_get_response_text_at(void *p,size_t n,const char **o) {
  (void)p;if(n!=0) abort();*o=failure==11 ? NULL : copied;return failure==10 ? 13 : 0;
}
void litert_lm_responses_delete(void *p) { drop(p); }

int litert_lm_session_config_set_apply_prompt_template(void *p,bool value) { (void)p; if(value) abort();return 0; }

static int sampler_k, sampler_seed;
static float sampler_p, sampler_t;
int fixture_sampler_int(int index) { return index ? sampler_seed : sampler_k; }
float fixture_sampler_float(int index) { return index ? sampler_t : sampler_p; }
int litert_lm_sampler_params_set_top_k(void *p,int k) { assert(p);if(status(35))return 13;sampler_k=k;return 0; }
int litert_lm_sampler_params_set_top_p(void *p,float v) { assert(p);if(status(36))return 13;sampler_p=v;return 0; }
int litert_lm_sampler_params_set_temperature(void *p,float v) { assert(p);if(status(37))return 13;sampler_t=v;return 0; }
#ifndef OMIT_SAMPLER_SEED
int litert_lm_sampler_params_set_seed(void *p,int seed) { assert(p);if(status(38))return 13;sampler_seed=seed;return 0; }
#endif

// Engine settings use the v1 status contract. The speculative config is copied
// into settings, so its caller-owned handle is freed before engine creation.
int litert_lm_speculative_decoding_config_create(void **out) {
  int result = create(22,out); if (!result && *out) ++speculative_live; return result;
}
void litert_lm_speculative_decoding_config_delete(void *p) { if(p)--speculative_live;drop(p); }
int litert_lm_speculative_decoding_config_set_mode(void *p,int value) {
  assert(p);if(status(23))return 13;*(int *)p = value;return 0;
}
#ifndef OMIT_ENGINE_SPECULATIVE_SETTER
int litert_lm_engine_settings_set_speculative_decoding_config(void *p,const void *config) {
  assert(p && config);if(status(24))return 13;settings_values[7]=*(const int *)config;return 0;
}
#endif
int litert_lm_engine_settings_enable_benchmark(void *p) {
  assert(p);if(status(25))return 13;settings_values[5]=1;return 0;
}
int litert_lm_engine_settings_set_parallel_file_section_loading(void *p,bool value) {
  assert(p);if(status(26))return 13;settings_values[2]=value;return 0;
}
int litert_lm_engine_settings_set_activation_data_type(void *p,int value) {
  assert(p);if(status(27))return 13;settings_values[3]=value;return 0;
}
#ifndef OMIT_PREFILL_CHUNK_SETTER
int litert_lm_engine_settings_set_prefill_chunk_size(void *p,int value) {
  assert(p);if(status(28))return 13;settings_values[4]=value;return 0;
}
#endif
int litert_lm_engine_settings_set_num_prefill_tokens(void *p,int value) {
  assert(p);if(status(29))return 13;settings_values[6]=value;return 0;
}
int litert_lm_engine_settings_set_litert_dispatch_lib_dir(void *p,const char *value) {
  assert(p && value);if(status(30))return 13;copy_path(5,value);return 0;
}
int litert_lm_engine_settings_set_single_threaded_execution(void *p,bool value) {
  assert(p);++calls[34];assert(!value);settings_values[8]=value;return 0;
}
int litert_lm_engine_settings_set_num_decode_tokens(void *p,int value) {
  (void)p;(void)value;abort();
}
