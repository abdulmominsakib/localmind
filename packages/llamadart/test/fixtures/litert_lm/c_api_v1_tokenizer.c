#include "c_api_v1_conversation.c"

static int token_mode, token_failure, token_calls[10], token_deletes[3];
static int token_data[3], bos_data[2], token_input[8];
static size_t token_input_count;
static char token_texts[2][128], bos_text[32], decoded_text[128];
void fixture_token_mode(int value) { token_mode = value; }
void fixture_token_fail(int value) { token_failure = value; }
int fixture_token_calls(int index) { return token_calls[index]; }
int fixture_token_deletes(int index) { return token_deletes[index]; }
int fixture_token_input(int index) { return token_input[index]; }
size_t fixture_token_input_count(void) { return token_input_count; }
const char *fixture_token_text(int index) { return token_texts[index]; }
void fixture_token_reset(void) {
  assert(live == 0);
  token_mode = token_failure = 0;
  memset(token_calls, 0, sizeof token_calls);
  memset(token_deletes, 0, sizeof token_deletes);
  memset(token_texts, 0, sizeof token_texts);
  fixture_fail(0);
}
static int token_status(int stage) {
  ++token_calls[stage];
  if (token_failure != stage) return 0;
  snprintf(last_error, sizeof last_error, "token-stage%d /secret/models/m.litertlm /secret/cache", stage);
  return 13;
}
static void *token_owned(void) { ++live; return malloc(1); }
static void token_drop(void *value, int kind) {
  assert(value); ++token_deletes[kind]; drop(value);
}
#ifndef OMIT_TOKENIZE
int litert_lm_engine_tokenize(void *engine, const char *text, void **out) {
  assert(engine && text && out); *out = NULL;
  if (token_status(1)) return 13;
  snprintf(token_texts[1], sizeof token_texts[1], "%s", token_texts[0]);
  snprintf(token_texts[0], sizeof token_texts[0], "%s", text);
  if (token_mode == 100) return 0;
  size_t length = strlen(text);
  token_data[0] = (int)length;
  token_data[1] = length ? (unsigned char)text[0] : 0;
  token_data[2] = length ? (unsigned char)text[length - 1] : 0;
  if (!strcmp(text,"BOS")) { token_data[0] = 900; token_data[1] = 901; }
  *out = token_owned(); return 0;
}
#endif
#ifndef OMIT_TOKEN_COUNT
int litert_lm_tokenize_result_get_num_tokens(const void *result, size_t *out) {
  assert(result && out); if (token_status(2)) return 13;
  *out = token_mode == 104 ? ((size_t)1 << 32) + 1 :
      token_mode == 103 || !token_texts[0][0] ? 0 :
      !strcmp(token_texts[0],"BOS") ? 2 : 3;
  return 0;
}
#endif
#ifndef OMIT_TOKEN_ARRAY
int litert_lm_tokenize_result_get_tokens(const void *result, const int **out) {
  assert(result && out); *out = NULL; if (token_status(3)) return 13;
  *out = token_mode == 102 || token_mode == 103 || !token_texts[0][0] ? NULL : token_data;
  return 0;
}
#endif
#ifndef OMIT_TOKEN_DELETE
void litert_lm_tokenize_result_delete(void *result) {
  for (int i=0;i<3;++i) token_data[i]=-777;
  token_drop(result,0);
}
#endif
#ifndef OMIT_TOKEN_START
int litert_lm_engine_get_start_token(void *engine, void **out) {
  assert(engine && out); *out = NULL; if (token_status(4)) return 13;
  if (token_mode == 0 || token_mode >= 100) return 0;
  bos_data[0]=11;bos_data[1]=22;strcpy(bos_text, token_mode == 4 ? "" : "BOS");
  *out = token_owned(); return 0;
}
#endif
#ifndef OMIT_TOKEN_TYPE
int litert_lm_token_union_get_type(const void *result, int *out) {
  assert(result && out); if (token_status(5)) return 13;
  *out = token_mode == 5 ? 9 : (token_mode == 2 || token_mode == 4 || token_mode == 7) ? 0 : 1;
  return 0;
}
#endif
#ifndef OMIT_TOKEN_IDS
int litert_lm_token_union_get_ids(const void *result, const int **out, size_t *count) {
  assert(result && out && count); *out = NULL; if (token_status(6)) return 13;
  *out = token_mode == 3 || token_mode == 6 ? NULL : bos_data;
  *count = token_mode == 3 ? 0 : token_mode == 8 ? ((size_t)1 << 32) + 1 : 2;
  return 0;
}
#endif
#ifndef OMIT_TOKEN_STRING
int litert_lm_token_union_get_string(const void *result, const char **out) {
  assert(result && out); *out = NULL; if (token_status(7)) return 13;
  *out = token_mode == 7 ? NULL : bos_text; return 0;
}
#endif
#ifndef OMIT_TOKEN_UNION_DELETE
void litert_lm_token_union_delete(void *result) {
  bos_data[0]=bos_data[1]=-888;strcpy(bos_text,"deleted");token_drop(result,1);
}
#endif
#ifndef OMIT_DETOKENIZE
int litert_lm_engine_detokenize(void *engine, const int *tokens, size_t count, void **out) {
  assert(engine && tokens && out && count<=8);*out=NULL;
  if(token_status(8))return 13;
  token_input_count=count;for(size_t i=0;i<count;++i)token_input[i]=tokens[i];
  if(token_mode==101)return 0;
  strcpy(decoded_text, token_mode==105 ? "" : "decoded 世界🙂");
  *out=token_owned();return 0;
}
#endif
#ifndef OMIT_DETOKEN_STRING
int litert_lm_detokenize_result_get_string(const void *result, const char **out) {
  assert(result && out);*out=NULL;if(token_status(9))return 13;
  *out=token_mode==106 ? NULL : decoded_text;return 0;
}
#endif
#ifndef OMIT_DETOKEN_DELETE
void litert_lm_detokenize_result_delete(void *result) {
  strcpy(decoded_text,"deleted");token_drop(result,2);
}
#endif
