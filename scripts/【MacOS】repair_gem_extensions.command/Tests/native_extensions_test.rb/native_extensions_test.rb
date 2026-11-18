#!/usr/bin/ruby
# 脚本自述：
# - 核心用途：隔离验证 Gem 原生扩展发现、重编译、备份与失败恢复。
# - 影响范围：仅写入专属临时 Gem 目录；构建器使用替身，不联网、不安装真实 Gem。
# - 运行提示：使用 /usr/bin/ruby 执行；可用 JOBS_GEM_REPAIR_SCRIPT 指定待验证脚本。

# JOBS_TERMINAL_STYLE_GUARD_V1_BEGIN
if $PROGRAM_NAME == __FILE__
  # 直接运行时由 fork 父进程保护配色；子进程继续原文件，不重放 Ruby 参数和预载模块。
  def jobs_terminal_style_bootstrap_v1
    return unless $PROGRAM_NAME == __FILE__
    plain = lambda do
      ENV.update('PLAIN_OUTPUT' => '1', 'NO_COLOR' => '1', 'FORCE_COLOR' => '0',
                 'CLICOLOR' => '0', 'ANSI_COLORS_DISABLED' => '1', 'npm_config_color' => 'false')
    end
    notify = lambda do |message|
      encoding = $stderr.external_encoding || Encoding::UTF_8
      $stderr.write((message + "\n").encode(encoding, invalid: :replace, undef: :replace))
    end
    return unless $stdin.tty? && $stdout.tty?
    return if ENV.key?('NO_COLOR') || ENV['PLAIN_OUTPUT'] == '1' ||
              ENV['IS_SOURCETREE_RUNTIME'] == '1' ||
              ENV.keys.any? { |key| key.match?(/\A(?:SOURCETREE|SOURCE_TREE)/i) }
    return if ['', 'dumb'].include?(ENV.fetch('TERM', ''))
    if File::ALT_SEPARATOR == '\\' || !Process.respond_to?(:fork) ||
       Thread.list.length > 1 || ENV['TMUX'] || ENV['STY']
      plain.call
      return
    end
    tty_name = IO.popen(['tty'], err: File::NULL, &:read).strip
    groups = IO.popen(['ps', '-o', 'pgid=', '-o', 'tpgid=', '-p', Process.pid.to_s], err: File::NULL, &:read).split
    unless tty_name.match?(%r{\A/dev/[A-Za-z0-9_./-]+\z}) && groups.length == 2 &&
           groups.all? { |group| group.match?(/\A\d+\z/) } && groups[0].to_i > 0 && groups[0] == groups[1]
      plain.call
      return
    end
    owner = ENV['JOBS_TERMINAL_STYLE_OWNER']
    if ENV['JOBS_TERMINAL_STYLE_TTY'] == tty_name && owner && owner.match?(/\A\d+\z/)
      begin
        Process.kill(0, owner.to_i)
        return
      rescue Errno::ESRCH, Errno::EPERM
      end
    end
    require 'io/console'
    require 'tmpdir'
    if Thread.list.length > 1
      plain.call
      return
    end
    tty = File.open('/dev/tty', 'r+')
    tty.binmode
    tty.sync = true
    keys = ['10', '11', '12'] + (0..15).map { |index| "4;#{index}" }
    palette = %w[000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee
                 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff]
    targets = { '10' => 'ffffff', '11' => '000000', '12' => 'ffffff' }
    palette.each_with_index { |color, index| targets["4;#{index}"] = color }
    query = lambda do |key|
      tty.write("\e]#{key};?\a")
      bytes = ''.b
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.3
      loop do
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return nil if remaining <= 0 || !IO.select([tty], nil, nil, remaining)
        piece = tty.read_nonblock(256, exception: false)
        next if piece == :wait_readable
        return nil unless piece && !piece.empty?
        bytes << piece
        return nil if bytes.bytesize > 256 || !bytes.start_with?("\e".b)
        break if bytes.end_with?("\a".b) || bytes.end_with?("\e\\".b)
      end
      match = bytes.match(/\A\e\]#{Regexp.escape(key)};rgb:([0-9a-fA-F]{1,4})\/([0-9a-fA-F]{1,4})\/([0-9a-fA-F]{1,4})(?:\a|\e\\)\z/n)
      return nil unless match
      components = match.captures.map { |hex| (hex.to_i(16) * 65535.0 / (16**hex.length - 1)).round }
      { raw: bytes, rgb: components }
    rescue IOError, SystemCallError
      nil
    end
    snapshot = lambda do
      values = {}
      tty.raw(min: 0, time: 0, intr: true) do
        keys.each do |key|
          value = query.call(key)
          return nil unless value
          values[key] = value
        end
      end
      values
    rescue IOError, SystemCallError, ArgumentError
      nil
    end
    original = snapshot.call
    unless original
      notify.call('终端不支持完整配色保存，或启动时收到其它输入；保留原配色并使用纯文本。')
      tty.close
      plain.call
      return
    end
    directory = Dir.mktmpdir('jobs-terminal-style-')
    recovery = File.join(directory, 'restore.sh')
    original_bytes = keys.map { |key| original.fetch(key).fetch(:raw) }.join
    recovery_source = "#!/bin/sh\n" \
      "[ -t 0 ] && [ \"$(tty)\" = '#{tty_name}' ] || { printf '请在原终端运行恢复入口。\\n' >&2; exit 1; }\n" \
      "printf '本操作会覆盖此终端当前配色。确认恢复脚本启动前的配色，请输入 YES：' >&2\n" \
      "IFS= read -r jobs_restore_choice\n[ \"$jobs_restore_choice\" = YES ] || exit 1\n" \
      "printf '%s\\033[0m' '#{original_bytes}' > /dev/tty\n"
    File.open(recovery, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.binmode
      file.write(recovery_source.b)
    end
    notify.call("本次终端临时使用黑底白字；强退后恢复入口：sh \"#{recovery}\"")
    changed = false
    applied = nil
    # 比较仍生效的本轮颜色，只恢复未被用户另行修改的项。
    cleanup = lambda do
      current = applied && snapshot.call
      unless current
        notify.call("终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh \"#{recovery}\"")
        return false
      end
      conflicts = []
      restore_bytes = ''.b
      keys.each do |key|
        if current.fetch(key).fetch(:rgb) == applied.fetch(key).fetch(:rgb)
          restore_bytes << original.fetch(key).fetch(:raw)
        else
          conflicts << key
        end
      end
      tty.write(restore_bytes + "\e[0m".b)
      if conflicts.empty?
        File.unlink(recovery)
        Dir.rmdir(directory)
        true
      else
        notify.call("检测到运行期间的配色变更，已保留这些项：#{conflicts.join(' ')}")
        notify.call("确认要覆盖后续改色时才使用恢复入口：sh \"#{recovery}\"")
        false
      end
    rescue IOError, SystemCallError
      notify.call("终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh \"#{recovery}\"")
      false
    end
    child_pid = nil
    guardian = false
    interrupted = nil
    previous_signals = {}
    %w[INT TERM HUP].each do |name|
      previous_signals[name] = Signal.trap(name) do
        interrupted = name
        if child_pid && name != 'INT'
          begin
            Process.kill(name, child_pid)
          rescue Errno::ESRCH
          end
        end
      end
    end
    begin
      changed = true
      tty.write(targets.map { |key, color| "\e]#{key};##{color}\a" }.join + "\e[0m")
      applied = snapshot.call
      unless applied
        notify.call('无法核实本次临时配色，已停止启动业务。')
        raise SystemExit, 1
      end
      desired = targets.all? do |key, hex|
        rgb = hex.scan(/../).map { |component| component.to_i(16) * 257 }
        applied.fetch(key).fetch(:rgb).zip(rgb).all? { |actual, expected| (actual - expected).abs <= 255 }
      end
      unless desired
        notify.call('终端未接受本次配色，恢复后使用纯文本。')
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      if interrupted
        raise SystemExit, 128 + Signal.list.fetch(interrupted)
      end
      if Thread.list.length > 1
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      $stdout.flush
      $stderr.flush
      begin
        child_pid = Process.fork
      rescue NotImplementedError, SystemCallError
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      unless child_pid
        changed = false
        ENV['JOBS_TERMINAL_STYLE_TTY'] = tty_name
        ENV['JOBS_TERMINAL_STYLE_OWNER'] = Process.ppid.to_s
        raise SystemExit, 128 + Signal.list.fetch(interrupted) if interrupted
        return
      end
      guardian = true
      result = nil
      loop do
        begin
          _, result = Process.wait2(child_pid)
          break
        rescue Interrupt, Errno::EINTR
        end
      end
      status_code = result.exitstatus || 128 + result.termsig
      %w[INT TERM HUP].each { |name| Signal.trap(name, 'IGNORE') }
      restored = cleanup.call
      changed = false
      status_code = 1 if !restored && status_code.zero?
      tty.close
      Process.exit!(status_code)
    ensure
      if changed
        %w[INT TERM HUP].each { |name| Signal.trap(name, 'IGNORE') }
        cleanup.call
      end
      previous_signals.each { |name, handler| Signal.trap(name, handler) } unless guardian
      tty.close unless tty.closed?
    end
  rescue IOError, SystemCallError, LoadError => error
    if guardian
      notify.call("终端保护监督进程异常：#{error.message}")
      Process.exit!(1)
    end
    raise SystemExit, 1 if changed
    notify.call("终端保护不可用，使用纯文本：#{error.message}")
    plain.call
  end
  jobs_terminal_style_bootstrap_v1

end
# JOBS_TERMINAL_STYLE_GUARD_V1_END

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'digest'
require 'rbconfig'
require 'rubygems'
require 'rubygems/ext'

repair_script = ENV['JOBS_GEM_REPAIR_SCRIPT'] || File.expand_path('../../【MacOS】repair_gem_extensions.command', __dir__)
repair_source = File.read(repair_script)
repair_body = repair_source[/^# >>> Jobs Gem extension Ruby >>>\n(.*?)^# <<< Jobs Gem extension Ruby <<</m, 1]
raise '待验证脚本缺少 Gem 原生扩展 Ruby 标记。' unless repair_body

eval(repair_body, TOPLEVEL_BINDING, repair_script, repair_source.lines.index { |line| line.start_with?('# >>> Jobs Gem extension Ruby >>>') } + 2)

class NativeExtensionsTest < Minitest::Test
  # 每项测试只使用独立临时 Gem home，避免宿主扩展进入修复范围。
  def setup
    @root = Dir.mktmpdir('jobs-native-中文 空格-')
    @gem_home = File.join(@root, '测试 Gem home')
    @backup_root = File.join(@root, '修复备份')
    @saved_gem_home = Gem.dir
    @saved_gem_paths = Gem.path.dup
    FileUtils.mkdir_p(@gem_home)
    Gem.use_paths(@gem_home, [@gem_home])
    Gem::Specification.reset
    @builder_calls = []
  end

  # 恢复 RubyGems 发现路径并清理本测试创建的临时文件。
  def teardown
    Gem.use_paths(@saved_gem_home, @saved_gem_paths)
    Gem::Specification.reset
    FileUtils.chmod_R('u+rwX', @root) if @root && File.directory?(@root)
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  # 构造 RubyGems 可真实发现的已安装扩展 Gem，保留旧平台目录作为回归哨兵。
  def make_spec(name = 'jobs_native_fixture', version = '1.2.3', extensions: ['ext/fixture/extconf.rb'], healthy: false, default: false, current: false)
    specification = Gem::Specification.new do |spec|
      spec.name = name
      spec.version = version
      spec.summary = 'Jobs isolated native extension fixture'
      spec.authors = ['Jobs']
      spec.files = ['lib/fixture.rb'] + extensions
      spec.require_paths = ['lib']
      spec.extensions = extensions
      spec.installed_by_version = Gem::VERSION
    end
    specification_directory = File.join(@gem_home, 'specifications', default ? 'default' : '')
    FileUtils.mkdir_p(specification_directory)
    specification_path = File.join(specification_directory, "#{specification.full_name}.gemspec")
    File.write(specification_path, specification.to_ruby)
    spec = Gem::Specification.load(specification_path)
    FileUtils.mkdir_p(File.join(spec.full_gem_path, 'lib'))
    File.write(File.join(spec.full_gem_path, 'lib', 'fixture.rb'), "ORIGINAL = :source\n")
    extensions.each do |extension|
      extension_path = File.join(spec.full_gem_path, extension)
      FileUtils.mkdir_p(File.dirname(extension_path))
      File.write(extension_path, "# original extconf\n")
    end
    old_directory = old_extension_dir(spec)
    FileUtils.mkdir_p(old_directory)
    File.write(File.join(old_directory, 'previous.bundle'), 'previous-platform-native-binary')
    File.write(File.join(old_directory, 'gem.build_complete'), '')
    if current || healthy
      FileUtils.mkdir_p(spec.extension_dir)
      File.write(File.join(spec.extension_dir, 'previous-current.bundle'), 'current-platform-original')
    end
    File.write(spec.gem_build_complete_path, '') if healthy
    Gem::Specification.reset
    spec
  end

  # 定位夹具旧平台的目录；生产代码不能以改名代替重新构建。
  def old_extension_dir(spec)
    File.join(@gem_home, 'extensions', 'jobs-previous-platform', Gem.extension_api_version, spec.full_name)
  end

  # 比较内容、链接与权限，确保失败恢复没有遗失原有文件。
  def tree_snapshot(path)
    return nil unless File.exist?(path) || File.symlink?(path)

    paths = [path] + Dir[File.join(path, '**', '*'), File.join(path, '**', '.*')].reject do |entry|
      ['.', '..'].include?(File.basename(entry))
    end
    paths.uniq.sort.map do |entry|
      stat = File.lstat(entry)
      payload = if stat.symlink?
                  ['link', File.readlink(entry)]
                elsif stat.file?
                  ['file', Digest::SHA256.file(entry).hexdigest]
                else
                  ['directory']
                end
      [entry.sub(/\A#{Regexp.escape(path)}/, ''), stat.mode & 0o777, payload]
    end
  end

  # 使用同一 Ruby 自带的扩展验证真实载入，不引入联网或额外编译依赖。
  def native_fixture
    extension = RbConfig::CONFIG.fetch('DLEXT')
    candidates = Dir[File.join(RbConfig::CONFIG.fetch('archdir'), "*.#{extension}")]
    candidate = candidates.find { |path| File.basename(path).start_with?('pty.') } || candidates.first
    raise '当前测试 Ruby 没有可用于加载验证的原生扩展。' unless candidate

    candidate
  end

  # 模拟构建产物；真实子进程载入在单独用例中验证。
  def complete_build(spec)
    FileUtils.mkdir_p(spec.extension_dir)
    FileUtils.cp(native_fixture, File.join(spec.extension_dir, "fixture.#{RbConfig::CONFIG.fetch('DLEXT')}"))
    File.write(spec.gem_build_complete_path, '')
    File.write(File.join(spec.full_gem_path, 'lib', 'rebuilt.txt'), 'rebuilt')
  end

  # 只替换编译动作；可按用例保留真实载入检查或明确模拟载入成功。
  def with_builder(behavior, verify: :real)
    calls = @builder_calls
    build = lambda do |spec|
      calls << [spec.full_name]
      behavior.call(spec)
    end
    JobsGemExtensionRepair.stub(:preflight!, nil) do
      JobsGemExtensionRepair.stub(:build_spec, build) do
        if verify == :real
          yield
        else
          JobsGemExtensionRepair.stub(:verify_spec, verify) { yield }
        end
      end
    end
  end

  # 独立修复接口由调用方创建备份根目录，和 Shell 实际调用顺序保持一致。
  def repair_spec(spec)
    FileUtils.mkdir_p(@backup_root)
    JobsGemExtensionRepair.repair_spec(spec, @backup_root)
  end

  # 保存修复前的完整哨兵，方便同一用例核验当前、旧平台及 gemspec。
  def original_state(spec)
    {
      source: tree_snapshot(spec.full_gem_path),
      current: tree_snapshot(spec.extension_dir),
      previous: tree_snapshot(old_extension_dir(spec)),
      gemspec: File.binread(spec.loaded_from)
    }
  end

  # 验证恢复限于本次写入范围，旧平台与版本声明始终保留。
  def assert_original_state(spec, state)
    assert_equal state[:source], tree_snapshot(spec.full_gem_path)
    if state[:current].nil?
      assert_nil tree_snapshot(spec.extension_dir)
    else
      assert_equal state[:current], tree_snapshot(spec.extension_dir)
    end
    assert_equal state[:previous], tree_snapshot(old_extension_dir(spec))
    assert_equal state[:gemspec], File.binread(spec.loaded_from)
  end

  def test_discovery_returns_only_missing_non_default_native_gems
    missing = make_spec('jobs_missing')
    make_spec('jobs_healthy', healthy: true)
    make_spec('jobs_pure_ruby', extensions: [])
    make_spec('jobs_default', default: true)

    assert_equal [missing.full_name], JobsGemExtensionRepair.missing_specs.map(&:full_name)
  end

  def test_health_check_does_not_build_or_create_backups
    make_spec('jobs_healthy', healthy: true)
    output, error = capture_io do
      with_builder(lambda { flunk '健康 Gem 不应构建。' }) do
        assert_equal 0, JobsGemExtensionRepair.run(mode: 'check', backup_root: @backup_root)
      end
    end

    assert_empty @builder_calls
    refute File.exist?(@backup_root)
    refute_match(/Ignoring/, output + error)
  end

  def test_check_reports_missing_extensions_without_mutation
    spec = make_spec
    state = original_state(spec)
    capture_io do
      assert_equal 0, JobsGemExtensionRepair.run(mode: 'check', backup_root: @backup_root)
    end

    assert_original_state(spec, state)
    refute File.exist?(@backup_root)
  end

  def test_successful_repair_builds_current_platform_and_preserves_version_and_previous_platform
    spec = make_spec(current: true)
    state = original_state(spec)
    capture_io do
      with_builder(lambda { |target| complete_build(target) }, verify: true) do
        assert repair_spec(spec)
      end
    end

    assert_equal [spec.full_name], @builder_calls.map(&:first)
    assert File.file?(spec.gem_build_complete_path)
    refute spec.missing_extensions?
    assert_equal state[:previous], tree_snapshot(old_extension_dir(spec))
    assert_equal state[:gemspec], File.binread(spec.loaded_from)
    assert_equal Gem::Version.new('1.2.3'), spec.version
    assert File.directory?(@backup_root)
    refute_empty Dir[File.join(@backup_root, '**', '*')]
  end

  def test_builder_failure_restores_existing_source_and_current_extensions
    spec = make_spec(current: true)
    state = original_state(spec)
    capture_io do
      with_builder(lambda do |target|
        File.write(File.join(target.full_gem_path, 'lib', 'fixture.rb'), 'damaged')
        FileUtils.rm_r(target.extension_dir)
        FileUtils.mkdir_p(target.extension_dir)
        File.write(target.gem_build_complete_path, '')
        raise Gem::Ext::BuildError, 'isolated compiler failure'
      end) do
        refute repair_spec(spec)
      end
    end

    assert_original_state(spec, state)
    assert_equal 1, @builder_calls.length
    assert File.directory?(@backup_root)
  end

  def test_failed_build_removes_new_current_platform_directory_when_it_did_not_exist
    spec = make_spec
    state = original_state(spec)
    capture_io do
      with_builder(lambda do |target|
        FileUtils.mkdir_p(target.extension_dir)
        File.write(File.join(target.extension_dir, 'partial.bundle'), 'partial')
        File.write(File.join(target.full_gem_path, 'lib', 'partial.rb'), 'partial')
        raise Gem::Ext::BuildError, 'isolated incomplete build'
      end) do
        refute repair_spec(spec)
      end
    end

    assert_original_state(spec, state)
    refute File.exist?(spec.extension_dir)
  end

  def test_marker_without_native_artifact_is_not_a_success
    spec = make_spec
    state = original_state(spec)
    capture_io do
      with_builder(lambda do |target|
        FileUtils.mkdir_p(target.extension_dir)
        File.write(target.gem_build_complete_path, '')
      end) do
        refute repair_spec(spec)
      end
    end

    assert_original_state(spec, state)
  end

  def test_invalid_native_artifact_rolls_back_even_when_builder_reports_success
    spec = make_spec
    state = original_state(spec)
    capture_io do
      with_builder(lambda do |target|
        FileUtils.mkdir_p(target.extension_dir)
        File.write(target.gem_build_complete_path, '')
        File.write(File.join(target.extension_dir, "fixture.#{RbConfig::CONFIG.fetch('DLEXT')}"), 'not a native library')
      end) do
        refute repair_spec(spec)
      end
    end

    assert_original_state(spec, state)
  end

  def test_unavailable_backup_root_stops_before_builder_runs
    spec = make_spec
    state = original_state(spec)
    File.write(@backup_root, 'a file cannot hold a backup directory')
    capture_io do
      with_builder(lambda { flunk '备份失败时不得开始构建。' }) do
        refute JobsGemExtensionRepair.repair_spec(spec, @backup_root)
      end
    end

    assert_empty @builder_calls
    assert_original_state(spec, state)
  end

  def test_repair_is_idempotent_when_current_platform_is_healthy
    spec = make_spec
    capture_io do
      with_builder(lambda { |target| complete_build(target) }, verify: true) do
        assert_equal 0, JobsGemExtensionRepair.run(mode: 'repair', backup_root: @backup_root, runtime_label: '隔离 Ruby')
      end
    end
    state = original_state(spec)
    backups = tree_snapshot(@backup_root)
    capture_io do
      with_builder(lambda { flunk '二次运行不得重建已经健康的扩展。' }) do
        assert_equal 0, JobsGemExtensionRepair.run(mode: 'repair', backup_root: @backup_root)
      end
    end

    assert_equal 1, @builder_calls.length
    assert_original_state(spec, state)
    assert_equal backups, tree_snapshot(@backup_root)
  end

  def test_run_propagates_failed_repair_exit_status
    make_spec
    capture_io do
      with_builder(lambda { raise Gem::Ext::BuildError, 'isolated build failure' }) do
        assert_equal 1, JobsGemExtensionRepair.run(mode: 'repair', backup_root: @backup_root)
      end
    end

    assert_equal 1, @builder_calls.length
  end

  def test_read_only_source_stops_before_backup_or_build
    spec = make_spec
    state = original_state(spec)
    writable = File.method(:writable?)
    read_only_source = lambda { |path| path == spec.full_gem_path ? false : writable.call(path) }
    capture_io do
      File.stub(:writable?, read_only_source) do
        with_builder(lambda { flunk '不可写目标不得构建。' }) do
          refute repair_spec(spec)
        end
      end
    end

    assert_empty @builder_calls
    assert_original_state(spec, state)
    assert_empty Dir[File.join(@backup_root, '*')]
  end

  def test_backup_copy_failure_stops_before_build_and_keeps_original_files
    spec = make_spec(current: true)
    state = original_state(spec)
    capture_io do
      FileUtils.stub(:cp_r, lambda { |*arguments| raise IOError, 'isolated backup copy failure' }) do
        with_builder(lambda { flunk '备份未完整保存时不得构建。' }) do
          refute repair_spec(spec)
        end
      end
    end

    assert_empty @builder_calls
    assert_original_state(spec, state)
  end

  def test_modified_gemspec_is_restored_and_reported_as_failed
    spec = make_spec
    state = original_state(spec)
    capture_io do
      with_builder(lambda do |target|
        complete_build(target)
        File.write(target.loaded_from, 'unexpected gemspec mutation')
      end, verify: true) do
        refute repair_spec(spec)
      end
    end

    assert_original_state(spec, state)
    assert_match(/failed/, File.read(Dir[File.join(@backup_root, '*', 'result.txt')].fetch(0)))
  end

  def test_deleted_gemspec_is_restored_after_failed_build
    spec = make_spec
    state = original_state(spec)
    capture_io do
      with_builder(lambda do |target|
        File.delete(target.loaded_from)
        raise Gem::Ext::BuildError, 'isolated build deleted gemspec'
      end) do
        refute repair_spec(spec)
      end
    end

    assert_original_state(spec, state)
  end

  def test_fresh_process_requires_exact_version_and_loads_native_extension
    spec = make_spec('pty')
    FileUtils.mkdir_p(spec.extension_dir)
    native_path = File.join(spec.extension_dir, "pty.#{RbConfig::CONFIG.fetch('DLEXT')}")
    FileUtils.cp(native_fixture, native_path)
    File.write(File.join(spec.full_gem_path, 'lib', 'pty.rb'), "require #{native_path.inspect}\n")
    File.write(spec.gem_build_complete_path, '')

    assert JobsGemExtensionRepair.verify_spec(spec)
  end

  def test_fresh_process_rejects_pure_ruby_fallback
    spec = make_spec
    FileUtils.mkdir_p(spec.extension_dir)
    FileUtils.cp(native_fixture, File.join(spec.extension_dir, "fixture_native.#{RbConfig::CONFIG.fetch('DLEXT')}"))
    File.write(File.join(spec.full_gem_path, 'lib', "#{spec.name}.rb"), "FIXTURE = :pure_ruby\n")
    File.write(spec.gem_build_complete_path, '')

    error = assert_raises(RuntimeError) { JobsGemExtensionRepair.verify_spec(spec) }
    assert_match(/原生扩展/, error.message)
  end

  def test_unknown_mode_fails_without_mutation_even_for_healthy_environment
    make_spec('jobs_healthy', healthy: true)
    capture_io do
      assert_equal 1, JobsGemExtensionRepair.run(mode: 'unexpected', backup_root: @backup_root)
    end

    refute File.exist?(@backup_root)
  end
end
