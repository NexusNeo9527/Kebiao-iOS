# 学校网页登录兼容性：v1.4.2（18）

本轮针对重庆理工大学完成登录后出现“未知设备”的问题，在 v1.4.1 的基础上完善浏览器身份与 SSO 会话。App 与 Widget 同步至 1.4.2（18），保留 iOS 17+。

## 与 WakeUp 的区别和选择

| 项目 | WakeUp 官方公开方式 | 本项目及本轮处理 |
| --- | --- | --- |
| 入口和适配 | 先选学校，按学校弹窗说明登录；指定学校失败后再尝试通用教务类型。 | 保留重庆理工大学办事大厅入口及其他学校自定义地址，完成学校自己的登录流程。 |
| 认证 | 多数学校在网页登录，部分学校直接输入账号导入。 | 用户在 App 内的 WebKit 网页输入账号和验证码；App 不代发认证请求，不读取或记录密码。 |
| 课程读取 | 打开完整课表后导入并核对；也提供 HTML 文件导入。 | 复用现有网页课表提取和预览，登录异常时先处理网页登录状态；外部浏览器导出课表文件是独立后备方式。 |
| 浏览器实现 | 官方文档没有公开当前 iOS 的 UA、Cookie、新窗口或重庆理工大学私有适配实现。 | 使用真实 WebKit 设备/系统身份，仅补识别所需的 Safari 标识，并在新窗口首个请求前继承；保留 WebKit 的认证上下文。 |

选择继续使用 App 内网页登录、本地课表读取，并补齐学校入口、新窗口和会话重置。单纯把网页换成 Safari 不能让 App 读取 Safari 的登录 Cookie 或课表 DOM；固定伪装成 Windows/Chrome 也会让设备和系统身份不一致。

公开资料：[WakeUp 教务导入](https://wakeup.fun/doc/import_from_eas.html)、[HTML 导入](https://wakeup.fun/doc/import_from_html.html)、[现行隐私政策](https://www.wakeup.fun/policy.html)。官方重庆理工大学条目位于 [Android/鸿蒙适配名单](https://wakeup.fun/doc/adapt_android_hmos.html)，不能据此宣称它的 iOS 私有适配方式已公开。

## 已确认的学校脚本行为

2026-10-11 读取重庆理工大学公开办事大厅及其当时的静态资源：

- `https://ehall.cqut.edu.cn/new_office_hall/`
- `static/js/vendor.57c5e79c3fa915afbf2d.js`
- `static/js/app.16799920d416e44ada0b.js`

门户的浏览器分类器从 `navigator.userAgent` 得到 `browser`、`browserVersion`、`os`、`device`；App 脚本用它生成 `equipmentName`，在登录票据交换 `/officeHallPageHome/uap/check/{ticket}` 中发送。用公开资源的原始分类器执行最小复现：裸 iPhone WK UA 没有 `browser`，补 Safari 标识后得到 Safari、iOS、Mobile 与真实系统版本。此前修复已覆盖根页面；新窗口首脚本与完整认证跳转需要额外验证。

公开资源仅用于本地诊断，未把完整学校脚本或任何账号、票据和 Cookie 提交到仓库。

## 实现和回归重点

- 根页面首次导航前准备可识别的浏览器身份；新窗口同步继承，防止登录首脚本生成空设备名称。
- `window.open` 使用 WebKit 提供的配置创建新网页，并交由 WebKit 加载原始请求，保留 `window.opener`、消息与关闭行为。避免把弹窗请求强行重发到原页面。
- 当前认证导航保留票据、查询参数及请求方法；安全地址显示和历史入口清理不改变正在执行的认证请求。
- 网页提示未知设备、登录失效或仍在密码登录页时，不把它当课表读取成功。
- 用户确认重新登录后，仅清除学校入口绑定范围内的网站数据，重新从稳定入口建立会话；重庆理工大学覆盖 `cqut.edu.cn` 下的认证与办事大厅。未明确支持的域保守限定为入口主机，访问外校或托管租户不会扩大清理范围。其他学校资料和课表保留。
- 回归检查真实 WebKit 根/子窗口首脚本、消息、关闭、票据/POST 和网站数据隔离，以及原有课表导入与小组件检查。

Apple 的 [新窗口代理文档](https://developer.apple.com/documentation/webkit/wkuidelegate/webview%28_%3Acreatewebviewwith%3Afor%3Awindowfeatures%3A%29) 要求用传入配置创建并返回新 WebView；由 WebKit 加载导航请求。

## 验收边界

Windows 本地可运行门户脚本回归和静态检查；Swift、WebKit 与界面由 GitHub macOS CI 验证。最终 CI、截图和未签名 IPA 的验收记录保存在本轮独立草稿 PR。

没有使用用户真实账号执行学校认证。完成登录后的真实跳转、验证码、校园网络限制及学校服务端设备校验仍需用户在签名设备上复验。自动回归证明已覆盖的兼容行为，不能承诺学校以后改变认证策略也不会报错。
