import Foundation

/// Versioned separately from older installs so a failed repair cannot damage the user's old runtime.
public enum RuntimePolicy {
    public static let pythonVersion = "3.12.14"
    public static let runtimeDirectory = "runtime-v3"

    public static func setupEnvironment(support: URL) -> [String: String] {
        ["UV_PYTHON_INSTALL_DIR": support.appendingPathComponent("python").path,
         "UV_CACHE_DIR": support.appendingPathComponent("setup-cache").path,
         "UV_PYTHON_INSTALL_BIN": "0",
         "UV_NO_CONFIG": "1",
         "UV_NO_HF_TOKEN": "1"]
    }

    public static func setupCommands(support: URL, requirements: URL) -> [[String]] {
        let runtime = support.appendingPathComponent(runtimeDirectory)
        return [
            ["venv", "--allow-existing", "--managed-python", "--python", pythonVersion, runtime.path],
            ["pip", "sync", "--python", runtime.appendingPathComponent("bin/python3").path,
             "--require-hashes", "--only-binary", ":all:", "--default-index", "https://pypi.org/simple", requirements.path]
        ]
    }
}
