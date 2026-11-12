#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "asr_abi1.h"

static int collision_calls;

// Exported by the executable to model a previously loaded native runtime.
void litert_lm_asr_free_string(char* value) {
  collision_calls++;
  free(value);
}

#define LOAD(type, name) \
  type name = (type)dlsym(handle, #name); \
  assert(name)

int main(int argc, char** argv) {
  assert(argc == 2);
  void* handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!handle) {
    fprintf(stderr, "%s\n", dlerror());
    return 2;
  }
  typedef int (*Count)(void);
  LOAD(Count, fixture_asr_strings);
  LOAD(Count, fixture_asr_results);
  LOAD(Count, fixture_asr_engines);
  LOAD(Count, fixture_asr_sessions);
  typedef LitertLmAsrStatus (*Init)(LitertLmAsrConfig*, LitertLmAsrModelPreset);
  LOAD(Init, litert_lm_asr_config_init_for_model_preset);
  typedef LitertLmAsrStatus (*CreateEngine)(const LitertLmAsrConfig*,
                                          LitertLmAsrEngine**, char**);
  LOAD(CreateEngine, litert_lm_asr_engine_create);
  typedef LitertLmAsrStatus (*CreateSession)(LitertLmAsrEngine*,
                                           LitertLmAsrSession**, char**);
  LOAD(CreateSession, litert_lm_asr_session_create);
  typedef LitertLmAsrStatus (*Push)(LitertLmAsrSession*, const float*, size_t,
                                  size_t*, char**);
  LOAD(Push, litert_lm_asr_session_push_audio_f32);
  typedef void (*ResultCall)(LitertLmAsrResult*);
  LOAD(ResultCall, litert_lm_asr_result_init);
  LOAD(ResultCall, litert_lm_asr_result_release);
  typedef LitertLmAsrStatus (*Process)(LitertLmAsrSession*, LitertLmAsrResult*,
                                     char**);
  LOAD(Process, litert_lm_asr_session_process_next);
  typedef void (*DeleteEngine)(LitertLmAsrEngine*);
  LOAD(DeleteEngine, litert_lm_asr_engine_delete);
  typedef void (*DeleteSession)(LitertLmAsrSession*);
  LOAD(DeleteSession, litert_lm_asr_session_delete);

  LitertLmAsrConfig config;
  assert(litert_lm_asr_config_init_for_model_preset(
             &config, LITERT_LM_ASR_MODEL_PRESET_MOONSHINE_TINY) == 0);
  config.model_path = "fixture";
  config.tokenizer_path = "fixture";
  LitertLmAsrEngine* engine = NULL;
  LitertLmAsrSession* session = NULL;
  char* error = NULL;
  assert(litert_lm_asr_engine_create(&config, &engine, &error) == 0);
  assert(litert_lm_asr_session_create(engine, &session, &error) == 0);
  float pcm[] = {1, 2, 3, 4};
  size_t accepted = 0;
  assert(litert_lm_asr_session_push_audio_f32(session, pcm, 4, &accepted,
                                            &error) ==
         LITERT_LM_ASR_STATUS_WOULD_BLOCK);
  assert(accepted == 3);
  LitertLmAsrResult result;
  litert_lm_asr_result_init(&result);
  assert(litert_lm_asr_session_process_next(session, &result, &error) == 0);
  assert(fixture_asr_strings() == 2);
  assert(strcmp(result.confirmed_text, "part") == 0);
  assert(strcmp(result.unconfirmed_text, "pending") == 0);
  litert_lm_asr_result_release(&result);
  litert_lm_asr_session_delete(session);
  litert_lm_asr_engine_delete(engine);
  printf("strings=%d results=%d engines=%d sessions=%d collision_calls=%d\n",
         fixture_asr_strings(), fixture_asr_results(), fixture_asr_engines(),
         fixture_asr_sessions(), collision_calls);
  int failed = fixture_asr_strings() != 0 || fixture_asr_results() != 0 ||
               fixture_asr_engines() != 0 || fixture_asr_sessions() != 0 ||
               collision_calls != 0;
  dlclose(handle);
  return failed;
}
