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
]

export function findModel(id: string): ModelInfo | undefined {
  return ModelCatalog.find((m) => m.id === id)
}
