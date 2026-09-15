# 课表

原生 iOS 17+ SwiftUI 课表应用。它提供按日查看、课程添加/编辑/删除、本机持久化、主屏幕小组件、本地上课提醒，以及锁屏/灵动岛实时活动；首次运行自带可删除的示例课程。

## 在 Mac 上运行

1. 用 Xcode 15 或更高版本打开 `Kebiao.xcodeproj`。
2. 在 Signing & Capabilities 选择你的 Apple 开发团队，并将 App 与 Widget 的 Bundle Identifier 改为自己的唯一标识。
3. 选择 iPhone 模拟器或真机后运行。

课程资料只写入本机 `UserDefaults`，不会上传到网络。

## 主屏幕小组件

工程已含“今日课表”小组件（小号、中号）。在 Xcode 的项目设置里搜索 `APP_GROUP_IDENTIFIER`，把 `group.com.example.kebiao` 改成你在 Apple Developer 后台创建的 App Group；Debug/Release 使用同一个值。然后为 App 和 `KebiaoWidgetExtension` 的 **Signing & Capabilities** 启用同一个 **App Groups**。代码、Info.plist 与 entitlement 都会读取这一个构建设置，课程变更后小组件会自动刷新。

点击小组件会通过 `kebiao://schedule` 返回 App 的课表页。

## 上课提醒与灵动岛

1. 在课程编辑页设置真实的开始时间与提前提醒分钟数。
2. 打开 App 的“提醒”标签，开启上课提醒并允许通知。
3. 支持灵动岛的真机可显示课前倒计时；其他设备显示锁屏实时活动。“预览下一门课的灵动岛”可立即创建一个 5 分钟倒计时用于验收。

本地通知由系统调度，即使 App 没运行也能提醒。iOS 17/18 不允许普通离线 App 在未运行时于任意时刻新建 Live Activity，因此灵动岛会在 App 处于前台或重新进入前台、且已进入课程提醒窗口时启动；要实现完全无人值守的远程启动，需要 APNs 服务端。

## Windows 上的自动编译

`.github/workflows/ios-ci.yml` 会在每次推送、Pull Request 或手动运行时，使用 GitHub 的 macOS Runner 运行单元测试并编译 App、小组件与 Live Activity。该检查为模拟器构建，故意不使用签名证书；成功后可在 Actions 的 Artifacts 下载 `Kebiao-simulator-app`。

发布或安装到真机需要另配 Apple 开发者证书、描述文件和 App Group；请不要把这些文件或密码提交进仓库。
