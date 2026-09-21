import React, { useEffect, useState } from 'react'

export default function AboutScreen(): JSX.Element {
  const [version, setVersion] = useState<string | null>(null)

  useEffect(() => {
    window.appInfo.getVersion().then(setVersion)
  }, [])

  return (
    <div style={s.wrap}>
      <div style={s.logo}>🌿</div>
      <h1 style={s.title}>EcoInference&trade;</h1>
      <p style={s.version}>{version ? `Version ${version}` : 'Loading…'}</p>
      <p style={s.tagline}>Local AI, offline and private.</p>
      <div style={s.meta}>
        <p style={s.metaLine}>Local inference powered by llama.cpp</p>
        <p style={s.metaLine}>© {new Date().getFullYear()} EcoInference</p>
      </div>
    </div>
  )
}

const s: Record<string, React.CSSProperties> = {
  wrap: {
    display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
    height: '100%', padding: '32px 28px', textAlign: 'center',
  },
  logo:    { fontSize: 48, marginBottom: 12 },
  title:   { margin: '0 0 4px', fontSize: 22, fontWeight: 700 },
  version: { margin: '0 0 16px', fontSize: 14, color: 'var(--text-dim)' },
  tagline: { margin: '0 0 32px', fontSize: 13, color: 'var(--text-dim)' },
  meta:    { borderTop: '1px solid var(--border)', paddingTop: 16, width: '100%', maxWidth: 280 },
  metaLine:{ margin: '4px 0', fontSize: 12, color: 'var(--text-dim)' },
}
