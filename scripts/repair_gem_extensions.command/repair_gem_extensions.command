#!/bin/zsh
# 脚本自述：
# - 脚本名称：repair_gem_extensions.command。
# - 核心用途：用当前 CocoaPods / Ruby 对应运行时重建缺失的原生 Gem 扩展。
# - 影响范围：只修缺失扩展的已安装版本，先备份 Gem 目录及当前平台扩展目录；不升级 Ruby 或 Gem。
# - 运行提示：默认只检查；--repair 才修复，-t 明确允许无人值守；日志写系统临时目录。

GEMEXT_MODE=check
GEMEXT_UNATTENDED=0
GEMEXT_LOG=''

# >>> Jobs Gem extension repair >>>
# 定位 CocoaPods 所用 Ruby；无法解析时复用当前 Ruby 和现有 Homebrew Ruby。
jobs_gemext_find_ruby() {
  local pod_bin='' entry='' interpreter='' candidate=''
  local -a candidates=()
  [[ -z "${JOBS_GEMEXT_RUBY:-}" ]] || candidates+=("$JOBS_GEMEXT_RUBY")
  pod_bin="$(whence -p pod 2>/dev/null)" || pod_bin=''
  if [[ -n "$pod_bin" ]]; then
    pod_bin="${pod_bin:A}"
    for entry in "$pod_bin" "${pod_bin:h:h}/libexec/bin/pod"; do
      [[ -f "$entry" ]] || continue
      interpreter="$(/usr/bin/sed -n '1s/^#!//p' "$entry")"
      [[ "$interpreter" == /*/ruby && -x "$interpreter" ]] && candidates+=("$interpreter")
    done
  fi
  candidates+=("$(whence -p ruby 2>/dev/null)" /opt/homebrew/opt/ruby/bin/ruby /usr/local/opt/ruby/bin/ruby)
  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    if env -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_BIN_PATH \
      "$candidate" --disable-gems -rrbconfig -e 'exit(RUBY_ENGINE == "ruby" ? 0 : 1)' >/dev/null 2>&1; then
      print -r -- "$candidate"
      return 0
    fi
  done
  print -u2 -r -- '✖ 没有找到可用的 Ruby，停止原生扩展检查。'
  return 1
}
# 清理仅影响本次 worker 的 Bundler 注入，原调用终端环境保持不变。
jobs_gemext_process() {
  local repair_mode="${1:-check}" ruby_bin=''
  ruby_bin="$(jobs_gemext_find_ruby)" || return 1
  env -u RUBYOPT -u RUBYLIB -u RUBYGEMS_GEMDEPS -u BUNDLE_GEMFILE -u BUNDLE_BIN_PATH \
    "$ruby_bin" --disable-gems - "$repair_mode" "${JOBS_GEMEXT_BACKUP_ROOT:-$HOME/.JobsMacEnv/backups/gem-native-extensions}" <<'JOBS_GEMEXT_RUBY'
# >>> Jobs Gem extension Ruby >>>
require 'rubygems'
require 'rbconfig'
require 'fileutils'
require 'tmpdir'
require 'open3'
require 'rubygems/ext'

# 仅重建实际缺失的本平台扩展；保留已安装版本和原 Gem 安装记录。
class JobsGemExtensionRepair
  FEATURES = {
    'io-console' => ['io/console'],
    'erb' => ['erb', 'erb/escape'],
    'prism' => ['prism'],
    'json' => ['json']
  }.freeze
  PRIORITY = %w[bigdecimal io-console json prism psych erb nkf rbs].freeze
  CLEAN_ENV = %w[RUBYOPT RUBYLIB RUBYGEMS_GEMDEPS BUNDLE_GEMFILE BUNDLE_BIN_PATH].freeze

  class << self
    # 按当前 Ruby 的实际 Gem 搜索目录读取完整 spec，健康 / 默认 Gem 不进入修复。
    def missing_specs
      Gem.path.flat_map do |root|
        Dir.glob(File.join(root, 'specifications', '*.gemspec')).map do |path|
          spec = Gem::Specification.load(path)
          next unless spec && !spec.default_gem? && !spec.extensions.empty? && spec.missing_extensions?

          spec
        end.compact
      end.uniq { |spec| File.realpath(spec.loaded_from) }.sort_by do |spec|
        [PRIORITY.index(spec.name) || PRIORITY.length, spec.name, spec.version]
      end
    end

    # 只有确实有待修目标时，才检查本机编译工具链。
    def preflight!
      %w[rubyhdrdir rubyarchhdrdir].each do |key|
        file = key == 'rubyhdrdir' ? 'ruby.h' : 'ruby/config.h'
        raise "当前 Ruby 缺少头文件：#{key}" unless File.file?(File.join(RbConfig::CONFIG.fetch(key), file))
      end
      raise 'make 不可用' unless system('make', '--version', out: File::NULL, err: File::NULL)
      if RUBY_PLATFORM.include?('darwin')
        raise 'Xcode / Command Line Tools 的 clang 不可用' unless system('/usr/bin/xcrun', '--find', 'clang', out: File::NULL, err: File::NULL)
      end
    end

    # 完整备份会被构建器覆盖的 Gem 源目录和当前平台目录，旧平台扩展保持原状。
    def snapshot(spec, backup_root)
      source = spec.full_gem_path
      extension = spec.extension_dir
      raise "Gem 目录不存在或为链接：#{source}" unless File.directory?(source) && !File.symlink?(source)
      raise "Gem 目录不可写：#{source}" unless File.writable?(source) && File.writable?(File.dirname(source))
      ancestor = File.dirname(extension)
      ancestor = File.dirname(ancestor) until File.exist?(ancestor) || ancestor == File.dirname(ancestor)
      raise "扩展目录不可写：#{ancestor}" unless File.writable?(ancestor)
      raise '扩展目标不允许符号链接' if File.symlink?(extension)
      raise '仅支持本机已有的 extconf.rb 扩展源码' unless spec.extensions.all? { |entry| entry.end_with?('extconf.rb') && File.file?(File.join(source, entry)) }

      directory = Dir.mktmpdir("#{spec.full_name.gsub(/[^A-Za-z0-9_.-]/, '_')}-", backup_root)
      saved = {
        :directory => directory,
        :source => source,
        :extension => extension,
        :extension_existed => File.exist?(extension),
        :spec_path => spec.loaded_from,
        :spec_bytes => File.binread(spec.loaded_from)
      }
      FileUtils.cp_r(source, File.join(directory, 'gem'), preserve: true)
      FileUtils.cp_r(extension, File.join(directory, 'extension'), preserve: true) if saved[:extension_existed]
      FileUtils.cp(spec.loaded_from, File.join(directory, 'original.gemspec'), preserve: true)
      File.write(File.join(directory, 'manifest.txt'), saved.reject { |key, _| key == :spec_bytes }.map { |key, value| "#{key}=#{value.inspect}" }.join("\n") + "\n")
      saved
    end

    # 使用 RubyGems 原生构建接口；不经过 Gem 安装器、插件或远程下载。
    def build_spec(spec)
      spec.build_extensions
    end

    # 新 Ruby 进程精确激活原版本，并确认该版本的原生二进制真正载入。
    def verify_spec(spec)
      environment = CLEAN_ENV.each_with_object({}) { |key, result| result[key] = nil }
      environment['GEM_HOME'] = spec.base_dir
      environment['GEM_PATH'] = ([spec.base_dir] + Gem.path).uniq.join(File::PATH_SEPARATOR)
      features = FEATURES.fetch(spec.name, [spec.name.tr('-', '_')])
      code = <<~'VERIFY'
        require 'rubygems'
        name, version, source, extension, *features = ARGV
        gem name, "= #{version}"
        spec = Gem.loaded_specs.fetch(name)
        abort '激活了其它目录的同名 Gem' unless File.realpath(spec.full_gem_path) == File.realpath(source)
        features.each { |feature| require feature }
        binaries = $LOADED_FEATURES.select do |path|
          path.match?(/\.(bundle|so)\z/) &&
            [source, extension].any? { |root| File.expand_path(path).start_with?(File.expand_path(root) + File::SEPARATOR) }
        end
        expected = Dir.glob(File.join(extension, '**', '*.{bundle,so}')).map { |path| File.basename(path) }.uniq
        loaded = binaries.map { |path| File.basename(path) }.uniq
        abort '原生扩展未实际加载完整，或回退到了纯 Ruby 实现' if expected.empty? || !(expected - loaded).empty?
      VERIFY
      output, status = Open3.capture2e(environment, RbConfig.ruby, '--disable-gems', '-e', code,
                                      spec.name, spec.version.to_s, spec.full_gem_path, spec.extension_dir, *features)
      raise "原生扩展加载验证失败：#{output}" unless status.success?
      true
    end

    # 将失败构建留在备份旁，恢复本目标的原目录；不回滚其它已成功目标。
    def restore_snapshot(saved)
      directory = saved.fetch(:directory)
      source = saved.fetch(:source)
      extension = saved.fetch(:extension)
      FileUtils.mv(source, File.join(directory, 'failed-gem')) if File.exist?(source)
      FileUtils.cp_r(File.join(directory, 'gem'), source, preserve: true)
      FileUtils.mv(extension, File.join(directory, 'failed-extension')) if File.exist?(extension)
      if saved[:extension_existed]
        FileUtils.mkdir_p(File.dirname(extension))
        FileUtils.cp_r(File.join(directory, 'extension'), extension, preserve: true)
      end
      if !File.file?(saved[:spec_path]) || File.binread(saved[:spec_path]) != saved[:spec_bytes]
        FileUtils.cp(File.join(directory, 'original.gemspec'), saved[:spec_path], preserve: true)
      end
    end

    # 每个目标先备份，构建或验证失败则恢复并明确保留排查材料。
    def repair_spec(spec, backup_root)
      saved = snapshot(spec, backup_root)
      puts "➤ 重建 #{spec.full_name}；备份：#{saved[:directory]}"
      build_spec(spec)
      raise '构建结束后仍缺少当前平台完成标记' unless File.file?(spec.gem_build_complete_path)
      raise 'Gem 安装记录被意外改写' unless File.binread(spec.loaded_from) == saved[:spec_bytes]
      verify_spec(spec)
      File.write(File.join(saved[:directory], 'result.txt'), "success\n")
      puts "✔ #{spec.full_name}：当前平台扩展已构建并实际加载。"
      true
    rescue StandardError => error
      warn "✖ #{spec.full_name}：#{error.class}: #{error.message}"
      if saved
        File.write(File.join(saved[:directory], 'result.txt'), "failed\n#{error.class}: #{error.message}\n")
        begin
          restore_snapshot(saved)
          warn "⚠ 已恢复该 Gem 原目录；排查材料：#{saved[:directory]}"
        rescue StandardError => restore_error
          warn "✖ 自动恢复失败：#{restore_error.message}；完整备份：#{saved[:directory]}"
          raise
        end
      end
      false
    end

    # 持有修复锁后重新检测；健康设备不写备份、不重复编译。
    def run(mode:, backup_root:, runtime_label: nil)
      raise '未知执行模式' unless %w[check repair].include?(mode)
      puts "ℹ Ruby #{RUBY_VERSION}；平台 #{Gem::Platform.local}；运行时 #{runtime_label || RbConfig.ruby}"
      targets = missing_specs
      puts "ℹ 当前平台缺失原生扩展：#{targets.length} 个已安装版本。"
      targets.each { |spec| puts "  - #{spec.full_name}" }
      return 0 if targets.empty? || mode == 'check'

      preflight!
      FileUtils.mkdir_p(backup_root)
      File.open(File.join(backup_root, '.repair.lock'), File::RDWR | File::CREAT, 0o600) do |lock|
        raise '另一个 Gem 扩展修复正在运行' unless lock.flock(File::LOCK_EX | File::LOCK_NB)

        targets = missing_specs
        failed = targets.reject { |spec| repair_spec(spec, backup_root) }
        remaining = missing_specs
        puts "ℹ 修复成功 #{targets.length - failed.length}；失败 #{failed.length}；仍缺失 #{remaining.length}。"
        return failed.empty? && remaining.empty? ? 0 : 1
      end
    rescue StandardError => error
      warn "✖ 扩展修复停止：#{error.class}: #{error.message}"
      1
    end

    # 单文件 Shell 通过 stdin 执行；加载测试中的类定义不会启动修复。
    def run_cli
      $stdout.sync = true
      $stderr.sync = true
      exit run(mode: ARGV.fetch(0), backup_root: File.expand_path(ARGV.fetch(1)))
    end
  end
end

JobsGemExtensionRepair.run_cli if $PROGRAM_NAME == '-'
# <<< Jobs Gem extension Ruby <<<
JOBS_GEMEXT_RUBY
}
# <<< Jobs Gem extension repair <<<

# 自述按终端能力着色，业务日志仍保留原始文本。
jobs_intro_line() {
  local role="$1" message="$2" style='0;34'
  [[ "$role" != title ]] || style='1;31'
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" &&
        "${PLAIN_OUTPUT:-0}" != 1 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]]; then
    printf '\033[%sm%s\033[0m\n' "$style" "$message"
  else
    print -r -- "$message"
  fi
}
# 先展示固定自述；修复须显式选择，-t 仅在调用者已授权时免交互。
show_script_intro_and_wait() {
  local argument=''
  jobs_intro_line title 'repair_gem_extensions.command：Gem 原生扩展检查与修复'
  jobs_intro_line body '1、默认只检查；--repair 使用当前 Ruby 重编译缺失扩展，保持 Gem 版本。'
  jobs_intro_line body '2、每个目标先完整备份；失败恢复原目录。旧平台扩展、Ruby、Gem 版本与全局代理保持。'
  jobs_intro_line body '3、日志在系统临时目录的 repair_gem_extensions.log；备份在用户 .JobsMacEnv/backups/gem-native-extensions。'
  jobs_intro_line body '4、普通模式先回车确认自述，再非空输入执行；Ctrl+C 取消。-t / --unattended 为显式无人值守入口。'
  for argument in "$@"; do
    case "$argument" in
      --check) GEMEXT_MODE=check ;;
      --repair) GEMEXT_MODE=repair ;;
      -t|--unattended) GEMEXT_UNATTENDED=1 ;;
      -h|--help) print -r -- '用法：repair_gem_extensions.command [--check | --repair] [-t]'; exit 0 ;;
      *) print -u2 -r -- "未知参数：$argument"; exit 2 ;;
    esac
  done
  if (( GEMEXT_UNATTENDED == 0 )); then
    [[ -t 0 ]] || { print -u2 -r -- '请在终端确认，或显式传入 -t。'; exit 2; }
    local answer=''
    IFS= read -r '?👉 已了解影响，按回车继续；输入其它内容取消：' answer || exit 2
    [[ -z "$answer" ]] || exit 0
  fi
}
# 普通入口逐项确认，直接回车跳过本次检查或修复。
confirm_operation() {
  (( GEMEXT_UNATTENDED == 1 )) && return 0
  local answer=''
  IFS= read -r "?➤ 执行 ${GEMEXT_MODE}？直接回车跳过，输入任意字符后回车执行：" answer || return 1
  [[ -n "$answer" ]]
}
# 确认后初始化本次日志；加载测试模式不触发真实业务。
initialize_runtime() {
  setopt NO_NOMATCH
  setopt PIPE_FAIL
  GEMEXT_LOG="${TMPDIR:-/tmp}/repair_gem_extensions.log"
  : > "$GEMEXT_LOG" || return 1
}
# 同时保留终端和落盘结果，并传播真实修复退出码。
run_repair() {
  jobs_gemext_process "$GEMEXT_MODE" 2>&1 | /usr/bin/tee -a "$GEMEXT_LOG"
  local -a stage_codes=("${pipestatus[@]}")
  (( stage_codes[1] == 0 )) || return "${stage_codes[1]}"
  return "${stage_codes[2]}"
}
# 编排自述、日志与单次检测或修复。
main() {
  show_script_intro_and_wait "$@" # 展示边界并处理明确的执行模式。
  confirm_operation || return 0 # 普通执行回车跳过；显式无人值守直接执行。
  initialize_runtime || return $? # 确认后初始化日志；不可写则停止。
  run_repair # 检测缺失项，必要时备份、构建并复检。
}

main "$@"
