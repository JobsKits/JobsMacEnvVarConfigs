# Flutter SDK网络入口

此私有库供Flutter命令、安装和升级入口source；加载时只定义函数。SDK实际调用才创建任务缓存，以子进程探测原始来源和候选路线，SDK获取失败持续重试，Ctrl+C或终止信号取消。健康缓存直接复用，run/pub/analyze/build只执行一次。

`jobs_flutter_sdk_command 原命令 参数...`保留参数、stdin与退出码；`jobs_flutter_sdk_versions`只读取明确配置的制品源发布清单。Brew Flutter cask从brew真实JSON元数据读取原URL，URL和SHA由Brew校验，不替换下载主机。不source用户配置，不写全局代理或Flutter源。安装器部署整个_lib时自动携带本目录及两个同级模块。
