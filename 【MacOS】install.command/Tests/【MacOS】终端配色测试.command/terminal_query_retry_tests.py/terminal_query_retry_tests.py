#!/usr/bin/env python3
"""完整 bootstrap/reexec 的 OSC 查询丢包、重发和帧解析隔离回归。"""

from __future__ import annotations

import argparse
import dataclasses
import json
import logging
import os
from pathlib import Path
import pty
import re
import select
import signal
import tempfile
import termios
import time


KEYS = ["10", "11", "12"] + [f"4;{index}" for index in range(16)]
OSC = re.compile(rb"\x1b\]([^\x07\x1b]*)(?:\x07|\x1b\\)")
WARNING = "终端配色未能安全自动恢复".encode()
ROLLBACK = "临时配色核验失败（颜色项".encode()
PLAIN_RESTORED = "已恢复原配色并使用纯文本。".encode()
CONFLICT = "检测到运行期间的配色变更".encode()
CLEANUP_KEY_LIMIT = 64
CSI_ARROWS = b"".join(b"\x1b[" + bytes([key]) for key in b"ABCD")
SS3_ARROWS = b"".join(b"\x1bO" + bytes([key]) for key in b"ABCD")


@dataclasses.dataclass(frozen=True)
class Scenario:
    name: str
    expected_code: int = 0
    transmissions: tuple[str, str, int] | None = None
    key_phase: str = ""
    key_bytes: bytes = b""
    key_position: str = "before"
    key_target: str = "10"
    startup_fallback: bool = False
    max_seconds: float | None = None
    rollback: bool = False
    rollback_failed: bool = False
    rollback_conflict: bool = False
    already_original: tuple[str, ...] = ()
    business_code: int = 0


