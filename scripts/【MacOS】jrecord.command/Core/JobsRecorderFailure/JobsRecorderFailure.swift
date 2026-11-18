//
//  JobsRecorderFailure.swift
//  JobsWindowRecorder
//
//  Created by Jobs on 2026年11月14日，星期六.
//

import Foundation

struct JobsRecorderFailure: Error,
                            LocalizedError {

    let message: String
    let code: Int32

    init(_ message: String, code: Int32 = 1) {
        self.message = message
        self.code = code
    }

    var errorDescription: String? {
        return message
    }
}
