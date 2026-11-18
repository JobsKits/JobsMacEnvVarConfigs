# 通用缓存选择与保护回归

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

验证[终端 clean](../../【MacOS】clean.command)和[右键清理](../../../../../../OS@Extension/MacOS@Extension/JobsDiskSpaceInfo/Scripts/【MacOS】清理磁盘空间.command/README.md)的独立通用缓存实现。所有候选都在临时用户目录内，覆盖不含任何 Jobs 专用目录的电脑环境；不清理真实用户缓存、SDK、依赖或模拟器。

## 一、<span id="run">运行</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前目录执行：

```shell
ruby ./CacheScopeTests.rb
```

测试依赖系统 [**Ruby**](https://www.ruby-lang.org/)、[**zsh**](https://zsh.sourceforge.io/) 及 MacOS 原生命令。存在健康的 [**fzf**](https://github.com/junegunn/fzf) 时执行真实 PTY 按键验证；缺失时明确跳过该项，不安装依赖。

## 二、<span id="coverage">覆盖内容</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 完整冻结一级候选后才选择；中文、空格路径和普通机器缓存可用。默认跳过；Enter 勾选、Space 确认已选集，无勾选时选定当前行。覆盖直接确认全选／单项、取消最后一个勾选、已有选集不增选光标、已选但搜索无匹配、无匹配确认后清搜索恢复、混选跳过优先及 Esc 取消；最终准确范围仍需回车确认。
- 随机目录名中的源码、Go／Node／Rust／Python 依赖、SDK 标记按内容保护，不按 `JobsSoftwareEnvironments` 等专用目录名判断。只读父目录、嵌套链接、异盘元数据及无法完整检查的候选整体保留。
- 流式检查设置 10000 项、64 层和操作间 5 秒预算；测试使用缩小项数边界及真实深层树，另覆盖流返回停顿。预算不是系统调用的强制抢占超时。
- 保护项不进入失败重试，工具错误不能在下一轮变成空队列成功；失败重试不采纳新增、替换或被修改的成员。文件时间采用原生纳秒字段，覆盖同 inode、同大小的快速改写。
- 删除仅处理授权快照中的原文件，目录逆序使用 `rmdir`；最后扫描后新增文件也不会被递归移除。取消退出码立即停止后续成员；不可变／仅追加 flags 与普通非保护 flags 分开判断。

## 三、<span id="boundary">验证边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

测试加载两份生产函数，选择／确认替身只用于内核用例，真实 fzf 与方向键、Enter、Space、Esc 另用 PTY 验证。仅操作本轮临时文件；flags、设备号和预算边界部分使用受控替身。通过不代表真实系统受保护目录、其它电脑、Windows 原生控制台或已安装右键菜单已完成验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

真实 PTY 的缓存选择回归覆盖首行全选、第二行默认跳过、全选后搜索仍展开完整候选、混选跳过优先、单选、空选与 Esc 取消；全选只形成候选计划，原保护与最终范围确认继续生效。
