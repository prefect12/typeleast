import AppKit
import SwiftData
import SwiftUI

@main
internal struct TypeleastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // This is a menu bar app, so we just need to define menu commands
        // All windows are created programmatically
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
                .onAppear {
                    // Hide the empty window immediately
                    NSApplication.shared.windows.first?.orderOut(nil)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.Menu.settings) {
                    DashboardWindowManager.shared.showDashboardWindow(selectedNav: .preferences)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .windowArrangement) {
                Button(L10n.Menu.closeWindow) {
                    NSApplication.shared.keyWindow?.orderOut(nil)
                }
                // No keyboard shortcut hints
            }
        }
    }

    /// Creates a fallback container if DataManager initialization fails
    private func createFallbackContainer() -> ModelContainer {
        do {
            let schema = Schema([TranscriptionRecord.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create fallback ModelContainer: \(error)")
        }
    }
}
