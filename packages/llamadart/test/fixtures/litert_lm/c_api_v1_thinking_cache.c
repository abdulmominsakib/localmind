#define litert_lm_engine_create fixture_base_cache_engine_create
#include "c_api_v1_thinking.c"
#undef litert_lm_engine_create
#include <sys/stat.h>
#include <unistd.h>

static int cache_checks;
static char checked_cache[256];
int fixture_cache_checks(void) { return cache_checks; }
int fixture_cache_exists(void) {
  struct stat info;
  return stat(checked_cache, &info) == 0 && S_ISDIR(info.st_mode)
      && access(checked_cache, W_OK) == 0;
}
int litert_lm_engine_create(void *settings, void **output) {
  ++cache_checks;
  snprintf(checked_cache, sizeof checked_cache, "%s", settings_text[4]);
  *output = NULL;
  /* Mirrors the real owner's pre-allocation cache validation boundary. */
  if (!fixture_cache_exists()) {
    snprintf(last_error, sizeof last_error,
             "Cache directory does not exist or is not writable: %s", checked_cache);
    return 3;
  }
  return fixture_base_cache_engine_create(settings, output);
}
