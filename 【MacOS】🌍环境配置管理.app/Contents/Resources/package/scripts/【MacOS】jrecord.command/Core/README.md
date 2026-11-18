# Jobs 窗口录屏原生内核

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

> 本目录提供窗口枚举、身份复核、录前倒计时与 MacOS 15+ 原生视频采集。日常使用从[上级 .command 入口](../README.md)开始，由入口体检并编译，无需 SwiftPM 或外部包。

## 一、<span id="layout">职责与结构</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 目录 | 职责 |
| --- | --- |
| `JobsRecorderCLI/` | 命令路由、帮助优先返回、权限和纯逻辑自检 |
| `JobsRecorderOptions/` | 严格解析与范围校验，默认静音 |
| `JobsWindowToken/` | 真实窗口与进程身份的编码、解码和校验 |
| `JobsWindowCatalog/` | 正常窗口候选、辅助窗口显式选择、浏览器范围、文字清理和启动前身份复核 |
| `JobsRecordingCountdown/`、`JobsCountdownPanel/`、`JobsCountdownView/` | 5 秒屏幕倒计时、鼠标穿透且不抢焦点的提示面板、数字绘制；提示全部移除后才启动采集 |
| `JobsRecordingSession/` | 独立窗口 SCStream／SCRecordingOutput、信号、首帧、窗口关闭和失败状态 |
| `JobsRecordingLifetime/` | 独立监视启动父进程关系和控制终端挂断，终端强退后请求停止并封尾，不遗留后台录制 |
| `JobsRecordingDestination/` | 磁盘门禁、独立暂存、媒体验证及 `RENAME_EXCL` 无覆盖发布 |
| `JobsAsyncDeadline/` | 系统异步回调的有界等待，迟到结果不会二次完成 |
| `JobsRecorderFailure/` | 稳定错误说明与非零退出码 |

## 二、<span id="contract">内部命令契约</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
JobsWindowRecorder --version
JobsWindowRecorder doctor
JobsWindowRecorder request-permission
JobsWindowRecorder list [--browsers] [--include-auxiliary]
JobsWindowRecorder resolve --window-id ID [--browsers] [--include-auxiliary]
JobsWindowRecorder record --target TOKEN --output /absolute/video.mp4
                   [--duration SEC] [--fps N] [--audio none|system] [--no-cursor]
JobsWindowRecorder --self-test
```

`list` 输出五列 TSV：内部 token、真实窗口 ID、应用、标题、尺寸。窗口文字剥离控制及双向格式字符；入口只向使用者显示后四列。`resolve` 只输出 token；录制时仍重新核验 ID、PID、Bundle ID 和进程启动时间。`doctor` 输出 JSON，仅预检录屏权限，不触发授权。

默认 `list` 与 `resolve` 选择标题经控制字符清理后非空，且通过原有身份、layer 0 和有效尺寸校验的应用窗口；包含最小化或其他桌面的正常命名窗口，不以当前是否可见作为硬门禁。浏览器标签页数量不等于可录窗口数量；无标题渲染窗、辅助窗和悬浮提示默认排除。不会按标题或尺寸去重，也不使用任意高度阈值。

`--browsers` 只限定浏览器应用范围；`--include-auxiliary` 独立决定是否额外加入无标题辅助窗口。隐藏窗口在两种模式下均标注 `[隐藏]`，无标题辅助窗口另标 `[无标题]`；正常可见有标题窗口保留原显示。`resolve --window-id ID` 同样需要该参数才能选择无标题辅助目标；隐藏但有标题的有效窗口默认可选。未知或重复参数直接拒绝；该候选策略不引入辅助功能权限，也不申请 AX 权限。

选择规则仅作用于开始前的候选构造。录制 token、启动后的身份复核和窗口存续检查继续使用完整窗口集合，不因遮挡、隐藏或切换桌面而改录其它窗口或仅凭不可见就判定关闭。


采用 [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) 的 `SCContentFilter(desktopIndependentWindow:)`。只允许指定窗口，不提供屏幕或矩形回退。倒计时使用原生 AppKit 事件循环，提示不接管鼠标或键盘焦点，结束后移除全部面板并重新验证目标，再开始采集。权限未授予返回 77；参数不合法返回 64；输出冲突或空间不足返回 73；其它故障返回非零。倒计时期间 SIGINT 取消返回 130，不生成录制；采集开始后 SIGINT 封尾成功返回 0，SIGTERM／SIGHUP 封尾后分别返回 143／129。

Shell 仅对本次交互子进程传入真实控制终端路径 `JOBS_RECORD_TTY`。内核保持该终端描述符，约每 100 毫秒用不读取输入的 `poll` 与终端属性检查挂断，并独立核对 `getppid()` 父子关系。启动父进程被 KILL 后，内核由系统重新挂接，PID 复用不会恢复旧父子关系。终端或父进程消失走正常停止／验证／发布，返回 129；不依赖父 Shell 仍能运行清理。无控制终端的调用保持可用，仅监视父关系。直接 KILL 内核本身无法捕获，不能保证封尾。

## 三、<span id="build">构建与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

入口根据源码、编译器、SDK 和架构创建独立缓存构建目录。需要支持 MacOS 15+ SDK 的 Xcode／Command Line Tools，编译目标为当前架构的 `apple-macos15.0`，链接 AppKit、ScreenCaptureKit、AVFoundation、CoreMedia、CoreVideo；不访问上游仓库或下载 Swift 包。

`--self-test` 不枚举或录制屏幕，覆盖凭据、参数范围、控制字符清理、默认静音、可见与隐藏／无标题窗口的纯选择策略、辅助模式独立开关、重复与未知选择参数拒绝、排他发布、已有文件保护、悬空链接及异步超时。文件发布测试仅在独立系统临时目录中创建夹具并自行移除。真实录制另用独立测试窗口验收，详见[上级验证说明](../README.md#validation)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
