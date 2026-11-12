// Minimal LiteRT-LM C ABI fixture whose calls fail on request and record a
// thread-local last error, as the runtime does from v0.18.0.
// -DWITH_STREAM_PROXY sends through litert_lm_conversation_send_message_stream;
// without it the client sends through litert_lm_conversation_send_message.
// -DOMIT_LAST_ERROR leaves out the last-error API, as runtimes before v0.18.0.
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

enum { OP_NONE, OP_SETTINGS, OP_ENGINE, OP_CONVERSATION, OP_SEND, OP_OPTIONAL_ARGS };

typedef struct {
  int generation;
  int code;
  bool has_message;
  char message[1024];
} error_state;

static int fail_op;
static int fail_code;
static bool has_fail_message;
static char fail_message[1024];
static bool stale_errors;
static int generation;
static _Thread_local error_state thread_error;

// Each fixture_configure call starts every thread over: with a stale error
// when stale is set, as if an earlier call on that thread had failed.
static error_state* current_error(void) {
  if (thread_error.generation != generation) {
    thread_error.generation = generation;
    thread_error.code = stale_errors ? 13 : 0;
    thread_error.has_message = stale_errors;
    strcpy(thread_error.message, "stale error");
  }
  return &thread_error;
}

// Makes op fail. A zero code with a null message fails without recording an
// error.
void fixture_configure(int op, int code, const char* message, bool stale) {
  fail_op = op;
  fail_code = code;
  has_fail_message = message != NULL;
  if (message != NULL) {
    strncpy(fail_message, message, sizeof(fail_message) - 1);
  }
  stale_errors = stale;
  generation++;
}

static bool fails(int op) {
  if (fail_op != op) return false;
  if (fail_code != 0 || has_fail_message) {
    error_state* error = current_error();
    error->code = fail_code;
    error->has_message = has_fail_message;
    strcpy(error->message, fail_message);
  }
  return true;
}

#ifndef OMIT_LAST_ERROR
const char* litert_lm_get_last_error_message(void) {
  error_state* error = current_error();
  return error->has_message ? error->message : NULL;
}
int litert_lm_get_last_error_code(void) { return current_error()->code; }
void litert_lm_clear_last_error(void) {
  error_state* error = current_error();
  error->code = 0;
  error->has_message = false;
}
#endif

void litert_lm_set_min_log_level(int level) {}
void* litert_lm_engine_settings_create(const char* m, const char* b, const char* v, const char* a) {
  return fails(OP_SETTINGS) ? NULL : (void*)1;
}
void litert_lm_engine_settings_set_max_num_tokens(void* p, int n) {}
// In stale mode a call between engine settings creation and engine creation
// records an error, so a stale error is on the thread that creates the engine
// even when that thread already cleared it for engine settings creation.
void litert_lm_engine_settings_enable_benchmark(void* p) {
  if (stale_errors) {
    error_state* error = current_error();
    error->code = 13;
    error->has_message = true;
    strcpy(error->message, "stale error");
  }
}
void litert_lm_engine_settings_set_enable_speculative_decoding(void* p, bool b) {}
void litert_lm_engine_settings_set_cache_dir(void* p, const char* d) {}
void litert_lm_engine_settings_delete(void* p) {}
void* litert_lm_engine_create(void* p) { return fails(OP_ENGINE) ? NULL : (void*)2; }
void litert_lm_engine_delete(void* p) {}
void* litert_lm_session_config_create(void) { return (void*)3; }
void litert_lm_session_config_delete(void* p) {}
void* litert_lm_conversation_config_create(void) { return (void*)4; }
void litert_lm_conversation_config_set_session_config(void* p, void* s) {}
void litert_lm_conversation_config_set_enable_constrained_decoding(void* p, bool b) {}
void litert_lm_conversation_config_delete(void* p) {}
void* litert_lm_conversation_create(void* e, void* c) {
  return fails(OP_CONVERSATION) ? NULL : (void*)5;
}
void litert_lm_conversation_delete(void* p) {}
void litert_lm_conversation_cancel_process(void* p) {}
static int optional_args_deleted, send_calls;
int fixture_optional_args_deleted(void) { return optional_args_deleted; }
int fixture_send_calls(void) { return send_calls; }
void* litert_lm_conversation_optional_args_create(void) { return fails(OP_OPTIONAL_ARGS) ? NULL : (void*)6; }
void litert_lm_conversation_optional_args_delete(void* p) { optional_args_deleted++; }
void litert_lm_conversation_optional_args_set_max_output_tokens(void* p, int n) {}

#ifdef WITH_STREAM_PROXY
typedef void (*stream_callback)(void*, const char*, bool, const char*);
static int proxy_data;
static void proxy_callback(void* d, const char* c, bool f, const char* e) {}
void* stream_proxy_create(stream_callback callback, void* data, stream_callback* out) {
  *out = proxy_callback;
  return &proxy_data;
}
void stream_proxy_free_string(char* value) {}
void stream_proxy_delete(void* data) {}
int litert_lm_conversation_send_message_stream(void* c, const char* m, const char* x, void* a, stream_callback cb, void* d) {
  return fails(OP_SEND) ? -1 : 0;
}
#else
static char response_text[] = "{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"ok\"}]}";
void* litert_lm_conversation_send_message(void* c, const char* m, const char* x, void* a) {
  send_calls++;
  return fails(OP_SEND) ? NULL : (void*)7;
}
const char* litert_lm_json_response_get_string(void* r) { return response_text; }
void litert_lm_json_response_delete(void* r) {}
#endif
