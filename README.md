# 课表

原生 iOS 17+ SwiftUI 课表应用。它提供周课表、课程添加/编辑/删除、本机持久化、本地上课提醒、主屏幕“今日课表”小组件，以及锁屏/灵动岛实时活动；首次运行自带可删除的示例课程。

## 在 Mac 上运行

1. 推荐用 Xcode 26 或更高版本打开 `Kebiao.xcodeproj`；Xcode 15/16 仍可构建 iOS 17/18 兼容功能。
2. 在 Signing & Capabilities 选择你的 Apple 开发团队，并将 App 与 Widget 的 Bundle Identifier 改为自己的唯一标识。
3. 为两个 target 注册并启用相同的 App Group（默认 `group.com.example.kebiao`），确保它包含在两者的签名和 provisioning profile 中。
4. 选择 iPhone 模拟器或真机后运行。

课程资料只写入本机 `UserDefaults`，不会上传到网络。App 使用统一浅色外观。ICS 支持单次事件、按日/周重复、INTERVAL、COUNT、UNTIL、EXDATE、RDATE 和命名时区；无法支持的复杂重复规则会提示并跳过。没有结束日期的重复事件仅导入 30 周，其他重复事件最多展开两年。

## 上课提醒与灵动岛

1. 在课程编辑页设置真实的开始时间与提前提醒分钟数。
2. 打开 App 的“提醒”标签，开启上课提醒并允许通知。
3. 支持灵动岛的真机可显示课前倒计时；其他设备显示锁屏实时活动。“预览下一门课的灵动岛”可立即创建一个 5 分钟倒计时用于验收。

在“提醒”页设置学校本学期第一周内的日期；课表、通知和小组件共用该学期周次。通知按课程有效周次和具体日期安排，最多保留最近 60 次；每次打开 App 时会补排，长期不打开 App 可能耗尽已安排的通知。本地通知由系统调度，已安排的通知即使 App 没运行也能提醒。iOS 26 会预先安排下一门课的 Live Activity，到课前时间由系统自动启动灵动岛；iOS 17/18 则在 App 处于前台或重新进入前台、且已进入课程提醒窗口时启动。旧系统若要完全无人值守地远程启动，需要 APNs 服务端。

“今日课表”小组件提供小号和中号布局，读取 App Group 中共享的课程数据；课程有变更时 App 会请求 WidgetKit 更新时间线。WidgetKit 按系统时间线预算刷新，因此显示可能稍晚于课程编辑。Live Activity 的课程名称、上课时间、教学楼和节次通过 ActivityKit 内容直接传给系统，不依赖 App Group。

## 使用 Sideloadly 安装

导入 Release IPA 后使用 `Apple ID Sideload`，保持 `Dropping 0 of 1 plugins`，不要删除 `KebiaoWidgetExtension.appex`。安装并首次打开 App 后，到“提醒”页点击“预览下一门课的灵动岛”进行验收；主屏幕长按后选择“编辑”>“添加小组件”>“课表”即可添加“今日课表”。Widget 需要签名配置允许 App Group `group.com.example.kebiao`；免费 Apple ID 的 Sideloadly 签名可能无法授予该 entitlement，遇到小组件缺失或无课程时需使用包含此 App Group 的 provisioning profile。免费 Apple ID 签名通常只有 7 天有效期，需要定期刷新。

## Windows 上的自动编译

`.github/workflows/ios-ci.yml` 会在每次推送、Pull Request 或手动运行时，使用 GitHub 的 macOS Runner 运行单元测试，编译 App 与 WidgetKit 扩展，并检查“今日课表”及 Live Activity 已注册、小组件共享数据所用的 App Group 已配置、扩展已嵌入。该检查为模拟器构建，故意不使用签名证书；成功后可在 Actions 的 Artifacts 下载 `Kebiao-simulator-app`。

Actions 产出的 IPA 未签名，安装到真机前仍需由 Sideloadly 等工具重新签名。真机上使用小组件时，签名所用开发团队必须注册 App Group，并在 App 与 Widget 扩展的 provisioning profile 中包含它；证书、描述文件和密码不得提交进仓库。
