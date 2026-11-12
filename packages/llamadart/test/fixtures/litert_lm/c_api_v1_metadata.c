#include "c_api_v1_conversation.c"
#include <math.h>

#ifndef OMIT_METADATA
#define OMIT_METADATA 0
#endif
static int metadata_failure, metadata_mode, metadata_flags;
static int metadata_calls[20], metadata_deletes[2];
static char metadata_input[8192], metadata_rendered[8192];
void fixture_metadata_reset(void) {
  assert(live == 0);
  metadata_failure = metadata_mode = metadata_flags = failure = 0;
  memset(metadata_calls, 0, sizeof metadata_calls);
  memset(metadata_deletes, 0, sizeof metadata_deletes);
}
void fixture_metadata_fail(int value) { metadata_failure = value; }
void fixture_metadata_mode(int value) { metadata_mode = value; }
void fixture_metadata_flags(int value) { metadata_flags = value; }
int fixture_metadata_calls(int index) { return metadata_calls[index]; }
int fixture_metadata_deletes(int index) { return metadata_deletes[index]; }
const char *fixture_metadata_input(void) { return metadata_input; }
static int metadata_status(int stage) {
  ++metadata_calls[stage];
  if (metadata_failure != stage) return 0;
  snprintf(last_error, sizeof last_error,
           "metadata-stage%d /secret/models/m.litertlm /secret/other.litertlm", stage);
  return 13;
}
static int metadata_create(int stage, void **out) {
  *out = NULL;
  if (metadata_status(stage)) return 13;
  if ((stage == 1 && metadata_mode == 101) ||
      (stage == 7 && metadata_mode == 107)) return 0;
  *out = malloc(1); ++live; return 0;
}
#if OMIT_METADATA != 1
int litert_lm_loaded_file_create(const char *path, void **out) {
  assert(path);snprintf(metadata_input, sizeof metadata_input, "%s", path);
  return metadata_create(1, out);
}
#endif
#if OMIT_METADATA != 2
void litert_lm_loaded_file_delete(void *file) {
  ++metadata_deletes[0]; drop(file);
}
#endif
#if OMIT_METADATA != 3
int litert_lm_loaded_file_supports_input_modality(const void *file,int modality,bool *out) {
  assert(file && modality >= 0 && modality <= 3);
  if(metadata_status(2))return 13;
  *out=(metadata_flags & (1 << modality)) != 0;return 0;
}
#endif
#if OMIT_METADATA != 4
int litert_lm_loaded_file_has_speculative_decoding_support(const void *file,bool *out) {
  assert(file);if(metadata_status(3))return 13;
  *out=(metadata_flags & 16) != 0;return 0;
}
#endif
#if OMIT_METADATA != 5
int litert_lm_loaded_file_supports_thinking(const void *file,bool *out) {
  assert(file);if(metadata_status(4))return 13;
  *out=(metadata_flags & 32) != 0;return 0;
}
#endif
#if OMIT_METADATA != 6
int litert_lm_loaded_file_supports_function_calling(const void *file,bool *out) {
  assert(file);if(metadata_status(5))return 13;
  *out=(metadata_flags & 64) != 0;return 0;
}
#endif
#if OMIT_METADATA != 7
int litert_lm_conversation_render_message_to_string(void *conversation,const char *json,const char **out) {
  assert(conversation && json && !active);*out=NULL;
  snprintf(metadata_input, sizeof metadata_input, "%s", json);
  if(metadata_status(6))return 13;
  if(metadata_mode == 106)return 0;
  snprintf(metadata_rendered, sizeof metadata_rendered, "render:%s",json);
  *out=metadata_rendered;return 0;
}
#endif
#if OMIT_METADATA != 8
int litert_lm_conversation_get_benchmark_info(void *conversation,void **out) {
  assert(conversation && !active);return metadata_create(7,out);
}
#endif
#if OMIT_METADATA != 9
void litert_lm_benchmark_info_delete(void *info) { ++metadata_deletes[1];drop(info); }
#endif
static int metric_turns(const void *info,size_t *out,int stage) {
  assert(info);if(metadata_status(stage))return 13;
  *out=metadata_mode == 1 ? 0 : metadata_mode == 2 ? ((size_t)1 << 32) + 2 : 2;return 0;
}
#if OMIT_METADATA != 10
int litert_lm_benchmark_info_get_num_prefill_turns(const void *info,size_t *out) {
  return metric_turns(info,out,8);
}
#endif
#if OMIT_METADATA != 11
int litert_lm_benchmark_info_get_num_decode_turns(const void *info,size_t *out) {
  return metric_turns(info,out,9);
}
#endif
static int metric_tokens(const void *info,size_t index,size_t *out,int stage) {
  assert(info && index < 2);if(metadata_status(stage))return 13;
  *out=metadata_mode == 3 ? SIZE_MAX : metadata_mode == 4 ? (index ? 1 : INT64_MAX) :
       metadata_mode == 8 ? (size_t)UINT32_MAX + 3 : (stage == 10 ? 10 : 3) + index;
  return 0;
}
#if OMIT_METADATA != 12
int litert_lm_benchmark_info_get_prefill_token_count_at(const void *info,size_t index,size_t *out) {
  return metric_tokens(info,index,out,10);
}
#endif
#if OMIT_METADATA != 13
int litert_lm_benchmark_info_get_decode_token_count_at(const void *info,size_t index,size_t *out) {
  return metric_tokens(info,index,out,11);
}
#endif
static int metric_value(const void *info,double *out,int stage) {
  assert(info);if(metadata_status(stage))return 13;
  *out=metadata_mode == 5 ? NAN : metadata_mode == 6 ? -1 : metadata_mode == 7 ? 0 :
       stage == 12 ? 123.25 : stage == 13 ? 45.75 : stage == 14 ? 0.125 : 1.5;
  return 0;
}
#if OMIT_METADATA != 14
int litert_lm_benchmark_info_get_prefill_tokens_per_sec_at(const void *info,size_t index,double *out) {
  assert(index == 1);return metric_value(info,out,12);
}
#endif
#if OMIT_METADATA != 15
int litert_lm_benchmark_info_get_decode_tokens_per_sec_at(const void *info,size_t index,double *out) {
  assert(index == 1);return metric_value(info,out,13);
}
#endif
#if OMIT_METADATA != 16
int litert_lm_benchmark_info_get_time_to_first_token(const void *info,double *out) {
  return metric_value(info,out,14);
}
#endif
#if OMIT_METADATA != 17
int litert_lm_benchmark_info_get_total_init_time_in_second(const void *info,double *out) {
  return metric_value(info,out,15);
}
#endif
