#ifndef LITERT_LM_NATIVE_BRIDGE_LITERT_LM_ASR_BRIDGE_H_
#define LITERT_LM_NATIVE_BRIDGE_LITERT_LM_ASR_BRIDGE_H_

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define LITERT_LM_ASR_EXPORT __declspec(dllexport)
#else
#define LITERT_LM_ASR_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define LITERT_LM_ASR_ABI_VERSION 1u

typedef struct LitertLmAsrEngine LitertLmAsrEngine;
typedef struct LitertLmAsrSession LitertLmAsrSession;

typedef enum LitertLmAsrStatus {
  LITERT_LM_ASR_STATUS_OK = 0,
  LITERT_LM_ASR_STATUS_INVALID_ARGUMENT = 1,
  LITERT_LM_ASR_STATUS_FAILED_PRECONDITION = 2,
  LITERT_LM_ASR_STATUS_NOT_FOUND = 3,
  LITERT_LM_ASR_STATUS_ALREADY_EXISTS = 4,
  LITERT_LM_ASR_STATUS_OUT_OF_RANGE = 5,
  LITERT_LM_ASR_STATUS_UNAVAILABLE = 6,
  LITERT_LM_ASR_STATUS_CANCELLED = 7,
  LITERT_LM_ASR_STATUS_RESOURCE_EXHAUSTED = 8,
  LITERT_LM_ASR_STATUS_INTERNAL = 9,
  // No complete inference window is buffered yet. Push more audio or finish
  // the input stream before calling process_next again.
  LITERT_LM_ASR_STATUS_NEEDS_MORE_AUDIO = 10,
  // The final transcript result has already been returned.
  LITERT_LM_ASR_STATUS_END_OF_STREAM = 11,
  // Only part (or none) of the supplied audio fit in the bounded input queue.
  // `out_accepted_samples` reports how much the caller may discard.
  LITERT_LM_ASR_STATUS_WOULD_BLOCK = 12,
} LitertLmAsrStatus;

typedef enum LitertLmAsrBackend {
  LITERT_LM_ASR_BACKEND_CPU = 0,
  LITERT_LM_ASR_BACKEND_GPU = 1,
  LITERT_LM_ASR_BACKEND_NPU = 2,
} LitertLmAsrBackend;

typedef enum LitertLmAsrDecoderType {
  LITERT_LM_ASR_DECODER_CTC = 0,
  LITERT_LM_ASR_DECODER_TDT = 1,
  LITERT_LM_ASR_DECODER_STATELESS = 2,
} LitertLmAsrDecoderType;

typedef enum LitertLmAsrTextMergerType {
  LITERT_LM_ASR_TEXT_MERGER_LEVENSHTEIN = 0,
  LITERT_LM_ASR_TEXT_MERGER_TIMESTAMP = 1,
} LitertLmAsrTextMergerType;

typedef enum LitertLmAsrLogMelNormType {
  LITERT_LM_ASR_LOG_MEL_NORM_STANDARD = 0,
  LITERT_LM_ASR_LOG_MEL_NORM_WHISPER = 1,
} LitertLmAsrLogMelNormType;

typedef enum LitertLmAsrModelPreset {
  LITERT_LM_ASR_MODEL_PRESET_PARAKEET_TDT_0_6B_V3 = 1,
  LITERT_LM_ASR_MODEL_PRESET_PARAKEET_CTC_0_6B = 2,
  LITERT_LM_ASR_MODEL_PRESET_MOONSHINE_TINY = 3,
  LITERT_LM_ASR_MODEL_PRESET_WHISPER_TINY = 4,
  LITERT_LM_ASR_MODEL_PRESET_QWEN3_ASR_0_6B = 5,
} LitertLmAsrModelPreset;

// Versioned engine and streaming-input configuration. Call
// litert_lm_asr_config_init before overriding fields. String pointers are
// borrowed only for the duration of litert_lm_asr_engine_create.
typedef struct LitertLmAsrConfig {
  uint32_t struct_size;
  uint32_t abi_version;

  const char *model_name;
  const char *model_path;
  const char *tokenizer_path;

  int32_t sample_rate_hz;
  int32_t num_channels;
  int32_t input_milliseconds;
  int32_t max_buffered_audio_milliseconds;
  LitertLmAsrDecoderType decoder_type;
  LitertLmAsrBackend backend;
  LitertLmAsrTextMergerType text_merger_type;
  int32_t num_threads;
  float overlap_ratio;

  int32_t has_log_mel_config;
  int32_t log_mel_n_fft;
  int32_t log_mel_n_mels;
  int32_t log_mel_hop_length;
  int32_t log_mel_n_frames;
  int32_t log_mel_transpose;
  float log_mel_preemphasis;
  LitertLmAsrLogMelNormType log_mel_norm_type;

  int32_t decode_start_token_id;
  int32_t decode_stop_token_id;
  int32_t decode_skip_until_token_id;
  int32_t decode_statefully_after;
  int32_t vocab_size;
  int32_t blank_token_id;
} LitertLmAsrConfig;

