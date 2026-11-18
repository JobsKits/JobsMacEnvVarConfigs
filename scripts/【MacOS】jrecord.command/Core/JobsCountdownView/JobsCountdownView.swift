//
//  JobsCountdownView.swift
//  JobsWindowRecorder
//
//  Created by Jobs on 2026年11月14日，星期六.
//

import AppKit
import QuartzCore

/// 只绘制数字和双圆；透明区域保持桌面原貌，阴影保证明暗背景均可读。
@MainActor
final class JobsCountdownView: NSView {

    private let badge = CALayer()
    private let numberLayer = CATextLayer()
    private let outerRing = CAShapeLayer()
    private let innerRing = CAShapeLayer()
    private let displayScale: CGFloat

    override var isOpaque: Bool {
        return false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    init(frame: NSRect, scale: CGFloat) {
        displayScale = scale
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        badge.bounds = CGRect(x: 0, y: 0, width: 360, height: 360)
        badge.position = CGPoint(x: bounds.midX, y: bounds.midY)
        badge.opacity = 0
        badge.shadowColor = NSColor.black.cgColor
        badge.shadowOpacity = 0.65
        badge.shadowRadius = 12
        badge.shadowOffset = .zero
        layer?.addSublayer(badge)
        configureRing(innerRing, radius: 139, width: 3,
                      color: NSColor.white.withAlphaComponent(0.95))
        innerRing.fillColor = NSColor.black.withAlphaComponent(0.22).cgColor
        configureRing(outerRing, radius: 157, width: 2,
                      color: NSColor(calibratedRed: 0.46, green: 0.85, blue: 1, alpha: 0.9))
        numberLayer.contentsScale = displayScale
        numberLayer.alignmentMode = .center
        badge.addSublayer(numberLayer)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        badge.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    private func configureRing(_ ring: CAShapeLayer, radius: CGFloat, width: CGFloat, color: NSColor) {
        ring.frame = badge.bounds
        ring.path = CGPath(ellipseIn: CGRect(x: 180 - radius, y: 180 - radius,
                                            width: radius * 2, height: radius * 2),
                           transform: nil)
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = color.cgColor
        ring.lineWidth = width
        ring.contentsScale = displayScale
        badge.addSublayer(ring)
    }

    func show(number: Int) {
        let text = NSAttributedString(string: String(number), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 164, weight: .bold),
            .foregroundColor: NSColor.white
        ])
        let size = text.size()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        numberLayer.string = text
        numberLayer.frame = CGRect(x: 0, y: (360 - size.height) / 2,
                                   width: 360, height: size.height)
        CATransaction.commit()

        // 每秒两次轻脉冲后淡出；系统减少动态效果时保留静态数字和淡出。
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [1, 1, 0]
        opacity.keyTimes = [0, 0.58, 1]
        opacity.duration = 0.94
        opacity.timingFunctions = [CAMediaTimingFunction(name: .easeOut),
                                   CAMediaTimingFunction(name: .easeIn)]
        badge.add(opacity, forKey: "countdown.fade")

        if !reduceMotion {
            let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
            pulse.values = [0.94, 1.07, 1, 1.035, 1, 1.08]
            pulse.keyTimes = [0, 0.16, 0.31, 0.43, 0.58, 1]
            pulse.duration = 0.94
            pulse.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 5)
            badge.add(pulse, forKey: "countdown.heartbeat")
        }
    }
}
