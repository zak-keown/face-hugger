import AppKit
import Foundation

@MainActor
final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var status: NSTextField!
    private let defaults = UserDefaults.standard
    private var preRestoreReadSucceeded: Bool?
    private var reportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FaceHuggerSandboxProbe", isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 310), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Face Hugger Sandbox Probe"
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let heading = NSTextField(labelWithString: "Source access and Python inheritance")
        heading.font = .boldSystemFont(ofSize: 18)
        status = NSTextField(wrappingLabelWithString: "Choose only the dedicated tiny fixture folder. This probe creates one marker file and asks the signed bundled Python child to read and write it. Quit and relaunch with --restore to test the persisted bookmark.")
        status.font = .systemFont(ofSize: 13)
        let choose = NSButton(title: "Choose test folder…", target: self, action: #selector(chooseFolder))
        let restore = NSButton(title: "Restore saved folder", target: self, action: #selector(restoreFolder))
        let quit = NSButton(title: "Quit probe", target: self, action: #selector(quitProbe))
        [heading, status, choose, restore, quit].forEach { stack.addArrangedSubview($0) }
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)])
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--restore") { restoreFolder() }
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Select only the dedicated face-hugger-sandbox-probe-source fixture folder."
        panel.prompt = "Test this folder"
        panel.directoryURL = URL(fileURLWithPath: "/private/tmp/face-hugger-sandbox-probe-source", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.lastPathComponent == "face-hugger-sandbox-probe-source" else {
            status.stringValue = "Please choose only face-hugger-sandbox-probe-source. No files were changed."; return
        }
        do {
            let access = try FolderAccess.selected(url)
            defer { access.close() }
            defaults.set(access.bookmark, forKey: "sourceBookmark")
            defaults.set(access.url.path, forKey: "sourcePath")
            if CommandLine.arguments.contains("--upload") { runUpload(access) }
            else { runChild(access, mode: "selection") }
        } catch { recordFailure(error, mode: "selection") }
    }

    @objc private func restoreFolder() {
        guard let data = defaults.data(forKey: "sourceBookmark"), let path = defaults.string(forKey: "sourcePath") else {
            status.stringValue = "No saved bookmark. Choose the dedicated test folder first."; return
        }
        preRestoreReadSucceeded = (try? Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("face-hugger-probe-marker.txt"))) != nil
        do {
            let access = try FolderAccess.restore(path: path, bookmark: data)
            defer { access.close() }
            defaults.set(access.bookmark, forKey: "sourceBookmark")
            defaults.set(access.url.path, forKey: "sourcePath")
            runChild(access, mode: "restored")
        } catch { recordFailure(error, mode: "restored") }
    }

    private func runChild(_ access: FolderAccess, mode: String) {
        do {
            let marker = access.url.appendingPathComponent("face-hugger-probe-marker.txt")
            let expected = "Face Hugger sandbox fixture \(mode)"
            try Data(expected.utf8).write(to: marker, options: .atomic)
            let executable = Bundle.main.resourceURL!.appendingPathComponent("runtime/bin/python3")
            let process = Process(), pipe = Pipe()
            process.executableURL = executable
            process.currentDirectoryURL = access.url
            process.arguments = ["-c", """
import json,sys
from pathlib import Path
import huggingface_hub
source=Path(sys.argv[1]); expected=sys.argv[2]; mode=sys.argv[3]
actual=(source/'face-hugger-probe-marker.txt').read_text()
assert actual == expected, 'Child could not read the parent marker'
output=source/('face-hugger-child-'+mode+'.txt')
output.write_text(actual)
assert output.read_text() == expected, 'Child could not read its own output'
print(json.dumps({'read':True,'write':True,'hf_version':huggingface_hub.__version__,'python':sys.version.split()[0],'mode':mode}))
""", access.url.path, expected, mode]
            var environment = ProcessInfo.processInfo.environment
            environment.removeValue(forKey: "HF_TOKEN")
            environment["PYTHONDONTWRITEBYTECODE"] = "1"
            environment["PYTHONNOUSERSITE"] = "1"
            environment["HF_HUB_OFFLINE"] = "1"
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe; process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            let passed = process.terminationStatus == 0
            var report: [String: Any] = ["passed": passed, "mode": mode, "exit_status": process.terminationStatus, "source": access.url.path,
                "sandbox_container": ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] ?? "not in environment",
                "home": NSHomeDirectory(), "pid": ProcessInfo.processInfo.processIdentifier, "child_output": output, "date": ISO8601DateFormatter().string(from: Date()),
                "scope": "Signed sandbox probe; bundled Python read/write and SDK import only. No HF network/upload test."]
            if let preRestoreReadSucceeded { report["pre_restore_read_succeeded"] = preRestoreReadSucceeded }
            try save(report, mode: mode)
            // Export only this probe's generated report into its explicitly
            // selected fixture, avoiding any need for container privacy access.
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: access.url.appendingPathComponent("face-hugger-probe-\(mode).json"), options: .atomic)
            status.stringValue = "\(passed ? "PASS" : "FAIL") · \(mode)\n\(output)\nReport: \(reportDirectory.path)/\(mode).json"
        } catch { recordFailure(error, mode: mode) }
    }

    private func runUpload(_ access: FolderAccess) {
        let environment = ProcessInfo.processInfo.environment
        guard let token = environment["FACEHUGGER_PROBE_TOKEN"], !token.isEmpty,
              let repo = environment["FACEHUGGER_PROBE_REPO"] else {
            status.stringValue = "Missing upload-test environment. Launch using sandbox_upload_smoke.py."; return
        }
        let reportURL = access.url.appendingPathComponent("face-hugger-upload.json")
        do {
            let process = Process(), pipe = Pipe()
            process.executableURL = Bundle.main.resourceURL!.appendingPathComponent("runtime/bin/python3")
            process.arguments = [Bundle.main.resourceURL!.appendingPathComponent("bridge.py").path,
                                 "upload", "--repo", repo, "--type", "model", "--source", access.url.appendingPathComponent("payload").path,
                                 "--destination", "sandbox-check"]
            var childEnvironment = environment
            childEnvironment.removeValue(forKey: "FACEHUGGER_PROBE_TOKEN")
            childEnvironment.removeValue(forKey: "FACEHUGGER_PROBE_REPO")
            childEnvironment.removeValue(forKey: "HF_HUB_OFFLINE")
            childEnvironment["HF_TOKEN"] = token
            childEnvironment["PYTHONDONTWRITEBYTECODE"] = "1"
            childEnvironment["PYTHONNOUSERSITE"] = "1"
            process.environment = childEnvironment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe; process.standardError = pipe
            try process.run()
            // Only the process identifier is exposed for timeout cleanup.
            try JSONSerialization.data(withJSONObject: ["bridge_pid": process.processIdentifier])
                .write(to: access.url.appendingPathComponent("face-hugger-upload-running.json"), options: .atomic)
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .replacingOccurrences(of: token, with: "[redacted]")
                .replacingOccurrences(of: "hf_[A-Za-z0-9]+", with: "[redacted]", options: .regularExpression)
            process.waitUntilExit()
            let events = output.split(separator: "\n").compactMap { line -> [String: Any]? in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
            let passed = process.terminationStatus == 0 && events.contains { $0["event"] as? String == "complete" }
            let report: [String: Any] = ["passed": passed, "mode": "upload", "exit_status": process.terminationStatus,
                "pid": ProcessInfo.processInfo.processIdentifier, "bridge_pid": process.processIdentifier,
                "sandbox_container": environment["APP_SANDBOX_CONTAINER_ID"] ?? "not in environment",
                "home": NSHomeDirectory(), "events": events, "output_tail": String(output.suffix(12_000)),
                "scope": "Actual sandbox probe → bundled bridge → bundled HF CLI, private disposable repository."]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportURL, options: .atomic)
            status.stringValue = "\(passed ? "PASS" : "FAIL") · sandbox bridge → HF CLI upload\nExit \(process.terminationStatus). Host harness verifies bytes and deletes the private test repository."
        } catch {
            let message = error.localizedDescription.replacingOccurrences(of: token, with: "[redacted]")
            try? JSONSerialization.data(withJSONObject: ["passed": false, "mode": "upload", "error": message]).write(to: reportURL, options: .atomic)
            status.stringValue = "FAIL · upload\n\(message)"
        }
    }

    private func save(_ report: [String: Any], mode: String) throws {
        try FileManager.default.createDirectory(at: reportDirectory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportDirectory.appendingPathComponent(mode + ".json"), options: .atomic)
    }
    private func recordFailure(_ error: Error, mode: String) {
        try? save(["passed": false, "mode": mode, "error": error.localizedDescription], mode: mode)
        status.stringValue = "FAIL · \(mode)\n\(error.localizedDescription)"
    }
    @objc private func quitProbe() { NSApp.terminate(nil) }
}

@main
struct ProbeMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = ProbeDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
