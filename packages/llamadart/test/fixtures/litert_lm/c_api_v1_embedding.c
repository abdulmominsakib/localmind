/* Status/out-pointer ABI: google-ai-edge/LiteRT-LM 83ce6067, c/embedding_engine.h.
 * Deliberately overwrites TLS during cleanup and poisons freed responses. */
#define litert_lm_input_data_create fixture_text_input_create
#define litert_lm_input_data_delete fixture_text_input_delete
#define litert_lm_get_last_error_message fixture_text_error_message
#define litert_lm_clear_last_error fixture_text_clear_error
#include "c_api_v1_client.c"
#undef litert_lm_input_data_create
#undef litert_lm_input_data_delete
#undef litert_lm_get_last_error_message
#undef litert_lm_clear_last_error

#include <math.h>
#include <stdatomic.h>
#include <unistd.h>

static int embedding_fault, embedding_calls;
static _Atomic int embedding_objects;
static int embedding_threads, embedding_context, embedding_normalize;
static int embedding_vision, embedding_audio, embedding_types;
static int embedding_delay_ms;
static _Atomic int embedding_entered;
static size_t embedding_byte_count;
static _Thread_local char embedding_error[256];
const char *litert_lm_get_last_error_message(void) { return embedding_error; }
void litert_lm_clear_last_error(void) { embedding_error[0] = 0; }
typedef struct { size_t size; unsigned char bytes[256]; int type; } embedding_input;
typedef struct { float values[3]; } embedding_response;

void fixture_embedding_fault(int value) { embedding_fault = value; }
void fixture_embedding_delay(int value) { embedding_delay_ms = value; embedding_entered = 0; }
int fixture_embedding_count(void) { return embedding_objects; }
int fixture_embedding_call_count(void) { return embedding_calls; }
int fixture_embedding_entered(void) { return embedding_entered; }
int fixture_embedding_threads(void) { return embedding_threads; }
int fixture_embedding_context(void) { return embedding_context; }
int fixture_embedding_normalize(void) { return embedding_normalize; }
int fixture_embedding_vision(void) { return embedding_vision; }
int fixture_embedding_audio(void) { return embedding_audio; }
int fixture_embedding_types(void) { return embedding_types; }
size_t fixture_embedding_byte_count(void) { return embedding_byte_count; }

#ifndef OMIT_IN_PROCESS_LITERT_MARKER
static int32_t embedding_in_process_litert = 1;
void fixture_embedding_in_process_litert(int value) { embedding_in_process_litert = value; }
int32_t litert_lm_native_in_process_litert_abi_version(void) {
  return embedding_in_process_litert;
}
#endif

static int embedding_status(int stage) {
  ++embedding_calls;
  if (embedding_fault != stage) return 0;
  snprintf(embedding_error, sizeof embedding_error,
           "embedding stage%d /secret/models/m.litertlm /secret/cache", stage);
  return 13;
}
static void embedding_drop(void *pointer) {
  if (!pointer) return;
  --embedding_objects;
  memset(pointer, 0x7f, sizeof(int));
  free(pointer);
  strcpy(embedding_error, "cleanup replaced embedding error");
}
static int embedding_create(int stage, size_t size, void **out) {
  *out = NULL;
  int status = embedding_status(stage);
  if (embedding_fault == stage + 100) return 0;
  if (status && embedding_fault != 200 + stage) return status;
  *out = calloc(1, size);
  assert(*out);
  ++embedding_objects;
  if (embedding_fault == 200 + stage) {
    snprintf(embedding_error, sizeof embedding_error, "partial owner stage%d", stage);
    return 13;
  }
  return status;
}

int litert_lm_embedding_engine_settings_create(const char *model, const char *backend,
    const char *vision, const char *audio, void **out) {
  assert(model && !strcmp(backend, "cpu"));
  embedding_vision = vision != NULL;
  embedding_audio = audio != NULL;
  if (vision) assert(!strcmp(vision, "cpu"));
  if (audio) assert(!strcmp(audio, "cpu"));
  return embedding_create(1, sizeof(int), out);
}
void litert_lm_embedding_engine_settings_delete(void *p) { embedding_drop(p); }
int litert_lm_embedding_engine_settings_set_cache_dir(void *p, const char *value) {
  assert(p && value); return embedding_status(2);
}
int litert_lm_embedding_engine_settings_set_max_input_length(void *p, int value) {
  assert(p); embedding_context = value; return embedding_status(3);
}
int litert_lm_embedding_engine_settings_set_num_threads(void *p, int value) {
  assert(p); embedding_threads = value; return embedding_status(4);
}
int litert_lm_embedding_engine_create(void *settings, void **out) {
  assert(settings); embedding_entered = 1;
  if (embedding_delay_ms) usleep(embedding_delay_ms * 1000);
  return embedding_create(5, sizeof(int), out);
}
void litert_lm_embedding_engine_delete(void *p) { embedding_drop(p); }
int litert_lm_embedding_options_create(void **out) {
  return embedding_create(6, sizeof(int), out);
}
void litert_lm_embedding_options_delete(void *p) { embedding_drop(p); }
int litert_lm_embedding_options_set_normalize(void *p, bool value) {
  assert(p); embedding_normalize = value; return embedding_status(7);
}
int litert_lm_embedding_options_set_input_overflow_strategy(void *p, int value) {
  assert(p && value == 2); return embedding_status(8);
}
int litert_lm_input_data_create(int type, const void *bytes, size_t size, void **out) {
  assert((type == 0 || type == 1 || type == 3) && size <= 256);
  int status = embedding_create(9, sizeof(embedding_input), out);
  if (!status && *out) {
    embedding_input *input = *out;
    input->type = type; input->size = size;
    memcpy(input->bytes, bytes, size);
  }
  return status;
}
void litert_lm_input_data_delete(void *p) { embedding_drop(p); }
int litert_lm_embedding_engine_compute_embedding(void *engine, void *const *inputs,
    size_t count, const void *options, void **out) {
  assert(engine && options && count > 0);
  embedding_entered = 2;
  if (embedding_delay_ms) usleep(embedding_delay_ms * 1000);
  embedding_types = 0; embedding_byte_count = 0;
  for (size_t i = 0; i < count; ++i) {
    const embedding_input *input = inputs[i];
    assert(input); embedding_types |= 1 << input->type;
    embedding_byte_count += input->size;
  }
  int status = embedding_create(10, sizeof(embedding_response), out);
  if (!status && *out) {
    embedding_response *response = *out;
    response->values[0] = embedding_normalize ? 0.6f : 3.0f;
    response->values[1] = embedding_normalize ? 0.8f : 4.0f;
    response->values[2] = embedding_fault == 13 ? NAN : 0.0f;
  }
  return status;
}
int litert_lm_embedding_response_get_size(const void *response, size_t *out) {
  assert(response); *out = embedding_fault == 14 ? 0 : 3;
  return embedding_status(11);
}
#ifndef OMIT_EMBEDDING_VALUES
int litert_lm_embedding_response_get_values(const void *response, const float **out) {
  assert(response);
  *out = embedding_fault == 15 ? NULL : ((embedding_response *)response)->values;
  return embedding_status(12);
}
#endif
void litert_lm_embedding_response_delete(void *p) { embedding_drop(p); }
