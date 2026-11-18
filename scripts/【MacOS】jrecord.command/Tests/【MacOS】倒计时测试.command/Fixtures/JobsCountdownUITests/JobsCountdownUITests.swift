//
//  JobsCountdownUITests.swift
//  JobsCountdownUITests
//
//  Created by Jobs on 2026年11月14日，星期六.
//

import AppKit
import CoreGraphics
import Darwin
import Foundation
import QuartzCore

@main
@MainActor
struct JobsCountdownUITests {

    private static var assertions = 0

    static func main() {
        if CommandLine.arguments.contains("--lifetime") {
            lifetimeCase()
        }
        let previousFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                if CommandLine.arguments.contains("--signal") {
                    try await signalCase()
                } else {
                    try await run(previousFrontmost: previousFrontmost)
                    print("PASS: \(assertions) countdown assertions")
                }
                exit(0)
            } catch {
                fputs("FAIL: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        application.run()
    }

    private static func lifetimeCase() -> Never {
        signal(SIGPIPE, SIG_IGN)
        signal(SIGHUP, SIG_IGN)
        let path = CommandLine.arguments.last!
        let monitor = JobsRecordingLifetime { reason in
            try? reason.write(toFile: path, atomically: true, encoding: .utf8)
            exit(129)
        }
        fputs("LIFETIME_READY\n", stdout)
        fflush(stdout)
        return withExtendedLifetime(monitor) {
            dispatchMain()
        }
    }

    private static func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
        assertions += 1
        guard value() else {
            throw JobsRecorderFailure(message)
        }
    }

    private static func visiblePanels() -> [JobsCountdownPanel] {
        return NSApplication.shared.windows.compactMap { $0 as? JobsCountdownPanel }.filter(\.isVisible)
    }

    private static func number(in panel: JobsCountdownPanel) -> String? {
        let badge = panel.contentView?.layer?.sublayers?.first
        let text = badge?.sublayers?.compactMap { $0 as? CATextLayer }.first
        return (text?.string as? NSAttributedString)?.string
    }

