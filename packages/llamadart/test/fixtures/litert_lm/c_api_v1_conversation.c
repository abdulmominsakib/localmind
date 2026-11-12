#ifndef LITERT_V1_CONVERSATION_FIXTURE
#define LITERT_V1_CONVERSATION_FIXTURE
#include "c_api_v1_text.c"
#include <assert.h>
#include <stdint.h>
#include <pthread.h>
#include <stdatomic.h>

#ifndef PROXY_ABI
#define PROXY_ABI 2
#endif
#ifndef ALLOCATION_FAILURE_ABI
#define ALLOCATION_FAILURE_ABI 1
#endif
#ifndef FINISH_ABI
#define FINISH_ABI 1
#endif

typedef void (*owned_callback)(void *, char *, bool, char *);
typedef struct {
  owned_callback callback;
  void *data;
  int reason;
  atomic_int allocation_failure;
  bool started, final_seen, loss_read;
} proxy;
typedef struct { const char *text, *error; bool final; } borrowed_chunk;
typedef void (*chunk_callback)(void *, const borrowed_chunk *);
static int copies, proxies, created, deleted, waits, cancels, sends;
static int failed_copies, loss_reads, copy_index, fail_copy_mask, proxy_allocations;
static bool active, drained, cancelled;
static chunk_callback receiver;
static void *receiver_data;
typedef struct {
  bool max_present, penalty_present;
  int max_tokens, window;
  float repetition, presence, frequency;
} turn_options;
static int args_live, penalty_live;
static turn_options sent_options;
static bool sent_args;
static char sent_message[8192];
static char sent_extra_context[8192];
int fixture_args_live(void) { return args_live; }
int fixture_penalty_live(void) { return penalty_live; }
int fixture_turn_int(int index) {
  switch(index) {
    case 0: return sent_args;
    case 1: return sent_options.max_present;
    case 2: return sent_options.max_tokens;
    case 3: return sent_options.penalty_present;
    default: return sent_options.window;
  }
}
float fixture_turn_float(int index) {
  return index == 0 ? sent_options.repetition : index == 1 ? sent_options.presence : sent_options.frequency;
}
const char *fixture_message(void) { return sent_message; }
const char *fixture_extra_context(void) { return sent_extra_context; }
#ifndef OMIT_TURN_CREATE
int litert_lm_conversation_optional_args_create(void **out) {
  *out=NULL;if(status(70))return 13;if(failure==76)return 0;
  *out=calloc(1,sizeof(turn_options));++live;++args_live;return 0;
}
#endif
#ifndef OMIT_TURN_DELETE
void litert_lm_conversation_optional_args_delete(void *args) { ++calls[78];--args_live;drop(args); }
#endif
#ifndef OMIT_TURN_MAX
int litert_lm_conversation_optional_args_set_max_output_tokens(void *args,int value) {
  assert(args);if(status(71))return 13;
  ((turn_options *)args)->max_present=true;((turn_options *)args)->max_tokens=value;return 0;
}
#endif
#ifndef OMIT_TURN_PENALTY_CREATE
int litert_lm_repetition_penalty_config_create(void **out) {
  *out=NULL;if(status(72))return 13;if(failure==77)return 0;
  turn_options *config=calloc(1,sizeof *config);config->repetition=1;
  *out=config;++live;++penalty_live;return 0;
}
#endif
#ifndef OMIT_TURN_PENALTY_DELETE
void litert_lm_repetition_penalty_config_delete(void *config) { ++calls[79];--penalty_live;drop(config); }
#endif
#ifndef OMIT_TURN_REPETITION
int litert_lm_repetition_penalty_config_set_repetition_penalty(void *config,float value) {
  assert(config);if(status(73))return 13;((turn_options *)config)->repetition=value;return 0;
}
#endif
#ifndef OMIT_TURN_PRESENCE
int litert_lm_repetition_penalty_config_set_presence_penalty(void *config,float value) {
  assert(config);if(status(74))return 13;((turn_options *)config)->presence=value;return 0;
}
#endif
#ifndef OMIT_TURN_ATTACH
int litert_lm_conversation_optional_args_set_repetition_penalty_config(void *args,const void *config) {
  assert(args&&config);if(status(75))return 13;
  turn_options *options=args;const turn_options *penalty=config;
  options->penalty_present=true;options->repetition=penalty->repetition;options->presence=penalty->presence;
  options->frequency=penalty->frequency;options->window=penalty->window;return 0;
}
#endif

