import AppKit
import ScreenCaptureKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var galleryWindowController: GalleryWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()
        registerGlobalHotkeys()
        NSLog("ScreenLens started")
    }

    // MARK: - Status Bar (Tray)

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenLens")
        }

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
                saveAndAnalyze(imageData: pngData, mode: "fullscreen")

            } catch {
                NSLog("Capture failed: \(error)")
            }
        }
    }

    @objc private func captureRegion() {
        // TODO: Present RegionSelectionOverlay, then capture that region
        NSLog("Region capture not yet implemented")
    }

    @objc private func captureWindow() {
        // TODO: Present window picker, then capture selected window
        NSLog("Window capture not yet implemented")
    }

    @objc private func openGallery() {
        if galleryWindowController == nil {
            galleryWindowController = GalleryWindowController()
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

    private func saveAndAnalyze(imageData: Data, mode: String) {
        // TODO: Call into Rust FFI to:
        // 1. Save image to screenshots directory
        // 2. Insert DB record
        // 3. Send to AI API for analysis
        // 4. Update DB with analysis results
        NSLog("Captured \(imageData.count) bytes (\(mode))")
    }
}
