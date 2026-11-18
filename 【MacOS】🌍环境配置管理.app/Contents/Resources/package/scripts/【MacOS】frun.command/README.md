# frun · Flutter Demo 独立运行

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

新开终端输入 `frun`，再手动输入或把一个 `.dart` 文件拖入终端，回车即运行该 Demo。源码必须有直接 `main` 入口，继续使用它所属的 [**Flutter**](https://flutter.dev/) 工程、依赖、资源及平台宿主，不需要打开 Demo 总目录 App。

## 一、<span id="usage">运行示例</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
frun
# 此时输入 / 拖入文件：/你的工程/lib/demos/某功能/某功能.dart
# 回车运行；Flutter 结束后继续等待下一份源码，q 退出备战状态。

frun '/你的工程/lib/demos/某功能/某功能.dart'
frun -d chrome '/你的工程/lib/demos/某功能/某功能.dart'
frun --dry-run '/你的工程/lib/demos/某功能/某功能.dart'
frun '/你的工程/lib/demos/某功能/某功能.dart' -- --release
frun --help
```

未部署短命令时，可从完整 `scripts/` 目录直接执行：

```shell
/bin/zsh './【MacOS】frun.command/【MacOS】frun.command'
```

该相对路径示例以 `scripts/` 为当前位置；入口本身从实际位置定位相邻 `_lib`，任意工作目录均可调用脚本绝对路径。默认不选设备，由 Flutter 原生设备选择接管；`r` 热重载、`R` 热重启、`q` 结束本次 Flutter。备战状态的 `q` 才退出 frun。

## 二、<span id="parameters">参数、路径与边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 输入 | 行为与默认值 |
| --- | --- |
| 无参数 | 备战循环；提交有效路径即确认启动，运行结束后可换 Demo；空输入或无效目标重新询问 |
| 单个 `.dart` | 先显示目标、所属工程、SDK 命令，按回车确认后运行一次 |
| `-d ID` / `--device ID` | 传给 `flutter run -d`，默认留给 Flutter 原生设备选择 |
| `--dry-run` | 需要明确路径；只校验与打印计划，不调用 Flutter、联网或创建日志 |
| `--yes` | 显式确认指定目标，可供已授权自动化使用；无参模式仍需要交互终端 |
| `-- 参数…` | 原样透传 `flutter run` 参数；禁止再次指定 target / device 以免替换用户选中的源码 |
| `-h` / `--help` | 只打印帮助，无业务副作用 |

先接受真实文件路径，再按 zsh 词法解析 Finder 拖入的转义文本；兼容中文、空格、引号、相对路径与 `~/`。每次只能一个文件，不执行输入中的变量替换、命令替换或其它 Shell 表达式。路径按真实文件解析，向上选择最近 `pubspec.yaml`；普通 Dart package、辅助文件和 `part of` 文件明确报错，不跨过其它嵌套 package 找外层宿主。

入口检查是轻量的直接 `main` 声明检查，最终语法与入口合法性由 Dart 编译器决定。Demo 独立运行不等于把任意 helper 文件变成独立 App，也不复制实现或另造 `main`。

## 三、<span id="sdk-and-lifecycle">SDK、缓存与生命周期</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1、优先所属工程 / 上级配置的 `.fvm/flutter_sdk/bin/flutter`；FVM 配置存在但链接不可用时，使用已安装的 `fvm flutter`。FVM 与对应 SDK 都缺失时，显示确切位置并停止，绝不改用全局另一版本。

2、没有 FVM 绑定时使用 PATH 中的 Flutter。普通运行不升级 SDK 或重绑频道；项目的动态 `stable` 配置继续由原有 FVM 流程管理。

3、实际运行复用随包 `_lib/【MacOS】FlutterSDK命令适配.sh/` 与相邻 SDK 网络模块；沿用其缺失组件补齐、下载前选路和取消策略。不额外运行 `clean`、`pub get` 或更新工程依赖命令；`flutter run` 自身仍可能解析依赖、下载平台组件、构建和写入工程缓存。

4、Flutter 的输入输出直接连接当前终端，不用管道夺走热重载按键。确认后的独立日志位于系统临时目录 `frun.XXXXXXXX`，只记录调度信息及退出码；Flutter 全量输出直接显示于终端。失败退出码保留；`Ctrl+C` 取消。frun 本身不驻留后台，不持久化所选目标或设备。

5、同一当前终端采用内嵌保护保存临时配色，退出按可验证快照恢复；非 TTY、`NO_COLOR` 或不支持的终端保持纯文本。不会修改用户默认 Profile 或全局 Shell 配置。

## 四、<span id="deployment">安装、分项管理与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

[环境同步入口](../../【MacOS】install.command/README.md)部署完整命令包和 `~/.local/bin/frun` 转发器；[分项管理后端](../../【MacOS】环境管理后端.command/README.md)通过 `cmd-frun` 独立选择并按原有收据撤回。`list` 中的 Flutter Demo 与终端函数均调用同一包；分发时保留相邻 `_lib` SDK 资源，不能单独把真实脚本复制到 `bin/`。

本轮验证记录见[独立运行验收](../../项目相关报告/Flutter-Demo终端独立运行.md)。源码合同、替身及 PTY 验证、当前机器命令部署、真实 Demo 编译运行分别记账，不把只读计划当作已启动全部 Demo。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
