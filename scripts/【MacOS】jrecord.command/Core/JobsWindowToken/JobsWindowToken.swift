//
//  JobsWindowToken.swift
//  JobsWindowRecorder
//
//  Created by Jobs on 2026年11月14日，星期六.
//

import Foundation

struct JobsWindowToken: Codable {

    let version: Int
    let windowID: UInt32
    let pid: Int32
    let bundleID: String
    let processLaunchDate: Double

    func encode() throws -> String {
        return try JSONEncoder().encode(self).base64EncodedString()
    }

    static func decode(_ text: String) throws -> Self {
        guard text.utf8.count <= 8192,
              let data = Data(base64Encoded: text),
              let result = try? JSONDecoder().decode(Self.self, from: data),
              result.version == 1,
              result.windowID > 0,
              result.pid > 0,
              !result.bundleID.isEmpty,
              result.processLaunchDate.isFinite,
              result.processLaunchDate > 0 else {
            throw JobsRecorderFailure("窗口凭据无效，请重新列出并选择窗口。", code: 64)
        }
        return result
    }
}
