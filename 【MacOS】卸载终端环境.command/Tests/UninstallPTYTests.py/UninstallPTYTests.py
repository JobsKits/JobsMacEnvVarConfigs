#!/usr/bin/env python3
"""Exercise only a copied terminal wrapper, real fzf, and a fake backend."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import struct
import termios
import time
import fcntl
import tempfile

SOURCE = Path(__file__).resolve().parents[2] / '【MacOS】卸载终端环境.command'
ROOT: Path | None = None
FAKE = '''#!/bin/zsh
main() {
  print -r -- "${(j:|:)@}" >> "$FAKE_BACKEND_LOG"
  if [[ "$1" == --catalog ]]; then
    printf 'cmd-alpha\\tAlpha tool\\tFake alpha\\tyes\\ncmd-beta\\tBeta tool\\tFake beta\\tyes\\ncmd-gamma\\tGamma tool\\tFake gamma\\tyes\\n'
  elif [[ " $* " == *" --dry-run "* ]]; then
    print -r -- '假后端：只读计划'
  else
    print -r -- '假后端：已收到明确选择'
  fi
}
main "$@"
'''

class Session:
    def __init__(self, name: str):
        self.root = ROOT / name
        (self.root / 'wrapper').mkdir(parents=True)
        (self.root / '【MacOS】环境管理后端.command').mkdir()
        (self.root / 'home').mkdir()
        self.entry = self.root / 'wrapper' / SOURCE.name
        shutil.copy2(SOURCE, self.entry)
        (self.root / '【MacOS】环境管理后端.command' / '【MacOS】环境管理后端.command').write_text(FAKE)
        self.log = self.root / 'calls.log'
        self.output = bytearray()
        self.mark = 0
        self.exit_code = None
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(self.root)
            env = dict(os.environ, HOME=str(self.root / 'home'), NO_COLOR='1', TERM='xterm-256color', SHELL='/bin/zsh', FAKE_BACKEND_LOG=str(self.log), LINES='45', COLUMNS='140')
            os.execve('/bin/zsh', ['/bin/zsh', str(self.entry)], env)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack('HHHH', 45, 140, 0, 0))

    def pump(self, timeout: float = .15):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if select.select([self.fd], [], [], min(.05, max(0, end-time.monotonic())))[0]:
                try:
                    chunk = os.read(self.fd, 65536)
                except OSError:
                    chunk = b''
                if chunk:
                    self.output.extend(chunk)
                    if b'\x1b[6n' in chunk:
                        os.write(self.fd, b'\x1b[1;1R')
            if self.exit_code is None:
                pid, status = os.waitpid(self.pid, os.WNOHANG)
                if pid:
                    self.exit_code = os.waitstatus_to_exitcode(status)

    def wait(self, token: str, timeout: float = 6):
        token_b = token.encode()
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            if token_b in self.output[self.mark:]:
                self.mark = len(self.output)
                self.pump(.12)
                return
            self.pump(.10)
            if self.exit_code is not None:
                break
        raise AssertionError(f'wait for {token!r}, exit={self.exit_code}, output tail={self.output[-1800:]!r}')

    def send(self, payload: bytes):
        os.write(self.fd, payload)
        self.pump(.18)

    def calls(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def writes(self):
        return [row for row in self.calls() if '|--yes' in row]

    def intro(self):
        self.wait('按回车阅读后继续')
        self.send(b'\r')
        self.wait('卸载组件 >')

    def alpha_plan(self):
        self.send(b'Alpha')
        self.send(b'\r')
        assert not any('--dry-run' in call for call in self.calls()), 'Enter must only toggle'
        self.send(b' ')
        self.wait('卸载确认 >')

    def confirm(self):
        self.send(b'\x1b[B')
        self.send(b'\r')

    def finish(self, wanted: int):
        end = time.monotonic() + 6
        while self.exit_code is None and time.monotonic() < end:
            self.pump(.10)
        normalized = self.exit_code if self.exit_code is None or self.exit_code >= 0 else 128 - self.exit_code
        assert normalized == wanted, f'exit expected {wanted}, got {self.exit_code}'
        (self.root / 'terminal.log').write_bytes(self.output)
        os.close(self.fd)

    def abort(self):
        if self.exit_code is None:
            # PTY child owns this process group; cleanup never targets user processes.
            os.killpg(self.pid, signal.SIGTERM)
            self.pump(.4)
        (self.root / 'terminal.log').write_bytes(self.output)

results = []
def case(name, fn):
    session = Session(name)
    try:
        fn(session)
        results.append({'case': name, 'passed': True, 'calls': session.calls()})
        print('PASS', name, flush=True)
    except Exception as exc:
        session.abort()
        results.append({'case': name, 'passed': False, 'error': str(exc), 'calls': session.calls()})
        print('FAIL', name, str(exc), flush=True)

def intro_ctrl_c(s):
    s.wait('按回车阅读后继续'); s.send(b'\x03'); s.finish(130); assert not s.calls()
def intro_eof(s):
    s.wait('按回车阅读后继续'); s.send(b'\x04'); s.finish(130); assert not s.calls()
def empty_selection(s):
    s.intro(); s.send(b' '); s.finish(130); assert not s.writes(); assert not any('--dry-run' in c for c in s.calls())
def default_cancel(s):
    s.intro(); s.alpha_plan(); s.send(b'\r'); s.finish(130); assert not s.writes()
def explicit_one(s):
    s.intro(); s.alpha_plan(); s.confirm(); s.finish(0); assert s.writes() == ['--uninstall|cmd-alpha|--yes']
def final_left(s):
    s.intro(); s.alpha_plan(); s.send(b'\x1b[D'); s.wait('卸载组件 >'); assert not s.writes(); s.send(b' '); s.wait('卸载确认 >'); s.confirm(); s.finish(0); assert s.writes() == ['--uninstall|cmd-alpha|--yes']
def unmatched_left(s):
    s.intro(); s.alpha_plan(); s.send(b'NOTMATCH'); s.send(b'\x1b[D'); s.wait('卸载组件 >'); s.send(b' '); s.wait('卸载确认 >'); s.confirm(); s.finish(0); assert s.writes() == ['--uninstall|cmd-alpha|--yes']
def explicit_two(s):
    s.intro(); s.send(b'Alpha'); s.send(b'\r'); s.send(b'\x15'); s.send(b'Beta'); s.send(b'\r'); s.send(b' '); s.wait('卸载确认 >'); s.confirm(); s.finish(0); rows=s.writes(); assert len(rows) == 1 and set(rows[0].split('|')[1:-1]) == {'cmd-alpha','cmd-beta'}
def all_then_confirm(s):
    s.intro(); s.send(b'\t'); s.send(b'\r'); s.wait('卸载组件 >'); s.send(b' '); s.wait('卸载确认 >'); s.confirm(); s.finish(0); rows=s.writes(); assert len(rows) == 1 and set(rows[0].split('|')[1:-1]) == {'cmd-alpha','cmd-beta','cmd-gamma'}
def all_then_clear(s):
    s.intro(); s.send(b'\t'); s.send(b'\r'); s.wait('卸载组件 >'); s.send(b'\t\t'); s.send(b'\r'); s.wait('卸载组件 >'); s.send(b' '); s.finish(130); assert not s.writes(); assert not any('--dry-run' in c for c in s.calls())
def root_left(s):
    s.intro(); s.send(b'\x1b[D'); s.finish(130); assert not s.writes()
# 参数授权和运行时只读检查；不创建用户环境或测试文件。
def prepare_test_arguments():
    global SOURCE
    parser = argparse.ArgumentParser(description='真实 fzf + 独立 PTY，只运行复制后的卸载包装器和假后端。')
    parser.add_argument('--yes', action='store_true', help='允许创建独立临时夹具')
    parser.add_argument('--source', type=Path, default=SOURCE, help='可选：待测包装器文件')
    parser.add_argument('--output', type=Path, help='可选：尚不存在的输出目录')
    args = parser.parse_args()
    print('终端卸载键位测试：仅复制包装器、真实 fzf、假后端；不运行真实环境后端。')
    if not args.yes:
        parser.error('需要 --yes；该授权只允许建立测试夹具。')
    SOURCE = args.source.resolve()
    if not SOURCE.is_file() or not shutil.which('fzf'):
        parser.error('需要可读的包装器和已安装的 fzf；测试不会安装依赖。')
    return args


# 只在授权后创建新的临时夹具，显式输出目录仍要求尚不存在。
def initialize_test_fixture(args):
    global ROOT
    if args.output:
        ROOT = args.output.resolve()
        ROOT.mkdir(parents=True, exist_ok=False)
    else:
        ROOT = Path(tempfile.mkdtemp(prefix='jobs-env-uninstall-pty.'))


# 顺序运行现有11个独立PTY用例，保留原名称、记录和失败状态。
def run_uninstall_pty_cases() -> int:
    for name, fn in [('intro_ctrl_c',intro_ctrl_c),('intro_eof',intro_eof),('empty_selection',empty_selection),('default_cancel',default_cancel),('explicit_one',explicit_one),('final_left',final_left),('unmatched_left',unmatched_left),('explicit_two',explicit_two),('all_then_confirm',all_then_confirm),('all_then_clear',all_then_clear),('root_left',root_left)]:
        case(name, fn)
    (ROOT / 'results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2))
    print('RESULTS', ROOT, flush=True)
    return 1 if any(not item['passed'] for item in results) else 0


# 入口只编排参数、隔离现场与测试集合。
def main() -> int:
    args = prepare_test_arguments()
    initialize_test_fixture(args)
    return run_uninstall_pty_cases()

if __name__ == '__main__':
    raise SystemExit(main())
