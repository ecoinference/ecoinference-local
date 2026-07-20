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

interface State {
  user:                User | null
  authLoading:         boolean
  screen:              Screen
  models:              ModelInfo[]
  enabledModelIds:     Set<string> | null
  downloadedFiles:     Set<string>      // basenames present in modelsDir
  modelsDir:           string
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
  | { type: 'APPEND_MESSAGE';       message: Message }
  | { type: 'PATCH_LAST_ASSISTANT'; delta: string }
  | { type: 'SET_GENERATING';       value: boolean }
  | { type: 'CLEAR_MESSAGES' }

// ── Catalog helpers ───────────────────────────────────────────────────────────

function buildCatalog(
  enabled: Set<string> | null,
  downloaded: Set<string>,
  loadedId: string | null,
): ModelInfo[] {
  return ModelCatalog
    .filter((m) => enabled === null || enabled.has(m.id))
    .map((m) => ({
      ...m,
      downloaded: downloaded.has(m.fileName),
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
    case 'SET_ENABLED_IDS':
      return {
        ...state,
        enabledModelIds: action.ids,
        models: buildCatalog(action.ids, state.downloadedFiles, state.loadedModelId),
      }
    case 'SET_MODELS_DIR':
      return { ...state, modelsDir: action.dir }
    case 'SET_DOWNLOADED':
      return {
        ...state,
        downloadedFiles: action.files,
        models: buildCatalog(state.enabledModelIds, action.files, state.loadedModelId),
      }
    case 'SET_LOADED_MODEL':
      return {
        ...state,
        loadedModelId: action.id,
        models: buildCatalog(state.enabledModelIds, state.downloadedFiles, action.id),
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

const LLAMA_URL = 'http://127.0.0.1:8765/v1/chat/completions'

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
    if (!info) return
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
      const modelPath = `${modelsDirRef.current}/${info.fileName}`
      const result = await window.llama.start(modelPath)
      if (result.ok) {
        dispatch({ type: 'SET_LOADED_MODEL', id: modelId })
        dispatch({ type: 'SET_SERVER_RUNNING', running: true })
      } else {
        throw new Error(result.error ?? 'Failed to start llama-server')
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
      const history = [...state.messages, userMsg].map(({ role, content }) => ({ role, content }))
      const res = await fetch(LLAMA_URL, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        signal:  abortRef.current.signal,
        body:    JSON.stringify({ messages: history, stream: true }),
      })

      if (!res.ok || !res.body) throw new Error(`HTTP ${res.status}`)

      const reader  = res.body.getReader()
      const decoder = new TextDecoder()
      let buf = ''

      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        buf += decoder.decode(value, { stream: true })
        const lines = buf.split('\n')
        buf = lines.pop() ?? ''
        for (const line of lines) {
          if (!line.startsWith('data: ')) continue
          const data = line.slice(6).trim()
          if (data === '[DONE]') continue
          try {
            const delta = JSON.parse(data)?.choices?.[0]?.delta?.content
            if (delta) dispatch({ type: 'PATCH_LAST_ASSISTANT', delta })
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
  }, [state.generating, state.messages])

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
