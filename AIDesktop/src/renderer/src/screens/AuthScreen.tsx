import React, { useState } from 'react'
import {
  signInWithEmailAndPassword,
  createUserWithEmailAndPassword,
} from 'firebase/auth'
import { firebaseAuth } from '../services/firebase'

export default function AuthScreen(): JSX.Element {
  const [email,    setEmail]    = useState('')
  const [password, setPassword] = useState('')
  const [error,    setError]    = useState<string | null>(null)
  const [loading,  setLoading]  = useState(false)
  const [mode,     setMode]     = useState<'signin' | 'signup'>('signin')

  async function handleSubmit(e: React.FormEvent): Promise<void> {
    e.preventDefault()
    setError(null)
    setLoading(true)
    try {
      if (mode === 'signin') {
        await signInWithEmailAndPassword(firebaseAuth(), email, password)
      } else {
        await createUserWithEmailAndPassword(firebaseAuth(), email, password)
      }
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Authentication failed')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div style={styles.wrap}>
      <div style={styles.card}>
        <div style={styles.logo}>
          <span style={styles.logoLeaf}>🌿</span>
          <span style={styles.logoText}>EcoInference&trade;</span>
        </div>
        <p style={styles.tagline}>Local AI, offline and private</p>

        <form onSubmit={handleSubmit} style={styles.form}>
          <input
            style={styles.input}
            type="email"
            placeholder="Email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
          />
          <input
            style={styles.input}
            type="password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
          <button style={styles.submitBtn} type="submit" disabled={loading}>
            {loading ? 'Please wait…' : mode === 'signin' ? 'Sign In' : 'Create Account'}
          </button>
        </form>

        {error && <p style={styles.error}>{error}</p>}

        <p style={styles.toggle}>
          {mode === 'signin' ? "Don't have an account? " : 'Already have an account? '}
          <button
            style={styles.toggleBtn}
            onClick={() => setMode(mode === 'signin' ? 'signup' : 'signin')}
          >
            {mode === 'signin' ? 'Sign Up' : 'Sign In'}
          </button>
        </p>
      </div>
    </div>
  )
}

const styles: Record<string, React.CSSProperties> = {
  wrap: {
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    height: '100%', background: 'var(--bg)',
  },
  card: {
    width: 360, padding: '40px 36px', background: 'var(--surface)',
    borderRadius: 'var(--radius)', border: '1px solid var(--border)',
    display: 'flex', flexDirection: 'column', gap: 12,
  },
  logo: { display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 },
  logoLeaf: { fontSize: 28 },
  logoText: { fontSize: 20, fontWeight: 700, color: 'var(--accent)' },
  tagline: { margin: '0 0 8px', color: 'var(--text-dim)', fontSize: 13 },
  form: { display: 'flex', flexDirection: 'column', gap: 10 },
  input: {
    padding: '9px 12px', borderRadius: 8, border: '1px solid var(--border)',
    background: 'var(--surface2)', color: 'var(--text)', fontSize: 14, outline: 'none',
  },
  submitBtn: {
    padding: '10px 0', borderRadius: 8, border: 'none',
    background: 'var(--accent)', color: 'var(--on-accent)', fontWeight: 600, fontSize: 14,
  },
  error: { color: 'var(--danger)', fontSize: 13, margin: 0 },
  toggle: { fontSize: 13, color: 'var(--text-dim)', margin: 0, textAlign: 'center' },
  toggleBtn: {
    background: 'none', border: 'none', color: 'var(--accent)',
    fontWeight: 600, fontSize: 13, padding: 0,
  },
}
