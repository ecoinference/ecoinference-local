import React, { useEffect, useRef, useState } from 'react'
import { useAppContext } from '../context/AppContext'
import { Message } from '../context/AppContext'

function MessageBubble({ msg }: { msg: Message }): JSX.Element {
  const isUser = msg.role === 'user'
  return (
    <div style={{ ...styles.bubble, alignSelf: isUser ? 'flex-end' : 'flex-start' }}>
      <div style={isUser ? styles.bubbleUser : styles.bubbleAssistant}>
        {msg.imageDataUrl && (
          <img src={msg.imageDataUrl} alt="Attached" style={styles.messageImage} />
        )}
        <pre style={styles.bubbleText}>{msg.content || <span style={styles.cursor}>▊</span>}</pre>
      </div>
    </div>
  )
}

export default function ChatScreen(): JSX.Element {
  const { state, sendMessage, clearChat, navigateTo } = useAppContext()
  const [input, setInput] = useState('')
  const [attachedImage, setAttachedImage] = useState<string | null>(null)
  const bottomRef = useRef<HTMLDivElement>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [state.messages])

  const model = state.models.find((m) => m.id === state.loadedModelId)

  function handleKeyDown(e: React.KeyboardEvent<HTMLTextAreaElement>): void {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSend()
    }
  }

  function handleSend(): void {
    const text = input.trim()
    if ((!text && !attachedImage) || state.generating) return
    setInput('')
    setAttachedImage(null)
    sendMessage(text, attachedImage ?? undefined)
  }

  function handleFileSelect(e: React.ChangeEvent<HTMLInputElement>): void {
    const file = e.target.files?.[0]
    e.target.value = '' // allow re-selecting the same file later
    if (!file) return
    const reader = new FileReader()
    reader.onload = () => setAttachedImage(reader.result as string)
    reader.readAsDataURL(file)
  }

  if (!state.loadedModelId || !state.serverRunning) {
    return (
      <div style={styles.emptyWrap}>
        <p style={styles.emptyText}>No model loaded.</p>
        <button style={styles.btnPrimary} onClick={() => navigateTo('models')}>
          Go to Models
        </button>
      </div>
    )
  }

  return (
    <div style={styles.wrap}>
      <div style={styles.header}>
        <span style={styles.modelLabel}>{model?.displayName ?? state.loadedModelId}</span>
        <button style={styles.clearBtn} onClick={clearChat} title="Clear conversation">
          Clear
        </button>
      </div>

      <div style={styles.messages}>
        {state.messages.length === 0 && (
          <p style={styles.placeholder}>Send a message to start the conversation.</p>
        )}
        {state.messages.map((m) => <MessageBubble key={m.id} msg={m} />)}
        <div ref={bottomRef} />
      </div>

      {attachedImage && (
        <div style={styles.attachmentRow}>
          <img src={attachedImage} alt="Attached" style={styles.attachmentThumb} />
          <button style={styles.attachmentRemoveBtn} onClick={() => setAttachedImage(null)} title="Remove image">
            ✕
          </button>
        </div>
      )}

      <div style={styles.inputRow}>
        {model?.supportsImageInput && (
          <>
            <input
              ref={fileInputRef}
              type="file"
              accept="image/*"
              style={styles.hiddenFileInput}
              onChange={handleFileSelect}
            />
            <button
              style={styles.attachBtn}
              onClick={() => fileInputRef.current?.click()}
              disabled={state.generating}
              title="Attach an image"
            >
              📷
            </button>
          </>
        )}
        <textarea
          style={styles.textarea}
          placeholder="Message…  (Shift+Enter for new line)"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={handleKeyDown}
          rows={1}
          disabled={state.generating}
        />
        <button
          style={styles.sendBtn}
          onClick={handleSend}
          disabled={state.generating || (!input.trim() && !attachedImage)}
        >
          {state.generating ? '…' : '↑'}
        </button>
      </div>
    </div>
  )
}