SCENARIOS = (
    Scenario("drop-first-startup", transmissions=("startup", "10", 2)),
    Scenario("drop-first-startup-4-9", transmissions=("startup", "4;9", 2)),
    Scenario("drop-first-applied", transmissions=("applied", "10", 2)),
    Scenario("drop-first-cleanup", transmissions=("cleanup", "10", 2)),
    Scenario("drop-two-cleanup", transmissions=("cleanup", "10", 3)),
    Scenario("drop-all-startup", transmissions=("startup", "10", 3)),
    Scenario("drop-all-applied", transmissions=("applied", "10", 3), rollback=True),
    Scenario("drop-all-cleanup", 1, ("cleanup", "10", 3)),
    Scenario("stale-then-target"),
    Scenario("combined-old-duplicate-target"),
    Scenario("late-first-into-next-query", transmissions=("cleanup", "10", 2)),
    Scenario("fragmented-stale-st-then-target"),
    Scenario("only-stale-then-retry-target", transmissions=("cleanup", "10", 2)),
    Scenario("conflicting-duplicate-target", 1),
    Scenario("keyboard-csi-before-target", 1),
    Scenario("keyboard-newline-before-target"),
    Scenario("keyboard-newline-after-target"),
    Scenario("incomplete-frame-no-retry", 1, ("cleanup", "10", 1)),
    Scenario("unknown-color-frame", 1),
    Scenario("malformed-old-key", 1),
    Scenario("multi-record-rgb", 1),
    Scenario("cleanup-cr-before-target", key_phase="cleanup", key_bytes=b"\r"),
    Scenario("cleanup-csi-arrows", key_phase="cleanup", key_bytes=CSI_ARROWS),
    Scenario("cleanup-ss3-arrows", key_phase="cleanup", key_bytes=SS3_ARROWS),
    Scenario("cleanup-modified-csi-arrows", key_phase="cleanup", key_bytes=b"\x1b[1;5D\x1b[1;2A"),
    Scenario("cleanup-consecutive-keys", key_phase="cleanup", key_bytes=b"\r\n" * 3 + CSI_ARROWS + SS3_ARROWS),
    Scenario("cleanup-fragmented-csi-left", key_phase="cleanup", key_bytes=b"\x1b[D", key_position="fragmented"),
    Scenario("cleanup-fragmented-ss3-right", key_phase="cleanup", key_bytes=b"\x1bOC", key_position="fragmented"),
    Scenario("cleanup-keys-between-color-frames", key_phase="cleanup", key_bytes=b"\n\x1b[D\r", key_position="between"),
    Scenario("cleanup-key-arrives-next-query"),
    Scenario("drop-first-cleanup-with-keys", transmissions=("cleanup", "10", 2)),
    Scenario("cleanup-key-budget-exact", key_phase="cleanup", key_bytes=b"\r" * CLEANUP_KEY_LIMIT),
    Scenario("cleanup-key-budget-exceeded", 1, ("cleanup", "10", 1), key_phase="cleanup", key_bytes=b"\r" * (CLEANUP_KEY_LIMIT + 1), max_seconds=4),
    Scenario("cleanup-key-budget-across-queries", 1, ("cleanup", "11", 1), max_seconds=4),
    Scenario("cleanup-key-budget-across-retries", 1, ("cleanup", "10", 2), max_seconds=7),
    Scenario("startup-crlf-strict", key_phase="startup", key_bytes=b"\r\n", startup_fallback=True),
    Scenario("startup-csi-arrow-strict", key_phase="startup", key_bytes=b"\x1b[D", startup_fallback=True),
    Scenario("startup-ss3-arrow-strict", key_phase="startup", key_bytes=b"\x1bOD", startup_fallback=True),
    Scenario("applied-crlf-accepted", key_phase="applied", key_bytes=b"\r\n"),
    Scenario("applied-csi-arrow-accepted", key_phase="applied", key_bytes=b"\x1b[D"),
    Scenario("applied-ss3-arrow-accepted", key_phase="applied", key_bytes=b"\x1bOD"),
    Scenario("applied-consecutive-keys", key_phase="applied", key_bytes=b"\r\n" * 3 + CSI_ARROWS + SS3_ARROWS),
    Scenario("applied-modified-csi-arrows", key_phase="applied", key_bytes=b"\x1b[1;5D\x1b[1;2A"),
    Scenario("applied-fragmented-csi-left", key_phase="applied", key_bytes=b"\x1b[D", key_position="fragmented"),
    Scenario("applied-fragmented-ss3-right", key_phase="applied", key_bytes=b"\x1bOC", key_position="fragmented"),
    Scenario("applied-keys-between-color-frames", key_phase="applied", key_bytes=b"\n\x1b[D\r", key_position="between"),
    Scenario("applied-key-budget-exact", key_phase="applied", key_bytes=b"\r" * CLEANUP_KEY_LIMIT),
    Scenario("applied-key-budget-exceeded", key_phase="applied", key_bytes=b"\r" * (CLEANUP_KEY_LIMIT + 1), rollback=True, max_seconds=4),
    Scenario("applied-key-budget-across-queries", rollback=True, max_seconds=4),
    Scenario("applied-key-budget-across-retries", rollback=True, transmissions=("applied", "10", 2), max_seconds=7),
    Scenario("applied-and-cleanup-independent-budgets"),
    Scenario("applied-plain-text-rollback", key_phase="applied", key_bytes=b"X", rollback=True),
    Scenario("applied-later-color-rollback", key_phase="applied", key_bytes=b"X", key_target="4;9", rollback=True),
    Scenario("applied-key-inside-target-rollback", key_phase="applied", key_bytes=b"\x1b[D", key_position="inside-target", rollback=True),
    Scenario("applied-incomplete-frame-rollback", rollback=True, transmissions=("applied", "10", 1)),
    Scenario("applied-invalid-rgb-rollback", rollback=True),
    Scenario("applied-conflicting-replies-rollback", rollback=True),
    Scenario("rollback-timeout", 1, ("rollback", "10", 3), rollback=True, rollback_failed=True),
    Scenario("rollback-external-color-conflict", 1, rollback=True, rollback_conflict=True),
    Scenario("rollback-control-keys", key_phase="rollback", key_bytes=b"\r" * CLEANUP_KEY_LIMIT, rollback=True),
    Scenario("rollback-control-budget-exceeded", 1, key_phase="rollback", key_bytes=b"\r" * (CLEANUP_KEY_LIMIT + 1), rollback=True, rollback_failed=True, max_seconds=4),
    Scenario("rollback-one-already-original", rollback=True, already_original=("11",)),
    Scenario("rollback-all-already-original", rollback=True, already_original=tuple(KEYS)),
    Scenario("rollback-continues-with-business-status", 37, rollback=True, business_code=37),
    Scenario("cleanup-plain-text-strict", 1, key_phase="cleanup", key_bytes=b"X"),
    Scenario("cleanup-unknown-ss3-strict", 1, key_phase="cleanup", key_bytes=b"\x1bOP"),
    Scenario("cleanup-unknown-csi-modifier-strict", 1, key_phase="cleanup", key_bytes=b"\x1b[1;9D"),
    Scenario("cleanup-bare-escape-strict", 1, key_phase="cleanup", key_bytes=b"\x1b"),
    Scenario("cleanup-key-inside-target-strict", 1, key_phase="cleanup", key_bytes=b"\x1b[D", key_position="inside-target"),
    Scenario("cleanup-key-inside-old-strict", 1, key_phase="cleanup", key_bytes=b"\x1bOD", key_position="inside-old"),
)


