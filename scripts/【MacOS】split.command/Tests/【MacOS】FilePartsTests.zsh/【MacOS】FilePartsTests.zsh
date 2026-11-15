#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】FilePartsTests.zsh
# - 核心用途：在独占临时目录回归文件拆分、合并、输入验证和数据保留边界。
# - 影响范围：只处理测试自身的临时文件；不联网、不安装、不修改用户数据。
# - 运行提示：自动运行；日志及夹具保留在输出的临时目录，Ctrl+C 可取消。

TEST_SOURCE_PATH="$0"
TEST_ROOT=""
SCRIPTS_DIR=""
SPLIT_SCRIPT=""
MERGE_SCRIPT=""
PASSED=0
FAILED=0
# 先说明隔离范围，测试入口不等待人工输入。
show_script_intro() {
  print -r -- 'Jobs 文件拆分 / 合并隔离回归：仅使用本轮独占临时目录，自动运行，Ctrl+C 可取消。'
}
# 从测试自身位置解析目标源码，创建隔离夹具与纯文本日志。
initialize_test_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  export NO_COLOR=1
  SCRIPTS_DIR="${TEST_SOURCE_PATH:A:h:h:h:h}"
  SPLIT_SCRIPT="$SCRIPTS_DIR/【MacOS】split.command/【MacOS】split.command"
  MERGE_SCRIPT="$SCRIPTS_DIR/【MacOS】merge.command/【MacOS】merge.command"
  TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-file-parts-tests.XXXXXXXX")" || exit 1
  /bin/mkdir -p "$TEST_ROOT/libraries" "$TEST_ROOT/目标 中文 (空格)" "$TEST_ROOT/empty" "$TEST_ROOT/outside" || exit 1
  print -r -- "隔离目录：$TEST_ROOT"
}
# 校验依赖并提取函数；不向产品入口增加测试绕过开关。
prepare_test_libraries() {
  local script kind
  for kind in split merge; do
    script="$SCRIPTS_DIR/【MacOS】${kind}.command/【MacOS】${kind}.command"
    /bin/zsh -n "$script" || exit 1
    /usr/bin/awk '$0 != "jobs_terminal_style_bootstrap \"$0\" \"$@\"" && $0 != "main \"$@\"" { print }' "$script" > "$TEST_ROOT/libraries/$kind.zsh" || exit 1
  done
}
# 成功断言同时记录真实失败状态，避免错误被测试框架吞掉。
assert_success() {
  local label="$1"
  shift
  if "$@" >> "$TEST_ROOT/details.log" 2>&1; then
    (( PASSED += 1 ))
    print -r -- "PASS $label"
  else
    (( FAILED += 1 ))
    print -r -- "FAIL $label"
  fi
}
# 失败断言只接受被测操作真实返回非零。
assert_failure() {
  local label="$1"
  shift
  if "$@" >> "$TEST_ROOT/details.log" 2>&1; then
    (( FAILED += 1 ))
    print -r -- "FAIL $label（意外成功）"
  else
    (( PASSED += 1 ))
    print -r -- "PASS $label"
  fi
}
# 比较输出值，便于定位顺序和路径归属错误。
assert_equal() {
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    (( PASSED += 1 ))
    print -r -- "PASS $label"
  else
    (( FAILED += 1 ))
    print -r -- "FAIL $label"
    print -r -- "$label 实际：${(q)actual}；预期：${(q)expected}" >> "$TEST_ROOT/details.log"
  fi
}
# 加载拆分函数，所有运行日志均重定向到测试独占目录。
load_split_library() {
  source "$TEST_ROOT/libraries/split.zsh"
  SCRIPT_SOURCE_PATH="$SPLIT_SCRIPT"
  LOG_FILE="$TEST_ROOT/split.log"
  LOG_READY=1
}
# 加载合并函数，保留与真实入口相同的管道失败传播规则。
load_merge_library() {
  source "$TEST_ROOT/libraries/merge.zsh"
  SCRIPT_SOURCE_PATH="$MERGE_SCRIPT"
  LOG_FILE="$TEST_ROOT/merge.log"
  LOG_READY=1
}
# 核对输入只是字面路径，不进行变量或命令求值。
run_split_input_tests() {
  load_split_library
  local target="$TEST_ROOT/目标 中文 (空格)" source_file='' marker="$TEST_ROOT/should-not-exist" quoted='' escaped=''
  source_file="$target/样本.bin"
  printf 'abcdefghijklmnopqrstuvwxyz0123456789' > "$source_file"
  : > "$target/空.bin"
  printf 'x' > "$target/单字节.bin"
  printf 'already chunk' > "$target/旧.bin@1of2"
  printf 'hidden file' > "$target/.hidden"
  /bin/ln -s "$source_file" "$target/链接.bin"
  assert_failure '拆分空输入拒绝' normalize_target_input ''
  assert_failure '拆分纯空白拒绝' normalize_target_input $' \t\r'
  assert_failure '拆分不存在路径拒绝' normalize_target_input "$TEST_ROOT/missing"
  assert_failure '拆分多个路径拒绝' normalize_target_input "${(q)source_file} ${(q)target}"
  assert_failure '拆分符号链接拒绝' normalize_target_input "$target/链接.bin"
  assert_success '拆分真实中文空格路径' normalize_target_input "$source_file"
  assert_equal '拆分规范化路径' "$REPLY" "${source_file:A}"
  quoted="\"$source_file\""
  escaped="${(q)source_file} "
  assert_success '拆分引号路径' normalize_target_input "$quoted"
  assert_success '拆分拖入转义与尾空白' normalize_target_input "$escaped"
  assert_failure '拆分未闭合引号拒绝' normalize_target_input '"unterminated'
  assert_failure '拆分单引号拒绝' normalize_target_input "'"
  assert_failure '拆分尾部孤立转义拒绝' normalize_target_input $'unknown\\'
  assert_failure '拆分命令文本不执行' normalize_target_input "\$(touch ${(q)marker})"
  assert_failure '拆分注入标记未创建' test -e "$marker"
  assert_failure '拆分空文件拒绝' is_splittable_file "$target/空.bin"
  assert_failure '拆分单字节拒绝' is_splittable_file "$target/单字节.bin"
  assert_failure '拆分已有分卷拒绝' is_splittable_file "$target/旧.bin@1of2"
  assert_failure '拆分隐藏文件拒绝' is_splittable_file "$target/.hidden"
  assert_success '拆分普通非空文件接受' is_splittable_file "$source_file"
  assert_success '拆分无效目标循环后接受目录' choose_target_directory <<< $'\n\"\nunknown\\\n/not-real\n'"$TEST_ROOT/empty"$'\n'"$target"
  assert_equal '拆分持续重问最终目录' "$TARGET_DIR" "${target:A}"
  assert_failure '拆分EOF停止而不默认扫描' choose_target_directory < /dev/null
  assert_failure '拆分参数不能绕过手动输入' /bin/zsh -c 'source "$1"; require_target_directory "$2"' _ "$TEST_ROOT/libraries/split.zsh" "$target"
  TARGET_DIR="$target"
  TARGET_FILE=''
  MAX_CHUNK_BYTES=8
  assert_success '拆分仅扫描合格第一层大文件' find_large_files
  assert_equal '拆分候选数量排除空文件与旧分卷' "${#LARGE_FILES}" 1
  assert_equal '拆分候选指向实际源文件' "$LARGE_FILES[1]" "$source_file"
  MAX_CHUNK_BYTES=100
  assert_failure '拆分阈值过大不形成计划' find_large_files
}
# 真实生成分卷，并核对原数据、命名、边界和无覆盖发布。
run_split_data_tests() {
  load_split_library
  local target="$TEST_ROOT/目标 中文 (空格)" source_file="$TEST_ROOT/目标 中文 (空格)/样本.bin" part='' total=0 bytes=0
  local -a parts=()
  MAX_CHUNK_BYTES=8
  MAX_CHUNK_LABEL='8 字节（隔离测试）'
  assert_success '真实拆分与SHA校验' split_one_file "$source_file" <<< ''
  assert_success '拆分默认保留源文件' test -f "$source_file"
  parts=("$target/样本/"*(N))
  assert_equal '拆分卷数' "${#parts}" 5
  for part in "${parts[@]}"; do
    bytes="$(/usr/bin/stat -f %z "$part")"
    (( total += bytes ))
    assert_success "分卷不超过上限：${part:t}" test "$bytes" -le 8
  done
  assert_equal '分卷字节总和' "$total" 36
  assert_equal '按顺序分卷内容等于源文件' "$(stream_parts "${parts[@]}" | /usr/bin/shasum -a 256)" "$(/usr/bin/shasum -a 256 < "$source_file")"
  assert_failure '拆分不覆盖已有输出目录' split_one_file "$source_file" <<< 'YES'
  assert_success '拆分冲突仍保留源文件' test -f "$source_file"
  printf 'no extension source' > "$target/noextension"
  assert_success '无扩展名使用parts目录' split_one_file "$target/noextension" <<< ''
  assert_success '无扩展名分卷目录存在' test -d "$target/noextension.parts"
  printf 'source delete test' > "$target/delete.bin"
  local hash="$(file_sha256 "$target/delete.bin")"
  local identity="$(/usr/bin/stat -f '%d:%i' "$target/delete.bin")"
  assert_success '小写yes保留源' confirm_delete_source "$target/delete.bin" "$hash" "$identity" <<< 'yes'
  assert_success '小写yes未删除' test -f "$target/delete.bin"
  assert_success '源删除EOF保留' confirm_delete_source "$target/delete.bin" "$hash" "$identity" < /dev/null
  assert_success '精确YES删除已校验源' confirm_delete_source "$target/delete.bin" "$hash" "$identity" <<< 'YES'
  assert_failure '精确YES源已删除' test -e "$target/delete.bin"
  printf 'changed' > "$target/changed.bin"
  printf 'changed parts' > "$target/样本/样本.bin@1of5"
  local protected_hash="$(file_sha256 "$source_file")"
  local protected_identity="$(/usr/bin/stat -f '%d:%i' "$source_file")"
  assert_failure '分卷被改写时YES仍保留源' confirm_delete_source "$source_file" "$protected_hash" "$protected_identity" "$target/样本" 5 <<< 'YES'
  assert_success '分卷改写源仍在' test -f "$source_file"
  assert_failure '分卷目录消失时YES仍保留源' confirm_delete_source "$source_file" "$protected_hash" "$protected_identity" "$target/missing-parts" 5 <<< 'YES'
  assert_success '分卷缺失源仍在' test -f "$source_file"
  assert_failure '源内容变化拒绝删除' confirm_delete_source "$target/changed.bin" "$hash" '' <<< 'YES'
  assert_success '源内容变化仍保留' test -f "$target/changed.bin"
}
# 构建各类卷号清单，检查数字排序、缺卷与总数冲突。
run_merge_validation_tests() {
  load_merge_library
  local good="$TEST_ROOT/合并 中文 (空格)" bad="$TEST_ROOT/坏卷" other="$TEST_ROOT/其它"
  /bin/mkdir -p "$good" "$bad" "$other"
  printf 'first' > "$good/disk@name.iso@001of002"
  printf 'second' > "$good/disk@name.iso@002of002"
  assert_success '合并补零分卷与原名含@' validate_group "$good" 'disk@name.iso'
  assert_equal '合并数值卷号顺序首项' "${CHUNKS[1]:t}" 'disk@name.iso@001of002'
  assert_equal '合并数值卷号顺序末项' "${CHUNKS[2]:t}" 'disk@name.iso@002of002'
  assert_failure '合并空输入拒绝' normalize_directory_input ''
  assert_failure '合并纯空白拒绝' normalize_directory_input $' \t'
  assert_failure '合并普通文件不是目录' normalize_directory_input "$good/disk@name.iso@001of002"
  assert_success '合并引号与中文目录' normalize_directory_input "\"$good\""
  assert_equal '合并规范化目录' "$NORMALIZED_DIR" "${good:A}"
  assert_success '合并拖入转义目录' normalize_directory_input "${(q)good} "
  assert_failure '合并多路径拒绝' normalize_directory_input "${(q)good} ${(q)bad}"
  assert_failure '合并未闭合引号拒绝' normalize_directory_input "'unterminated"
  printf 'single' > "$bad/one.bin@1of1"
  assert_failure '单卷不构成合并操作' validate_group "$bad" one.bin
  printf 'missing' > "$bad/lost.bin@1of2"
  assert_failure '缺卷拒绝' validate_group "$bad" lost.bin
  printf 'first' > "$bad/duplicate.bin@1of2"
  printf 'same index' > "$bad/duplicate.bin@01of02"
  printf 'second' > "$bad/duplicate.bin@2of2"
  assert_failure '补零后重复卷号拒绝' validate_group "$bad" duplicate.bin
  printf 'first' > "$bad/mixed.bin@1of2"
  printf 'second' > "$bad/mixed.bin@2of3"
  assert_failure '总卷数冲突拒绝' validate_group "$bad" mixed.bin
  : > "$bad/empty.bin@1of2"
  printf 'second' > "$bad/empty.bin@2of2"
  assert_failure '空分卷拒绝' validate_group "$bad" empty.bin
  printf 'range' > "$bad/out.bin@3of2"
  assert_failure '越界卷号拒绝' validate_group "$bad" out.bin
  TARGET_DIR="$bad"
  TARGET_EXPLICIT=1
  assert_failure '仅有坏卷目录持续要求重新输入' find_volume_groups
  assert_success '合并空目录与坏卷重问后接受正确目标' require_target_directory <<< "$TEST_ROOT/empty"$'\n'"$bad"$'\n'"$good"
  assert_equal '合并持续重问最终目录' "$TARGET_DIR" "${good:A}"
  assert_equal '合并仅保留完整多卷组' "${#GROUP_NAMES}" 1
  assert_failure '合并EOF停止不默认扫描' /bin/zsh -c 'source "$1"; require_target_directory' _ "$TEST_ROOT/libraries/merge.zsh" < /dev/null
  assert_failure '合并参数不能绕过手动输入' /bin/zsh -c 'source "$1"; require_target_directory "$2"' _ "$TEST_ROOT/libraries/merge.zsh" "$good"
}
# 真实合并并逐字节核对，默认保留分卷且不覆盖原有目标。
run_merge_data_tests() {
  load_merge_library
  local good="$TEST_ROOT/合并 中文 (空格)" output="$TEST_ROOT/disk@name.iso" part=''
  TARGET_DIR="$good"
  TARGET_EXPLICIT=1
  TARGET_IS_VOLUME_DIR=1
  assert_success '真实合并与流摘要校验' merge_one_group "$good" 'disk@name.iso' <<< ''
  assert_equal '合并完整字节内容' "$(/bin/cat "$output")" 'firstsecond'
  assert_success '合并默认保留分卷' test -f "$good/disk@name.iso@001of002"
  assert_failure '合并不覆盖已存在目标' merge_one_group "$good" 'disk@name.iso' <<< 'YES'
  assert_equal '冲突输出原内容保留' "$(/bin/cat "$output")" 'firstsecond'
  assert_success '删除前重新建立精确分卷清单' validate_group "$good" 'disk@name.iso'
  local protected_output_hash="$(/usr/bin/shasum -a 256 < "$output")"
  protected_output_hash="${protected_output_hash%% *}"
  /bin/mv "$output" "$output.original"
  assert_failure '合并结果消失时YES仍保留分卷' offer_delete_chunks "$good" "$TEST_ROOT" "$output" "$protected_output_hash" <<< 'YES'
  assert_success '结果缺失后原分卷仍在' test -f "$good/disk@name.iso@001of002"
  printf 'tampered result' > "$output"
  assert_failure '合并结果改写时YES仍保留分卷' offer_delete_chunks "$good" "$TEST_ROOT" "$output" "$protected_output_hash" <<< 'YES'
  assert_success '结果改写后原分卷仍在' test -f "$good/disk@name.iso@001of002"
  /bin/mv "$output.original" "$output"
  assert_success '合并小写yes保留分卷' offer_delete_chunks "$good" "$TEST_ROOT" <<< 'yes'
  assert_success '小写yes分卷存在' test -f "$good/disk@name.iso@001of002"
  assert_success '精确YES仅删除已合并清单' offer_delete_chunks "$good" "$TEST_ROOT" <<< 'YES'
  assert_failure '已删除分卷不存在' test -e "$good/disk@name.iso@001of002"
  assert_success '合并成品在删除分卷后保留' test -f "$output"
  local parent="$TEST_ROOT/parent" child="$TEST_ROOT/parent/child"
  /bin/mkdir -p "$child"
  printf 'A' > "$child/child.bin@1of2"
  printf 'B' > "$child/child.bin@2of2"
  TARGET_DIR="$parent"
  TARGET_EXPLICIT=1
  assert_success '父目录发现一级分卷子目录' find_volume_groups
  assert_equal '父目录扫描不误判直接分卷目录' "$TARGET_IS_VOLUME_DIR" 0
  assert_success '子目录分卷还原在指定父目录' merge_one_group "$child" child.bin <<< ''
  assert_equal '父目录输出内容' "$(/bin/cat "$parent/child.bin")" AB
}
# 搬移完整入口后从无关目录解析位置，不依赖开发工作目录。
run_portability_tests() {
  load_split_library
  local relocated="$TEST_ROOT/搬移 改名的脚本包"
  /bin/mkdir -p "$relocated"
  /bin/cp "$SPLIT_SCRIPT" "$relocated/另一个入口.command"
  SCRIPT_SOURCE_PATH="$relocated/另一个入口.command"
  (
    builtin cd "$TEST_ROOT/outside" || exit 1
    prepare_display
    [[ "$SCRIPT_DIR" == "${relocated:A}" && "$SCRIPT_PATH" == "${relocated:A}/另一个入口.command" ]]
  )
  assert_equal '工程外cwd与改名定位状态' "$?" 0
}
# 以系统 expect 驱动真实 TTY 与 fzf，逐键检查导航、返回和默认取消。
run_pty_tests() {
  if [[ ! -x /usr/bin/expect ]] || ! command -v fzf >/dev/null 2>&1; then
    (( FAILED += 1 ))
    print -r -- 'FAIL 真实TTY回归需要系统expect及可用fzf，未执行的交互不计通过。'
    return 1
  fi
  cat > "$TEST_ROOT/case.zsh" <<'CASE_ZSH'
#!/bin/zsh
setopt NO_NOMATCH PIPE_FAIL
stty rows 38 columns 145
source "$JOBS_PARTS_TEST_ROOT/libraries/$1.zsh"
LOG_FILE="$JOBS_PARTS_TEST_ROOT/pty-business.log"
LOG_READY=1
TARGET_DIR="$JOBS_PARTS_TEST_ROOT"
TARGET_FILE=''
LARGE_FILES=("$JOBS_PARTS_TEST_ROOT/a.bin" "$JOBS_PARTS_TEST_ROOT/b.bin")
SELECTED_FILES=("$JOBS_PARTS_TEST_ROOT/a.bin")
GROUP_DIRS=("$JOBS_PARTS_TEST_ROOT/group-a" "$JOBS_PARTS_TEST_ROOT/group-b")
GROUP_NAMES=(a.bin b.bin)
SELECTED_GROUPS=(1)
case "$2" in
  standard) choose_split_standard; code=$?; print -r -- "CASE_RETURN:$code:$MAX_CHUNK_BYTES" ;;
  select_split) select_large_files; code=$?; print -r -- "CASE_RETURN:$code:${#SELECTED_FILES}:${SELECTED_FILES[1]:t}" ;;
  select_merge) select_volume_groups; code=$?; print -r -- "CASE_RETURN:$code:${#SELECTED_GROUPS}:${SELECTED_GROUPS[1]}" ;;
  confirm_split) confirm_split_plan; code=$?; print -r -- "CASE_RETURN:$code" ;;
  confirm_merge) confirm_merge_plan; code=$?; print -r -- "CASE_RETURN:$code" ;;
