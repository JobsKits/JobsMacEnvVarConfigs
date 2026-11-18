# Jobs 环境配置管理面板

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、用途与入口](#panel-entry)
- [二、操作方式](#operation)
- [三、卸载、后台与日志](#lifecycle-logs)
- [四、语言、主题与资源](#preferences-resources)
- [五、构建与检查](#build-validation)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

管理入口与原终端入口分别保留，按当前所选组件执行安装或反安装。

## 一、<span id="panel-entry">用途与入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

原生 [**AppKit**](https://developer.apple.com/documentation/appkit) 面板用于按组件安装、预览计划和卸载本机终端配置及短命令。原终端安装入口继续独立使用。

| 入口 | 用途 |
| --- | --- |
| [环境配置管理 App](../【MacOS】🌍环境配置管理.app) | 双击打开组件管理面板 |
| [原终端安装](../【MacOS】install.command/【MacOS】install.command) | 保留原来的终端安装流程 |
| [构建脚本](./【MacOS】构建安装面板.command/【MacOS】构建安装面板.command) | 从本仓源码与当前后端生成 App |
| [面板源码](./Sources/EnvironmentManager.swift) | 原生交互、后台任务、日志与偏好 |
| [翻译资源](./Resources/PanelTranslations.json) | 完整的十种界面语言 |

## 二、<span id="operation">操作方式</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 打开面板，等待组件状态读取完成。首次进入为空选；可搜索、全选当前结果、清空全部勾选，也可逐项勾选。

- 选择“安装”或“卸载”。切换操作保留当前勾选；列表显示名称、说明、存在状态或本轮执行结果。

- 可先点“预览计划”。预览使用后端 `--dry-run`，会显示实际组件和依赖计划。

- 点击“安装所选组件”或“卸载所选组件”，核对汇总后明确确认。确认框默认取消；取消不会启动业务。

- 查看实时日志和逐项结果。面板每轮把完整选中集合交给后端一次，由后端处理依赖次序、互斥锁和公共支持；后端事件更新列表，真实退出码保留在日志中。

命令可按需单独勾选；所需的环境核心和公共运行支持由后端在同一轮准备。卸载使用整批选择保护仍被其它命令使用的公共文件，完整卸载按后端依赖次序执行。

安装确认中的自动补齐仅针对当前环境部署所需的配置与公共脚本支持。部署某个短命令不会立即运行其业务或安装该业务的 SDK；需要实际安装开发工具及修复 Node／Ruby 等运行时，使用新系统配置面板的对应组件。只读目录、预览与卸载继续保持零依赖安装副作用。“更新开发环境（update）”的[桌面右键入口](../../../OS@Extension/MacOS@Extension/JobsEnvironmentUpdater/README.md)由 Finder 扩展面板独立安装／卸载；本面板部署 `update` 短命令，不将终端环境配置安装视为右键菜单已经注册。

## 三、<span id="lifecycle-logs">卸载、后台与日志</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 卸载只撤回后端能核对归属和当前状态的受管变更。原有、共享、后续已修改或缺少恢复依据的对象保留，并报告未完成原因。非零退出码显示失败或未完成。
- 安装、卸载和计划同一时刻只运行一轮。任务开始后关闭窗口会退到状态栏并继续；任务结束仍保留状态栏入口。进行中禁止完全退出，面板不强杀安装进程。
- 空闲关闭窗口可选择退到后台、完全退出或取消。后台入口恢复同一窗口、选择和日志。
- 日志可选中文字复制，可复制可见日志或定位完整日志文件。手动滚动、翻页会暂停追尾，重新勾选“自动滚动”恢复。
- 每轮完整日志独立保存在当前用户的 Application Support 内 `JobsEnvironmentManager/Logs/env`，目录和文件分别使用私有权限。窗口最多保留约一百万字符，完整文件继续保留。日志写入失败会提示，窗口日志仍可复制。

## 四、<span id="preferences-resources">语言、主题与资源</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

支持简体中文、繁体中文、藏文、英文、日文、法文、西班牙文、德文、俄罗斯文、韩文，以及语言跟随系统。支持白天、黑夜、跟随系统主题；偏好保存在当前面板自己的用户配置域，不与环境配置面板混用。切换语言或主题保留选择和日志。

组件包名、命令名和路径保留技术名称。非中文界面的组件说明使用对应语言的类别说明；后端原始日志保持原文便于排查。

App 内包含二进制、翻译、后端与环境配置资源，运行时从 Bundle 定位，不依赖构建机路径或源码目录。可单独复制整个 App 再打开。图标来源为本仓已有的 [icon.png](../icon.png)，构建时转换为 ICNS；状态栏复用同一图标。

## 五、<span id="build-validation">构建与检查</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

需已安装的 [**Xcode**](https://developer.apple.com/xcode/) 命令行工具，目标系统为 macOS 13 或以上。构建脚本不执行环境安装、卸载或自动安装编译工具。

```zsh
/bin/zsh ./【MacOS】构建安装面板.command/【MacOS】构建安装面板.command --yes
```

默认生成 Apple Silicon／Intel 通用 App。`--native` 只构建当前架构；`--output /明确指定的目标.app` 可输出到其它实际目录。脚本检查目标 App 归属、构建互斥和运行状态，完整打包、签名、自测后再发布；运行中的管理面板需先等任务结束并完全退出。

在上一级目录运行以下只读检查：

```zsh
./【MacOS】🌍环境配置管理.app/Contents/MacOS/JobsEnvironmentManager --self-test
./【MacOS】🌍环境配置管理.app/Contents/MacOS/JobsEnvironmentManager --diagnose
./【MacOS】🌍环境配置管理.app/Contents/MacOS/JobsEnvironmentManager --smoke-test-native
codesign --verify --deep --strict ./【MacOS】🌍环境配置管理.app
```

`--self-test` 检查十语键、目录解析、重复 ID 拒绝、中文日志分帧和包内后端；`--diagnose` 还显示 Bundle 路径并只读查询后端目录；`--smoke-test-native` 使用独立临时偏好域初始化十语三主题控件后退出。上述检查不安装或卸载组件，原生控件初始化通过不等于所有真实环境安装和人工点击均已验收。

构建使用本地 ad-hoc 签名并验证 Bundle 完整性。跨机首次打开仍由系统现行安全策略处理；程序不修改隔离属性或系统安全设置。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
