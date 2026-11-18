//
//  JobsRecorderOptions.swift
//  JobsWindowRecorder
//
//  Created by Jobs on 2026年11月14日，星期六.
//

import Foundation

struct JobsRecorderOptions {

    let target: JobsWindowToken
    let outputURL: URL
    let duration: Double?
    let fps: Int
    let capturesAudio: Bool
    let showsCursor: Bool

    static func parse(_ arguments: [String]) throws -> Self {
        var values: [String: String] = [:]
        var showsCursor = true
        var index = 0
        let known = ["--target", "--output", "--duration", "--fps", "--audio"]
        while index < arguments.count {
            let option = arguments[index]
            if option == "--no-cursor" {
                guard showsCursor else {
                    throw JobsRecorderFailure("重复参数：--no-cursor", code: 64)
                }
                showsCursor = false
            } else {
                guard known.contains(option), values[option] == nil else {
                    throw JobsRecorderFailure("未知或重复参数：\(option)", code: 64)
                }
                index += 1
                guard index < arguments.count,
                      !arguments[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw JobsRecorderFailure("参数缺少有效值：\(option)", code: 64)
                }
                values[option] = arguments[index]
            }
            index += 1
        }
        guard let encoded = values["--target"], let path = values["--output"], path.hasPrefix("/") else {
            throw JobsRecorderFailure("record 必须提供 --target 和绝对 --output 路径。", code: 64)
        }
        guard URL(fileURLWithPath: path).pathExtension.lowercased() == "mp4" else {
            throw JobsRecorderFailure("输出文件必须使用 .mp4 后缀。", code: 64)
        }
        let fpsString = values["--fps"] ?? "30"
        guard let fps = Int(fpsString), (1...60).contains(fps) else {
            throw JobsRecorderFailure("帧率必须是 1 至 60 的整数。", code: 64)
        }
        var duration: Double?
        if let text = values["--duration"] {
            guard let seconds = Double(text), seconds.isFinite, seconds > 0, seconds <= 86400 else {
                throw JobsRecorderFailure("录制时长必须大于 0 且不超过 86400 秒。", code: 64)
            }
            duration = seconds
        }
        let audio = values["--audio"] ?? "none"
        guard audio == "none" || audio == "system" else {
            throw JobsRecorderFailure("音频只能是 none 或 system。", code: 64)
        }
        return Self(target: try JobsWindowToken.decode(encoded),
                    outputURL: URL(fileURLWithPath: path).standardizedFileURL,
                    duration: duration,
                    fps: fps,
                    capturesAudio: audio == "system",
                    showsCursor: showsCursor)
    }
}
