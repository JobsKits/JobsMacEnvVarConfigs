# Flutter Demo 终端独立运行验收

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、入口与行为盘点](#assets)
- [二、限定验证](#verification)
- [三、运行边界与撤回](#limits)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

日期：2026-11-17。用户确认的运行方式：新终端输入 `frun` 进入备战状态，输入 / 拖入含 `main` 的 `.dart` 文件并回车独立运行。菜单入口由 `OS@Extension` 的现有 JobsFlutterRunner 双端实现承接；此表只记终端命令范围。

## 一、<span id="assets">入口与行为盘点</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 资产 | 入口 / 默认值 / 行为 | 持久化与生命周期 | 状态 |
| --- | --- | --- | --- |
| 备战命令 | [真实脚本](../scripts/【MacOS】frun.command/【MacOS】frun.command)；无参等待单路径，提交即确认，目标退出后继续等待；q / Ctrl+C 退出 | 当前终端前台运行；不保存 Demo 或设备偏好 | 源码已实现；PTY 已验 |
| 定向运行 | `frun 文件.dart`；显示计划后回车确认；`-d` / `--device` 指定设备；`--` 后传 Flutter 参数 | 同一次调用只启动一个目标，不转写 main 或复制工程 | 源码、替身参数与退出码已验 |
| 只读计划 | `--dry-run 文件.dart`；解析真实文件、轻量 main、最近 Flutter pubspec 与 FVM / PATH SDK | 不调用 SDK、不联网、不创建业务日志 | 源码与替身已验；真实工程全入口检查由主任务记录 |
| SDK 准备 | 先用相邻 `_lib` 的 SDK 适配器执行 `--version`，再原生直连 TTY 执行 `flutter run -t` | 复用已有 SDK；缺失组件沿原适配器策略准备；不升级或改绑频道 | 源码已实现；TTY 及调用一次已验 |
| 安装接线 | 仓根同步器、entrypoints、list、分项后端 `cmd-frun` | bin 转发到完整包；分项管理继续按其收据撤回 | 源码 / 目录读取已验；本轮未执行全环境安装或重建管理 App |
| 本机短命令 | `~/.local/bin/frun` 转发到 `~/.JobsMacEnv/Scripts/【MacOS】frun.command/` | 本轮只新增该包及转发器，未更改 .zshrc、其它命令或既有 SDK 支持文件；未通过分项后端写安装收据，其目录状态会显示 unknown | 新登录 zsh 的命令发现、帮助、真实目标 dry-run 已验 |
| 展示与日志 | 随脚本内嵌标准终端配色保护；非 TTY / NO_COLOR 纯文本；确认后私有日志 | 日志只记调度与退出码，Flutter 输入输出直连终端 | 标准范本两项隔离 PTY 场景已验；未声称所有真实终端主题均验 |

## 二、<span id="verification">限定验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `zsh -n`：frun、entrypoints、list、仓根同步器、分项管理后端均通过。
- 15 项独立夹具检查通过：完整脚本复制 / 改名、中文空格括号引号路径、无关工作目录、原样设备与 `--dart-define` 参数、失败退出码 37、禁止覆写 target、helper 拒绝、注释伪 main 拒绝、最近嵌套非 Flutter package 拒绝、FVM 缺失不降级、fvm 路由、Shell 表达式字面文件安全、dry-run 无 SDK 调用。夹具使用假 SDK 和故意经过管道的假适配器，不访问网络。
- 真实 PTY 中，假 SDK 记录 stdin / stdout 均为 TTY；`read -k1` 无需回车收到 r 和 q，q 后只结束目标并回到备战状态，再 q 回车退出 0。该检查证明按键交给运行目标，不冒称 Flutter 真编译验收。
- 内嵌终端保护复用标准范本，`applied-consecutive-keys`、`applied-later-color-rollback` 两项生产 bootstrap 隔离 PTY 测试通过。
- 本机新登录 zsh 可定位 `~/.local/bin/frun`；胶囊按钮源码从新命令 dry-run 成功，SDK 仍为本工程 `.fvm/flutter_sdk/bin/flutter`。
- 主任务额外执行全 300 注册入口只读计划，并以真实 Flutter 胶囊源码验证 Web 编译 / HTTP 与原生按键：修复后启动 8.7 秒、HTTP 200、单键 h 显示完整帮助、单键 q 正常结束且退出 0。未连接浏览器，不记 UI 或热重载业务验收；最终结果查 Flutter 工程 `项目相关报告/Demo源码目录整理.md#file-launchers` 和 `项目相关报告/验收记录/2026-11-17-Demo独立启动/`。

## 三、<span id="limits">运行边界与撤回</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

Demo 必须有直接 main，并保留所属工程的依赖、资源和平台实现；普通 helper / part 不变成可运行 Demo。main 与 pubspec 是轻量源码预检，最终有效性由 Flutter 编译器判断。实际运行仍受插件平台、设备、签名和服务条件约束。SDK 适配器准备首次自举；实际 run 的终端选择和输出保持原生，不能经日志管道监督。

本机撤回只处理本轮新增且未改动的 `~/.local/bin/frun` 及 `~/.JobsMacEnv/Scripts/【MacOS】frun.command/`，可移到废纸篓；保留原 `.zshrc`、其它命令及 `_lib`。分项管理安装的后续版本使用其原有安装收据卸载；不能把本轮无收据部署误报为受管安装。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
