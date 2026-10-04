# <span id="前言">`tts.command`</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

> 说明：终端启动时不会打印本 README 全文，只会打印脚本内部维护的简要自述。本 README 用于展开说明、后续维护和排查。

## <span id="前言">🔥 前言</span>

这个脚本现在是增强型本地 TTS 入口：

```text
list / tts
  ↓
fzf 选择 TTS 引擎
  ├─ MOSS-TTS-Nano：CPU 友好、中文/中英混读、长文本；音质/表现力弱于 VoxCPM2
  ├─ VoxCPM2：30 语言、48kHz、声音设计/克隆；2B 大模型，首次下载大，CPU 慢
  └─ Supertonic：轻量稳定、启动快、英文/日韩；无官方中文，中文走 macOS say
```

也就是说，在 `list` 菜单里选择 `tts`，或者终端里直接输入 `tts`，都会先弹出一个 `fzf` 菜单。菜单行里已经写明每个 TTS 的优势和劣势，方便按场景选择。

如果 `fzf` 不存在，脚本会尝试提示使用 `brew install fzf` 安装；仍不可用时会回退到普通文本选择菜单。

---

## 一、推荐策略 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文本 / 场景 | 推荐引擎 | 原因 |
| --- | --- | --- |
| 中文短文本、中文长文本、中英混读、普通本地朗读 | MOSS-TTS-Nano | 小模型，CPU 友好，部署负担低 |
| 高质量中文、多语言、声音设计、参考音频克隆 | VoxCPM2 | 30 语言、48kHz、声音设计/克隆能力强 |
| 英文、日文、韩文、轻量快速朗读、保留原有逻辑 | Supertonic | 原脚本逻辑稳定，启动快，轻量 |
| 老机器、无 GPU、只是想能朗读 | MOSS-TTS-Nano 或 Supertonic | 不建议默认跑 VoxCPM2 |
| Apple Silicon 且追求更好效果 | VoxCPM2，`:device mps` | MPS 比 CPU 更现实 |

---

## 二、通过 `list` 菜单运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

安装 / 同步 `🌍JobsMacEnvVarConfigs` 后执行：

```shell
list
```

在菜单里输入或选择：

```text
tts
```

回车后会继续弹出 TTS 引擎选择菜单：

```text
MOSS-TTS-Nano    优势：CPU 友好、中文/中英混读、长文本；劣势：音质/表现力弱于 VoxCPM2
VoxCPM2          优势：30 语言、48kHz、声音设计/克隆；劣势：2B 大模型，首次下载大，CPU 慢
Supertonic       优势：轻量稳定、启动快、英文/日韩；劣势：无官方中文，中文走 macOS say
```

---

## 三、通过终端短命令运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

直接进入交互模式：

```shell
tts
```

带文本直接朗读：

```shell
tts "你好，这是本地 TTS 测试。"
```

每次都会先弹出引擎选择菜单。

如果要跳过菜单，可以显式指定：

```shell
tts --moss "你好，这是 MOSS-TTS-Nano 测试。"
tts --voxcpm "你好，这是 VoxCPM2 测试。"
tts --supertonic "Hello, this is a Supertonic test."
tts --engine moss "你好。"
tts --engine voxcpm "你好。"
tts --engine supertonic "Hello."
```

也可以用环境变量指定：

```shell
TTS_ENGINE=moss tts "你好。"
TTS_ENGINE=voxcpm tts "你好。"
TTS_ENGINE=supertonic tts "Hello."
```

---

## 四、MOSS-TTS-Nano 引擎 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### 4.1 默认路径 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
MOSS_TTS_NANO_HOME=~/Desktop/MOSS-TTS-Nano
MOSS_TTS_NANO_VENV_DIR=~/Desktop/moss-tts-nano-venv
MOSS_TTS_NANO_BACKEND=onnx
MOSS_TTS_NANO_EXECUTION_PROVIDER=cpu
MOSS_TTS_NANO_PROMPT_SPEECH=~/Desktop/MOSS-TTS-Nano/assets/audio/zh_1.wav
```

首次选择 MOSS-TTS-Nano 时，如果环境不存在，脚本会询问是否自动执行：

```text
克隆 OpenMOSS/MOSS-TTS-Nano
创建 Python venv
pip install -r requirements.txt
pip install -e .
```

直接按回车执行，输入任意字符后回车跳过。

### 4.2 MOSS 交互命令 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 命令 | 作用 |
| --- | --- |
| `直接输入文本` | 立即朗读 |
| `:prompt /path/voice.wav` | 指定 voice clone 参考音频 |
| `:backend onnx` | 使用 ONNX 后端，默认推荐 |
| `:provider cpu` | 使用 CPU 推理，默认推荐 |
| `:provider cuda` | 使用 CUDA，需要自行安装 GPU 版 onnxruntime |
| `:config` | 查看当前 MOSS 配置 |
| `:quit` | 退出 |

### 4.3 输出文件 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

MOSS-TTS-Nano 官方 CLI 默认输出：

```text
~/Desktop/MOSS-TTS-Nano/generated_audio/moss_tts_nano_output.wav
```

脚本会复制一份带时间戳的文件到：

```text
scripts/tts.command/outputs/moss_tts_nano_YYYYMMDD_HHMMSS.wav
```

---

## 五、VoxCPM2 引擎 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### 5.1 默认路径与参数 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
VOXCPM_VENV_DIR=~/Desktop/voxcpm-venv
VOXCPM_OUTPUT_DIR=scripts/tts.command/outputs
VOXCPM_DEVICE=auto
VOXCPM_NO_OPTIMIZE=1
```

