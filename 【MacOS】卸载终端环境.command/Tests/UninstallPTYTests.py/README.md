# 卸载入口真实 PTY 键位回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行方式](#jobs-toc-heading-2)
- [二、覆盖与结果](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[UninstallPTYTests.py](./UninstallPTYTests.py) 以真实 [**fzf**](https://github.com/junegunn/fzf) 和独立 PTY 向[卸载包装器](../../【MacOS】卸载终端环境.command)发送回车、空格、Tab、方向键和中断字符。被测脚本先复制到独立目录，旁边只有假后端和临时 HOME；不会触及真实环境管理后端。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

需要已有 [**Python**](https://www.python.org/) 3 和 fzf，测试不安装依赖。在本 README 所在目录运行：

```shell
python3 ./UninstallPTYTests.py --yes
```

可用 `--source` 指定待测包装器文件，`--output` 指定尚不存在的输出目录。默认在系统临时目录建立新夹具，每项保留 `terminal.log`、假后端 `calls.log`，汇总保存为 `results.json`。终端颜色保护以 `NO_COLOR` 关闭，本测试只验证键位与业务门禁；颜色切换由独立配色回归负责。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、覆盖与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

测试覆盖首屏 Ctrl+C／EOF、空选不执行、回车只勾选、空格形成计划、最终默认取消、明确单选和多选、确认层左键返回并保留选择、无匹配左键返回、全选／清空操作行及组件根层左键取消。检查假后端只收到明确选择的真实 ID，操作行和当前高亮项不能冒充业务选择。

当前 macOS、fzf 0.75.0 的真实 PTY 回归包含 11 个场景；这是包装器交互的限定验证，不代表真实用户环境卸载、业务命令、图形面板或其它 fzf 版本全部通过。后端的文件部署和恢复由[原生生命周期回归](../../../【MacOS】环境管理后端.command/Tests/【MacOS】环境后端回归.zsh/README.md)另行验证。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
