import AppKit
import Combine
import CoreGraphics
import SwiftUI

/// Narrow AppKit bridge for a read-only, non-activating presentation surface.
/// SwiftUI owns all display values; this controller owns only the NSPanel.
@MainActor
final class ControllerHUDPanelController: ObservableObject {
    private var panel: NonActivatingHUDPanel?
    private var hostingView: NSHostingView<ControllerHUDView>?

    func update(
        runtimeState: ControllerHUDRuntimeState,
        language: ControllerHUDLanguage = .current
    ) {
        update(
            presentation: ControllerHUDPresentation.resolve(from: runtimeState),
            language: language
        )
    }

    func update(
        presentation: ControllerHUDPresentation,
        language: ControllerHUDLanguage
    ) {
        guard presentation.isVisible else {
            hide()
            return
        }

        let panel = makePanelIfNeeded()
        let view = ControllerHUDView(
            presentation: presentation,
            language: language
        )
        hostingView?.rootView = view
        let fittingSize = hostingView?.fittingSize ?? NSSize(width: 300, height: 120)
        panel.setContentSize(fittingSize)
        guard position(panel, size: fittingSize) else {
            hide()
            return
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanelIfNeeded() -> NonActivatingHUDPanel {
        if let panel { return panel }

        let panel = NonActivatingHUDPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = true

        let hostingView = NSHostingView(
            rootView: ControllerHUDView(
                presentation: ControllerHUDPresentation(
                    isVisible: false,
                    actions: []
                ),
                language: .current
            )
        )
        panel.contentView = hostingView
        self.panel = panel
        self.hostingView = hostingView
        return panel
    }

    private func position(_ panel: NSPanel, size: NSSize) -> Bool {
        guard let codexFrame = currentCodexWindowFrame(),
              let screen = NSScreen.screens.first(where: {
                  $0.frame.intersects(codexFrame)
              }) else {
            return false
        }

        let frame = screen.visibleFrame
        let desiredX = codexFrame.midX - size.width / 2
        let desiredY = codexFrame.maxY - size.height - 16
        panel.setFrameOrigin(
            NSPoint(
                x: min(max(desiredX, frame.minX), frame.maxX - size.width),
                y: min(max(desiredY, frame.minY), frame.maxY - size.height)
            )
        )
        return true
    }

    /// Reads only public window geometry for the verified Codex PID. It never
    /// uses the result for input delivery or clicking; failure simply hides
    /// the HUD.
    private func currentCodexWindowFrame() -> NSRect? {
        guard let codex = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.openai.codex"
        ).first,
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]],
        let primaryHeight = NSScreen.screens.first?.frame.height else {
            return nil
        }

        return windows.compactMap { item -> NSRect? in
            guard (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ==
                    codex.processIdentifier,
                  (item[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = item[kCGWindowBounds as String] as? [String: Any],
                  let quartzRect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  quartzRect.width >= 320,
                  quartzRect.height >= 240 else {
                return nil
            }
            return NSRect(
                x: quartzRect.minX,
                y: primaryHeight - quartzRect.minY - quartzRect.height,
                width: quartzRect.width,
                height: quartzRect.height
            )
        }.max(by: { $0.width * $0.height < $1.width * $1.height })
    }
}

private final class NonActivatingHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