def require(condition: bool, message: str) -> None:
    """记录真实协议行为的失败，不能把待测结果改成预期值。"""
    if not condition:
        raise AssertionError(message)


def full_guard(source: Path) -> str:
    """保留生产保护块和实际 bootstrap 调用，去掉全部安装业务。"""
    content = source.read_text(encoding="utf-8")
    start = content.index("# >>> Jobs terminal style protection v1 >>>")
    end_marker = "# <<< Jobs terminal style protection v1 <<<"
    end = content.index(end_marker, start) + len(end_marker)
    block = content[start:end]
    require('jobs_terminal_style_bootstrap "$0" "$@"' in block,
            "生产块缺少完整 bootstrap 调用，不能使用截断的函数模型代替。")
    return "#!/bin/zsh\n" + block + "\n"


class TerminalModel:
    """只模拟本轮独立 PTY 的颜色与故障，不读取或控制用户终端。"""

    def __init__(self, case: Scenario) -> None:
        self.case = case
        self.colors = {key: "1234/3456/5678" for key in KEYS}
        self.original = dict(self.colors)
        self.output = b""
        self.pending = b""
        self.replies: list[tuple[float, bytes]] = []
        self.query_counts: dict[tuple[str, str], int] = {}
        self.updates: list[str] = []
        self.rollback_started = False

    def frame(self, key: str, rgb: str | None = None, ending: bytes = b"\x07") -> bytes:
        """生成完整模拟答复；RGB 故障仅来自明确的测试场景。"""
        value = self.colors[key] if rgb is None else rgb
        return ("\x1b]" + key + ";rgb:" + value).encode() + ending

    def queue(self, reply: bytes, delay: float = 0) -> None:
        """按单调时间安排分片和迟到答复。"""
        self.replies.append((time.monotonic() + delay, reply))

    def flush_ready(self, descriptor: int) -> None:
        """只向当前测试创建的 PTY 发送已经到期的模拟数据。"""
        now = time.monotonic()
        for when, reply in list(self.replies):
            if when <= now:
                os.write(descriptor, reply)
                self.replies.remove((when, reply))

    def answer_keys(self, phase: str, key: str, count: int) -> bool:
        """只在明确阶段注入模拟按键，区分完整帧边界与帧内非法数据。"""
        case = self.case
        if case.key_phase != phase or key != case.key_target or count != 1:
            return False
        target = self.frame(key)
        if case.key_position == "before":
            self.queue(case.key_bytes + target)
        elif case.key_position == "after":
            self.queue(target + case.key_bytes)
        elif case.key_position == "fragmented":
            for index, value in enumerate(case.key_bytes):
                self.queue(bytes([value]), index * 0.025)
            self.queue(target, len(case.key_bytes) * 0.025 + 0.02)
        elif case.key_position == "between":
            self.queue(self.frame("11") + case.key_bytes + target)
        elif case.key_position in ("inside-target", "inside-old"):
            frame = target if case.key_position == "inside-target" else self.frame("11")
            split = frame.index(b"rgb:") + len(b"rgb:") + 2
            malformed = frame[:split] + case.key_bytes + frame[split:]
            self.queue(malformed + (target if case.key_position == "inside-old" else b""))
        else:
            raise AssertionError("未知按键注入位置：" + case.key_position)
        return True

    def answer(self, phase: str, key: str, count: int) -> None:
        """在保存、设置核验或退出阶段丢请求，并制造明确的旧帧和非法帧。"""
        name = self.case.name
        if self.answer_keys(phase, key, count):
            return
        if phase in ("applied", "cleanup") and name == "applied-and-cleanup-independent-budgets" and key == "10" and count == 1:
            self.queue(b"\r" * CLEANUP_KEY_LIMIT + self.frame(key))
            return
        if phase == "applied":
            if name == "applied-key-budget-across-queries" and key in ("10", "11"):
                self.queue(b"\r" * (CLEANUP_KEY_LIMIT if key == "10" else 1) + self.frame(key))
                return
            if name == "applied-key-budget-across-retries" and key == "10":
                self.queue(b"\r" * CLEANUP_KEY_LIMIT if count == 1 else b"\r" + self.frame(key))
                return
            if key == "10":
                if name.startswith("rollback-"):
                    self.queue(b"X" + self.frame(key))
                    return
                faults = {
                    "applied-incomplete-frame-rollback": b"\x1b]10;rgb:ffff/ffff/",
                    "applied-invalid-rgb-rollback": self.frame(key, "not-rgb"),
                    "applied-conflicting-replies-rollback": self.frame(key) + self.frame(key, "abcd/0000/ffff"),
                }
                if name in faults:
                    self.queue(faults[name])
                    return
        if phase == "rollback" and name == "rollback-timeout" and key == "10":
            return
        if phase == "cleanup" and key == "10":
            if name == "drop-first-cleanup-with-keys":
                self.queue(b"\r\n\x1b[D" if count == 1 else b"\x1bOC" + self.frame(key))
                return
            if name == "cleanup-key-budget-across-retries":
                self.queue(b"\r" * CLEANUP_KEY_LIMIT if count == 1 else b"\r" + self.frame(key))
                return
            if name == "cleanup-key-budget-across-queries":
                self.queue(b"\r" * CLEANUP_KEY_LIMIT + self.frame(key))
                return
            if name == "cleanup-key-arrives-next-query":
                self.queue(self.frame(key))
                self.queue(b"\x1b[D\r\n", 0.035)
                return
        if phase == "cleanup" and key == "11":
            if name == "cleanup-key-budget-across-queries":
                self.queue(b"\r" + self.frame(key))
                return
            if name == "cleanup-key-arrives-next-query":
                self.queue(self.frame(key), 0.12)
                return
        first_losses = {
            "drop-first-startup": ("startup", "10"),
            "drop-first-startup-4-9": ("startup", "4;9"),
            "drop-first-applied": ("applied", "10"),
            "drop-first-cleanup": ("cleanup", "10"),
        }
        if first_losses.get(name) == (phase, key) and count == 1:
            return
        if name == "drop-all-" + phase and key == "10":
            return
        if phase == "cleanup" and key == "10":
            if name == "drop-two-cleanup" and count <= 2:
                return
            if name == "late-first-into-next-query" and count == 1:
                self.queue(self.frame(key), 2.2)
                return
            if name == "only-stale-then-retry-target" and count == 1:
                self.queue(self.frame("11"))
                return
            faults = {
                "conflicting-duplicate-target": self.frame(key) + self.frame(key, "abcd/0000/ffff"),
                "keyboard-csi-before-target": b"\x1b[O" + self.frame(key),
                "keyboard-newline-before-target": b"\n" + self.frame(key),
                "keyboard-newline-after-target": self.frame(key) + b"\n",
                "incomplete-frame-no-retry": b"\x1b]10;rgb:ffff/ffff/",
                "unknown-color-frame": b"\x1b]17;rgb:ffff/ffff/ffff\x07" + self.frame(key),
                "malformed-old-key": self.frame("11", "not-rgb") + self.frame(key),
                "multi-record-rgb": self.frame(key, "ffff/ffff/ffff\nffff/ffff/ffff"),
            }
            if name in faults:
                self.queue(faults[name])
                return
        if phase == "cleanup" and key == "11":
            if name == "stale-then-target":
                self.queue(self.frame("10"))
                self.queue(self.frame(key), 0.2)
                return
            if name == "combined-old-duplicate-target":
                self.queue(self.frame("10") + self.frame(key) + self.frame(key))
                return
            if name == "late-first-into-next-query":
                self.queue(self.frame(key), 0.4)
                return
            if name == "fragmented-stale-st-then-target":
                stale = self.frame("10", ending=b"\x1b\\")
                self.queue(stale[:2])
                self.queue(stale[2:-2], 0.02)
                self.queue(stale[-2:], 0.04)
                self.queue(self.frame(key), 0.09)
                return
        self.queue(self.frame(key))

    def receive(self, chunk: bytes) -> None:
        """按真实输出设置更新模拟颜色，按实际请求计数而不是等待次数计数。"""
        self.output += chunk
        self.pending += chunk
        if ROLLBACK in self.output and not self.rollback_started:
            self.rollback_started = True
            for original_key in self.case.already_original:
                self.colors[original_key] = self.original[original_key]
            if self.case.rollback_conflict:
                self.colors["11"] = "abcd/1234/9876"
        while True:
            match = OSC.search(self.pending)
            if not match:
                return
            self.pending = self.pending[match.end():]
            key, value = match.group(1).decode().rsplit(";", 1)
            require(key in self.colors, "生产请求了未声明的颜色项：" + key)
            if value == "?":
                if b"BUSINESS_DONE" in self.output:
                    phase = "cleanup"
                elif self.rollback_started:
                    phase = "rollback"
                else:
                    phase = "applied" if self.updates else "startup"
                mark = (phase, key)
                self.query_counts[mark] = self.query_counts.get(mark, 0) + 1
                self.answer(phase, key, self.query_counts[mark])
            elif value.startswith("#"):
                digits = value[1:]
                self.colors[key] = "/".join(digits[index:index + 2] * 2 for index in (0, 2, 4))
                self.updates.append(key)
            elif value.startswith("rgb:"):
                self.colors[key] = value[4:]
                self.updates.append(key)


