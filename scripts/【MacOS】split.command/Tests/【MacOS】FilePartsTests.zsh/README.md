# 文件拆分与合并隔离回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行方式](#jobs-toc-heading-2)
- [二、验证范围](#jobs-toc-heading-3)
- [三、结果与日志](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

验证 [jsplit](../../README.md) 与 [jmerge](../../../【MacOS】merge.command/README.md) 的手动目标校验、分卷完整性、内容还原和保留数据边界。测试只创建本轮独占的系统临时目录，不联网、不安装软件，也不处理真实业务文件。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在当前目录运行：

```shell
zsh './【MacOS】FilePartsTests.zsh'
```

测试从自身位置定位同仓源码，允许在其它工作目录使用脚本路径运行。需要 [**MacOS**](https://www.apple.com/macos/) 自带的 `zsh`、`expect`、`split`、`stat`、`shasum`、`osascript` 及可用的 [**fzf**](https://github.com/junegunn/fzf)。系统工具参与真实的小文件拆分与合并，`expect` 仅负责测试中的伪终端按键，不是 `jsplit` / `jmerge` 的运行依赖。缺少交互测试依赖会报告失败，不把未执行项记为通过。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、验证范围 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 空输入、纯空白、无效目录、多个路径、普通文件与目录区别、符号链接、引号、中文空格和拖入转义；未闭合引号与尾部转义不会执行输入代码。
- 拆分候选排除空文件、单字节文件、已有分卷及隐藏文件；无有效文件时持续重问，输入结束后退出，不扫描默认位置。
- 真实拆分、字节上限、卷数、分卷命名与 SHA-256；分卷流与源文件内容一致，无扩展名文件使用 `.parts` 输出目录。
- 合并按数字卷号排序，兼容补零及原文件名含 `@`；拒绝单卷、缺卷、重复卷号、总数冲突、空分卷与越界号；父目录发现第一层子目录并正确还原。
- 已有输出不覆盖；默认、小写 `yes` 和输入结束均保留源数据；只有精确 `YES` 才删除。确认期间源文件、分卷或合并成品发生变化时保留对应原始数据。
- 脚本包搬移、改名以及在工程外工作目录下的位置解析。
- 真实伪终端中的单选方向键、多选 Tab 导航、全选／清空／取消操作行、空选、Esc、正常和无匹配时返回，以及执行计划的默认取消、显式执行确认和返回。

测试提取产品脚本的函数定义，去除入口调用后在临时副本中运行；不会向产品脚本增加测试参数或绕过手动确认的生产路径。伪终端只执行真实选择函数，文件写操作另由临时夹具独立验证。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、结果与日志 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

每项显示 `PASS` 或 `FAIL`，最后汇总通过与失败数量，存在失败时返回非零。系统临时目录中的 `jobs-file-parts-tests.*` 保留本轮夹具、`details.log`、`split.log`、`merge.log` 和 `pty.log`，实际位置由启动输出给出。日志便于检查失败原因；测试不会自动删除这些隔离证据。

这些检查验证当前机器的原生小文件处理及真实选择器行为，不代表其它电脑、所有终端配色环境或大型镜像文件已经验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
