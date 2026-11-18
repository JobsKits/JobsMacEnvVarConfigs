# Jobs 倒计时测试夹具

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、源码职责](#jobs-toc-heading-2)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

配合[原生倒计时测试入口](../README.md)，通过真实 [**AppKit**](https://developer.apple.com/documentation/appkit) 事件循环运行生产倒计时，不载入采集内核。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、源码职责 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 职责 |
| --- | --- |
| [JobsCountdownUITests.swift](./JobsCountdownUITests/JobsCountdownUITests.swift) | 驱动真实面板，检查序列、时长、图层动画、焦点和清理；既有权限下测试鼠标穿透，独立模式接收真实结束信号；生命周期模式故意忽略 HUP，用生产监视器验证 PTY 断开与父进程强退。 |
| [JobsCountdownClickView.swift](./JobsCountdownClickView/JobsCountdownClickView.swift) | 自建底层测试窗口的点击计数视图，允许首次点击，用于确认覆盖期间实际收到事件。 |
| [JobsCountdownTestState.swift](./JobsCountdownTestState/JobsCountdownTestState.swift) | 用锁在信号回调与主线程倒计时之间传递取消状态。 |

源码由上级 Shell 入口直接编译，不需要项目生成器或第三方依赖。临时 PNG 只绘制倒计时图层；不得改成全屏截图或用真实用户应用内容作为测试素材。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
