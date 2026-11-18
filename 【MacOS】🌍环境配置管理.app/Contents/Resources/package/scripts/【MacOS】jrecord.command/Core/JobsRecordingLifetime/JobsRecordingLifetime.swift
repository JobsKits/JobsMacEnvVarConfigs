//
//  JobsRecordingLifetime.swift
//  JobsWindowRecorder
//
//  Created by Jobs on 2026年11月14日，星期六.
//

import Darwin
import Foundation

/// HUP 之外独立检查父进程和控制终端，避免启动终端强退后遗留后台录制。
final class JobsRecordingLifetime: @unchecked Sendable {

    private let parentPID: pid_t
    private let terminalFD: Int32
    private let terminalExpected: Bool
    private let terminalCanPoll: Bool
    private let timer: DispatchSourceTimer

    init(onSessionEnded: @escaping @Sendable (String) -> Void) {
        parentPID = getppid()
        let terminal = Self.openControllingTerminal()
        terminalFD = terminal.fd
        terminalExpected = terminal.expected
        terminalCanPoll = terminal.canPoll
        timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            // 父子关系由内核维护；父进程死亡后会重新挂接，不能被 PID 复用蒙混。
            if self.parentPID <= 1 || getppid() != self.parentPID {
                onSessionEnded("启动录制的父进程已结束")
                return
            }
            if self.terminalExpected && self.terminalFD < 0 {
                onSessionEnded("启动录制的终端会话已关闭")
                return
            }
            if self.terminalFD >= 0 {
                var attributes = termios()
                // 不读取输入；PTY 挂断后 tcgetattr 仍可能成功，需同时核对挂断标志。
                var status = pollfd(fd: self.terminalFD, events: Int16(POLLIN), revents: 0)
                let polled = self.terminalCanPoll ? poll(&status, 1, 0) : 0
                let disconnected = polled > 0 && status.revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0
                if disconnected || tcgetattr(self.terminalFD, &attributes) != 0 {
                    onSessionEnded("启动录制的终端会话已关闭")
                }
            }
        }
        timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(10))
        timer.resume()
    }

    private static func openControllingTerminal() -> (fd: Int32, expected: Bool, canPoll: Bool) {
        let inherited = ttyname(STDIN_FILENO).map { String(cString: $0) }
        let specified = ProcessInfo.processInfo.environment["JOBS_RECORD_TTY"]
        let terminal = specified ?? inherited ?? "/dev/tty"
        let expected = specified != nil || inherited != nil
        guard terminal.hasPrefix("/dev/tty"), !terminal.contains("/../") else {
            return (-1, expected, false)
        }
        let descriptor = open(terminal, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            return (-1, expected, false)
        }
        guard isatty(descriptor) == 1 else {
            close(descriptor)
            return (-1, expected, false)
        }
        // /dev/tty 是复用设备，Darwin 不支持对它 poll；Shell 传真实 slave 路径。
        return (descriptor, expected, terminal != "/dev/tty")
    }

    func cancel() {
        timer.cancel()
    }

    deinit {
        timer.cancel()
        if terminalFD >= 0 {
            close(terminalFD)
        }
    }
}
