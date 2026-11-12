#define litert_lm_thinking_config_create fixture_schema_create
#define litert_lm_thinking_config_delete fixture_schema_delete
#define litert_lm_thinking_config_set_enable_thinking fixture_schema_enable
#define litert_lm_conversation_optional_args_set_thinking_config fixture_schema_thinking_args
#define litert_lm_conversation_optional_args_create fixture_base_args_create
#define litert_lm_conversation_send_message_stream fixture_base_send
#define litert_lm_engine_tokenize fixture_base_tokenize
#define litert_lm_tokenize_result_get_num_tokens fixture_base_token_count
#define litert_lm_engine_detokenize fixture_base_detokenize
#include "c_api_v1_json_schema.c"
#undef litert_lm_thinking_config_create
#undef litert_lm_thinking_config_delete
#undef litert_lm_thinking_config_set_enable_thinking
#undef litert_lm_conversation_optional_args_set_thinking_config
#undef litert_lm_conversation_optional_args_create
#undef litert_lm_conversation_send_message_stream
#undef litert_lm_engine_tokenize
#undef litert_lm_tokenize_result_get_num_tokens
#undef litert_lm_engine_detokenize

typedef struct { int enabled, budget; } thinking_config;
typedef struct { turn_options base; bool thinking; thinking_config config; } thinking_args;
static int thinking_live, thinking_mode, thinking_token_mode;
static thinking_config sent_thinking;
static bool sent_thinking_present;
int fixture_thinking_live(void) { return thinking_live; }
int fixture_thinking_present(void) { return sent_thinking_present; }
int fixture_thinking_enabled(void) { return sent_thinking.enabled; }
int fixture_thinking_budget(void) { return sent_thinking.budget; }
void fixture_thinking_mode(int mode) { thinking_mode=mode; }
void fixture_thinking_token_mode(int mode) { thinking_token_mode=mode; }
#ifndef OMIT_THINK_CREATE
int litert_lm_thinking_config_create(void **out) {
  *out=NULL;if(status(91))return 13;
  if(thinking_mode==2)return 0;
  thinking_config *config=malloc(sizeof *config);config->enabled=1;config->budget=-1;
  *out=config;++live;++thinking_live;
  if(thinking_mode==1){snprintf(last_error,sizeof last_error,"thinking-partial %s",engine_text[0]);return 9;}
  return 0;
}
#endif
#ifndef OMIT_THINK_DELETE
void litert_lm_thinking_config_delete(void *config) { --thinking_live;drop(config); }
#endif
#ifndef OMIT_THINK_ENABLE
int litert_lm_thinking_config_set_enable_thinking(void *config,bool enabled) {
  assert(config);if(status(92))return 13;((thinking_config*)config)->enabled=enabled;return 0;
}
#endif
#ifndef OMIT_THINK_BUDGET
int litert_lm_thinking_config_set_thinking_token_budget(void *config,int budget) {
  assert(config);if(status(97))return 13;((thinking_config*)config)->budget=budget;return 0;
}
#endif
#ifndef OMIT_THINK_ARGS
int litert_lm_conversation_optional_args_set_thinking_config(void *args,const void *config) {
  assert(args && config);if(status(94))return 13;
  ((thinking_args*)args)->thinking=true;((thinking_args*)args)->config=*(const thinking_config*)config;
  return 0;
}
#endif
#ifndef OMIT_THINK_ARGS_CREATE
int litert_lm_conversation_optional_args_create(void **out) {
  *out=NULL;if(status(70))return 13;
  *out=calloc(1,sizeof(thinking_args));++live;++args_live;
  if(thinking_mode==3){snprintf(last_error,sizeof last_error,"args-partial %s",engine_text[0]);return 9;}
  return 0;
}
#endif
int litert_lm_conversation_send_message_stream(void *conversation,const char *message,
    const char *extra,const void *args,chunk_callback callback,void *data) {
  assert(thinking_live==0);
  sent_thinking_present=args && ((const thinking_args*)args)->thinking;
  sent_thinking=sent_thinking_present ? ((const thinking_args*)args)->config : (thinking_config){-1,-1};
  return fixture_base_send(conversation,message,extra,args,callback,data);
}
static int boundary_id(const char *text) {
  if(!strcmp(text,"<think>"))return 101;
  if(!strcmp(text,"</think>"))return 102;
  if(!strcmp(text,"思考："))return 103;
  if(!strcmp(text,"終了。"))return 104;
  return 0;
}
#ifndef OMIT_TOKENIZE
int litert_lm_engine_tokenize(void *engine,const char *text,void **out) {
  int code=fixture_base_tokenize(engine,text,out);
  int id=boundary_id(text);if(!code && id)token_data[0]=thinking_token_mode==3 ? -1 : thinking_token_mode==6 ? 101 : id;
  return code;
}
#endif
#ifndef OMIT_TOKEN_COUNT
int litert_lm_tokenize_result_get_num_tokens(const void *result,size_t *out) {
  int code=fixture_base_token_count(result,out);int id=boundary_id(token_texts[0]);
  if(!code && id)*out=(thinking_token_mode==1 && id==101) || (thinking_token_mode==2 && id==102) ? 0 : 1;
  return code;
}
#endif
#ifndef OMIT_DETOKENIZE
int litert_lm_engine_detokenize(void *engine,const int *tokens,size_t count,void **out) {
  int code=fixture_base_detokenize(engine,tokens,count,out);
  if(!code && count==1) {
    const char *text=tokens[0]==101 ? "<think>" : tokens[0]==102 ? "</think>" : tokens[0]==103 ? "思考：" : tokens[0]==104 ? "終了。" : "unknown";
    if(thinking_token_mode==6)text=token_texts[0];
    if((thinking_token_mode==4 && tokens[0]==101)||(thinking_token_mode==5 && tokens[0]==102))text="corrupt";
    snprintf(decoded_text,sizeof decoded_text,"%s",text);
  }
  return code;
}
#endif
