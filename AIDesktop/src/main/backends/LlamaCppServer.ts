import { join } from 'path'
import { app } from 'electron'
import { is } from '@electron-toolkit/utils'
import * as fs from 'fs'
import { InferenceServer } from './InferenceServer'

const DEFAULT_PORT = 8765

/** llama.cpp's llama-server, used on macOS and Windows x64. */
export class LlamaCppServer extends InferenceServer {
  constructor() {
    super(DEFAULT_PORT)
  }

  protected get binaryPath(): string {
    if (is.dev) {
      // During dev, look for a llama-server binary next to the project
      const devPath = join(app.getAppPath(), '..', 'bin', 'llama-server')
      if (fs.existsSync(devPath)) return devPath
      // Fall back to PATH
      return 'llama-server'
    }
    // In packaged app, binary is bundled in resources/
    const platform = process.platform
    const binaryName = platform === 'win32' ? 'llama-server.exe' : 'llama-server'
    return join(process.resourcesPath, 'bin', binaryName)
  }

  protected buildArgs(modelPath: string): string[] {
    return [
      '--model', modelPath,
      '--port', String(this.port),
      '--host', '127.0.0.1',
      '--ctx-size', '8192',
      '--n-gpu-layers', '99',   // offload all layers to GPU when available
    ]
  }
}