// Owned result payload. Initialize before first use and release after every
// successful process_next call. Confirmed text will not change in subsequent
// results; unconfirmed text may be revised by the next inference window.
typedef struct LitertLmAsrResult {
  uint32_t struct_size;
  char *confirmed_text;
  char *unconfirmed_text;
  int32_t is_final;
} LitertLmAsrResult;

LITERT_LM_ASR_EXPORT uint32_t litert_lm_asr_abi_version(void);
LITERT_LM_ASR_EXPORT size_t litert_lm_asr_config_size(void);
LITERT_LM_ASR_EXPORT size_t litert_lm_asr_result_size(void);
LITERT_LM_ASR_EXPORT void litert_lm_asr_config_init(LitertLmAsrConfig *config);
// Initializes the exact model-family parameters published in LiteRT-LM v0.16
// model_metadata.json. The caller still supplies local model/tokenizer paths
// and may override backend, threads, merger, overlap, and buffer settings.
LITERT_LM_ASR_EXPORT LitertLmAsrStatus
litert_lm_asr_config_init_for_model_preset(LitertLmAsrConfig *config,
                                           LitertLmAsrModelPreset preset);
LITERT_LM_ASR_EXPORT void litert_lm_asr_result_init(LitertLmAsrResult *result);
LITERT_LM_ASR_EXPORT void
litert_lm_asr_result_release(LitertLmAsrResult *result);
LITERT_LM_ASR_EXPORT void litert_lm_asr_free_string(char *value);

LITERT_LM_ASR_EXPORT LitertLmAsrStatus litert_lm_asr_engine_create(
    const LitertLmAsrConfig *config, LitertLmAsrEngine **out_engine,
    char **out_error_message);
LITERT_LM_ASR_EXPORT void
litert_lm_asr_engine_delete(LitertLmAsrEngine *engine);

LITERT_LM_ASR_EXPORT LitertLmAsrStatus litert_lm_asr_session_create(
    LitertLmAsrEngine *engine, LitertLmAsrSession **out_session,
    char **out_error_message);
LITERT_LM_ASR_EXPORT void
litert_lm_asr_session_delete(LitertLmAsrSession *session);

// Engine deletion is safe after session creation; each session retains the
// upstream model resources it needs. Do not delete a session concurrently with
// one of its other calls. cancel is the only operation intended to run while
// process_next is in flight.

// Pushes interleaved float PCM. ABI v1 accepts mono input only. The call may
// run concurrently with process_next. A WOULD_BLOCK result is not fatal; call
// process_next to drain a window, then retry the unaccepted suffix.
LITERT_LM_ASR_EXPORT LitertLmAsrStatus litert_lm_asr_session_push_audio_f32(
    LitertLmAsrSession *session, const float *samples, size_t sample_count,
    size_t *out_accepted_samples, char **out_error_message);

LITERT_LM_ASR_EXPORT LitertLmAsrStatus litert_lm_asr_session_finish_audio(
    LitertLmAsrSession *session, char **out_error_message);

// Runs at most one inference window synchronously. NEEDS_MORE_AUDIO is a
// normal flow-control result. The call that returns a result with is_final=1
// completes the stream; later calls return END_OF_STREAM.
LITERT_LM_ASR_EXPORT LitertLmAsrStatus litert_lm_asr_session_process_next(
    LitertLmAsrSession *session, LitertLmAsrResult *out_result,
    char **out_error_message);

LITERT_LM_ASR_EXPORT LitertLmAsrStatus litert_lm_asr_session_reset(
    LitertLmAsrSession *session, char **out_error_message);

// Requests cancellation between inference windows. LiteRT-LM v0.16 does not
// expose an interrupt for an inference call already in flight.
LITERT_LM_ASR_EXPORT LitertLmAsrStatus
litert_lm_asr_session_cancel(LitertLmAsrSession *session);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // LITERT_LM_NATIVE_BRIDGE_LITERT_LM_ASR_BRIDGE_H_
