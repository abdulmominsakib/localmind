#include <stdio.h>

#if defined(FACADE_COMPANION)
void fixture_companion(void) {}
#else
#define litert_lm_engine_create fixture_validation_engine_create
#if defined(FACADE_V1)
#include "c_api_v1_asr.c"
#else
#include "c_api_legacy_service.c"
#endif
#undef litert_lm_engine_create
#if defined(FACADE_V1)
int litert_lm_engine_create(void *settings, void **out) {
  fputs("FACADE_ENGINE_CREATE\n", stderr);
  fflush(stderr);
  return fixture_validation_engine_create(settings, out);
}
#else
void *litert_lm_engine_create(void *settings) {
  fputs("FACADE_ENGINE_CREATE\n", stderr);
  fflush(stderr);
  return fixture_validation_engine_create(settings);
}
#endif
#endif

__attribute__((constructor)) static void fixture_validation_loaded(void) {
  fputs("FACADE_LIBRARY_OPEN\n", stderr);
  fflush(stderr);
}
