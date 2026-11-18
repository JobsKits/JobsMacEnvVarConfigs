# Jobs 终端配色 PTY 驱动

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、直接运行](#usage)
- [二、行为与产物](#implementation)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

配合[上级测试入口](../README.md)，使用 [**Python**](https://www.python.org) 标准库 `pty`、`termios` 和 `select` 构造独立终端。它是测试依赖，不是生产安装器或录屏命令的新增运行依赖。

## 一、<span id="usage">直接运行</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录运行：

```zsh
python3 ./terminal_style_pty_tests.py --yes
```

默认按驱动自身位置定位同包安装器，不依赖启动工作目录。可明确传入另一个待审查入口及新的隔离产物目录：

```zsh
python3 ./terminal_style_pty_tests.py --yes \
  --source ../../../【MacOS】install.command \
  --output "${TMPDIR:-/tmp}/jobs-style-reviewed-run"
```

`--output` 必须是本轮新的结果目录；默认自动生成独立目录，保留原有现场，不覆盖其它回归。没有 `--yes` 时先显示自述并等待回车，输入结束或 Ctrl+C 取消。

## 二、<span id="implementation">行为与产物</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

驱动只取受控保护块的函数定义，换成独立假业务，不求值安装器业务正文。模拟器按真实 OSC 设置更新 19 项颜色，并分别回复立即、延迟、分片、冲突或无效结果；最终比对原色、退出码、输入模式和恢复文件。

根 `tests.log` 汇总 17 个场景；各场景目录保留生产保护夹具、终端字节日志和独立的模拟临时目录。字节日志含模拟 OSC 控制序列，不含用户终端内容或凭据。详细覆盖和实际终端的验证边界见[上级说明](../README.md#coverage)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
