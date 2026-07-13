import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow?
    private var panel: NSPanel?
    private var translationMenuItem: NSMenuItem?
    private var clickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private static let panelSize = NSSize(width: 340, height: 520)
    private static let mainWindowSize = NSSize(width: 980, height: 680)

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        createMainWindow()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.eyeImage(active: false)
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        AppState.shared.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                self?.statusItem.button?.image = Self.eyeImage(active: running)
                self?.translationMenuItem?.title = running
                    ? "Остановить перевод"
                    : "Запустить перевод"
            }
            .store(in: &cancellables)

        AppState.shared.refreshApps()
        showMainWindow()
        UpdateManager.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await SupabaseAuthManager.shared.refreshCurrentUser() }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === mainWindow else { return true }

        closePanel()
        sender.orderOut(nil)
        return false
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "EyeVoice")

        let openItem = NSMenuItem(
            title: "Открыть EyeVoice",
            action: #selector(showMainWindowFromMenu(_:)),
            keyEquivalent: ""
        )
        openItem.target = self
        appMenu.addItem(openItem)

        let translationItem = NSMenuItem(
            title: "Запустить перевод",
            action: #selector(toggleTranslationFromMenu(_:)),
            keyEquivalent: ""
        )
        translationItem.target = self
        appMenu.addItem(translationItem)
        translationMenuItem = translationItem
        appMenu.addItem(.separator())

        let hideItem = NSMenuItem(
            title: "Скрыть EyeVoice",
            action: #selector(hideMainWindow(_:)),
            keyEquivalent: "h"
        )
        hideItem.target = self
        appMenu.addItem(hideItem)
        appMenu.addItem(.separator())

        let updateItem = NSMenuItem(
            title: "Проверить обновления…",
            action: #selector(UpdateManager.checkForUpdatesFromMenu(_:)),
            keyEquivalent: ""
        )
        updateItem.target = UpdateManager.shared
        appMenu.addItem(updateItem)

        let quitItem = NSMenuItem(
            title: "Завершить EyeVoice",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func createMainWindow() {
        let hosting = NSHostingController(
            rootView: MainWindowView().environmentObject(AppState.shared)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.mainWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "EyeVoice"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = hosting
        window.backgroundColor = NSColor(white: 0.02, alpha: 1)
        window.minSize = NSSize(width: 860, height: 580)
        window.setContentSize(Self.mainWindowSize)
        window.setFrameAutosaveName("EyeVoiceDashboardWindow")
        window.center()
        mainWindow = window
    }

    private func showMainWindow() {
        guard let mainWindow else { return }
        AppState.shared.refreshApps()
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow.makeKeyAndOrderFront(nil)
    }

    @objc private func showMainWindowFromMenu(_ sender: Any?) {
        showMainWindow()
    }

    @objc private func hideMainWindow(_ sender: Any?) {
        closePanel()
        mainWindow?.orderOut(nil)
    }

    @objc private func toggleTranslationFromMenu(_ sender: Any?) {
        AppState.shared.toggle()
    }

    /// Menu bar eye: almond outline with a pupil; filled (inverted) when translation is active.
    private static func eyeImage(active: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 15)
        let image = NSImage(size: size, flipped: false) { _ in
            let eye = NSBezierPath()
            eye.move(to: NSPoint(x: 1.5, y: 7.5))
            eye.curve(
                to: NSPoint(x: 20.5, y: 7.5),
                controlPoint1: NSPoint(x: 6.5, y: 14.8),
                controlPoint2: NSPoint(x: 15.5, y: 14.8)
            )
            eye.curve(
                to: NSPoint(x: 1.5, y: 7.5),
                controlPoint1: NSPoint(x: 15.5, y: 0.2),
                controlPoint2: NSPoint(x: 6.5, y: 0.2)
            )
            eye.close()

            NSColor.black.set()
            if active {
                // filled eye with a punched-out pupil — clearly "on"
                let pupil = NSBezierPath(ovalIn: NSRect(x: 8.2, y: 4.7, width: 5.6, height: 5.6))
                eye.append(pupil)
                eye.windingRule = .evenOdd
                eye.fill()
            } else {
                eye.lineWidth = 1.6
                eye.stroke()
                NSBezierPath(ovalIn: NSRect(x: 8.6, y: 5.1, width: 4.8, height: 4.8)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func togglePopover(_ sender: Any?) {
        if panel?.isVisible == true {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        AppState.shared.refreshApps()

        let hosting = NSHostingController(
            rootView: ControlPanelView().environmentObject(AppState.shared)
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hosting

        hosting.view.wantsLayer = true
        hosting.view.layer?.cornerRadius = 14
        hosting.view.layer?.masksToBounds = true
        hosting.view.layer?.borderWidth = 1
        hosting.view.layer?.borderColor = NSColor(white: 0.28, alpha: 1).cgColor

        // anchor: centered under the status item icon, clamped to the screen edge
        if let button = statusItem.button, let buttonWindow = button.window {
            let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let screen = buttonWindow.screen ?? NSScreen.main
            let visible = screen?.visibleFrame ?? buttonRect
            var x = buttonRect.midX - Self.panelSize.width / 2
            x = min(max(x, visible.minX + 8), visible.maxX - Self.panelSize.width - 8)
            let y = buttonRect.minY - Self.panelSize.height - 6
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        self.panel = panel

        // close when clicking anywhere outside the app
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func closePanel() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
    }
}
