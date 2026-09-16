# 课表

原生 iOS 17+ SwiftUI 课表应用。它提供周课表、课程添加/编辑/删除、本机持久化、本地上课提醒，以及锁屏/灵动岛实时活动；首次运行自带可删除的示例课程。

## 在 Mac 上运行

1. 推荐用 Xcode 26 或更高版本打开 `Kebiao.xcodeproj`；Xcode 15/16 仍可构建 iOS 17/18 兼容功能。
2. 在 Signing & Capabilities 选择你的 Apple 开发团队，并将 App 与 Widget 的 Bundle Identifier 改为自己的唯一标识。
3. 选择 iPhone 模拟器或真机后运行。

课程资料只写入本机 `UserDefaults`，不会上传到网络。

## 上课提醒与灵动岛

1. 在课程编辑页设置真实的开始时间与提前提醒分钟数。
2. 打开 App 的“提醒”标签，开启上课提醒并允许通知。
3. 支持灵动岛的真机可显示课前倒计时；其他设备显示锁屏实时活动。“预览下一门课的灵动岛”可立即创建一个 5 分钟倒计时用于验收。

本地通知由系统调度，即使 App 没运行也能提醒。iOS 26 会预先安排下一门课的 Live Activity，到课前时间由系统自动启动灵动岛；iOS 17/18 则在 App 处于前台或重新进入前台、且已进入课程提醒窗口时启动。旧系统若要完全无人值守地远程启动，需要 APNs 服务端。

Live Activity 的课程名称、上课时间、教学楼和节次通过 ActivityKit 内容直接传给系统，不依赖 App Group。当前发布版特意不注册主屏幕课表小组件，也不声明 App Group entitlement，以便免费 Apple ID 能通过 Sideloadly 给主 App 和嵌套扩展重新签名。

## 使用 Sideloadly 安装

导入 Release IPA 后使用 `Apple ID Sideload`，保持 `Dropping 0 of 1 plugins`，不要删除 `KebiaoWidgetExtension.appex`。安装并首次打开 App 后，到“提醒”页点击“预览下一门课的灵动岛”进行验收。免费 Apple ID 签名通常只有 7 天有效期，需要定期刷新。

## Windows 上的自动编译

`.github/workflows/ios-ci.yml` 会在每次推送、Pull Request 或手动运行时，使用 GitHub 的 macOS Runner 运行单元测试，编译 App 与 Live Activity，并检查扩展已嵌入且没有 App Group 依赖。该检查为模拟器构建，故意不使用签名证书；成功后可在 Actions 的 Artifacts 下载 `Kebiao-simulator-app`。

Actions 产出的 IPA 未签名，安装到真机前仍需由 Sideloadly 等工具重新签名。若以后恢复能自动读取课程的主屏幕小组件，则需要付费开发者账号为主 App 与 Widget 扩展配置同一个 App Group；证书、描述文件和密码不得提交进仓库。