    private static func saveOwnLayer(_ panel: JobsCountdownPanel, name: String) throws {
        guard CommandLine.arguments.count >= 2,
              let layer = panel.contentView?.layer?.presentation() else {
            return
        }
        let scale: CGFloat = 2
        guard let context = CGContext(data: nil, width: 1000, height: 1000,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw JobsRecorderFailure("无法创建仅倒计时图层的预览上下文。")
        }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 250 - layer.bounds.midX, y: 250 - layer.bounds.midY)
        layer.render(in: context)
        guard let image = context.makeImage(),
              let bytes = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw JobsRecorderFailure("无法导出倒计时图层预览。")
        }
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try bytes.write(to: folder.appendingPathComponent(name))
    }

    private static func postClick(at point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point,
                mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point,
                mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point,
                mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private static func run(previousFrontmost: pid_t?) async throws {
        try require(!NSScreen.screens.isEmpty, "测试需要已连接的图形会话。")
        let fixture = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 440),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        fixture.isReleasedWhenClosed = false
        fixture.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        fixture.hidesOnDeactivate = false
        fixture.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        fixture.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 1)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        fixture.setFrameOrigin(NSPoint(x: screen.frame.midX - 220, y: screen.frame.midY - 220))
        let clickView = JobsCountdownClickView(frame: NSRect(origin: .zero, size: fixture.frame.size))
        fixture.contentView = clickView
        fixture.orderFrontRegardless()
        defer {
            fixture.orderOut(nil)
            fixture.close()
        }

        let existingKey = NSApplication.shared.keyWindow
        let canPost = CGPreflightPostEventAccess()
        let oldMouse = CGEvent(source: nil)?.location
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let clickPoint = CGPoint(x: screen.frame.midX, y: primaryHeight - screen.frame.midY)
        var digits: [String] = []
        var opacities: [Float] = []
        var scales: [Double] = []
        var mousePosted = false
        var pulseSaved = false
        var fadeSaved = false
        var finished = false
        var monitorError: Error?
        let start = ProcessInfo.processInfo.systemUptime
        let monitor = Task { @MainActor in
            while !Task.isCancelled && !finished {
                do {
                    let panels = visiblePanels()
                    if !panels.isEmpty {
                        try require(panels.count == NSScreen.screens.count, "每个已连接屏幕应有一个倒计时面板。")
                        try require(NSApplication.shared.keyWindow === existingKey, "倒计时抢走了键盘窗口。")
                        // 用户可以在倒计时中切换应用；只禁止提示层激活自己的进程。
                        try require(NSWorkspace.shared.frontmostApplication?.processIdentifier != getpid(),
                                    "倒计时提示进程成为了前台应用。")
                        for panel in panels {
                            try require(panel.ignoresMouseEvents && !panel.canBecomeKey && !panel.canBecomeMain,
                                        "面板未保持鼠标穿透或不可成为焦点。")
                            try require(NSScreen.screens.contains(where: { $0.frame == panel.frame }), "面板未覆盖真实全屏范围。")
                            try require(panel.contentView?.hitTest(.zero) == nil, "内容视图意外接收点击。")
                            let badge = panel.contentView?.layer?.sublayers?.first
                            try require(badge?.sublayers?.compactMap { $0 as? CAShapeLayer }.count == 2,
                                        "数字外应当恰好有两圈。")
                        }
                        if let panel = panels.first, let digit = number(in: panel) {
                            if digits.last != digit {
                                digits.append(digit)
                            }
                            if digit == "5", let badge = panel.contentView?.layer?.sublayers?.first?.presentation() {
                                opacities.append(badge.opacity)
                                if let scale = badge.value(forKeyPath: "transform.scale") as? Double {
                                    scales.append(scale)
                                }
                            }
                            let elapsed = ProcessInfo.processInfo.systemUptime - start
                            if !pulseSaved && elapsed > 0.16 {
                                try saveOwnLayer(panel, name: "countdown-pulse.png")
                                pulseSaved = true
                            }
                            if !fadeSaved && elapsed > 0.81 {
                                try saveOwnLayer(panel, name: "countdown-fade.png")
                                fadeSaved = true
                            }
                            if canPost && !mousePosted && elapsed > 0.35 {
                                postClick(at: clickPoint)
                                mousePosted = true
                            }
                        }
                    }
                    try await Task.sleep(nanoseconds: 20_000_000)
                } catch is CancellationError {
                    return
                } catch {
                    monitorError = error
                    return
                }
            }
        }
        let completed = try await JobsRecordingCountdown.play { false }
        finished = true
        monitor.cancel()
        await monitor.value
        if let oldMouse, mousePosted {
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                    mouseCursorPosition: oldMouse, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        if let monitorError {
            throw monitorError
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        try require(completed && elapsed >= 5 && elapsed < 5.6, "倒计时未按约5秒完成。")
        try require(digits == ["5", "4", "3", "2", "1"], "实际显示数字序列错误：\(digits)。")
        try require(visiblePanels().isEmpty, "完成后仍残留倒计时窗口。")
        try require((opacities.max() ?? 0) > 0.9 && (opacities.min() ?? 1) < 0.2,
                    "未观察到实际图层淡出。")
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            try require((scales.max() ?? 0) - (scales.min() ?? 0) > 0.08, "未观察到实际心跳缩放。")
        }
        if canPost {
            try require(mousePosted && clickView.clicks == 1, "倒计时覆盖时底层自建窗口未收到唯一真实点击。")
            print("PASS: real mouse click passed through overlay")
        } else {
            print("SKIP: actual mouse click; existing event-post permission unavailable, no permission requested")
        }
        print("OBSERVED: digits=\(digits.joined(separator: ",")) seconds=\(String(format: "%.3f", elapsed))")

        let preCancelled = try await JobsRecordingCountdown.play { true }
        try require(!preCancelled && visiblePanels().isEmpty, "已取消的倒计时仍显示或未清理。")
        let cancelStart = ProcessInfo.processInfo.systemUptime
        let midCancelled = try await JobsRecordingCountdown.play {
            ProcessInfo.processInfo.systemUptime - cancelStart >= 1.3
        }
        try require(!midCancelled && visiblePanels().isEmpty, "中途取消未清理窗口。")
        try require(ProcessInfo.processInfo.systemUptime - cancelStart < 1.5, "中途取消反应超过200ms。")
        let task = Task { @MainActor in
            try await JobsRecordingCountdown.play { false }
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        do {
            _ = try await task.value
            throw JobsRecorderFailure("Task取消未传播。")
        } catch is CancellationError {
            try require(visiblePanels().isEmpty, "Task取消后仍残留倒计时面板。")
        }
    }

    private static func signalCase() async throws {
        let start = ProcessInfo.processInfo.systemUptime
        var sources: [DispatchSourceSignal] = []
        let stopped = JobsCountdownTestState()
        for number in [SIGINT, SIGTERM, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler {
                stopped.set(number)
            }
            source.resume()
            sources.append(source)
        }
        defer {
            for source in sources {
                source.cancel()
            }
        }
        fputs("COUNTDOWN_READY\n", stdout)
        fflush(stdout)
        let completed = try await JobsRecordingCountdown.play { stopped.get() != 0 }
        try require(!completed && visiblePanels().isEmpty, "真实信号未取消倒计时或未清理面板。")
        try require(ProcessInfo.processInfo.systemUptime - start < 3, "信号取消后等待过长。")
        print("SIGNAL_CLEANED:\(stopped.get())")
        fflush(stdout)
        exit(128 + stopped.get())
    }
}
