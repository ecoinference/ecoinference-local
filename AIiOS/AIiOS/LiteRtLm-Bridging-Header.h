// LiteRtLm-Bridging-Header.h
// Swift bridging header for the LiteRT-LM C API (native-v0.12.0 patched dylib).
//
// Source of truth:
//   https://github.com/DenisovAV/flutter_gemma/blob/native-v0.12.0/native/litert_lm/include/engine.h
//   https://github.com/DenisovAV/flutter_gemma/blob/native-v0.12.0/lib/core/ffi/litert_lm_client.dart
//
// The dylib shipped in the native-v0.12.0 release is PATCHED from the upstream
// LiteRT-LM source.  Key patch: litert_lm_conversation_config_create takes
// LiteRtLmEngine* as its FIRST argument (6-arg overload) so the session config
// can be applied at config-creation time.  Passing nil/NULL for the engine
// causes the function to return NULL.
//
// DO NOT add functions that are not in the canonical engine.h —
// undefined symbols cause a link error on iOS.

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
typedef struct LiteRtLmJsonResponse            LiteRtLmJsonResponse;
typedef struct LiteRtLmBenchmarkInfo           LiteRtLmBenchmarkInfo;
/// Introduced in the native-v0.12.0 patched dylib.
/// Must be non-NULL in send_message / send_message_stream — passing NULL
/// causes the library to read garbage from the stack and return nil/segfault.
typedef struct LiteRtLmConversationOptionalArgs LiteRtLmConversationOptionalArgs;

// ── Enumerations ─────────────────────────────────────────────────────────────

typedef enum {
    kTypeUnspecified = 0,
    kTopK            = 1,
    kTopP            = 2,
    kGreedy          = 3,
} LiteRtLmSamplerTypeEnum;

typedef enum {
    kInputText,
    kInputImage,
    kInputImageEnd,
    kInputAudio,
    kInputAudioEnd,
} InputDataType;

// ── Parameter structs ─────────────────────────────────────────────────────────

typedef struct {
    LiteRtLmSamplerTypeEnum type;
    int32_t                 top_k;
    float                   top_p;
    float                   temperature;
    int32_t                 seed;
} LiteRtLmSamplerParams;

typedef struct {
    InputDataType type;
    const void*   data;   // UTF-8 string for text; raw bytes for image/audio
    size_t        size;   // byte length (excluding null terminator for text)
} InputData;

// ── Stream callback ───────────────────────────────────────────────────────────

/// Fired once per generated chunk (and once more with is_final=true).
/// chunk    — partial token text (JSON for Conversation API); may be NULL on the final call.
/// is_final — true on the last invocation.
/// error_msg — non-NULL if generation failed; NULL on success.
typedef void (*LiteRtLmStreamCallback)(
    void*        callback_data,
    const char*  chunk,
    bool         is_final,
    const char*  error_msg
);

// ── Engine settings ───────────────────────────────────────────────────────────

LiteRtLmEngineSettings* litert_lm_engine_settings_create(
    const char* model_path,
    const char* backend_str,
    const char* vision_backend_str,
    const char* audio_backend_str);

void litert_lm_engine_settings_set_max_num_tokens(
    LiteRtLmEngineSettings* settings, int max_num_tokens);

void litert_lm_engine_settings_set_max_num_images(
    LiteRtLmEngineSettings* settings, int max_num_images);

void litert_lm_engine_settings_set_cache_dir(
    LiteRtLmEngineSettings* settings, const char* cache_dir);

void litert_lm_engine_settings_enable_benchmark(
    LiteRtLmEngineSettings* settings);

void litert_lm_engine_settings_set_enable_speculative_decoding(
    LiteRtLmEngineSettings* settings, bool enable);

void litert_lm_engine_settings_delete(LiteRtLmEngineSettings* settings);

// ── Benchmark ─────────────────────────────────────────────────────────────────

/// Returns a new LiteRtLmBenchmarkInfo snapshot; caller must call
/// litert_lm_benchmark_info_delete when done.  Returns NULL if benchmarking
/// was not enabled via litert_lm_engine_settings_enable_benchmark().
LiteRtLmBenchmarkInfo* litert_lm_session_get_benchmark_info(
    LiteRtLmSession* session);

LiteRtLmBenchmarkInfo* litert_lm_conversation_get_benchmark_info(
    LiteRtLmConversation* conversation);

void   litert_lm_benchmark_info_delete(LiteRtLmBenchmarkInfo* benchmark_info);
double litert_lm_benchmark_info_get_time_to_first_token(
           const LiteRtLmBenchmarkInfo* benchmark_info);
double litert_lm_benchmark_info_get_total_init_time_in_second(
           const LiteRtLmBenchmarkInfo* benchmark_info);
int    litert_lm_benchmark_info_get_num_decode_turns(
           const LiteRtLmBenchmarkInfo* benchmark_info);
double litert_lm_benchmark_info_get_decode_tokens_per_sec_at(
           const LiteRtLmBenchmarkInfo* benchmark_info, int index);
int    litert_lm_benchmark_info_get_decode_token_count_at(
           const LiteRtLmBenchmarkInfo* benchmark_info, int index);

// ── Engine lifecycle ──────────────────────────────────────────────────────────

