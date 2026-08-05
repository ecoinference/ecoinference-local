import { initializeApp, FirebaseApp } from 'firebase/app'
import {
  initializeAuth,
  getAuth,
  indexedDBLocalPersistence,
  browserLocalPersistence,
  Auth,
} from 'firebase/auth'
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
  // Persistence is set EXPLICITLY rather than using getAuth()'s auto-detection.
  //
  // In production the renderer is loaded via mainWindow.loadFile(), so the page
  // origin is file:// — not a normal http(s) origin. getAuth() probes the
  // available storage backends and silently falls back to in-memory persistence
  // when it can't confirm one works. In-memory means the session is discarded on
  // every app quit, so the user has to sign in again on each launch. Online that
  // just looks like an annoyance; offline it's fatal, because signing in requires
  // reaching Firebase — the app is stuck on the auth screen with no way past it.
  // Dev builds hid this: they load over http:// from Vite, where storage probing
  // succeeds and the session persists normally.
  //
  // Passing an explicit array makes the SDK try each in order and keep the first
  // that works, instead of quietly degrading to in-memory.
  if (!_auth) {
    try {
      _auth = initializeAuth(getFirebaseApp(), {
        persistence: [indexedDBLocalPersistence, browserLocalPersistence],
      })
    } catch {
      // initializeAuth throws if auth was already initialised for this app. That
      // can happen under Vite HMR in dev, where this module's `_auth` is reset
      // but the underlying Firebase app instance survives. Fall back to the
      // existing instance rather than crashing the renderer — persistence was
      // already configured by the first call.
      _auth = getAuth(getFirebaseApp())
    }
  }
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
