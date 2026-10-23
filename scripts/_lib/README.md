# JobsMacEnv 私有函数库

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、实现与能力边界](#jobs-toc-heading-2)
- [二、输入、结果与副作用](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录提供被[功能命令包](../README.md)加载的实现。用户从 `a`、`zz`、`apk` 等入口操作；这些 `.zsh` 文件定义内部函数，不作为独立程序双击执行。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、实现与能力边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 / 目录 | 提供的能力 | 主要调用入口 |
| --- | --- | --- |
| [jobs_session_lib.zsh](./jobs_session_lib.zsh) | 打开 bash / zsh 配置、重载配置、重启登录 Shell、按显式开发目录 / 当前 Xcode / 常见位置定位 Device Hub 或 Simulator | `a`、`b`、`save`、`rb`、`i` |
| [jobs_path_lib.zsh](./jobs_path_lib.zsh) | 解析拖入路径、Finder 替身和软链接；目标为文件时进入父目录；对所选文件增加执行权限并运行 | `zz`、`x` |
| [jobs_flutter_lib.zsh](./jobs_flutter_lib.zsh) | Flutter / Dart 执行器解析、项目识别与目录选择、FVM 路由与修复、JDK 17 选择、doctor / 构建准备、APK / iOS 构建、配置文件打开 | `flutter_project`、`d`、`check1`、`check`、`c`、`fixfvm`、`buildCheck`、`apk`、`ipa`、`config` |
| [jobs_git_network_strategy/](./jobs_git_network_strategy/README.md) | Git 可执行包装、push 失败后的动态网络策略、进程环境与隔离验证 | 终端 Git 包装及接入此策略的 Sourcetree 入口 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、输入、结果与副作用 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

输入由上层命令传入，包括项目目录、拖入路径、构建参数及环境变量；默认项目位置和 Dart 补全配置位于 Flutter 库的配置段，复制环境后需要核对。结果写到终端、当前 Shell、目标工程或构建输出中，各入口的 README 负责具体交互与日志。

函数定义被加载不代表业务已执行，但调用函数可能切换目录、重载环境、运行文件、重新激活全局 FVM、写项目 Java 版本或构建产物。需要影响当前终端的操作必须经 [entrypoints 函数包装](../entrypoints.command/README.md)调用；独立子进程不能更改父 Shell 状态。复制命令包时须连同它依赖的私有库保留相对布局。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
