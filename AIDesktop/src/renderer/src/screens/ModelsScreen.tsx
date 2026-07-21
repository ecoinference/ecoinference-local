import React, { useEffect, useState } from 'react'
import { useAppContext } from '../context/AppContext'
import { ModelInfo } from '../models/ModelInfo'

function formatSize(mb: number): string {
  return mb >= 1000 ? `${(mb / 1000).toFixed(1)} GB` : `${mb} MB`
}

// Loading a model has no incremental progress to report (llama-server doesn't expose one),
// so this just proves to the user it's actively working rather than frozen — the "hang"
// complaint that motivated this was really "no feedback during a legitimately slow step."
function LoadingStatus(): JSX.Element {
  const [elapsedSec, setElapsedSec] = useState(0)

  useEffect(() => {
    const start = Date.now()
    const id = setInterval(() => setElapsedSec(Math.floor((Date.now() - start) / 1000)), 1000)
    return () => clearInterval(id)
  }, [])

  return (
    <p style={s.loadingStatus}>
      Loading model into memory… {elapsedSec}s
      {elapsedSec >= 15 && ' — large models can take up to a minute, especially on first load'}
    </p>
  )
}

function ModelCard({ model }: { model: ModelInfo }): JSX.Element {
  const { state, startDownload, deleteModel, loadModel, unloadModel, navigateTo } = useAppContext()
  const isDownloading      = state.downloadingModelId === model.id
  const isOtherDownloading = !!state.downloadingModelId && !isDownloading
  const isLoading          = state.loadingModelId === model.id
  const isOtherLoading     = !!state.loadingModelId && !isLoading

  async function handleLoad(): Promise<void> {
    try {
      await loadModel(model.id)
      navigateTo('chat')
    } catch (e) {
      alert(String(e))
    }
  }

  return (
    <div style={s.card}>
      <div style={s.cardHeader}>
        <div>
          <div style={s.modelName}>{model.displayName}</div>
          <div style={s.modelMeta}>
            {formatSize(model.fileSizeMb)}
            {model.supportsVision       && <span style={s.badge}>Vision</span>}
            {model.maxContextTokens >= 16384 && <span style={s.badge}>16k ctx</span>}
          </div>
        </div>
        <div style={{ ...s.statusDot, background: model.loaded ? 'var(--accent)' : 'var(--border)' }} />
      </div>

      {isDownloading && (
        <div style={s.progressBar}>
          <div style={{ ...s.progressFill, width: `${state.downloadProgress}%` }} />
        </div>
      )}

      <div style={s.actions}>
        {!model.downloaded && !isDownloading && (
          <button style={s.btnPrimary} onClick={() => startDownload(model.id)} disabled={isOtherDownloading}>
            Download
          </button>
        )}
        {isDownloading && <span style={s.progressLabel}>{state.downloadProgress}%</span>}
        {model.downloaded && !model.loaded && (
          <>
            <button style={s.btnPrimary} onClick={handleLoad} disabled={isLoading || isOtherLoading}>
              {isLoading ? 'Loading…' : 'Load'}
            </button>
            {model.backend !== 'geniex' && (
              <button style={s.btnDanger} onClick={() => deleteModel(model.id)} disabled={isLoading || isOtherLoading}>
                Delete
              </button>
            )}
          </>
        )}
        {model.loaded && (
          <>
            <button style={s.btnAccent}     onClick={() => navigateTo('chat')}>Chat</button>
            <button style={s.btnSecondary}  onClick={unloadModel}>Unload</button>
          </>
        )}
      </div>

      {isLoading && <LoadingStatus />}

      {state.downloadErrorModelId === model.id && (
        <p style={s.error}>{state.downloadError}</p>
      )}
    </div>
  )
}

export default function ModelsScreen(): JSX.Element {
  const { state } = useAppContext()
  return (
    <div style={s.wrap}>
      <h1 style={s.title}>Models</h1>
      <p style={s.sub}>
        Download a model to run it locally. Files are stored on your machine — no internet required after download.
        All requests are local and private on your computer.
      </p>
      <div style={s.grid}>
        {state.models.map((m) => <ModelCard key={m.id} model={m} />)}
      </div>
    </div>
  )
}

const s: Record<string, React.CSSProperties> = {
  wrap:         { padding: '32px 28px', overflowY: 'auto', height: '100%' },
  title:        { margin: '0 0 6px', fontSize: 22, fontWeight: 700 },
  sub:          { margin: '0 0 24px', color: 'var(--text-dim)', fontSize: 13 },
  grid:         { display: 'flex', flexDirection: 'column', gap: 14 },
  card:         { background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: 'var(--radius)', padding: '18px 20px', display: 'flex', flexDirection: 'column', gap: 12 },
  cardHeader:   { display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' },
  modelName:    { fontSize: 16, fontWeight: 600 },
  modelMeta:    { fontSize: 12, color: 'var(--text-dim)', display: 'flex', gap: 6, marginTop: 3 },
  badge:        { background: 'var(--surface2)', border: '1px solid var(--border)', borderRadius: 4, padding: '1px 5px', fontSize: 11 },
  statusDot:    { width: 10, height: 10, borderRadius: '50%', marginTop: 4 },
  progressBar:  { height: 4, background: 'var(--border)', borderRadius: 2 },
  progressFill: { height: '100%', background: 'var(--accent)', borderRadius: 2, transition: 'width 0.2s' },
  progressLabel:{ fontSize: 13, color: 'var(--text-dim)' },
  actions:      { display: 'flex', gap: 8 },
  btnPrimary:   { padding: '7px 16px', borderRadius: 7, border: 'none', background: 'var(--accent)', color: 'var(--on-accent)', fontWeight: 600, fontSize: 13 },
  btnAccent:    { padding: '7px 16px', borderRadius: 7, border: 'none', background: 'var(--accent)', color: 'var(--on-accent)', fontWeight: 600, fontSize: 13 },
  btnSecondary: { padding: '7px 16px', borderRadius: 7, border: '1px solid var(--border)', background: 'var(--surface2)', color: 'var(--text)', fontWeight: 600, fontSize: 13 },
  btnDanger:    { padding: '7px 16px', borderRadius: 7, border: 'none', background: 'transparent', color: 'var(--danger)', fontWeight: 600, fontSize: 13 },
  error:        { color: 'var(--danger)', fontSize: 12, margin: 0 },
  loadingStatus:{ color: 'var(--text-dim)', fontSize: 12, margin: 0 },
}