def run_child(fixture: Path, folder: Path, model: TerminalModel) -> tuple[int, list, list]:
    """以真实 bootstrap/reexec 执行假业务，失败只回收本测试的直接子进程。"""
    pid, descriptor = pty.fork()
    if pid == 0:
        environment = dict(os.environ, TERM="xterm-256color", TMPDIR=str(folder / "tmp") + "/")
        for key in list(environment):
            if key.startswith(("JOBS_TERMINAL_STYLE_", "SOURCETREE", "SOURCE_TREE")):
                environment.pop(key)
        for key in ("NO_COLOR", "PLAIN_OUTPUT", "IS_SOURCETREE_RUNTIME", "TMUX", "STY"):
            environment.pop(key, None)
        os.execve("/bin/zsh", ["/bin/zsh", str(fixture)], environment)
    before_mode = termios.tcgetattr(descriptor)
    status = None
    deadline = time.monotonic() + 22
    try:
        while time.monotonic() < deadline:
            model.flush_ready(descriptor)
            ready, _, _ = select.select([descriptor], [], [], 0.01)
            if not ready:
                continue
            try:
                chunk = os.read(descriptor, 65536)
            except OSError:
                break
            if not chunk:
                break
            model.receive(chunk)
        else:
            raise TimeoutError("独立 PTY 超过有界运行时间：" + model.case.name)
        after_mode = termios.tcgetattr(descriptor)
        reap_deadline = time.monotonic() + 0.5
        while True:
            ended, status = os.waitpid(pid, os.WNOHANG)
            if ended:
                break
            if time.monotonic() >= reap_deadline:
                status = None
                raise TimeoutError("测试子进程未正常结束：" + model.case.name)
            time.sleep(0.01)
        return os.waitstatus_to_exitcode(status), before_mode, after_mode
    finally:
        os.close(descriptor)
        if status is None:
            try:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            except ProcessLookupError:
                pass
        (folder / "terminal.log").write_bytes(model.output)


