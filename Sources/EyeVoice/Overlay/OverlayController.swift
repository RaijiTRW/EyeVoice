import AppKit
import Combine
import SwiftUI

/// Click-through overlay: edge vignette and the bottom island on every screen/Space.
final class OverlayController {
    private var vignetteWindows: [NSPanel] = []
    private var islandWindows: [NSPanel] = []
    private var observers: [NSObjectProtocol] = []
    private var dimmingCancellable: AnyCancellable?
    private var collapseCancellable: AnyCancellable?
    private weak var state: AppState?

    func show(state: AppState) {
        hide()
        self.state = state
        createWindows(state: state)
        observeDisplayChanges()
        observeDimming(state: state)
        observeCollapse(state: state)
    }

    private func createWindows(state: AppState) {
        for screen in NSScreen.screens {
            let window = Self.makeOverlayWindow(frame: screen.frame, interactive: false)
            window.contentView = NSHostingView(rootView: VignetteView())
            window.alphaValue = state.dimmingEnabled ? 1 : 0
            window.orderFrontRegardless()
            vignetteWindows.append(window)
        }

        for screen in NSScreen.screens {
            let frame = Self.islandFrame(for: screen, collapsed: state.overlayCollapsed)
            let island = Self.makeOverlayWindow(frame: frame, interactive: true)
            island.contentView = NSHostingView(
                rootView: IslandView()
                    .environmentObject(state)
                    .environmentObject(state.meter)
            )
            island.orderFrontRegardless()
            islandWindows.append(island)
        }
    }

    func hide() {
        vignetteWindows.forEach { $0.orderOut(nil) }
        vignetteWindows = []
        islandWindows.forEach { $0.orderOut(nil) }
        islandWindows = []
        observers.forEach { token in
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        observers = []
        dimmingCancellable?.cancel()
        dimmingCancellable = nil
        collapseCancellable?.cancel()
        collapseCancellable = nil
        state = nil
    }

    private func observeDimming(state: AppState) {
        dimmingCancellable = state.$dimmingEnabled
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    self.vignetteWindows.forEach { window in
                        if enabled { window.orderFrontRegardless() }
                        window.animator().alphaValue = enabled ? 1 : 0
                    }
                }
            }
    }

    private func observeCollapse(state: AppState) {
        collapseCancellable = state.$overlayCollapsed
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] collapsed in
                guard let self else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.24
                    for window in self.islandWindows {
                        guard let screen = window.screen ?? NSScreen.main else { continue }
                        let frame = Self.islandFrame(for: screen, collapsed: collapsed)
                        window.animator().setFrame(frame, display: true)
                    }
                }
            }
    }

    private static func islandFrame(for screen: NSScreen, collapsed: Bool) -> NSRect {
        let size = collapsed
            ? NSSize(width: 64, height: 26)
            : NSSize(width: min(520, screen.visibleFrame.width - 32), height: 124)
        return NSRect(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + 8,
            width: size.width,
            height: size.height
        )
    }

    private func observeDisplayChanges() {
        let screens = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let state = self.state else { return }
            self.vignetteWindows.forEach { $0.orderOut(nil) }
            self.islandWindows.forEach { $0.orderOut(nil) }
            self.vignetteWindows = []
            self.islandWindows = []
            self.createWindows(state: state)
        }
        observers.append(screens)

        let spaces = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Reassert the level after Mission Control/full-screen transitions.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self?.vignetteWindows.forEach { $0.orderFrontRegardless() }
                self?.islandWindows.forEach { $0.orderFrontRegardless() }
            }
        }
        observers.append(spaces)
    }

    private static func makeOverlayWindow(frame: NSRect, interactive: Bool) -> NSPanel {
        let window = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = !interactive
        window.hidesOnDeactivate = false
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        return window
    }
}
