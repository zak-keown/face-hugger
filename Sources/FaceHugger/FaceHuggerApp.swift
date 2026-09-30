import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model?.installing == true {
            let alert = NSAlert(); alert.messageText = "Upload tools are still being installed"
            alert.informativeText = "Please let setup finish before quitting Face Hugger."
            alert.addButton(withTitle: "Continue setup"); alert.runModal()
            return .terminateCancel
        }
        guard let model, model.activeJob != nil else { return .terminateNow }
        let alert = NSAlert(); alert.messageText = "Stop uploading and quit?"
        alert.informativeText = "You can resume this upload next time you open Face Hugger. Files already committed will remain on Hugging Face. Closing the window instead keeps your upload running."
        alert.addButton(withTitle: "Keep uploading"); alert.addButton(withTitle: "Stop and quit")
        if alert.runModal() == .alertSecondButtonReturn {
            model.stop()
            Task { @MainActor in
                while model.activeJob != nil { try? await Task.sleep(for: .milliseconds(100)) }
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        return .terminateCancel
    }
}

@main
struct FaceHuggerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    var body: some Scene {
        Window("Face Hugger", id: "main") {
            MainView(model: model)
                .tint(BenchTheme.transfer)
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1240, height: 820)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Upload…") { model.chooseFolder() }.keyboardShortcut("n")
                Button("New Repository…") { model.showCreateRepo = true }.keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.showSettings = true }.keyboardShortcut(",")
            }
        }
        MenuBarExtra("Face Hugger", systemImage: model.activeJob == nil ? "tray.and.arrow.up" : "arrow.up.circle.fill") {
            MenuContent(model: model)
        }
    }
}

struct MenuContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        if let job = model.activeJob {
            Text("Uploading \(job.title)")
            Text(job.repo.name)
            Button("Stop Uploads") { model.stop() }
        } else { Text("No active uploads") }
        Divider()
        Button("Show Face Hugger") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("Quit Face Hugger") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
