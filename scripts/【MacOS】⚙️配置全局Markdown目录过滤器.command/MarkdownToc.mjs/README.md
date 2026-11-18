# `MarkdownToc.mjs`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、依赖与调用](#jobs-toc-heading-2)
- [二、交付与验证](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

自包含 Markdown 转换器资源兼 CLI。Git clean 从 stdin 生成受控折叠目录，smudge 还原 [toc]；还保留 install / restore / status / uninstall / check / verify / preview 的已有仓内驱动协议。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、依赖与调用 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

需要健康的 Node.js 20+；涉及仓库操作还需要 Git。保留整个上级脚本包和相邻转换器，路径按实际模块位置解析；不依赖启动工作目录。从本目录执行以下只读状态、语法或隔离测试命令：

```shell
node --check ./MarkdownToc.mjs
```

源码由全局驱动复制为固定的 MarkdownToc.mjs 安装文件，不能随意改写已登记 Git 配置路径。clean / smudge 只处理标准流；其它模式按当前驱动所在仓的 manifest 精确选文件，真实写操作由其调用入口负责授权。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、交付与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

[实际源码](<./MarkdownToc.mjs>)与本 README 同名包装。[上级完整说明](../README.md)列出前端一次确认、参数、默认安装范围、依赖、日志和撤回。兼容现有平铺部署包及固定转换器文件名；本次没有改写用户 Git 配置。语法、临时 Git 回归与用户实际环境验收分别记录。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
