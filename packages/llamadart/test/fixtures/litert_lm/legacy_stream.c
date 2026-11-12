#define WITH_STREAM_PROXY
#define stream_proxy_create unused_proxy_create
#define stream_proxy_free_string unused_proxy_free_string
#define stream_proxy_delete unused_proxy_delete
#define litert_lm_conversation_send_message_stream unused_stream_start
#define litert_lm_conversation_delete unused_conversation_delete
#include "last_error.c"
#undef stream_proxy_create
#undef stream_proxy_free_string
#undef stream_proxy_delete
#undef litert_lm_conversation_send_message_stream
#undef litert_lm_conversation_delete
#include <assert.h>
#include <pthread.h>
#include <stdlib.h>

typedef struct {
  stream_callback callback;
  void *data;
} owned_proxy;
static int copied_strings, proxies, conversations_deleted;
static bool active;
static stream_callback receiver;
static void *receiver_data;
int fixture_copied_strings(void) { return copied_strings; }
int fixture_proxies(void) { return proxies; }
int fixture_conversations_deleted(void) { return conversations_deleted; }
static char *copy_string(const char *text) {
  if (!text) return NULL;
  ++copied_strings;
  return strdup(text);
}
static void forward_owned(void *data, const char *text, bool final, const char *error) {
  owned_proxy *context = data;
  context->callback(context->data, copy_string(text), final, copy_string(error));
}
void *stream_proxy_create(stream_callback callback, void *data, stream_callback *out) {
  owned_proxy *context = calloc(1, sizeof *context);
  context->callback = callback;
  context->data = data;
  *out = forward_owned;
  ++proxies;
  return context;
}
void stream_proxy_free_string(char *text) {
  if (text) { memset(text, 0xCC, strlen(text)); free(text); --copied_strings; }
}
void stream_proxy_delete(void *data) {
  assert(!active);
  free(data);
  --proxies;
}
void litert_lm_conversation_delete(void *conversation) {
  assert(conversation && !active);
  ++conversations_deleted;
}
int litert_lm_conversation_send_message_stream(void *c, const char *m,
    const char *x, void *a, stream_callback callback, void *data) {
  assert(!active);
  receiver = callback;
  receiver_data = data;
  active = true;
  return 0;
}
static void *emit(void *argument) {
  int kind = *(int *)argument;
  char text[] = "{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"late\"}]}";
  char error[] = "INTERNAL: original native failure";
  bool final = kind >= 2;
  if (final) active = false;
  receiver(receiver_data, kind < 2 ? text : NULL, final,
      kind == 1 || kind == 3 ? error : NULL);
  memset(text, 'X', sizeof text - 1);
  memset(error, 'X', sizeof error - 1);
  return NULL;
}
void fixture_emit(int kind) {
  assert(active);
  pthread_t thread;
  assert(!pthread_create(&thread, NULL, emit, &kind));
  assert(!pthread_join(thread, NULL));
}
