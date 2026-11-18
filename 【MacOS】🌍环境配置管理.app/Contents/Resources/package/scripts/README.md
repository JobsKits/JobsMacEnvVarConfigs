# JobsMacEnv 功能脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

本目录保存 JobsMacEnv 自维护命令的源码包及私有函数库。安装器将其复制到用户环境目录中的大写 `Scripts/`，终端与菜单执行运行副本；修改源码后须同步相应文件。

## 一、目录与入口 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 路径 | 职责 |
| --- | --- |
| [`【MacOS】list.command/`](./【MacOS】list.command/README.md) | 交互菜单，按功能调度相邻命令包。 |
| [`【MacOS】entrypoints.command/`](./【MacOS】entrypoints.command/README.md) | 注册终端命令并解析运行副本。 |
| [`【MacOS】runtime_init.command/`](./【MacOS】runtime_init.command/README.md) | 用户终端的运行环境初始化。 |
| [`【MacOS】i.command/`](./【MacOS】i.command/README.md) | 新旧 Xcode 模拟器启动入口。 |
| [`【MacOS】simios.command/`](./【MacOS】simios.command/README.md) | 检查 Xcode 并按独立确认流程补齐 iOS 运行时。 |
| [`【MacOS】⚙️配置全局Markdown目录过滤器.command/`](./【MacOS】⚙️配置全局Markdown目录过滤器.command/README.md) | 独立安装用户级 Git 目录过滤器；完整脚本包可复制运行，不在环境同步时自动安装过滤器。 |
| [`【MacOS】a.command/`](./【MacOS】a.command/README.md) | 用系统关联应用打开 bash 登录配置。 |
| [`【MacOS】b.command/`](./【MacOS】b.command/README.md) | 用系统关联应用打开 zsh 配置。 |
| [`【MacOS】save.command/`](./【MacOS】save.command/README.md) | 重新加载 bash / zsh 常用配置；当前会话生效需使用已注册函数。 |
| [`【MacOS】rb.command/`](./【MacOS】rb.command/README.md) | 以登录模式重启 Shell；函数调用可替换当前终端 Shell。 |
| [`【MacOS】shell.command/`](./【MacOS】shell.command/README.md) | 扫描本机可用 Shell，菜单选择后用 `chsh` 设置默认登录 Shell。 |
| [`【MacOS】x.command/`](./【MacOS】x.command/README.md) | 给所选文件增加执行权限并立即运行。 |
| [`【MacOS】zz.command/`](./【MacOS】zz.command/README.md) | 解析 Finder 替身 / 软链接 / 拖入路径，进入目标目录或文件的父目录。 |
| [`【MacOS】config.command/`](./【MacOS】config.command/README.md) | 用 Xcode 或文本编辑器打开默认或指定配置文件。 |
| [`【MacOS】code.command/`](./【MacOS】code.command/README.md) | 查找已有 VS Code 官方 CLI，并转交打开参数。 |
| [`【MacOS】d.command/`](./【MacOS】d.command/README.md) | 选择并进入 Flutter 工程目录。 |
| [`【MacOS】check1.command/`](./【MacOS】check1.command/README.md) | 显示 Dart、FVM、Flutter 路径与版本，排查命令路由。 |
| [`【MacOS】check.command/`](./【MacOS】check.command/README.md) | 按目标项目的 FVM 配置运行 Flutter doctor。 |
| [`【MacOS】c.command/`](./【MacOS】c.command/README.md) | 在目标 Flutter 工程锁定 JDK 17 并执行清理 / 检查。 |
| [`【MacOS】buildCheck.command/`](./【MacOS】buildCheck.command/README.md) | 构建前准备：清理工程、获取依赖并检查工具链。 |
| [`【MacOS】apk.command/`](./【MacOS】apk.command/README.md) | 检查 Flutter / FVM / JDK 17，构建 Android release APK 并打开产物目录。 |
| [`【MacOS】ipa.command/`](./【MacOS】ipa.command/README.md) | 检查 Flutter 环境，构建 iOS release 产物并打开输出目录；签名依赖工程配置。 |
| [`【MacOS】fixfvm.command/`](./【MacOS】fixfvm.command/README.md) | 重新激活 Dart 全局 FVM，处理 Dart SDK 内核版本不匹配。 |
| [`【MacOS】flutter_project.command/`](./【MacOS】flutter_project.command/README.md) | 按项目路由 Flutter / Dart 的 source 函数模块；优先项目 FVM。 |
| [`【MacOS】frun.command/`](./【MacOS】frun.command/README.md) | `frun` 进入备战状态，输入 / 拖入单个 Dart main 独立运行；支持设备、只读计划与 Flutter 参数透传。 |
| [`【MacOS】install_jdk17.command/`](./【MacOS】install_jdk17.command/README.md) | 检测 JDK 17，按 Temurin、Zulu、OpenJDK 候选安装并复检。 |
| [`【MacOS】install.command/`](./【MacOS】install.command/README.md) | 通过分类多选菜单安装所选开发依赖；不同于上一层的环境配置同步入口。 |
| [`【MacOS】update.command/`](./【MacOS】update.command/README.md) | 无参数默认低打扰，自动维护开发工具、语言运行时和依赖，最多启动阶段系统密码，不等待逐项或收尾重试输入；保留 Homebrew 更新锁等待及 Flutter／CocoaPods 网络适配；Flutter 只升级已有独立全局环境，未安装则跳过，保留项目 FVM；[桌面右键入口](../../../OS@Extension/MacOS@Extension/JobsEnvironmentUpdater/README.md)由 Finder 面板独立安装，随包运行同源完整脚本，遵循同一默认交互约定。 |
| [`【MacOS】pods.command/`](./【MacOS】pods.command/README.md) | 选择本地 Pod / podspec，在独立检查环境运行 `pod lib lint`。 |
| [`【MacOS】repair_gem_extensions.command/`](./【MacOS】repair_gem_extensions.command/README.md) | 默认检查缺失的 Ruby 原生扩展；显式修复时备份、重建、验证，失败恢复。 |
| [`【MacOS】codemap.command/`](./【MacOS】codemap.command/README.md) | 为当前或一个 / 多个指定目录构建 CodeGraph 索引，支持拖入路径。 |
| [`【MacOS】clean.command/`](./【MacOS】clean.command/README.md) | 清空 Shell 历史和用户缓存，处理失效 App 图标，备份并注销实体已缺失的 iOS 模拟器登记。 |
| [`【MacOS】clr.command/`](./【MacOS】clr.command/README.md) | 借助本地 Chrome 扩展清空下载记录，保留已下载文件。 |
| [`【MacOS】dq.command/`](./【MacOS】dq.command/README.md) | 仅移除所选目标的 quarantine 标记；支持预览与处理后打开。 |
| [`【MacOS】df.command/`](./【MacOS】df.command/README.md) | 以 dufs + Caddy 共享所选目录，支持只读 / 读写、认证与访问地址配置。 |
| [`【MacOS】download.command/`](./【MacOS】download.command/README.md) | 以 yt-dlp 下载媒体，可使用浏览器 Cookies；已配置 API 时支持 cobalt 后端。 |
| [`【MacOS】to.command/`](./【MacOS】to.command/README.md) | FFmpeg 视频 / 音频格式转换；格式短命令复用此入口，目标重名时保留原文件。 |
| [`【MacOS】gif.command/`](./【MacOS】gif.command/README.md) | 录制终端或全屏，输出 GIF / MP4；支持对已有录制重新生成产物。 |
| [`【MacOS】jrecord.command/`](./【MacOS】jrecord.command/README.md) | `jrecord`：依赖体检、自愈和原生编译后，精确选择浏览器 / 应用窗口，保存不覆盖的独立 MP4。 |
| [`【MacOS】m5c.command/`](./【MacOS】m5c.command/README.md) | 读取两个文件的 MD5 摘要并比较，不修改输入。 |
| [`【MacOS】split.command/`](./【MacOS】split.command/README.md) | `jsplit`：手动输入或拖入文件 / 目录，按分卷上限均摊拆分并校验，源文件默认保留。 |
| [`【MacOS】merge.command/`](./【MacOS】merge.command/README.md) | `jmerge`：手动输入或拖入目录，校验至少两卷的完整分组后按卷号还原，分卷默认保留。 |
| [`【MacOS】flat.command/`](./【MacOS】flat.command/README.md) | 参数或交互方式做 URL 百分号解码，支持 `--plus` 并复制结果。 |
| [`【MacOS】decode.command/`](./【MacOS】decode.command/README.md) | 循环输入 URL 编码文本，解码后显示并复制，输入 `q` 退出。 |
| [`【MacOS】cor.command/`](./【MacOS】cor.command/README.md) | HEX / RGB / RGBA / ARGB 互转，输出通道数值和终端色块。 |
| [`【MacOS】ts.command/`](./【MacOS】ts.command/README.md) | 识别秒 / 毫秒 / 微秒 / 纳秒时间戳，按所选时区输出日期、星期和偏移。 |
| [`【MacOS】trs.command/`](./【MacOS】trs.command/README.md) | macOS 原生文本翻译；可切换方向与对方语言，单个空格进入设置。 |
| [`【MacOS】tts.command/`](./【MacOS】tts.command/README.md) | 选择 MOSS-TTS-Nano / VoxCPM2 / Supertonic，准备模型、合成和播放语音。 |
| [`【MacOS】orc.command/`](./【MacOS】orc.command/README.md) | [**Indra OCR**](https://pypi.org/project/indra-ocr/) 图片／PDF 识别；`orc`、`ORC` 等全部大小写组合等效，依赖与模型就绪后可离线。 |
| [`_lib/`](./_lib/README.md) | 被入口 source 的会话、路径、Flutter 实现，以及 Git 动态网络策略。 |

表中每项链接进入该功能的输入、参数、运行步骤和影响范围。短命令需要先通过[环境安装入口](../【MacOS】install.command/README.md)部署；直接运行源码中的命令包时，其私有库、资源和相邻依赖仍须保持完整。`entrypoints`、`runtime_init` 与 `flutter_project` 是 source 模块，不按独立程序双击运行。

`jsplit` / `jmerge` 不接收路径参数；每次输入或拖入明确目标，空输入、无效路径或没有可处理文件时持续询问，`Ctrl+C` 或输入结束可停止。选择待处理对象后，最终执行菜单默认取消，选中开始并回车才处理，`←` 返回上一选择层。两项工具需要已有可用的 [**fzf**](https://formulae.brew.sh/formula/fzf)，不会自动安装依赖；分卷命名为 `原文件名@序号of总数`，已有目标不覆盖，删除源文件或分卷必须精确输入 `YES`。

`jrecord` 的[完整包](./【MacOS】jrecord.command/README.md)使用 `【MacOS】jrecord.command/【MacOS】jrecord.command`，包含入口和 `Core/` 原生 [**Swift**](https://www.swift.org/) 源码，不依赖第三方 SwiftPM 包。默认交互选择浏览器窗口，可切换全部窗口、音频和录制配置；保存地址确认后显示可鼠标穿透的 5 秒倒计时，结束后才开始采集。取消不录制，默认无声音，现有输出不覆盖。`--doctor` 仅体检，`--prepare` 只修复依赖和编译；运行时按需补齐并复检依赖，不修改原始 `screcord` 仓库。终端短命令使用完整包转发器，不可单独复制 `.command` 到 `bin/`。

`orc` 的[完整说明](./【MacOS】orc.command/README.md)包含 [**Indra OCR**](https://pypi.org/project/indra-ocr/) 参数、独立虚拟环境、模型目录及离线条件。无参数时可输入或拖入路径；`--install` 仅安装工具，首次实际识别才获取缺失模型。环境同步只部署命令包与入口，识别时按需准备依赖；已经准备好工具与模型后可用 `--offline` 运行。

### [【MacOS】i.command](./【MacOS】i.command/【MacOS】i.command)

> **目的：** 打开当前 [**Xcode**](https://developer.apple.com/xcode/) 对应的模拟器管理应用。

- 展示脚本内置自述并等待一次回车，Ctrl+C 取消。
- 加载相邻会话库，优先遵循显式开发目录，再检查系统所选 Xcode 和常见安装位置。
- Xcode 27 使用 Device Hub，旧版使用 Simulator；按完整路径启动并保留失败退出码。
- 将启动路径和错误写入系统临时目录中的 `i.log`；需要 iOS 运行时则另行使用 `simios`。

## 二、依赖与运行边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

命令使用 [**macOS**](https://www.apple.com/macos/) 自带 `/bin/zsh`。各包的依赖、参数、日志和风险以其配套 README 与内置自述为准；`_lib/` 不独立执行。模拟器入口需要包含 Device Hub 或 Simulator 的完整 Xcode，不安装组件、不修改全局开发目录。安装、清理和更新等其它命令具有各自的写入范围，运行前应阅读相应自述。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
