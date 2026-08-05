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
    // Independently compiled by a community publisher (piffie), not Qualcomm's own AI
    // Hub pipeline — only importable via GenieX's `--model-hub localfs` path (`--model-hub
    // hf` doesn't recognize raw genie/QAIRT bundles at all, see project memory), so it must
    // already be present in the local GenieX cache before this entry will load — there's
    // no `geniex pull` fallback the app can trigger on demand like the other geniex models.
    // Real 16k context (confirmed: verified with an actual >4096-token prompt), at the cost
    // of much lower throughput (~9 tok/s vs ~21 tok/s for Qwen3-8B) — a genuine capability
    // vs. speed tradeoff, not a bug.
    id:                 'llama32-3b-16k-npu',
    displayName:        'Llama 3.2 3B 16K (NPU)',
    fileSizeMb:         0, // GenieX pulls and caches its own model, nothing for the app to download
    fileName:           'piffie/Llama-3.2-3B-Instruct-Genie-Snapdragon-X2-Elite-v81-16k',
    licenseUrl:         'https://huggingface.co/meta-llama/Llama-3.2-3B-Instruct',
    platform:           'desktop',
    supportsVision:     false,
    supportsImageInput: false,
    maxContextTokens:   16384,
    backend:            'geniex',
    downloaded:         false,
    loaded:             false,
  },
]

export function findModel(id: string): ModelInfo | undefined {
  return ModelCatalog.find((m) => m.id === id)
}
