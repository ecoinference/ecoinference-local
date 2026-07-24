import React, {
  createContext, useContext, useEffect, useReducer, useCallback, useRef,
} from 'react'
import { onAuthStateChanged, User } from 'firebase/auth'
import { firebaseAuth } from '../services/firebase'
import { fetchEnabledModelIds } from '../services/remoteConfigService'
import { getModelDownloadUrl } from '../services/b2Service'
import { ModelInfo, ModelCatalog, findModel } from '../models/ModelInfo'

// ── Types ─────────────────────────────────────────────────────────────────────

export type Screen = 'auth' | 'models' | 'chat' | 'about'

export interface Message {
  id:      string
  role:    'user' | 'assistant'
  content: string
}

interface PlatformInfo {
  platform: string
  arch:     string
}

interface State {
  user:                User | null
  authLoading:         boolean
  screen:              Screen
  models:              ModelInfo[]
  enabledModelIds:     Set<string> | null
  downloadedFiles:     Set<string>      // basenames present in modelsDir
  modelsDir:           string
  platformInfo:        PlatformInfo | null
  loadedModelId:       string | null
  loadingModelId:      string | null
  serverRunning:       boolean
  downloadingModelId:  string | null
  downloadProgress:    number
  downloadError:       string | null
  downloadErrorModelId: string | null
  messages:            Message[]
  generating:          boolean
}

type Action =
  | { type: 'SET_USER';             user: User | null }
  | { type: 'SET_SCREEN';           screen: Screen }
  | { type: 'SET_PLATFORM';         info: PlatformInfo }
  | { type: 'SET_ENABLED_IDS';      ids: Set<string> | null }
  | { type: 'SET_MODELS_DIR';       dir: string }
  | { type: 'SET_DOWNLOADED';       files: Set<string> }
  | { type: 'SET_LOADED_MODEL';     id: string | null }
  | { type: 'SET_LOADING_MODEL';    id: string | null }
  | { type: 'SET_SERVER_RUNNING';   running: boolean }
  | { type: 'DOWNLOAD_START';       modelId: string }
  | { type: 'DOWNLOAD_PROGRESS';    progress: number }
  | { type: 'DOWNLOAD_DONE' }
  | { type: 'DOWNLOAD_ERROR';       error: string; modelId: string }
  | { type: 'APPEND_MESSAGE';             message: Message }
  | { type: 'PATCH_LAST_ASSISTANT';       delta: string }
  | { type: 'SET_LAST_ASSISTANT_CONTENT'; content: string }
  | { type: 'SET_GENERATING';             value: boolean }
  | { type: 'CLEAR_MESSAGES' }

// ── Reasoning-model helpers ───────────────────────────────────────────────────

// Reasoning models (Qwen3's thinking mode, DeepSeek-R1 distills, etc.) emit their
// internal monologue inline as <think>...</think> before the real answer — useful
// for the model, not for the user. Strip it from what's displayed. Re-derived from
// the full raw buffer on every chunk (rather than parsed incrementally) so a
// <think>/</think> tag split across two stream chunks can't leave a stray fragment
// visible — recomputing from scratch is cheap at chat-message lengths.
function stripThinking(rawText: string): string {
  const withoutClosedBlocks = rawText.replace(/<think>[\s\S]*?<\/think>/g, '')
  // Whatever's left starting at <think> (if anything) is a still-open block —
  // the model hasn't finished reasoning yet, so there's nothing to show for it.
  return withoutClosedBlocks.replace(/<think>[\s\S]*$/, '').trim()
}

// ── Catalog helpers ───────────────────────────────────────────────────────────

