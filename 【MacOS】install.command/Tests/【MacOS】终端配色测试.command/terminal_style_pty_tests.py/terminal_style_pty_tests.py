#!/usr/bin/env python3
"""在独立 PTY 中模拟 OSC 终端，只执行生产配色保护和无副作用业务。"""

from __future__ import annotations

import argparse
import dataclasses
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


OSC = re.compile(rb"\x1b\]([^\x07\x1b]*)(?:\x07|\x1b\\)")
KEYS = ["10", "11", "12"] + [f"4;{index}" for index in range(16)]
WARNING = "终端配色未能安全自动恢复".encode()
CONFLICT = "检测到运行期间的配色变更".encode()


@dataclasses.dataclass(frozen=True)
class Scenario:
    name: str
    expected_code: int = 0
    delay: float = 0
    fragmented: bool = False
    terminator: bytes = b"\x07"
    conflict: bool = False
    response_fault: str = ""
    business_code: int = 0
    stop_signal: int = 0
    nested: bool = False
    keyboard: bool = False
    startup_input: bool = False
    plain: str = ""


def require(condition: bool, message: str) -> None:
    """将协议和恢复约束作为真实行为断言。"""
    if not condition:
        raise AssertionError(message)


def extract_header(source: Path) -> str:
    """只取受控保护函数，绝不加载安装器 main 或真实安装业务。"""
    content = source.read_text(encoding="utf-8")
    begin = content.index("# >>> Jobs terminal style protection v1 >>>")
    end = content.index('jobs_terminal_style_bootstrap "$0" "$@"', begin)
    return "#!/bin/zsh\n" + content[begin:end]


def make_fixture(header: str, folder: Path, case: Scenario) -> Path:
    """每个场景生成独立假业务，参数及故障均不来自用户终端。"""
    script = folder / "fixture.zsh"
    if case.stop_signal:
        body = """run_test_business() {
    printf 'BUSINESS_READY\\n'
    while :; do
        :
    done
}
jobs_terminal_style_run run_test_business
"""
    elif case.keyboard:
        body = """run_test_business() {
    printf 'INPUT_READY\\n'
    IFS= read -r test_value < /dev/tty || return 71
    printf 'INPUT_VALUE:%s\\n' "$test_value"
    return 0
}
jobs_terminal_style_run run_test_business
"""
    elif case.nested:
        inner = folder / "inner.zsh"
        inner.write_text(header + "\njobs_terminal_style_run /bin/sh -c 'printf \"BUSINESS_DONE\\n\"; exit 0'\n", encoding="utf-8")
        quoted = "'" + str(inner).replace("'", "'\\''") + "'"
        body = "jobs_terminal_style_run /bin/zsh " + quoted + "\n"
    else:
        body = f"jobs_terminal_style_run /bin/sh -c 'printf \"BUSINESS_DONE\\n\"; exit {case.business_code}'\n"
    script.write_text(header + "\n" + body, encoding="utf-8")
    return script