def run_case(header: str, work: Path, case: Scenario) -> dict:
    """验证实际发包次数、颜色、模式、错误状态和恢复文件。"""
    folder = work / case.name
    folder.mkdir()
    (folder / "tmp").mkdir()
    fixture = folder / "fixture.command"
    fixture.write_text(header + f"printf 'BUSINESS_MODE:%s:%s\\n' \"${{PLAIN_OUTPUT:-0}}\" \"${{NO_COLOR:-0}}\"\nprintf 'BUSINESS_DONE\\n'\nexit {case.business_code}\n", encoding="utf-8")
    model = TerminalModel(case)
    started = time.monotonic()
    code, before_mode, after_mode = run_child(fixture, folder, model)
    elapsed = time.monotonic() - started
    require(code == case.expected_code, f"退出码 {code}，预期 {case.expected_code}")
    require(before_mode == after_mode, "终端输入模式或VMIN／VTIME未精确恢复")
    if case.rollback:
        require(ROLLBACK in model.output, "核验失败未显示具体颜色项与原因")
        require(model.rollback_started, "未进入独立回退查询")
        require(model.query_counts.get(("rollback", "10"), 0) > 0, "未重新查询当前颜色就声称回退")
        if case.rollback_failed:
            require(len(model.updates) == 19, "回退答复无效时发生盲目覆盖")
            require(WARNING in model.output, "回退失败未明确报告")
            require(b"BUSINESS_DONE" not in model.output, "回退失败仍启动业务")
            require("回退颜色项 10".encode() in model.output, "回退失败未指出具体颜色项")
        elif case.rollback_conflict:
            expected = dict(model.original, **{"11": "abcd/1234/9876"})
            require(model.colors == expected, "回退覆盖了其它来源的新配色，或未恢复仍由本次持有的项")
            require(len(model.updates) == 37, "回退冲突时应只恢复18个仍由本次持有的颜色项")
            require(CONFLICT in model.output and WARNING in model.output, "回退冲突未明确报告")
            require(b"BUSINESS_DONE" not in model.output, "存在配色归属冲突仍启动业务")
        else:
            require(model.colors == model.original, "核验失败后未精确恢复19项原色")
            require(len(model.updates) == 38 - len(case.already_original), "回退重复改写原色或恢复项数量异常")
            require(PLAIN_RESTORED in model.output, "回退成功未明确显示纯文本继续")
            require(b"BUSINESS_DONE" in model.output, "恢复成功后没有继续业务")
            require(b"BUSINESS_MODE:1:1" in model.output, "回退成功后没有启用纯文本环境")
            require(WARNING not in model.output and CONFLICT not in model.output, "成功回退误报恢复失败或冲突")
        retained = bool(list((folder / "tmp").glob("jobs-terminal-style.*/restore.sh")))
        require(retained == (case.rollback_failed or case.rollback_conflict), "回退后的人工恢复入口保留策略错误")
    elif case.expected_code:
        require(len(model.updates) == 19, "非法或无答复时发生了盲目覆盖")
        require(WARNING in model.output, "恢复失败未明确报告")
        require(bool(list((folder / "tmp").glob("jobs-terminal-style.*/restore.sh"))), "缺少恢复入口")
    elif case.name == "drop-all-startup" or case.startup_fallback:
        require(model.colors == model.original and not model.updates, "初始保存失败应保留原配色并降级")
        require(WARNING not in model.output, "未改色的启动降级不应报告恢复失败")
    else:
        require(model.colors == model.original, "未精确恢复19项原色")
        require(len(model.updates) == 38, "改色或恢复次数异常")
        require(WARNING not in model.output, "正常恢复意外报告失败")
    expected_business = 0 if case.rollback_failed or case.rollback_conflict else 1
    require(model.output.count(b"BUSINESS_DONE") == expected_business, "业务未严格按预期只执行一次，或失败后仍被执行")
    if case.transmissions:
        phase, key, expected = case.transmissions
        actual = model.query_counts.get((phase, key), 0)
        require(actual == expected, f"{phase}:{key} 真正发包 {actual} 次，预期 {expected} 次")
    if case.max_seconds is not None:
        require(elapsed < case.max_seconds, f"按键噪声未在限定时间内结束：{elapsed:.3f} 秒")
    result = {
        "name": case.name, "exit_code": code, "updates": len(model.updates),
        "queries": sum(model.query_counts.values()),
        "elapsed_seconds": round(elapsed, 3),
        "query_counts": {phase + ":" + key: value for (phase, key), value in model.query_counts.items()},
        "colors": model.colors,
        "original": model.original,
        "business_runs": model.output.count(b"BUSINESS_DONE"),
        "input_mode_restored": before_mode == after_mode,
    }
    (folder / "result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    logging.info("PASS: %s (exit=%s, queries=%s)", case.name, code, result["queries"])
    return result


def main() -> int:
    """先确认隔离范围，再从实际源码选取完整保护块运行指定场景。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yes", action="store_true", help="确认独立 PTY 回归")
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[3] / "【MacOS】install.command")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--case", action="append", choices=[case.name for case in SCENARIOS], help="只跑指定场景，可重复")
    args = parser.parse_args()
    print("查询重发回归：实际生产bootstrap/reexec＋假业务；只用独立PTY，不执行安装或操作用户终端。", flush=True)
    if not args.yes:
        try:
            input("按回车开始，Ctrl+C取消：")
        except (EOFError, KeyboardInterrupt):
            return 130
    if args.output:
        work = args.output.resolve()
        if work.exists():
            parser.error("--output 必须是本轮尚不存在的独立目录。")
        work.mkdir(parents=True)
    else:
        work = Path(tempfile.mkdtemp(prefix="jobs-terminal-query-retry-tests."))
    logging.basicConfig(level=logging.INFO, format="%(message)s", handlers=[
        logging.StreamHandler(), logging.FileHandler(work / "tests.log", encoding="utf-8")
    ])
    logging.info("隔离现场：%s", work)
    header = full_guard(args.source.resolve())
    selected = [case for case in SCENARIOS if not args.case or case.name in args.case]
    results = []
    for case in selected:
        try:
            results.append(run_case(header, work, case))
        except Exception as error:
            logging.exception("FAIL: %s", case.name)
            results.append({"name": case.name, "error": str(error)})
    failures = sum("error" in result for result in results)
    (work / "results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    logging.info("查询重发回归：%s场景，%s失败；日志：%s", len(selected), failures, work / "tests.log")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
