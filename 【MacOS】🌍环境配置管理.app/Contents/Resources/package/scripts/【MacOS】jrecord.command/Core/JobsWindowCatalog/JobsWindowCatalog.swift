//
//  JobsWindowCatalog.swift
//  JobsWindowRecorder
//
//  Created by Jobs on 2026年11月14日，星期六.
//

import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum JobsWindowCatalog {

    private static let browserBundles: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Canary", "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly",
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
        "company.thebrowser.Browser", "company.thebrowser.dia", "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi", "com.kagi.kagimacOS", "app.zen-browser.zen"
    ]

    static func requirePermission() throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw JobsRecorderFailure("尚未授予屏幕录制权限；请在系统设置中授权启动本工具的终端。", code: 77)
        }
    }

    static func content() async throws -> SCShareableContent {
        try requirePermission()
        return try await JobsAsyncDeadline.run(seconds: 15, label: "窗口枚举") {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        }
    }

    static func sanitized(_ text: String) -> String {
        let forbidden = CharacterSet.controlCharacters
            .union(CharacterSet(charactersIn: "\u{061C}\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}"))
        let scalars = text.unicodeScalars.map { forbidden.contains($0) ? " " : String($0) }
        return scalars.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isBrowser(_ bundleID: String) -> Bool {
        return browserBundles.contains(bundleID)
    }

    static func token(for window: SCWindow) throws -> JobsWindowToken {
        guard window.windowLayer == 0,
              window.frame.width >= 2,
              window.frame.height >= 2,
              window.frame.width < 1_000_000,
              window.frame.height < 1_000_000,
              window.frame.width.isFinite,
              window.frame.height.isFinite,
              let owner = window.owningApplication,
              !owner.bundleIdentifier.isEmpty,
              let process = NSRunningApplication(processIdentifier: owner.processID),
              !process.isTerminated,
              process.bundleIdentifier == owner.bundleIdentifier,
              let launch = process.launchDate else {
            throw JobsRecorderFailure("该窗口已关闭或不支持独立录制，请重新选择。")
        }
        return JobsWindowToken(version: 1,
                               windowID: window.windowID,
                               pid: owner.processID,
                               bundleID: owner.bundleIdentifier,
                               processLaunchDate: launch.timeIntervalSince1970)
    }

    /// 只限定启动前的候选列表；录制中的身份复核仍可见完整窗口集合。
    static func includesInSelection(isOnScreen: Bool,
                                    title: String?,
                                    includeAuxiliary: Bool) -> Bool {
        return includeAuxiliary || !sanitized(title ?? "").isEmpty
    }

    static func windows(in content: SCShareableContent,
                        browsersOnly: Bool,
                        includeAuxiliary: Bool = false) -> [SCWindow] {
        return content.windows.filter { window in
            guard let candidate = try? token(for: window) else {
                return false
            }
            guard !browsersOnly || isBrowser(candidate.bundleID) else {
                return false
            }
            return includesInSelection(isOnScreen: window.isOnScreen,
                                       title: window.title,
                                       includeAuxiliary: includeAuxiliary)
        }.sorted { lhs, rhs in
            let left = lhs.owningApplication?.applicationName ?? ""
            let right = rhs.owningApplication?.applicationName ?? ""
            if left != right {
                return left.localizedStandardCompare(right) == .orderedAscending
            }
            return lhs.windowID < rhs.windowID
        }
    }

    static func resolve(_ token: JobsWindowToken, in content: SCShareableContent) throws -> SCWindow {
        guard let window = content.windows.first(where: { $0.windowID == token.windowID }),
              let actual = try? self.token(for: window),
              actual.pid == token.pid,
              actual.bundleID == token.bundleID,
              abs(actual.processLaunchDate - token.processLaunchDate) < 0.001 else {
            throw JobsRecorderFailure("目标窗口已关闭或身份已变化；已拒绝改录其他窗口。")
        }
        return window
    }

    static func list(browsersOnly: Bool, includeAuxiliary: Bool = false) async throws {
        let current = try await content()
        for window in windows(in: current,
                              browsersOnly: browsersOnly,
                              includeAuxiliary: includeAuxiliary) {
            let token = try token(for: window)
            let appText = sanitized(window.owningApplication?.applicationName ?? "")
            let app = appText.isEmpty ? token.bundleID : appText
            let titleText = sanitized(window.title ?? "")
            var labels = ""
            if !window.isOnScreen {
                labels += "[隐藏]"
            }
            if includeAuxiliary && titleText.isEmpty {
                labels += "[无标题]"
            }
            let title = labels + (titleText.isEmpty ? "辅助窗口" : titleText)
            print("\(try token.encode())\t\(window.windowID)\t\(app)\t\(title)\t\(Int(window.frame.width))x\(Int(window.frame.height))")
        }
    }

    static func resolveID(_ id: UInt32,
                          browsersOnly: Bool,
                          includeAuxiliary: Bool = false) async throws {
        let current = try await content()
        let matching = windows(in: current,
                               browsersOnly: browsersOnly,
                               includeAuxiliary: includeAuxiliary).filter { $0.windowID == id }
        guard matching.count == 1, let window = matching.first else {
            let detail = includeAuxiliary ? "请重新列出窗口。" : "无标题辅助窗口需要显式使用 --include-auxiliary。"
            throw JobsRecorderFailure("未找到指定 ID 的可选窗口；" + detail)
        }
        print(try token(for: window).encode())
    }
}
