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

为 [clean.command](../../clean.command) 的 CoreSimulator 残留登记清理提供隔离回归。只加载生产函数，每个用例使用独立临时 HOME、合成 JSON 和假 `simctl`，不关闭或删除真实设备，不操作真实 Runtime、用户缓存及历史。

## 一、<span id="run">运行</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录执行，或从任意工作目录传入脚本实际路径：

```shell
/bin/zsh './【MacOS】SimulatorOrphanTests.zsh'
```

依赖 macOS 自带的 zsh、JXA / Foundation、`ditto`、`diff` 和基础命令，不需要 Python、Ruby 或额外 SDK。各用例打印 PASS / FAIL；任一失败时最终退出码非零。临时目录带独占归属标记，结束后只回收本次夹具；可按 Ctrl+C 取消。

## 二、<span id="coverage">验证边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 保留完整设备、仅 Runtime 失配的设备、仍有定义但仅缺 `data` 的可恢复设备、非 iOS 设备和未知过渡状态。
- 设备目录缺失时精确注销 UUID；缺 `device.plist` 但仍有数据时先核对备份内容；坏 Booted 设备先关闭，再复检与注销。
- 关闭 / 注销失败、工具假成功未改变登记、备份内容不可读、查询失败、损坏 JSON、异常 schema 和无法遍历的目录均不得报告完整成功。
- 写前复检时实体恢复、备份后数据变化、非法 UUID、外部 `dataPath`、设备 / 定义 / 设备集 / 废纸篓软链接及缺少入口确认不得触发注销。
- 合法空设备清单和重复执行保持幂等；所有用例从工程外工作目录运行，并覆盖带空格及中文的临时 HOME。

这些夹具验证判断与命令编排，不能替代 Apple CoreSimulator 服务、Device Hub 界面或真实清理工具的端到端验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
