# frozen_string_literal: true

# 隔离验证内嵌选路与后续 Specs 命令的环境交接，不联网或升级工具。
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
    stage = 'route' if name == 'git' && ARGV.include?('https://github.com/andreamazz/AMPopTip.git')
    record = { 'stage' => stage, 'arguments' => ARGV, 'environment' => ENV.select { |key, _| key =~ /\A(?:https?_proxy|HTTPS?_PROXY|all_proxy|ALL_PROXY|NO_PROXY|GIT_CONFIG_)/ } }
    File.open(File.join(root, 'events'), 'a') { |file| file.puts(JSON.generate(record)) }
    if name == 'git'
      if stage == 'route'
        allowed = ENV.fetch('JOBS_PROXY_TEST_ROUTE') == 'inherited' ||
          (ENV.fetch('JOBS_PROXY_TEST_ROUTE') == 'proxy' && ENV['https_proxy'] == ENV.fetch('JOBS_PROXY_TEST_EXPECTED_PROXY'))
        exit 128 unless allowed
        puts "db495eea0747a3493ca8b3c737d037c0090973db\trefs/tags/4.12.0"
      else
        puts "0123456789012345678901234567890123456789\tHEAD"
      end
    elsif name == 'curl'
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

  def test_enabled_system_proxy_is_used_after_inherited_route_fails
    config = "<dictionary> {\nHTTPSEnable : 1\nHTTPSProxy : 127.0.0.1\nHTTPSPort : 18888\n}\n"
    proxy = 'http://127.0.0.1:18888'
    result = run_fixture('JOBS_PROXY_TEST_ROUTE' => 'proxy', 'JOBS_PROXY_TEST_EXPECTED_PROXY' => proxy, 'JOBS_PROXY_TEST_SYSTEM_CONFIG' => config)
    assert_equal 0, result[:status]
    assert_handoff(result, proxy, '2')
    routes = result[:events].select { |event| event['stage'] == 'route' }
    assert_equal [ORIGINAL_PROXY, proxy], routes.map { |event| event['environment']['https_proxy'] }
    assert_private_and_restored(result)
  end

  def test_inherited_route_keeps_existing_environment
    result = run_fixture
    assert_equal 0, result[:status]
    assert_handoff(result, ORIGINAL_PROXY, '1')
    assert_includes result[:stderr], '复用当前 Git 链路'
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
    refute result[:events].any? { |event| event['stage'] == 'route' }
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
    downstream = result[:events].reject { |event| event['stage'] == 'route' }
    assert downstream.any? { |event| event['stage'] == 'curl' }
    assert downstream.any? { |event| event['stage'] == 'pod' }
    downstream.each do |event|
      environment = event['environment']
      assert_equal proxy, environment['https_proxy'], event['stage']
      assert_equal count, environment['GIT_CONFIG_COUNT'], event['stage']
      assert_equal 'http.https://private.invalid/.proxy', environment['GIT_CONFIG_KEY_0']
      assert_equal 'http://private-proxy.invalid:18081', environment['GIT_CONFIG_VALUE_0']
      assert_equal 'localhost,private.invalid', environment['NO_PROXY']
      if count == '2'
        assert_equal 'http.https://github.com/.proxy', environment['GIT_CONFIG_KEY_1']
        assert_equal proxy, environment['GIT_CONFIG_VALUE_1']
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
        'JOBS_SPECS_PROBE_TIMEOUT' => '3', 'JOBS_SPECS_CONNECT_TIMEOUT' => '1', 'JOBS_SPECS_UPDATE_TIMEOUT' => '3',
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
