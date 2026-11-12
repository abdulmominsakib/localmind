#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#ifndef PROBE_ABI
#define PROBE_ABI 1
#endif

__attribute__((constructor)) static void startup(void) {
  fprintf(stdout, "PRIVATE_DIAGNOSTIC_TOKEN /Users/private-user/key\n");
  fprintf(stderr, "PRIVATE_DIAGNOSTIC_TOKEN https://private.invalid/?token=SECRET\n");
  fflush(stdout);
  fflush(stderr);
#if defined(PROBE_ABORT)
  abort();
#elif defined(PROBE_HANG)
  sleep(60);
#endif
}

void llama_model_default_params(void) {}
void llama_model_load_from_file(void) {}
#ifndef PROBE_MISSING_SYMBOL
void llama_decode(void) {}
#endif
void llama_dart_model_load_from_file(void) {}
void llama_dart_init_from_model(void) {}
void llama_dart_sampler_sample(void) {}
int32_t llama_dart_tts_api_version(void) { return PROBE_ABI; }
