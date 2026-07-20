import { initializeApp, FirebaseApp } from 'firebase/app'
import { getAuth, Auth } from 'firebase/auth'
import { getRemoteConfig, RemoteConfig } from 'firebase/remote-config'

const firebaseConfig = {
  apiKey:            'AIzaSyDahFpI3oma1vdu3LXtxMRhXcyHmvGT-Ec',
  authDomain:        'ecoinference-28c31.firebaseapp.com',
  projectId:         'ecoinference-28c31',
  storageBucket:     'ecoinference-28c31.firebasestorage.app',
  messagingSenderId: '333037511007',
  appId:             '1:333037511007:web:bae0516ce9b05235c6d6ea',
  measurementId:     'G-MLXRF27TKL',
}

let _app:          FirebaseApp    | null = null
let _auth:         Auth           | null = null
let _remoteConfig: RemoteConfig   | null = null

export function getFirebaseApp(): FirebaseApp {
  if (!_app) _app = initializeApp(firebaseConfig)
  return _app
}

export function firebaseAuth(): Auth {
  if (!_auth) _auth = getAuth(getFirebaseApp())
  return _auth
}

export function firebaseRemoteConfig(): RemoteConfig {
  if (!_remoteConfig) {
    _remoteConfig = getRemoteConfig(getFirebaseApp())
    // TODO: restore to 3_600_000 before shipping — set to 0 temporarily to verify
    // the new gemma4-12b-it Remote Config entry without waiting out the cache.
    _remoteConfig.settings.minimumFetchIntervalMillis = 0
  }
  return _remoteConfig
}
