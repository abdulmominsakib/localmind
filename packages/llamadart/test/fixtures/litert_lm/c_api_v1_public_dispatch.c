#define litert_lm_engine_create fixture_public_base_engine_create
#ifdef FIXTURE_TAGGED_SETTINGS
#define litert_lm_engine_settings_create fixture_public_base_settings_create
#define litert_lm_engine_settings_delete fixture_public_base_settings_delete
#endif
#include "c_api_v1_asr.c"
#undef litert_lm_engine_create
#ifdef FIXTURE_TAGGED_SETTINGS
#undef litert_lm_engine_settings_create
#undef litert_lm_engine_settings_delete
#include <stdint.h>

// A host-only opaque handle models Android's signed high-byte heap tags.
// Only this fixture translates it back for free; production must preserve it.
static void *public_settings, *public_tagged_settings;
static int public_tagged_creates;
int fixture_public_tagged_creates(void) { return public_tagged_creates; }
int litert_lm_engine_settings_create(const char *m, const char *b,
                                    const char *v, const char *a, void **out) {
  int result = fixture_public_base_settings_create(m, b, v, a, out);
  if (!result && *out) {
    assert(sizeof(uintptr_t) == 8 && !public_settings);
    public_settings = *out;
    assert(((uintptr_t)public_settings >> 56) == 0);
    public_tagged_settings = (void *)((uintptr_t)public_settings | (UINT64_C(0xb4) << 56));
    *out = public_tagged_settings;
  }
  return result;
}
void litert_lm_engine_settings_delete(void *settings) {
  assert(settings == public_tagged_settings && public_settings);
  fixture_public_base_settings_delete(public_settings);
  public_settings = public_tagged_settings = NULL;
}
#endif

static int public_attempts, public_gpu_refusals, public_cpu_creates;
__attribute__((constructor)) static void fixture_public_loaded(void) {
  fputs("PUBLIC_FIXTURE_LOADED\n", stderr);
  fflush(stderr);
}
int fixture_public_engine_attempts(void) { return public_attempts; }
int fixture_public_gpu_refusals(void) { return public_gpu_refusals; }
int fixture_public_cpu_creates(void) { return public_cpu_creates; }
void fixture_public_reset(void) {
  assert(live == 0);
  public_attempts = public_gpu_refusals = public_cpu_creates = 0;
}
int litert_lm_engine_create(void *settings, void **out) {
#ifdef FIXTURE_TAGGED_SETTINGS
  assert(settings == public_tagged_settings && public_settings);
  ++public_tagged_creates;
#endif
  ++public_attempts;
  if (!strcmp(settings_text[1], "gpu")) {
    ++public_gpu_refusals;
    *out = NULL;
    snprintf(last_error, sizeof last_error,
             "Android GPU safety preflight refused the known fixture; use CPU.");
    return 9;
  }
  ++public_cpu_creates;
  return fixture_public_base_engine_create(settings, out);
}
