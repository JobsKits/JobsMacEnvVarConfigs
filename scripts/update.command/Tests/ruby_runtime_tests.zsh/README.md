# [**Ruby**](https://www.ruby-lang.org/) 运行时隔离测试

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、覆盖范围](#coverage)
- [二、运行方式](#usage)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

> 使用假解释器复现 `gem` 仍指向旧系统运行时的环境，验证更新与原生扩展检查使用同一解释器；不联网、不升级真实工具。

## 一、<span id="coverage">覆盖范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 环境查询和更新均绑定所选解释器，忽略 `PATH` 中旧 `gem` 的固定解释器。
- 子命令清除 Bundler 注入，不修改调用进程原环境。
- [**Homebrew**](https://brew.sh/) 管理的 RubyGems 本体不执行 `gem update --system`。
- 环境读取失败、解释器错配和升级失败均停止或返回失败。
- `PATH` 缺少 `gem` 启动器时，已有解释器自带的 RubyGems 仍可维护。

## 二、<span id="usage">运行方式</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录运行，依赖系统 `zsh` 和基础文件工具：

```shell
zsh ./ruby_runtime_tests.zsh
```

脚本自动执行六项用例；按 `Ctrl+C` 取消。调用记录和日志位于专属临时目录，进程结束自动清理；全部通过返回 `0`，任一用例失败返回非零。该测试不代替真实网络和包升级验收。

[返回更新脚本说明](../../README.md)

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
