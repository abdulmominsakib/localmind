#include "c_api_v1_client.c"
static int schema_provider, config_thinking=-1, args_thinking=-1, schema_kind;
static char copied_schema[8192];
int fixture_schema_provider(void) { return schema_provider; }
int fixture_config_thinking(void) { return config_thinking; }
int fixture_args_thinking(void) { return args_thinking; }
int fixture_schema_kind(void) { return schema_kind; }
const char *fixture_schema_text(void) { return copied_schema; }
#ifndef OMIT_SCHEMA_PROVIDER
int litert_lm_conversation_config_set_constraint_provider(void *config,int provider) {
  assert(config && provider==1);if(status(90))return 13;schema_provider=provider;return 0;
}
#endif
#ifndef OMIT_SCHEMA_CREATE
int litert_lm_thinking_config_create(void **out) {
  if(failure==96){*out=NULL;return 0;}return create(91,out);
}
#endif
#ifndef OMIT_SCHEMA_DELETE
void litert_lm_thinking_config_delete(void *config) { drop(config); }
#endif
#ifndef OMIT_SCHEMA_ENABLE
int litert_lm_thinking_config_set_enable_thinking(void *config,bool enabled) {
  assert(config);if(status(92))return 13;*(int *)config=enabled;return 0;
}
#endif
#ifndef OMIT_SCHEMA_CONFIG
int litert_lm_conversation_config_set_thinking_config(void *config,const void *thinking) {
  assert(config && thinking);if(status(93))return 13;config_thinking=*(const int *)thinking;return 0;
}
#endif
#ifndef OMIT_SCHEMA_ARGS
int litert_lm_conversation_optional_args_set_thinking_config(void *args,const void *thinking) {
  assert(args && thinking);if(status(94))return 13;args_thinking=*(const int *)thinking;return 0;
}
#endif
#ifndef OMIT_SCHEMA_CONSTRAINT
int litert_lm_conversation_optional_args_set_constraint(void *args,int kind,const char *schema) {
  assert(args && kind==2 && schema && strlen(schema)<sizeof copied_schema);
  if(status(95))return 13;schema_kind=kind;strcpy(copied_schema,schema);return 0;
}
#endif
