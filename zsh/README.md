# zsh 环境与交互模块

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、加载顺序与功能](#jobs-toc-heading-2)
- [二、custom 交互能力](#jobs-toc-heading-3)
- [三、运行边界与排查](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录将终端启动、环境工具、别名与交互操作分开管理，由[用户入口模板](../Sys/.zshrc) source。源码配置通过[环境安装器](../install.command/README.md)部署到用户环境，不是逐个双击运行的程序。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、加载顺序与功能 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 顺序 / 文件 | 当前功能 |
| --- | --- |
| 1、[bootstrap.zsh](./bootstrap.zsh) | 仅交互 Shell 加载已有 Oh My Zsh，并发现健康 Homebrew、载入 `shellenv`；不隐式安装工具 |
| 2、[env_methods.zsh](./env_methods.zsh) | 提供 PATH 去重、架构 / Homebrew / Java 路径解析、工具初始化与环境加载辅助函数 |
| 3、运行目录的 `env.zsh` | 安装器依据 [sync_env.txt](../sync_env.txt) 生成的环境声明；不把生成文件当作源码模板修改 |
| 4、[aliases.zsh](./aliases.zsh) | 别名配置位置；源码文件保留说明，部署结果由安装流程生成 |
| 5、[user_mounts.zsh](./user_mounts.zsh) | 依次载入 `custom/` 下的 Shell、Git、拖入路径及本地命令模块 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、custom 交互能力 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 操作与默认值 |
| --- | --- |
| [shell_behavior.zsh](./custom/shell_behavior.zsh) | 仅交互终端进入桌面，并加载用户环境中的 `clean` 命令定义 |
| [git_behavior.zsh](./custom/git_behavior.zsh) | 挂载进程内 Git 网络入口、补足 UTF-8 字符环境，并通过每次调用的 `core.quotepath=false` 显示中文路径；`JOBS_GIT_QUOTEPATH_FIX=false` 可关闭路径包装，不写永久 Git 配置 |
| [path_drag_resolver.zsh](./custom/path_drag_resolver.zsh) | 默认 `Ctrl-G` 解析命令行最后一个拖入路径，支持 Finder 替身与软链接；自动解析粘贴默认关闭，可用 `JOBS_ALIAS_DRAG_AUTO_RESOLVE=true` 启用；GIF 录制会话不绑定此键 |
| [local.zsh](./custom/local.zsh) | 定位用户环境的 `Scripts/`，加载 `runtime_init.command` 和 `entrypoints.command`；缺失时输出具体路径和同步提示 |

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、运行边界与排查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

修改声明后使用环境安装器同步，再重新打开终端。命令业务在 [scripts/](../scripts/README.md)，Git 动态网络策略的触发条件、进程作用域与日志见[独立说明](../scripts/_lib/jobs_git_network_strategy/README.md)。source 会改变当前 Shell 环境，路径和命令覆盖应在当前终端核对；缺模块先查用户运行副本是否完整，不用复制单个加载器代替完整部署。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
