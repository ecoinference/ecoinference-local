import React, { useEffect, useState } from 'react'
import { signOut } from 'firebase/auth'
import { firebaseAuth } from '../services/firebase'
import { useAppContext } from '../context/AppContext'
import { Screen } from '../context/AppContext'

interface UpdaterStatus {
  state:    'checking' | 'available' | 'not-available' | 'downloading' | 'downloaded' | 'error'
  version?: string
  percent?: number
  message?: string
}

function UpdateBanner(): JSX.Element | null {
  const [status, setStatus] = useState<UpdaterStatus | null>(null)

  useEffect(() => {
    window.updater?.onStatus(setStatus)
  }, [])

  if (!status || status.state === 'checking' || status.state === 'not-available' || status.state === 'error') {
    return null
  }

  if (status.state === 'downloaded') {
    return (
      <button style={styles.updateBanner} onClick={() => window.updater.install()}>
        Restart to update {status.version ? `(v${status.version})` : ''}
      </button>
    )
  }

  return (
    <div style={styles.updateBanner}>
      {status.state === 'available'
        ? `Update available${status.version ? ` (v${status.version})` : ''}…`
        : `Downloading update… ${status.percent ?? 0}%`}
    </div>
  )
}

interface UpdateInfo {
  justUpdated:      boolean
  previousVersion?: string
  currentVersion:   string
}

function JustUpdatedBanner(): JSX.Element | null {
  const [info, setInfo]           = useState<UpdateInfo | null>(null)
  const [dismissed, setDismissed] = useState(false)

  useEffect(() => {
    window.appInfo?.getUpdateInfo().then(setInfo)
  }, [])

  if (!info?.justUpdated || dismissed) return null

  return (
    <div style={styles.justUpdatedBanner}>
      <span>✓ Updated to v{info.currentVersion}</span>
      <button style={styles.dismissBtn} onClick={() => setDismissed(true)} title="Dismiss">×</button>
    </div>
  )
}

interface NavItem {
  id:    Screen
  label: string
  icon:  string
}

const NAV: NavItem[] = [
  { id: 'models', label: 'Models', icon: '⬡' },
  { id: 'chat',   label: 'Chat',   icon: '◎' },
  { id: 'about',  label: 'About',  icon: 'ⓘ' },
]

export default function Sidebar(): JSX.Element {
  const { state, navigateTo } = useAppContext()

  const chatBadge = state.loadedModelId !== null

  return (
    <div style={styles.sidebar}>
      <div style={styles.logo}>
        <span style={styles.logoLeaf}>🌿</span>
        <span style={styles.logoText}>EcoInference&trade;</span>
      </div>

      <nav style={styles.nav}>
        {NAV.map((item) => {
          const active = state.screen === item.id
          return (
            <button
              key={item.id}
              style={{ ...styles.navItem, ...(active ? styles.navActive : {}) }}
              onClick={() => navigateTo(item.id)}
            >
              <span style={styles.navIcon}>{item.icon}</span>
              <span>{item.label}</span>
              {item.id === 'chat' && chatBadge && <span style={styles.dot} />}
            </button>
          )
        })}
      </nav>

      <div style={styles.bottom}>
        <JustUpdatedBanner />
        <UpdateBanner />
        {state.user && (
          <div style={styles.userRow}>
            <span style={styles.userEmail}>{state.user.email}</span>
            <button
              style={styles.signOutBtn}
              onClick={() => signOut(firebaseAuth())}
              title="Sign out"
            >
              ⏻
            </button>
          </div>
        )}
      </div>
    </div>
  )
}

const styles: Record<string, React.CSSProperties> = {
  sidebar: {
    width: 200, flexShrink: 0, display: 'flex', flexDirection: 'column',
    background: 'var(--surface)', borderRight: '1px solid var(--border)',
    padding: '16px 0',
    // macOS traffic lights sit at ~52px from top; add extra top inset on macOS
    paddingTop: window.electron.process.platform === 'darwin' ? 44 : 16,
  },
  logo: {
    display: 'flex', alignItems: 'center', gap: 8,
    padding: '0 16px 16px', borderBottom: '1px solid var(--border)',
  },
  logoLeaf: { fontSize: 20 },
  logoText: { fontSize: 15, fontWeight: 700, color: 'var(--accent)' },

  nav: { flex: 1, display: 'flex', flexDirection: 'column', gap: 2, padding: '12px 8px 0' },
  navItem: {
    display: 'flex', alignItems: 'center', gap: 10,
    padding: '9px 10px', borderRadius: 8, border: 'none',
    background: 'none', color: 'var(--text-dim)', fontSize: 14,
    fontWeight: 500, textAlign: 'left', position: 'relative',
  },
  navActive: {
    background: 'var(--surface2)', color: 'var(--text)',
  },
  navIcon: { fontSize: 16 },
  dot: {
    position: 'absolute', right: 10, top: '50%', transform: 'translateY(-50%)',
    width: 7, height: 7, borderRadius: '50%', background: 'var(--accent)',
  },

  bottom: { padding: '12px 10px 0', borderTop: '1px solid var(--border)', marginTop: 'auto' },
  userRow: { display: 'flex', alignItems: 'center', gap: 6 },
  userEmail: {
    flex: 1, fontSize: 11, color: 'var(--text-dim)',
    overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
  },
  signOutBtn: {
    background: 'none', border: 'none', color: 'var(--text-dim)',
    fontSize: 16, padding: '2px 4px',
  },
  updateBanner: {
    display: 'block', width: '100%', marginBottom: 8,
    padding: '7px 8px', borderRadius: 6, border: '1px solid var(--accent)',
    background: 'transparent', color: 'var(--accent)', fontSize: 11,
    fontWeight: 600, textAlign: 'left', lineHeight: 1.3, cursor: 'default',
  },
  justUpdatedBanner: {
    display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 6,
    marginBottom: 8, padding: '7px 8px', borderRadius: 6,
    background: 'var(--accent)', color: 'var(--on-accent)', fontSize: 11, fontWeight: 600,
  },
  dismissBtn: {
    background: 'none', border: 'none', color: 'var(--on-accent)', fontSize: 14,
    lineHeight: 1, padding: 0, opacity: 0.8,
  },
}
