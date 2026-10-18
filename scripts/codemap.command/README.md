# `codemap.command`：构建代码地图

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、运行方式](#usage)
- [二、执行前检查](#dependencies)
- [三、构建行为与产物](#build-behavior)
- [四、命令注册](#registration)
- [五、日志与排查](#logs-and-errors)
- [六、验证范围](#validation)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

`codemap` 调用 [**CodeGraph**](https://github.com/colbymchenry/codegraph) 为当前目录或指定目录构建 `.codegraph` 代码地图。支持手工输入路径、从 Finder 拖入路径，以及一次处理多个目录；每次先展示内置自述，按回车确认后才写入索引。

| 终端输入 | 执行结果 |
| --- | --- |
| `codemap` | 构建终端当前目录的地图 |
| `codemap .` | 显式构建当前目录 |
| `codemap "./项目 A"` | 构建含空格的相对目录 |
| `codemap 目录A 目录B` | 依次构建两个目录，最后汇总成功与失败 |
| 输入 `codemap ` 后拖入目录 | 由终端解析拖入路径后构建该目录 |

表中的示例目录需替换为实际项目。路径在调用者的当前目录下解析，不会切换到脚本目录后误索引其它项目。

## 一、<span id="usage">运行方式</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

通过仓库根目录的 [配置同步入口](../../install.command/README.md) 部署后，在终端运行：

```zsh
codemap
codemap "./项目目录"
codemap "./项目 A" "./项目 B"
```

也可以直接运行主脚本：

```zsh
/bin/zsh ./codemap.command "./项目目录"
```

含空格、中文、单引号或反斜杠的目录优先直接拖入终端，或按 Shell 规则引用路径。脚本先原样匹配真实目录；只有原样路径不存在时才处理拖入转义、外层引号和末尾回车。解析不使用 `eval`，不会把路径文字当成命令执行。多个目录作为多个参数传入。

首次展示自述后，按回车继续，按 `Ctrl+C` 取消。没有可交互标准输入时直接失败，不会跳过确认继续构建。

## 二、<span id="dependencies">执行前检查</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1、目标必须是存在、可读取并可写入的目录；文件、失效路径、文件系统根目录和用户主目录整体都会被拒绝。所有参数先统一校验，任一路径错误时不会提前构建其它目标。

2、已有 `.codegraph` 必须是目标内的普通目录，不能是文件或符号链接。软链接形式的项目路径会解析为真实目录，并按真实路径去重。

3、依次查找用户独立安装前缀、`PATH`、Apple Silicon / Intel 的常规安装位置及用户级安装位置。候选命令必须通过 `--version` 以及 `init`、`index`、`status` 接口检查，发现残缺安装时继续寻找其它健康候选。

4、使用 macOS 原生 `plutil` 解析官方 JSON 状态，不为读状态额外安装运行时。当前接口按 CodeGraph `1.6.2` 核验。

缺少健康 CodeGraph 时停止，并指向 [独立安装器](../../../../JobsCommand@iOS/配置相关/【MacOS】⚙️安装代码地图CodeGraph.command/README.md)。安装器负责先体检 [**Homebrew**](https://brew.sh/) 及实际依赖，再安装工具；`codemap` 不执行隐式安装、修复或升级。

## 三、<span id="build-behavior">构建行为与产物</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 目标状态 | 实际调用 |
| --- | --- |
| 尚无 `.codegraph` | `codegraph init --yes 目标目录` |
| 本目标已初始化 | `codegraph index 目标目录` |
| 只有空 `.codegraph` 或初始化失败残留 | 检查状态后执行 `codegraph init --yes 目标目录` |
| 构建结束 | `codegraph status --json 目标目录` |

输出位置固定为目标下的 `.codegraph`。已有目录先读取官方初始化状态；只有状态属于当前目标时才执行完整重建，不能把空目录或自动找到的父项目地图误认为本项目已初始化。源码内容不由本脚本改写。首次初始化会在 `.codegraph` 内创建索引及内部 `.gitignore`，不改项目根目录的 `.gitignore`、`AGENTS.md` 或 MCP 配置。

每次调用局部设置 `CODEGRAPH_DIR=.codegraph`、关闭遥测、禁止发行版 shim 自动下载平台组件及运行时编译缓存，并在构建时移除继承的 `CODEGRAPH_NO_WATCH`，避免 macOS 下首次初始化自动进入 Git hooks 回退安装；不修改用户的全局环境变量。缺少平台组件时应通过独立安装器修复。该构建入口不启动常驻监听服务。

只有官方 JSON 同时满足 `initialized=true`、项目路径与目标一致、索引位置为目标下的 `.codegraph`、`lastIndexed` 非空及 `index.state=complete`，且目录实际存在，才会报告构建成功。状态无法解析、子进程失败或产物不完整均算失败。多个目标中单个构建失败后仍处理其余目标，最终只要有失败就返回非零状态。

## 四、<span id="registration">命令注册</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

仓库配置同步入口会同步 `codemap.command` 脚本包，检查必需模块，并在用户的 `.local/bin` 注册 `codemap`。`entrypoints.command` 同时注册同名 Shell 函数，复用已部署脚本；`list` 功能菜单也提供“代码地图”入口。

注册模块被 `source` 时只定义入口，不做建图或阻塞确认；实际调用 `codemap` 时由主脚本统一确认。

## 五、<span id="logs-and-errors">日志与排查</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

日志写入系统临时目录中的 `codemap.log`，每次确认运行后重新初始化。终端和日志同步保留目标路径、实际命令、CodeGraph 输出、官方 JSON、失败原因及汇总；非彩色终端输出纯文本。

- 提示依赖不可用：运行[独立安装器](../../../../JobsCommand@iOS/配置相关/【MacOS】⚙️安装代码地图CodeGraph.command/README.md)，按健康体检结果修复。

- 提示路径不存在：确认拖入的是目录；手工输入含空格路径时使用引号；多个目录分别作为参数传入。

- 提示索引未完成：查看日志中的 CodeGraph 错误，排查目录权限和工具状态后重新运行同一个目标。

- 单个目标失败：其余目标仍会处理；终端退出码非零，不能把部分成功当成全部完成。

## 六、<span id="validation">验证范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

已通过 `zsh -n`，并使用隔离假命令验证当前目录、特殊字符路径、多个目标、空地图修复、父项目索引识别、失败退出及 JSON 完整性校验。已通过真实终端确认，用已安装的 CodeGraph `1.6.2` 在无 Git 的临时目录完成首次初始化和再次重建，识别到样例中的两个函数并通过完整状态校验；样例已清理，没有常驻进程。未对真实业务仓库构建地图，也未执行包管理器安装。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
