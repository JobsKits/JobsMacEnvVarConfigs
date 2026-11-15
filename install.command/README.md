# `install.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、适用场景](#jobs-toc-heading-2)
- [二、目录结构](#jobs-toc-heading-3)
- [三、执行前检查](#jobs-toc-heading-4)
- [四、运行方式](#jobs-toc-heading-5)
  - [4.1、双击运行](#jobs-toc-heading-6)
  - [4.2、终端运行](#jobs-toc-heading-7)
- [五、操作流程](#jobs-toc-heading-8)
- [六、风险说明](#jobs-toc-heading-9)
- [七、日志文件](#jobs-toc-heading-10)
- [八、常见问题](#jobs-toc-heading-11)
  - [8.1、提示命令不存在](#jobs-toc-heading-12)
  - [8.2、提示权限不足](#jobs-toc-heading-13)
  - [8.3、双击后没有继续执行](#jobs-toc-heading-14)
- [九、未执行声明](#jobs-toc-heading-15)

</details>
<!-- jobs-toc:end -->

---

> 环境自检函数封装在每个实际业务脚本内部；包含原生源码或资源的命令须保留完整功能包，短命令转发到包内入口。此配置部署入口保留既有配置同步职责。

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

`install.command` 用于执行“install”对应的 MacOS 自动化流程。主脚本与本 `README.md` 必须保持在同一目录，运行前先阅读影响范围。

配置同步会将 [codemap.command](../scripts/codemap.command/README.md) 部署到用户的 JobsMacEnv 脚本目录，同时注册 `codemap` 函数和终端命令。`codemap` 用于构建当前目录或指定目录的 [**CodeGraph**](https://github.com/colbymchenry/codegraph) 地图；配置同步只部署命令，不隐式安装 CodeGraph 引擎。

配置同步同时部署[文件拆分](../scripts/【MacOS】split.command/README.md)与[分卷合并](../scripts/【MacOS】merge.command/README.md)，注册 `jsplit` / `jmerge` 函数、独立终端命令和 `list` 菜单入口，不覆盖系统 `split`。运行两个功能时，每次手动输入或拖入目标，无效目录或没有可处理文件会持续重问；执行确认默认取消，源文件和分卷默认保留。同步入口只复制和注册工具，不自动拆分或合并文件，也不代替工具自身的依赖检查。

配置同步还会完整复制[窗口录屏包](../scripts/jrecord.command/README.md)，注册 `jrecord` 函数、`list` 菜单和 `~/.local/bin/jrecord` 转发器。转发器运行时按 `JOBS_MAC_ENV_HOME_OVERRIDE`、`JOBS_MAC_ENV_HOME` 或默认用户环境目录定位包内入口，保留相邻 `Core/` 原生 [**Swift**](https://www.swift.org/) 源码，不将业务入口裸复制到 `bin/`。录屏工具首次使用时才体检、按需修复依赖及编译；环境同步本身不安装录屏依赖、不编译、不申请录屏权限，也不开始录制。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、适用场景 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 需要执行“install”所描述的本机开发或维护任务。
- 希望通过可重复运行的 Shell 脚本减少手工命令遗漏。
- 需要结合终端日志定位环境、路径或第三方工具问题。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、目录结构 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```text
install.command/
├── install.command
└── README.md
```

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、执行前检查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 确认当前系统为 MacOS，并已安装脚本实际调用的工具。
- 确认脚本路径、工程目录、输入文件和当前 Git 工作区正确。
- 打开主脚本检查其中的业务命令，不理解的操作不要直接执行。
- 涉及安装、更新或升级时，以脚本终端提示为准；直接回车应表示跳过。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

### <span id="jobs-toc-heading-6" data-jobs-toc="v2">4.1、双击运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在 Finder 中打开当前目录并双击 `install.command`。阅读终端自述后按回车继续，按 `Ctrl+C` 取消。

### <span id="jobs-toc-heading-7" data-jobs-toc="v2">4.2、终端运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```shell
cd "脚本所在目录/install.command"
./install.command
```

## <span id="jobs-toc-heading-8" data-jobs-toc="v2">五、操作流程 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1. 展示脚本自述或同目录 `README.md`。
2. 检查运行环境、输入参数和目标路径。
3. 按脚本提示确认需要执行的业务步骤。
4. 输出执行结果、失败原因和日志位置。

## <span id="jobs-toc-heading-9" data-jobs-toc="v2">六、风险说明 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 脚本包含删除、清理或重置动作，执行前必须确认目标路径和影响范围。
- 脚本可能修改文件权限或 MacOS 安全属性。
- 脚本可能访问网络、下载文件或更新本机工具链。
- 脚本会调用 Flutter / Dart 工具链，运行前应确认工程根目录和 SDK 版本。

危险操作必须以脚本中的 `YES` 确认为准；如果脚本尚未提供明确确认，应先审查脚本内容，不要盲目执行。

## <span id="jobs-toc-heading-10" data-jobs-toc="v2">七、日志文件 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

Jobs 标准脚本日志默认写入：

```text
$TMPDIR/install.log
```

如果脚本内部另有 `LOG_FILE` 定义，以主脚本实际配置为准。

## <span id="jobs-toc-heading-11" data-jobs-toc="v2">八、常见问题 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

### <span id="jobs-toc-heading-12" data-jobs-toc="v2">8.1、提示命令不存在 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

根据终端错误确认缺少的工具，先完成安装并保证命令已经加入 `PATH`。

### <span id="jobs-toc-heading-13" data-jobs-toc="v2">8.2、提示权限不足 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

检查目标文件权限和目录归属。只有确认命令及目标路径安全后，才按提示使用管理员权限。

### <span id="jobs-toc-heading-14" data-jobs-toc="v2">8.3、双击后没有继续执行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

查看终端是否正在等待阅读确认或业务输入；不确定时按 `Ctrl+C` 退出后重新检查脚本。

## <span id="jobs-toc-heading-15" data-jobs-toc="v2">九、未执行声明 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

README 只描述脚本职责和通用风险，不代表已经在当前 MacOS 环境执行真实业务命令。交付前应至少通过对应 Shell 的静态语法检查。

[**Homebrew**](https://brew.sh/) 安装路径由用户选择：已有可运行安装时复用；确实需要安装时先强提示，只有精确输入大写 `YES` 才选择系统标准目录，其它输入或直接回车选择当前用户的 `.local/homebrew`。`YES` 只表示选择路径，权限与密码由官方安装器实际处理；有管理员权限也可以选用户目录。选定路径失败立即停止，不自动切换；`Ctrl+C` / 输入结束取消整个任务。

**终端配色保护：** 独立运行时，在支持完整保存与恢复配色的交互终端中临时使用黑底白字及统一强调色；正常结束、失败或可捕获中断后恢复进入前的配色，不修改终端全局偏好或 Shell 启动配置。不支持完整保护、无交互终端、`NO_COLOR`、既有纯文本模式和 Sourcetree 场景不切换配色，并沿用纯文本输出约定。强制终止（如 `kill -9`）无法由脚本自身保证恢复，请使用运行时显示的独立恢复入口。

配色查询每次等待约 2 秒，未收到目标答复时重新发送请求，总共最多查询 3 次；完整解析 BEL／ST 颜色帧，排除合法的迟到或重复回复。启动保存和设置核验阶段仍严格拒绝键盘数据；退出恢复阶段可以识别颜色帧之间余留的 CR／LF、CSI／SS3 方向键，避免连续回车或方向键干扰正常恢复。整次退出最多接收 64 个控制单元，跨 19 个颜色项和重发累计；未知输入、帧内按键、残缺帧、非法 RGB、冲突回复或超限都停止自动覆盖。

退出时只恢复仍与本次临时设置一致的颜色，保留运行期间的其它改色。失败会指出具体原因，并保留仅适用于原终端的恢复入口。[隔离终端配色测试](./Tests/【MacOS】终端配色测试.command/README.md)覆盖 17 项基本场景和 47 项真实重入调用链的丢请求、合法按键余留、共享预算及重复／非法回复场景，共 64 项；测试不执行安装业务，也不改用户正在使用的终端。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
