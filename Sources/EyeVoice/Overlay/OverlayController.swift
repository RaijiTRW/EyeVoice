import AppKit
import SwiftUI

/// Click-through overlay: edge vignette on every screen + the bottom "island" on the main screen.
final class OverlayController {
    private var vignetteWindows: [NSWindow] = []
    private var islandWindow: NSWindow?

    func show(state: AppState) {
        hide()

        for screen in NSScreen.screens {
            let window = Self.makeOverlayWindow(frame: screen.frame)
            window.contentView = NSHostingView(rootView: VignetteView())
            window.orderFrontRegardless()
            vignetteWindows.append(window)
        }

        guard let screen = NSScreen.main else { return }
        let islandSize = NSSize(width: 480, height: 96)
        let frame = NSRect(
            x: screen.frame.midX - islandSize.width / 2,
            y: screen.frame.minY + 24,
            width: islandSize.width,
            height: islandSize.height
        )
        let island = Self.makeOverlayWindow(frame: frame)
        island.level = .statusBar
        island.contentView = NSHostingView(rootView: IslandView().environmentObject(state))
        island.orderFrontRegardless()
        islandWindow = island
    }

    func hide() {
        vignetteWindows.forEach { $0.orderOut(nil) }
        vignetteWindows = []
        islandWindow?.orderOut(nil)
        islandWindow = nil
    }

    private static func makeOverlayWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        return window
    }
}
