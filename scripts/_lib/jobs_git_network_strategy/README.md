# Git 推送网络策略

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、行为速览](#behavior)
- [二、文件职责](#layout)
- [三、代理回退流程与边界](#fallback)
- [四、部署与普通推送入口](#setup)
- [五、日志与备份](#logs)
- [六、恢复原状与临时旁路](#restore)
- [七、隔离验证与验收范围](#validation)

</details>
<!-- jobs-toc:end -->

[行为速览](#behavior) · [接入方式](#setup) · [日志](#logs) · [恢复原状](#restore) · [验证](#validation)

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

> 为终端 `git push` 和 [**Sourcetree**](https://www.sourcetreeapp.com/) 普通推送按钮提供同一套 [**Git**](https://git-scm.com/) 网络策略：先正常推送，遇到符合条件的连接故障后，再读取当前系统代理探测并重试一次。代理地址随当前系统设置读取，不固定端口，也不持久写入 `http.proxy`。

## 一、<span id="behavior">行为速览</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 情况 | 实际处理 |
| --- | --- |
| 普通 HTTP / HTTPS 推送成功 | 保留原结果，不读取系统代理，不额外探测。 |
| DNS / 连接失败或超时，且尚无传输 / 远端进度 | 读取当前系统代理；探测首个可用候选后重试一次。 |
| 已设置 Git 或环境变量代理，包括显式空值 | 尊重已有选择，不自动换成系统代理。 |
| 命中 `NO_PROXY` / `no_proxy` 或系统旁路规则 | 保持旁路，不强制代理。 |
| 认证、权限、非快进拒绝、分支冲突、证书错误 | 保留原错误，不触发代理重试。 |
| 已出现传输 / 远端进度，或首轮标准输出非空 | 保留原结果，避免重复提交不明确的远端操作。 |
| SSH、本地路径，或 `status` / `fetch` / `pull` 等其它命令 | 交给原生 Git 执行，不进入 HTTP 推送回退。 |

首次推送沿用 Git 与既有配置的超时，可能先等待几十秒或更久；短超时只用于失败后的代理探测。探测成功仅说明目标站点可达，实际凭据、仓库权限及推送结果仍由 Git 校验。

## 二、<span id="layout">文件职责</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
jobs_git_network_strategy/
├── README.md            # 使用、边界与恢复说明
├── bin/git              # Git 命令入口，内部固定调用 /usr/bin/git
├── rollback.command     # 恢复本次挂载和 Sourcetree Git 选择
└── tests/
    ├── run.zsh          # 临时仓库与受控网络的隔离回归
    └── http_fixture.pl  # 仅监听回环地址的 HTTP 推送测试夹具
```

源码位于仓库的 `scripts/_lib/`，部署后位于用户环境的 `Scripts/_lib/`。Git 的 [`http.proxy`](https://git-scm.com/docs/git-config#Documentation/git-config.txt-httpproxy) 配置用于指定代理；本模块用独立命令入口实现“推送失败后读取系统代理再试”的流程。入口固定执行 `/usr/bin/git`，避免经 `PATH` 再次调用自己形成递归。

终端现有的中文路径修正函数仍由 `zsh/custom/git_behavior.zsh` 维护；该文件只增加网络策略入口的 `PATH` 挂载，不复制推送处理代码。Sourcetree 直接使用相同的 `bin/git`，不依赖交互式终端函数。

## 三、<span id="fallback">代理回退流程与边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 原样执行普通推送，保留参数、标准输出、错误输出和退出状态。
- 仅原推送发生明确的 DNS / 连接故障，且尚未出现传输 / 远端进度时，检查是否允许回退。
  - 显式代理和旁路设置优先；非 HTTP / HTTPS 目标、结果不明确及其它类型错误直接保留原结果。
- 通过 [**macOS**](https://www.apple.com/macos/) 的 `scutil --proxy` 读取当前已启用的 HTTPS、HTTP、SOCKS 代理，并按此顺序去重形成候选。
  - 同时遵守 `ExceptionsList` 和 `ExcludeSimpleHostnames`，不绕过已有 `NO_PROXY` / `no_proxy`；系统例外支持域名、通配与 IPv4 CIDR，IPv6 CIDR 无法精确判断时保守保持旁路。
- 使用 [**curl**](https://curl.se/docs/manpage.html) 对目标站点根地址发起无凭据 HEAD 探测，每个候选连接超时 3 秒、总超时 6 秒，最多三个候选。
  - 取首个可达候选，不继续探测其它候选；探测不携带 Git 凭据，不证明仓库可写。
  - 无可用候选时返回原推送的失败结果，不循环重试。
- 将选中的代理仅注入本次 Git 子进程，按原参数重试一次；最终返回这次重试的退出状态。

模块不修改操作系统代理、Shell 启动环境中的代理变量、全局 Git 代理或仓库配置。关闭代理软件或更改系统代理后，下一次符合条件的回退会重新读取；无需修改脚本中的固定地址。

## 四、<span id="setup">部署与普通推送入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本仓根目录运行[配置同步入口](../../../install.command/install.command)，按入口说明完成同步；它负责把 `_lib/` 和 `git_behavior.zsh` 部署到用户环境：

```zsh
./install.command/install.command
```

重新打开终端或重新载入配置后，终端继续直接使用普通命令：

```zsh
source "$HOME/.zshrc"
git push
```

在 Sourcetree 设置的 Git 页面选择系统 Git，将可执行文件位置设为当前用户的 `.JobsMacEnv/Scripts/_lib/jobs_git_network_strategy/bin/git`；该位置对应终端中的：

```zsh
printf '%s\n' "$HOME/.JobsMacEnv/Scripts/_lib/jobs_git_network_strategy/bin/git"
```

保存后重新启动 Sourcetree，使用原有普通推送按钮。其它 Git 操作继续透传给 `/usr/bin/git`；项目远端、分支、提交和凭据保持 Git 原有管理方式。

`scripts/install.command` 和 `scripts/update.command` 中的仓库拉取步骤不等同于部署：取得新版源码后，仍须运行仓库根目录的配置同步入口。已有终端的中文路径修正开关 `JOBS_GIT_QUOTEPATH_FIX` 只控制路径显示，不承担网络策略开关。

## 五、<span id="logs">日志与备份</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 推送策略审计保存在用户 `Library/Logs/JobsGitNetworkStrategy/` 下的 `push.log`，权限为 `0600`；只记录 UTC 时间、模式、主机、端口和退出码，不记录完整参数、凭据或 Git 输出。
- 本次接入备份保存在用户 `Library/Application Support/JobsGitNetworkStrategy/` 下以日期和随机值区分的目录，安装 / 恢复审计为同目录 `audit.log`。
- 恢复入口依据运行包内的本次备份指向读取快照；保留运行包及备份，便于准确识别本次挂载，避免误删后续修改。

## 六、<span id="restore">恢复原状与临时旁路</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

先运行只读检查，无须交互，也不会变更配置：

```zsh
/bin/zsh "$HOME/.JobsMacEnv/Scripts/_lib/jobs_git_network_strategy/rollback.command" \
  --check
```

恢复前先正常退出 Sourcetree，避免应用退出时用缓存覆盖恢复结果；恢复入口不会自动结束正在执行的任务。执行后阅读作用范围并回车确认：

```zsh
/bin/zsh "$HOME/.JobsMacEnv/Scripts/_lib/jobs_git_network_strategy/rollback.command"
```

恢复只撤回本次写入的源码 / 运行态 `git_behavior.zsh` 挂载块，并在 Sourcetree 的 Git 路径和选择仍与本次部署值一致时，恢复这两个设置的原未设置状态；发现后续修改则保留并报告冲突。已有中文路径修正函数、其它设置、模块文件、备份和日志保留。恢复后重新打开终端和 Sourcetree。

需要单次直接使用系统 Git 时，可显式调用原生入口；这不会修改持久设置：

```zsh
/usr/bin/git push
```

## 七、<span id="validation">隔离验证与验收范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本模块目录执行随包回归：

```zsh
/bin/zsh ./tests/run.zsh
```

回归覆盖命令透传、首轮成功、网络故障回退、原结果保留、候选选择、显式代理、旁路、认证 / 权限 / 分支 / 证书拒绝及禁止重复重试等路径。临时本地仓库和受控网络用例用于验证策略与 Git 传输衔接；通过这些检查不代表真实公网仓库已完成推送，生产推送结果须由普通命令或 Sourcetree 实际输出确认。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
