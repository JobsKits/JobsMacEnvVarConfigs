# SDK网络适配隔离回归

执行`zsh flutter_sdk_network_tests.zsh`。测试将实际适配器复制到含中文和空格的临时包，网络模块和SDK/Brew/FVM全部替换为假命令，验证预检顺序、FVM参数、原始cask URL、stdin、失败码、业务一次执行和source不下载。测试仅清理自建临时目录，不联网、不安装真实工具。
