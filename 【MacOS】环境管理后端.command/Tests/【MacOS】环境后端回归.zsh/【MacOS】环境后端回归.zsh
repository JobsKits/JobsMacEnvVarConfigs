#!/bin/zsh
# 脚本自述：
# - 用途：在独立 HOME 和复制后的源码中验证环境后端，不执行真实依赖或用户工具。
# - 影响：仅创建新的临时夹具，保留所有测试输出；必须显式 --yes。
# shell: zsh
ENTRY_PATH="${0:A}"
BACKEND=""
SOURCE_ROOT=""
TEST_ROOT=""
CHECKS=0
FAILURES=0

record_check() {
  local result="$1" description="$2"
  (( CHECKS += 1 ))
  if (( result == 0 )); then print -r -- "✔ $description"; else print -u2 -r -- "✖ $description"; (( FAILURES += 1 )); fi
}
expect_code() {
  local wanted="$1" description="$2" actual=0
  shift 2
  "$@" > "$TEST_ROOT/step-$CHECKS.log" 2>&1 || actual=$?
  if (( actual == wanted )); then record_check 0 "$description"; else record_check 1 "$description（预期 $wanted，实际 $actual；$TEST_ROOT/step-$CHECKS.log）"; fi
}
assert_test() {
  local description="$1" actual=0
  shift
  "$@" || actual=$?
  record_check "$actual" "$description"
}
run_backend() {
  local fixture="$1"
  shift
  env HOME="$fixture" /bin/zsh "$BACKEND" "$@"
}
initialize_fixture() {
  print -r -- '环境后端回归：独立 HOME、真实文件复制与收据；不安装或卸载当前用户环境。'
  [[ "${1:-}" == --yes ]] || { print -u2 -r -- '需要 --yes；仅创建临时夹具。'; return 2; }
  setopt NO_NOMATCH PIPE_FAIL
  BACKEND="${ENTRY_PATH:h:h:h}/【MacOS】环境管理后端.command"
  SOURCE_ROOT="${BACKEND:h:h}"
  [[ -f "$BACKEND" && -d "$SOURCE_ROOT/scripts" ]] || return 1
  TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-env-regression.XXXXXXXX")" || return 1
  # 测试使用冻结的源码副本，工作树后续编辑不影响正在执行的 zsh 字节流。
  local snapshot="$TEST_ROOT/fixed-source"
  /bin/mkdir -p "$snapshot/【MacOS】环境管理后端.command" || return 1
  /bin/cp -p "$BACKEND" "$snapshot/【MacOS】环境管理后端.command/【MacOS】环境管理后端.command" || return 1
  /bin/cp -R "$SOURCE_ROOT/scripts" "$SOURCE_ROOT/zsh" "$SOURCE_ROOT/Sys" "$snapshot/" || return 1
  /bin/cp "$SOURCE_ROOT/sync_env.txt" "$snapshot/sync_env.txt" || return 1
  SOURCE_ROOT="$snapshot"
  BACKEND="$snapshot/【MacOS】环境管理后端.command/【MacOS】环境管理后端.command"
  /bin/mkdir -p "$TEST_ROOT/用户 HOME" || return 1
}
run_readonly_checks() {
  local fixture="$TEST_ROOT/用户 HOME" catalog=""
  expect_code 0 '目录查询成功' run_backend "$fixture" --catalog
  catalog="$(run_backend "$fixture" --catalog)" || return 1
  assert_test '目录严格为四列、50个稳定组件' /bin/zsh -f -c '[[ $(print -r -- "$1" | awk -F"\t" "NF != 4 { bad=1 } END { if (bad || NR != 50) exit 1 }") == "" ]]' _ "$catalog"
  expect_code 0 '全部安装计划可只读生成' run_backend "$fixture" --install all --dry-run
  expect_code 2 'all 混入未知ID不能吞掉错误' run_backend "$fixture" --install all typo --yes
  expect_code 2 '没有 --yes 不执行真实安装' run_backend "$fixture" --install cmd-cor
  assert_test '只读操作未创建用户文件或状态目录' /bin/zsh -f -c '[[ -z $(find "$1" -mindepth 1 -print -quit) ]]' _ "$fixture"
}
run_roundtrip_checks() {
  local fixture="$TEST_ROOT/用户 HOME"
  /bin/mkdir -p "$fixture/.local/bin"
  printf '# 原配置末尾空行必须保留\nexport USER_KEEP=1\n\n\n' > "$fixture/.zshrc"
  printf '# 原有同名命令\n' > "$fixture/.local/bin/cor"
  /bin/chmod 640 "$fixture/.local/bin/cor"
  /bin/cp -p "$fixture/.zshrc" "$TEST_ROOT/original.zshrc"
  /bin/cp -p "$fixture/.local/bin/cor" "$TEST_ROOT/original.cor"
  expect_code 0 '单选命令自动补齐公共支持与Shell入口' run_backend "$fixture" --yes cmd-cor --install
  assert_test '没有部署未选的清理命令' /bin/zsh -f -c '[[ ! -e "$1/.local/bin/clean" && ! -e "$1/.JobsMacEnv/Scripts/【MacOS】clean.command" && ! -e "$1/.JobsMacEnv/Scripts/clean.command" ]]' _ "$fixture"
  assert_test '完整命令包和函数加载器均存在' /bin/zsh -f -c '[[ -f "$1/.JobsMacEnv/Scripts/【MacOS】cor.command/【MacOS】cor.command" && -f "$1/.JobsMacEnv/zsh/custom/【MacOS】local.zsh/【MacOS】local.zsh" ]]' _ "$fixture"
  assert_test '生成的环境与别名通过zsh语法检查' /bin/zsh -f -n "$fixture/.JobsMacEnv/zsh/env.zsh" "$fixture/.JobsMacEnv/zsh/aliases.zsh"
  /usr/bin/head -c "$(/usr/bin/stat -f %z "$TEST_ROOT/original.zshrc")" "$fixture/.zshrc" > "$TEST_ROOT/prefix.zshrc"
  assert_test '安装保留原 .zshrc 全部字节（含末尾空行）' /usr/bin/cmp -s "$TEST_ROOT/original.zshrc" "$TEST_ROOT/prefix.zshrc"
  assert_test '组件状态为 yes' /bin/zsh -f -c 'env HOME="$1" /bin/zsh "$2" --catalog | awk -F"\t" '\''$1 == "cmd-cor" { found=1; if ($4 != "yes") exit 1 } END { if (!found) exit 1 }'\''' _ "$fixture" "$BACKEND"
  /bin/cp "$fixture/.zshrc" "$TEST_ROOT/installed.zshrc"
  /bin/cp "$fixture/.local/bin/cor" "$TEST_ROOT/installed.cor"
  expect_code 0 '重复安装成功且仍使用最初备份' run_backend "$fixture" --install cmd-cor --yes
  assert_test '重复安装不会累积Shell块或空行' /usr/bin/cmp -s "$TEST_ROOT/installed.zshrc" "$fixture/.zshrc"
  expect_code 3 '不能单独卸载仍被命令依赖的公共支持' run_backend "$fixture" --uninstall runtime-support --yes
  print -r -- '# 用户后来修改' >> "$fixture/.local/bin/cor"
  /bin/cp "$fixture/.local/bin/cor" "$TEST_ROOT/changed.cor"
  expect_code 3 '用户修改后卸载返回非零' run_backend "$fixture" --uninstall cmd-cor --yes
  assert_test '用户后来修改完整保留' /usr/bin/cmp -s "$TEST_ROOT/changed.cor" "$fixture/.local/bin/cor"
  assert_test '用户修改时整个命令包都保留' /bin/zsh -f -c '[[ -f "$1/.JobsMacEnv/Scripts/【MacOS】cor.command/【MacOS】cor.command" ]]' _ "$fixture"
  expect_code 3 '用户修改后重新安装也不能覆盖' run_backend "$fixture" --install cmd-cor --yes
  /bin/cp -p "$TEST_ROOT/installed.cor" "$fixture/.local/bin/cor"
  expect_code 0 '解决冲突后全部卸载可重复续跑' run_backend "$fixture" --uninstall all --yes
  assert_test '原.zshrc逐字节恢复' /usr/bin/cmp -s "$TEST_ROOT/original.zshrc" "$fixture/.zshrc"
  assert_test '原同名命令逐字节恢复' /usr/bin/cmp -s "$TEST_ROOT/original.cor" "$fixture/.local/bin/cor"
  assert_test '原同名命令权限恢复' /bin/zsh -f -c '[[ $(stat -f %Lp "$1") == 640 ]]' _ "$fixture/.local/bin/cor"
  expect_code 0 '重复卸载缺失命令安全跳过' run_backend "$fixture" --uninstall cmd-clean --yes
}
run_guard_checks() {
  local fixture="$TEST_ROOT/符号链接HOME" legacy="$TEST_ROOT/历史HOME" shared="$TEST_ROOT/共享HOME" active="$TEST_ROOT/Shell修改HOME"
  /bin/mkdir -p "$fixture" "$legacy/.local/bin" "$shared/.local/bin" "$active"
  printf '# 链接原件\n' > "$TEST_ROOT/link-original"
  /bin/ln -s "$TEST_ROOT/link-original" "$fixture/.zshrc"
  expect_code 3 '符号链接.zshrc不会被穿透覆盖' run_backend "$fixture" --install shell-entry --yes
  assert_test '符号链接原件仍在' /bin/zsh -f -c '[[ -L "$1/.zshrc" && $(cat "$2") == "# 链接原件" ]]' _ "$fixture" "$TEST_ROOT/link-original"
  printf '# 旧安装，不能推断之前内容\n' > "$legacy/.local/bin/cor"
  expect_code 3 '历史无收据命令保留并返回未完成' run_backend "$legacy" --uninstall cmd-cor --yes
  assert_test '历史无收据文件仍在' /usr/bin/grep -Fq '旧安装' "$legacy/.local/bin/cor"
  expect_code 0 '共享测试先安装完整命令' run_backend "$shared" --install cmd-cor --yes
  printf '#!/bin/zsh\nsource "$HOME/.JobsMacEnv/Scripts/_lib/【MacOS】jobs_path_lib.zsh/【MacOS】jobs_path_lib.zsh"\n' > "$shared/.local/bin/legacy-custom"
  expect_code 3 '无收据的自定义共享引用阻止删除公共支持' run_backend "$shared" --uninstall all --yes
  assert_test '未知共享引用与支持均保留' /bin/zsh -f -c '[[ -f "$1/.local/bin/legacy-custom" && -f "$1/.JobsMacEnv/Scripts/_lib/【MacOS】jobs_path_lib.zsh/【MacOS】jobs_path_lib.zsh" ]]' _ "$shared"
  expect_code 0 'Shell修改夹具先安装命令及公共环境' run_backend "$active" --install cmd-cor --yes
  print -r -- '# 用户在受管Shell入口之后追加内容' >> "$active/.zshrc"
  /bin/cp "$active/.zshrc" "$TEST_ROOT/active.changed.zshrc"
  expect_code 3 '改.zshrc后全部卸载明确返回未完成' run_backend "$active" --uninstall all --yes
  assert_test '改.zshrc后全部共享加载模块保留' /bin/zsh -f -c '[[ -f "$1/.JobsMacEnv/.zshrc" && -f "$1/.JobsMacEnv/zsh/【MacOS】env_methods.zsh/【MacOS】env_methods.zsh" && -f "$1/.JobsMacEnv/zsh/【MacOS】user_mounts.zsh/【MacOS】user_mounts.zsh" && -f "$1/.JobsMacEnv/zsh/custom/【MacOS】local.zsh/【MacOS】local.zsh" && -f "$1/.JobsMacEnv/Scripts/【MacOS】entrypoints.command/【MacOS】entrypoints.command" ]]' _ "$active"
  assert_test '修改后的.zshrc全部字节保留' /usr/bin/cmp -s "$TEST_ROOT/active.changed.zshrc" "$active/.zshrc"
}
run_relocated_and_concurrent_checks() {
  local payload="$TEST_ROOT/中文 空格移动后的源码" fixture="$TEST_ROOT/并发HOME" relocated_backend=""
  /bin/mkdir -p "$payload/【MacOS】环境管理后端.command" "$fixture"
  /bin/cp "$BACKEND" "$payload/【MacOS】环境管理后端.command/【MacOS】环境管理后端.command"
  /bin/cp -R "$SOURCE_ROOT/scripts" "$SOURCE_ROOT/zsh" "$SOURCE_ROOT/Sys" "$payload/"
  /bin/cp "$SOURCE_ROOT/sync_env.txt" "$payload/sync_env.txt"
  relocated_backend="$payload/【MacOS】环境管理后端.command/【MacOS】环境管理后端.command"
  expect_code 0 '完整源码移动改名后仍能只读计划' env HOME="$fixture" /bin/zsh "$relocated_backend" --install cmd-cor --dry-run
  /usr/bin/awk '{ print; if ($0 == "env_begin_transaction() {") print "  print -r -- concurrent-change >> \"$HOME/.zshrc\"" }' "$BACKEND" > "$relocated_backend"
  printf '# 开始计划时的配置\n' > "$fixture/.zshrc"
  expect_code 3 '计划后.zshrc发生并发变化时停止发布' env HOME="$fixture" /bin/zsh "$relocated_backend" --install shell-entry --yes
  assert_test '计划后的并发内容保留' /usr/bin/grep -Fq concurrent-change "$fixture/.zshrc"
  assert_test '并发冲突不发布过期Shell候选' /bin/zsh -f -c '! grep -Fq "# >>> JobsMacEnv managed shell entry >>>" "$1/.zshrc"' _ "$fixture"
  /bin/mv "$payload/zsh/【MacOS】env_methods.zsh/【MacOS】env_methods.zsh" "$payload/zsh/【MacOS】env_methods.zsh/【MacOS】env_methods.zsh.saved"
  expect_code 1 '源文件缺失在写入前阻止安装' env HOME="$fixture" /bin/zsh "$relocated_backend" --install env-core --yes
}
run_complete_catalog_checks() {
  local fixture="$TEST_ROOT/完整目录HOME"
  /bin/mkdir -p "$fixture"
  expect_code 0 '完整50组件全部可安装（不执行已部署业务）' run_backend "$fixture" --install all --yes
  assert_test '媒体别名和窗口录屏完整源码已部署' /bin/zsh -f -c '[[ -x "$1/.local/bin/opus" && -d "$1/.JobsMacEnv/Scripts/【MacOS】jrecord.command/Core" ]]' _ "$fixture"
  expect_code 0 '完整50组件全部可按收据卸载' run_backend "$fixture" --uninstall all --yes
  assert_test '全部撤回后没有遗留受管文件' /bin/zsh -f -c '[[ -z $(find "$1/.JobsMacEnv" "$1/.local/bin" -type f -print -quit) && ! -e "$1/.zshrc" ]]' _ "$fixture"
}
finish_checks() {
  printf '验证：%s 项；失败：%s 项。夹具与日志保留：%s\n' "$CHECKS" "$FAILURES" "$TEST_ROOT"
  (( FAILURES == 0 ))
}
main() {
  initialize_fixture "$@" || return $? # 只有显式测试授权才创建全新临时目录。
  run_readonly_checks || return $? # 验证机器目录、演练与缺少授权时零用户写入。
  run_roundtrip_checks || return $? # 验证选择、依赖、重装、冲突、恢复与权限。
  run_guard_checks || return $? # 验证链接、历史安装与未知共享引用的保护边界。
  run_relocated_and_concurrent_checks || return $? # 验证源码迁移、并发与缺少源文件。
  run_complete_catalog_checks || return $? # 全量走完每个组件的真实文件生命周期。
  finish_checks # 汇总真实结果，不删除测试现场。
}
main "$@"
