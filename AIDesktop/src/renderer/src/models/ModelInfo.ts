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
    id:                 'qwen3-8b-npu',
    displayName:        'Qwen3 8B (NPU)',
    fileSizeMb:         0, // GenieX pulls and caches its own model, nothing for the app to download
    fileName:           'qualcomm/Qwen3-8B',
    licenseUrl:         'https://huggingface.co/Qwen/Qwen3-8B',
    platform:           'desktop',
    supportsVision:     false,
    supportsImageInput: false,
    maxContextTokens:   4096,
    backend:            'geniex',
    downloaded:         false,
    loaded:             false,
  },
  {
    // NPU model availability is chip-specific to Qualcomm's AI Hub compile catalog (see
    // project memory) — confirmed working via GenieX on this exact chip (Snapdragon X2
    // Elite Extreme), not verified on other Snapdragon X-series variants.
    id:                 'qwen3-vl-4b-npu',
    displayName:        'Qwen3 VL 4B (NPU)',
    fileSizeMb:         0, // GenieX pulls and caches its own model, nothing for the app to download
    fileName:           'qualcomm/Qwen3-VL-4B-Instruct',
    licenseUrl:         'https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct',
    platform:           'desktop',
    supportsVision:     true,
    supportsImageInput: true,
    maxContextTokens:   4096,
    backend:            'geniex',
    downloaded:         false,
    loaded:             false,
  },
  {
    // NPU model availability is chip-specific to Qualcomm's AI Hub compile catalog (see
    // project memory) — confirmed working via GenieX on this exact chip (Snapdragon X2
    // Elite Extreme), not verified on other Snapdragon X-series variants.
    id:                 'qwen3-1-7b-npu',
    displayName:        'Qwen3 1.7B (NPU)',
    fileSizeMb:         0, // GenieX pulls and caches its own model, nothing for the app to download
    fileName:           'qualcomm/Qwen3-1.7B',
    licenseUrl:         'https://huggingface.co/Qwen/Qwen3-1.7B',
    platform:           'desktop',
    supportsVision:     false,
    supportsImageInput: false,
    maxContextTokens:   4096,
    backend:            'geniex',
    downloaded:         false,
    loaded:             false,
  },
]

export function findModel(id: string): ModelInfo | undefined {
  return ModelCatalog.find((m) => m.id === id)
}
