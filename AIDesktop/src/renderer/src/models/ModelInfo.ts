export interface ModelInfo {
  id:                string
  displayName:       string
  fileSizeMb:        number
  /**
   * For backend 'llama-cpp': the file downloaded to modelsDir, loaded from a real
   * local path. For backend 'geniex': the GenieX model ID (e.g. "qualcomm/Qwen3-8B")
   * — there's no local file, GenieX resolves and caches it itself on first use, and
   * this string is passed straight through to llama:start / the chat request's
   * "model" field instead of being joined with modelsDir.
   */
  fileName:          string
  licenseUrl:        string
  /** 'desktop' | 'mobile' | 'both' */
  platform:          string
  gemmaVersion?:      number
  supportsVision:    boolean
  supportsImageInput: boolean
  maxContextTokens:  number
  /** Which InferenceServer implementation this model runs on — determines both
   *  which platforms it's shown on (see AppContext's buildCatalog) and how
   *  loadModel/sendMessage interpret fileName. */
  backend:           'llama-cpp' | 'geniex'
  /** backend:'geniex' only — passed as `geniex serve --compute <value>`. Defaults to
   *  'npu' (every qairt-plugin model's native path) when omitted; set explicitly for
   *  a llama_cpp-plugin model (GGUF pulled via --model-hub hf) that measured faster on
   *  a different compute unit under sustained load — see project notes. */
  geniexCompute?:    'npu' | 'gpu' | 'cpu'
  // Runtime state
  downloaded:        boolean
  loaded:            boolean
}

export const ModelCatalog: ModelInfo[] = [
  {
    id:                 'gemma4-e4b-it',
    displayName:        'Gemma 4 E4B',
    fileSizeMb:         4980,
    fileName:           'gemma-4-E4B-it-Q4_K_M.gguf',
    licenseUrl:         'https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF',
    platform:           'desktop',
    gemmaVersion:       4,
    supportsVision:     false,
    supportsImageInput: false,
    maxContextTokens:   8192,
    backend:            'llama-cpp',
    downloaded:         false,
    loaded:             false,
  },
  {
    id:                 'gemma4-12b-it',
    displayName:        'Gemma 4 12B',
    fileSizeMb:         6720,
    fileName:           'gemma-4-12B-it-qat-UD-Q4_K_XL.gguf',
    licenseUrl:         'https://huggingface.co/unsloth/gemma-4-12B-it-qat-GGUF',
    platform:           'desktop',
    gemmaVersion:       4,
    supportsVision:     false,
    supportsImageInput: false,
    maxContextTokens:   8192,
    backend:            'llama-cpp',
    downloaded:         false,
    loaded:             false,
  },
  {
    // NPU model availability is chip-specific to Qualcomm's AI Hub compile catalog (see
    // project memory) — confirmed working via GenieX on this exact chip (Snapdragon X2
    // Elite), not verified on other Snapdragon X-series variants. Was blocked (empty
    // supported-chipset list) as recently as the same day this was integrated; only
    // just became pullable after a GenieX update, so re-verify chipset support if this
    // ever starts failing to load again rather than assuming it's a regression.
    // Gemma's own Terms of Use (not Apache/MIT) apply — see the repo's NOTICE file.
    // `max_tokens` was confirmed ignored by the qairt plugin on earlier GenieX versions
    // (server always generated to a fixed ~2048-token cap regardless of the request —
    // see https://github.com/qualcomm/GenieX/issues/1403), appears fixed as of the
    // GenieX version this was integrated on, but re-verify after any future GenieX
    // update. Long-form generation has shown real hallucinations in testing (e.g.
    // misattributing Gutenberg's "Aha!" moment to Johannes Fust, his financier) —
    // watch for this on other qairt models too if any get added back in the future.
    // This is now the daily-driver model (2026-09-20), replacing the since-removed
    // Qwen3 NPU models — see project memory for why.
    id:                 'gemma4-e4b-npu',
    displayName:        'Gemma 4 E4B (NPU)',
    fileSizeMb:         0, // GenieX pulls and caches its own model, nothing for the app to download
    fileName:           'qualcomm/Gemma-4-E4B-it',
    licenseUrl:         'https://huggingface.co/qualcomm/Gemma-4-E4B-it',
    platform:           'desktop',
    gemmaVersion:       4,
    supportsVision:     true,
    supportsImageInput: true,
    maxContextTokens:   4096,
    backend:            'geniex',
    downloaded:         false,
    loaded:             false,
  },
  {
    // llama_cpp-plugin model (pulled via `--model-hub hf`, not Qualcomm's AI Hub
    // catalog), MoE architecture (21B total / 3.6B active per token). Previously
    // crashed on every GenieX compute path (`ggml-backend.cpp:584: GGML_ASSERT(device)
    // failed`, see project memory's "GPU exploration" entries, 2026-07-29/30) — fixed
    // as of GenieX v0.8.1-rc.4 via two upstream PRs that stopped pinning GPT-OSS
    // experts to CPU and added GPU-specific flash attention for this model specifically.
    // `geniexCompute: 'gpu'` is intentional, not the usual 'npu' default — measured
    // ~5.8x faster on GPU under a sustained 800-token generation (2.38 vs 13.9 tok/s),
    // the opposite of every other geniex model in this catalog. Don't change this to
    // 'npu' without re-benchmarking; don't assume this generalizes to other models —
    // GPU is confirmed *worse* than CPU for ordinary dense models on this chip's Adreno
    // GPU (see the September "GPU is not real acceleration" finding).
    // Upstream context window is 128K, but a KV-cache-cost caveat applies at that size
    // (see project notes, "128k context trap") — set to 32768 as a middle ground given
    // this model's already-documented CPU-heavy footprint on this chip. maxContextTokens
    // is passed straight through as `geniex serve --nctx` (see AppContext.loadModel /
    // GenieXServer.buildArgs) — it's a real, functional value for this llama_cpp-plugin
    // model, not just catalog display text. Raise further deliberately, not by default,
    // if actual long-context use is needed — re-benchmark first, don't assume it scales.
    id:                 'gpt-oss-20b-gpu',
    displayName:        'GPT-OSS 20B (GPU)',
    fileSizeMb:         0, // GenieX pulls and caches its own model, nothing for the app to download
    fileName:           'unsloth/gpt-oss-20b-GGUF:Q4_K_M',
    licenseUrl:         'https://huggingface.co/openai/gpt-oss-20b',
    platform:           'desktop',
    supportsVision:     false,
    supportsImageInput: false,
    maxContextTokens:   32768,
    backend:            'geniex',
    geniexCompute:      'gpu',
    downloaded:         false,
    loaded:             false,
  },
]

export function findModel(id: string): ModelInfo | undefined {
  return ModelCatalog.find((m) => m.id === id)
}
