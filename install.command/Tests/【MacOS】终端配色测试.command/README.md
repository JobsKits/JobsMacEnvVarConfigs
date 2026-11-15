# Jobs 终端配色隔离回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、入口与依赖](#usage)
- [二、实际覆盖](#coverage)
- [三、日志与验证边界](#artifacts)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

验证[安装器](../../README.md)内嵌的终端临时配色保护。入口依次运行 17 项生命周期回归和 47 项完整入口查询回归，共 64 场景；在独立伪终端运行假业务，不执行安装、不写入用户终端、不修改 Profile 或 Shell 配置。

## 一、<span id="usage">入口与依赖</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

需要 MacOS、系统 `/bin/zsh` 以及已安装的 [**Python**](https://www.python.org) 3，驱动只使用标准库。缺少依赖立即停止，不进行自动安装。

在本目录执行：

```zsh
./【MacOS】终端配色测试.command
```

无交互的自动回归显式确认隔离执行：

```zsh
NO_COLOR=1 ./【MacOS】终端配色测试.command --yes
```

`NO_COLOR` 只关闭外层测试入口对当前终端的临时配色；测试驱动会在其独立 PTY 中分别构造有色、无色环境，仍执行真实生产配色保护。直接运行或局部验证见[生命周期17项驱动](./terminal_style_pty_tests.py/README.md)和[完整入口47项查询驱动](./terminal_query_retry_tests.py/README.md)。

## 二、<span id="coverage">实际覆盖</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 场景 | 核验行为 |
| --- | --- |
| 正常和业务失败 | 19 项原色逐项精确恢复，回显／规范输入模式恢复，业务退出 7 不被覆盖 |
| 退出答复延迟 | 第一条退出查询延迟 450 毫秒，仍完成恢复；不会将稍迟的答复误报为失败 |
| 分片与结束符 | BEL、ST 两种协议结束符，分片读取仍构成完整答复 |
| 用户后续改色 | 模拟背景被用户修改，保留冲突项、只恢复其它 18 项并报告 |
| 超时与非协议数据 | 不答复、无关输入、非法 RGB 时停止自动覆盖、保留恢复入口和错误状态 |
| 键盘与降级 | 正常业务输入不被吞掉；启动时有无关输入则不改色、降级继续 |
| 可捕获信号 | 独立子进程收到 INT／TERM／HUP 后恢复配色与输入模式，保留 130／143／129 |
| 嵌套和纯文本 | 同 TTY 嵌套只保护一次；`NO_COLOR` 含空值和 `TERM=dumb` 不发出 OSC |
| 丢请求后真重发 | 保存、设置核验和退出三阶段实际丢首请求，核对新的 OSC 请求确实发出；三轮仍无答复时有界降级／失败 |
| 完整入口和旧帧 | 保留真实 bootstrap/reexec，迟到、重复和旧 key 帧不能混成当前目标答复，BEL／ST 分片均能解析 |
| 退出阶段按键余留 | 只容忍帧外 CR／LF、CSI／SS3 方向键，包含分片、连续按键及丢首请求后的按键；完整核验后才恢复原色 |
| 共享按键上限 | 整次退出最多 64 个控制单元，跨颜色项和重发累计；第 65 单元有界停止，不盲目覆盖 |
| 阶段隔离、非法帧和 RGB | 启动／设置核验仍拒绝按键；未知文本、未知转义、帧内按键、残缺帧、未知颜色、不一致重复值及多行 RGB 均不能触发盲目恢复 |

所有 OSC 答复、颜色变化与键盘输入来自测试驱动，不读取原终端或实际应用内容。各子进程均属于本轮独立 PTY，失败时只回收该测试自己创建的进程。

## 三、<span id="artifacts">日志与验证边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

入口日志为系统临时目录中的 `jobs-terminal-style-tests-entry.log`；生命周期17项创建 `jobs-terminal-style-tests.*`，完整入口47项创建 `jobs-terminal-query-retry-tests.*`，分别保留测试汇总、各场景夹具、终端字节日志和模拟恢复文件。任一组失败即返回非零，不能被后一组成功掩盖。

这是可重复的协议与生命周期回归，不替代 Terminal／iTerm 等真实应用的独立会话验色；不能据此声称所有终端、窗口关闭或不可捕获 SIGKILL 均可恢复。不为验色运行完整安装流程。

```text
【MacOS】终端配色测试.command/
├── 【MacOS】终端配色测试.command
├── README.md
├── terminal_style_pty_tests.py/
│   ├── terminal_style_pty_tests.py
│   └── README.md
└── terminal_query_retry_tests.py/
    ├── terminal_query_retry_tests.py
    └── README.md
```

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
