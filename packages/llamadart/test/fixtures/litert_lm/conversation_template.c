// Minimal C ABI fixture for the Dart conversation-template and sampler FFI paths.
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
static char template_text[32768];
static char system_text[32768];
const char* fixture_system_message(void) { return system_text; }
void litert_lm_conversation_config_set_system_message(void* p, const char* s) { strncpy(system_text, s, sizeof(system_text) - 1); }
void litert_lm_set_min_log_level(int level) {}
void* litert_lm_engine_settings_create(const char* m, const char* b, const char* v, const char* a) { return (void*)1; }
void litert_lm_engine_settings_set_max_num_tokens(void* p, int n) {}
void litert_lm_engine_settings_enable_benchmark(void* p) {}
void litert_lm_engine_settings_set_enable_speculative_decoding(void* p, bool b) {}
void litert_lm_engine_settings_delete(void* p) {}
void* litert_lm_engine_create(void* p) { return (void*)2; }
void litert_lm_engine_delete(void* p) {}
void* litert_lm_session_config_create(void) { return (void*)3; }
void litert_lm_session_config_delete(void* p) {}
// Layout must match _LegacyLiteRtLmSamplerParams in litert_lm_runtime.dart.
typedef struct { int32_t type, top_k; float top_p, temperature; int32_t seed; } sampler_params;
static sampler_params session_sampler;
static int32_t sampler_sets;
int32_t fixture_top_k(void) { return session_sampler.top_k; }
float fixture_temperature(void) { return session_sampler.temperature; }
int32_t fixture_sampler_sets(void) { return sampler_sets; }
void litert_lm_session_config_set_sampler_params(void* p, const void* s) { session_sampler = *(const sampler_params*)s; sampler_sets++; }
#ifndef OMIT_OPAQUE_SAMPLER
static sampler_params opaque_sampler;
void* litert_lm_sampler_params_create(int32_t type) { opaque_sampler = (sampler_params){type}; return &opaque_sampler; }
void litert_lm_sampler_params_delete(void* p) {}
void litert_lm_sampler_params_set_top_k(void* p, int32_t k) { ((sampler_params*)p)->top_k = k; }
void litert_lm_sampler_params_set_top_p(void* p, float v) { ((sampler_params*)p)->top_p = v; }
void litert_lm_sampler_params_set_temperature(void* p, float v) { ((sampler_params*)p)->temperature = v; }
void litert_lm_sampler_params_set_seed(void* p, int32_t v) { ((sampler_params*)p)->seed = v; }
#endif
void* litert_lm_conversation_config_create(void) { template_text[0] = 0; return (void*)4; }
void litert_lm_conversation_config_set_session_config(void* p, void* s) {}
void litert_lm_conversation_config_set_enable_constrained_decoding(void* p, bool b) {}
#ifndef OMIT_TEMPLATE_SETTER
void litert_lm_conversation_config_set_prompt_template(void* p, const char* t) {
  strncpy(template_text, t, sizeof(template_text) - 1);
}
#endif
void litert_lm_conversation_config_delete(void* p) {}
void* litert_lm_conversation_create(void* e, void* c) { return (void*)5; }
void litert_lm_conversation_delete(void* p) {}
#ifndef OMIT_RENDER
const char* litert_lm_conversation_render_message_to_string(void* p, const char* m) { return template_text; }
#endif
