// LiteRtLm-Bridging-Header.h
// Swift bridging header for the LiteRT-LM C API (native-v0.10.2).
//
// Source: https://github.com/google-ai-edge/LiteRT-LM/blob/main/c/engine.h
// Prebuilt dylibs: https://github.com/DenisovAV/flutter_gemma/releases/tag/native-v0.10.2

#ifndef LiteRtLm_Bridging_Header_h
#define LiteRtLm_Bridging_Header_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ── Opaque types ─────────────────────────────────────────────────────────────

typedef struct LiteRtLmEngine             LiteRtLmEngine;
typedef struct LiteRtLmSession            LiteRtLmSession;
typedef struct LiteRtLmResponses          LiteRtLmResponses;
typedef struct LiteRtLmEngineSettings     LiteRtLmEngineSettings;
typedef struct LiteRtLmConversation       LiteRtLmConversation;
typedef struct LiteRtLmSessionConfig      LiteRtLmSessionConfig;
typedef struct LiteRtLmConversationConfig LiteRtLmConversationConfig;
typedef struct LiteRtLmJsonResponse       LiteRtLmJsonResponse;
typedef struct LiteRtLmBenchmarkInfo      LiteRtLmBenchmarkInfo;

// ── Enumerations ─────────────────────────────────────────────────────────────

typedef enum {
    kLiteRtLmSamplerTypeUnspecified = 0,
    kLiteRtLmSamplerTypeTopK        = 1,
    kLiteRtLmSamplerTypeTopP        = 2,
    kLiteRtLmSamplerTypeGreedy      = 3,
} LiteRtLmSamplerType;

typedef enum {
    kLiteRtLmInputDataTypeText  = 0,
    kLiteRtLmInputDataTypeImage = 1,
    kLiteRtLmInputDataTypeAudio = 2,
} LiteRtLmInputDataType;

// ── Parameter structs ─────────────────────────────────────────────────────────

typedef struct {
    LiteRtLmSamplerType type;
    int32_t             top_k;
    float               top_p;
    float               temperature;
    int32_t             seed;
} LiteRtLmSamplerParams;

typedef struct {
    LiteRtLmInputDataType type;
    const void*           data;   // UTF-8 string for text inputs
    size_t                size;   // byte length (excluding null terminator)
} LiteRtLmInputData;

// ── Stream callback ───────────────────────────────────────────────────────────

/// Fired once per generated chunk (and once more with is_final=true).
/// chunk   — partial token text; may be NULL on the final call.
/// is_final— true on the last invocation (no more calls will follow).
/// error   — non-NULL if generation failed; NULL on success.
typedef void (*LiteRtLmStreamCallback)(
    void*        callback_data,
    const char*  chunk,
    bool         is_final,
    const char*  error_msg
);

// ── Engine settings ───────────────────────────────────────────────────────────

/// Create engine settings.
/// backend_str: "cpu" or "gpu"
/// vision_backend_str / audio_backend_str: NULL if unused.
LiteRtLmEngineSettings* litert_lm_engine_settings_create(
    const char* model_path,
    const char* backend_str,
    const char* vision_backend_str,
    const char* audio_backend_str);

void litert_lm_engine_settings_set_max_num_tokens(
    LiteRtLmEngineSettings* settings, int max_num_tokens);

void litert_lm_engine_settings_set_cache_dir(
    LiteRtLmEngineSettings* settings, const char* cache_dir);

void litert_lm_engine_settings_delete(LiteRtLmEngineSettings* settings);

// ── Engine lifecycle ──────────────────────────────────────────────────────────

/// Create and initialise an engine from the given settings.
/// Returns NULL on failure. Blocking — may take several seconds.
LiteRtLmEngine* litert_lm_engine_create(const LiteRtLmEngineSettings* settings);

void litert_lm_engine_delete(LiteRtLmEngine* engine);

// ── Session config ────────────────────────────────────────────────────────────

LiteRtLmSessionConfig* litert_lm_session_config_create(void);

void litert_lm_session_config_set_max_output_tokens(
    LiteRtLmSessionConfig* config, int max_output_tokens);

void litert_lm_session_config_set_apply_prompt_template(
    LiteRtLmSessionConfig* config, bool apply_prompt_template);

void litert_lm_session_config_set_sampler_params(
    LiteRtLmSessionConfig* config,
    const LiteRtLmSamplerParams* sampler_params);

void litert_lm_session_config_delete(LiteRtLmSessionConfig* config);

// ── Session lifecycle ─────────────────────────────────────────────────────────

/// config may be NULL (uses engine defaults).
LiteRtLmSession* litert_lm_engine_create_session(
    LiteRtLmEngine*       engine,
    LiteRtLmSessionConfig* config);

void litert_lm_session_delete(LiteRtLmSession* session);

void litert_lm_session_cancel_process(LiteRtLmSession* session);

// ── Session inference ─────────────────────────────────────────────────────────

/// Blocking: prefill the session KV-cache with the given input.
int litert_lm_session_run_prefill(
    LiteRtLmSession*        session,
    const LiteRtLmInputData* inputs,
    size_t                  num_inputs);

/// Blocking: decode until stop token; returns full response.
LiteRtLmResponses* litert_lm_session_run_decode(LiteRtLmSession* session);

/// Blocking convenience: prefill + decode in one call.
LiteRtLmResponses* litert_lm_session_generate_content(
    LiteRtLmSession*        session,
    const LiteRtLmInputData* inputs,
    size_t                  num_inputs);

/// Streaming: prefill + decode, calling callback for each token chunk.
/// Returns 0 on success. The callback fires on an internal LiteRT-LM thread.
int litert_lm_session_generate_content_stream(
    LiteRtLmSession*        session,
    const LiteRtLmInputData* inputs,
    size_t                  num_inputs,
    LiteRtLmStreamCallback  callback,
    void*                   callback_data);

/// Streaming: stream decode after a prior run_prefill call.
int litert_lm_session_run_decode_async(
    LiteRtLmSession*       session,
    LiteRtLmStreamCallback callback,
    void*                  callback_data);

// ── Responses ─────────────────────────────────────────────────────────────────

void        litert_lm_responses_delete(LiteRtLmResponses* responses);
int         litert_lm_responses_get_num_candidates(const LiteRtLmResponses* responses);
const char* litert_lm_responses_get_response_text_at(
                const LiteRtLmResponses* responses, int index);

// ── Logging ───────────────────────────────────────────────────────────────────

/// 0=VERBOSE 1=DEBUG 2=INFO 3=WARNING 4=ERROR 5=FATAL 1000=SILENT
void litert_lm_set_min_log_level(int level);

#ifdef __cplusplus
}
#endif
#endif /* LiteRtLm_Bridging_Header_h */
