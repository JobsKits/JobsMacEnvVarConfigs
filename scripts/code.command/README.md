# code.command

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

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
