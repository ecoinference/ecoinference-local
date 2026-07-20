import { autoUpdater } from 'electron-updater'
import { BrowserWindow } from 'electron'

// autoUpdater checks the "generic" feed at build.publish.url (releases.ecoinference.ai)
// for a latest.yml / latest-mac.yml manifest, compares versions, and — once code
// signing is set up — downloads + verifies + applies updates. Until then, this still
// gives us update *detection*; installing an unsigned update may be blocked by the OS
// (especially macOS Gatekeeper), which is expected and fine for now.

let mainWindowRef: BrowserWindow | null = null

function send(channel: string, ...args: unknown[]): void {
  mainWindowRef?.webContents.send(channel, ...args)
}

export function initAutoUpdater(mainWindow: BrowserWindow): void {
  mainWindowRef = mainWindow

  autoUpdater.logger = {
    info:  (...a: unknown[]) => console.log('[autoUpdater]', ...a),
    warn:  (...a: unknown[]) => console.log('[autoUpdater:warn]', ...a),
    error: (...a: unknown[]) => console.log('[autoUpdater:error]', ...a),
    debug: (...a: unknown[]) => console.log('[autoUpdater:debug]', ...a),
  }

  autoUpdater.on('checking-for-update', () => send('updater:status', { state: 'checking' }))
  autoUpdater.on('update-available', (info) =>
    send('updater:status', { state: 'available', version: info.version }))
  autoUpdater.on('update-not-available', () => send('updater:status', { state: 'not-available' }))
  autoUpdater.on('download-progress', (progress) =>
    send('updater:status', { state: 'downloading', percent: Math.round(progress.percent) }))
  autoUpdater.on('update-downloaded', (info) =>
    send('updater:status', { state: 'downloaded', version: info.version }))
  autoUpdater.on('error', (err) =>
    send('updater:status', { state: 'error', message: err.message }))

  // Check once shortly after launch, then every 4 hours. Never blocks startup.
  setTimeout(() => autoUpdater.checkForUpdates().catch((e) => console.log('[autoUpdater] check failed:', e)), 10_000)
  setInterval(() => autoUpdater.checkForUpdates().catch((e) => console.log('[autoUpdater] check failed:', e)), 4 * 60 * 60 * 1000)
}

export function checkForUpdatesNow(): void {
  autoUpdater.checkForUpdates().catch((e) => console.log('[autoUpdater] manual check failed:', e))
}

export function quitAndInstall(): void {
  autoUpdater.quitAndInstall()
}
