# Jobs 窗口录屏倒计时原生回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行方式](#jobs-toc-heading-2)
- [二、实际覆盖](#jobs-toc-heading-3)
- [三、产物与边界](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

编译[窗口录屏](../../README.md)的真实倒计时代码，在当前图形会话检查 5→1、双圆、心跳淡出、鼠标穿透和取消清理。只创建测试窗口，不运行窗口枚举、录屏、依赖安装或权限申请。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在本目录运行，先阅读自述并按回车确认；自动验证显式添加 `--yes`：

```zsh
NO_COLOR=1 zsh './【MacOS】倒计时测试.command' --yes
```

入口按自身位置定位生产源码，支持从其它工作目录调用。需要 [**MacOS**](https://www.apple.com/macos/) 图形会话与已有健康 [**Swift**](https://www.swift.org/) 工具链；缺少依赖时停止，不安装或升级。

测试会在所有已连接屏幕显示生产倒计时。已有事件发送权限时，鼠标短暂移动到自建底层窗口中心并执行一次点击，随后恢复原位置；没有该权限则明确输出 `SKIP`，不弹出授权请求。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、实际覆盖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 范围 | 验证方式 |
| --- | --- |
| 数字与时长 | 读取实际可见面板中的文字层，顺序必须为 5、4、3、2、1，总时长约 5 秒。 |
| 双圆与动画 | 每个面板恰有两个圆形图层，读取真实 presentation 图层确认透明度变化；系统未启用“减少动态效果”时验证心跳缩放。 |
| 全屏与焦点 | 每个已连接屏幕一个完整 `screen.frame` 面板，不成为 key/main，不改变前台应用，内容视图不命中鼠标。 |
| 鼠标穿透 | 有既有权限时向自建窗口发送真实鼠标点击，覆盖期间底层窗口必须收到一次点击。无权限单列跳过。 |
| 取消 | 已取消、中途取消和 Swift Task 取消均移除面板；中途取消在约 200 毫秒内响应。 |
| 真实信号 | 独立子进程接收 `INT`、`TERM`、`HUP` 后确认面板移除，分别返回 130、143、129。 |
| 终端生命周期 | 独立真实 PTY 故意忽略 HUP，关闭 master 或 KILL 启动父进程后仍必须被生产生命周期监视识别；无 TTY 的自动化夹具继续运行。 |

本测试直接编译五份生产源码：`JobsRecordingCountdown`、`JobsCountdownPanel`、`JobsCountdownView`、`JobsRecorderFailure` 和 `JobsRecordingLifetime`；测试驱动另见 [Fixtures](./Fixtures/README.md)。不通过注入假生产图层代替实际绘制。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、产物与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

每轮在系统临时目录创建独立的 `jobs-countdown-tests.*` 现场，入口首先打印其路径，保留原生测试二进制、`countdown-tests.log`、三份信号日志、终端生命周期日志与 trace，以及 `countdown-pulse.png` / `countdown-fade.png`。PNG 仅将倒计时自己的图层绘入透明位图，不截取或保存用户桌面与应用内容。

成功输出断言数量和 `PASS`，失败返回非零并保留现场。真实点击因权限跳过时，其余通过不能替代实际鼠标点击验收。全屏 Space 切换、热插拔多屏、所有系统版本，以及倒计时不进入最终视频的媒体链仍需按各自场景验证；本测试不录制视频。

```text
【MacOS】倒计时测试.command/
├── 【MacOS】倒计时测试.command
├── README.md
└── Fixtures/
    ├── README.md
    ├── JobsCountdownUITests/JobsCountdownUITests.swift
    ├── JobsCountdownClickView/JobsCountdownClickView.swift
    └── JobsCountdownTestState/JobsCountdownTestState.swift
```

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
