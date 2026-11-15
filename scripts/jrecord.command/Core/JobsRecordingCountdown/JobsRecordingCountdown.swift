//
//  JobsRecordingCountdown.swift
//  JobsWindowRecorder
//
//  Created by Jobs on 2026年11月14日，星期六.
//

import AppKit
import Foundation
import QuartzCore

/// 倒计时只负责提示；采集在窗口全部移除并再次验证原目标后才启动。
@MainActor
final class JobsRecordingCountdown {

    static let seconds = 5

    static func play(isCancelled: @escaping @Sendable () -> Bool) async throws -> Bool {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            throw JobsRecorderFailure("未发现可显示倒计时的屏幕，已取消录制。", code: 69)
        }
        let panels = screens.map { JobsCountdownPanel(screen: $0) }
        defer {
            for panel in panels {
                panel.orderOut(nil)
                panel.close()
            }
            CATransaction.flush()
        }
        guard !isCancelled() else {
            return false
        }
        for panel in panels {
            panel.show(number: seconds)
            panel.orderFrontRegardless()
        }
        CATransaction.flush()
        let start = ProcessInfo.processInfo.systemUptime
        var lastNumber = seconds
        while true {
            try Task.checkCancellation()
            if isCancelled() {
                return false
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            if elapsed >= Double(seconds) {
                return true
            }
            let number = seconds - Int(elapsed)
            if number != lastNumber {
                for panel in panels {
                    panel.show(number: number)
                }
                lastNumber = number
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
