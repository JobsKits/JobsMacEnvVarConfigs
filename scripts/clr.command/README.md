# clr.command

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

> **Python 环境预检**：实际调用 [**Python**](https://www.python.org/) 前使用本文件内嵌的环境预检函数，通过 [**Homebrew**](https://brew.sh/) 管理运行时；脚本可单文件复制运行，不需要旁边的支持目录。终端自述确认后执行 `brew update` 更新本体及公式索引；只在指定公式 `python@3.13` 缺失、损坏或版本不满足 `3.11+` 时安装或修复，健康运行时直接复用。缺失 Homebrew 时强提示选安装路径：精确大写 `YES` 选系统标准目录，其它输入或回车选用户目录；失败停止，不自动换路。必需安装或修复直接回车执行，任意非空输入（含空格）取消。预检不执行全局 `brew upgrade`。

## 🔥 <font id=前言>前言</font>

- 脚本入口使用 macOS 原生 Shell；其中的解析、转换或服务功能需要下述已验证的 Python 运行时。


## 功能 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

清空 Google Chrome 浏览器下载历史，不删除已经下载到本地的真实文件。

## 命令 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```zsh
clr
```

## 现实结论 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

Chrome 没有给普通 macOS 命令行提供稳定的「清空下载历史」接口。坐标点击 `chrome://downloads/` 右上角「全部清除」不稳定；直接改 Chrome `History` 数据库也不能稳定影响正在运行的 Chrome 内存状态。

这一版改为可靠方案：使用一个极小的本地 Chrome 扩展，通过 Chrome `downloads` API 清除下载历史。

## v7 修正 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 不再盲信 `~/.JobsMacEnv/ChromeExtensions/jobs-clear-downloads/extension_id.txt` 里保存的旧扩展 ID。
- 每次运行会先检查 Chrome `Preferences` / `Secure Preferences`，确认扩展仍然存在并处于启用状态。
- 已删除、已禁用、已被 Chrome 屏蔽的旧 ID 会被自动忽略，避免浏览器出现 `ERR_BLOCKED_BY_CLIENT`，但脚本仍误判为“已触发清理”。
- manifest.json 继续使用合法固定 `key`，预期新版扩展 ID 为：`fglcbiaddbchgemaegkjejejikhilpon`。
- 如果 Chrome 扩展页已经显示装好了，但 `clr` 仍识别不到，可手动保存一次扩展 ID。

```zsh
clr --extension-id 扩展卡片里显示的32位ID
```

不要继续硬写旧截图里的 `bceffimgdjebjemfhcfkombngddhmdee`；除非 Chrome 扩展页明确显示这个 ID 仍然存在且已启用。



## v8 修正 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 修复 `zsh` 下 `jobs_clr_read_saved_extension_id: read-only variable: status`。
- 原因是 `status` 是 `zsh` 的只读特殊变量，脚本里不能再 `local status=...`。
- 已改为 `ext_status`，保留扩展 ID 校验逻辑不变。

## 看到 ERR_BLOCKED_BY_CLIENT 怎么办 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

这不是下载历史清理成功，而是 Chrome 拦截了扩展内部页面。常见原因：

- `clr` 还在使用旧的扩展 ID，但这个扩展已经被你移除。
- 旧扩展被 Chrome 禁用。
- 本地扩展目录的 manifest 更新后，Chrome 里的旧扩展 ID 已经失效。

处理方式：

```zsh
rm -f ~/.JobsMacEnv/ChromeExtensions/jobs-clear-downloads/extension_id.txt
clr --install-extension
```

然后到 `chrome://extensions/`：

1. 开启「开发者模式」。
2. 移除旧的 `Jobs Clear Chrome Downloads`。
3. 重新「加载已解压的扩展程序」。
4. 选择 `~/.JobsMacEnv/ChromeExtensions/jobs-clear-downloads`。
5. 确认扩展开关处于启用状态。
6. 重新执行 `clr`。

## 第一次使用 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```zsh
clr --install-extension
```

然后按提示操作：

1. 打开 Chrome 的 `chrome://extensions/`
2. 开启右上角「开发者模式」
3. 点击「加载未打包的扩展程序」
4. 选择脚本提示的扩展目录
5. 加载完成后重新执行：

```zsh
clr
```

如果之前加载过旧版且仍不生效，先在 `chrome://extensions/` 移除旧的 `Jobs Clear Chrome Downloads`，再重新加载目录。

## 常用参数 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```zsh
clr
clr --install-extension
clr --extension-id 扩展卡片里显示的32位ID
clr --open-only
clr --open
clr --yes
```

说明：

- `clr`：触发下载历史清理。
- `clr --install-extension`：生成并打开本地 Chrome 扩展安装指引。
- `clr --extension-id ID`：手动指定并保存 Chrome 扩展卡片里的 32 位 ID。
- `clr --open-only`：只打开 `chrome://downloads/`，不清理。
- `clr --open`：清理触发后打开 `chrome://downloads/` 查看结果。
- `clr --yes`：跳过回车确认，适合脚本化调用。

## 边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 只清除 Chrome 下载历史。
- 不删除 `~/Downloads` 或其它目录里的真实文件。
- 不退出 Chrome。
- 不备份 Chrome History 数据库。
- 不关闭或替换原来的网页。

## 日志 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
$TMPDIR/clr.log
```

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
