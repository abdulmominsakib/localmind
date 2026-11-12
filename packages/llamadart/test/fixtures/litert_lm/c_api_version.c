#include <stdlib.h>

#ifndef API_MAJOR
#define API_MAJOR 1
#endif
#ifndef API_MINOR
#define API_MINOR 0
#endif
#ifndef API_PATCH
#define API_PATCH 0
#endif
#ifndef API_STATUS
#define API_STATUS 0
#endif

#ifndef OMIT_API_VERSION
int litert_lm_get_api_version(int *major, int *minor, int *patch) {
  *major = API_MAJOR;
  *minor = API_MINOR;
#ifndef OMIT_PATCH_WRITE
  *patch = API_PATCH;
#endif
  return API_STATUS;
}
#endif

#ifdef IN_PROCESS_LITERT_ABI
int litert_lm_native_in_process_litert_abi_version(void) {
  return IN_PROCESS_LITERT_ABI;
}
#endif

// A missing gate must fail the test process before an incompatible call can
// accidentally look like a supported engine initialization.
void *litert_lm_engine_settings_create(void) { abort(); }

#ifdef SMOKE_SYMBOLS
void litert_lm_engine_create(void) { abort(); }
void litert_lm_engine_delete(void) { abort(); }
void stream_proxy_create(void) { abort(); }
void stream_proxy_free_string(void) { abort(); }
void stream_proxy_delete(void) { abort(); }
#endif
