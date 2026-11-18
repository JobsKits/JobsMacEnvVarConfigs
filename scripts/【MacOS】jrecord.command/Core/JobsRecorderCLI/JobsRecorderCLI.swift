//
//  JobsRecorderCLI.swift
//  JobsWindowRecorder
//
//  Created by Jobs on 2026年11月14日，星期六.
//

import AppKit
import CoreGraphics
import Darwin
import Foundation

@main
struct JobsRecorderCLI {

    @MainActor
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        Task { @MainActor in
            await execute(args)
            exit(0)
        }
        // 录制需要真正的 AppKit 事件循环，透明倒计时才能刷新且不抢焦点。
        if args.first == "record", !args.contains("--help"), !args.contains("-h") {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            app.run()
        } else {
            dispatchMain()
        }
    }

    @MainActor
    private static func execute(_ args: [String]) async {
        if args.isEmpty || args.contains("--help") || args.contains("-h") {
            printHelp()
            return
        }
        if args == ["--version"] {
            print("JobsWindowRecorder 1.0.0")
            return
        }
        guard #available(macOS 15.0, *) else {
            fputs("错误：原生录屏内核需要 MacOS 15 或更高版本，不会自动升级系统。\n", stderr)
            exit(69)
        }
        do {
            let command = args[0]
            let tail = Array(args.dropFirst())
            if command == "doctor", tail.isEmpty {
                try printDoctor()
                return
            }
            if command == "request-permission", tail.isEmpty {
                _ = NSApplication.shared
                _ = CGRequestScreenCaptureAccess()
                try printDoctor()
                if !CGPreflightScreenCaptureAccess() {
                    exit(77)
                }
                return
            }
            if command == "--self-test", tail.isEmpty {
                try await selfTest()
                return
            }
            if command == "list" {
                let selection = try parseSelectionArguments(tail, requiresWindowID: false)
                _ = NSApplication.shared
                try await JobsWindowCatalog.list(browsersOnly: selection.browsersOnly,
                                                 includeAuxiliary: selection.includeAuxiliary)
                return
            }
            if command == "resolve" {
                let selection = try parseSelectionArguments(tail, requiresWindowID: true)
                guard let id = selection.windowID else {
                    throw JobsRecorderFailure("resolve 缺少有效 --window-id。", code: 64)
                }
                _ = NSApplication.shared
                try await JobsWindowCatalog.resolveID(id,
                                                      browsersOnly: selection.browsersOnly,
                                                      includeAuxiliary: selection.includeAuxiliary)
                return
            }
            if command == "record" {
                let options = try JobsRecorderOptions.parse(tail)
                try JobsWindowCatalog.requirePermission()
                let app = NSApplication.shared
                app.setActivationPolicy(.accessory)
                let session = try JobsRecordingSession(options: options)
                let code = try await session.run()
                exit(code)
            }
            throw JobsRecorderFailure("未知命令或参数组合，请使用 --help。", code: 64)
        } catch {
            fputs("错误：\(error.localizedDescription)\n", stderr)
            exit((error as? JobsRecorderFailure)?.code ?? 1)
        }
    }

    private static func parseSelectionArguments(_ arguments: [String],
                                                requiresWindowID: Bool) throws -> (browsersOnly: Bool, includeAuxiliary: Bool, windowID: UInt32?) {
        var seen: Set<String> = []
        var windowID: UInt32?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard seen.insert(argument).inserted else {
                throw JobsRecorderFailure("重复参数：\(argument)", code: 64)
            }
            if argument == "--window-id", requiresWindowID {
                index += 1
                guard index < arguments.count,
                      let id = UInt32(arguments[index]), id > 0 else {
                    throw JobsRecorderFailure("--window-id 必须是正整数。", code: 64)
                }
                windowID = id
            } else if argument != "--browsers" && argument != "--include-auxiliary" {
                throw JobsRecorderFailure("未知窗口选择参数：\(argument)", code: 64)
            }
            index += 1
        }
        guard !requiresWindowID || windowID != nil else {
            throw JobsRecorderFailure("resolve 必须提供 --window-id。", code: 64)
        }
        return (seen.contains("--browsers"), seen.contains("--include-auxiliary"), windowID)
    }

    private static func printDoctor() throws {
        let value: [String: Any] = [
            "screenRecordingAuthorized": CGPreflightScreenCaptureAccess(),
            "macOSVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "engine": "JobsWindowRecorder",
            "version": "1.0.0"
        ]
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private static func printHelp() {
        print("""
        JobsWindowRecorder 1.0.0 — MacOS 15+ 独立窗口录屏内核
        --version
        doctor
        request-permission
        list [--browsers] [--include-auxiliary]
        resolve --window-id ID [--browsers] [--include-auxiliary]
        record --target TOKEN --output /绝对路径/video.mp4
               [--duration 1..86400] [--fps 1..60] [--audio none|system] [--no-cursor]
        --self-test
        list 每行：TOKEN<TAB>WINDOW_ID<TAB>APP<TAB>TITLE<TAB>WIDTHxHEIGHT
        默认列有标题的应用窗口，含最小化或其他桌面的隐藏窗口；--include-auxiliary 额外加入无标题辅助窗口。
        浏览器标签页不是独立捕获窗口；--browsers 只限定应用范围。
        record 默认无声音；Ctrl+C 保存，TERM/HUP 保存后返回信号码。
        system 音频无法保证隔离同一应用其他窗口声音；严格无其他声音请使用 none。
        仅保存所选窗口，绝不降级整屏采集；已有输出拒绝覆盖。
        """)
    }

    private static func selfTestSelection() throws {
        let scenarios: [(Bool, String?, Bool, Bool)] = [
            (true, "正常窗口", false, true),
            (false, "隐藏窗口", false, true),
            (true, nil, false, false),
            (true, "", false, false),
            (true, " \t\n\u{202E}", false, false),
            (false, "", false, false),
            (false, "隐藏窗口", true, true),
            (true, "", true, true),
            (false, nil, true, true)
        ]
        for (visible, title, auxiliary, expected) in scenarios {
            guard JobsWindowCatalog.includesInSelection(isOnScreen: visible,
                                                        title: title,
                                                        includeAuxiliary: auxiliary) == expected else {
                throw JobsRecorderFailure("正常窗口与辅助窗口选择策略校验失败。")
            }
        }
        let normal = try parseSelectionArguments([], requiresWindowID: false)
        guard !normal.browsersOnly, !normal.includeAuxiliary, normal.windowID == nil else {
            throw JobsRecorderFailure("默认列窗参数校验失败。")
        }
        let all = try parseSelectionArguments(["--include-auxiliary", "--browsers"], requiresWindowID: false)
        guard all.browsersOnly, all.includeAuxiliary else {
            throw JobsRecorderFailure("浏览器与辅助窗口开关未独立解析。")
        }
        let resolved = try parseSelectionArguments(["--include-auxiliary", "--window-id", "123", "--browsers"], requiresWindowID: true)
        guard resolved.windowID == 123, resolved.browsersOnly, resolved.includeAuxiliary else {
            throw JobsRecorderFailure("辅助窗口 ID 解析失败。")
        }
        let invalid: [([String], Bool)] = [
            (["--unknown"], false),
            (["--browsers", "--browsers"], false),
            (["--include-auxiliary", "--include-auxiliary"], false),
            (["--window-id", "123"], false),
            ([], true),
            (["--window-id", ""], true),
            (["--window-id", "0"], true),
            (["--window-id", "-1"], true),
            (["--window-id", "nan"], true),
            (["--window-id", "123", "--window-id", "456"], true),
            (["--window-id", "123", "--browsers", "--browsers"], true),
            (["--window-id", "123", "--include-auxiliary", "--include-auxiliary"], true)
        ]
        for (arguments, requiresID) in invalid {
            if (try? parseSelectionArguments(arguments, requiresWindowID: requiresID)) != nil {
                throw JobsRecorderFailure("未知或重复窗口选择参数未被拒绝。")
            }
        }
    }

    private static func selfTest() async throws {
        let token = JobsWindowToken(version: 1,
                                    windowID: 123,
                                    pid: 456,
                                    bundleID: "com.apple.Safari",
                                    processLaunchDate: 1_700_000_000)
        let text = try token.encode()
        guard try JobsWindowToken.decode(text).windowID == 123 else {
            throw JobsRecorderFailure("窗口凭据往返校验失败。")
        }
        let clean = JobsWindowCatalog.sanitized("A\u{001B}[31m\tB\nC\u{202E}")
        guard !clean.contains("\u{001B}"), !clean.contains("\t"), !clean.contains("\n"), !clean.contains("\u{202E}") else {
            throw JobsRecorderFailure("窗口文字控制字符清理失败。")
        }
        let valid = ["--target", text, "--output", "/tmp/jobs-recorder-self-test.mp4"]
        let defaults = try JobsRecorderOptions.parse(valid)
        guard !defaults.capturesAudio, defaults.duration == nil, defaults.fps == 30 else {
            throw JobsRecorderFailure("默认静音或帧率校验失败。")
        }
        let invalidCases: [[String]] = [
            [], ["--target", "bad", "--output", "/tmp/test.mp4"],
            valid + ["--duration", "nan"], valid + ["--duration", "inf"],
            valid + ["--duration", "-1"], valid + ["--duration", "86401"],
            valid + ["--fps", "0"], valid + ["--fps", "61"],
            valid + ["--audio", "both"], valid + ["--audio", ""],
            valid + ["--preset", "broll"], valid + ["--target", text],
            ["--target", text, "--output", "relative.mp4"],
            ["--target", text, "--output", "/tmp/test.mov"]
        ]
        for arguments in invalidCases {
            if (try? JobsRecorderOptions.parse(arguments)) != nil {
                throw JobsRecorderFailure("无效参数未被拒绝：\(arguments.joined(separator: " "))")
            }
        }
        guard (try? JobsWindowToken.decode("")) == nil,
              (try? JobsWindowToken.decode(String(repeating: "a", count: 8193))) == nil else {
            throw JobsRecorderFailure("无效凭据未被拒绝。")
        }
        try selfTestSelection()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("JobsWindowRecorder-self-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: temporary)
        }
        let collisionURL = temporary.appendingPathComponent("collision.mp4")
        let collision = try JobsRecordingDestination(finalURL: collisionURL)
        try Data("new".utf8).write(to: collision.stagingURL)
        try Data("existing".utf8).write(to: collisionURL)
        do {
            try collision.commit()
            throw JobsRecorderFailure("已存在的目标文件被错误覆盖。")
        } catch let error as JobsRecorderFailure where error.code == 73 {
            guard try Data(contentsOf: collisionURL) == Data("existing".utf8),
                  FileManager.default.fileExists(atPath: collision.stagingURL.path) else {
                throw JobsRecorderFailure("输出冲突破坏了原文件或暂存视频。")
            }
        }
        let publishURL = temporary.appendingPathComponent("publish.mp4")
        let publish = try JobsRecordingDestination(finalURL: publishURL)
        try Data("published".utf8).write(to: publish.stagingURL)
        try publish.commit()
        guard try Data(contentsOf: publishURL) == Data("published".utf8),
              !FileManager.default.fileExists(atPath: publish.stagingDirectory.path) else {
            throw JobsRecorderFailure("原子发布或暂存清理校验失败。")
        }
        let linkedURL = temporary.appendingPathComponent("dangling.mp4")
        try FileManager.default.createSymbolicLink(atPath: linkedURL.path, withDestinationPath: temporary.appendingPathComponent("missing").path)
        if (try? JobsRecordingDestination(finalURL: linkedURL)) != nil {
            throw JobsRecorderFailure("悬空符号链接未被拒绝。")
        }
        let result = try await JobsAsyncDeadline<Int>.run(seconds: 1, label: "自测") {
            return 42
        }
        guard result == 42 else {
            throw JobsRecorderFailure("异步成功结果错误。")
        }
        var timedOut = false
        do {
            _ = try await JobsAsyncDeadline<Int>.run(seconds: 0.01, label: "自测") {
                try await Task.sleep(nanoseconds: 100_000_000)
                return 0
            }
        } catch {
            timedOut = true
        }
        guard timedOut else {
            throw JobsRecorderFailure("系统回调超时门闩未生效。")
        }
        print("PASS: token round-trip, control sanitization, silent defaults, 16 invalid argument/token cases, atomic collision protection, exclusive publish, dangling symlink refusal, bounded async callback, normal-window selection and auxiliary opt-in")

    }
}
