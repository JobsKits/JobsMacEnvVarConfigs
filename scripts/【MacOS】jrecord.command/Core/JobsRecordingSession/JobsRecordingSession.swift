//
//  JobsRecordingSession.swift
//  JobsWindowRecorder
//
//  Created by Jobs on 2026年11月14日，星期六.
//

import AVFoundation
import CoreMedia
import CoreVideo
import Darwin
import Foundation
import ScreenCaptureKit

@available(macOS 15.0, *)
final class JobsRecordingSession: NSObject,
                                  SCStreamDelegate,
                                  SCStreamOutput,
                                  SCRecordingOutputDelegate,
                                  @unchecked Sendable {

    private let options: JobsRecorderOptions
    private let destination: JobsRecordingDestination
    private let lock = NSLock()
    private let sampleQueue = DispatchQueue(label: "JobsWindowRecorder.frame-health")
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var signals: [DispatchSourceSignal] = []
    private var completeFrames = 0
    private var didStartOutput = false
    private var didFinishOutput = false
    private var failure: Error?
    private var stopReason: String?
    private var exitCode: Int32 = 0
    private var isStopping = false

    init(options: JobsRecorderOptions) throws {
        self.options = options
        self.destination = try JobsRecordingDestination(finalURL: options.outputURL)
        super.init()
    }

    func run() async throws -> Int32 {
        installSignals()
        let lifetime = JobsRecordingLifetime { [weak self] reason in
            self?.requestStop(reason: reason, code: 129)
        }
        defer {
            lifetime.cancel()
            for source in signals {
                source.cancel()
            }
        }
        do {
            let initialContent = try await JobsWindowCatalog.content()
            _ = try JobsWindowCatalog.resolve(options.target, in: initialContent)
            fputs("5 秒倒计时；鼠标可正常点击，Ctrl+C 取消录制。\n", stderr)
            let completed = try await JobsRecordingCountdown.play { [self] in
                return snapshot().reason != nil
            }
            if !completed {
                return try cancellationBeforeCapture() ?? 130
            }
            // 倒计时期间允许操作桌面，必须重新核对目标身份、尺寸和磁盘。
            let content = try await JobsWindowCatalog.content()
            let window = try JobsWindowCatalog.resolve(options.target, in: content)
            try JobsRecordingDestination.requireDiskSpace(in: destination.stagingDirectory)
            if let code = try cancellationBeforeCapture() {
                return code
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = try makeConfiguration(window: window, filter: filter)
            let capture = SCStream(filter: filter, configuration: config, delegate: self)
            let recordingConfig = SCRecordingOutputConfiguration()
            recordingConfig.outputURL = destination.stagingURL
            recordingConfig.outputFileType = .mp4
            recordingConfig.videoCodecType = .h264
            let recording = SCRecordingOutput(configuration: recordingConfig, delegate: self)
            try capture.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            try capture.addRecordingOutput(recording)
            stream = capture
            output = recording
            if let earlyFailure = snapshot().failure {
                throw earlyFailure
            }
            if let code = try cancellationBeforeCapture() {
                return code
            }
            try await JobsAsyncDeadline<Void>.run(seconds: 20, label: "录制启动") {
                try await capture.startCapture()
            }
            fputs("正在等待有效画面；Ctrl+C 停止并保存。\n", stderr)
            if options.capturesAudio {
                fputs("音频说明：system 由系统采集，无法保证隔离同一应用其他窗口声音；严格静音请使用 none。\n", stderr)
            }
            await watchRecording()
            try await finish()
            return snapshot().code
        } catch {
            await attemptStopAfterFailure()
            fputs("\(destination.recoveryDescription())\n", stderr)
            throw error
        }
    }

    private func cancellationBeforeCapture() throws -> Int32? {
        let state = snapshot()
        guard state.reason != nil else {
            return nil
        }
        try destination.discardEmptyStaging()
        fputs("录制在采集前已取消，未开始录制。\n", stderr)
        return state.code == 0 ? 130 : state.code
    }

    private func makeConfiguration(window: SCWindow, filter: SCContentFilter) throws -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let scale = Double(filter.pointPixelScale)
        let nativeWidth = window.frame.width * scale
        let nativeHeight = window.frame.height * scale
        guard scale.isFinite, scale > 0,
              nativeWidth.isFinite, nativeHeight.isFinite,
              nativeWidth >= 2, nativeHeight >= 2 else {
            throw JobsRecorderFailure("窗口像素尺寸不可用，请把窗口放回已连接显示器后重试。")
        }
        let proportion = min(1, 3840 / max(nativeWidth, nativeHeight))
        config.width = max(2, Int(nativeWidth * proportion) / 2 * 2)
        config.height = max(2, Int(nativeHeight * proportion) / 2 * 2)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.fps))
        config.queueDepth = 5
        config.showsCursor = options.showsCursor
        config.capturesAudio = options.capturesAudio
        config.captureMicrophone = false
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.preservesAspectRatio = true
        config.scalesToFit = true
        config.ignoreShadowsSingleWindow = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        return config
    }

    private func installSignals() {
        // 终端或日志管道提前关闭时，EPIPE 不应打断视频封尾。
        signal(SIGPIPE, SIG_IGN)
        for number in [SIGINT, SIGTERM, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { [weak self] in
                self?.requestStop(reason: "收到结束信号", code: number == SIGINT ? 0 : 128 + number)
            }
            source.resume()
            signals.append(source)
        }
    }

    private func requestStop(reason: String, code: Int32 = 0, error: Error? = nil) {
        lock.lock()
        if let error, failure == nil {
            failure = error
        }
        if stopReason == nil {
            stopReason = reason
            exitCode = code
        }
        lock.unlock()
    }

    private func snapshot() -> (frames: Int, started: Bool, finished: Bool, reason: String?, code: Int32, failure: Error?) {
        lock.lock()
        defer {
            lock.unlock()
        }
        return (completeFrames, didStartOutput, didFinishOutput, stopReason, exitCode, failure)
    }

    private func watchRecording() async {
        let start = ProcessInfo.processInfo.systemUptime
        var nextInspection = start
        var disappeared = 0
        var reportedFirstFrame = false
        while snapshot().reason == nil {
            let now = ProcessInfo.processInfo.systemUptime
            let state = snapshot()
            if !reportedFirstFrame, state.started, state.frames > 0 {
                fputs("已收到有效画面，正在录制。\n", stderr)
                reportedFirstFrame = true
            }
            if (!state.started || state.frames == 0), now - start > 15 {
                requestStop(reason: "首帧超时", error: JobsRecorderFailure("15 秒内未收到有效首帧，已停止录制。"))
                break
            }
            if let duration = options.duration, now - start >= duration {
                requestStop(reason: "达到设定时长")
                break
            }
            if now >= nextInspection {
                nextInspection = now + 2
                do {
                    try JobsRecordingDestination.requireDiskSpace(in: destination.stagingDirectory)
                    let current = try await JobsWindowCatalog.content()
                    if (try? JobsWindowCatalog.resolve(options.target, in: current)) == nil {
                        disappeared += 1
                        if disappeared >= 2 {
                            requestStop(reason: "目标窗口已关闭")
                        }
                    } else {
                        disappeared = 0
                    }
                } catch {
                    requestStop(reason: "录制环境检查失败", error: error)
                }
            }
            // 静态页面会输出 idle 帧，不能把文件暂时不增长误判成录制故障。
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func markStopping() {
        lock.lock()
        isStopping = true
        lock.unlock()
    }

    private func finish() async throws {
        markStopping()
        if let capture = stream {
            do {
                try await JobsAsyncDeadline<Void>.run(seconds: 15, label: "停止采集") {
                    try await capture.stopCapture()
                }
            } catch {
                // 系统已确认文件封尾时，重复 stop 的“已停止”错误不破坏有效视频。
                let native = error as NSError
                let sourceEnded = snapshot().reason == "目标窗口采集源已结束"
                let alreadyStopped = native.domain == SCStreamErrorDomain
                    && native.code == SCStreamError.Code.attemptToStopStreamState.rawValue
                if !snapshot().finished, !(sourceEnded && alreadyStopped) {
                    throw error
                }
            }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 15
        while !snapshot().finished, snapshot().failure == nil, ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let state = snapshot()
        if let failure = state.failure {
            throw failure
        }
        guard state.finished else {
            throw JobsRecorderFailure("视频封尾超时，未发布最终文件。")
        }
        guard state.frames > 0 else {
            throw JobsRecorderFailure("未收到有效画面，未发布最终文件。")
        }
        try await destination.validate()
        try destination.commit()
        fputs("已保存：\(destination.finalURL.path)\n结束原因：\(state.reason ?? "采集结束")\n", stderr)
    }

    private func attemptStopAfterFailure() async {
        markStopping()
        guard stream != nil else {
            return
        }
        if let capture = stream {
            try? await JobsAsyncDeadline<Void>.run(seconds: 10, label: "失败后停止采集") {
                try await capture.stopCapture()
            }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while !snapshot().finished, ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock()
        let stopping = isStopping
        lock.unlock()
        if !stopping {
            let native = error as NSError
            // 关闭独立窗口会先触发 noCaptureSource；已有有效帧仍须正常封尾保存。
            if native.domain == SCStreamErrorDomain,
               native.code == SCStreamError.Code.noCaptureSource.rawValue {
                requestStop(reason: "目标窗口采集源已结束")
                return
            }
            requestStop(reason: "采集流错误", error: JobsRecorderFailure("采集流已中断：\(error.localizedDescription)"))
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferGetImageBuffer(sampleBuffer) != nil,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete else {
            return
        }
        lock.lock()
        completeFrames += 1
        lock.unlock()
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        lock.lock()
        didStartOutput = true
        lock.unlock()
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        requestStop(reason: "视频写入失败", error: JobsRecorderFailure("视频写入失败：\(error.localizedDescription)"))
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        lock.lock()
        didFinishOutput = true
        let alreadyStopping = isStopping
        lock.unlock()
        if !alreadyStopping {
            requestStop(reason: "系统结束采集")
        }
    }
}
