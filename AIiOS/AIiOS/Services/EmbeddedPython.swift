import Foundation
import PythonKit

/// Bootstraps the embedded BeeWare CPython runtime.
///
/// Call `EmbeddedPython.start()` exactly once, before any Python code runs.
/// It sets the required environment variables (PYTHONHOME, PYTHON_LIBRARY,
/// MPLBACKEND) and configures sys.path so that runner.py and app_packages
/// are importable.
enum EmbeddedPython {

    // MARK: - Public API

    private(set) static var isStarted = false

    /// Starts the Python runtime. Safe to call multiple times — only the first
    /// call has any effect.
    static func start() {
        guard !isStarted else { return }
        isStarted = true

        guard let bundle = Bundle.main.resourceURL else {
            fatalError("EmbeddedPython: cannot locate main bundle resources")
        }

        let frameworks = bundle.deletingLastPathComponent().appendingPathComponent("Frameworks")
        let pythonLib  = frameworks.appendingPathComponent("Python.framework/Python").path
        let pythonHome = bundle.appendingPathComponent("python").path

        // Must be set before PythonKit loads the library via dlopen.
        setenv("PYTHON_LIBRARY", pythonLib, 1)
        setenv("PYTHONHOME",     pythonHome, 1)
        setenv("MPLBACKEND",     "Agg",     1)

        // Trigger Py_Initialize via the first PythonKit access.
        _ = Python.version

        // Extend sys.path with app_packages and app directories.
        let sys         = Python.import("sys")
        let appPackages = bundle.appendingPathComponent("app_packages").path
        let app         = bundle.appendingPathComponent("app").path

        sys.path.insert(0, appPackages)
        sys.path.insert(0, app)

        print("[EmbeddedPython] Python \(Python.version) started")
        print("[EmbeddedPython] PYTHONHOME  = \(pythonHome)")
        print("[EmbeddedPython] lib path[0] = \(app)")
    }
}
