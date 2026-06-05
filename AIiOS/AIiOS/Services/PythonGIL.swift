import Foundation

// MARK: - CPython symbol references
//
// PythonKit links Python.framework, so CPython's ABI symbols are already in
// the process.  @_silgen_name tells Swift to call the named C symbol directly,
// bypassing any Swift name-mangling — no bridging header or header import needed.
//
// Why the GIL matters:
//   After Py_Initialize() the GIL is held by the initialising thread (main).
//   Calling *any* Python C-API or PythonKit function from a different OS thread
//   without first acquiring the GIL causes an immediate SIGSEGV (signal 11).
//   Swift's Task.detached uses the cooperative thread pool, NOT the main thread,
//   so every PythonRunner call needs the acquire/release wrapper below.

/// Release the GIL from the current (main) thread.
/// Returns the saved PyThreadState* — we discard it; other threads use
/// PyGILState_Ensure/Release independently.
@_silgen_name("PyEval_SaveThread")
private func _PyEval_SaveThread() -> OpaquePointer?

/// Acquire the GIL for the calling thread (creates a thread-state if needed).
/// Returns a PyGILState_STATE token (int enum: 0 = locked, 1 = unlocked).
@_silgen_name("PyGILState_Ensure")
private func _PyGILState_Ensure() -> Int32

/// Release the GIL, passing back the token from _PyGILState_Ensure.
@_silgen_name("PyGILState_Release")
private func _PyGILState_Release(_ state: Int32)

// MARK: - Public API

/// GIL management helpers for running PythonKit safely on background threads.
enum PythonGIL {

    /// Call ONCE at the end of EmbeddedPython.start(), after all main-thread
    /// Python setup is complete.  Releases the GIL from the main thread so
    /// background threads can acquire it via ensure()/release().
    static func enableMultiThreading() {
        _ = _PyEval_SaveThread()
    }

    /// Acquire the GIL.  Call before any PythonKit / CPython C-API access on
    /// a background thread.  Returns an opaque state token.
    static func ensure() -> Int32 {
        return _PyGILState_Ensure()
    }

    /// Release the GIL.  Pass the token returned by ensure().
    static func release(_ state: Int32) {
        _PyGILState_Release(state)
    }
}
