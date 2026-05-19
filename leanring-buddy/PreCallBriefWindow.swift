//
//  PreCallBriefWindow.swift
//  leanring-buddy
//
//  Non-activating floating NSPanel that shows the pre-call brief.
//  Positioned top-right of the primary screen, stays on top without
//  stealing keyboard focus from whatever the rep is doing.
//

import AppKit
import SwiftUI

final class PreCallBriefWindow: NSPanel {

    private static let windowWidth: CGFloat = 320
    private static let windowHeight: CGFloat = 210

    init(brief: PreCallBrief) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.windowWidth, height: Self.windowHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true

        let view = PreCallBriefView(brief: brief) {
            self.close()
        }
        .frame(width: Self.windowWidth, height: Self.windowHeight)

        contentView = NSHostingView(rootView: view)
        positionTopRight()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        orderFront(nil)
        animator().alphaValue = 1
    }

    override func close() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            self.animator().alphaValue = 0
        }, completionHandler: {
            super.close()
        })
    }

    private func positionTopRight() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.maxX - Self.windowWidth - 16
        let y = screenFrame.maxY - Self.windowHeight - 8
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}
