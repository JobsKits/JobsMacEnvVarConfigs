# Jobs 功能菜单返回测试

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行](#run)
- [二、验证范围](#coverage)
- [三、现场与结果](#artifacts)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

验证从 `list` 进入子功能后，尚未确认执行时能用左方向键回到原菜单。测试只提取真实确认与父层函数，在独立的伪终端运行；具体业务全部替换为哨兵，不安装、更新、清理、录屏或申请权限。

## 一、<span id="run">运行</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录执行：

```zsh
./【MacOS】ListConfirmTests.zsh
```

自动验证显式跳过测试自述确认：

```zsh
./【MacOS】ListConfirmTests.zsh --yes
```

依赖 macOS 系统 `/bin/zsh`、`/usr/bin/expect` 和已经可用的 [**fzf**](https://github.com/junegunn/fzf)。入口只检查工具，不自动安装。可从任意工作目录执行；生产脚本位置相对测试入口解析。

## 二、<span id="coverage">验证范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 场景 | 检查内容 |
| --- | --- |
| 确认按键 | 真正发送 CSI／SS3 左方向键，必须返回专用状态 20；回车继续，Esc／Ctrl+C 取消，取消时业务哨兵不执行。 |
| 独立启动 | 没有 `list` 来源标记时，继续使用原始 `read` 参数和输入内容，不擅自打开菜单。 |
| 全部确认入口 | 从实际菜单发现非录屏脚本，逐个提取真实初始确认函数，在 PTY 中验证左键返回；只读展示和参数解析用桩隔离。录屏入口由其独立测试覆盖。 |
| 原父菜单 | 普通脚本、录屏标记、格式转换别名和 Flutter 函数四类，通过真正的 fzf 进入确认再返回；原 `show_menu` 必须立即重画，不递归启动新菜单、不增加回车等待。 |
| 输入状态 | 核对父层前后的输入模式，忽略内核的 PENDIN 输入队列瞬时标志；不修改真实用户终端。 |

测试使用 fzf 的真实交互，仅模拟其光标位置查询响应。测试没有调用各功能的业务入口，不能代替各功能本身的安装、运行或媒体回归。

## 三、<span id="artifacts">现场与结果</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

每轮创建独立的 `jobs-list-confirm-tests.*` 临时目录，入口显示其位置，保留提取的函数、Expect 驱动与 `navigation.log`。失败返回非零并保留现场；成功输出按键、生产确认入口和父层返回三类结果。

```text
【MacOS】ListConfirmTests.zsh/
├── 【MacOS】ListConfirmTests.zsh
└── README.md
```

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