esac
CASE_ZSH
  export JOBS_PARTS_TEST_ROOT="$TEST_ROOT"
  export JOBS_PARTS_TEST_CASE="$TEST_ROOT/case.zsh"
  /usr/bin/expect <<'EXPECT_TCL'
log_user 0
set env(TERM) xterm-256color
set env(NO_COLOR) 1
set env(SHELL) /bin/zsh
set passed 0
set failed 0
set report [open "$env(JOBS_PARTS_TEST_ROOT)/pty.log" w]
# 启动一个独立选择器，处理光标位置查询后按真实键序列核对结果。
proc check_case {label kind mode keys expected} {
  global passed failed report env spawn_id
  spawn -noecho /bin/zsh "$env(JOBS_PARTS_TEST_CASE)" $kind $mode
  set transcript ""
  set timed_out 0
  set timeout 1
  expect {
    -exact "\033\[6n" { append transcript $expect_out(buffer); send -- "\033\[1;1R"; exp_continue }
    timeout {}
    eof { append transcript $expect_out(buffer) }
  }
  after 250
  foreach key $keys {
    send -- $key
    after 150
  }
  set timeout 8
  expect {
    -exact "\033\[6n" { append transcript $expect_out(buffer); send -- "\033\[1;1R"; exp_continue }
    eof { append transcript $expect_out(buffer) }
    timeout { append transcript $expect_out(buffer); set timed_out 1; send -- "\003"; after 100; catch {close} }
  }
  set process_result [wait]
  set actual_status [lindex $process_result 3]
  set ok [expr {!$timed_out && $actual_status == 0}]
  if {$expected eq "CANCEL_EXIT"} {
    set ok [expr {$ok && [string first "CASE_RETURN:" $transcript] < 0 && ([string first "已取消" $transcript] >= 0 || [string first "没有勾选" $transcript] >= 0)}]
  } else {
    set ok [expr {$ok && [string first $expected $transcript] >= 0}]
  }
  puts $report "===== $label status=$actual_status timeout=$timed_out ====="
  puts $report $transcript
  if {$ok} {
    incr passed
    puts "PASS TTY $label"
  } else {
    incr failed
    puts "FAIL TTY $label"
  }
}
check_case "单选下方向键" split standard [list "\033\[B" "\r"] "CASE_RETURN:0:104857600"
check_case "单选上下方向键" split standard [list "\033\[B" "\033\[A" "\r"] "CASE_RETURN:0:52428800"
check_case "拆分Tab导航后勾选" split select_split [list "\t" "\t" "\t" "\r" " "] "CASE_RETURN:0:1:a.bin"
check_case "拆分空选不采用高亮项" split select_split [list "\t" "\t" "\t" " "] "CASE_RETURN:2:0:"
check_case "拆分左键返回" split select_split [list "\033\[D"] "CASE_RETURN:3:0:"
check_case "拆分无匹配左键仍返回" split select_split [list "not-found" "\033\[D"] "CASE_RETURN:3:0:"
check_case "拆分取消行" split select_split [list "\033\[B" "\033\[B" "\r"] "CASE_RETURN:2:0:"
check_case "拆分Esc取消" split select_split [list "\033"] "CASE_RETURN:2:0:"
check_case "拆分全选行" split select_split [list "\r" "\033\[B" "\033\[B" "\033\[B" " "] "CASE_RETURN:0:2:"
check_case "拆分全选后清空行" split select_split [list "\r" "\033\[B" "\r" "\033\[B" "\033\[B" " "] "CASE_RETURN:2:0:"
check_case "合并Tab导航后勾选" merge select_merge [list "\t" "\t" "\t" "\r" " "] "CASE_RETURN:0:1:1"
check_case "合并空选不采用高亮项" merge select_merge [list "\t" "\t" "\t" " "] "CANCEL_EXIT"
check_case "合并取消行" merge select_merge [list "\033\[B" "\033\[B" "\r"] "CANCEL_EXIT"
check_case "合并Esc取消" merge select_merge [list "\033"] "CANCEL_EXIT"
check_case "合并全选行" merge select_merge [list "\r" "\033\[B" "\033\[B" "\033\[B" " "] "CASE_RETURN:0:2:"
check_case "合并全选后清空行" merge select_merge [list "\r" "\033\[B" "\r" "\033\[B" "\033\[B" " "] "CANCEL_EXIT"
check_case "拆分执行默认取消" split confirm_split [list "\r"] "CASE_RETURN:2"
check_case "拆分执行显式确认" split confirm_split [list "\033\[B" "\r"] "CASE_RETURN:0"
check_case "拆分执行返回上一层" split confirm_split [list "\033\[D"] "CASE_RETURN:3"
check_case "合并执行默认取消" merge confirm_merge [list "\r"] "CASE_RETURN:2"
check_case "合并执行显式确认" merge confirm_merge [list "\033\[B" "\r"] "CASE_RETURN:0"
check_case "合并执行返回上一层" merge confirm_merge [list "\033\[D"] "CASE_RETURN:3"
close $report
set counts [open "$env(JOBS_PARTS_TEST_ROOT)/pty-counts.txt" w]
puts $counts "$passed $failed"
close $counts
exit [expr {$failed > 0}]
EXPECT_TCL
  local pty_passed=0 pty_failed=0
  if [[ -r "$TEST_ROOT/pty-counts.txt" ]]; then
    read -r pty_passed pty_failed < "$TEST_ROOT/pty-counts.txt"
    (( PASSED += pty_passed ))
    (( FAILED += pty_failed ))
  else
    (( FAILED += 1 ))
    print -r -- 'FAIL 真实TTY驱动未生成结果。'
  fi
}
# 汇总真实失败数并返回适当退出码；夹具保留便于核对。
finish_tests() {
  print -r -- "结果：$PASSED 通过，$FAILED 失败。详细日志：$TEST_ROOT/details.log"
  (( FAILED == 0 ))
}
# 编排隔离准备和输入、数据及可迁移性回归。
main() {
  show_script_intro # 说明测试自动运行与隔离范围。
  initialize_test_runtime # 从自身位置定位源码并创建独占临时目录。
  prepare_test_libraries # 语法检查后提取产品函数，不执行业务入口。
  run_split_input_tests # 覆盖路径解析和无效目标持续重问。
  run_split_data_tests # 真实拆分并核对分卷、摘要与源文件保护。
  run_merge_validation_tests # 拒绝单卷、缺卷、重复号和总数冲突。
  run_merge_data_tests # 真实合并并核对输出归属与删除门禁。
  run_portability_tests # 验证改名搬移与工程外工作目录定位。
  run_pty_tests # 在真实fzf中逐键核对选择、返回和执行确认。
  finish_tests # 输出汇总并传递失败状态。
}

main "$@"
