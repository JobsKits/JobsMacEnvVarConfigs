# 终端环境多选卸载

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、使用与依赖](#jobs-toc-heading-2)
- [二、恢复范围与日志](#jobs-toc-heading-3)
- [三、验证边界](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[【MacOS】卸载终端环境.command](./【MacOS】卸载终端环境.command) 保留终端操作方式，使用 [**fzf**](https://github.com/junegunn/fzf) 多选配置或命令，再由[统一后端](../【MacOS】环境管理后端.command/README.md)按收据恢复。原终端安装入口继续保留。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、使用与依赖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

保留完整仓库目录。在本目录双击同名脚本，或执行：

```shell
/bin/zsh ./【MacOS】卸载终端环境.command
```

- 先阅读范围，自述页回车只表示继续阅读；`Ctrl+C`、其它输入或 EOF 取消。
- ↑／↓ 或 Tab 移动，回车勾选／取消，空格确认；显式提供“取消本轮”“全选全部组件”“清空选择”操作行，操作行不会作为业务 ID 传给后端。
- 展示只读计划，最终确认默认“取消”；明确选择执行后才开始写操作。
- 组件选择层 Esc／← 取消本轮；最终确认层 ← 返回组件选择并保留勾选，即使查询没有匹配项也可返回。空选不能取当前高亮项执行。缺少可运行 fzf 时停止并提示，也可使用图形面板。

此入口需要交互终端。自动化调用使用后端的 `--uninstall ID... --yes`，不根据非交互输入默认执行。脚本包定位相邻后端，不能仅拷走单个卸载文件。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、恢复范围与日志 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

只撤回有本工具收据且未被后来修改的对象；原有文件恢复备份，新建文件核验后移除。缺少原点、用户修改、未知共享引用或仍被其它命令依赖时保留并报告，非零退出。历史终端安装没有收据时不会删除整片环境；不卸载 Homebrew、SDK、模型或用户数据。

日志和历史备份位于用户资源库 `Application Support` 的 `JobsMacEnvManager/logs` 和 `history`。中断后可以核对日志并再次选择同一批组件；不要与原安装器同时运行。

支持完整查询和恢复颜色的终端使用当前会话临时黑底白字，正常结束或可捕获信号后还原；非 TTY、`NO_COLOR` 和不支持的宿主使用纯文本，不修改终端全局主题。强制终止不能保证恢复，按运行时给出的原终端恢复入口处理。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

入口通过 zsh 语法检查；[后端隔离回归](../【MacOS】环境管理后端.command/Tests/【MacOS】环境后端回归.zsh/README.md)覆盖恢复与保护边界。[终端按键回归](./Tests/UninstallPTYTests.py/README.md)使用真实 fzf、独立 PTY、复制的包装器与假后端验证；不执行真实用户卸载或部署后的工具业务。真实用户环境卸载和业务工具使用不能由这些隔离测试推定通过。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
