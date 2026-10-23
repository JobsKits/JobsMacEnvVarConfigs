# 全局 Markdown 目录过滤器

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行方式](#usage)
- [二、配置与部署](#configuration)
- [三、下载流程中的选择](#optional-flow)
- [四、验证与撤回](#validation)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本功能统一维护在 JobsMacEnvVarConfigs，每台电脑安装一次 [**Git**](https://git-scm.com/docs/gitattributes#_filter) 全局过滤器。已登记文档本地保留 `[toc]`，整文件暂存时生成缩进、默认收起的折叠目录，检出时自动还原。每个仓库仍通过精确 `.gitattributes` 选择文件，不把所有 Markdown 文档自动纳入。

| 入口 | 行为 |
| --- | --- |
| 双击同目录的配置脚本 | 只安装或复检全局驱动，不推断或遍历父仓。 |
| JobsGenesis 下载入口的附加提示 | 先完成代码拉取与向下递归；回车才安装并恢复该目标仓库，输入任意字符后回车跳过。 |
| 附加配置缺依赖、缺文件或失败 | 保留已完成的拉取结果，稍后可独立运行配置。 |

## 一、<span id="usage">运行方式</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

需要 Git 和 [**Node.js**](https://nodejs.org/) 20 或更新版本；不自动联网安装依赖。以下命令在本目录执行，目标路径需替换为实际仓库根目录：

```shell
/bin/zsh ./【MacOS】⚙️配置全局Markdown目录过滤器.command
node ./GlobalMarkdownToc.mjs status
node ./GlobalMarkdownToc.mjs setup "目标仓库根目录"
node ./GlobalMarkdownToc.mjs restore-tree "目标仓库根目录"
node ./GlobalMarkdownToc.mjs uninstall
```

| 命令 | 范围 |
| --- | --- |
| `install`（双击默认） | 安装或更新本机全局驱动，重复执行不会重复登记。 |
| `status` | 显示全局配置、机器转换副本及安装记录状态。 |
| `setup <仓库根目录>` | 安装全局驱动，再恢复该仓及已初始化子模块并逐仓验证。 |
| `restore-tree <仓库根目录>` | 只恢复指定仓库树的受控文档；保留正文、暂存内容和用户 flags。 |
| `uninstall` | 撤回本工具登记的全局字段；保留机器副本、工作文件和仓内配置。 |

`setup` / `restore-tree` 必须显式指定根目录，缺少路径或传入仓库子目录时停止，不自动向上查找并恢复其它仓库。未完成 Git 操作、损坏目录标记、清单缺失或属性冲突会停止恢复，已完成仓库不会回滚。

## 二、<span id="configuration">配置与部署</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

安装只维护用户级 `filter.jobs-markdown-toc.clean`、`smudge`、`required` 三项。转换副本和安装记录放在用户目录下 `.local/share/jobs-markdown-toc`；驱动使用 Node 与副本的绝对路径，首次检出不执行新下载仓库中的脚本，移动源码仓库不影响转换。优先使用稳定的 Node 可执行路径，更换 Node 安装位置后重新运行配置入口。

本脚本包包含入口、`GlobalMarkdownToc.mjs`、自包含的 `MarkdownToc.mjs` 转换副本及测试。环境配置安装器按现有规则将整个包复制到运行目录的大写 `Scripts/`；运行副本不依赖源仓库或上层 `.jobs-markdown-toc/`。复制脚本包只部署文件，不自动安装 Git 过滤器。

已有同名全局配置但无本工具安装记录时不覆盖；安装记录中的字段被其它操作更改时停止并报告。已有仓内 local 驱动优先级更高，需结合目标仓库的 `MarkdownToc.mjs status` 核对有效来源。

普通 `git clone` / `git pull` 不会执行安装脚本或给新电脑写配置；每台电脑需运行独立入口，或在下载后的附加提示中按回车安装一次。`fetch` 或无更新的 `pull` 不会重写已有文件，需要时用带明确目标的恢复命令。

## 三、<span id="optional-flow">下载流程中的选择</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

附加提示与拉代码的确认相互独立，只在递归拉取成功后出现。直接回车才执行 `setup`；任意非空输入（包括空格）后回车跳过，输入结束也跳过。缺少本包、Node.js 不可用或配置失败只显示附加结果，不改变已完成拉取的成功退出码。拉取失败保留原失败状态，不进入附加配置；演练模式不询问、不安装。

## 四、<span id="validation">验证与撤回</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
node --test ./GlobalMarkdownToc.Tests.mjs
```

测试使用隔离的 Git 全局配置与临时仓库，覆盖首次克隆、暂存生成、部分暂存保留、子模块恢复、重复安装、卸载与重装、冲突保护、复制后的独立脚本包和显式目标校验。隔离转换目录使用绝对路径环境变量 `JOBS_MARKDOWN_TOC_HOME`。下载入口的可选交互测试位于 JobsGenesis 的 `.jobs-markdown-toc/DownloadMarkdownToc.Tests.mjs`。

操作结果与错误显示在终端；安装恢复记录是机器副本旁的 `installation.json`。卸载不会遍历任意仓库改写文档，没有仓内驱动兜底时，现有 `[toc]` 将不再转换；需要继续编辑时重新安装。不暂存、不提交、不推送，不更改 hooks。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
