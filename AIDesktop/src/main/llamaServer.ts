import { ChildProcess, spawn, execFile } from 'child_process'
import { promisify } from 'util'
import { join, isAbsolute } from 'path'
import { app } from 'electron'
import { is } from '@electron-toolkit/utils'
import * as fs from 'fs'

const execFileAsync = promisify(execFile)

export interface LlamaStatus {
  running: boolean
  port: number
  modelPath: string | null
  pid: number | null
}

const DEFAULT_PORT = 8765

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

export class LlamaServer {
  private proc: ChildProcess | null = null
  private _modelPath: string | null = null
  readonly port = DEFAULT_PORT

  private get binaryPath(): string {
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

  private async checkHealth(): Promise<boolean> {
    try {
      const res = await fetch(`http://127.0.0.1:${this.port}/health`)
      return res.ok
    } catch {
      return false
    }
  }

  private async waitForHealth(timeoutMs: number): Promise<boolean> {
    const deadline = Date.now() + timeoutMs
    while (Date.now() < deadline) {
      if (!this.proc) return false // process died while we were waiting
      if (await this.checkHealth()) return true
      await sleep(300)
    }
    return false
  }

  /**
   * Kills whatever is listening on our port that we don't own — e.g. a llama-server
   * left running from a previous session that crashed without cleanup. Call once at
   * app startup, before any start() call, so a stale orphan doesn't cause a silent
   * port-bind failure later.
   */
  async ensureClean(): Promise<void> {
    if (this.proc) return // we already own a live process, nothing to reconcile
    const alive = await this.checkHealth()
    if (!alive) return

    console.log('[llamaServer] found an orphaned server on port', this.port, '— killing it')

    try {
      if (process.platform === 'win32') {
        const { stdout } = await execFileAsync('netstat', ['-ano'])
        const line = stdout.split('\n').find((l) => l.includes(`:${this.port}`) && l.includes('LISTENING'))
        const pid = line?.trim().split(/\s+/).pop()
        if (pid) await execFileAsync('taskkill', ['/PID', pid, '/F'])
      } else {
        const { stdout } = await execFileAsync('lsof', ['-ti', `tcp:${this.port}`])
        const pids = stdout.split('\n').map((s) => s.trim()).filter(Boolean)
        for (const pid of pids) process.kill(Number(pid), 'SIGKILL')
      }
    } catch (e) {
      console.log('[llamaServer] failed to kill orphaned process:', e)
    }

    // Wait for the port to actually free up before returning.
    const deadline = Date.now() + 5_000
    while (Date.now() < deadline) {
      if (!(await this.checkHealth())) return
      await sleep(200)
    }
    console.log('[llamaServer] orphaned server did not die within 5s — start() may fail to bind')
  }

  async start(modelPath: string): Promise<{ ok: boolean; error?: string }> {
    if (this.proc) {
      await this.stop()
    }
    if (!fs.existsSync(modelPath)) {
      return { ok: false, error: `Model file not found: ${modelPath}` }
    }
    // Only pre-check when we have a real absolute path (dev's bundled bin/ or the
    // packaged app's resources/bin/). The dev-mode PATH fallback is a bare command
    // name ("llama-server") that fs.existsSync() can't resolve — that case relies on
    // spawn()'s 'error' event (ENOENT) below instead, which is handled just as fast.
    if (isAbsolute(this.binaryPath) && !fs.existsSync(this.binaryPath)) {
      return { ok: false, error: `llama-server binary not found at ${this.binaryPath}. The app may be missing a required component — try reinstalling.` }
    }

    const args = [
      '--model', modelPath,
      '--port', String(this.port),
      '--host', '127.0.0.1',
      '--ctx-size', '8192',
      '--n-gpu-layers', '99',   // offload all layers to GPU when available
    ]

    console.log('[llamaServer] spawning:', this.binaryPath, args.join(' '))

    try {
      this.proc = spawn(this.binaryPath, args, { stdio: ['ignore', 'pipe', 'pipe'] })
    } catch (e) {
      console.log('[llamaServer] spawn threw:', e)
      return { ok: false, error: String(e) }
    }

    this.proc.stdout?.on('data', (d: Buffer) => console.log('[llama-server stdout]', d.toString()))
    this.proc.stderr?.on('data', (d: Buffer) => console.log('[llama-server stderr]', d.toString()))

    // 'error' fires immediately for spawn-level failures (e.g. ENOENT) and — critically —
    // 'exit' does NOT reliably follow it, since no real process was ever created. Racing
    // these three outcomes (instead of only polling /health with a fixed 60s timeout)
    // means a spawn failure surfaces instantly instead of after a silent full-minute wait.
    const outcome = await new Promise<{ ok: boolean; error?: string }>((resolve) => {
      let settled = false
      const finish = (result: { ok: boolean; error?: string }): void => {
        if (settled) return
        settled = true
        resolve(result)
      }

      this.proc!.on('error', (err) => {
        console.log('[llamaServer] process error event:', err.message)
        this.proc = null
        this._modelPath = null
        finish({ ok: false, error: `Failed to start llama-server: ${err.message}` })
      })

      this.proc!.on('exit', (code, signal) => {
        console.log('[llamaServer] exited, code:', code, 'signal:', signal)
        this.proc = null
        this._modelPath = null
        finish({ ok: false, error: `llama-server exited with code ${code}${signal ? ` (signal ${signal})` : ''}` })
      })

      this._modelPath = modelPath
      this.waitForHealth(60_000).then((healthy) => {
        finish(healthy ? { ok: true } : { ok: false, error: 'llama-server startup timed out' })
      })
    })

    return outcome
  }

  async stop(): Promise<void> {
    if (!this.proc) return
    const p = this.proc
    this.proc = null
    this._modelPath = null
    return new Promise((resolve) => {
      p.on('exit', () => resolve())
      p.kill('SIGTERM')
      setTimeout(() => { p.kill('SIGKILL'); resolve() }, 3000)
    })
  }

  /**
   * Best-effort synchronous kill for use in process 'exit' handlers, where async
   * work is not possible. Fires SIGKILL and does not wait for confirmation — this
   * is a last-resort safety net for abrupt termination (SIGINT/SIGTERM/process.exit),
   * not the normal shutdown path (use stop() for that).
   */
  killSync(): void {
    if (!this.proc) return
    try {
      this.proc.kill('SIGKILL')
    } catch {
      // process may already be gone
    }
    this.proc = null
    this._modelPath = null
  }

  status(): LlamaStatus {
    return {
      running: this.proc !== null,
      port: this.port,
      modelPath: this._modelPath,
      pid: this.proc?.pid ?? null,
    }
  }
}
