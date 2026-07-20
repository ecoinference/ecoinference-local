import React from 'react'
import { AppProvider, useAppContext } from './context/AppContext'
import Sidebar from './components/Sidebar'
import AuthScreen from './screens/AuthScreen'
import ModelsScreen from './screens/ModelsScreen'
import ChatScreen from './screens/ChatScreen'
import AboutScreen from './screens/AboutScreen'

function AppShell(): JSX.Element {
  const { state } = useAppContext()

  if (state.authLoading) {
    return (
      <div style={styles.loading}>
        <span style={styles.spinner}>●</span>
      </div>
    )
  }

  if (!state.user) {
    return <AuthScreen />
  }

  return (
    <div style={styles.layout}>
      <Sidebar />
      <main style={styles.main}>
        {state.screen === 'models' && <ModelsScreen />}
        {state.screen === 'chat'   && <ChatScreen />}
        {state.screen === 'about'  && <AboutScreen />}
      </main>
    </div>
  )
}

export default function App(): JSX.Element {
  return (
    <AppProvider>
      <AppShell />
    </AppProvider>
  )
}

const styles: Record<string, React.CSSProperties> = {
  loading: {
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    height: '100%', color: 'var(--text-dim)', fontSize: 24,
  },
  spinner: { animation: 'spin 1s linear infinite' },
  layout: { display: 'flex', height: '100%' },
  main:   { flex: 1, overflow: 'hidden' },
}
