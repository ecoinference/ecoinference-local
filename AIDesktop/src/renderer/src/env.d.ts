/// <reference types="vite/client" />
import type { ElectronAPI } from '@electron-toolkit/preload'

declare global {
  interface Window {
    electron: ElectronAPI
    fsOps: {
      modelsDir:  ()                                => Promise<string>
      listFiles:  (dir: string)                     => Promise<string[]>
      unlink:     (path: string)                    => Promise<void>
      rename:     (from: string, to: string)        => Promise<void>
      openWrite:  (path: string)                    => Promise<void>
      writeChunk: (path: string, chunk: Uint8Array) => Promise<void>
      closeWrite: (path: string)                    => Promise<void>
      abortWrite: (path: string)                    => Promise<void>
    }
    llama: {
      start:  (modelPath: string) => Promise<{ ok: boolean; error?: string }>
      stop:   ()                  => Promise<void>
      status: ()                  => Promise<unknown>
    }
    theme: {
      get:      ()                              => Promise<boolean>
      onChange: (cb: (dark: boolean) => void)   => void
    }
    updater: {
      check:    ()                                      => Promise<void>
      install:  ()                                      => Promise<void>
      onStatus: (cb: (status: {
        state:    'checking' | 'available' | 'not-available' | 'downloading' | 'downloaded' | 'error'
        version?: string
        percent?: number
        message?: string
      }) => void) => void
    }
    appInfo: {
      getVersion:    () => Promise<string>
      getUpdateInfo: () => Promise<{
        justUpdated:      boolean
        previousVersion?: string
        currentVersion:   string
      } | null>
      getPlatform:   () => Promise<{ platform: string; arch: string }>
    }
  }
}
