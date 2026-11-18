# 【MacOS】SimulatorOrphanTests.zsh

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行](#run)
- [二、验证边界](#coverage)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

为 [【MacOS】clean.command](../../【MacOS】clean.command) 的 CoreSimulator 残留登记清理提供隔离回归。只加载生产函数，每个用例使用独立临时 HOME、合成 JSON 和假 `simctl`，不关闭或删除真实设备，不操作真实 Runtime、用户缓存及历史。

夹具加载后仅在测试进程中覆盖 Xcode 路径归属判断，使本组继续直接验证旧备份／复检／精确注销内核。生产入口中的失效设备由先行 Simulators 组承接，跳过／未选须保留，其选择、归属和孤儿桥接门禁由 Xcode 阶段测试覆盖；生产脚本没有新增跳过确认的测试参数。

## 一、<span id="run">运行</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录执行，或从任意工作目录传入脚本实际路径：

```shell
/bin/zsh './【MacOS】SimulatorOrphanTests.zsh'
```

依赖 macOS 自带的 zsh、JXA / Foundation、`ditto`、`diff` 和基础命令，不需要 Python、Ruby 或额外 SDK。各用例打印 PASS / FAIL；任一失败时最终退出码非零。临时目录带独占归属标记，结束后只回收本次夹具；可按 Ctrl+C 取消。

## 二、<span id="coverage">验证边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 保留完整设备、仅 Runtime 失配的设备、仍有定义但仅缺 `data` 的可恢复设备、非 iOS 设备和未知过渡状态。
- 设备目录完全缺失时精确注销 UUID，覆盖 `Booted` 异步进入 `Shutting Down`、起始已卡在关闭中，以及关闭失败、超时返回 `124` 或假成功仍未切换状态；同时核对完整正常设备未被关闭或注销。
- 缺 `device.plist` 但仍有数据时，先关闭并核对备份内容；关闭失败、超时、假成功或仍在 `Shutting Down` 时保留数据和登记，不套用无目录恢复分支。
- 注销失败、工具假成功未改变登记、备份内容不可读、查询失败、损坏 JSON、异常 schema 和无法遍历的目录均不得报告完整成功；卡在关闭中的设备也必须校验实际注销结果。
- 关闭后的查询异常、完整实体恢复、部分目录重现及未知状态不得沿用旧快照注销；只发送精确 UUID，不调用全局关闭或批量注销。
- 关闭返回取消状态 `130` 时保留登记并传播取消；其它客户端已移除登记时不再发送注销。
- 写前复检时实体恢复、备份后数据变化、非法 UUID、外部 `dataPath`、设备 / 定义 / 设备集 / 废纸篓软链接及缺少入口确认不得触发注销。
- 合法空设备清单和重复执行保持幂等；所有用例从工程外工作目录运行，并覆盖带空格及中文的临时 HOME。

这些夹具验证判断与命令编排，不能替代 Apple CoreSimulator 服务、Device Hub 界面或真实清理工具的端到端验收。

**终端配色保护：** 独立运行时，在支持完整保存与恢复配色的交互终端中临时使用黑底白字及统一强调色；正常结束、失败或可捕获中断后恢复进入前的配色，不修改终端全局偏好或 Shell 启动配置。不支持完整保护、无交互终端、`NO_COLOR`、既有纯文本模式和 Sourcetree 场景不切换配色，并沿用纯文本输出约定。强制终止（如 `kill -9`）无法由脚本自身保证恢复，请使用运行时显示的独立恢复入口。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
