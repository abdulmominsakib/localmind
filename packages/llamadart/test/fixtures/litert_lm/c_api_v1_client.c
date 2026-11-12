#include "c_api_v1_tokenizer.c"
#include "c_api_v1_metadata.c"

static int client_log_level;
int fixture_client_log_level(void) { return client_log_level; }
int fixture_client_active(void) { return active; }
#ifndef OMIT_LOG_LEVEL
int litert_lm_set_min_log_level(int level) {
  if(status(81))return 13;client_log_level=level;return 0;
}
#endif

typedef struct { char *json; bool final; int reason; } client_emit;
static void *client_emit_thread(void *argument) {
  client_emit *event=argument;
  borrowed_chunk chunk={.text=event->json,.error=NULL,.final=event->final};
  receiver(receiver_data,&chunk);
  if(event->final)((proxy *)receiver_data)->reason=event->reason;
  if(event->json)memset(event->json,'X',strlen(event->json));
  return NULL;
}
void fixture_client_emit(const char *json,bool final,int reason) {
  assert(active);client_emit event={.json=json ? strdup(json) : NULL,.final=final,.reason=reason};
  pthread_t thread;assert(!pthread_create(&thread,NULL,client_emit_thread,&event));
  assert(!pthread_join(thread,NULL));free(event.json);
}
