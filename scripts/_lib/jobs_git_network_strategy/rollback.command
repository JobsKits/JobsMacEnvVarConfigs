#!/bin/zsh
# 脚本自述：
# - 核心用途：撤回本次全局 Git 网络策略挂载与 Sourcetree Git 路径选择。
# - 影响范围：只删除本次精确挂载块，恢复原本未设置的两个 Sourcetree 偏好键。
# - 运行提示：先退出 Sourcetree，再回车确认；--check 仅检查，后续配置冲突时停止。
# shell: zsh

STATE_DIR=""
LOG_FILE=""
TITLE_COLOR=""
BODY_COLOR=""
RESET_COLOR=""
# 从运行包寻找本次私有快照，不把机器路径写死在脚本里。
prepare_display_context() {
    setopt NO_NOMATCH
    local module_dir="${${(%):-%x}:A:h}"
    local runtime_dir="${JOBS_MAC_ENV_HOME:-$HOME/.JobsMacEnv}/Scripts/_lib/jobs_git_network_strategy"
    [[ -f "$module_dir/.active-run" ]] || module_dir="$runtime_dir"
    if [[ ! -r "$module_dir/.active-run" ]]; then
        print -u2 -r -- "没有找到本次安装快照；请用 Sourcetree Git 设置恢复原入口。"
        exit 1
    fi
    STATE_DIR="$(< "$module_dir/.active-run")"
    LOG_FILE="$STATE_DIR/audit.log"
    if [[ ! -d "$STATE_DIR" || ! -r "$STATE_DIR/mount.block" ]]; then
        print -u2 -r -- "恢复快照不可读，停止。"
        exit 1
    fi
    if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
        TITLE_COLOR=$'\033[1;31m'
        BODY_COLOR=$'\033[0;34m'
        RESET_COLOR=$'\033[0m'
    fi
}
# 先展示边界，实际恢复必须退出 Sourcetree 并在终端确认。
show_script_intro_and_wait() {
    prepare_display_context
    printf '%s恢复全局 Git 网络策略前状态%s\n' "$TITLE_COLOR" "$RESET_COLOR"
    printf '%s1、只撤回本次 Git 入口挂载与 Sourcetree 路径选择，保留源码与其它配置。%s\n' "$BODY_COLOR" "$RESET_COLOR"
    printf '%s2、不会关闭系统代理；后续改动与本次快照不匹配时停止。%s\n' "$BODY_COLOR" "$RESET_COLOR"
    printf '%s3、实际恢复前先退出 Sourcetree，避免旧进程回写设置。%s\n' "$BODY_COLOR" "$RESET_COLOR"
    printf '%s4、日志：%s；Ctrl+C 取消。%s\n' "$BODY_COLOR" "$LOG_FILE" "$RESET_COLOR"
    if [[ "${1:-}" == --check ]]; then
        return 0
    fi
    if [[ -n "${1:-}" || ! -t 0 ]]; then
        print -u2 -r -- "请在终端回车确认；--check 可只读检查。"
        exit 2
    fi
    if /usr/bin/pgrep -x Sourcetree >/dev/null; then
        print -u2 -r -- "Sourcetree 正在运行；请先正常退出后重试，避免中断任务。"
        exit 1
    fi
    read -r "?已了解范围，按回车恢复，Ctrl+C 取消：" _ || exit 1
}
# 只保存动作与结果，不记录完整配置或环境。
record_result() {
    print -r -- "time=$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ') action=rollback result=$1" >> "$LOG_FILE"
    print -r -- "$1"
}
# 只接受本次写入值或原始未设置状态，保留后续自定义选择。
check_sourcetree_state() {
    local current_path="" current_mode="" path_exit=0 mode_exit=0
    local expected_path="$(< "$STATE_DIR/wrapper.path")"
    current_path="$(/usr/bin/defaults read com.torusknot.SourceTreeNotMAS gitCustomPath 2>/dev/null)"
    path_exit=$?
    current_mode="$(/usr/bin/defaults read com.torusknot.SourceTreeNotMAS gitWhichOne 2>/dev/null)"
    mode_exit=$?
    if [[ "$path_exit" != 0 && "$mode_exit" != 0 ]]; then
        return 0
    fi
    [[ "$path_exit" == 0 && "$mode_exit" == 0 && "$current_path" == "$expected_path" && "$current_mode" == 1 ]]
}
# 对精确文本块做检查或局部删除，原文的其它内容与权限保持原样。
process_mount_block() {
    /usr/bin/perl - "$1" "$STATE_DIR/mount.block" "$2" <<'PERL'
use strict;
use warnings;
use Fcntl qw(O_WRONLY O_CREAT O_EXCL);
my ($file, $block_file, $mode) = @ARGV;
sub slurp {
    my ($file) = @_;
    open my $input, '<:raw', $file or die "无法读取挂载文件\n";
    local $/;
    return <$input>;
}
my $content = slurp($file);
my $block = slurp($block_file);
my $count = () = $content =~ /\Q$block\E/g;
if (!$count) {
    die "挂载块已被修改，保留当前内容并停止\n" if $content =~ /JOBS_GIT_NETWORK_STRATEGY_(?:BEGIN|END)/;
    exit 0;
}
die "发现重复挂载块，停止\n" if $count != 1;
die "恢复后的挂载块仍存在\n" if $mode eq 'absent';
exit 0 if $mode eq 'check';
my @metadata = stat($file);
$content =~ s/\Q$block\E//;
my $temporary = "$file.jobs-git-rollback.$$";
sysopen my $output, $temporary, O_WRONLY | O_CREAT | O_EXCL, 0600 or die "无法建立恢复临时文件\n";
binmode $output;
print {$output} $content or die "无法写入恢复文件\n";
close $output or die "无法保存恢复文件\n";
chmod($metadata[2] & 07777, $temporary) or die "无法恢复文件权限\n";
rename $temporary, $file or die "无法原子保存恢复文件\n";
PERL
}
# 按快照撤回两处挂载及两个偏好键；重复执行保持原状态。
restore_and_verify() {
    local source_file="$(< "$STATE_DIR/source.path")"
    local runtime_file="$(< "$STATE_DIR/runtime.path")"
    local mode="apply"
    [[ "${1:-}" == --check ]] && mode="check"
    if ! check_sourcetree_state ||
       ! process_mount_block "$source_file" check ||
       ! process_mount_block "$runtime_file" check; then
        [[ "$mode" == check ]] || record_result "发现后续变更；保留当前配置并停止"
        print -u2 -r -- "恢复前检查失败，未修改配置。"
        return 1
    fi
    if [[ "$mode" == check ]]; then
        print -r -- "挂载与 Sourcetree 设置匹配本次安装，或已处于原状态；可安全恢复。"
        return 0
    fi
    process_mount_block "$source_file" apply || return 1
    process_mount_block "$runtime_file" apply || return 1
    if ! check_sourcetree_state; then
        record_result "恢复过程中 Sourcetree 设置发生变化；保留当前偏好并停止"
        return 1
    fi
    if /usr/bin/defaults read com.torusknot.SourceTreeNotMAS gitCustomPath >/dev/null 2>&1; then
        /usr/bin/defaults delete com.torusknot.SourceTreeNotMAS gitCustomPath || return 1
    fi
    if /usr/bin/defaults read com.torusknot.SourceTreeNotMAS gitWhichOne >/dev/null 2>&1; then
        /usr/bin/defaults delete com.torusknot.SourceTreeNotMAS gitWhichOne || return 1
    fi
    if /usr/bin/defaults read com.torusknot.SourceTreeNotMAS gitCustomPath >/dev/null 2>&1 ||
       /usr/bin/defaults read com.torusknot.SourceTreeNotMAS gitWhichOne >/dev/null 2>&1; then
        record_result "Sourcetree 偏好恢复验证失败"
        return 1
    fi
    process_mount_block "$source_file" absent || return 1
    process_mount_block "$runtime_file" absent || return 1
    record_result "已撤回本次策略挂载；新终端与重新启动的 Sourcetree 使用原入口"
}
# 编排恢复说明、确认与局部恢复。
main() {
    show_script_intro_and_wait "$@" # 展示恢复范围，并在应用退出后确认。
    restore_and_verify "$@" # 保留后续改动，只撤回本次可核对的设置。
}

main "$@"

