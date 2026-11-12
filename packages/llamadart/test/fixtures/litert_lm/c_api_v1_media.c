#define litert_lm_conversation_optional_args_create fixture_base_args_create
#define litert_lm_conversation_send_message_stream fixture_base_send
#define litert_lm_get_api_version fixture_base_version
#define litert_lm_engine_tokenize fixture_base_tokenize
#define litert_lm_tokenize_result_get_num_tokens fixture_base_token_count
#define litert_lm_engine_detokenize fixture_base_detokenize
#include "c_api_v1_client.c"
#undef litert_lm_engine_tokenize
#undef litert_lm_tokenize_result_get_num_tokens
#undef litert_lm_engine_detokenize
#undef litert_lm_conversation_optional_args_create
#undef litert_lm_conversation_send_message_stream
#undef litert_lm_get_api_version
#ifndef MEDIA_API_MAJOR
#define MEDIA_API_MAJOR 1
#endif
int litert_lm_get_api_version(int *a,int *b,int *c) { *a=MEDIA_API_MAJOR;*b=0;*c=0;return 0; }
typedef struct { turn_options base; int visual; bool present; } media_args;
static int media_budget, media_hint_calls;
int fixture_media_budget(void) { return media_budget; }
int fixture_media_hint_calls(void) { return media_hint_calls; }
int litert_lm_engine_settings_set_max_num_images(void *settings,int count) {
  (void)settings;(void)count;++media_hint_calls;return 13;
}
int litert_lm_conversation_optional_args_create(void **out) {
  *out=NULL;if(status(70))return 13;
  *out=calloc(1,sizeof(media_args));++live;++args_live;return 0;
}
#ifndef OMIT_VISUAL_BUDGET
int litert_lm_conversation_optional_args_set_visual_token_budget(void *args,int value) {
  assert(args);if(status(85))return 13;
  ((media_args *)args)->visual=value;((media_args *)args)->present=true;return 0;
}
#endif
int litert_lm_conversation_send_message_stream(void *conversation,const char *message,
    const char *extra,const void *args,chunk_callback callback,void *data) {
  media_budget=args && ((media_args *)args)->present ? ((media_args *)args)->visual : -1;
  return fixture_base_send(conversation,message,extra,args,callback,data);
}

static int media_inference;
void fixture_media_inference(int value) { media_inference=value; }
int litert_lm_engine_tokenize(void *engine,const char *text,void **out) {
  int code=fixture_base_tokenize(engine,text,out);
  if(!code && media_inference==1 && !strcmp(text,"<start_of_audio>"))token_data[0]=256000;
  return code;
}
int litert_lm_tokenize_result_get_num_tokens(const void *result,size_t *out) {
  int code=fixture_base_token_count(result,out);
  if(!code && media_inference==1 && !strcmp(token_texts[0],"<start_of_audio>"))*out=1;
  return code;
}
int litert_lm_engine_detokenize(void *engine,const int *tokens,size_t count,void **out) {
  int code=fixture_base_detokenize(engine,tokens,count,out);
  if(!code && media_inference && count==1 && tokens[0]==105)strcpy(decoded_text,"<start_of_turn>");
  return code;
}
