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
| `_lib/` | 被各入口加载的私有实现，包括会话、Flutter、路径及 Git 网络策略。 |
| 其它 `<命令>.command/` | 同名命令与配套 README；完整用途及执行流程见[仓库入口说明](../README.md)。 |

### <span id="jobs-toc-heading-3" data-jobs-toc="v2">[i.command](./i.command/i.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 打开当前 [**Xcode**](https://developer.apple.com/xcode/) 对应的模拟器管理应用。

- 展示脚本内置自述并等待一次回车，Ctrl+C 取消。
- 加载相邻会话库，优先遵循显式开发目录，再检查系统所选 Xcode 和常见安装位置。
- Xcode 27 使用 Device Hub，旧版使用 Simulator；按完整路径启动并保留失败退出码。
- 将启动路径和错误写入系统临时目录中的 `i.log`；需要 iOS 运行时则另行使用 `simios`。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">二、依赖与运行边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

命令使用 [**macOS**](https://www.apple.com/macos/) 自带 `/bin/zsh`。各包的依赖、参数、日志和风险以其配套 README 与内置自述为准；`_lib/` 不独立执行。模拟器入口需要包含 Device Hub 或 Simulator 的完整 Xcode，不安装组件、不修改全局开发目录。安装、清理和更新等其它命令具有各自的写入范围，运行前应阅读相应自述。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
