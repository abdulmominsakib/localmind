#include <stdint.h>
#include <stddef.h>

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

// No model is allocated: these addresses are identity tokens for Dart's
// liveness checks. The cold probe resolves the sampler API from the hook-built
// wrapper library, not this fixture, without constructing a sampler.
EXPORT void * llama_model_get_vocab(void * model) {
    return (void *) (uintptr_t) 0x2000;
}
EXPORT void llama_model_free(void * model) {}
EXPORT void llama_free(void * context) {}

// Three backends expose four devices because Metal has two device ordinals.
EXPORT size_t ggml_backend_reg_count(void) { return 3; }

// Registry order deliberately differs from each backend's device ordinal.
EXPORT size_t ggml_backend_dev_count(void) { return 4; }
EXPORT void * ggml_backend_dev_get(size_t index) {
    return (void *) (uintptr_t) (index + 10);
}
EXPORT int ggml_backend_dev_type(void * device) {
    uintptr_t index = (uintptr_t) device - 10;
    return index == 0 ? 0 : index == 2 ? 2 : 1; // CPU, GPU, iGPU, GPU
}
EXPORT void * ggml_backend_dev_backend_reg(void * device) { return device; }
EXPORT const char * ggml_backend_reg_name(void * registry) {
    uintptr_t index = (uintptr_t) registry - 10;
    return index == 0 ? "CPU" : index == 1 ? "Vulkan" : "Metal";
}
EXPORT const char * ggml_backend_dev_name(void * device) {
    static const char * names[] = { "CPU", "Vulkan0", "MTL0", "MTL1" };
    return names[(uintptr_t) device - 10];
}
