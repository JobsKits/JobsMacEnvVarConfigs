# JobsMacEnv 分项环境管理后端

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[【MacOS】环境管理后端.command](./【MacOS】环境管理后端.command) 为[安装面板](../安装面板/README.md)及[终端卸载入口](../【MacOS】卸载终端环境.command/README.md)提供同一套分项安装、收据和恢复流程。使用系统 [**zsh**](https://www.zsh.org/)、文件工具与校验工具，不要求额外安装解释器，不运行被部署命令的业务。

原[终端完整同步入口](../【MacOS】install.command/README.md)继续保留，其交互与安装方式独立。两个入口不要同时运行；新后端的锁只约束新后端，发布前的文件指纹复检用于发现外部修改。

## 一、组件与来源 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 组件 | 内容 |
| --- | --- |
| `env-core` | 从 `sync_env.txt` 生成环境变量、PATH、别名；部署基础方法、启动层和轻量 `.zshrc` 模板 |
| `shell-behavior` | 交互式启动目录、Git 行为、路径拖入处理 |
| `user-mounts` | 按序加载自定义模块 |
| `local-custom` | 加载运行时初始化与短命令函数 |
| `shell-entry` | 将受控加载块追加到用户 `.zshrc`，保留原有正文和末尾字节；已有完整 Jobs 入口不重复加载 |
| `runtime-support` | `entrypoints`、`runtime_init`、Flutter 路由、JDK 辅助与 `_lib` |
| `cmd-*` | 按命令独立部署完整脚本包和短命令转发器；包含录屏原生源码、Chrome 扩展等相邻资源 |
| `cmd-gemrepair` | 部署 Gem 原生扩展修复器，终端短命令为 `repair_gem_extensions` |
| `cmd-markdown-toc` | 部署全局 Markdown 目录过滤器管理器，终端短命令为 `jmarkdown-toc`；不自动配置 Git |
| `cmd-to` | 同时注册 `to` 和各媒体格式入口，格式名作为参数传给同一脚本 |
| `cmd-orc` | 部署 [**Indra OCR**](https://pypi.org/project/indra-ocr/) 完整包及终端入口；全部大小写函数统一调用，依赖与模型由业务入口按需准备 |

2026-11-16 源码后端的真实 `--catalog` 为 **50 个可选组件**，口径为六个配置／支持组件和 44 个独立命令组件，包含 [Indra OCR](../scripts/【MacOS】orc.command/README.md) 的 `cmd-orc`。现有 App 未重新打包，包内仍为 49 项、不含此命令；目录查询是各入口的实时依据，不要求面板写死数量。选中命令时自动补齐基础环境、公共支持、模块和命令函数加载器、Shell 入口；不自动安装 [**Homebrew**](https://brew.sh/)、JDK、SDK、模型或业务依赖。

所有来源从后端包的上一层定位：`../sync_env.txt`、`../scripts/`、`../zsh/`、`../Sys/`。复制或移动时保留这些目录与后端包的相对结构；安装面板的 App Bundle 带有独立资源副本。

## 二、运行方式与协议 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本 README 所在目录执行：

```shell
/bin/zsh ./【MacOS】环境管理后端.command --catalog
/bin/zsh ./【MacOS】环境管理后端.command --install cmd-cor cmd-jrecord --dry-run
/bin/zsh ./【MacOS】环境管理后端.command --install cmd-cor cmd-jrecord --yes
/bin/zsh ./【MacOS】环境管理后端.command --uninstall cmd-cor cmd-jrecord --dry-run
/bin/zsh ./【MacOS】环境管理后端.command --uninstall cmd-cor cmd-jrecord --yes
/bin/zsh ./【MacOS】环境管理后端.command --uninstall all --yes
```

- `--catalog`／`--status`：无表头的 UTF-8 TSV，四列依次是 `id`、名称、说明、状态。只读，不写用户配置、状态或日志。
- `--install`／`--uninstall`：至少选择一个有效 ID；`all` 展开全部当前组件，混入未知 ID 仍拒绝执行。
- `--dry-run`：只生成计划，不写配置、收据和日志，不下载、不执行安装业务。
- `--yes`：真实操作的显式授权；开关可放在组件列表前后，不根据无 TTY 自动放行。
- 真实操作的标准输出包含纯文本进度和 `JOBS_MANAGER_EVENT` 事件；事件用制表符分隔，依次是固定前缀、组件 ID、`running`／`success`／`failed`、说明。目录查询没有事件。

状态 `yes` 表示完整收据和当前文件指纹一致；`no` 表示未发现该组件；`unknown` 表示历史无收据安装、用户后来修改、残缺收据或其它需核查状态，不能视为成功安装或成功卸载。

退出码：`0` 为完成，`1` 为文件／依赖／执行失败，`2` 为参数或缺少授权，`3` 为用户修改、未知归属、共享引用或恢复冲突，`4` 为存在独占锁。HUP／INT／TERM 分别以 `129`／`130`／`143` 结束；强制终止后保留收据和备份供核查，不自动删除未知锁。

## 三、安装与反安装边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

安装前精确备份每个将覆盖的普通文件，保存原始和安装后指纹。发布前重新检查目标，发现计划后的变化即停止。新创建文件与原有文件分开记录；重复安装继续使用最初的原件，不把已部署版本当成原点。

卸载顺序与依赖相反：先停用 Shell 入口，再撤回选中命令，最后恢复公共模块。每个组件先核对全部文件；用户后来修改或备份异常时保留整个组件，返回未完成。未选命令、未完成撤回的命令、无收据但仍引用环境的自定义脚本都会阻止删除共享支持。仅卸载 `shell-entry` 时命令包仍保留，新终端不再自动加载相应函数；需要的可执行入口仍位于用户本地命令目录。

历史终端安装没有新后端收据，不能凭空恢复原 `.zshrc` 或删除整片环境。再次通过面板安装时会备份当前历史状态；此后的反安装恢复到这次面板安装之前，不能等同于移除更早的历史安装。符号链接、目录替身、后续修改、未知归属和共享引用均保留并报告。

收据、原件备份、历史恢复材料和纯文本日志放在用户资源库 `Application Support` 的 `JobsMacEnvManager` 中，分别为 `receipts/`、`history/`、`logs/`。卸载后保留这些审计与恢复材料及空目录；不清除用户数据、SDK、模型、缓存、其它应用配置或全局代理。

本流程是逐文件核验、可重试的恢复协议，不承诺整个多组件批次在断电或外部并发修改下具备原子性。不要与原终端安装器同时运行。

## 四、验证与目录 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
【MacOS】环境管理后端.command/
├── 【MacOS】环境管理后端.command
├── README.md
└── Tests/
    ├── README.md
    └── 【MacOS】环境后端回归.zsh/
        ├── 【MacOS】环境后端回归.zsh
        └── README.md
```

[隔离回归](./Tests/【MacOS】环境后端回归.zsh/README.md)只在全新临时 HOME 与复制后的源码中执行文件生命周期，覆盖目录、参数、选择依赖、完整组件、原件／权限恢复、用户修改、历史无收据对象、共享引用、源码迁移和计划后并发变化。测试不运行部署后的业务命令，不代表已在当前用户环境安装、卸载或逐项实用各工具；图形界面与真实终端按键另行验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
