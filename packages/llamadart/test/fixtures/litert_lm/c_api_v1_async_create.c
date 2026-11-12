#define litert_lm_engine_create fixture_base_engine_create
#define litert_lm_engine_delete fixture_base_engine_delete
#define litert_lm_engine_settings_delete fixture_base_settings_delete
#define litert_lm_get_last_error_message fixture_base_error_message
#define litert_lm_clear_last_error fixture_base_clear_error
#include "c_api_v1_client.c"
#undef litert_lm_engine_create
#undef litert_lm_engine_delete
#undef litert_lm_engine_settings_delete
#undef litert_lm_get_last_error_message
#undef litert_lm_clear_last_error
#include <stdatomic.h>
#include <unistd.h>

static _Atomic int async_hold, async_entered, async_mode, async_calls, settings_deleted, engines_deleted;
static _Thread_local char async_error[512] = "main thread stale error";
static int legacy_code_reads;
void fixture_async_reset(void) {
 assert(live==0);atomic_store(&async_hold,0);atomic_store(&async_entered,0);atomic_store(&async_mode,0);atomic_store(&async_calls,0);atomic_store(&settings_deleted,0);atomic_store(&engines_deleted,0);fixture_reset_settings();
}
void fixture_async_hold(int value) { atomic_store(&async_hold,value); }
void fixture_async_mode(int value) { atomic_store(&async_mode,value); }
int fixture_async_entered(void) { return atomic_load(&async_entered); }
int fixture_async_calls(void) { return atomic_load(&async_calls); }
int fixture_async_settings_deleted(void) { return atomic_load(&settings_deleted); }
int fixture_async_engines_deleted(void) { return atomic_load(&engines_deleted); }
const char* litert_lm_get_last_error_message(void) { return async_error; }
#ifdef LEGACY_CODE_TRAP
int litert_lm_get_last_error_code(void) { legacy_code_reads++;return 15; }
#endif
int fixture_async_legacy_code_reads(void) { return legacy_code_reads; }
void litert_lm_clear_last_error(void) { async_error[0]=0; }
void litert_lm_engine_settings_delete(void* settings) {
 atomic_fetch_add(&settings_deleted,1);snprintf(async_error,sizeof async_error,"cleanup overwrote thread error");fixture_base_settings_delete(settings);
}
void litert_lm_engine_delete(void* engine) {
 if(engine)atomic_fetch_add(&engines_deleted,1);snprintf(async_error,sizeof async_error,"partial-owner cleanup overwrote thread error");fixture_base_engine_delete(engine);
}
int litert_lm_engine_create(void* settings,void** output) {
 int call=atomic_fetch_add(&async_calls,1)+1;atomic_store(&async_entered,1);*output=NULL;
 while(atomic_load(&async_hold))usleep(1000);
 int mode=atomic_load(&async_mode);
 if(mode==4)return 0;
 if(mode==2 || mode==3 || (mode==5 && call==1)) {
  if(mode==3){int result=fixture_base_engine_create(settings,output);assert(result==0 && *output);}

  snprintf(async_error,sizeof async_error,"FAILED_PRECONDITION: worker engine failure /secret/models/m.litertlm /secret/cache token=https://user:secret@example.test/model?token=private");
  return 9;
 }
 return fixture_base_engine_create(settings,output);
}
