import AppKit
import SwiftUI
import NexusCore

@main
struct NexusGanttApp: App {
    @NSApplicationDelegateAdaptor(NexusGanttApplicationDelegate.self) private var appDelegate
    @StateObject private var store = GanttStore()

    var body: some Scene {
        WindowGroup("Nexus Gantt") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 620)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("새 프로젝트") { store.addProject() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("새 작업") { store.addTask() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("보기") {
                Button("확대") { store.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                Button("축소") { store.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(store.zoom <= store.minimumZoom + 0.001)
                Button("실제 크기") { store.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)
                Divider()
                Button("처음 위치로 이동") { store.resetViewport() }
                    .keyboardShortcut("0", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
private final class NexusGanttApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            let application = NSApplication.shared
            application.activate(ignoringOtherApps: true)
            application.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}
