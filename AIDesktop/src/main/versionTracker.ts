import { app } from 'electron'
import { join } from 'path'
import * as fs from 'fs'

export interface UpdateInfo {
  justUpdated:      boolean
  previousVersion?: string
  currentVersion:   string
}

// Compares the running version against whatever was recorded on the previous launch,
// so the UI can show a one-time "you're now on vX" confirmation after an auto-update
// relaunches the app. Not first-launch-safe by design — a missing/unreadable record
// means "nothing to compare against", not "an update happened".
export function checkForRecentUpdate(): UpdateInfo {
  const versionFile = join(app.getPath('userData'), 'last-version.json')
  const currentVersion = app.getVersion()
  let previousVersion: string | undefined

  try {
    const data = JSON.parse(fs.readFileSync(versionFile, 'utf-8')) as { version?: string }
    previousVersion = data.version
  } catch {
    // No file yet (first-ever launch) or unreadable — treat as nothing to compare.
  }

  try {
    fs.writeFileSync(versionFile, JSON.stringify({ version: currentVersion }))
  } catch (e) {
    console.log('[versionTracker] failed to write last-version.json:', e)
  }

  return {
    justUpdated: previousVersion !== undefined && previousVersion !== currentVersion,
    previousVersion,
    currentVersion,
  }
}
