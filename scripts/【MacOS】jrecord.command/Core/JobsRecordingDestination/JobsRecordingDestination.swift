//
//  JobsRecordingDestination.swift
//  JobsWindowRecorder
//
//  Created by Jobs on 2026年11月14日，星期六.
//

import AVFoundation
import Darwin
import Foundation

final class JobsRecordingDestination {

    static let minimumFreeBytes: Int64 = 256 * 1024 * 1024
    let finalURL: URL
    let stagingDirectory: URL
    let stagingURL: URL

    init(finalURL: URL) throws {
        self.finalURL = finalURL
        let manager = FileManager.default
        let parent = finalURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: parent.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              manager.isWritableFile(atPath: parent.path) else {
            throw JobsRecorderFailure("输出目录不存在或不可写。", code: 73)
        }
        var info = stat()
        guard lstat(finalURL.path, &info) != 0, errno == ENOENT else {
            throw JobsRecorderFailure("输出路径已存在，拒绝覆盖文件、目录或符号链接。", code: 73)
        }
        try Self.requireDiskSpace(in: parent)
        stagingDirectory = parent.appendingPathComponent(".JobsWindowRecorder-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: stagingDirectory,
                                    withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        stagingURL = stagingDirectory.appendingPathComponent("recording.mp4")
    }

    static func requireDiskSpace(in directory: URL) throws {
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
        guard let space = attributes[.systemFreeSize] as? NSNumber,
              space.int64Value >= minimumFreeBytes else {
            throw JobsRecorderFailure("可用磁盘空间不足 256 MB，已停止录制准备或正在保存现有片段。", code: 73)
        }
    }

    func discardEmptyStaging() throws {
        let manager = FileManager.default
        guard try manager.contentsOfDirectory(atPath: stagingDirectory.path).isEmpty else {
            return
        }
        try manager.removeItem(at: stagingDirectory)
    }

    func validate() async throws {
        try await JobsAsyncDeadline<Void>.run(seconds: 15, label: "视频完整性校验") {
            let asset = AVURLAsset(url: self.stagingURL)
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let readable = try await asset.load(.isReadable)
            let seconds = duration.seconds
            guard readable, !tracks.isEmpty, seconds.isFinite, seconds > 0 else {
                throw JobsRecorderFailure("暂存视频无有效画面或时长，未发布最终文件。")
            }
        }
    }

    func commit() throws {
        // RENAME_EXCL 在提交瞬间再次保证已有输出不会被覆盖。
        let result = stagingURL.path.withCString { source in
            finalURL.path.withCString { destination in
                renamex_np(source, destination, UInt32(RENAME_EXCL))
            }
        }
        guard result == 0 else {
            throw JobsRecorderFailure("视频已封尾，但最终路径不可用（\(String(cString: strerror(errno)))）；暂存文件保留。", code: 73)
        }
        try? FileManager.default.removeItem(at: stagingDirectory)
    }

    func recoveryDescription() -> String {
        return "暂存内容保留在：\(stagingDirectory.path)"
    }
}
