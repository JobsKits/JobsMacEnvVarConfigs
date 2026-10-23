# JobsMacEnv 功能脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、目录与入口](#jobs-toc-heading-2)
  - [i.command](#jobs-toc-heading-3)
- [二、依赖与运行边界](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录保存 JobsMacEnv 自维护命令的源码包及私有函数库。安装器将其复制到用户环境目录中的大写 `Scripts/`，终端与菜单执行运行副本；修改源码后须同步相应文件。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、目录与入口 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 路径 | 职责 |
| --- | --- |
| [`list.command/`](./list.command/README.md) | 交互菜单，按功能调度相邻命令包。 |
| [`entrypoints.command/`](./entrypoints.command/README.md) | 注册终端命令并解析运行副本。 |
| [`runtime_init.command/`](./runtime_init.command/README.md) | 用户终端的运行环境初始化。 |
| [`i.command/`](./i.command/README.md) | 新旧 Xcode 模拟器启动入口。 |
| [`simios.command/`](./simios.command/README.md) | 检查 Xcode 并按独立确认流程补齐 iOS 运行时。 |
| [`【MacOS】⚙️配置全局Markdown目录过滤器.command/`](./【MacOS】⚙️配置全局Markdown目录过滤器.command/README.md) | 独立安装用户级 Git 目录过滤器；完整脚本包可复制运行，不在环境同步时自动安装过滤器。 |
| [`a.command/`](./a.command/README.md) | 用系统关联应用打开 bash 登录配置。 |
| [`b.command/`](./b.command/README.md) | 用系统关联应用打开 zsh 配置。 |
| [`save.command/`](./save.command/README.md) | 重新加载 bash / zsh 常用配置；当前会话生效需使用已注册函数。 |
| [`rb.command/`](./rb.command/README.md) | 以登录模式重启 Shell；函数调用可替换当前终端 Shell。 |
| [`shell.command/`](./shell.command/README.md) | 扫描本机可用 Shell，菜单选择后用 `chsh` 设置默认登录 Shell。 |
| [`x.command/`](./x.command/README.md) | 给所选文件增加执行权限并立即运行。 |
| [`zz.command/`](./zz.command/README.md) | 解析 Finder 替身 / 软链接 / 拖入路径，进入目标目录或文件的父目录。 |
| [`config.command/`](./config.command/README.md) | 用 Xcode 或文本编辑器打开默认或指定配置文件。 |
| [`code.command/`](./code.command/README.md) | 查找已有 VS Code 官方 CLI，并转交打开参数。 |
| [`d.command/`](./d.command/README.md) | 选择并进入 Flutter 工程目录。 |
| [`check1.command/`](./check1.command/README.md) | 显示 Dart、FVM、Flutter 路径与版本，排查命令路由。 |
| [`check.command/`](./check.command/README.md) | 按目标项目的 FVM 配置运行 Flutter doctor。 |
| [`c.command/`](./c.command/README.md) | 在目标 Flutter 工程锁定 JDK 17 并执行清理 / 检查。 |
| [`buildCheck.command/`](./buildCheck.command/README.md) | 构建前准备：清理工程、获取依赖并检查工具链。 |
| [`apk.command/`](./apk.command/README.md) | 检查 Flutter / FVM / JDK 17，构建 Android release APK 并打开产物目录。 |
| [`ipa.command/`](./ipa.command/README.md) | 检查 Flutter 环境，构建 iOS release 产物并打开输出目录；签名依赖工程配置。 |
| [`fixfvm.command/`](./fixfvm.command/README.md) | 重新激活 Dart 全局 FVM，处理 Dart SDK 内核版本不匹配。 |
| [`flutter_project.command/`](./flutter_project.command/README.md) | 按项目路由 Flutter / Dart 的 source 函数模块；优先项目 FVM。 |
| [`install_jdk17.command/`](./install_jdk17.command/README.md) | 检测 JDK 17，按 Temurin、Zulu、OpenJDK 候选安装并复检。 |
| [`install.command/`](./install.command/README.md) | 通过分类多选菜单安装所选开发依赖；不同于上一层的环境配置同步入口。 |
| [`update.command/`](./update.command/README.md) | 按项维护开发工具、语言运行时和依赖；支持逐项确认及无人值守模式。 |
| [`pods.command/`](./pods.command/README.md) | 选择本地 Pod / podspec，在独立检查环境运行 `pod lib lint`。 |
| [`repair_gem_extensions.command/`](./repair_gem_extensions.command/README.md) | 默认检查缺失的 Ruby 原生扩展；显式修复时备份、重建、验证，失败恢复。 |
| [`codemap.command/`](./codemap.command/README.md) | 为当前或一个 / 多个指定目录构建 CodeGraph 索引，支持拖入路径。 |
| [`clean.command/`](./clean.command/README.md) | 清空 Shell 历史，处理失效 App 图标并执行其约定的本机清理。 |
| [`clr.command/`](./clr.command/README.md) | 借助本地 Chrome 扩展清空下载记录，保留已下载文件。 |
| [`dq.command/`](./dq.command/README.md) | 仅移除所选目标的 quarantine 标记；支持预览与处理后打开。 |
| [`df.command/`](./df.command/README.md) | 以 dufs + Caddy 共享所选目录，支持只读 / 读写、认证与访问地址配置。 |
| [`download.command/`](./download.command/README.md) | 以 yt-dlp 下载媒体，可使用浏览器 Cookies；已配置 API 时支持 cobalt 后端。 |
| [`to.command/`](./to.command/README.md) | FFmpeg 视频 / 音频格式转换；格式短命令复用此入口，目标重名时保留原文件。 |
| [`gif.command/`](./gif.command/README.md) | 录制终端或全屏，输出 GIF / MP4；支持对已有录制重新生成产物。 |
| [`m5c.command/`](./m5c.command/README.md) | 读取两个文件的 MD5 摘要并比较，不修改输入。 |
| [`flat.command/`](./flat.command/README.md) | 参数或交互方式做 URL 百分号解码，支持 `--plus` 并复制结果。 |
| [`decode.command/`](./decode.command/README.md) | 循环输入 URL 编码文本，解码后显示并复制，输入 `q` 退出。 |
| [`cor.command/`](./cor.command/README.md) | HEX / RGB / RGBA / ARGB 互转，输出通道数值和终端色块。 |
| [`ts.command/`](./ts.command/README.md) | 识别秒 / 毫秒 / 微秒 / 纳秒时间戳，按所选时区输出日期、星期和偏移。 |
| [`trs.command/`](./trs.command/README.md) | macOS 原生文本翻译；可切换方向与对方语言，单个空格进入设置。 |
| [`tts.command/`](./tts.command/README.md) | 选择 MOSS-TTS-Nano / VoxCPM2 / Supertonic，准备模型、合成和播放语音。 |
| [`_lib/`](./_lib/README.md) | 被入口 source 的会话、路径、Flutter 实现，以及 Git 动态网络策略。 |

表中每项链接进入该功能的输入、参数、运行步骤和影响范围。短命令需要先通过[环境安装入口](../install.command/README.md)部署；直接运行源码中的命令包时，其私有库、资源和相邻依赖仍须保持完整。`entrypoints`、`runtime_init` 与 `flutter_project` 是 source 模块，不按独立程序双击运行。

### <span id="jobs-toc-heading-3" data-jobs-toc="v2">[i.command](./i.command/i.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 打开当前 [**Xcode**](https://developer.apple.com/xcode/) 对应的模拟器管理应用。

- 展示脚本内置自述并等待一次回车，Ctrl+C 取消。
- 加载相邻会话库，优先遵循显式开发目录，再检查系统所选 Xcode 和常见安装位置。
- Xcode 27 使用 Device Hub，旧版使用 Simulator；按完整路径启动并保留失败退出码。
- 将启动路径和错误写入系统临时目录中的 `i.log`；需要 iOS 运行时则另行使用 `simios`。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">二、依赖与运行边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

命令使用 [**macOS**](https://www.apple.com/macos/) 自带 `/bin/zsh`。各包的依赖、参数、日志和风险以其配套 README 与内置自述为准；`_lib/` 不独立执行。模拟器入口需要包含 Device Hub 或 Simulator 的完整 Xcode，不安装组件、不修改全局开发目录。安装、清理和更新等其它命令具有各自的写入范围，运行前应阅读相应自述。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
