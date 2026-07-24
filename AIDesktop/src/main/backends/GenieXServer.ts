import { InferenceServer } from './InferenceServer'

const DEFAULT_PORT = 18181

/**
 * Qualcomm's GenieX (github.com/qualcomm/GenieX) — used on Windows ARM64/Snapdragon
 * to run models on the Hexagon NPU via its bundled QAIRT runtime. Local testing only:
 * relies on GenieX already being installed separately (geniex.exe on PATH), not
 * bundled into the app — redistribution terms for Qualcomm's proprietary QAIRT
 * runtime binaries haven't been checked, so this isn't packaged for release yet.
 */
export class GenieXServer extends InferenceServer {
  constructor() {
    super(DEFAULT_PORT)
  }

  protected get binaryPath(): string {
    return 'geniex'
  }

  protected buildArgs(_modelPath: string): string[] {
    // geniex serve takes no model at startup — it's selected per-request via the
    // "model" field in the chat completion body instead. modelPath here is really
    // the model ID the caller intends to use (e.g. "qualcomm/Qwen3-8B"); the base
    // class still tracks it via _modelPath for status(), it's just not a CLI arg.
    return ['serve', '--compute', 'npu', '--host', `127.0.0.1:${this.port}`]
  }

  protected healthPath(): string {
    return '/v1/models'
  }

  protected validateModelPath(_modelPath: string): string | null {
    // Opaque GenieX model ID, not a local file — nothing to check here.
    return null
  }
}
