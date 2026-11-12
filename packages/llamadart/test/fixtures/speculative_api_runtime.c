#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

// Synthetic export sets test binding behavior; they are not a runtime-version handshake.
// The test passes Dart's generated size. These large structs use indirect
// passing/return on the supported host ABIs; none of their fields is read.
typedef struct { uint64_t words[CONTEXT_PARAMS_SIZE / 8]; } context_params;
typedef struct {
    int32_t n_tokens;
    int32_t *token;
    float *embd;
    int32_t *pos;
    int32_t *n_seq_id;
    int32_t **seq_id;
    int8_t *logits;
} batch;
static int calls[10];
static void require_null(void *pointer) { if (pointer) abort(); }
EXPORT int fixture_context_params_size(void) { return sizeof(context_params); }
EXPORT int fixture_batch_size(void) { return sizeof(batch); }
EXPORT int fixture_call_count(int index) { return calls[index]; }
EXPORT context_params llama_context_default_params(void) {
    context_params result = {0};
    return result;
}
EXPORT batch llama_batch_init(int32_t count, int32_t embd, int32_t seq) {
    batch result = {0};
    return result;
}
EXPORT void llama_batch_free(batch value) {}
EXPORT void *llama_dart_speculative_init(void *model, void *draft, void *context,
                                        context_params params, void *config) {
    require_null(model); require_null(draft); require_null(context); require_null(config);
    calls[0]++;
    return NULL;
}
EXPORT void llama_dart_speculative_free(void *session) { require_null(session); calls[1]++; }
EXPORT void *llama_dart_speculative_get_draft_context(void *session) {
    require_null(session); calls[2]++; return NULL;
}
EXPORT bool llama_dart_speculative_begin(void *session, int32_t seq, void *prompt, int32_t count) {
    require_null(session); require_null(prompt); calls[3]++; return false;
}
#ifndef OMIT_PROCESS_BATCH
EXPORT bool llama_dart_speculative_process_batch(void *session, batch value) {
    require_null(session); calls[4]++; return false;
}
#endif
EXPORT int32_t llama_dart_speculative_draft(void *session, int32_t seq, int32_t past,
                                          int32_t last, void *prompt, int32_t count,
                                          int32_t maximum, void *output, int32_t capacity) {
    require_null(session); require_null(prompt); require_null(output); calls[5]++; return -1;
}
EXPORT void llama_dart_speculative_accept(void *session, int32_t seq, uint16_t count) {
    require_null(session); calls[6]++;
}
EXPORT int32_t llama_dart_sampler_sample_and_accept_n(void *sampler, void *context,
                                                     void *draft, int32_t draft_count,
                                                     void *indices, int32_t index_count,
                                                     void *output, int32_t capacity) {
    require_null(sampler); require_null(context); require_null(draft);
    require_null(indices); require_null(output); calls[7]++; return -1;
}
#ifdef RETAIN_LEGACY_QUERIES
EXPORT bool llama_dart_speculative_need_embd(void *session) { require_null(session); calls[8]++; return false; }
#endif
EXPORT bool llama_dart_speculative_need_embd_nextn(void *session) { require_null(session); calls[9]++; return false; }
