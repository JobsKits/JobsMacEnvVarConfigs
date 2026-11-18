# clean 询问提示样式回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行](#run)
- [二、覆盖内容](#coverage)
- [三、验证边界](#boundary)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

仅验证[终端 clean](../../【MacOS】clean.command)与[MacOS 右键清理](../../../../../../OS@Extension/MacOS@Extension/JobsDiskSpaceInfo/Scripts/【MacOS】清理磁盘空间.command/README.md)的提示展示和原生输入读取，不执行清理、不更换终端主题。

## 一、<span id="run">运行</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前目录执行：

```shell
ruby ./PromptStyleTests.rb
```

使用系统 [**Ruby**](https://www.ruby-lang.org/) 和 [**zsh**](https://zsh.sourceforge.io/)，每项分别加载两份生产脚本中的提示函数。真实 PTY 只承载展示和输入夹具，不运行 `main` 或清理阶段。

## 二、<span id="coverage">覆盖内容</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 显式询问题干使用青色粗体 `1;36`；仅回车选项保持绿色粗体 `1;32`，任意字符／非空输入保持红色粗体 `1;31`；问号、斜线、括号等分隔字符普通，提示结尾复位。
- Xcode 询问通过现有渲染器展示，原 `read -r`、空格、反斜线、中文输入与 EOF 返回值保持。
- 英文、已有 ANSI 样式、多行和无操作选项的询问正确展示；普通日志、自述及 URL 展示不追加询问题干样式。
- 调用者采用 `LC_ALL=C` 或仅 `LC_CTYPE=C` 时，formatter 的单条 `awk` 命令使用 MacOS 现有 `en_US.UTF-8` locale，避免中文字符类按字节拆分。中文路径、多行和输入保持完整，调用者 locale 不变；同时覆盖 `NO_COLOR` 空值降级。
- 非 TTY、`NO_COLOR`（包括空值）、`TERM=dumb`／空值、既有纯文模式及 Sourcetree 环境均输出纯文本；落盘日志不带 ANSI。

## 三、<span id="boundary">验证边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

PTY 核对实际输出控制码和真实输入读取，不等于所有终端软件的视觉验收。生产业务、删除范围、默认选项、清理授权、退出流程和终端配色保护保持原逻辑；本套测试不修改已安装入口或真实用户数据。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
