// Minimal LiteRT-LM v0.18 C ABI fixture that records the per-send decode
// controls each send receives through its optional args.
// -DWITH_STREAM_PROXY sends through litert_lm_conversation_send_message_stream;
// without it the client sends through litert_lm_conversation_send_message.
// -DOMIT_PENALTIES leaves out the repetition penalty API and -DOMIT_THINKING
// the thinking config API, as runtimes that predate them.
// -DOMIT_PRESENCE leaves out only the presence penalty setter.
// With -DWITH_STREAM_PROXY, -DFINISH_REASON_ABI=<n> exports the litert-lm-native
// finish-reason proxy ABI <n>; -DOMIT_FINISH_REASON_GETTER then leaves out
// stream_proxy_get_finish_reason.
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
  float repetition;
  float presence;
} penalty_config;

typedef struct {
  bool enable;
  int budget;
} thinking_config;

typedef struct {
  bool has_penalty;
  penalty_config penalty;
  bool has_thinking;
  thinking_config thinking;
  int max_output_tokens;
} optional_args;

static int sends;
static optional_args last_send;
static int live_args;
static int live_penalties;
static int live_thinking;

int fixture_sends(void) { return sends; }
bool fixture_has_penalty(void) { return last_send.has_penalty; }
float fixture_repetition_penalty(void) { return last_send.penalty.repetition; }
float fixture_presence_penalty(void) { return last_send.penalty.presence; }
bool fixture_has_thinking(void) { return last_send.has_thinking; }
bool fixture_enable_thinking(void) { return last_send.thinking.enable; }
int fixture_thinking_budget(void) { return last_send.thinking.budget; }
int fixture_max_output_tokens(void) { return last_send.max_output_tokens; }
int fixture_live_objects(void) {
  return live_args + live_penalties + live_thinking;
}

static void record_send(void* args) {
  sends++;
  last_send = *(optional_args*)args;
}

void litert_lm_set_min_log_level(int level) {}
void* litert_lm_engine_settings_create(const char* m, const char* b, const char* v, const char* a) {
  return (void*)1;
}
void litert_lm_engine_settings_set_max_num_tokens(void* p, int n) {}
void litert_lm_engine_settings_enable_benchmark(void* p) {}
void litert_lm_engine_settings_set_enable_speculative_decoding(void* p, bool b) {}
void litert_lm_engine_settings_set_cache_dir(void* p, const char* d) {}
void litert_lm_engine_settings_delete(void* p) {}
void* litert_lm_engine_create(void* p) { return (void*)2; }
void litert_lm_engine_delete(void* p) {}
void* litert_lm_session_config_create(void) { return (void*)3; }
void litert_lm_session_config_delete(void* p) {}
void* litert_lm_conversation_config_create(void) { return (void*)4; }
void litert_lm_conversation_config_set_session_config(void* p, void* s) {}
void litert_lm_conversation_config_set_enable_constrained_decoding(void* p, bool b) {}
void litert_lm_conversation_config_delete(void* p) {}
void* litert_lm_conversation_create(void* e, void* c) { return (void*)5; }
void litert_lm_conversation_delete(void* p) {}
void litert_lm_conversation_cancel_process(void* p) {}

void* litert_lm_conversation_optional_args_create(void) {
  live_args++;
  return calloc(1, sizeof(optional_args));
}
void litert_lm_conversation_optional_args_delete(void* p) {
  live_args--;
  free(p);
}
void litert_lm_conversation_optional_args_set_max_output_tokens(void* p, int n) {
  ((optional_args*)p)->max_output_tokens = n;
}

#ifndef OMIT_PENALTIES
void* litert_lm_repetition_penalty_config_create(void) {
  live_penalties++;
  penalty_config* config = calloc(1, sizeof(penalty_config));
  config->repetition = 1.0f;
  return config;
}
void litert_lm_repetition_penalty_config_delete(void* p) {
  live_penalties--;
  free(p);
}
void litert_lm_repetition_penalty_config_set_repetition_penalty(void* p, float v) {
  ((penalty_config*)p)->repetition = v;
}
#ifndef OMIT_PRESENCE
void litert_lm_repetition_penalty_config_set_presence_penalty(void* p, float v) {
  ((penalty_config*)p)->presence = v;
}
#endif
// Deep-copies the config, as the runtime does.
void litert_lm_conversation_optional_args_set_repetition_penalty_config(void* p, const void* c) {
  optional_args* args = p;
  args->has_penalty = c != NULL;
  if (c != NULL) args->penalty = *(const penalty_config*)c;
}
#endif

#ifndef OMIT_THINKING
// Defaults to enabled with an unlimited (-1) budget, as the runtime does.
void* litert_lm_thinking_config_create(void) {
  live_thinking++;
  thinking_config* config = calloc(1, sizeof(thinking_config));
  config->enable = true;
  config->budget = -1;
  return config;
}
void litert_lm_thinking_config_delete(void* p) {
  live_thinking--;
  free(p);
}
void litert_lm_thinking_config_set_enable_thinking(void* p, bool v) {
  ((thinking_config*)p)->enable = v;
}
void litert_lm_thinking_config_set_thinking_token_budget(void* p, int v) {
  ((thinking_config*)p)->budget = v;
}
void litert_lm_conversation_optional_args_set_thinking_config(void* p, const void* c) {
  optional_args* args = p;
  args->has_thinking = c != NULL;
  if (c != NULL) args->thinking = *(const thinking_config*)c;
}
#endif

static const char response_text[] =
    "{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"ok\"}]}";

#ifdef WITH_STREAM_PROXY
typedef void (*stream_callback)(void*, const char*, bool, const char*);
static stream_callback listener;
static int proxy_data;
static bool proxy_live;
static int next_finish_reason;
static bool cancel_next;
// The wire value the proxy records at the next final callback.
void fixture_set_finish_reason(int value) { next_finish_reason = value; }
// Makes the next send end with the runtime's cancellation error.
void fixture_cancel_next(void) { cancel_next = true; }
static void proxy_callback(void* d, const char* c, bool f, const char* e) {
  listener(NULL, c, f, e);
}
void* stream_proxy_create(stream_callback callback, void* data, stream_callback* out) {
  listener = callback;
  *out = proxy_callback;
  proxy_live = true;
  proxy_data = 0;
  return &proxy_data;
}
void stream_proxy_free_string(char* value) { free(value); }
void stream_proxy_delete(void* data) { proxy_live = false; }
#ifdef FINISH_REASON_ABI
int stream_proxy_finish_reason_abi_version(void) { return FINISH_REASON_ABI; }
#ifndef OMIT_FINISH_REASON_GETTER
// A deleted proxy reads as unknown, so a read after stream_proxy_delete shows.
int stream_proxy_get_finish_reason(const void* data) {
  return data == &proxy_data && proxy_live ? proxy_data : 0;
}
#endif
#endif
int litert_lm_conversation_send_message_stream(void* c, const char* m, const char* x, void* a, stream_callback cb, void* d) {
  record_send(a);
  if (cancel_next) {
    cancel_next = false;
    proxy_data = 4;
    cb(d, NULL, true, strdup("CANCELLED: Process cancelled."));
    return 0;
  }
  proxy_data = next_finish_reason;
  cb(d, strdup(response_text), true, NULL);
  return 0;
}
#else
void* litert_lm_conversation_send_message(void* c, const char* m, const char* x, void* a) {
  record_send(a);
  return (void*)7;
}
const char* litert_lm_json_response_get_string(void* r) { return response_text; }
void litert_lm_json_response_delete(void* r) {}
#endif
