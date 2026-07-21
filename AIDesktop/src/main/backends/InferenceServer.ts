import { ChildProcess, spawn, execFile } from 'child_process'
import { promisify } from 'util'
import { isAbsolute } from 'path'
import * as fs from 'fs'

const execFileAsync = promisify(execFile)

export interface InferenceStatus {
  running: boolean
  port: number
  modelPath: string | null
  pid: number | null
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

/**
 * Shared subprocess+REST lifecycle management for a local inference server —
 * spawn a binary that exposes an OpenAI-compatible REST API on localhost,
 * poll it over HTTP, tear it down cleanly. Every platform's inference backend
 * (llama.cpp today, ONNX Runtime+QNN on Windows ARM64 later) speaks this same
 * shape, so this base class covers everything except which binary to run and
 * what arguments to launch it with — subclasses only implement those two.
 */
export abstract class InferenceServer {
  protected proc: ChildProcess | null = null
  protected _modelPath: string | null = null
  readonly port: number

  constructor(port: number) {
    this.port = port
  }

  protected abstract get binaryPath(): string
  protected abstract buildArgs(modelPath: string): string[]

  /** Path to poll for readiness. Override when a backend has no /health (e.g. GenieX only exposes /v1/models). */
  protected healthPath(): string {
    return '/health'
  }

  /**
   * Validate the modelPath argument to start() before spawning. Default assumes it's a
   * real file on disk (llama.cpp's case). Override for backends where modelPath is an
   * opaque identifier instead (e.g. GenieX resolves model IDs like "qualcomm/Qwen3-8B"
   * itself, server-side — there's no local file to check).
   */
  protected validateModelPath(modelPath: string): string | null {
    if (!fs.existsSync(modelPath)) {
      return `Model file not found: ${modelPath}`
    }
    return null
  }

  private async checkHealth(): Promise<boolean> {
    try {
      const res = await fetch(`http://127.0.0.1:${this.port}${this.healthPath()}`)
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
   * Kills whatever is listening on our port that we don't own — e.g. a server
   * left running from a previous session that crashed without cleanup. Call once at
   * app startup, before any start() call, so a stale orphan doesn't cause a silent
   * port-bind failure later.
   */
  async ensureClean(): Promise<void> {
    if (this.proc) return // we already own a live process, nothing to reconcile
    const alive = await this.checkHealth()
    if (!alive) return

    console.log('[inferenceServer] found an orphaned server on port', this.port, '— killing it')

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
      console.log('[inferenceServer] failed to kill orphaned process:', e)
    }

    // Wait for the port to actually free up before returning.
    const deadline = Date.now() + 5_000
    while (Date.now() < deadline) {
      if (!(await this.checkHealth())) return
      await sleep(200)
    }
    console.log('[inferenceServer] orphaned server did not die within 5s — start() may fail to bind')
  }

  async start(modelPath: string): Promise<{ ok: boolean; error?: string }> {
    if (this.proc) {
      await this.stop()
    }
    const modelPathError = this.validateModelPath(modelPath)
    if (modelPathError) {
      return { ok: false, error: modelPathError }
    }
    // Only pre-check when we have a real absolute path (dev's bundled bin/ or the
    // packaged app's resources/bin/). The dev-mode PATH fallback is a bare command
    // name that fs.existsSync() can't resolve — that case relies on spawn()'s
    // 'error' event (ENOENT) below instead, which is handled just as fast.
    if (isAbsolute(this.binaryPath) && !fs.existsSync(this.binaryPath)) {
      return { ok: false, error: `Inference server binary not found at ${this.binaryPath}. The app may be missing a required component — try reinstalling.` }
    }

    const args = this.buildArgs(modelPath)

    console.log('[inferenceServer] spawning:', this.binaryPath, args.join(' '))

    try {
      this.proc = spawn(this.binaryPath, args, { stdio: ['ignore', 'pipe', 'pipe'] })
    } catch (e) {
      console.log('[inferenceServer] spawn threw:', e)
      return { ok: false, error: String(e) }
    }

    this.proc.stdout?.on('data', (d: Buffer) => console.log('[inference-server stdout]', d.toString()))
    this.proc.stderr?.on('data', (d: Buffer) => console.log('[inference-server stderr]', d.toString()))

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
        console.log('[inferenceServer] process error event:', err.message)
        this.proc = null
        this._modelPath = null
        finish({ ok: false, error: `Failed to start inference server: ${err.message}` })
      })

      this.proc!.on('exit', (code, signal) => {
        console.log('[inferenceServer] exited, code:', code, 'signal:', signal)
        this.proc = null
        this._modelPath = null
        finish({ ok: false, error: `Inference server exited with code ${code}${signal ? ` (signal ${signal})` : ''}` })
      })

      this._modelPath = modelPath
      this.waitForHealth(60_000).then((healthy) => {
        finish(healthy ? { ok: true } : { ok: false, error: 'Inference server startup timed out' })
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

  status(): InferenceStatus {
    return {
      running: this.proc !== null,
      port: this.port,
      modelPath: this._modelPath,
      pid: this.proc?.pid ?? null,
    }
  }
}
