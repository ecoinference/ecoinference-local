import { contextBridge, ipcRenderer } from 'electron'
import { electronAPI } from '@electron-toolkit/preload'

const fsOps = {
  modelsDir:  ():                              Promise<string>   => ipcRenderer.invoke('fs:modelsDir'),
  listFiles:  (dir: string):                   Promise<string[]> => ipcRenderer.invoke('fs:listFiles', dir),
  unlink:     (path: string):                  Promise<void>     => ipcRenderer.invoke('fs:unlink', path),
  rename:     (from: string, to: string):      Promise<void>     => ipcRenderer.invoke('fs:rename', from, to),
  openWrite:  (path: string):                  Promise<void>     => ipcRenderer.invoke('fs:openWrite', path),
  writeChunk: (path: string, chunk: Uint8Array): Promise<void>   => ipcRenderer.invoke('fs:writeChunk', path, chunk),
  closeWrite: (path: string):                  Promise<void>     => ipcRenderer.invoke('fs:closeWrite', path),
  abortWrite: (path: string):                  Promise<void>     => ipcRenderer.invoke('fs:abortWrite', path),
}

const llamaAPI = {
  start:  (modelPath: string): Promise<{ ok: boolean; error?: string }> => ipcRenderer.invoke('llama:start', modelPath),
  stop:   ():                  Promise<void>                             => ipcRenderer.invoke('llama:stop'),
  status: ():                  Promise<unknown>                          => ipcRenderer.invoke('llama:status'),
}

const themeAPI = {
  get:      ():                               Promise<boolean> => ipcRenderer.invoke('theme:get'),
  onChange: (cb: (dark: boolean) => void):   void             => { ipcRenderer.on('theme:changed', (_e, dark) => cb(dark)) },
}

export interface UpdaterStatus {
  state:    'checking' | 'available' | 'not-available' | 'downloading' | 'downloaded' | 'error'
  version?: string
  percent?: number
  message?: string
}

const updaterAPI = {
  check:     ():                                  Promise<void> => ipcRenderer.invoke('updater:check'),
  install:   ():                                  Promise<void> => ipcRenderer.invoke('updater:install'),
  onStatus:  (cb: (status: UpdaterStatus) => void): void        => { ipcRenderer.on('updater:status', (_e, status) => cb(status)) },
}

export interface UpdateInfo {
  justUpdated:      boolean
  previousVersion?: string
  currentVersion:   string
}

const appInfoAPI = {
  getVersion:    (): Promise<string>              => ipcRenderer.invoke('app:getVersion'),
  getUpdateInfo: (): Promise<UpdateInfo | null>    => ipcRenderer.invoke('app:getUpdateInfo'),
  getPlatform:   (): Promise<{ platform: string; arch: string }> => ipcRenderer.invoke('app:getPlatform'),
}

if (process.contextIsolated) {
  try {
    contextBridge.exposeInMainWorld('electron', electronAPI)
    contextBridge.exposeInMainWorld('fsOps', fsOps)
    contextBridge.exposeInMainWorld('llama', llamaAPI)
    contextBridge.exposeInMainWorld('theme', themeAPI)
    contextBridge.exposeInMainWorld('updater', updaterAPI)
    contextBridge.exposeInMainWorld('appInfo', appInfoAPI)
  } catch (e) {
    console.error(e)
  }
} else {
  // @ts-ignore
  window.electron = electronAPI
  // @ts-ignore
  window.fsOps = fsOps
  // @ts-ignore
  window.llama = llamaAPI
  // @ts-ignore
  window.theme = themeAPI
  // @ts-ignore
  window.updater = updaterAPI
  // @ts-ignore
  window.appInfo = appInfoAPI
}
