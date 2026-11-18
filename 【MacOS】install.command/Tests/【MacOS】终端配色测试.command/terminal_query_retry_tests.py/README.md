# Jobs 终端查询重发回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行方式](#usage)
- [二、70 场景矩阵](#coverage)
- [三、产物与边界](#artifacts)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

配合[上级入口](../README.md)验证真实生产保护块的查询重发与逐帧解析。保留完整 `bootstrap` 调用和真实重入执行，在独立 PTY 中替换成无副作用假业务；不执行安装、不读写用户终端或 Profile。

## 一、<span id="usage">运行方式</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

依赖 MacOS、系统 `/bin/zsh` 及已有 [**Python**](https://www.python.org) 3.9 以上版本，仅使用标准库。这是测试依赖，生产入口不新增 Python 运行要求。

在本目录运行完整 70 场景：

```zsh
python3 ./terminal_query_retry_tests.py --yes
```

默认从脚本自身位置定位安装器，与启动目录无关。也可显式选择生产源码和本轮尚不存在的结果目录：

```zsh
python3 ./terminal_query_retry_tests.py --yes \
  --source ../../../【MacOS】install.command \
  --output "${TMPDIR:-/tmp}/jobs-query-reviewed-run"
```

局部验证用可重复的 `--case`，例如四个关键场景：

```zsh
python3 ./terminal_query_retry_tests.py --yes \
  --case drop-first-cleanup \
  --case drop-first-startup-4-9 \
  --case combined-old-duplicate-target \
  --case multi-record-rgb
```

不传 `--yes` 时先显示隔离范围并等待回车；输入结束或 Ctrl+C 取消。`--help` 列出全部可选场景。

验证退出阶段的按键余留和跨颜色项预算，可单独运行：

```zsh
python3 ./terminal_query_retry_tests.py --yes \
  --case cleanup-consecutive-keys \
  --case cleanup-fragmented-csi-left \
  --case cleanup-key-budget-across-queries \
  --case startup-csi-arrow-strict
```

设置核验、独立回退与业务状态，可单独运行：

```zsh
python3 ./terminal_query_retry_tests.py --yes \
  --case applied-consecutive-keys \
  --case applied-later-color-rollback \
  --case rollback-external-color-conflict \
  --case rollback-continues-with-business-status
```

## 二、<span id="coverage">70 场景矩阵</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 组别 | 场景数 | 核验行为 |
| --- | ---: | --- |
| 真正丢请求 | 8 | 保存期、设置核验期、退出期丢首请求，保存 `4;9` 丢首请求、退出丢两次，以及三阶段各连续丢三次；核验全丢后独立重新核对、恢复原色并以纯文本继续；按实际 OSC 发包计数，不能以增加读取等待冒充重发 |
| 旧帧与重复帧 | 5 | 旧 key 先到、旧帧与重复目标合并、首次迟到落入下一查询、旧 ST 帧分片后目标 BEL 到达、仅旧帧后再请求 |
| 退出阶段的合法按键 | 13 | 帧外 CR／LF、CSI／SS3 四向键及合法修饰方向键，包含连续按键、分片、颜色帧之间、下一个颜色查询中到达、丢首请求后仍有按键，以及恰好 64 单元；必须完整核验 19 项原色并恢复 |
| 共享按键预算 | 3 | 第 65 单元分别发生在同一查询、下一个颜色项、重发请求后；必须有界失败且不覆盖，证明预算不会随颜色项或重发重置 |
| 严格拒绝和阶段隔离 | 15 | 保存期仍拒绝 CR／LF、CSI／SS3；退出时未知文本、未知 CSI／SS3／裸 Esc、帧内方向键、相同目标颜色冲突、残缺帧、未知颜色协议、非法旧帧 RGB、单帧含多行 RGB 均不能触发盲目恢复 |
| 设置核验的合法按键 | 9 | 帧外 CR／LF、CSI／SS3 方向键及合法修饰，连续按键、分片、颜色帧之间和恰好 64 单元均不阻断业务 |
| 设置核验预算与阶段隔离 | 4 | 第 65 单元分别出现在同一查询、下一个颜色项和重发之后，均转独立回退；设置核验与退出可分别消耗 64 单元，证明阶段预算独立 |
| 核验失败后重新核对 | 6 | 首项／后部 `4;9` 收到普通文本、帧内按键、残缺帧、非法 RGB 或冲突答复时停止该核验，再重新读取全部 19 项原色归属，恢复成功才以纯文本继续 |
| 独立回退边界 | 7 | 回退持续失答、外部改色、64／65 按键边界、单项／全部已回原色及恢复成功后业务退出 37；核对保留新配色、避免重复写入、人工恢复入口和真实业务退出码 |

初始保存连续丢三次时尚未改色，保留原色并降级。设置核验失败会显示具体颜色项和原因，随后独立重新查询：当前仍等于本次临时目标值才还原，已经等于原值则保留，外部改色不覆盖。完整回退成功后清理人工恢复文件，以纯文本继续业务一次；回退仍失答、输入非法或颜色归属冲突则返回失败并保留恢复入口。正常退出持续失答也保持失败，不以初始快照盲目覆盖。合法旧帧可以排除，残缺或非法帧不能用重发拼成有效答复。

设置核验、独立回退及正常退出均可消费颜色帧之间的明确按键：每个 CR／LF 各计 1 单元，每条完整 CSI／SS3 方向键序列计 1 单元；CSI 修饰形式限定 `1;2` 至 `1;8` 加 `A`／`B`／`C`／`D`。每个阶段独立共用 64 单元，跨全部 19 个颜色项和重发请求累计。残缺键序列不算完整按键，不能吞掉未知输入，也不能从 OSC 帧内部删除按键后再接受 RGB。

启动保存期遇到按键仍保持原色并降级；设置核验期遇到未知或超限输入先进入独立回退，退出期未知或超限输入保留恢复入口。旧场景 `keyboard-csi-before-target` 使用的 `ESC[O` 并非方向键，仍作为未知 CSI 的失败回归保留。

每个场景同时检查退出码、19 项颜色、完整输入模式及 VMIN／VTIME、业务运行次数和恢复文件；正常恢复应恰有 19 次临时设置和 19 次恢复，已回原色的回退项不重复写入。回退成功同时检查 `PLAIN_OUTPUT=1`、`NO_COLOR=1`；失败或冲突不启动业务。夹具运行的是完整保护块及 `bootstrap/reexec`，不以直接调用内部函数代替实际入口。

## 三、<span id="artifacts">产物与边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

默认创建独立的 `jobs-terminal-query-retry-tests.*` 目录，包含 `tests.log`、`results.json`，以及各场景的夹具、模拟终端字节日志、逐阶段请求计数、原色与结束颜色、业务运行次数、输入模式恢复结果和模拟恢复文件。场景失败返回非零并保留现场，不覆盖已有回归。

全部颜色、答复和键盘故障均为模拟数据，不记录用户终端或应用内容。协议回归不能替代真实 Terminal／iTerm 会话验色，也不能证明不可捕获信号或所有窗口关闭场景均能恢复。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
