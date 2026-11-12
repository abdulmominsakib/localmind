// Test-only forwarding image. All payload operations still execute in the
// caller-selected immutable runtime; counters expose the production FFI chain.
#include "llama_dart_wrapper.h"
#include <atomic>
#include <cassert>
#include <dlfcn.h>

static void *runtime;
static std::atomic<int> counts[12];
static std::atomic<void *> token;
static std::atomic<bool> active;
static std::atomic<bool> parent_release;
static std::atomic<void *> model_address, context_address;
static void *symbol(const char *name) {
  void *address = dlsym(runtime, name);
  assert(address); return address;
}
extern "C" {
void owner_chain_probe_initialize(const char *path) {
  runtime = dlopen(path, RTLD_NOW | RTLD_LOCAL); assert(runtime);
}
int owner_chain_probe_count(int index) { assert(index >= 0 && index < 12); return counts[index]; }
void owner_chain_probe_parent_release(bool value) { parent_release = value; }
void *llama_dart_owner_create() {
  auto result = reinterpret_cast<void *(*)()>(symbol("llama_dart_owner_create"))();
  token = result; active = false; ++counts[0]; return result;
}
bool llama_dart_owner_activate(void *value) {
  if (value != token) ++counts[9];
  bool result = reinterpret_cast<bool (*)(void *)>(symbol("llama_dart_owner_activate"))(value);
  active = result; ++counts[1]; return result;
}
void llama_dart_owner_release(void *value) {
  ++counts[6]; if (parent_release) ++counts[10];
  reinterpret_cast<void (*)(void *)>(symbol("llama_dart_owner_release"))(value);
}
void llama_dart_owner_abandon(void *value) {
  ++counts[7]; reinterpret_cast<void (*)(void *)>(symbol("llama_dart_owner_abandon"))(value);
}
llama_model *llama_dart_owner_model_load_from_file(void *value, const char *path, llama_model_params params) {
  if (value != token || !active) ++counts[9];
  ++counts[2];
  auto *result = reinterpret_cast<llama_model *(*)(void *,const char *,llama_model_params)>(symbol("llama_dart_owner_model_load_from_file"))(value,path,params);
  model_address = result; return result;
}
llama_context *llama_dart_owner_init_from_model(void *value, llama_model *model, llama_context_params params) {
  if (value != token || !active) ++counts[9];
  ++counts[3];
  auto *result = reinterpret_cast<llama_context *(*)(void *,llama_model *,llama_context_params)>(symbol("llama_dart_owner_init_from_model"))(value,model,params);
  context_address = result; return result;
}
mtmd_context *llama_dart_owner_mtmd_init_from_file(void *value, const char *path, const llama_model *model, const mtmd_context_params *params) {
  if (value != token || !active) ++counts[9];
  ++counts[11]; return reinterpret_cast<mtmd_context *(*)(void *,const char *,const llama_model *,const mtmd_context_params *)>(symbol("llama_dart_owner_mtmd_init_from_file"))(value,path,model,params);
}
int32_t llama_dart_owner_track(void *value, void *object, void (*free_function)(void *), int32_t stage) {
  int result = reinterpret_cast<int32_t (*)(void *,void *,void (*)(void *),int32_t)>(symbol("llama_dart_owner_track"))(value,object,free_function,stage);
  if (result == 2) ++counts[4]; if (result == 1) ++counts[5];
  if (stage < 0 || stage > 5 ||
      (object == model_address && (stage != 5 || result != 2)) ||
      (object == context_address && (stage != 2 || result != 2))) ++counts[9];
  return result;
}
bool llama_dart_owner_untrack(void *value, void *object) {
  if (object == model_address || object == context_address) ++counts[9];
  ++counts[8]; return reinterpret_cast<bool (*)(void *,void *)>(symbol("llama_dart_owner_untrack"))(value,object);
}
}
