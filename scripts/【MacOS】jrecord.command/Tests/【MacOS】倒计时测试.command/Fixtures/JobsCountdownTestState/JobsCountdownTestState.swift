//
//  JobsCountdownTestState.swift
//  JobsCountdownUITests
//
//  Created by Jobs on 2026年11月14日，星期六.
//

import Foundation

final class JobsCountdownTestState: @unchecked Sendable {

    private let lock = NSLock()
    private var number: Int32 = 0

    func set(_ value: Int32) {
        lock.lock()
        number = value
        lock.unlock()
    }

    func get() -> Int32 {
        lock.lock()
        defer {
            lock.unlock()
        }
        return number
    }
}
