//
//  JobsAsyncDeadline.swift
//  JobsWindowRecorder
//
//  Created by Jobs on 2026年11月14日，星期六.
//

import Foundation

/// 独立超时门闩避免系统回调未到达时无限等待；迟到回调只被忽略。
final class JobsAsyncDeadline<Value>: @unchecked Sendable {

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    private init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    private func resolve(_ result: Result<Value, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }

    static func run(seconds: Double,
                    label: String,
                    operation: @escaping () async throws -> Value) async throws -> Value {
        return try await withCheckedThrowingContinuation { continuation in
            let gate = JobsAsyncDeadline(continuation)
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                gate.resolve(.failure(JobsRecorderFailure("\(label)超时，请重试或检查系统权限。")))
            }
            Task {
                do {
                    gate.resolve(.success(try await operation()))
                } catch {
                    gate.resolve(.failure(error))
                }
            }
        }
    }
}
