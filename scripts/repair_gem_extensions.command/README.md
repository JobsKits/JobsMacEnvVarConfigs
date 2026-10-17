# `repair_gem_extensions.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

使用当前 [**CocoaPods**](https://cocoapods.org/) 对应的 [**Ruby**](https://www.ruby-lang.org/) 重新构建缺失的 [**Gem**](https://rubygems.org/) 原生扩展，处理 `Ignoring ... because its extensions are not built`。默认只扫描，明确传入 `--repair` 才会修改已安装扩展；Ruby 和 Gem 版本保持原状。

从本 README 所在目录执行：

```zsh
/bin/zsh ./repair_gem_extensions.command \
  --check \
  -t
```

确认扫描目标后，明确修复：

```zsh
/bin/zsh ./repair_gem_extensions.command \
  --repair \
  -t
```

| 本机实际状态 | 修复行为 | 2026-10-17 本机验证 |
| --- | --- | --- |
| 旧扩展位于 `arm64-darwin-25/4.0.0`，当前 Ruby 需要 `arm64-darwin-27/4.0.0` | 使用当前 Ruby 编译本机已有源码，生成当前平台扩展 | 25 个已安装版本全部重建并逐版实际加载 |
| `pod --version` 输出 75 条 `Ignoring` | 重建后重新执行原命令 | 0 条警告，正常输出 `1.17.0` |
| Ruby 已为 `4.0.7` | 复用该运行时 | 版本仍为 `4.0.7` |
| 修复完成后再次运行 `--repair -t` | 缺失数为 0 时直接结束 | 未重复编译；144 个旧平台文件及 gemspec 指纹保持一致 |

平台名称由运行时读取，不写死 `darwin-27`。旧平台目录继续保留，不通过目录改名或复制完成标记替代重编译。以上结果仅对应本机验证。

## 一、运行方式与交互 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 参数 | 行为 |
| --- | --- |
| 无参数 / `--check` | 默认检查，列出当前运行时缺失扩展的已安装版本；不构建、不备份、不修改 Gem |
| `--repair` | 检查后仅修复缺失项，健康项跳过 |
| `-t` / `--unattended` | 显示内置自述后免交互执行；不会自动把检查切换为修复 |
| `-h` / `--help` | 显示用法并退出 |

普通终端或双击入口先显示内置自述，按回车继续阅读确认，输入其它内容取消。随后操作确认中，直接回车跳过，输入任意字符后回车执行。随时可用 `Ctrl+C` 取消；没有终端交互条件时须明确传入 `-t`。

`--check` 对 Gem 目录只读，仍会在确认执行后初始化本次日志。扫描完成即返回 `0`，是否缺失以输出数量为准；`--repair` 只有全部目标通过验证且复检缺失数为 `0` 才返回 `0`，构建或检查失败返回非零。

日常入口 [update.command](../update.command/README.md#gem-native-extensions) 在 Ruby / RubyGems 更新项中内嵌同一实现。独立脚本可单文件复制运行，不依赖 README 或外置函数库。

## 二、运行时与执行前检查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

默认优先解析活跃 `pod` 的脚本及 [**Homebrew**](https://brew.sh/) 包装层，选择其 Ruby；无法解析时依次检查 PATH 中的 Ruby、现有标准 Homebrew Ruby 路径。不调用 Homebrew 安装或升级命令。

| 配置 | 默认值 / 用途 |
| --- | --- |
| `JOBS_GEMEXT_RUBY` | 可指定现有 Ruby 可执行文件，作为首选候选；不设置时按上述顺序发现 |
| `JOBS_GEMEXT_BACKUP_ROOT` | 默认 `~/.JobsMacEnv/backups/gem-native-extensions`；可指定备份根目录 |

只扫描选定 Ruby 实际 Gem 搜索路径中非默认、声明了原生扩展且被 RubyGems 判定缺失的版本。已有健康扩展、默认 Gem 和纯 Ruby Gem 不进入修复。

只有发现待修项后，才检查 Ruby 头文件、`make` 和 [**Xcode**](https://developer.apple.com/xcode) / Command Line Tools 的 `clang`。每个目标还须具备本机 `extconf.rb` 源码、可写的 Gem 和扩展目录；符号链接目标或不支持的构建入口会明确报错。脚本不自动安装工具链、下载源码或提权补权限。

## 三、备份、构建与失败恢复 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 阶段 | 实际行为 |
| --- | --- |
| 检查 | 读取当前 Ruby、平台和缺失目标；没有缺失项时不编译、不写备份 |
| 加锁 | 修复进程取得备份根目录的锁后重新检查，避免同一路径并发修复 |
| 备份 | 每个 Gem 保存完整源目录、当前平台原有扩展、原始 gemspec 和路径清单 |
| 构建 | 通过 RubyGems 构建接口，使用本机已有源码重编译原版本 |
| 验证 | 检查当前平台完成标记及 gemspec 未变；新 Ruby 进程精确激活原版本，并确认原生二进制实际加载 |
| 失败 | 恢复该目标的源目录及原有当前平台扩展，保留失败构建和日志；其它已成功目标保留 |
| 复检 | 重新统计缺失项并汇总成功、失败和剩余数量 |

修复会覆盖目标 Gem 源目录内的构建产物，以及当前平台扩展目录。备份位于用户目录中的 `~/.JobsMacEnv/backups/gem-native-extensions`，每个目标有独立子目录，终端会打印完整位置；`result.txt` 标记该目标结果。自动恢复失败时明确报错并打印完整备份位置，停止后续修复。

修复本身不进行网络安装、不新增 Gem、不调用 `sudo`、不升级 Ruby，不删除旧平台目录。没有本机源码、工具链或写权限时，应先处理日志列出的阻塞项，再重新运行；已成功目标下次自动跳过。

## 四、日志与常见问题 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

终端结果同步写入系统临时目录的 `repair_gem_extensions.log`，即 `$TMPDIR/repair_gem_extensions.log`；`TMPDIR` 未设置时使用 `/tmp`。每次确认执行后重新初始化日志；备份和失败材料保留在各目标目录。

| 现象 | 说明 / 处理 |
| --- | --- |
| 缺失数为 `0` | 当前选定运行时没有待修目标；健康环境直接结束 |
| Ruby 与终端 `ruby --version` 不同 | 默认优先使用活跃 `pod` 绑定的 Ruby，核对脚本首行输出的运行时路径 |
| 构建失败 | 查看日志中的具体 Gem、编译错误和备份位置；该目标会尝试恢复原目录 |
| 加载验证失败 | 不能仅凭完成标记判定成功；脚本会恢复该目标并保留失败材料 |
| 已修复扩展但 `pod install` 仍下载超时 | 扩展加载与源码下载属于不同问题；继续检查实际失败 URL 的网络链路 |

## 五、隔离回归 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

从本目录执行：

```zsh
/usr/bin/ruby ./Tests/native_extensions_test.rb
/bin/zsh ./Tests/update_integration_test.zsh
```

隔离测试使用临时目录与替身对象验证目标筛选、健康跳过、构建失败恢复、实际加载校验及更新入口衔接，不重建系统 Gem。真实运行验收见前言中的本机结果。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