const styles: Record<string, React.CSSProperties> = {
  wrap: {
    display: 'flex', flexDirection: 'column', height: '100%',
    background: 'var(--bg)',
  },
  header: {
    display: 'flex', alignItems: 'center', justifyContent: 'space-between',
    padding: '12px 20px', borderBottom: '1px solid var(--border)',
    background: 'var(--surface)',
  },
  modelLabel: { fontSize: 13, fontWeight: 600, color: 'var(--text-dim)' },
  clearBtn: {
    background: 'none', border: 'none', color: 'var(--text-dim)',
    fontSize: 12, fontWeight: 600,
  },

  messages: {
    flex: 1, overflowY: 'auto', padding: '20px 20px 12px',
    display: 'flex', flexDirection: 'column', gap: 14,
  },
  placeholder: { color: 'var(--text-dim)', fontSize: 14, textAlign: 'center', marginTop: 40 },

  bubble: { display: 'flex', flexDirection: 'column', maxWidth: '72%' },
  bubbleUser: {
    background: 'var(--accent)', color: 'var(--on-accent)',
    borderRadius: '14px 14px 4px 14px', padding: '10px 14px',
  },
  bubbleAssistant: {
    background: 'var(--surface)', border: '1px solid var(--border)',
    borderRadius: '14px 14px 14px 4px', padding: '10px 14px',
  },
  bubbleText: {
    margin: 0, fontFamily: 'inherit', fontSize: 14, lineHeight: 1.5,
    whiteSpace: 'pre-wrap', wordBreak: 'break-word',
  },
  messageImage: {
    maxWidth: '100%', maxHeight: 240, borderRadius: 8, display: 'block', marginBottom: 8,
  },
  cursor: { animation: 'blink 1s step-end infinite' },

  attachmentRow: {
    display: 'flex', alignItems: 'center', gap: 10,
    padding: '10px 16px 0', background: 'var(--surface)',
  },
  attachmentThumb: {
    height: 56, width: 56, objectFit: 'cover', borderRadius: 8,
    border: '1px solid var(--border)',
  },
  attachmentRemoveBtn: {
    background: 'var(--surface2)', border: '1px solid var(--border)', borderRadius: '50%',
    width: 22, height: 22, color: 'var(--text-dim)', fontSize: 11, lineHeight: 1,
    display: 'flex', alignItems: 'center', justifyContent: 'center',
  },

  inputRow: {
    display: 'flex', gap: 10, padding: '12px 16px',
    borderTop: '1px solid var(--border)', background: 'var(--surface)',
    alignItems: 'flex-end',
  },
  hiddenFileInput: { display: 'none' },
  attachBtn: {
    width: 40, height: 40, borderRadius: 10, border: '1px solid var(--border)',
    background: 'var(--surface2)', fontSize: 16,
    display: 'flex', alignItems: 'center', justifyContent: 'center',
  },
  textarea: {
    flex: 1, padding: '10px 14px', borderRadius: 12,
    border: '1px solid var(--border)', background: 'var(--surface2)',
    color: 'var(--text)', fontSize: 14, resize: 'none',
    fontFamily: 'inherit', outline: 'none', lineHeight: 1.5,
    maxHeight: 160, overflowY: 'auto',
  },
  sendBtn: {
    width: 40, height: 40, borderRadius: 10, border: 'none',
    background: 'var(--accent)', color: 'var(--on-accent)', fontWeight: 700, fontSize: 18,
    display: 'flex', alignItems: 'center', justifyContent: 'center',
  },

  emptyWrap: {
    display: 'flex', flexDirection: 'column', alignItems: 'center',
    justifyContent: 'center', height: '100%', gap: 16,
  },
  emptyText: { color: 'var(--text-dim)', fontSize: 15 },
  btnPrimary: {
    padding: '9px 22px', borderRadius: 8, border: 'none',
    background: 'var(--accent)', color: 'var(--on-accent)', fontWeight: 600, fontSize: 14,
  },
}
