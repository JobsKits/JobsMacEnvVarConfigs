//
//  JobsCountdownClickView.swift
//  JobsCountdownUITests
//
//  Created by Jobs on 2026年11月14日，星期六.
//

import AppKit

@MainActor
final class JobsCountdownClickView: NSView {

    private(set) var clicks = 0

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        clicks += 1
    }
}
