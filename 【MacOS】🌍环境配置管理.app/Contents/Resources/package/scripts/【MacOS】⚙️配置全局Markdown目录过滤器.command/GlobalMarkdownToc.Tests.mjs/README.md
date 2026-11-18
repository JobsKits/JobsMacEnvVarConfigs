# `GlobalMarkdownToc.Tests.mjs`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

使用 Node 内置 test runner 和独立 Git 临时仓验证全局驱动；当前 7 项涵盖首次检出、暂存保护、重复安装撤回、外部配置保护、冲突、独立脚本包与无效目标。

## 一、依赖与调用 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

需要健康的 Node.js 20+；涉及仓库操作还需要 Git。保留整个上级脚本包和相邻转换器，路径按实际模块位置解析；不依赖启动工作目录。从本目录执行以下只读状态、语法或隔离测试命令：

```shell
node --test ./GlobalMarkdownToc.Tests.mjs
```

夹具显式限定 GIT_CONFIG_GLOBAL、GIT_CONFIG_NOSYSTEM 和独立用户安装目录；仅测试目录内写入，不联网，不安装业务依赖。

## 二、交付与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

[实际源码](<./GlobalMarkdownToc.Tests.mjs>)与本 README 同名包装。[上级完整说明](../README.md)列出前端一次确认、参数、默认安装范围、依赖、日志和撤回。兼容现有平铺部署包及固定转换器文件名；本次没有改写用户 Git 配置。语法、临时 Git 回归与用户实际环境验收分别记录。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