function buildCatalog(
  enabled: Set<string> | null,
  downloaded: Set<string>,
  loadedId: string | null,
  platformInfo: PlatformInfo | null,
): ModelInfo[] {
  // Windows ARM64/Snapdragon has no llama.cpp GPU/NPU path worth shipping (see project
  // memory) — it runs GenieX-backed models instead, while every other platform runs
  // llama-cpp-backed ones. Until platform info loads, show nothing rather than guess.
  const isWinArm64 = platformInfo?.platform === 'win32' && platformInfo?.arch === 'arm64'
  const wantBackend = platformInfo === null ? null : isWinArm64 ? 'geniex' : 'llama-cpp'

  // Windows ARM64's catalog is intentionally hardcoded in this build, not managed via
  // Firebase Remote Config the way the Gemma 4 catalog is — GenieX models are inherently
  // local/experimental for this specific platform variant (see project memory) and this
  // is expected to always be a one-off rather than something rolled out centrally, so
  // skip the remote allowlist check entirely here rather than needing it kept in sync.
  const skipRemoteAllowlist = isWinArm64

  return ModelCatalog
    .filter((m) => skipRemoteAllowlist || enabled === null || enabled.has(m.id))
    .filter((m) => wantBackend === null || m.backend === wantBackend)
    .map((m) => ({
      ...m,
      // GenieX manages its own model download/caching — there's no local file for the
      // app's own download flow to track, so just treat it as always ready to load.
      downloaded: m.backend === 'geniex' ? true : downloaded.has(m.fileName),
      loaded:     m.id === loadedId,
    }))
}

// ── Reducer ───────────────────────────────────────────────────────────────────

function reducer(state: State, action: Action): State {
  switch (action.type) {
    case 'SET_USER':
      return { ...state, user: action.user, authLoading: false,
               screen: action.user ? 'models' : 'auth' }
    case 'SET_SCREEN':
      return { ...state, screen: action.screen }
    case 'SET_PLATFORM':
      return {
        ...state,
        platformInfo: action.info,
        models: buildCatalog(state.enabledModelIds, state.downloadedFiles, state.loadedModelId, action.info),
      }
    case 'SET_ENABLED_IDS':
      return {
        ...state,
        enabledModelIds: action.ids,
        models: buildCatalog(action.ids, state.downloadedFiles, state.loadedModelId, state.platformInfo),
      }
    case 'SET_MODELS_DIR':
      return { ...state, modelsDir: action.dir }
    case 'SET_DOWNLOADED':
      return {
        ...state,
        downloadedFiles: action.files,
        models: buildCatalog(state.enabledModelIds, action.files, state.loadedModelId, state.platformInfo),
      }
    case 'SET_LOADED_MODEL':
      return {
        ...state,
        loadedModelId: action.id,
        models: buildCatalog(state.enabledModelIds, state.downloadedFiles, action.id, state.platformInfo),
      }
    case 'SET_LOADING_MODEL':
      return { ...state, loadingModelId: action.id }
    case 'SET_SERVER_RUNNING':
      return { ...state, serverRunning: action.running }
    case 'DOWNLOAD_START':
      return { ...state, downloadingModelId: action.modelId, downloadProgress: 0,
               downloadError: null, downloadErrorModelId: null }
    case 'DOWNLOAD_PROGRESS':
      return { ...state, downloadProgress: action.progress }
    case 'DOWNLOAD_DONE':
      return { ...state, downloadingModelId: null, downloadProgress: 100,
               downloadError: null, downloadErrorModelId: null }
    case 'DOWNLOAD_ERROR':
      return { ...state, downloadingModelId: null, downloadError: action.error,
               downloadErrorModelId: action.modelId }
    case 'APPEND_MESSAGE':
      return { ...state, messages: [...state.messages, action.message] }
    case 'PATCH_LAST_ASSISTANT': {
      const msgs = [...state.messages]
      const last = msgs[msgs.length - 1]
      if (last?.role === 'assistant') {
        msgs[msgs.length - 1] = { ...last, content: last.content + action.delta }
      }
      return { ...state, messages: msgs }
    }
    case 'SET_LAST_ASSISTANT_CONTENT': {
      const msgs = [...state.messages]
      const last = msgs[msgs.length - 1]
      if (last?.role === 'assistant') {
        msgs[msgs.length - 1] = { ...last, content: action.content }
      }
      return { ...state, messages: msgs }
    }
    case 'SET_GENERATING':
      return { ...state, generating: action.value }
    case 'CLEAR_MESSAGES':
      return { ...state, messages: [] }
    default:
      return state
  }
}

// ── Context ───────────────────────────────────────────────────────────────────

interface AppContextValue {
  state: State
  navigateTo:    (screen: Screen) => void
  startDownload: (modelId: string) => void
  deleteModel:   (modelId: string) => void
  loadModel:     (modelId: string) => Promise<void>
  unloadModel:   () => Promise<void>
  sendMessage:   (content: string) => Promise<void>
  clearChat:     () => void
}

const AppContext = createContext<AppContextValue | null>(null)

