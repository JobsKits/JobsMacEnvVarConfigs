# frozen_string_literal: true
# Jobs：只验证提示展示和真实read，不进入清理阶段或修改终端主题。
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'pty'
require 'timeout'

class PromptStyleTests < Minitest::Test
  TERMINAL = File.expand_path('../../【MacOS】clean.command', __dir__)
  MENU = File.expand_path('../../../../../../OS@Extension/MacOS@Extension/JobsDiskSpaceInfo/Scripts/【MacOS】清理磁盘空间.command/【MacOS】清理磁盘空间.command', __dir__)
  SCRIPTS = [TERMINAL, MENU].freeze
  CSI = /\e\[[0-9;]*m/.freeze
  QUESTION = '是否进入 Xcode 清理？[回车继续 / 其它输入跳过]：'

  def fixtures
    SCRIPTS.each do |script|
      Dir.mktmpdir('jobs-prompt-style-') do |directory|
        source = File.read(script)
        block = source[/^# JOBS_INPUT_CHOICE_STYLE_BEGIN\n.*?^# JOBS_INPUT_CHOICE_STYLE_END/m]
        read = source[/^jobs_xcode_read\(\) \{\n.*?^\}/m]
        raise 'missing prompt definitions' unless block && read
        definitions = File.join(directory, 'definitions.zsh')
        File.write(definitions, block + "\n" + read + "\n")
        yield directory, definitions
      end
    end
  end

  def env_for(directory, extra = {})
    { 'HOME' => directory, 'TMPDIR' => directory, 'TERM' => 'xterm-256color', 'NO_COLOR' => nil, 'PLAIN_OUTPUT' => nil, 'IS_SOURCETREE_RUNTIME' => nil, 'SOURCETREE_TEST' => nil, 'SOURCE_TREE_TEST' => nil }.merge(extra)
  end

  def run_pty(directory, definitions, code, extra: {}, input: nil, ready: nil)
    transcript = +''
    result = nil
    PTY.spawn(env_for(directory, extra), '/bin/zsh', '-c', "stty -echo rows 25 columns 110\nsource \"$1\"\n" + code, '--', definitions) do |reader, writer, pid|
      sent = input.nil?
      begin
        Timeout.timeout(5) do
          loop do
            transcript << reader.readpartial(8192)
            if !sent && transcript.b.include?(ready.b)
              writer.write(input)
              writer.flush
              sent = true
            end
          end
        end
      rescue EOFError, Errno::EIO
        # 仅展示/读取进程结束后PTY关闭。
      rescue Timeout::Error
        Process.kill('TERM', pid) rescue nil
        flunk "提示隔离验证超时：#{transcript.inspect}"
      ensure
        _, result = Process.wait2(pid) rescue nil
      end
    end
    assert result&.success?, transcript
    transcript.force_encoding(Encoding::UTF_8)
  end

  def assert_prompt_colors(output, question, green, red)
    assert_includes output, "\e[1;36m#{question}\e[0m"
    assert_includes output, "\e[1;32m#{green}"
    assert_includes output, "\e[1;31m#{red}"
    state = ''
    output.split(/(\e\[[0-9;]*m)/).each do |part|
      if part.match?(CSI)
        state = part
      elsif part.include?('/') || part.include?('[') || part.include?(']') || part.include?('？')
        assert_equal "\e[0m", state, "separator leaked style: #{output.inspect}"
      end
    end
  end

  def test_xcode_question_is_styled_and_read_preserves_spaces_unicode_and_backslashes
    fixtures do |directory, definitions|
      answer = "  保留\\原样\t  "
      code = <<~'ZSH'
        jobs_xcode_read '是否进入 Xcode 清理？[回车继续 / 其它输入跳过]：'
        result=$?
        printf '\nREAD_STATUS:%s\nANSWER:<%s>\n' "$result" "$REPLY"
      ZSH
      output = run_pty(directory, definitions, code, input: answer + "\n", ready: '其它输入跳过')
      assert_prompt_colors(output, '是否进入 Xcode 清理', '回车继续', '其它输入跳过')
      assert_includes output, 'READ_STATUS:0'
      assert_includes output, "ANSWER:<#{answer}>"
      assert_includes output, "]：\e[0m"
    end
  end

  def test_english_existing_styles_and_multiline_keep_text_and_reset
    fixtures do |directory, definitions|
      code = <<~'ZSH'
        jobs_prompt_render $'\033[0;35mContinue cleanup? [Enter to continue / type anything to skip]:\033[0m\n确认下一步？[回车执行 / 任意字符取消]：'
      ZSH
      output = run_pty(directory, definitions, code)
      assert_includes output, "\e[1;36mContinue cleanup\e[0m?"
      assert_includes output, "\e[1;32mEnter to continue"
      assert_includes output, "\e[1;31mtype anything to skip"
      assert_includes output, "\e[1;36m确认下一步\e[0m？"
      refute_includes output, "\e[0;35m"
      assert_equal "Continue cleanup? [Enter to continue / type anything to skip]:\r\n确认下一步？[回车执行 / 任意字符取消]：", output.gsub(CSI, '')
      assert output.end_with?("\e[0m"), output.inspect
    end
  end

  def test_prompt_without_choices_uses_cyan_bold
    fixtures do |directory, definitions|
      output = run_pty(directory, definitions, "jobs_prompt_render '请输入目标名称：'\n")
      assert_equal "\e[1;36m请输入目标名称\e[0m：\e[0m", output
    end
  end

  def test_no_color_empty_dumb_plain_and_sourcetree_do_not_emit_ansi
    cases = [{ 'NO_COLOR' => '' }, { 'NO_COLOR' => '1' }, { 'TERM' => 'dumb' }, { 'TERM' => '' }, { 'PLAIN_OUTPUT' => '1' }, { 'IS_SOURCETREE_RUNTIME' => '1' }, { 'SOURCETREE_TEST' => '1' }, { 'SOURCE_TREE_TEST' => '1' }]
    fixtures do |directory, definitions|
      cases.each do |extra|
        output = run_pty(directory, definitions, "jobs_prompt_render '#{QUESTION}'\n", extra: extra)
        assert_equal QUESTION, output
        refute_includes output, "\e"
      end
    end
  end

  def test_noninteractive_render_and_eof_keep_plain_text_and_read_status
    fixtures do |directory, definitions|
      code = <<~'ZSH'
        source "$1"
        jobs_prompt_render '是否进入 Xcode 清理？[回车继续 / 其它输入跳过]：'
        printf '\n'
        jobs_xcode_read '是否进入 Xcode 清理？[回车继续 / 其它输入跳过]：'
        printf '\nREAD_STATUS:%s\n' "$?"
      ZSH
      out, err, status = Open3.capture3(env_for(directory), '/bin/zsh', '-c', code, '--', definitions, stdin_data: '')
      assert status.success?, out + err
      assert_includes out, QUESTION
      assert_includes out, 'READ_STATUS:1'
      refute_includes out + err, "\e"
    end
  end

  def test_c_locale_does_not_split_chinese_and_parent_locale_and_input_stay_unchanged
    prompt = "安装路径选择？[回车继续 / 其它输入跳过]：\n路径：/tmp/中文 路径"
    answer = "  /tmp/原始 中文\\路径  "
    cases = [
      [{ 'LC_ALL' => 'C', 'LC_CTYPE' => 'C' }, true, 'x:C:x:C'],
      [{ 'LC_ALL' => nil, 'LC_CTYPE' => 'C' }, true, '::x:C'],
      [{ 'LC_ALL' => 'C', 'LC_CTYPE' => 'C', 'NO_COLOR' => '' }, false, 'x:C:x:C']
    ]
    fixtures do |directory, definitions|
      cases.each do |locale, colored, expected_locale|
        code = <<~'ZSH'
          jobs_xcode_read "$JOBS_TEST_PROMPT"
          result=$?
          printf '\nREAD_STATUS:%s\nANSWER:<%s>\nLOCALE:<%s:%s:%s:%s>\n' "$result" "$REPLY" "${LC_ALL+x}" "${LC_ALL-}" "${LC_CTYPE+x}" "${LC_CTYPE-}"
        ZSH
        output = run_pty(directory, definitions, code, extra: locale.merge('JOBS_TEST_PROMPT' => prompt), input: answer + "\n", ready: '中文 路径')
        assert output.valid_encoding?, output.inspect
        assert_includes output.gsub(CSI, ''), prompt.gsub("\n", "\r\n")
        assert_includes output, "ANSWER:<#{answer}>"
        assert_includes output, "LOCALE:<#{expected_locale}>"
        assert_includes output, 'READ_STATUS:0'
        if colored
          assert_includes output, "\e[1;36m安装路径选择\e[0m"
          assert_includes output, "\e[1;32m回车继续"
        else
          refute_includes output, "\e"
        end
      end
    end
  end

  def test_ordinary_logs_intro_and_urls_are_not_question_colored_and_logs_are_plain
    fixtures do |directory, definitions|
      code = <<~'ZSH'
        printf '\033[0;34m普通功能说明\033[0m\n' | jobs_prompt_filter
        printf '\033[32;4mhttps://example.com/help?q=1\033[0m\n' | jobs_prompt_filter
        printf '\033[1;35m是否继续？[回车确认 / 其它输入跳过]\033[0m\n' | jobs_prompt_tee "$TMPDIR/render.log"
      ZSH
      output = run_pty(directory, definitions, code)
      refute_includes output, "\e[1;36m"
      assert_includes output, "\e[0;34m普通功能说明\e[0m"
      assert_includes output, "\e[32;4mhttps://example.com/help?q=1\e[0m"
      log = File.read(File.join(directory, 'render.log'))
      assert_equal "是否继续？[回车确认 / 其它输入跳过]\n", log
      refute_includes log, "\e"
    end
  end
end
