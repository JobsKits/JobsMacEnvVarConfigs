# Android SDK 隔离回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行方式](#jobs-toc-heading-2)
- [二、覆盖与边界](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[`android_sdk_tests.zsh`](./android_sdk_tests.zsh) 使用临时假命令验证 [`update.command`](../../update.command) 的 [**Flutter**](https://flutter.dev/) Android 工具自愈和许可复检；不联网、不安装、不升级真实工具，也不修改用户的 SDK、JDK 或环境配置。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在本目录运行：

```zsh
zsh ./android_sdk_tests.zsh
```

- 自动建立独立临时目录，输出每例 `PASS`／`FAIL` 和总数，进程退出时回收本次临时数据。
- 任一例失败时返回非零；按 `Ctrl+C` 可取消。
- 所有路径从测试脚本自身位置解析，支持从其它工作目录调用。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、覆盖与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 健康 SDK 仅直接复用 Flutter 可发现的 `latest`／数字开头版本目录；`jobs-*` 等目录仍可作引导工具，通过 `--sdk_root` 在实际 SDK 补齐 `cmdline-tools;latest`。安装后只剩不可见目录时停止，不误判可用。
- 引导工具缺失或残缺时分别安装／重装一次；安装失败、安装后复检失败或 JDK 不兼容均停止下游许可操作。
- 许可命令零退出码但输出明确错误时失败；许可接受后再次执行 doctor，许可仍未知、SDK 真实资源下载失败、未识别的验证失败和异常退出继续报告未完成。
- `Network resources` 连通性检查与设备离线提示计入环境健康告警，不覆盖已完成的升级结果；同时出现的真实下载错误仍须失败。JDK／SDK 环境只在当前维护函数内生效。
- Android 安装和许可命令默认总时限 `600` 秒，可通过 `JOBS_ANDROID_SDK_TIMEOUT` 设置为 `1`～`1800` 秒；超时仅终止本次命令进程树。测试以 `1` 秒验证卡住退出。
- 隔离回归不代表真实 [**Homebrew**](https://brew.sh/) 下载、Android SDK 安装和许可已完成；实际结果以用户运行 `update -t` 时的命令与复检输出为准。

安装依据：[Android 官方 sdkmanager 文档](https://developer.android.com/tools/sdkmanager)、[Homebrew android-commandlinetools cask](https://formulae.brew.sh/cask/android-commandlinetools)。当前兼容 Flutter 仍使用 sdkmanager 的许可入口；Google 已将 sdkmanager 标记为弃用，脚本通过版本检查和 doctor 复检确认它在当前工具链中的实际可用性。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
