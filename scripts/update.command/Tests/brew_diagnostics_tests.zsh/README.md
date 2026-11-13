# [**Homebrew**](https://brew.sh/) 诊断与包类型隔离测试

![Jobs出品，必属精品](https://picsum.photos/1500/400)

---

## 🔥 <span id="前言">前言</span>

> 使用假 [**Homebrew**](https://brew.sh/) 命令验证 `update.command` 的健康警告分类、真实失败传播与 formula 类型选择；仅操作临时目录，不联网、不安装、不升级。

## 一、运行与覆盖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录执行，或使用脚本的实际路径；依赖系统 `/bin/zsh` 与基本命令，不依赖真实 Homebrew：

```shell
/bin/zsh ./brew_diagnostics_tests.zsh
```

- 自动执行，无需确认；按 `Ctrl+C` 取消，退出时回收专属临时目录。
- `brew doctor` 返回健康警告时保存诊断并单独计数；`Error:`、异常、未知非零退出与日志写入失败均仍为失败。
- [**go-task**](https://formulae.brew.sh/formula/go-task) 使用 `homebrew/core/go-task` 与 `--formula`，不命中第三方同名 cask；其它 formula 也明确包类型。
- 未安装 formula 保持跳过；Tap 信任失败必须传播到调用方。
- 输出每组 `PASS` / `FAIL` 和统计；任一失败返回非零。隔离通过不代表真实升级或实际健康警告已经消除。

被测入口：[update.command](../../update.command)；上级说明：[更新脚本说明](../../README.md)。

**终端配色保护：** 独立运行时，在支持完整保存与恢复配色的交互终端中临时使用黑底白字及统一强调色；正常结束、失败或可捕获中断后恢复进入前的配色，不修改终端全局偏好或 Shell 启动配置。不支持完整保护、无交互终端、`NO_COLOR`、既有纯文本模式和 Sourcetree 场景不切换配色，并沿用纯文本输出约定。强制终止（如 `kill -9`）无法由脚本自身保证恢复，请使用运行时显示的独立恢复入口。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
