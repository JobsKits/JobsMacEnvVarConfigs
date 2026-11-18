# 构建安装面板

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、用途](#purpose)
- [二、运行](#run)
- [三、执行与恢复](#build-recovery)
- [四、源码与成品对账](#source-product-match)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本入口编译并打包自包含的原生管理 App。

## 一、<span id="purpose">用途</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

[【MacOS】构建安装面板.command](./【MacOS】构建安装面板.command) 编译上一级 `Sources/EnvironmentManager.swift`，读取 `Resources/BuildProfile.txt` 与十语翻译，打包项目当前后端和所需资源，生成同仓原生管理 App。完整功能见[面板说明](../README.md)。

## 二、<span id="run">运行</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

双击脚本先看内置自述，仅按回车开始构建，输入其它内容或 Ctrl+C 取消。明确的非交互调用：

```zsh
/bin/zsh ./【MacOS】构建安装面板.command --yes
```

| 参数 | 行为 |
| --- | --- |
| `--yes` | 明确授权构建产物，不授权环境安装或卸载 |
| `--native` | 只构建当前 CPU 架构；默认 Apple Silicon／Intel 通用版本 |
| `--output /目标路径.app` | 输出到用户明确指定的实际目录，拒绝符号链接和非自有同名 App |

## 三、<span id="build-recovery">执行与恢复</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

确认后检查本机 Swift 编译器、源码、翻译与仓内 `icon.png`，在目标同级私有暂存目录内装配资源、生成 ICNS、编译二进制、签名、验证并运行自测，成功后原子替换目标 App。首次缺少编译器时报告后停止；不会自动运行 `xcodebuild`、安装 SDK 或修改本机开发环境。

构建锁按目标目录和 Bundle 身份隔离。运行中的管理 App 拒绝替换；已有目标 Bundle 身份不匹配时拒绝覆盖。发布失败会尝试恢复上一份 App，恢复失败保留 `previous.app` 并明确其位置。正常退出只清理本轮确认归属的暂存和锁；异常留下的锁须确认没有构建进程后再人工处理。

日志使用系统临时目录中的独立 `JobsPanelBuild.*` 文件，终端实时显示相同内容。非 TTY、`NO_COLOR` 或未知终端保留纯文本；交互终端的临时配色按随脚本内嵌范本保护及恢复。运行不依赖本机 Skill 目录。

## 四、<span id="source-product-match">源码与成品对账</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

[环境配置管理 App](../../【MacOS】🌍环境配置管理.app)由本仓[面板源码](../Sources/EnvironmentManager.swift)和当前环境资源独立构建，不在运行时依赖父仓。签名前生成包内 `Contents/Resources/BuildReceipt.plist`，记录 `profile=env`、真实 UTC 构建时间及该源码的 SHA-256；同目录 `Payload.sha256` 覆盖构建收据、翻译、图标、配置和全部包内后端资源，并在发布前逐份复检。

在本 README 所在目录可核对当前默认产物：

```zsh
shasum -a 256 ../Sources/EnvironmentManager.swift
plutil -p '../../【MacOS】🌍环境配置管理.app/Contents/Resources/BuildReceipt.plist'
(cd '../../【MacOS】🌍环境配置管理.app/Contents/Resources' && shasum -a 256 -c Payload.sha256)
codesign --verify --deep --strict '../../【MacOS】🌍环境配置管理.app'
'../../【MacOS】🌍环境配置管理.app/Contents/MacOS/JobsEnvironmentManager' --self-test
```

使用 `--output` 时把上面的 App 路径改成实际目标。收据和资源清单用于核对成品关联与内容完整性；构建与自测不执行环境安装／卸载，也不代表另一台 Mac 或人工界面操作已验。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
