import AppKit
import os.log
import UniformTypeIdentifiers

internal extension AppDelegate {
    func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L10n.Menu.record, action: #selector(toggleRecordWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.Menu.transcribeAudioFile, action: #selector(transcribeAudioFile), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.Menu.dashboard, action: #selector(showDashboard), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.Menu.settings, action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: L10n.Menu.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        return menu
    }

    func refreshStatusMenu() {
        statusItem?.menu = makeStatusMenu()
    }

    @MainActor @objc func showDashboard() {
        Logger.app.info("Dashboard menu item selected")
        DashboardWindowManager.shared.showDashboardWindow()
    }

    @MainActor @objc func showSettings() {
        Logger.app.info("Settings menu item selected")
        DashboardWindowManager.shared.showDashboardWindow(selectedNav: .preferences)
    }

    @objc func transcribeAudioFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .mpeg4Audio,
            .mp3,
            .wav,
            .aiff,
            .init(filenameExtension: "m4a")!,
            .init(filenameExtension: "aac") ?? .mpeg4Audio,
            .init(filenameExtension: "flac") ?? .audio,
            .init(filenameExtension: "caf") ?? .audio
        ]
        panel.message = L10n.Menu.audioFilePanelMessage
        panel.prompt = L10n.Menu.transcribePrompt

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.processAudioFile(url)
        }
    }

    private func processAudioFile(_ url: URL) {
        if recordingWindow == nil {
            createRecordingWindow()
        }
        guard let window = recordingWindow else { return }

        if !window.isVisible {
            windowController.toggleRecordWindow(window)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(
                name: .transcribeAudioFile,
                object: url
            )
        }
    }

    @objc func screenConfigurationChanged() {
        AppSetupHelper.resetIconSizeCache()

        if let button = statusItem?.button {
            button.image = AppSetupHelper.createMenuBarIcon()
        }
    }
}