/// Returns NULL on failure. Blocking — may take several seconds.
LiteRtLmEngine* litert_lm_engine_create(const LiteRtLmEngineSettings* settings);

void litert_lm_engine_delete(LiteRtLmEngine* engine);

// ── Session config ────────────────────────────────────────────────────────────

LiteRtLmSessionConfig* litert_lm_session_config_create(void);

void litert_lm_session_config_set_max_output_tokens(
    LiteRtLmSessionConfig* config, int max_output_tokens);

void litert_lm_session_config_set_sampler_params(
    LiteRtLmSessionConfig* config,
    const LiteRtLmSamplerParams* sampler_params);

void litert_lm_session_config_delete(LiteRtLmSessionConfig* config);

// ── Session lifecycle ─────────────────────────────────────────────────────────

/// config may be NULL (uses engine defaults).
LiteRtLmSession* litert_lm_engine_create_session(
    LiteRtLmEngine*        engine,
    LiteRtLmSessionConfig* config);

void litert_lm_session_delete(LiteRtLmSession* session);

// ── Session inference ─────────────────────────────────────────────────────────

/// Blocking: prefill + decode in one call.
LiteRtLmResponses* litert_lm_session_generate_content(
    LiteRtLmSession*   session,
    const InputData*   inputs,
    size_t             num_inputs);

/// Streaming: prefill + decode, firing callback for each token chunk.
/// Returns 0 on success.
int litert_lm_session_generate_content_stream(
    LiteRtLmSession*       session,
    const InputData*       inputs,
    size_t                 num_inputs,
    LiteRtLmStreamCallback callback,
    void*                  callback_data);

// ── Responses ─────────────────────────────────────────────────────────────────

void        litert_lm_responses_delete(LiteRtLmResponses* responses);
int         litert_lm_responses_get_num_candidates(const LiteRtLmResponses* responses);
const char* litert_lm_responses_get_response_text_at(
                const LiteRtLmResponses* responses, int index);

// ── Conversation config ───────────────────────────────────────────────────────

/// PATCHED 6-arg overload in the native-v0.12.0 dylib.
/// engine               — must be non-NULL (the config is bound to this engine).
/// session_config       — sampler params / max_output_tokens; NULL = defaults.
/// system_message_json  — plain-text system message string; NULL = none.
/// tools_json           — JSON array of tool descriptions; NULL = none.
/// messages_json        — JSON array of prior turns for warm-start; NULL = fresh.
/// enable_constrained_decoding — true only when tools_json is non-NULL.
LiteRtLmConversationConfig* litert_lm_conversation_config_create(
    LiteRtLmEngine*              engine,
    const LiteRtLmSessionConfig* session_config,
    const char*                  system_message_json,
    const char*                  tools_json,
    const char*                  messages_json,
    bool                         enable_constrained_decoding);

void litert_lm_conversation_config_delete(LiteRtLmConversationConfig* config);

// ── Conversation lifecycle ─────────────────────────────────────────────────────

LiteRtLmConversation* litert_lm_conversation_create(
    LiteRtLmEngine*             engine,
    LiteRtLmConversationConfig* config);

void litert_lm_conversation_delete(LiteRtLmConversation* conversation);

void litert_lm_conversation_cancel_process(LiteRtLmConversation* conversation);

// ── Conversation inference ─────────────────────────────────────────────────────

/// Lifecycle for the optional-args object required by send_message[_stream].
LiteRtLmConversationOptionalArgs* litert_lm_conversation_optional_args_create(void);
void litert_lm_conversation_optional_args_delete(LiteRtLmConversationOptionalArgs* args);

/// Blocking: send message and return response as JSON.
/// message_json — {"role":"user","content":[{"type":"text","text":"..."},
///                 {"type":"image","blob":"<base64>"}]}
/// extra_context — optional JSON string (e.g. {"enable_thinking":true}); NULL = none.
/// optional_args — must be non-NULL (native-v0.12.0 patch); create with
///                 litert_lm_conversation_optional_args_create().
/// Returns NULL on failure.
LiteRtLmJsonResponse* litert_lm_conversation_send_message(
    LiteRtLmConversation*             conversation,
    const char*                       message_json,
    const char*                       extra_context,
    LiteRtLmConversationOptionalArgs* optional_args);

/// Streaming: send message and stream response via callback.
/// Each chunk is JSON: {"role":"assistant","content":[{"type":"text","text":"..."}]}.
/// End-of-stream: is_final=true with NULL chunk.
/// optional_args — must be non-NULL (native-v0.12.0 patch).
/// Returns 0 on success.
int litert_lm_conversation_send_message_stream(
    LiteRtLmConversation*             conversation,
    const char*                       message_json,
    const char*                       extra_context,
    LiteRtLmConversationOptionalArgs* optional_args,
    LiteRtLmStreamCallback            callback,
    void*                             callback_data);

// ── JSON response ──────────────────────────────────────────────────────────────

void        litert_lm_json_response_delete(LiteRtLmJsonResponse* response);
const char* litert_lm_json_response_get_string(
                const LiteRtLmJsonResponse* response);

// ── Logging ───────────────────────────────────────────────────────────────────

/// 0=INFO 1=WARNING 2=ERROR 3=FATAL
void litert_lm_set_min_log_level(int level);

#ifdef __cplusplus
}
#endif

#endif /* LiteRtLm_Bridging_Header_h */
