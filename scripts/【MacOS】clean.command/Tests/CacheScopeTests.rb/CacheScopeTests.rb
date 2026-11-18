# frozen_string_literal: true
# Jobs：只在临时 HOME 中验证通用缓存选择与保护，不执行真实 clean。
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'pty'
require 'timeout'

class CacheScopeTests < Minitest::Test
  TERMINAL = File.expand_path('../../【MacOS】clean.command', __dir__)
  MENU = File.expand_path('../../../../../../OS@Extension/MacOS@Extension/JobsDiskSpaceInfo/Scripts/【MacOS】清理磁盘空间.command/【MacOS】清理磁盘空间.command', __dir__)
  SCRIPTS = [TERMINAL, MENU].freeze

  def fixtures(source_transform = nil, scripts: SCRIPTS)
    scripts.each do |script|
      Dir.mktmpdir('jobs-cache-scope-') do |directory|
        directory = File.realpath(directory)
        home = File.join(directory, '不同电脑 用户')
        temp = File.join(directory, '临时目录')
        cache = File.join(home, 'Library/Caches')
        FileUtils.mkdir_p([cache, temp])
        source = File.read(script).sub(/^(?:main|initialize_script_module) "\$@"\s*\z/, '')
        source = source_transform.call(source) if source_transform
        definitions = File.join(directory, 'definitions.zsh')
        File.write(definitions, source)
        begin
          yield home, temp, cache, definitions
        ensure
          Dir.glob(File.join(directory, '**/*'), File::FNM_DOTMATCH).reverse_each do |path|
            File.chmod(File.directory?(path) ? 0o700 : 0o600, path) unless File.symlink?(path)
          rescue Errno::ENOENT, Errno::EPERM
            # 夹具只还原本轮路径，允许测试已删除的对象不存在。
          end
        end
      end
    end
  end

  def code_prefix
    <<~'ZSH'
      source "$1"
      JOBS_CLEAN_CONFIRMED=1
      LOG_FILE="$TMPDIR/scope.log"
      : > "$LOG_FILE"
      log() { print -r -- "$1" | tee -a "$LOG_FILE"; }
      jobs_clean_cache_select_candidates() { /usr/bin/awk -F '\t' '$1 ~ /^[0-9]+$/ {print $1}' "$1"; }
      jobs_clean_cache_confirm_selected() { return 0; }
    ZSH
  end

  def run_code(home, temp, definitions, code)
    Open3.capture3({ 'HOME' => home, 'TMPDIR' => temp, 'NO_COLOR' => '1', 'PLAIN_OUTPUT' => '1' }, '/bin/zsh', '-c', code_prefix + code, '--', definitions)
  end

  def run_runtime(home, temp, definitions, code)
    Open3.capture3({ 'HOME' => home, 'TMPDIR' => temp, 'NO_COLOR' => '1', 'PLAIN_OUTPUT' => '1' }, '/bin/zsh', '-f', '-c', "source \"$1\"\n" + code, '--', definitions)
  end

  def test_runtime_without_confirmation_does_not_create_logs
    fixtures(nil, scripts: [TERMINAL]) do |home, temp, _cache, definitions|
      out, err, status = run_runtime(home, temp, definitions, <<~'ZSH')
        JOBS_CLEAN_CONFIRMED=0
        jobs_clean_prepare_runtime
      ZSH
      assert_equal 1, status.exitstatus, out + err
      assert_empty Dir.children(temp)
    end
  end

  def test_runtime_logs_are_private_unique_and_preserve_existing_files
    fixtures(nil, scripts: [TERMINAL]) do |home, temp, _cache, definitions|
      sentinel = File.join(temp, 'keep.log')
      File.write(sentinel, 'keep existing log')
      %w[JobsClean.XXXXXXXX JobsDiskSpaceCleanup.XXXXXXXX.log].each do |name|
        File.symlink(sentinel, File.join(temp, name))
      end
      out, err, status = run_runtime(home, temp, definitions, <<~'ZSH')
        umask 000
        JOBS_CLEAN_CONFIRMED=1
        jobs_clean_prepare_runtime || exit $?
        first_log="$LOG_FILE"
        print -r -- 'first run retained' > "$first_log"
        jobs_clean_prepare_runtime || exit $?
        printf '%s\n%s\n' "$first_log" "$LOG_FILE"
      ZSH
      assert status.success?, out + err
      logs = out.lines.map(&:strip)
      assert_equal 2, logs.size
      refute_equal logs[0], logs[1]
      logs.each do |path|
        assert_equal temp, File.dirname(path)
        assert File.file?(path), path
        refute File.symlink?(path), path
        assert_equal 0o600, File.stat(path).mode & 0o777
      end
      assert_equal "first run retained\n", File.read(logs.first)
      assert_empty File.read(logs.last)
      assert_equal 'keep existing log', File.read(sentinel)
    end
  end

  def test_runtime_log_creation_failure_stops_before_regular_cleanup
    fixtures(nil, scripts: [TERMINAL]) do |home, temp, _cache, definitions|
      missing_temp = File.join(temp, '不存在 临时目录')
      out, err, status = run_runtime(home, missing_temp, definitions, <<~'ZSH')
        jobs_clean_run_xcode_stage() { return 0; }
        show_script_intro_and_wait() { JOBS_CLEAN_CONFIRMED=1; }
        jobs_clean_run_regular_stage() { print -r -- 'unexpected cleanup'; }
        jobs_clean_run_stages
        result=$?
        printf 'LOG:<%s>\n' "$LOG_FILE"
        exit "$result"
      ZSH
      assert_equal 1, status.exitstatus, out + err
      assert_includes err, '无法在临时目录创建清理日志'
      assert_includes out, 'LOG:<>'
      refute_includes out, 'unexpected cleanup'
      refute File.exist?(missing_temp)
    end
  end

  def test_clean_machine_uses_explicit_selection_and_keeps_unselected
    fixtures do |home, temp, cache, definitions|
      File.write(File.join(cache, '普通 应用'), 'remove')
      File.write(File.join(cache, 'keep'), 'keep')
      out, err, status = run_code(home, temp, definitions, <<~'ZSH')
        jobs_clean_cache_select_candidates() { /usr/bin/awk -F '\t' '$2 ~ /^普通/ {print $1}' "$1"; }
        jobs_clean_user_caches
      ZSH
      assert status.success?, out + err
      refute File.exist?(File.join(cache, '普通 应用'))
      assert_equal 'keep', File.read(File.join(cache, 'keep'))
    end
  end

  def test_empty_selection_never_checks_or_deletes_candidates
    fixtures do |home, temp, cache, definitions|
      File.write(File.join(cache, 'keep'), 'keep')
      out, err, status = run_code(home, temp, definitions, <<~'ZSH')
        jobs_clean_cache_select_candidates() { return 0; }
        jobs_clean_cache_snapshot() { print unexpected >> "$TMPDIR/checks"; return 99; }
        jobs_clean_user_caches
      ZSH
      assert status.success?, out + err
      assert File.exist?(File.join(cache, 'keep'))
      refute File.exist?(File.join(temp, 'checks'))
    end
  end

  def test_nonempty_confirmation_skips_and_eof_propagates_cancel
    [2, 130].each do |confirm_code|
      fixtures do |home, temp, cache, definitions|
        File.write(File.join(cache, 'keep'), 'keep')
        out, err, status = run_code(home, temp, definitions, "jobs_clean_cache_confirm_selected() { return #{confirm_code}; }\njobs_clean_user_caches\n")
        assert_equal(confirm_code == 2 ? 0 : 130, status.exitstatus, out + err)
        assert_equal 'keep', File.read(File.join(cache, 'keep'))
      end
    end
  end

  def test_randomly_named_development_and_sdk_trees_are_protected
    fixtures do |home, temp, cache, definitions|
      %w[go.mod package.json Cargo.toml pyvenv.cfg package.xml source.properties .git].each_with_index do |marker, index|
        tree = File.join(cache, "random-#{index}/deep")
        FileUtils.mkdir_p(tree)
        File.write(File.join(tree, marker), 'managed')
      end
      out, err, status = run_code(home, temp, definitions, 'jobs_clean_user_caches')
      assert status.success?, out + err
      assert_equal 7, Dir.children(cache).size
      assert_includes out + err, '源码、依赖或SDK标记'
    end
  end

  def test_readonly_directory_with_writable_file_is_protected_without_permission_changes
    fixtures do |home, temp, cache, definitions|
      tree = File.join(cache, 'random-environment')
      FileUtils.mkdir_p(tree)
      File.write(File.join(tree, 'module.go'), 'keep')
      File.chmod(0o555, tree)
      out, err, status = run_code(home, temp, definitions, 'jobs_clean_user_caches')
      assert status.success?, out + err
      assert_equal 'keep', File.read(File.join(tree, 'module.go'))
      assert_equal 0o555, File.stat(tree).mode & 0o777
    end
  end

  def test_nested_link_and_nonlocal_device_preserve_entire_candidate
    fixtures do |home, temp, cache, definitions|
      tree = File.join(cache, 'contains-link')
      outside = File.join(temp, 'outside')
      FileUtils.mkdir_p(tree)
      File.write(outside, 'keep')
      File.symlink(outside, File.join(tree, 'alias'))
      out, err, status = run_code(home, temp, definitions, 'jobs_clean_user_caches')
      assert status.success?, out + err
      assert File.symlink?(File.join(tree, 'alias'))
      assert_equal 'keep', File.read(outside)
      out, err, status = run_code(home, temp, definitions, 'jobs_clean_cache_snapshot "$HOME/Library/Caches/contains-link" invalid "$TMPDIR/snapshot"')
      assert_equal 2, status.exitstatus, out + err
    end
  end

  def test_scan_budget_and_depth_are_conservative
    transform = ->(source) { source.sub('count < 10000', 'count < 3') }
    fixtures(transform) do |home, temp, cache, definitions|
      tree = File.join(cache, 'many-items')
      FileUtils.mkdir_p(tree)
      5.times { |index| File.write(File.join(tree, index.to_s), 'keep') }
      out, err, status = run_code(home, temp, definitions, 'jobs_clean_user_caches')
      assert status.success?, out + err
      assert_equal 5, Dir.children(tree).size
      assert_includes out + err, '预算'
    end
    fixtures do |home, temp, cache, definitions|
      tree = File.join(cache, 'deep')
      FileUtils.mkdir_p(File.join(tree, *(['d'] * 65)))
      out, err, status = run_code(home, temp, definitions, 'jobs_clean_user_caches')
      assert status.success?, out + err
      assert File.directory?(tree)
      assert_includes out + err, '64层'
    end
  end

  def test_stream_idle_timeout_preserves_candidate_and_finishes
    transform = ->(source) { source.sub('/usr/bin/find -P -x "$target" -print0', 'jobs_test_slow_find "$target"') }
    fixtures(transform) do |home, temp, cache, definitions|
      File.write(File.join(cache, 'keep'), 'keep')
      out, err, status = run_code(home, temp, definitions, <<~'ZSH')
        jobs_test_slow_find() { zmodload zsh/zselect; zselect -t 200; }
        jobs_clean_user_caches
      ZSH
      assert status.success?, out + err
      assert File.exist?(File.join(cache, 'keep'))
      assert_includes out + err, '完整返回'
    end
  end

  def test_protected_candidates_leave_retry_queue_and_new_members_are_not_adopted
    transform = ->(source) { source.sub('jobs_clean_cache_remove_snapshot "$item" "$work/snapshot"', 'jobs_test_remove_cache "$item"') }
    fixtures(transform) do |home, temp, cache, definitions|
      tree = File.join(cache, 'retry-tree')
      FileUtils.mkdir_p(tree)
      File.write(File.join(tree, 'original'), 'keep')
      out, err, status = run_code(home, temp, definitions, <<~'ZSH')
        run_sequence() {
          local -i JOBS_CLEAN_CACHE_PLAN_READY=0
          local JOBS_CLEAN_CACHE_ROOT_ID=""
          local -A JOBS_CLEAN_CACHE_PENDING=() JOBS_CLEAN_CACHE_ORIGINAL=()
          jobs_test_remove_cache() { print attempt >> "$TMPDIR/attempts"; return 1; }
          jobs_clean_user_caches && return 91
          print new > "$HOME/Library/Caches/retry-tree/new"
          jobs_clean_user_caches || return $?
          [[ ${#JOBS_CLEAN_CACHE_PENDING} == 0 ]] || return 92
          jobs_clean_user_caches
        }
        run_sequence
      ZSH
      assert status.success?, out + err
      assert_equal 1, File.readlines(File.join(temp, 'attempts')).size
      assert File.exist?(File.join(tree, 'new'))
      assert_includes out + err, '未授权'
    end
  end

  def test_new_file_created_after_last_scan_is_never_recursively_removed
    fixtures do |home, temp, cache, definitions|
      tree = File.join(cache, 'live-cache')
      FileUtils.mkdir_p(tree)
      File.write(File.join(tree, 'old'), 'old')
      out, err, status = run_code(home, temp, definitions, <<~'ZSH')
        functions -c jobs_clean_cache_remove_snapshot original_remove_snapshot
        jobs_clean_cache_remove_snapshot() {
          print new > "$1/new"
          original_remove_snapshot "$@"
        }
        jobs_clean_user_caches
      ZSH
      assert_equal 1, status.exitstatus, out + err
      assert_equal "new\n", File.read(File.join(tree, 'new'))
      refute File.exist?(File.join(tree, 'old'))
    end
  end

  def test_same_inode_same_size_edit_after_confirmation_is_preserved
    fixtures do |home, temp, cache, definitions|
      item = File.join(cache, 'active-file')
      File.write(item, 'old')
      inode = File.stat(item).ino
      out, err, status = run_code(home, temp, definitions, <<~'ZSH')
        jobs_clean_cache_confirm_selected() { print -n new > "$HOME/Library/Caches/active-file"; return 0; }
        jobs_clean_user_caches
      ZSH
      assert status.success?, out + err
      assert_equal inode, File.stat(item).ino
      assert_equal 'new', File.read(item)
      assert_includes out + err, '候选已变化'
    end
  end

  def test_only_immutable_or_append_flags_are_blocked
    { 64 => 0, 2 => 2, 262144 => 2 }.each do |flag, expected|
      transform = ->(source) { source.sub('%u|%f|%HT', "%u|#{flag}|%HT") }
      fixtures(transform) do |home, temp, cache, definitions|
        File.write(File.join(cache, 'flagged'), 'keep')
        out, err, status = run_code(home, temp, definitions, 'jobs_clean_cache_snapshot "$HOME/Library/Caches/flagged" "$(/usr/bin/stat -f %d "$HOME/Library/Caches")" "$TMPDIR/snapshot"')
        assert_equal expected, status.exitstatus, out + err
        assert File.exist?(File.join(cache, 'flagged'))
      end
    end
  end

  def test_selector_and_confirmation_tool_failure_cannot_become_success_on_retry
    %w[jobs_clean_cache_select_candidates jobs_clean_cache_confirm_selected].each do |method|
      fixtures do |home, temp, cache, definitions|
        File.write(File.join(cache, 'keep'), 'keep')
        out, err, status = run_code(home, temp, definitions, <<~ZSH)
          #{method}() { return 1; }
          run_sequence() {
            local -i JOBS_CLEAN_CACHE_PLAN_READY=0
            local JOBS_CLEAN_CACHE_ROOT_ID=""
            local -A JOBS_CLEAN_CACHE_PENDING=() JOBS_CLEAN_CACHE_ORIGINAL=()
            jobs_clean_user_caches && return 91
            jobs_clean_user_caches && return 92
            return 0
          }
          run_sequence
        ZSH
        assert status.success?, out + err
        assert_equal 'keep', File.read(File.join(cache, 'keep'))
      end
    end
  end

  def test_cancelled_member_removal_stops_later_members_and_keeps_exit_code
    transform = ->(source) { source.sub('/bin/rm -f -- "$entry"', 'jobs_test_cancel_remove "$entry"') }
    fixtures(transform) do |home, temp, cache, definitions|
      tree = File.join(cache, 'cancel-tree')
      FileUtils.mkdir_p(tree)
      File.write(File.join(tree, 'a'), 'keep a')
      File.write(File.join(tree, 'b'), 'keep b')
      out, err, status = run_code(home, temp, definitions, <<~'ZSH')
        jobs_test_cancel_remove() { print attempt >> "$TMPDIR/attempts"; return 130; }
        jobs_clean_user_caches
      ZSH
      assert_equal 130, status.exitstatus, out + err
      assert_equal 1, File.readlines(File.join(temp, 'attempts')).size
      assert_equal 'keep a', File.read(File.join(tree, 'a'))
      assert_equal 'keep b', File.read(File.join(tree, 'b'))
    end
  end

  def run_picker(home, temp, definitions, keys)
    transcript = +''
    result = nil
    fixture_code = <<~'ZSH'
      source "$1"
      stty rows 25 columns 110
      printf 'ALL\t全选用户缓存\nSKIP\t跳过（默认）\n1\t数据候选\n2\t其它候选\n' > "$TMPDIR/rows"
      jobs_clean_cache_select_candidates "$TMPDIR/rows" > "$TMPDIR/result"
    ZSH
    PTY.spawn({ 'HOME' => home, 'TMPDIR' => temp, 'TERM' => 'xterm-256color', 'NO_COLOR' => '1' }, '/bin/zsh', '-c', fixture_code, '--', definitions) do |reader, writer, pid|
      steps = keys.is_a?(Array) ? keys.dup : [['4/4 (0)', keys]]
      offset = 0
      begin
        Timeout.timeout(8) do
          loop do
            transcript << reader.readpartial(4096)
            if !steps.empty? && transcript.b.include?('数据候选'.b) && transcript.byteslice(offset..-1).include?(steps[0][0])
              writer.write(steps.shift[1])
              writer.flush
              offset = transcript.bytesize
            end
          end
        end
      rescue EOFError, Errno::EIO
        # 进程正常结束后PTY关闭。
      rescue Timeout::Error
        Process.kill('TERM', pid) rescue nil
        File.binwrite('/tmp/jobs-cache-picker-transcript.log', transcript)
        flunk 'fzf交互超时；隔离输出已保留'
      ensure
        _, result = Process.wait2(pid) rescue nil
      end
    end
    [transcript.force_encoding(Encoding::UTF_8).scrub, result, File.read(File.join(temp, 'result'))]
  end

  def test_real_fzf_space_uses_current_row_only_without_an_existing_selection
    skip 'fzf unavailable' unless system('/bin/zsh', '-c', 'command -v fzf >/dev/null')
    {
      ' ' => [0, ''], # 默认跳过操作行保持跳过。
      "\e[A " => [0, "1\n2\n"],
      "\e[B " => [0, "1\n"],
      "\e[B\r\r " => [0, "1\n"], # 取消最后一个勾选后提交当前行。
      "\e[B\r\e[B " => [0, "1\n"], # 已选时不增选当前光标。
      "\e[B\r\e[B\r " => [0, "1\n2\n"],
      "\e[A\r " => [0, "1\n2\n"],
      "\e[A\r\e[B\r " => [0, ''],
      "\e[A\r数据 " => [0, "1\n2\n"],
      "\e[A\r\e" => [130, ''],
      "\e" => [130, ''],
      [['4/4 (0)', "\e[B\rzzzz"], ['0/4 (1)', ' ']] => [0, "1\n"],
      [['4/4 (0)', 'zzzz'], ['0/4 (0)', " \x15"], ['4/4 (0)', "\e[B\e[B "]] => [0, "1\n"]
    }.each do |keys, expected|
      fixtures do |home, temp, _cache, definitions|
        transcript, status, selected = run_picker(home, temp, definitions, keys)
        assert_equal expected[0], status.exitstatus, transcript
        assert_equal expected[1], selected, transcript
      end
    end
  end
end