int fixture_copies(void) { return copies; }
int fixture_failed_copies(void) { return failed_copies; }
int fixture_loss_reads(void) { return loss_reads; }
void fixture_fail_copies(int mask) { fail_copy_mask = mask; copy_index = 0; }
int fixture_proxies(void) { return proxies; }
int fixture_proxy_allocations(void) { return proxy_allocations; }
int fixture_created(void) { return created; }
int fixture_deleted(void) { return deleted; }
int fixture_waits(void) { return waits; }
int fixture_cancels(void) { return cancels; }
int fixture_sends(void) { return sends; }
#ifndef OMIT_PROXY_MARKER
int32_t stream_proxy_callback_abi_version(void) { return PROXY_ABI; }
#endif
#ifndef OMIT_FINISH_MARKER
int32_t stream_proxy_finish_reason_abi_version(void) { return FINISH_ABI; }
#endif
int32_t stream_proxy_get_finish_reason(void *data) { return ((proxy *)data)->reason; }
#ifndef OMIT_ALLOCATION_FAILURE_MARKER
int32_t stream_proxy_allocation_failure_abi_version(void) { return ALLOCATION_FAILURE_ABI; }
#endif
#ifndef OMIT_ALLOCATION_FAILURE_GETTER
int32_t stream_proxy_has_allocation_failure(const void *data) {
  if (!data) return 1;
  assert(drained && !active && ((const proxy *)data)->final_seen);
  ((proxy *)data)->loss_read = true; ++loss_reads;
  return atomic_load_explicit(&((const proxy *)data)->allocation_failure, memory_order_acquire);
}
#endif
static char *copy_string(const char *text) {
  if (!text) return NULL;
  if (fail_copy_mask & (1 << copy_index++)) { ++failed_copies; return NULL; }
  ++copies; return strdup(text);
}
static void forward(void *data, const borrowed_chunk *chunk) {
  proxy *context = data;
  if (chunk->final) { context->final_seen = true; context->reason = cancelled ? 4 : chunk->error ? 5 : 1; }
  // Text then error matches the owner proxy; each bit injects one copy loss.
  char *text = copy_string(chunk->text);
  char *error = copy_string(chunk->error);
  if ((chunk->text && !text) || (chunk->error && !error)) {
    atomic_store_explicit(&context->allocation_failure, 1, memory_order_release);
  }
  context->callback(context->data, text, chunk->final, error);
}
#ifndef OMIT_PROXY_CREATE
void *stream_proxy_create(owned_callback callback, void *data, chunk_callback *out) {
  if (failure == 16) { *out = NULL; return NULL; }
  proxy *context = calloc(1, sizeof *context);
  atomic_init(&context->allocation_failure, 0);
  context->callback = callback; context->data = data; *out = forward;
  ++proxies; ++proxy_allocations; return context;
}
#endif
void stream_proxy_free_string(char *text) {
  if (text) { memset(text, 0xCC, strlen(text)); free(text); --copies; }
}
void stream_proxy_delete(void *data) {
  assert(!active || drained);
  assert(!((proxy *)data)->started || ((proxy *)data)->loss_read);
  free(data); --proxies;
}
static char preface[5][8192];
static int constrained;
const char *fixture_preface(int index) { return preface[index]; }
int fixture_constrained(void) { return constrained; }
int litert_lm_conversation_config_create(void **out) {
  memset(preface,0,sizeof preface);constrained=-1;return create(13, out);
}
void litert_lm_conversation_config_delete(void *config) { drop(config); }
int litert_lm_conversation_config_set_session_config(void *config, void *session) {
  assert(config && session); return status(14);
}
int litert_lm_conversation_create(void *engine, void *config, void **out) {
  assert(engine && config);
  int status = create(15, out);
  if (!status) { ++created; cancelled = false; active = false; }
  return status;
}
void litert_lm_conversation_delete(void *conversation) {
  assert(!active || drained); ++deleted; active = false; drop(conversation);
}
int litert_lm_conversation_send_message_stream(void *conversation, const char *message,
    const char *extra, const void *args, chunk_callback callback, void *data) {
  assert(conversation && message && callback);
  assert(penalty_live == 0);
  assert(!active && !cancelled);
  assert(strlen(message)<sizeof sent_message);strcpy(sent_message,message);
  assert(!extra || strlen(extra)<sizeof sent_extra_context);
  snprintf(sent_extra_context,sizeof sent_extra_context,"%s",extra ? extra : "");
  sent_args=args!=NULL;memset(&sent_options,0,sizeof sent_options);
  if(args)sent_options=*(const turn_options *)args;
  ++sends;
  if (status(17)) return 13;
  ((proxy *)data)->started = true;
  receiver = callback; receiver_data = data; drained = false; active = true;
  return 0;
}
int litert_lm_conversation_cancel_process(void *conversation) {
  assert(conversation); ++cancels; cancelled = true;
  return failure == 18 ? 13 : 0;
}
int litert_lm_conversation_wait_until_done(void *conversation) {
  assert(conversation); ++waits;
  if (failure == 19) return 13;
  active = false; drained = true; return 0;
}
// Invoke from a foreign thread; overwrite borrowed storage immediately after
// callback return so an asynchronous Dart borrowed-pointer consumer is wrong.
static void *emit(void *argument) {
  assert(args_live==0 && penalty_live==0);
  int kind = *(int *)argument;
  char text[] = "borrowed UTF8 世界";
  char error[160] = "callback failure /secret/models/m.litertlm https://user:secret@example.test/model?token=secret";
  if (kind == 3 || kind == 8) strcpy(error, "CANCELLED: stream stopped");
  if (kind == 6) text[0] = (char)0xff;
  borrowed_chunk chunk = {
    .text = kind == 0 || kind == 4 || kind == 6 || kind == 7 || kind == 8 || kind == 9 ? text : NULL,
    .error = kind == 1 || kind == 3 || kind == 4 || kind == 7 || kind == 8 ? error : NULL,
    .final = kind >= 2 && kind != 7,
  };
  receiver(receiver_data, &chunk);
  memset(text, 'X', sizeof text - 1);
  memset(error, 'X', sizeof error - 1);
  return NULL;
}
void fixture_emit(int kind) {
  assert(active); pthread_t thread;
  assert(!pthread_create(&thread, NULL, emit, &kind));
  assert(!pthread_join(thread, NULL));
}

static int set_preface(void *config, const char *value, int slot) {
  assert(config && value && strlen(value) < sizeof preface[slot]);
  if(status(40+slot))return 13;
  strcpy(preface[slot],value);return 0;
}
int litert_lm_conversation_config_set_system_message(void *config,const char *s) { return set_preface(config,s,0); }
int litert_lm_conversation_config_set_messages(void *config,const char *s) { return set_preface(config,s,1); }
int litert_lm_conversation_config_set_tools(void *config,const char *s) { return set_preface(config,s,2); }
int litert_lm_conversation_config_set_extra_context(void *config,const char *s) { return set_preface(config,s,3); }
#ifndef OMIT_PROMPT_TEMPLATE
int litert_lm_conversation_config_set_prompt_template(void *config,const char *s) { return set_preface(config,s,4); }
#endif
int litert_lm_conversation_config_set_enable_constrained_decoding(void *config,bool value) {
  assert(config);if(status(46))return 13;constrained=value;return 0;
}
#endif
