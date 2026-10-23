# Shell 启动文件模板

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件与功能](#jobs-toc-heading-2)
- [二、使用与边界](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录保存用户 Shell 启动配置的源码模板。由[环境安装器](../install.command/README.md)部署和提示替换；查看模板不等于已经改变当前终端配置。模块实现和加载顺序见 [zsh/README.md](../zsh/README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、文件与功能 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 当前职责 |
| --- | --- |
| [.zshrc](./.zshrc) | 设置用户环境根目录，按顺序加载启动层、环境工具、生成的环境声明、别名和用户挂载；`JOBS_MAC_ENV_HOME_OVERRIDE` 可指定运行配置位置 |
| [.zprofile](./.zprofile) | zsh 登录时配置 Homebrew Ruby 的 PATH；包含检查并向用户登录配置追加 Ruby PATH 的动作，不能当作纯只读模板执行 |
| [.bash_profile](./.bash_profile) | bash 环境初始化、PATH 去重、Homebrew / Ruby / Java / Android / Flutter 路径、rbenv / jenv / SDKMAN 等已有工具初始化；交互 Shell 默认进入桌面 |
| [.bashrc](./.bashrc) | 加载 bash 登录配置；不要在登录配置中反向无条件加载它，避免循环 source |
| [.zshenv](./.zshenv)、[.zlogin](./.zlogin)、[.zlogout](./.zlogout) | 保留的启动 / 登录 / 退出模板位置，目前只有提示注释，没有业务动作 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、使用与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

需要部署时在本目录执行上级安装入口，并按提示决定是否替换用户配置：

```shell
zsh '../install.command/install.command'
```

安装器有自身的依赖检查与写入范围，运行前先读其 README。模板中的工具路径必须与本机安装一致，尤其是 bash 的 Gradle / Flutter 路径。直接 source 会执行配置正文、改变当前进程的环境或目录；它不用于安装缺失的全部开发工具。部署完成后重新打开终端验证命令路由，不能以模板文件存在代替运行环境已就绪。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
