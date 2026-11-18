# 【MacOS】code.command

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

让终端可以直接使用 VS Code 的 `code` 命令，例如：

```zsh
code .
code pubspec.yaml
```

这个脚本不会安装 VS Code 本体，只负责在常见位置查找 VS Code 自带的官方 CLI：

- `$APPLICATIONS_DIR/Visual Studio Code.app/Contents/Resources/app/bin/code`
- `$HOME/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code`
- `$(brew --prefix)/bin/code`
- `$(brew --prefix)/bin/code`

如果 VS Code 放在非标准目录，脚本会尝试通过 Spotlight 的 Bundle ID 继续查找。

**终端配色保护：** 独立运行时，在支持完整保存与恢复配色的交互终端中临时使用黑底白字及统一强调色；正常结束、失败或可捕获中断后恢复进入前的配色，不修改终端全局偏好或 Shell 启动配置。不支持完整保护、无交互终端、`NO_COLOR`、既有纯文本模式和 Sourcetree 场景不切换配色，并沿用纯文本输出约定。强制终止（如 `kill -9`）无法由脚本自身保证恢复，请使用运行时显示的独立恢复入口。

