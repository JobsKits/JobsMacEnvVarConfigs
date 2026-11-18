# <span id="前言">环境后端隔离测试</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

暂无章节。

</details>
<!-- jobs-toc:end -->

---

本目录的[原生 zsh 回归入口](./【MacOS】环境后端回归.zsh/README.md)在新建临时 HOME 和源码副本内测试选择安装、备份、卸载和冲突保护。入口及依赖都由仓库相对位置解析，测试不执行已部署业务，不修改当前用户环境。

只有显式 `--yes` 才创建夹具；日志与夹具保留在测试结束时显示的系统临时目录，便于复核。无需额外安装测试运行时。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
