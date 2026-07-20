import { fetchAndActivate, getString } from 'firebase/remote-config'
import { firebaseRemoteConfig } from './firebase'

export async function fetchEnabledModelIds(): Promise<Set<string> | null> {
  try {
    const rc = firebaseRemoteConfig()
    await fetchAndActivate(rc)
    const raw = getString(rc, 'available_models')
    console.log('[remoteConfig] raw available_models:', raw)
    if (!raw) return null
    const arr: { id?: string }[] = JSON.parse(raw)
    const ids = new Set(arr.map((e) => e.id).filter((id): id is string => !!id))
    console.log('[remoteConfig] parsed ids:', Array.from(ids))
    return ids.size > 0 ? ids : null
  } catch (e) {
    console.log('[remoteConfig] fetch failed:', e)
    return null
  }
}
