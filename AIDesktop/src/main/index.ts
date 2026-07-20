import { app, shell, BrowserWindow, ipcMain, nativeTheme } from 'electron'
import { join } from 'path'
import * as fs from 'fs'
import { electronApp, optimizer, is } from '@electron-toolkit/utils'
import { LlamaServer } from './llamaServer'
import { initAutoUpdater, checkForUpdatesNow, quitAndInstall } from './autoUpdate'
import { checkForRecentUpdate, UpdateInfo } from './versionTracker'

// Chromium's default ANGLE backend (D3D11) fails silently on Windows ARM64 +
// Adreno (renders a fully blank window, no error) — likely because Adreno's
// D3D11 driver support is a translation layer, not native. Adreno GPUs are
// built around Vulkan/GLES natively, so route ANGLE through Vulkan instead of
// falling back to software rendering. See WINDOWS_HANDOFF.md-adjacent notes:
// if Vulkan doesn't pan out, try 'gl' next — both are more native to Adreno
// than D3D11.
if (process.platform === 'win32' && process.arch === 'arm64') {
  app.commandLine.appendSwitch('use-angle', 'vulkan')
}

// Prevent duplicate app instances — each one would carry its own Chromium +
// Electron overhead, and could race to bind llama-server's port. If a second
// launch is attempted, it quits immediately and the first instance is focused.
const gotSingleInstanceLock = app.requestSingleInstanceLock()
if (!gotSingleInstanceLock) {
  app.quit()
}

let mainWindow: BrowserWindow | null = null
const llamaServer = new LlamaServer()
let isQuitting = false
let updateInfo: UpdateInfo | null = null

function getModelsDir(): string {
  const dir = join(app.getPath('userData'), 'models')
  fs.mkdirSync(dir, { recursive: true })
  return dir
}

function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 1100,
    height: 800,
    minWidth: 760,
    minHeight: 560,
    show: false,
    titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : 'default',
    autoHideMenuBar: true,
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      sandbox: false,
      contextIsolation: true,
      nodeIntegration: false,
    },
  })

  mainWindow.on('ready-to-show', () => {
    mainWindow!.show()
  })

  mainWindow.webContents.on('console-message', (_e, level, message, line, sourceId) => {
    console.log(`[renderer:${level}] ${message} (${sourceId}:${line})`)
  })

  mainWindow.webContents.on('render-process-gone', (_e, details) => {
    console.log('[renderer crashed]', details)
  })

  mainWindow.webContents.on('did-fail-load', (_e, errorCode, errorDescription) => {
    console.log('[did-fail-load]', errorCode, errorDescription)
  })

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url)
    return { action: 'deny' }
  })

  if (is.dev && process.env['ELECTRON_RENDERER_URL']) {
    mainWindow.loadURL(process.env['ELECTRON_RENDERER_URL'])
  } else {
    mainWindow.loadFile(join(__dirname, '../renderer/index.html'))
  }
}

// ── Filesystem IPC ────────────────────────────────────────────────────────────

ipcMain.handle('fs:modelsDir', () => getModelsDir())

ipcMain.handle('fs:listFiles', (_e, dir: string) => {
  try { return fs.readdirSync(dir) } catch { return [] }
})

ipcMain.handle('fs:unlink', (_e, p: string) => {
  try { fs.unlinkSync(p) } catch { /* noop */ }
})

ipcMain.handle('fs:rename', (_e, from: string, to: string) => {
  fs.renameSync(from, to)
})

// Chunked write for streaming downloads
const openStreams = new Map<string, fs.WriteStream>()

ipcMain.handle('fs:openWrite', (_e, path: string) => {
  const stream = fs.createWriteStream(path)
  openStreams.set(path, stream)
})

ipcMain.handle('fs:writeChunk', (_e, path: string, chunk: Uint8Array) => {
  return new Promise<void>((resolve, reject) => {
    const stream = openStreams.get(path)
    if (!stream) return reject(new Error('No open stream for ' + path))
    stream.write(Buffer.from(chunk), (err) => err ? reject(err) : resolve())
  })
})

