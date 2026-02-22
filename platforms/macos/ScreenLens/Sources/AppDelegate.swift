import AppKit
import ScreenCaptureKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var galleryWindowController: GalleryWindowController?

    private var database: ScreenLensDatabase?
    private var screenshotStore: ScreenshotStore?
    private var aiClient: AIClient?
    private var config: AppConfig?
    private var windowPicker: WindowPickerWindow?

    private func log(_ msg: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(msg)\n"
        let logPath = "/tmp/screenlens-debug.log"
        if let handle = FileHandle(forWritingAtPath: logPath) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8))
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("applicationDidFinishLaunching")
        initCore()
        log("initCore done")
        setupStatusBarItem()
        log("setupStatusBarItem done")
        registerGlobalHotkeys()
        log("started successfully")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        database = nil
        screenshotStore = nil
        aiClient = nil
    }

    // MARK: - Core Initialization

    private func initCore() {
        do {
            let loadedConfig = try AppConfig.load()
            config = loadedConfig

            let screenshotsDir = loadedConfig.screenshotsDir
            let dbPath = loadedConfig.databasePath

            // Ensure screenshots directory exists
            try FileManager.default.createDirectory(
                atPath: screenshotsDir, withIntermediateDirectories: true)

            let db = try ScreenLensDatabase(path: dbPath)
            database = db
            screenshotStore = ScreenshotStore(database: db, saveDir: screenshotsDir)

            // Set up AI client if configured
            if !loadedConfig.ai.apiUrl.isEmpty && !loadedConfig.ai.apiKey.isEmpty {
                aiClient = AIClient(
                    apiUrl: loadedConfig.ai.apiUrl,
                    apiKey: loadedConfig.ai.apiKey,
                    model: loadedConfig.ai.model
                )
            }

            NSLog("Database opened at \(dbPath)")
            NSLog("Screenshots will be saved to \(screenshotsDir)")
        } catch {
            NSLog("Failed to initialize: \(error)")
        }
    }

    // MARK: - Status Bar (Tray)

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenLens") {
                button.image = img
            } else {
                button.title = "SL"
            }
        }
        fputs("ScreenLens: status bar item created\n", stderr)

        let menu = NSMenu()
        menu.addItem(withTitle: "Capture Fullscreen", action: #selector(captureFullscreen), keyEquivalent: "F")
        menu.addItem(withTitle: "Capture Region", action: #selector(captureRegion), keyEquivalent: "R")
        menu.addItem(withTitle: "Capture Window", action: #selector(captureWindow), keyEquivalent: "W")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Open Gallery", action: #selector(openGallery), keyEquivalent: "G")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")

        statusItem.menu = menu
    }

    // MARK: - Global Hotkeys

    private func registerGlobalHotkeys() {
        // TODO: Register Ctrl+Shift+F/R/W/G using Carbon hotkey APIs
        // or NSEvent.addGlobalMonitorForEvents
    }

    // MARK: - Capture Actions

    @objc private func captureFullscreen() {
        Task {
            do {
                let content = try await SCShareableContent.current
                guard let display = content.displays.first else {
                    NSLog("No display found")
                    return
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = display.width * 2  // Retina
                config.height = display.height * 2

                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )

                let pngData = pngDataFrom(cgImage: image)
                saveAndAnalyze(imageData: pngData, mode: .fullscreen)

            } catch {
                NSLog("Capture failed: \(error)")
            }
        }
    }

    @objc private func captureRegion() {
        guard let screen = NSScreen.main else {
            NSLog("No main screen found")
            return
        }

        let selector = RegionSelectorWindow(screen: screen)
        selector.makeKeyAndOrderFront(nil)

        selector.onRegionSelected = { [weak self] selectedRect in
            guard let self = self else { return }
            // Wait briefly for the overlay to disappear before capturing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                Task {
                    do {
                        let content = try await SCShareableContent.current
                        guard let display = content.displays.first else {
                            NSLog("No display found")
                            return
                        }

                        let filter = SCContentFilter(display: display, excludingWindows: [])
                        let config = SCStreamConfiguration()
                        config.width = display.width * 2  // Retina
                        config.height = display.height * 2

                        let fullImage = try await SCScreenshotManager.captureImage(
                            contentFilter: filter,
                            configuration: config
                        )

                        // Convert the selection rect from screen coordinates to image pixels.
                        // Screen coordinates are in points; the captured image is at 2x (Retina).
                        let scale = CGFloat(fullImage.width) / screen.frame.width
                        // Screen coordinates have origin at bottom-left; CGImage at top-left.
                        let flippedY = screen.frame.height - selectedRect.maxY
                        let cropRect = CGRect(
                            x: selectedRect.origin.x * scale,
                            y: flippedY * scale,
                            width: selectedRect.width * scale,
                            height: selectedRect.height * scale
                        )

                        guard let croppedImage = fullImage.cropping(to: cropRect) else {
                            NSLog("Failed to crop image to selected region")
                            return
                        }

                        let pngData = self.pngDataFrom(cgImage: croppedImage)
                        self.saveAndAnalyze(imageData: pngData, mode: .region)

                    } catch {
                        NSLog("Region capture failed: \(error)")
                    }
                }
            }
        }

        selector.onCancelled = {
            NSLog("Region selection cancelled")
        }
    }

    @objc private func captureWindow() {
        guard let screen = NSScreen.main else { return }

        // Show picker overlay immediately (same pattern as region selector)
        self.windowPicker = WindowPickerWindow(screen: screen, windows: [])
        self.windowPicker?.makeKeyAndOrderFront(nil)

        // Fetch window list async, then update the picker
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    true, onScreenWindowsOnly: true
                )

                // Get z-ordered window IDs from CGWindowList (front-to-back)
                // Only include normal app windows (layer 0)
                let zOrderedIDs: [CGWindowID]
                if let cgList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
                    zOrderedIDs = cgList.compactMap { info -> CGWindowID? in
                        guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                              let layer = info[kCGWindowLayer as String] as? Int,
                              layer == 0 else { return nil }
                        return id
                    }
                } else {
                    zOrderedIDs = []
                }

                // Filter to real app windows, exclude our own app
                let filtered = content.windows.filter {
                    $0.isOnScreen
                    && $0.frame.width > 50 && $0.frame.height > 50
                    && $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
                }

                // Sort by z-order (frontmost first)
                let idToWindow = Dictionary(uniqueKeysWithValues: filtered.map { ($0.windowID, $0) })
                var windows: [SCWindow] = []
                for id in zOrderedIDs {
                    if let w = idToWindow[id] {
                        windows.append(w)
                    }
                }
                // Append any that weren't in CGWindowList
                let matched = Set(windows.map { $0.windowID })
                windows.append(contentsOf: filtered.filter { !matched.contains($0.windowID) })

                let display = content.displays.first

                await MainActor.run {
                    if let overlay = self.windowPicker?.contentView as? WindowPickerOverlayView {
                        overlay.windows = windows
                        overlay.needsDisplay = true
                    }
                }

                self.windowPicker?.onWindowSelected = { [weak self] selectedWindow in
                    guard let self = self else { return }
                    self.windowPicker = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        Task {
                            do {
                                guard let display = display else { return }
                                let filter = SCContentFilter(
                                    display: display,
                                    including: [selectedWindow]
                                )
                                let config = SCStreamConfiguration()
                                config.width = Int(selectedWindow.frame.width) * 2
                                config.height = Int(selectedWindow.frame.height) * 2

                                let image = try await SCScreenshotManager.captureImage(
                                    contentFilter: filter,
                                    configuration: config
                                )

                                let pngData = self.pngDataFrom(cgImage: image)
                                self.saveAndAnalyze(imageData: pngData, mode: .window)
                            } catch {
                                NSLog("Window capture failed: \(error)")
                            }
                        }
                    }
                }

                self.windowPicker?.onCancelled = { [weak self] in
                    self?.windowPicker = nil
                    NSLog("Window selection cancelled")
                }
            } catch {
                NSLog("Window capture failed: \(error)")
                await MainActor.run {
                    self.windowPicker?.close()
                    self.windowPicker = nil
                }
            }
        }
    }

    @objc private func openGallery() {
        if galleryWindowController == nil {
            galleryWindowController = GalleryWindowController(database: database)
        }
        galleryWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func pngDataFrom(cgImage: CGImage) -> Data {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    private func saveAndAnalyze(imageData: Data, mode: CaptureMode) {
        guard let store = screenshotStore else {
            NSLog("Core not initialized — captured \(imageData.count) bytes (\(mode.rawValue)) but cannot save")
            copyToClipboard(imageData: imageData)
            return
        }

        do {
            let result = try store.save(imageData: imageData, mode: mode)
            NSLog("Screenshot saved: \(result.filename) (\(result.sizeBytes) bytes)")

            // Fire async AI analysis if client is configured
            if let ai = aiClient, config?.ai.autoAnalyze == true {
                let screenshotId = result.id
                let db = database
                Task {
                    do {
                        let analysis = try await ai.analyze(imageData: imageData)
                        try db?.updateAnalysis(id: screenshotId, analysis: analysis)
                        NSLog("AI analysis complete for \(screenshotId): \(analysis.summary)")
                    } catch {
                        NSLog("AI analysis failed: \(error)")
                    }
                }
            }
        } catch {
            NSLog("Failed to save screenshot: \(error)")
        }

        // Also copy to clipboard as a convenience
        copyToClipboard(imageData: imageData)
    }

    private func copyToClipboard(imageData: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(imageData, forType: .png)
    }
}
