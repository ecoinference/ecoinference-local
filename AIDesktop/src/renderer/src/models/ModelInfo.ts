export interface ModelInfo {
  id:                string
  displayName:       string
  fileSizeMb:        number
  fileName:          string
  licenseUrl:        string
  /** 'desktop' | 'mobile' | 'both' */
  platform:          string
  gemmaVersion:      number
  supportsVision:    boolean
  supportsImageInput: boolean
  maxContextTokens:  number
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
    downloaded:         false,
    loaded:             false,
  },
]

export function findModel(id: string): ModelInfo | undefined {
  return ModelCatalog.find((m) => m.id === id)
}
