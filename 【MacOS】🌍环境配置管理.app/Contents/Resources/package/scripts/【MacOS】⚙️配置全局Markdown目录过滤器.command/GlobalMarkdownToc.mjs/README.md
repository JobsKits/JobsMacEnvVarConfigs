# `GlobalMarkdownToc.mjs`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

全局过滤器后台 CLI：install 注册或复检受控用户级驱动；status 只读查看；uninstall 撤回本工具登记；setup <仓库根目录> 安装后恢复明确仓库树；restore-tree <仓库根目录> 只恢复该树。缺失或非根目标、进行中的 Git 操作、属性冲突、外部配置改动均停止。

## 一、依赖与调用 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

需要健康的 Node.js 20+；涉及仓库操作还需要 Git。保留整个上级脚本包和相邻转换器，路径按实际模块位置解析；不依赖启动工作目录。从本目录执行以下只读状态、语法或隔离测试命令：

```shell
node ./GlobalMarkdownToc.mjs status
```

写操作影响当前用户 Git 三个受控 filter 字段、.local/share/jobs-markdown-toc 副本和记录；恢复不会替换已暂存 blob 或用户 flags。由已确认前端或显式模式调用，不新增重复询问。

## 二、交付与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

[实际源码](<./GlobalMarkdownToc.mjs>)与本 README 同名包装。[上级完整说明](../README.md)列出前端一次确认、参数、默认安装范围、依赖、日志和撤回。兼容现有平铺部署包及固定转换器文件名；本次没有改写用户 Git 配置。语法、临时 Git 回归与用户实际环境验收分别记录。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