def run_case(header: str, work: Path, case: Scenario) -> None:
    """驱动伪终端的颜色协议、输入和信号，并核对最终状态。"""
    folder = work / case.name
    folder.mkdir()
    (folder / "tmp").mkdir()
    script = make_fixture(header, folder, case)
    pid, master = pty.fork()
    if pid == 0:
        environment = dict(os.environ)
        for key in list(environment):
            if key.startswith(("JOBS_TERMINAL_STYLE_", "SOURCETREE", "SOURCE_TREE")):
                environment.pop(key)
        for key in ("NO_COLOR", "TMUX", "STY", "PLAIN_OUTPUT", "IS_SOURCETREE_RUNTIME"):
            environment.pop(key, None)
        environment["TERM"] = "dumb" if case.plain == "dumb" else "xterm-256color"
        environment["TMPDIR"] = str(folder / "tmp") + "/"
        if case.plain == "NO_COLOR":
            environment["NO_COLOR"] = ""
        os.execve("/bin/zsh", ["/bin/zsh", str(script)], environment)
    before_flags = termios.tcgetattr(master)[3]
    colors = {key: "1234/3456/5678" for key in KEYS}
    original = dict(colors)
    output = b""
    pending = b""
    replies: list[tuple[float, bytes]] = []
    queries: list[str] = []
    updates: list[str] = []
    signalled = False
    typed = False
    user_changed = False
    timed_out = False
    status = None
    deadline = time.monotonic() + 20
    try:
        while time.monotonic() < deadline:
            now = time.monotonic()
            for ready_at, reply in list(replies):
                if ready_at <= now:
                    os.write(master, reply)
                    replies.remove((ready_at, reply))
            ready, _, _ = select.select([master], [], [], 0.01)
            if not ready:
                continue
            try:
                data = os.read(master, 65536)
            except OSError:
                break
            if not data:
                break
            output += data
            pending += data
            if case.stop_signal and not signalled and b"BUSINESS_READY" in output:
                os.kill(pid, case.stop_signal)
                signalled = True
            if case.keyboard and not typed and b"INPUT_READY" in output:
                os.write(master, b"demo value\n")
                typed = True
            if case.conflict and not user_changed and b"BUSINESS_DONE" in output:
                colors["11"] = "abcd/1234/9876"
                user_changed = True
            while True:
                match = OSC.search(pending)
                if not match:
                    break
                pending = pending[match.end():]
                key, value = match.group(1).decode().rsplit(";", 1)
                require(key in colors, f"未知颜色项：{key}")
                if value == "?":
                    queries.append(key)
                    restoring = len(queries) >= 39
                    if case.startup_input and len(queries) == 1:
                        os.write(master, b"X")
                        continue
                    if restoring and case.response_fault == "timeout":
                        continue
                    if restoring and case.response_fault == "unexpected-input":
                        os.write(master, b"X")
                        continue
                    rgb = "not-rgb" if restoring and case.response_fault == "invalid-response" else colors[key]
                    reply = ("\x1b]" + key + ";rgb:" + rgb).encode() + case.terminator
                    wait = case.delay if len(queries) == 39 else 0
                    if case.fragmented:
                        cut = max(3, len(reply) // 2)
                        replies.append((time.monotonic() + wait, reply[:cut]))
                        replies.append((time.monotonic() + wait + 0.035, reply[cut:]))
                    else:
                        replies.append((time.monotonic() + wait, reply))
                elif value.startswith("#"):
                    digits = value[1:]
                    colors[key] = "/".join(digits[index:index + 2] * 2 for index in (0, 2, 4))
                    updates.append(key)
                elif value.startswith("rgb:"):
                    colors[key] = value[4:]
                    updates.append(key)
        else:
            timed_out = True
        after_flags = termios.tcgetattr(master)[3]
        finished, status = os.waitpid(pid, os.WNOHANG)
        reap_deadline = time.monotonic() + 0.5
        while not finished and time.monotonic() < reap_deadline:
            time.sleep(0.01)
            finished, status = os.waitpid(pid, os.WNOHANG)
        if not finished:
            os.kill(pid, signal.SIGKILL)
            _, status = os.waitpid(pid, 0)
            timed_out = True
    finally:
        os.close(master)
        if status is None:
            try:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            except ProcessLookupError:
                pass
        (folder / "terminal.log").write_bytes(output)
    require(not timed_out, "独立 PTY 超过有界等待，已回收本测试进程组")
    code = os.waitstatus_to_exitcode(status)
    require(code == case.expected_code, f"退出码 {code}，预期 {case.expected_code}")
    mode_mask = termios.ECHO | termios.ICANON
    require(before_flags & mode_mask == after_flags & mode_mask, "未恢复终端回显／规范输入模式")
    if case.plain or case.startup_input:
        require(not updates, "降级前不应修改终端颜色")
        require(colors == original, "降级改变了原配色")
        if case.plain:
            require(not queries, "纯文本模式不应发出 OSC 查询")
    elif case.response_fault:
        require(WARNING in output, "无法验证恢复安全性时应明确报告")
        require(len(updates) == 19, "查询失败时不应盲目覆盖当前颜色")
        require(list((folder / "tmp").glob("jobs-terminal-style.*/restore.sh")), "恢复失败应保留手工恢复入口")
    elif case.conflict:
        require(CONFLICT in output, "后续用户改色应明确报告冲突")
        require(colors["11"] == "abcd/1234/9876", "用户运行期间的新背景被覆盖")
        require(all(colors[key] == original[key] for key in KEYS if key != "11"), "非冲突颜色未恢复")
        require(len(updates) == 37, "只应恢复18项无冲突颜色")
    else:
        require(colors == original, "未精确恢复进入前的19项配色")
        require(len(queries) == 57 and len(updates) == 38, "应只保护一次，不得重复改色或重复查询")
        require(WARNING not in output, "正常恢复不应报告失败")
        require(not list((folder / "tmp").glob("jobs-terminal-style.*/restore.sh")), "成功恢复后不应保留过期恢复入口")
    if case.keyboard:
        require(b"INPUT_VALUE:demo value" in output, "业务键盘输入被配色探测消耗或改写")
    logging.info("PASS: %s (exit=%s, queries=%s, updates=%s)", case.name, code, len(queries), len(updates))


def main() -> int:
    """读取参数后按隔离场景运行，所有产物均在本轮临时目录。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yes", action="store_true", help="确认只运行独立 PTY 测试")
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[3] / "【MacOS】install.command")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    print("终端配色回归：只运行独立伪终端、假业务和模拟OSC，不执行安装、不操作原终端。", flush=True)
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
        work = Path(tempfile.mkdtemp(prefix="jobs-terminal-style-tests."))
    logging.basicConfig(level=logging.INFO, format="%(message)s", handlers=[logging.StreamHandler(), logging.FileHandler(work / "tests.log", encoding="utf-8")])
    logging.info("隔离现场：%s", work)
    header = extract_header(args.source.resolve())
    scenarios = [
        Scenario("normal"),
        Scenario("business-error", expected_code=7, business_code=7),
        Scenario("delayed-450ms", delay=0.45),
        Scenario("fragmented-bel", fragmented=True),
        Scenario("fragmented-st", fragmented=True, terminator=b"\x1b\\"),
        Scenario("later-color-change", expected_code=1, conflict=True),
        Scenario("restore-timeout", expected_code=1, response_fault="timeout"),
        Scenario("unexpected-input", expected_code=1, response_fault="unexpected-input"),
        Scenario("invalid-response", expected_code=1, response_fault="invalid-response"),
        Scenario("business-keyboard", keyboard=True),
        Scenario("startup-unrelated-input", startup_input=True),
        Scenario("signal-int", expected_code=130, stop_signal=signal.SIGINT),
        Scenario("signal-term", expected_code=143, stop_signal=signal.SIGTERM),
        Scenario("signal-hup", expected_code=129, stop_signal=signal.SIGHUP),
        Scenario("same-tty-nested", nested=True),
        Scenario("no-color", plain="NO_COLOR"),
        Scenario("dumb-terminal", plain="dumb"),
    ]
    failures = 0
    for case in scenarios:
        try:
            run_case(header, work, case)
        except Exception:
            failures += 1
            logging.exception("FAIL: %s", case.name)
    logging.info("终端配色回归：%s场景，%s失败；日志：%s", len(scenarios), failures, work / "tests.log")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
