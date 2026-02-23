import AppKit

class SettingsWindowController: NSWindowController {
    private var config: AppConfig
    /// Called when hotkeys change so the app can re-register them.
    var onHotkeysChanged: ((AppConfig.HotkeyConfig) -> Void)?

    init(config: AppConfig) {
        self.config = config
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        setupTabs()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Tab View

    private func setupTabs() {
        let tabView = NSTabView(frame: window!.contentView!.bounds)
        tabView.autoresizingMask = [.width, .height]

        let generalTab = NSTabViewItem(identifier: "general")
        generalTab.label = "General"
        generalTab.view = makeGeneralTab()
        tabView.addTabViewItem(generalTab)

        let shortcutsTab = NSTabViewItem(identifier: "shortcuts")
        shortcutsTab.label = "Shortcuts"
        shortcutsTab.view = makeShortcutsTab()
        tabView.addTabViewItem(shortcutsTab)

        window!.contentView = tabView
    }

    // MARK: - General Tab

    private func makeGeneralTab() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))

        var y: CGFloat = 190

        // Auto-Analyze toggle
        let analyzeLabel = NSTextField(labelWithString: "Auto-Analyze Screenshots:")
        analyzeLabel.frame = NSRect(x: 20, y: y, width: 200, height: 20)
        container.addSubview(analyzeLabel)

        let analyzeSwitch = NSSwitch()
        analyzeSwitch.frame = NSRect(x: 230, y: y - 2, width: 40, height: 24)
        analyzeSwitch.state = config.ai.autoAnalyze ? .on : .off
        analyzeSwitch.target = self
        analyzeSwitch.action = #selector(toggleAutoAnalyze(_:))
        container.addSubview(analyzeSwitch)

        y -= 40

        // Screenshots directory
        let dirLabel = NSTextField(labelWithString: "Screenshots Directory:")
        dirLabel.frame = NSRect(x: 20, y: y, width: 200, height: 20)
        container.addSubview(dirLabel)

        y -= 26
        let pathControl = NSPathControl()
        pathControl.frame = NSRect(x: 20, y: y, width: 360, height: 24)
        pathControl.isEditable = false
        pathControl.url = URL(fileURLWithPath: config.screenshotsDir)
        pathControl.pathStyle = .standard
        container.addSubview(pathControl)

        y -= 50

        // Open Config File button
        let openConfigBtn = NSButton(title: "Open Config File...", target: self, action: #selector(openConfigFile))
        openConfigBtn.bezelStyle = .rounded
        openConfigBtn.frame = NSRect(x: 20, y: y, width: 160, height: 28)
        container.addSubview(openConfigBtn)

        return container
    }

    @objc private func toggleAutoAnalyze(_ sender: NSSwitch) {
        config.ai.autoAnalyze = (sender.state == .on)
        saveConfig()
    }

    @objc private func openConfigFile() {
        let path = AppConfig.configPath()
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    // MARK: - Shortcuts Tab

    private var shortcutButtons: [String: ShortcutButton] = [:]

    private func makeShortcutsTab() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))

        let shortcuts: [(label: String, key: String, value: String)] = [
            ("Capture Fullscreen", "captureFullscreen", config.hotkeys.captureFullscreen),
            ("Capture Region", "captureRegion", config.hotkeys.captureRegion),
            ("Capture Window", "captureWindow", config.hotkeys.captureWindow),
            ("Open Gallery", "openGallery", config.hotkeys.openGallery),
        ]

        var y: CGFloat = 190
        for shortcut in shortcuts {
            let label = NSTextField(labelWithString: shortcut.label + ":")
            label.frame = NSRect(x: 20, y: y, width: 160, height: 20)
            container.addSubview(label)

            let btn = ShortcutButton(shortcutString: shortcut.value)
            btn.frame = NSRect(x: 190, y: y - 2, width: 190, height: 24)
            btn.onShortcutChanged = { [weak self] newValue in
                self?.updateShortcut(key: shortcut.key, value: newValue)
            }
            container.addSubview(btn)
            shortcutButtons[shortcut.key] = btn

            y -= 36
        }

        // Restore Defaults button
        let restoreBtn = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))
        restoreBtn.bezelStyle = .rounded
        restoreBtn.frame = NSRect(x: 20, y: 20, width: 140, height: 28)
        container.addSubview(restoreBtn)

        return container
    }

    private func updateShortcut(key: String, value: String) {
        switch key {
        case "captureFullscreen": config.hotkeys.captureFullscreen = value
        case "captureRegion": config.hotkeys.captureRegion = value
        case "captureWindow": config.hotkeys.captureWindow = value
        case "openGallery": config.hotkeys.openGallery = value
        default: break
        }
        saveConfig()
        onHotkeysChanged?(config.hotkeys)
    }

    @objc private func restoreDefaults() {
        config.hotkeys = .defaults
        shortcutButtons["captureFullscreen"]?.setShortcut(config.hotkeys.captureFullscreen)
        shortcutButtons["captureRegion"]?.setShortcut(config.hotkeys.captureRegion)
        shortcutButtons["captureWindow"]?.setShortcut(config.hotkeys.captureWindow)
        shortcutButtons["openGallery"]?.setShortcut(config.hotkeys.openGallery)
        saveConfig()
        onHotkeysChanged?(config.hotkeys)
    }

    private func saveConfig() {
        do {
            try config.save()
        } catch {
            NSLog("Failed to save config: \(error)")
        }
    }
}

// MARK: - Shortcut Recorder Button

/// A button that records a keyboard shortcut when clicked.
class ShortcutButton: NSButton {
    private var shortcutString: String
    private var isRecording = false
    var onShortcutChanged: ((String) -> Void)?

    private var localMonitor: Any?

    init(shortcutString: String) {
        self.shortcutString = shortcutString
        super.init(frame: .zero)
        bezelStyle = .rounded
        title = shortcutString
        target = self
        action = #selector(startRecording)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setShortcut(_ value: String) {
        shortcutString = value
        title = value
    }

    @objc private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        title = "Press shortcut..."

        // Monitor local key events to capture the shortcut
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }
            return self.handleRecordingKeyDown(event)
        }
    }

    private func handleRecordingKeyDown(_ event: NSEvent) -> NSEvent? {
        // Require at least one modifier
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasModifier = mods.contains(.control) || mods.contains(.shift)
            || mods.contains(.option) || mods.contains(.command)

        if event.keyCode == 0x35 /* Escape */ && !hasModifier {
            // Cancel recording
            stopRecording(shortcutString)
            return nil
        }

        guard hasModifier else { return event }

        let display = HotkeyManager.displayString(keyCode: event.keyCode, modifiers: mods)
        // Verify it can be parsed
        guard HotkeyManager.parse(display) != nil else { return event }

        stopRecording(display)
        return nil // consume the event
    }

    private func stopRecording(_ value: String) {
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        shortcutString = value
        title = value
        if value != shortcutString {
            onShortcutChanged?(value)
        } else {
            // Always fire — the value was set before the comparison
            onShortcutChanged?(value)
        }
    }
}
