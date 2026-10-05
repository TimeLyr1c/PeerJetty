# 投到 Mac mini

一个常驻在 MacBook 上的文件投放工具。平时投放区完全收在刘海后方；当你从 Finder 或微信拖起文件时，它会自动从刘海下拉出现。把文件放进去后，应用会通过 SSH/SCP 将文件发送到 Mac mini 的 `~/Downloads`，自动处理同名文件；普通文件会自动打开，可执行文件则只在 Finder 中显示。

模板连接地址：`username@Mac-mini.local`。请在设置面板中替换成接收端 Mac mini 的真实 SSH 地址，例如 `接收端用户名@电脑名称.local`。

## 构建

运行：

```bash
chmod +x build.sh
./build.sh
```

生成的应用位于项目的 `outputs/OpenOnMini.app`。

## 使用

1. 双击运行 `OpenOnMini.app`；默认不会显示投放窗口。
2. 从 Finder 或微信拖起文件，投放区会从刘海下方自动出现，再将文件放进去。
3. 普通文件会进入 Mac mini 的下载目录并自动打开；App、安装包、磁盘映像、命令文件及其他带可执行权限的文件只会在 Finder 中显示，不会自动运行。
4. 首次使用前，在“系统设置 → 隐私与安全性 → 完全磁盘访问权限”中加入并启用 `OpenOnMini.app`。
5. App 首次启动不会显示设置窗口；在 App 已运行时再次双击它，即可打开设置。

设置面板中可以修改 SSH 地址、测试连接、临时显示投放区、开启或关闭登录时自动启动，以及退出应用。App 不会在菜单栏放置额外图标。

如果文件已经发送成功、但 Mac mini 没有能够打开它的应用，投放区会显示“已发送，但无法自动打开”，不会再弹出错误对话框。

App 使用完全磁盘访问权限直接读取微信容器里的拖拽文件并交给 SCP，不再通过临时复制、Finder 自动化或 Automator 快速操作绕行。

应用使用系统现有的 SSH 密钥，不会保存 Mac mini 密码。

## 分享版初始化

这是去除个人信息后的 Starter。首次交给另一台 MacBook 使用时：

1. 在接收端 Mac mini 的“系统设置 → 通用 → 共享”中开启“远程登录”，确认允许对应用户登录。
2. 在 MacBook 的终端中先验证 `ssh 用户名@主机名.local` 可以连接；建议配置 SSH 密钥登录。
3. 如需更换默认值，修改 `OpenOnMini.swift` 中的 `defaultTarget`；也可以构建后在设置面板中保存地址。
4. 把 `Info.plist` 中的 `com.example.OpenOnMini` 换成自己的唯一 Bundle ID。
5. 运行 `./build.sh`，然后只在 MacBook 上启动 `outputs/OpenOnMini.app`。
6. 给构建后的 App 开启“完全磁盘访问权限”，用于读取微信容器中的拖拽文件。

不要在 Mac mini 上运行投放应用；Mac mini 只作为 SSH/SCP 接收端。