ipcMain.handle('fs:closeWrite', (_e, path: string) => {
  return new Promise<void>((resolve) => {
    const stream = openStreams.get(path)
    if (!stream) return resolve()
    stream.end(() => { openStreams.delete(path); resolve() })
  })
})

ipcMain.handle('fs:abortWrite', (_e, path: string) => {
  const stream = openStreams.get(path)
  if (stream) { stream.destroy(); openStreams.delete(path) }
  try { fs.unlinkSync(path) } catch { /* noop */ }
})

// ── llama-server IPC ──────────────────────────────────────────────────────────

ipcMain.handle('llama:start', async (_event, modelPath: string) => {
  return llamaServer.start(modelPath)
})

ipcMain.handle('llama:stop', async () => {
  return llamaServer.stop()
})

ipcMain.handle('llama:status', async () => {
  return llamaServer.status()
})

// ── Auto-update IPC ────────────────────────────────────────────────────────────

ipcMain.handle('updater:check', () => checkForUpdatesNow())
ipcMain.handle('updater:install', () => quitAndInstall())

// ── App info IPC ────────────────────────────────────────────────────────────────

ipcMain.handle('app:getVersion', () => app.getVersion())
ipcMain.handle('app:getUpdateInfo', () => updateInfo)

// ── App lifecycle ─────────────────────────────────────────────────────────────

app.on('second-instance', () => {
  // Someone tried to launch a second copy — focus the existing window instead.
  if (mainWindow) {
    if (mainWindow.isMinimized()) mainWindow.restore()
    mainWindow.focus()
  }
})

app.whenReady().then(async () => {
  electronApp.setAppUserModelId('ai.ecoinference.desktop')

  app.on('browser-window-created', (_, window) => {
    optimizer.watchWindowShortcuts(window)
  })

  ipcMain.handle('theme:get', () => nativeTheme.shouldUseDarkColors)
  nativeTheme.on('updated', () => {
    mainWindow?.webContents.send('theme:changed', nativeTheme.shouldUseDarkColors)
  })

  // Reconcile any orphaned llama-server left running from a previous session
  // (e.g. app crashed without cleanup) before the UI assumes a clean slate.
  await llamaServer.ensureClean()

  // Compare against the version recorded on the previous launch so the UI can show
  // a one-time "you're now on vX" confirmation after an auto-update relaunches the app.
  updateInfo = checkForRecentUpdate()
  if (updateInfo.justUpdated) {
    console.log('[versionTracker] just updated:', updateInfo.previousVersion, '->', updateInfo.currentVersion)
  }

  createWindow()

  if (!is.dev && mainWindow) {
    initAutoUpdater(mainWindow)
  }

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow()
  })
})

// This is a single-window utility app, not a document-based multi-window app,
// so closing the window (the "x" button) should fully quit and free memory —
// including the llama-server child process — rather than following the macOS
// convention of staying alive in the dock with no window.
app.on('window-all-closed', () => {
  app.quit()
})

// Intercept the actual quit to guarantee llama-server is stopped before the
// process exits. Covers both paths: closing the window (window-all-closed
// above calls app.quit()) and Cmd+Q / menu quit (fires before-quit directly).
app.on('before-quit', (event) => {
  if (isQuitting) return
  isQuitting = true
  event.preventDefault()
  llamaServer.stop().finally(() => app.quit())
})

// Last-resort synchronous safety net for abrupt termination (SIGINT/SIGTERM,
// e.g. Ctrl+C in a dev terminal, or the OS killing the process directly) where
// the async before-quit path above never gets a chance to run.
process.on('exit', () => llamaServer.killSync())
process.on('SIGINT', () => process.exit(0))
process.on('SIGTERM', () => process.exit(0))
