# Jobs 窗口录屏隔离回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行方式](#jobs-toc-heading-2)
- [二、测试覆盖](#jobs-toc-heading-3)
- [三、依赖与隔离边界](#jobs-toc-heading-4)
- [四、结果与排查](#jobs-toc-heading-5)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

验证[窗口录屏入口](../../README.md)的参数、依赖门禁和真实键盘交互。测试从生产脚本提取函数，移除末尾的 `main "$@"` 后加载；实际采集、编译、依赖安装和系统授权均不执行。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

从本目录运行，阅读自述后按回车确认，Ctrl+C 可取消：

```zsh
zsh './【MacOS】窗口录屏测试.command'
```

自动回归使用显式参数，无须回答业务菜单：

```zsh
NO_COLOR=1 zsh './【MacOS】窗口录屏测试.command' --yes
```

也可从其它目录以真实脚本路径调用；被测入口按测试文件所在位置解析。`--help` 只显示说明，未知参数报错退出。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、测试覆盖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 范围 | 断言 |
| --- | --- |
| 帮助优先 | 帮助位于无效参数、缺值参数、冲突模式或版本选项之后仍显示帮助；不会初始化日志、缓存和会话目录。 |
| 自述返回 | 从 list 进入时，最初自述按真实左方向键立即返回 20，兼容录屏专用与通用父标记，尚未初始化环境；普通回车仍确认继续。 |
| 参数校验 | 拒绝 NaN、无穷、负数、零、超大值、缺值、未知声音模式、错误输出后缀、模式冲突；保留有效小数时长和中文空格路径。 |
| 健康复用 | 依赖全健康时不调用安装通道，非交互指定窗口 ID 的路径不要求 fzf。 |
| 条件式修复 | 末端工具缺失、Apple 工具链与 Homebrew 多层缺失时依次补齐；成功后立即复检，后续调用复用健康结果。 |
| 失败阻断 | 安装失败、安装后复检失败、上游修复失败和禁止修复时均停止，不进入后续业务。 |
| 只读体检 | `--doctor` 不调用修复、编译、采集或授权，缺失依赖如实返回失败。 |
| SDK 重试 | 验证网络与本地故障分类、更新目录和安装连续网络失败后成功、分别递增退避、本地及未知错误停止，以及退避期间 Ctrl+C 取消。 |
| 真实键盘 | 在真实 PTY 中运行现有 [**fzf**](https://formulae.brew.sh/formula/fzf)，发送方向键、查询和回车；独立调用选窗左键返回 0，list 上下文返回 20 供父菜单重绘；配置左键返回真实选窗，无匹配时仍能逐层返回，Esc 才取消本轮。 |
| 帧率与声音 | 帧率进入独立菜单，覆盖 15／24／25／30／50／60 预设及自定义输入；声音进入 none／system 子菜单。子菜单左键只退一层，设置确认后回配置，跨菜单保留帧率和声音。 |
| 数字输入 | 自定义帧率仅接受 ASCII 数字，覆盖退格、1／60 边界、0／61 拒绝后纠正、120 不截成 12、Unicode 和字母符号忽略、CSI／OSC／SS3 控制序列吞除；混合粘贴整段拒绝，纯数字粘贴中的换行不提交。左键保留旧值并回帧率菜单，Esc／真实 Ctrl+C 取消本轮。 |
| 输入清理 | 真实 PTY 下直接运行生产数字输入函数与信号／EXIT 清理；提交、返回、Esc 和真实 SIGINT 后必须发送关闭 bracketed paste 的 `2004l` 序列，清空临时模式标志，取消时帧率不变且不进入录制。 |
| 明确开始 | 唯一“开始录制”操作只将本次选择的身份 token 交给假录制边界，不执行真实采集。 |
| 保存与完成 | 默认桌面、中文空格目录拖入、无效目录重问、EOF 取消、显式输出路径、非交互地址要求；假引擎 INT 保存成功后询问目录，失败或无最终文件不询问，默认不打开且不自动播放。 |
| 选窗状态 | 真实 PTY 下默认只有一条主窗口；普通菜单不提供辅助模式切换；显式诊断模式标注范围和候选数；重新加载从零到一时当前 header 清除空态，不留下框外空态日志。 |
| 范围开关 | `--all` 只切换浏览器／全部应用；显式 CLI `--include-auxiliary` 保留诊断能力，列窗和按 ID 解析正确透传；fzf 自带动作行计数隐藏，header 只统计真实窗口记录。 |

参数用例运行真实入口，依赖用例运行原始门禁函数并覆盖修复边界。PTY 用例使用确定的假窗口清单；fzf 是真实执行的程序，不用假选择结果代替键盘操作。选窗状态用例额外记录传入真实 fzf 的 header、行数据和参数，核对每次刷新后的当前状态；不会把累计 PTY 原始输出中曾出现的旧字节误当成仍在显示的空态。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、依赖与隔离边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 使用 [**MacOS**](https://www.apple.com/macos/) 自带的 `/bin/zsh` 和 `/usr/bin/ruby`，测试框架仅使用 [**Ruby**](https://www.ruby-lang.org/) 标准库 `PTY`、`Open3`、`FileUtils`、`Tmpdir` 与 `io/console`。
- 真实键盘回归要求本机已有健康 [**fzf**](https://formulae.brew.sh/formula/fzf)，先检查版本；缺失时清楚报错停止，不安装或升级软件。
- 假 Homebrew 只允许只读版本、前缀和配置查询；所有安装请求只写入隔离 trace，不运行真实包管理器。
- 测试不执行实际 `softwareupdate` 安装、Xcode 安装器、Swift 源码编译、原生录屏或授权入口。真实 `--doctor` 用例会查询系统版本、架构、已有编译器版本、SDK 和 fzf；编译器版本探测可能创建其自身的系统临时目录，但不会创建本工具的日志或编译缓存。
- 每轮使用系统临时目录下独立的 `jobs-window-record-tests.*` 夹具；不修改 `HOME`、Shell 配置、已有缓存和录制文件。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、结果与排查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

成功时输出断言数量和 `PASS`，退出码为 0；失败时输出失败用例或 PTY 等待目标，返回非零。夹具路径始终先显示，失败现场保留，可在相应子目录查看 `trace`、生产函数快照和假实现；PTY 用例的 `pty-tail` 保存最后阶段的原始输出，便于核对退出时的控制序列。

每个 PTY 阶段采用有限等待，结束后回收本次创建的假业务进程。测试不将语法检查或假依赖分支通过等同于真实 SDK 安装、系统权限授予或浏览器录制成功；真实媒体采集仍需独立验收。

目录结构：

```text
【MacOS】窗口录屏测试.command/
├── 【MacOS】窗口录屏测试.command
└── README.md
```

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
