# frozen_string_literal: true

# 隔离验证内嵌选路与后续 Specs 命令的环境交接，不联网或升级工具。
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
require 'open3'
require 'json'

class JobsUpdateCocoaPodsProxyTest < Minitest::Test
  SCRIPT = File.expand_path('../update.command', __dir__)
  SELECTED_PROXY = 'http://fixture-user:fixture-password@127.0.0.1:18888'
  ORIGINAL_PROXY = 'http://original.invalid:18080'
  ENV_KEYS = %w[https_proxy HTTPS_PROXY http_proxy HTTP_PROXY all_proxy ALL_PROXY NO_PROXY GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0]

  RUBY_RUNNER = <<~'RUBY'
    #!/usr/bin/ruby
    require 'json'
    ARGV.shift if ARGV.first == '-'
    payload = ARGV.fetch(0)
    File.write(File.join(ENV.fetch('JOBS_PROXY_TEST_ROOT'), 'payload-mode'), (File.stat(payload).mode & 0o777).to_s(8))
    custom_payload = ENV['JOBS_PROXY_TEST_PAYLOAD']
    if custom_payload
      File.binwrite(payload, JSON.parse(custom_payload).join("\0"))
      puts 'proxy'
      exit 0
    end
    source = STDIN.read
    injection = <<~'INJECTION'
      module JobsCocoaPodsNetwork
        # 仅替换系统配置读取，真实解析、候选构造和 Git 探测保持不变。
        def self.system_proxy_routes(timeout)
          parse_system_proxies(ENV.fetch('JOBS_PROXY_TEST_SYSTEM_CONFIG', '')).map do |kind, proxy|
            proxy_route(kind, proxy)
          end.compact
        end
      end
      module JobsUpdatePodNetwork
        # 保留真实有界进程执行，只将固定 Git 路径换成本测试假命令。
        def self.git_executable
          File.join(ENV.fetch('JOBS_PROXY_TEST_ROOT'), 'bin', 'git')
        end
      end
    INJECTION
    marker = '# >>> Jobs update Pod network handoff >>>'
    raise 'handoff marker missing' unless source.include?(marker)
    eval(source.sub(marker, injection + marker), TOPLEVEL_BINDING, 'embedded-network', 1)
  RUBY

  FAKE_TOOL = <<~'RUBY'
    #!/usr/bin/ruby
    require 'json'
    name = File.basename($PROGRAM_NAME)
    root = ENV.fetch('JOBS_PROXY_TEST_ROOT')
    stage = name
    request_url = ARGV.find { |argument| argument.start_with?('https://') }
    stage = 'route' if name == 'git' && ARGV.include?('https://github.com/andreamazz/AMPopTip.git')
    stage = 'route' if name == 'git' && ARGV.include?('--quiet')
    stage = 'route-http' if name == 'curl' && !ARGV.include?('--output')
    stage = 'api-probe' if name == 'curl' && request_url == 'https://api.github.com/repos/CocoaPods/Specs/commits/master'
    stage = 'configuration' if name == 'git' && ARGV.include?('--get-urlmatch')
    record = { 'stage' => stage, 'arguments' => ARGV, 'environment' => ENV.select { |key, _| key =~ /\A(?:https?_proxy|HTTPS?_PROXY|all_proxy|ALL_PROXY|NO_PROXY|GIT_CONFIG_|COCOAPODS_CDN_MAX_CONCURRENCY)/ } }
    File.open(File.join(root, 'events'), 'a') { |file| file.puts(JSON.generate(record)) }
    if name == 'git'
      if stage == 'configuration'
        exit 1 unless ENV.key?('JOBS_PROXY_TEST_GIT_PROXY')
        puts ENV['JOBS_PROXY_TEST_GIT_PROXY']
      elsif stage == 'route'
        allowed = ENV.fetch('JOBS_PROXY_TEST_ROUTE') == 'inherited' ||
          (ENV.fetch('JOBS_PROXY_TEST_ROUTE') == 'proxy' && ENV['https_proxy'] == ENV.fetch('JOBS_PROXY_TEST_EXPECTED_PROXY'))
        exit 128 unless allowed
        exit 128 if ENV['JOBS_PROXY_TEST_ROUTE_GIT'] == 'fail'
        if ENV['JOBS_PROXY_TEST_ROUTE_GIT'] == 'invalid'
          puts '<html>HEAD</html>'
          exit 0
        end
        puts "db495eea0747a3493ca8b3c737d037c0090973db\t#{ARGV.last}"
      else
        puts "0123456789012345678901234567890123456789\tHEAD"
      end
    elsif name == 'curl'
      if stage == 'api-probe'
        exit 28 if ENV['JOBS_PROXY_TEST_API_MODE'] == 'fail'
        body = ENV['JOBS_PROXY_TEST_API_MODE'] == 'sha64' ? '1234567890abcdef' * 4 : '0123456789012345678901234567890123456789'
        File.write(ARGV.fetch(ARGV.index('--output') + 1), body)
        print ENV.fetch('JOBS_PROXY_TEST_API_STATUS', '200')
        exit 0
      end
      if stage == 'route-http'
        allowed = ENV.fetch('JOBS_PROXY_TEST_ROUTE') == 'inherited' ||
          (ENV.fetch('JOBS_PROXY_TEST_ROUTE') == 'proxy' && ENV['https_proxy'] == ENV.fetch('JOBS_PROXY_TEST_EXPECTED_PROXY'))
        exit 7 unless allowed
        case ENV['JOBS_PROXY_TEST_ROUTE_HTTP']
        when 'fail' then exit 7
        when 'html' then print '<html>"name":"AFNetworking","version":"4.0.1"</html>'
        when 'wrong-version' then print '{"name":"AFNetworking","version":"9.0"}'
        else print '{"name":"AFNetworking","version":"4.0.1"}'
        end
        exit 0
      end
      exit 7 if ENV['JOBS_PROXY_TEST_SPECS_FAIL'] == '1'
      File.write(ARGV.fetch(ARGV.index('--output') + 1), '{"name":"AFNetworking","version":"4.0.1"}')
      print '0.10'
    elsif name == 'pod'
      if ARGV == %w[repo list --no-ansi]
        puts "public-alias\n- Type: CDN\n- URL: https://cdn.cocoapods.org/" unless ENV['JOBS_PROXY_TEST_ADD_CDN'] == '1'
      else
        exit Integer(ENV.fetch('JOBS_PROXY_TEST_POD_RESULT', '0'))
      end
    else
      exit 99
    end
  RUBY

  SHELL_RUNNER = <<~'ZSH'
    #!/bin/zsh
    setopt NO_NOMATCH
    export JOBS_MAC_ENV_SOURCE_MODE=1
    source "$JOBS_PROXY_TEST_SCRIPT" || exit 98
    LOG_FILE="$JOBS_PROXY_TEST_ROOT/update.log"
    jobs_gemext_find_ruby() {
      [[ "${JOBS_PROXY_TEST_NO_RUBY:-0}" == 1 ]] && return 1
      print -r -- "$JOBS_PROXY_TEST_ROOT/bin/ruby-runner"
    }
    jobs_update_run_cmd() { shift; "$@"; }
    warn_echo() { print -r -- "$*" >&2; }
    /usr/bin/ruby -rjson -e 'File.write(ARGV[0], JSON.generate(ENV.to_h))' "$JOBS_PROXY_TEST_ROOT/before.json"
    result=0
    jobs_update_cocoapods_repos || result=$?
    /usr/bin/ruby -rjson -e 'File.write(ARGV[0], JSON.generate(ENV.to_h))' "$JOBS_PROXY_TEST_ROOT/after.json"
    exit "$result"
  ZSH

  def test_explicit_proxy_reaches_specs_add_and_update_without_parent_changes
    result = run_fixture('JOBS_POD_PROXY_URL' => SELECTED_PROXY, 'JOBS_PROXY_TEST_ROUTE' => 'proxy', 'JOBS_PROXY_TEST_ADD_CDN' => '1')
    assert_equal 0, result[:status]
    assert_handoff(result, SELECTED_PROXY, '2')
    assert result[:events].any? { |event| event['stage'] == 'pod' && event['arguments'][1] == 'add-cdn' }
    assert_includes result[:stderr], '本次 Specs 探测与 repo 命令继承相同环境'
    assert_private_and_restored(result)
  end

  def test_enabled_system_proxy_is_exported_before_inherited_wrapper_can_hide_it
    config = "<dictionary> {\nHTTPSEnable : 1\nHTTPSProxy : 127.0.0.1\nHTTPSPort : 18888\n}\n"
    proxy = 'http://127.0.0.1:18888'
    result = run_fixture('https_proxy' => nil, 'JOBS_PROXY_TEST_ROUTE' => 'inherited', 'JOBS_PROXY_TEST_EXPECTED_PROXY' => proxy, 'JOBS_PROXY_TEST_SYSTEM_CONFIG' => config)
    assert_equal 0, result[:status]
    assert_handoff(result, proxy, '2')
    routes = result[:events].select { |event| event['stage'] == 'route-http' }
    assert_equal [proxy], routes.map { |event| event['environment']['https_proxy'] }
    assert_private_and_restored(result)
  end

  def test_explicit_proxy_environment_is_not_replaced_when_unusable
    config = "<dictionary> {\nHTTPSEnable : 1\nHTTPSProxy : 127.0.0.1\nHTTPSPort : 18888\n}\n"
    result = run_fixture('JOBS_PROXY_TEST_ROUTE' => 'proxy', 'JOBS_PROXY_TEST_EXPECTED_PROXY' => 'http://127.0.0.1:18888', 'JOBS_PROXY_TEST_SYSTEM_CONFIG' => config)
    assert_equal 0, result[:status]
    assert_handoff(result, ORIGINAL_PROXY, '1')
    assert_equal [ORIGINAL_PROXY], result[:events].select { |event| event['stage'].start_with?('route') }.map { |event| event['environment']['https_proxy'] }.uniq
    assert_private_and_restored(result)
  end

  def test_real_cdn_success_does_not_require_unrelated_git_access
    config = "<dictionary> {\nHTTPSEnable : 1\nHTTPSProxy : 127.0.0.1\nHTTPSPort : 18888\n}\n"
    proxy = 'http://127.0.0.1:18888'
    result = run_fixture('https_proxy' => nil, 'JOBS_PROXY_TEST_ROUTE' => 'proxy', 'JOBS_PROXY_TEST_EXPECTED_PROXY' => proxy,
                         'JOBS_PROXY_TEST_SYSTEM_CONFIG' => config, 'JOBS_PROXY_TEST_ROUTE_GIT' => 'fail')
    assert_equal 0, result[:status]
    assert_handoff(result, proxy, '2')
    assert result[:events].any? { |event| event['stage'] == 'route-http' && event['arguments'].last.start_with?('https://cdn.cocoapods.org/') }
    refute result[:events].any? { |event| event['arguments'].include?('https://github.com/andreamazz/AMPopTip.git') }
    assert_private_and_restored(result)
  end

  def test_api_probe_failure_keeps_valid_cdn_and_proxy_handoff
    config = "<dictionary> {\nHTTPSEnable : 1\nHTTPSProxy : 127.0.0.1\nHTTPSPort : 18888\n}\n"
    proxy = 'http://127.0.0.1:18888'
    result = run_fixture('https_proxy' => nil, 'JOBS_PROXY_TEST_ROUTE' => 'proxy', 'JOBS_PROXY_TEST_EXPECTED_PROXY' => proxy,
                         'JOBS_PROXY_TEST_SYSTEM_CONFIG' => config, 'JOBS_PROXY_TEST_API_MODE' => 'fail')
    assert_equal 0, result[:status]
    assert_handoff(result, proxy, '2')
    assert result[:events].any? { |event| event['stage'] == 'api-probe' }
    assert_includes result[:stderr], 'GitHub API 提交校验未通过'
    assert result[:events].any? { |event| event['stage'] == 'pod' && event['arguments'] == %w[repo update public-alias --verbose] }
    assert_private_and_restored(result)
  end

  def test_git_api_accepts_sha64_with_cocoapods_headers
    result = run_fixture('JOBS_PROXY_TEST_API_MODE' => 'sha64')
    assert_equal 0, result[:status]
    assert_handoff(result, ORIGINAL_PROXY, '1')
    request = result[:events].find { |event| event['stage'] == 'api-probe' }
    refute_nil request
    assert_includes request['arguments'], 'Accept: application/vnd.github.v3.sha'
    assert_includes request['arguments'], 'User-Agent: CocoaPods'
    assert_includes result[:stderr], 'git 可用'
    assert_private_and_restored(result)
  end

  def test_invalid_cdn_json_uses_only_real_specs_git_fallback
    result = run_fixture('JOBS_POD_PROXY_URL' => SELECTED_PROXY, 'JOBS_PROXY_TEST_ROUTE' => 'proxy', 'JOBS_PROXY_TEST_ROUTE_HTTP' => 'html')
    assert_equal 0, result[:status]
    assert_handoff(result, SELECTED_PROXY, '2')
    assert result[:events].any? { |event| event['stage'] == 'route' && event['arguments'].include?('https://github.com/CocoaPods/Specs.git') }
    assert_private_and_restored(result)
  end

  def test_invalid_cdn_identity_and_git_response_do_not_inject_proxy
    result = run_fixture('JOBS_POD_PROXY_URL' => SELECTED_PROXY, 'JOBS_PROXY_TEST_ROUTE' => 'proxy',
                         'JOBS_PROXY_TEST_ROUTE_HTTP' => 'wrong-version', 'JOBS_PROXY_TEST_ROUTE_GIT' => 'invalid')
    assert_equal 0, result[:status]
    assert_handoff(result, ORIGINAL_PROXY, '1')
    assert_includes result[:stderr], '网络尚未恢复'
    assert_private_and_restored(result)
  end

  def test_explicit_empty_proxy_environment_is_preserved
    config = "<dictionary> {\nHTTPSEnable : 1\nHTTPSProxy : 127.0.0.1\nHTTPSPort : 18888\n}\n"
    result = run_fixture('https_proxy' => '', 'JOBS_PROXY_TEST_SYSTEM_CONFIG' => config)
    assert_equal 0, result[:status]
    assert_handoff(result, '', '1')
    assert_private_and_restored(result)
  end

  def test_explicit_empty_pod_proxy_disables_automatic_system_injection
    config = "<dictionary> {\nHTTPSEnable : 1\nHTTPSProxy : 127.0.0.1\nHTTPSPort : 18888\n}\n"
    result = run_fixture('https_proxy' => nil, 'JOBS_POD_PROXY_URL' => '', 'JOBS_PROXY_TEST_SYSTEM_CONFIG' => config)
    assert_equal 0, result[:status]
    assert_handoff(result, nil, '1')
    assert_private_and_restored(result)
  end

  def test_git_url_proxy_and_its_empty_value_are_not_overridden
    config = "<dictionary> {\nHTTPSEnable : 1\nHTTPSProxy : 127.0.0.1\nHTTPSPort : 18888\n}\n"
    ['http://configured.invalid:18082', ''].each do |value|
      result = run_fixture('https_proxy' => nil, 'JOBS_PROXY_TEST_GIT_PROXY' => value, 'JOBS_PROXY_TEST_SYSTEM_CONFIG' => config)
      assert_equal 0, result[:status]
      assert_handoff(result, nil, '1')
      assert result[:events].any? { |event| event['stage'] == 'configuration' }
      assert_private_and_restored(result)
    end
  end

  def test_inherited_route_keeps_existing_environment
    result = run_fixture
    assert_equal 0, result[:status]
    assert_handoff(result, ORIGINAL_PROXY, '1')
    assert_includes result[:stderr], '复用当前 CocoaPods 链路'
    assert result[:events].any? { |event| event['stage'] == 'api-probe' }
    assert_includes result[:stderr], 'git 可用'
    assert_private_and_restored(result)
  end

  def test_unavailable_routes_do_not_fake_success_or_block_specs_probe
    result = run_fixture('JOBS_PROXY_TEST_ROUTE' => 'unavailable')
    assert_equal 0, result[:status]
    assert_handoff(result, ORIGINAL_PROXY, '1')
    assert_includes result[:stderr], '网络尚未恢复'
    refute_includes result[:stderr], '已验证已有代理'
    assert_private_and_restored(result)
  end

  def test_disabled_adaptation_skips_git_route_probe
    result = run_fixture('JOBS_POD_NETWORK_ADAPT' => '0')
    assert_equal 0, result[:status]
    refute result[:events].any? { |event| event['stage'].start_with?('route') }
    assert_handoff(result, ORIGINAL_PROXY, '1')
    assert_private_and_restored(result)
  end

  def test_missing_ruby_warns_and_preserves_existing_specs_workflow
    result = run_fixture('JOBS_PROXY_TEST_NO_RUBY' => '1')
    assert_equal 0, result[:status]
    assert_includes result[:stderr], '网络适配未完成'
    assert_handoff(result, ORIGINAL_PROXY, '1')
    assert_private_and_restored(result, worker_started: false)
  end

  def test_forbidden_payload_key_rejects_the_whole_payload
    payload = ['https_proxy', SELECTED_PROXY, 'PATH', '/forbidden', '']
    result = run_fixture('JOBS_PROXY_TEST_PAYLOAD' => JSON.generate(payload))
    assert_equal 0, result[:status]
    assert_includes result[:stderr], '网络载荷校验失败'
    assert_handoff(result, ORIGINAL_PROXY, '1')
    assert_private_and_restored(result)
  end

  def test_truncated_payload_rejects_all_pairs
    payload = ['https_proxy', SELECTED_PROXY, 'HTTP_PROXY', 'unterminated']
    result = run_fixture('JOBS_PROXY_TEST_PAYLOAD' => JSON.generate(payload))
    assert_equal 0, result[:status]
    assert_includes result[:stderr], '网络载荷校验失败'
    assert_handoff(result, ORIGINAL_PROXY, '1')
    assert_private_and_restored(result)
  end

  def test_shell_metacharacters_remain_literal_data
    value = "literal$(touch injected);`touch injected`;\"'\\end"
    result = run_fixture('JOBS_PROXY_TEST_PAYLOAD' => JSON.generate(['https_proxy', value, '']))
    assert_equal 0, result[:status]
    assert_handoff(result, value, '1')
    refute result[:injected], 'NUL 载荷被当成 Shell 代码执行'
    assert_private_and_restored(result)
  end

  def test_repo_failure_propagates_and_cleans_private_payload
    result = run_fixture('JOBS_POD_PROXY_URL' => SELECTED_PROXY, 'JOBS_PROXY_TEST_ROUTE' => 'proxy', 'JOBS_PROXY_TEST_POD_RESULT' => '7')
    assert_equal 7, result[:status]
    assert_handoff(result, SELECTED_PROXY, '2')
    assert_private_and_restored(result)
  end

  def test_failed_specs_probe_never_refreshes_and_still_restores_parent
    result = run_fixture('JOBS_POD_PROXY_URL' => SELECTED_PROXY, 'JOBS_PROXY_TEST_ROUTE' => 'proxy', 'JOBS_PROXY_TEST_SPECS_FAIL' => '1')
    assert_equal 1, result[:status]
    refute result[:events].any? { |event| event['stage'] == 'pod' && event['arguments'][1] != 'list' }
    assert_private_and_restored(result)
  end

  private

  def assert_handoff(result, proxy, count)
    downstream = result[:events].reject { |event| event['stage'].start_with?('route') || event['stage'] == 'configuration' }
    assert downstream.any? { |event| event['stage'] == 'curl' }
    assert downstream.any? { |event| event['stage'] == 'pod' }
    downstream.each do |event|
      environment = event['environment']
      if proxy.nil?
        assert_nil environment['https_proxy'], event['stage']
      else
        assert_equal proxy, environment['https_proxy'], event['stage']
      end
      assert_equal count, environment['GIT_CONFIG_COUNT'], event['stage']
      assert_equal 'http.https://private.invalid/.proxy', environment['GIT_CONFIG_KEY_0']
      assert_equal 'http://private-proxy.invalid:18081', environment['GIT_CONFIG_VALUE_0']
      assert_equal 'localhost,private.invalid', environment['NO_PROXY']
      if count == '2'
        assert_equal 'http.https://github.com/.proxy', environment['GIT_CONFIG_KEY_1']
        assert_equal proxy, environment['GIT_CONFIG_VALUE_1']
      end
      if event['stage'] == 'pod' && event['arguments'][1] == 'update'
        assert_equal '8', environment['COCOAPODS_CDN_MAX_CONCURRENCY']
        assert_includes event['arguments'], '--verbose'
      end
    end
  end

  def assert_private_and_restored(result, worker_started: true)
    assert_equal result[:before], result[:after], '父 Shell 环境被临时代理改变'
    assert_empty result[:payloads], '私有网络载荷未清理'
    assert_equal '600', result[:payload_mode] if worker_started
    refute_includes result[:stdout] + result[:stderr] + result[:log], SELECTED_PROXY
    refute_includes result[:stdout] + result[:stderr] + result[:log], 'fixture-password'
  end

  def run_fixture(options = {})
    Dir.mktmpdir('jobs-update-proxy-tests-') do |root|
      bin = File.join(root, 'bin')
      runtime = File.join(root, 'runtime')
      FileUtils.mkdir_p([bin, runtime])
      File.write(File.join(bin, 'ruby-runner'), RUBY_RUNNER)
      %w[git curl pod].each { |name| File.write(File.join(bin, name), FAKE_TOOL) }
      Dir.glob(File.join(bin, '*')).each { |path| File.chmod(0o755, path) }
      runner = File.join(root, 'runner.zsh')
      File.write(runner, SHELL_RUNNER)
      File.write(File.join(root, 'events'), '')
      environment = ENV.keys.grep(/\A(?:https?_proxy|HTTPS?_PROXY|all_proxy|ALL_PROXY|NO_PROXY|GIT_CONFIG_|JOBS_POD_)/).to_h { |key| [key, nil] }
      environment.merge!(
        'PATH' => "#{bin}:/usr/bin:/bin:/usr/sbin:/sbin", 'TMPDIR' => runtime,
        'JOBS_PROXY_TEST_ROOT' => root, 'JOBS_PROXY_TEST_SCRIPT' => SCRIPT,
        'JOBS_PROXY_TEST_ROUTE' => 'inherited', 'JOBS_PROXY_TEST_EXPECTED_PROXY' => SELECTED_PROXY,
        'https_proxy' => ORIGINAL_PROXY, 'NO_PROXY' => 'localhost,private.invalid',
        'GIT_CONFIG_COUNT' => '1', 'GIT_CONFIG_KEY_0' => 'http.https://private.invalid/.proxy',
        'GIT_CONFIG_VALUE_0' => 'http://private-proxy.invalid:18081',
        'JOBS_SPECS_PROBE_TIMEOUT' => '8', 'JOBS_SPECS_CONNECT_TIMEOUT' => '1', 'JOBS_SPECS_UPDATE_TIMEOUT' => '8',
        'JOBS_SPECS_SOURCE' => 'auto'
      ).merge!(options)
      stdout, stderr, status = Open3.capture3(environment, '/bin/zsh', runner, chdir: root)
      { stdout: stdout, stderr: stderr, status: status.exitstatus,
        events: File.readlines(File.join(root, 'events')).map { |line| JSON.parse(line) },
        before: JSON.parse(File.read(File.join(root, 'before.json'))),
        after: JSON.parse(File.read(File.join(root, 'after.json'))),
        payload_mode: File.file?(File.join(root, 'payload-mode')) ? File.read(File.join(root, 'payload-mode')) : nil,
        payloads: Dir.glob(File.join(runtime, 'jobs-update-pod-route.*')),
        log: File.file?(File.join(root, 'update.log')) ? File.read(File.join(root, 'update.log')) : '',
        injected: File.exist?(File.join(root, 'injected')) }
    end
  end
end