export function useAppContext(): AppContextValue {
  const ctx = useContext(AppContext)
  if (!ctx) throw new Error('useAppContext must be used inside AppProvider')
  return ctx
}

// ── Provider ──────────────────────────────────────────────────────────────────

export function AppProvider({ children }: { children: React.ReactNode }): JSX.Element {
  const [state, dispatch] = useReducer(reducer, {
    user:               null,
    authLoading:        true,
    screen:             'auth',
    models:             [],
    enabledModelIds:    null,
    downloadedFiles:    new Set<string>(),
    modelsDir:          '',
    platformInfo:       null,
    loadedModelId:      null,
    loadingModelId:     null,
    serverRunning:      false,
    downloadingModelId: null,
    downloadProgress:   0,
    downloadError:      null,
    downloadErrorModelId: null,
    messages:           [],
    generating:         false,
  })

  const abortRef      = useRef<AbortController | null>(null)
  const modelsDirRef  = useRef('')

  // Fetch models directory from main process once
  useEffect(() => {
    window.fsOps.modelsDir().then((dir) => {
      modelsDirRef.current = dir
      dispatch({ type: 'SET_MODELS_DIR', dir })
    })
  }, [])

  // Fetch platform info once — determines which backend's models show in the catalog
  // (llama-cpp everywhere except Windows ARM64/Snapdragon, which uses GenieX instead).
  useEffect(() => {
    window.appInfo.getPlatform().then((info) => {
      dispatch({ type: 'SET_PLATFORM', info })
    })
  }, [])

  // Firebase auth listener
  useEffect(() => {
    return onAuthStateChanged(firebaseAuth(), (user) => {
      dispatch({ type: 'SET_USER', user })
    })
  }, [])

  // Refresh downloaded file list whenever user signs in or models dir changes
  const refreshDownloaded = useCallback(async () => {
    const dir = modelsDirRef.current
    if (!dir) return
    const files = await window.fsOps.listFiles(dir)
    dispatch({ type: 'SET_DOWNLOADED', files: new Set(files) })
  }, [])

  useEffect(() => {
    if (state.user && modelsDirRef.current) refreshDownloaded()
  }, [state.user, state.modelsDir, refreshDownloaded])

  // Fetch Remote Config when signed in
  useEffect(() => {
    if (!state.user) return
    fetchEnabledModelIds().then((ids) => dispatch({ type: 'SET_ENABLED_IDS', ids }))
  }, [state.user])

  const navigateTo = useCallback((screen: Screen) => {
    dispatch({ type: 'SET_SCREEN', screen })
  }, [])

  // ── Download ────────────────────────────────────────────────────────────────

  const startDownload = useCallback(async (modelId: string) => {
    const info = findModel(modelId)
    if (!info) return
    const dir = modelsDirRef.current
    if (!dir) return

    dispatch({ type: 'DOWNLOAD_START', modelId })
    const destPath = `${dir}/${info.fileName}`
    const tmpPath  = `${destPath}.tmp`

    try {
      const url = await getModelDownloadUrl(modelId, info.fileName)
      const res = await fetch(url)
      if (!res.ok || !res.body) throw new Error(`HTTP ${res.status}`)

      const total = Number(res.headers.get('content-length') ?? 0)
      let received = 0

      await window.fsOps.openWrite(tmpPath)
      const reader = res.body.getReader()

      try {
        while (true) {
          const { done, value } = await reader.read()
          if (done) break
          await window.fsOps.writeChunk(tmpPath, value)
          received += value.byteLength
          if (total > 0) {
            dispatch({ type: 'DOWNLOAD_PROGRESS', progress: Math.round((received / total) * 100) })
          }
        }
        await window.fsOps.closeWrite(tmpPath)
      } catch (e) {
        await window.fsOps.abortWrite(tmpPath)
        throw e
      }

      await window.fsOps.rename(tmpPath, destPath)
      dispatch({ type: 'DOWNLOAD_DONE' })
      await refreshDownloaded()
    } catch (e) {
      dispatch({ type: 'DOWNLOAD_ERROR', error: String(e), modelId })
    }
  }, [refreshDownloaded])

  const deleteModel = useCallback(async (modelId: string) => {
    const info = findModel(modelId)
    if (!info || info.backend === 'geniex') return // GenieX manages its own cache, nothing local to delete
    await window.fsOps.unlink(`${modelsDirRef.current}/${info.fileName}`)
    await refreshDownloaded()
  }, [refreshDownloaded])

  // ── Model load / unload ─────────────────────────────────────────────────────

  const loadModel = useCallback(async (modelId: string) => {
    if (state.loadingModelId) return
    const info = findModel(modelId)
    if (!info) return
    dispatch({ type: 'SET_LOADING_MODEL', id: modelId })
    try {
      // llama-cpp: fileName is a real file downloaded to modelsDir. geniex: fileName is
      // already the GenieX model ID (e.g. "qualcomm/Qwen3-8B") — pass it straight through.
      const modelPath = info.backend === 'geniex'
        ? info.fileName
        : `${modelsDirRef.current}/${info.fileName}`
      const result = await window.llama.start(modelPath)
      if (result.ok) {
        dispatch({ type: 'SET_LOADED_MODEL', id: modelId })
        dispatch({ type: 'SET_SERVER_RUNNING', running: true })
      } else {
        throw new Error(result.error ?? 'Failed to start inference server')
      }
    } finally {
      dispatch({ type: 'SET_LOADING_MODEL', id: null })
    }
  }, [state.loadingModelId])

  const unloadModel = useCallback(async () => {
    await window.llama.stop()
    dispatch({ type: 'SET_LOADED_MODEL', id: null })
    dispatch({ type: 'SET_SERVER_RUNNING', running: false })
  }, [])

  // ── Chat ────────────────────────────────────────────────────────────────────

  const sendMessage = useCallback(async (content: string) => {
    if (state.generating) return

    const userMsg: Message = { id: crypto.randomUUID(), role: 'user', content }
    dispatch({ type: 'APPEND_MESSAGE', message: userMsg })
    dispatch({ type: 'SET_GENERATING', value: true })
    dispatch({ type: 'APPEND_MESSAGE', message: { id: crypto.randomUUID(), role: 'assistant', content: '' } })

    abortRef.current = new AbortController()

    try {
      // Port differs per backend (llama-server: 8765, GenieX: 18181) — ask the main
      // process what's actually running rather than assuming. The "model" field is
      // ignored by llama-server but required by GenieX, so always send it.
      const status = await window.llama.status() as { port: number }
      const loadedInfo = state.loadedModelId ? findModel(state.loadedModelId) : undefined
      const chatUrl = `http://127.0.0.1:${status.port}/v1/chat/completions`

      const history = [...state.messages, userMsg].map(({ role, content }) => ({ role, content }))
      const res = await fetch(chatUrl, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        signal:  abortRef.current.signal,
        body:    JSON.stringify({ model: loadedInfo?.fileName, messages: history, stream: true }),
      })

      if (!res.ok || !res.body) throw new Error(`HTTP ${res.status}`)

      const reader  = res.body.getReader()
      const decoder = new TextDecoder()
      let buf = ''
      let rawContent = '' // full text including any <think> blocks — displayed content is derived from this

      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        buf += decoder.decode(value, { stream: true })
        const lines = buf.split('\n')
        buf = lines.pop() ?? ''
        for (const line of lines) {
          // llama-server emits "data: {...}" (with a space); GenieX emits "data:{...}"
          // (no space) — accept either rather than requiring an exact "data: " match.
          if (!line.startsWith('data:')) continue
          const data = line.slice(5).trim()
          if (data === '[DONE]') continue
          try {
            const delta = JSON.parse(data)?.choices?.[0]?.delta?.content
            if (delta) {
              rawContent += delta
              dispatch({ type: 'SET_LAST_ASSISTANT_CONTENT', content: stripThinking(rawContent) })
            }
          } catch { /* malformed chunk */ }
        }
      }
    } catch (e: unknown) {
      if (e instanceof Error && e.name !== 'AbortError') {
        dispatch({ type: 'PATCH_LAST_ASSISTANT', delta: `\n\n[Error: ${e.message}]` })
      }
    } finally {
      dispatch({ type: 'SET_GENERATING', value: false })
    }
  }, [state.generating, state.messages, state.loadedModelId])

  const clearChat = useCallback(() => dispatch({ type: 'CLEAR_MESSAGES' }), [])

  return (
    <AppContext.Provider value={{
      state, navigateTo, startDownload, deleteModel,
      loadModel, unloadModel, sendMessage, clearChat,
    }}>
      {children}
    </AppContext.Provider>
  )
}
