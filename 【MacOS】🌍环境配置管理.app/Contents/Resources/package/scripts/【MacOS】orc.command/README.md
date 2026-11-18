# `ORC`：离线文字识别

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

通过 [**indra-ocr**](https://github.com/datalab-to/indra) 在本机识别 PDF 和图片，使用 CPU，无需 GPU。命令保留用户指定的 `ORC` 拼写，`orc`、`ORC`、`Orc`、`oRc`、`orC`、`ORc`、`OrC`、`oRC` 均可调用。

| 终端命令 | 结果 |
| --- | --- |
| `ORC` | 确认后输入或拖入一个或多个文件 |
| `ORC "扫描件.pdf" --format text` | 识别并向标准输出写纯文本 |
| `orc "图片.png" --out "识别结果"` | 向指定目录写 Markdown 文件 |
| `Orc --offline "扫描件.pdf" --format json` | 禁止依赖安装及模型联网，输出 JSON |
| `ORC --install` | 只准备工具，不预下载模型 |
| `ORC --help` / `ORC --version` | 只读帮助 / 已安装版本，不安装、不创建日志 |

首次实际识别通常下载约 76 MB 基础模型；完整缓存后可以离线使用，数学模型另计。默认先查本地缓存，`--offline` 明确禁止模型联网。依据：[官方说明](https://github.com/datalab-to/indra/blob/main/README.md)、[模型加载实现](https://github.com/datalab-to/indra/blob/main/indra_ocr/models.py)。

## 一、<span id="usage">运行与交互</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

通过[配置同步入口](../../【MacOS】install.command/README.md)安装命令，重新打开终端，或在已有终端重载环境。也可在本目录直接运行：

```zsh
/bin/zsh ./【MacOS】orc.command "扫描件.pdf" --format text
```

常规运行先展示内置自述；直接回车继续，任意非空输入或输入结束取消，`Ctrl+C` 中断。没有交互标准输入时不执行识别或安装。通过 `list` 进入时，首次确认的 `←` 返回功能菜单，`Esc` 取消。

无参数启动后可从 Finder 拖入 PDF、PNG、JPEG、TIFF、BMP 或 WebP；多个文件按 Shell 引号和转义规则解析，不执行路径中的命令表达式。含空格路径需引号包裹或直接拖入。命令行参数保持数组边界，路径基于调用时的当前目录，不切换到脚本目录。普通文件名若与选项相同，可在文件前使用 `--`。

## 二、<span id="environment">依赖与离线准备</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

- 使用用户数据目录 `jobs-orc/venv` 的独立虚拟环境，安装命令为该环境内的 `python -m pip install indra-ocr`，不往系统 Python 写包。
- 已有健康环境直接复用，不执行 pip / Homebrew 更新。缺依赖时先说明目标并再次确认，直接回车安装；非空输入或 EOF 取消。安装后校验 CLI、ONNX、OpenCV、PDF 和模型下载依赖。
- 准备新环境时优先选择已有 Python 3.10～3.13；缺少兼容解释器时通过健康 Homebrew 按需安装 `python@3.12`。Homebrew 不可用时停止并提示先准备它，或显式提供解释器，不隐式安装 Homebrew。
- 网络获取失败会有界退避并持续重试，`Ctrl+C` 停止；明确的版本、权限、磁盘或依赖错误停止。原有损坏虚拟环境保留并报告，不自动删除。安装锁阻止同时修改环境，异常残留锁须确认无人使用后移除此空目录。
- `--offline` 同时禁止安装和修复环境，并为识别进程设置 `HF_HUB_OFFLINE=1`；缺环境或模型时失败。已有 `HF_HUB_OFFLINE=1` 同样生效。离线模式不会为了体检更新 Homebrew 或查询包索引。

先联网运行一次实际识别，再验证离线：

```zsh
ORC --install
ORC "扫描件.pdf" --format text
ORC --offline "扫描件.pdf" --format text
```

`--install` 只安装工具，不能代替首次识别的模型准备。离线机器也可通过 `--model-dir` 或 `INDRA_OCR_MODEL_DIR` 指定从其它机器复制的完整模型。使用 `--math` 时须另行准备对应模型。

| 环境变量 | 含义 |
| --- | --- |
| `JOBS_ORC_HOME` | 工具数据目录；默认使用当前用户 `.local/share/jobs-orc`，相对值基于调用目录 |
| `JOBS_ORC_PYTHON` | 新建环境时指定健康 Python 可执行文件路径，版本限 3.10～3.13；无效时停止 |
| `INDRA_OCR_MODEL_DIR` | 上游完整本地模型目录 |
| `HF_HOME` / `HF_HUB_CACHE` | 显式设置时原样保留，包括空值；二者均未设置时，仅为当前识别进程设置 `HF_HOME` 到工具数据目录的 `models/`，默认不写共享缓存 |
| `HF_HUB_OFFLINE=1` | 强制离线，等效启用包装器的离线限制 |

上游安装要求为 Python ≥ 3.10；包装器选择上述区间以避开过新解释器的原生轮子兼容问题。官方已列出 macOS Apple Silicon 测试，Intel Mac 未列入官方已测清单，不由脚本可运行推定识别兼容。包信息见 [PyPI](https://pypi.org/project/indra-ocr/)。

## 三、<span id="options">识别选项与输出</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

除 `--offline` 和单独使用的 `--install`，其余参数透传[官方 CLI](https://github.com/datalab-to/indra/blob/main/indra_ocr/cli.py)。`--install` 不能与文件、其它选项或离线模式混用。

| 参数 | 行为 |
| --- | --- |
| `--format md\|text\|json` | 默认 Markdown；JSON 文件扩展名为 `.jsonl` |
| `--out 目录` | 每个输入生成一个结果；未指定时输出正文到 stdout |
| `--mode auto\|ocr\|text` | 默认自动使用合格 PDF 文本层，`ocr` 强制识别 |
| `--model-dir 目录` | 显式选择完整模型目录 |
| `--cores 数量` / `--threads 数量` | CPU 线程数 |
| `--dpi 数值` / `--max-pages 数量` | 默认 DPI 200，默认页数 0 表示不限制 |
| `--password 密码` | PDF 密码；包装器不记录命令参数 |
| `--math` / `--keep-furniture` | 启用公式识别 / 保留页眉页脚 |
| `--no-image-ocr` / `--timings` | 不识别图片 / 显示耗时 |

上游 `--out` 会覆盖跨次运行的同名结果；保留旧结果时请使用不同的输出目录。默认不改写输入文件。

```zsh
ORC --offline "扫描件.pdf" --format text > "识别文字.txt"
ORC "第一页.png" "第二页.png" --out "结果目录"
```

提示、确认和安装进度写 stderr；stdout 只保留识别正文，可直接重定向。运行日志为系统临时目录中的 `orc.log`，每次确认后重新初始化，包含步骤、上游错误和最终退出码，不额外复制识别正文或记录输入参数。上游错误文本仍会进入日志。包装器保留上游真实退出码。

## 四、<span id="registration">命令与维护入口</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

[安装器](../../【MacOS】install.command/README.md)同步完整脚本包并注册 bin 转发器；[entrypoints](../【MacOS】entrypoints.command/README.md)为默认 zsh 环境提供全部八种大小写函数；[list](../【MacOS】list.command/README.md)提供“离线 OCR”。模块 source 时只定义入口，不安装环境或下载模型。分项环境管理后端登记规范 `orc`，其余大小写由 zsh 函数和文件系统解析。

## 五、<span id="validation">验证范围</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

2026-11-16 已验：独立环境安装 Indra OCR 1.1.2、Python 3.13，`pip check` 正常；首次联网获取基础模型并识别样张，输出 `JOBS OFFLINE OCR 12345`、退出码 0。随后通过系统沙盒明确禁止全部网络，再运行 `--offline`，退出码仍为 0，stdout 与在线结果逐字节一致。

Shell 语法、帮助无副作用、非交互拒绝、八种大小写接线及 17 场终端配色隔离回归已通过。该结果覆盖当前机器的基础英文样张；其它 Mac、Intel 平台、数学模型及其它语言或复杂版面识别不由此测试外推。

<a id="🔚" href="#前言">我是有底线的➤点我回到首页</a>
