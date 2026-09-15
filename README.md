# 课表（Kebiao）

原生 iOS 17+ SwiftUI 课表应用。它提供按日查看、课程添加/编辑/删除与本机持久化；首次运行自带可删除的示例课程。

## 在 Mac 上运行

1. 用 Xcode 15 或更高版本打开 `Kebiao.xcodeproj`。
2. 在 Signing & Capabilities 选择你的 Apple 开发团队，并将 Bundle Identifier 改为自己的唯一标识。
3. 选择 iPhone 模拟器或真机后运行。

课程资料只写入本机 `UserDefaults`，不会上传到网络。

## 主屏幕小组件

工程已含“今日课表”小组件（小号、中号）。在 Xcode 的 **Signing & Capabilities** 中，为 App 和 `KebiaoWidgetExtension` 都启用 **App Groups**，并将 `group.com.example.kebiao` 改成与你的 Bundle Identifier 对应、且两个 target 完全相同的 App Group。课程变更后，小组件会自动刷新。

## Windows 上的自动编译

`.github/workflows/ios-ci.yml` 会在推送到 GitHub 的 `main` 分支、创建针对 `main` 的 Pull Request，或手动运行时，使用 GitHub 的 macOS Runner 编译 App 与小组件。该检查为模拟器构建，故意不使用签名证书；成功后可在 Actions 的 Artifacts 下载 `Kebiao-simulator-app`。

发布或安装到真机需要另配 Apple 开发者证书、描述文件和 App Group；请不要把这些文件或密码提交进仓库。
