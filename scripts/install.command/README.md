# install.command

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

## 🔥 <font id=前言>前言</font>

- 采用 Shell 脚本的原因：Shell 来自 [**macOS**](https://www.apple.com/macos/) 原生系统底层，虽然写法相对繁琐冗杂，但执行效率高，并且不需要额外介入 [**Ruby**](https://www.ruby-lang.org)、[**Python**](https://www.python.org) 等第三方运行环境，因此具备更好的移植性。


## 一、功能 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 安装和初始化常用 [**macOS**](https://www.apple.com/macos/) 开发环境依赖。

- 适合 `.command` 双击运行，也可以在终端中执行。
  启动后会先打印内置自述，确认后进入 [**fzf**](https://github.com/junegunn/fzf) 多选菜单。

- 核心原则：

  ```text
  不存在：安装最新版
  已存在：更新到最新版 / 刷新配置
  ```

- 第三方依赖已存在时，会统一确认一次是否升级，不再逐项询问。
  统一范围包括：

  ```text
  brew cask
  brew formula
  npm 全局包
  gem 包
  ```

- 注意：`install` 这个命令名与系统 `$SYSTEM_USR_DIR/bin/install` 存在冲突风险。
  建议保留 `.command` 后缀，或放在明确的工具目录中调用。

## 二、运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 在脚本目录中执行：

  ```zsh
  ./install.command
  ```

- 如果已经自行加入 `PATH`，也可以执行：

  ```zsh
  install.command
  install.command [参数...]
  ```

## 三、Homebrew 第三方配置 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 脚本顶部集中维护 [**Homebrew**](https://brew.sh) 第三方配置。

  ```zsh
  readonly -a BREW_CASKS=(
    hammerspoon
    flutter
    trex
    vlc
    jdownloader
    codex-app # 图形化界面
    codex # 终端使用
    github-store
    jtool2
    motrix
    onlyoffice
    pot
    qlcolorcode
    temurin@17
  )

  readonly -a BREW_FORMULAE=(
    agg
    asciinema
    caddy
    cloudflared
    git-lfs
    gh
    nushell
    rbenv
    ruby
    node
    jenv
    openjdk
    openjdk@17
    openjdk@21
    fvm
    pnpm
    python
    python3
    python-tk@3.14
    pyinstaller
    pyside
    cocoapods
    fastlane
    mysql
    hugo
    yt-dlp
    ffmpeg
    cmake
    graphviz
    sevenzip
    go-task
    uv
    fzf
    glow
    lazygit
    dufs
    git-filter-repo
    nginx
    radare2
  )
  ```

- 维护规则：

  ```text
  brew cask：只在 BREW_CASKS 里写第三方名称
  brew formula：只在 BREW_FORMULAE 里写第三方名称
  ```

- 不要在数组里写完整命令。
  错误写法：

  ```zsh
  brew install git-lfs
  brew install --cask vlc
  ```

  正确写法：

  ```zsh
  git-lfs
  vlc
  ```

- 菜单项会根据这两个数组自动生成，执行时会自动拼出：

  ```zsh
  brew install xxx
  brew install --cask xxx
  ```

- 少数需要 `tap` 或安装后置处理的 cask / formula，由脚本内部函数自动处理，不要在数组里写完整命令。

## 四、当前 brew cask <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- [**Hammerspoon**](https://www.hammerspoon.org/)

- [**Flutter**](https://flutter.dev)

- [**trex**](https://formulae.brew.sh/cask/trex)

- [**VLC**](https://www.videolan.org/vlc/)

- [**JDownloader**](https://formulae.brew.sh/cask/jdownloader)
  下载管理工具，对应：

  ```zsh
  brew install --cask jdownloader
  ```

- [**Codex App**](https://formulae.brew.sh/cask/codex-app)
  图形化桌面工具，对应：

  ```zsh
  brew install --cask codex-app
  ```

- [**Codex CLI**](https://formulae.brew.sh/cask/codex)
  终端工具，对应：

  ```zsh
  brew install --cask codex
  ```

- [**GitHub Store**](https://github.com/OpenHub-Store/GitHub-Store)
  开源的 GitHub Releases 应用商店，对应：

  ```zsh
  brew tap OpenHub-Store/tap
  brew install --cask github-store
  xattr -dr com.apple.quarantine $APPLICATIONS_DIR/GitHub-Store.app
  ```

- `jtool2`
- [**Motrix**](https://motrix.app/)
- [**ONLYOFFICE**](https://www.onlyoffice.com)
- [**Pot**](https://pot-app.com/)
- [**QLColorCode**](https://github.com/sbarex/QLColorCode)
- `temurin@17`

## 五、当前 brew formula <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- [**agg**](https://github.com/asciinema/agg)
- [**asciinema**](https://asciinema.org)
- [**Caddy**](https://caddyserver.com)
- [**cloudflared**](https://github.com/cloudflare/cloudflared)
- [**git-lfs**](https://git-lfs.com)
- [**gh**](https://cli.github.com)
- [**nushell**](https://www.nushell.sh)
- [**rbenv**](https://github.com/rbenv/rbenv)
- [**Ruby**](https://www.ruby-lang.org)
- [**Node.js**](https://nodejs.org)
- [**jenv**](https://www.jenv.be)
- [**OpenJDK**](https://openjdk.org)
- `openjdk@17`
- `openjdk@21`
- [**fvm**](https://fvm.app)
- [**pnpm**](https://pnpm.io)
- [**Python**](https://www.python.org)
- `python3`
- `python-tk@3.14`
- [**PyInstaller**](https://pyinstaller.org)
- [**PySide6**](https://doc.qt.io/qtforpython-6/)：Qt 官方 Python 绑定，Homebrew formula 名为 `pyside`。
- [**CocoaPods**](https://cocoapods.org)：Homebrew formula 名为 `cocoapods`。
- [**fastlane**](https://fastlane.tools)
- [**MySQL**](https://www.mysql.com)
- [**Hugo**](https://gohugo.io)
- [**yt-dlp**](https://github.com/yt-dlp/yt-dlp)
- [**FFmpeg**](https://ffmpeg.org)
- [**CMake**](https://cmake.org)
- [**Graphviz**](https://graphviz.org)
- [**sevenzip**](https://formulae.brew.sh/formula/sevenzip)
- [**go-task**](https://taskfile.dev)
- [**uv**](https://docs.astral.sh/uv/)
- [**fzf**](https://github.com/junegunn/fzf)
- [**Glow**](https://github.com/charmbracelet/glow)：终端 Markdown 阅读器，对应 `brew install glow`。
- [**lazygit**](https://github.com/jesseduffield/lazygit)
- [**dufs**](https://github.com/sigoden/dufs)
- [**git-filter-repo**](https://formulae.brew.sh/formula/git-filter-repo)
  用于重写 / 清理 [**Git**](https://git-scm.com) 仓库历史，例如移除误提交的大文件或敏感内容。
- [**nginx**](https://nginx.org)
- [**radare2**](https://www.radare.org/n/)

## 六、特殊处理 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- [**GitHub Store**](https://github.com/OpenHub-Store/GitHub-Store)
  安装 / 更新前会自动执行：

  ```zsh
  brew tap OpenHub-Store/tap
  ```

  安装 / 更新后会自动执行一次去隔离：

  ```zsh
  xattr -dr com.apple.quarantine $APPLICATIONS_DIR/GitHub-Store.app
  ```

- [**VLC**](https://www.videolan.org/vlc/)
  如果 Homebrew 未登记 `vlc`，但本机已经存在 `/Applications/VLC.app`，脚本会识别为本机已有 App 并跳过重复安装。

- [**fvm**](https://fvm.app)
  安装 / 更新前会自动执行：

  ```zsh
  brew tap leoafarias/fvm
  ```

- [**go-task**](https://taskfile.dev)
  安装 / 更新前会自动执行：

  ```zsh
  brew tap go-task/tap
  ```

  实际安装参数为：

  ```zsh
  go-task/tap/go-task
  ```

- [**rbenv**](https://github.com/rbenv/rbenv)
  安装 / 更新后自动写入初始化配置：

  ```zsh
  eval "$(rbenv init - zsh)"
  ```

- [**jenv**](https://www.jenv.be)
  安装 / 更新后自动写入初始化配置：

  ```zsh
  export PATH="$HOME/.jenv/bin:$PATH"
  eval "$(jenv init -)"
  ```

- [**OpenJDK**](https://openjdk.org) / `openjdk@17`
  安装 / 更新后会输出 [**Java**](https://www.java.com) 配置提示。

- [**fzf**](https://github.com/junegunn/fzf)
  安装 / 更新后自动写入 shell 配置：

  ```zsh
  key-bindings.zsh
  completion.zsh
  ```

## 七、菜单顺序 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- [**fzf**](https://github.com/junegunn/fzf) 菜单固定为按显示顺序从上到下排列。

  ```text
  ✅ 全选安装
  Xcode Command Line Tools
  Xcode iOS 平台组件
  Oh My Zsh
  Homebrew
  brew cask：hammerspoon
  brew cask：flutter
  brew cask：trex
  brew cask：vlc
  brew cask：jdownloader
  brew cask：codex-app
  brew cask：codex
  brew cask：github-store
  brew cask：jtool2
  brew cask：motrix
  brew cask：onlyoffice
  brew cask：pot
  brew cask：qlcolorcode
  brew cask：temurin@17
  brew formula：agg
  brew formula：asciinema
  brew formula：caddy
  brew formula：cloudflared
  brew formula：git-lfs
  brew formula：gh
  brew formula：nushell
  brew formula：rbenv
  brew formula：ruby
  brew formula：node
  brew formula：jenv
  brew formula：openjdk
  brew formula：openjdk@17
  brew formula：openjdk@21
  brew formula：fvm
  brew formula：pnpm
  brew formula：python
  brew formula：python3
  brew formula：python-tk@3.14
  brew formula：pyinstaller
  brew formula：pyside
  brew formula：cocoapods
  brew formula：fastlane
  brew formula：mysql
  brew formula：hugo
  brew formula：yt-dlp
  brew formula：ffmpeg
  brew formula：cmake
  brew formula：graphviz
  brew formula：sevenzip
  brew formula：go-task
  brew formula：uv
  brew formula：fzf
  brew formula：glow
  brew formula：lazygit
  brew formula：dufs
  brew formula：git-filter-repo
  brew formula：nginx
  brew formula：radare2
  Rosetta 2
  npm 全局包：quicktype
  npm 全局包：OpenCLI
  npm 全局包：CodeGraph
  gem 包：cocoapods
  Git LFS 初始化
  JobsKits 仓库
  手动下载页面
  ```

## 八、brew 相关顺序 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- brew 相关部分固定为：

  ```text
  Homebrew
  brew cask：...
  brew formula：...
  ```

- 也就是先处理 [**Homebrew**](https://brew.sh)，再紧接着显示依托 [**Homebrew**](https://brew.sh) 安装的 cask 与 formula 依赖。

- [**Homebrew**](https://brew.sh) 已存在时，选择更新会依次执行：

  ```zsh
  brew update
  brew upgrade
  brew cleanup
  brew doctor
  brew -v
  ```

## 九、交互规则 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 启动菜单前会自检 [**Homebrew**](https://brew.sh) 与 [**fzf**](https://github.com/junegunn/fzf)。

- 缺少 [**Homebrew**](https://brew.sh) 时，会先提示安装 [**Homebrew**](https://brew.sh)。

- 缺少 [**fzf**](https://github.com/junegunn/fzf) 时，会先通过 [**Homebrew**](https://brew.sh) 安装 [**fzf**](https://github.com/junegunn/fzf)。

- 菜单内使用：

  ```text
  Tab 多选
  Enter 确认
  ```

- 选择 `✅ 全选安装` 后，会按菜单顺序依次处理所有部件。

- 缺失依赖仍按部件单独确认安装。

- 已存在的第三方依赖升级会统一确认一次，不再逐项询问。

- 已存在第三方依赖的统一升级范围：

  ```text
  brew cask
  brew formula
  npm 全局包
  gem 包
  ```

- 普通安装 / 更新步骤的确认逻辑：

  ```text
  直接回车：执行安装 / 更新
  输入任意字符后回车：跳过
  ```

## 十、npm 全局包 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `quicktype`
  依赖 [**npm**](https://www.npmjs.com)，如果 `npm` 不存在，会提示先选择：

  ```text
  brew formula：node
  ```

- [**OpenCLI**](https://www.npmjs.com/package/@jackwener/opencli)
  npm 包名为：

  ```text
  @jackwener/opencli
  ```

  安装前会检查 [**Node.js**](https://nodejs.org) 主版本，要求：

  ```text
  Node.js >= 21
  ```

  如果版本不足，脚本会尝试通过 [**Homebrew**](https://brew.sh) 安装 / 升级 `node`。

  安装后会尝试输出版本：

  ```zsh
  opencli --version
  ```

  另外会提示浏览器自动化还需要手动安装 `Browser Bridge` 扩展，安装后可执行：

  ```zsh
  opencli doctor
  ```


- [**CodeGraph**](https://github.com/colbymchenry/codegraph)
  npm 包名为：

  ```text
  @colbymchenry/codegraph
  ```

  不存在时执行安装，已存在且选择统一升级时也执行同一条命令刷新到最新全局版本：

  ```zsh
  npm i -g @colbymchenry/codegraph
  ```

  安装后会尝试输出版本：

  ```zsh
  codegraph --version
  ```

  说明：这里只负责安装 CodeGraph 全局命令；进入具体项目后，如需生成项目索引，再执行：

  ```zsh
  codegraph init -i
  ```

## 十一、gem 包 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- [**CocoaPods**](https://cocoapods.org)
  依赖 [**RubyGems**](https://rubygems.org) 的 `gem` 命令。

  不存在时执行安装：

  ```zsh
  sudo gem install cocoapods
  ```

  已存在且选择统一升级时执行：

  ```zsh
  sudo gem update cocoapods
  ```

## 十二、Git LFS 初始化 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- [**Git LFS**](https://git-lfs.com) 初始化部件会检查：

  ```text
  git
  git lfs
  ```

- 如果 `git-lfs` 不存在，会提示先选择：

  ```text
  brew formula：git-lfs
  ```

- 初始化 / 刷新时会执行：

  ```zsh
  git lfs install
  git config --global core.compression 0
  git config --global http.postBuffer 524288000
  ```

## 十三、JobsKits 仓库 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 默认工作目录：

  ```zsh
  ~/Desktop/JobsKits
  ```

- 会处理以下仓库：

  ```text
  JobsSoftware.MacOS
  JobsMacEnvVarConfig
  ```

- 仓库不存在时会克隆。

- 仓库已存在时会询问是否执行：

  ```zsh
  git pull --ff-only
  ```

- 如果检测到 `JobsMacEnvVarConfig/install.command`，会询问是否添加可执行权限：

  ```zsh
  chmod +x install.command
  ```

- 不会递归执行 `JobsMacEnvVarConfig/install.command`，避免自调用死循环。

## 十四、手动下载页面 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- [**Visual Studio Code**](https://code.visualstudio.com/)

- [**Android Studio**](https://developer.android.com/studio?hl=zh-cn)

- [**Python**](https://www.python.org/downloads/)

- [**Codex++**](https://github.com/BigPizzaV3/CodexPlusPlus)

## 十五、网络前置检查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 安装 [**Homebrew**](https://brew.sh) / [**Oh My Zsh**](https://ohmyz.sh) 前，会检查：

  ```text
  raw.githubusercontent.com
  ```

- 拉取 [**GitHub**](https://github.com) 仓库前，会检查：

  ```text
  github.com
  ```

- 如果网络不可达，脚本会直接提示并退出对应流程，避免后续命令假失败。

## 十六、结构约定 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 运行时打印的自述已经写死在 `install.command` 内部，不依赖同级 `README.md`。

- 本 `README.md` 只用于源码浏览、维护说明和当前流程说明。

- 日志路径：

  ```zsh
  $TMPDIR/install.log
  ```

## 十七、流程图 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 主流程：

  ```mermaid
  flowchart TD
      A([启动 install.command]) --> B[打印内置自述]
      B --> C[等待回车继续]
      C --> D[准备 fzf 菜单运行环境]

      D --> E{Homebrew 是否存在}
      E -->|不存在| E1[提示安装 Homebrew]
      E -->|已存在| E2[加载 Homebrew shellenv]
      E1 --> E2

      E2 --> F{fzf 是否存在}
      F -->|不存在| F1[通过 brew 安装 fzf]
      F -->|已存在| G[显示 fzf 多选菜单]
      F1 --> G

      G --> H{选择内容}
      H -->|选择 ✅ 全选安装| I[展开全部菜单项]
      H -->|手动多选| J[保留已选菜单项]

      I --> K[按菜单顺序逐项处理]
      J --> K

      K --> L{当前部件是否已存在}
      L -->|不存在| M{单项确认安装}
      L -->|已存在且属于第三方依赖| N{本轮是否已统一确认}
      L -->|已存在且非第三方依赖| O{单项确认更新}

      N -->|未确认| P{统一确认是否升级}
      N -->|已确认升级| Q[执行升级]
      N -->|已确认跳过| R[跳过当前部件]

      P -->|直接回车| Q
      P -->|输入任意字符后回车| R

      M -->|直接回车| S[执行安装]
      M -->|输入任意字符后回车| R

      O -->|直接回车| Q
      O -->|输入任意字符后回车| R

      S --> T{是否还有下一个部件}
      Q --> T
      R --> T

      T -->|有| K
      T -->|无| U[输出收尾摘要]
      U --> V([结束])
  ```

- brew 相关部件顺序：

  ```mermaid
  flowchart TD
      A[Homebrew] --> B[BREW_CASKS 自动生成]
      B --> C[BREW_FORMULAE 自动生成]
  ```

- 第三方依赖已存在时的统一升级确认：

  ```mermaid
  flowchart TD
      A[检测到已存在的第三方依赖] --> B{本轮是否已有统一选择}
      B -->|没有| C{是否统一升级}
      C -->|直接回车| D[记录：本轮统一升级]
      C -->|输入任意字符后回车| E[记录：本轮统一跳过]
      B -->|已有统一升级| D
      B -->|已有统一跳过| E
      D --> F[后续已存在依赖直接升级，不再询问]
      E --> G[后续已存在依赖直接跳过，不再询问]
  ```

- [**OpenCLI**](https://www.npmjs.com/package/@jackwener/opencli) 安装流程：

  ```mermaid
  flowchart TD
      A[npm 全局包：OpenCLI] --> B{npm 是否存在}
      B -->|不存在| C[提示先安装 node]
      B -->|存在| D{Node.js 主版本是否 >= 21}
      D -->|否| E[尝试通过 Homebrew 安装 / 升级 node]
      E --> F{升级后是否满足}
      F -->|否| G[跳过 OpenCLI 安装]
      F -->|是| H[安装 / 更新 @jackwener/opencli]
      D -->|是| H
      H --> I{opencli 命令是否可用}
      I -->|可用| J[输出 opencli --version]
      I -->|不可用| K[提示重新打开终端或检查 npm global bin]
  ```

- [**CodeGraph**](https://github.com/colbymchenry/codegraph) 安装流程：

  ```mermaid
  flowchart TD
      A[npm 全局包：CodeGraph] --> B{npm 是否存在}
      B -->|不存在| C[提示先安装 node]
      B -->|存在| D{全局包是否已存在}
      D -->|不存在| E[确认后执行 npm i -g @colbymchenry/codegraph]
      D -->|已存在| F{是否已统一确认升级}
      F -->|统一升级| E
      F -->|统一跳过| G[跳过 CodeGraph]
      E --> H{codegraph 命令是否可用}
      H -->|可用| I[输出 codegraph --version]
      H -->|不可用| J[提示重新打开终端或检查 npm global bin]
  ```

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