首次选择 VoxCPM2 时，如果环境不存在，脚本会询问是否自动执行：

```text
创建 Python venv
pip install voxcpm
python -c "from voxcpm import VoxCPM; print('VoxCPM is ready')"
```

如果 Hugging Face 访问慢，可以在交互里执行：

```text
:hf-mirror on
```

等价于：

```shell
HF_ENDPOINT=https://hf-mirror.com
```

### 5.2 VoxCPM2 交互命令 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 命令 | 作用 |
| --- | --- |
| `直接输入文本` | 立即朗读 |
| `:device auto` | 自动选择 `cuda -> mps -> cpu` |
| `:device mps` | Apple Silicon 推荐 |
| `:device cpu` | 强制 CPU，能跑但可能慢 |
| `:control 年轻女声，温柔甜美` | 声音设计，不需要参考音频 |
| `:control off` | 清空声音设计提示词 |
| `:reference /path/voice.wav` | 使用参考音频进行声音克隆 |
| `:reference off` | 清空参考音频 |
| `:prompt /path/voice.wav` | Hi-Fi 克隆 prompt 音频 |
| `:prompt-text 参考音频逐字稿` | Hi-Fi 克隆 prompt 文本 |
| `:denoise on/off` | 克隆时是否对参考音频降噪 |
| `:optimize on/off` | CPU/MPS 不稳定时保持 off |
| `:hf-mirror on/off` | 设置 / 取消 Hugging Face 镜像 |
| `:config` | 查看当前 VoxCPM 配置 |
| `:quit` | 退出 |

### 5.3 VoxCPM2 输出文件 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

脚本输出到：

```text
scripts/tts.command/outputs/voxcpm_YYYYMMDD_HHMMSS.wav
```

### 5.4 使用建议 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

VoxCPM2 不适合作为所有场景的默认引擎。它的优势是高质量、多语言、声音设计和声音克隆；代价是模型大、首次下载慢、CPU 推理慢。

普通中文朗读优先用 MOSS-TTS-Nano；英文/日韩轻量朗读优先用 Supertonic；需要更自然、更可控、更像真实人声时再选 VoxCPM2。

---

## 六、Supertonic 引擎 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

Supertonic 保留原有逻辑。

默认路径：

```shell
SUPERTONIC_VENV_DIR=~/Desktop/supertonic-venv
SUPERTONIC_HOST=127.0.0.1
SUPERTONIC_PORT=7788
SUPERTONIC_VOICE=M1
SUPERTONIC_LANG=auto
```

脚本会调用：

```shell
supertonic serve --host 127.0.0.1 --port 7788
```

然后请求：

```text
POST http://127.0.0.1:7788/v1/tts
```

### 6.1 Supertonic 交互命令 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 命令 | 作用 |
| --- | --- |
| `直接输入文本` | 立即朗读 |
| `:lang en` | 切换语言 |
| `:lang auto` | 自动判断，默认模式 |
| `:voice F1` | 切换声音 |
| `:speed 1.2` | 切换语速 |
| `:steps 10` | 切换质量步数 |
| `:zh-engine say` | 中文走 macOS say，默认推荐 |
| `:zh-engine supertonic` | 中文也强制走 Supertonic，不推荐 |
| `:zh-voices` | 查看本机中文语音 |
| `:zh-voice Tingting` | 指定中文语音 |
| `:zh-rate 200` | 指定中文语速 |
| `:docs` | 打开接口文档 |
| `:config` | 查看当前配置 |
| `:stop` | 停止本脚本启动的后台服务 |
| `:quit` | 退出 |

---

## 七、日志与排查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

主日志：

```text
$TMPDIR/tts.log
```

Supertonic 服务日志：

```text
$TMPDIR/tts.server.log
```

常见风险：

| 问题 | 处理 |
| --- | --- |
| `fzf` 不存在 | 按提示 `brew install fzf`，或使用文本 fallback |
| MOSS-TTS-Nano 安装失败 | 多数是 `pynini` / `WeTextProcessing`，优先看 `$TMPDIR/tts.log` |
| VoxCPM2 首次很慢 | 首次会下载模型；Hugging Face 慢时用 `:hf-mirror on` |
| VoxCPM2 CPU 很慢 | Apple Silicon 用 `:device mps`；NVIDIA 用 `:device cuda` |
| VoxCPM2 MPS/CPU 报 `torch.compile` 相关错误 | 保持 `:optimize off`，脚本默认就是 off |
| Supertonic 中文读得怪 | 这是预期风险，中文默认走 macOS `say` |
| `afplay` 不存在 | 脚本会改用 `open` 打开生成音频 |

---

## 八、维护原则 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

这个脚本不要把所有引擎揉成一个“自动乱猜”的黑盒。正确方向是：

```text
用户进入 tts
  ↓
看清楚每个引擎的优势 / 劣势
  ↓
按本次文本和设备情况选择
```

默认推荐顺序：

```text
普通中文 / 中英混读：MOSS-TTS-Nano
高质量 / 声音克隆 / 声音设计：VoxCPM2
英文 / 日韩 / 快速稳定：Supertonic
```

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
