//
//  JobsCountdownPanel.swift
//  JobsWindowRecorder
//
//  Created by Jobs on 2026年11月14日，星期六.
//

import AppKit

/// 提示窗不接收鼠标或键盘，桌面和全屏应用继续使用原有焦点。
@MainActor
final class JobsCountdownPanel: NSPanel {

    override var canBecomeKey: Bool {
        return false
    }

    override var canBecomeMain: Bool {
        return false
    }

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isFloatingPanel = true
        animationBehavior = .none
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = JobsCountdownView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                        scale: screen.backingScaleFactor)
    }

    func show(number: Int) {
        (contentView as? JobsCountdownView)?.show(number: number)
    }
}
