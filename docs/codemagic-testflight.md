# LocalMind X → Codemagic CI + TestFlight 部署指引

> 本仓库已带 `codemagic.yaml`（workflow：`ios-testflight`），本文是把它跑通需要做的
> Apple 侧 + Codemagic 侧手动配置。**重要**：本仓库 fork 自 `abdulmominsakib/localmind`，
> 原 Bundle ID `pro.momin.localmind` 和原 DEVELOPMENT_TEAM 均属原作者，本项目已改为
> Bundle ID `top.headwindx.localmind`，Team ID 需换成你自己的（见 3.4）。

## 一、前置条件

| 条件 | 说明 |
| --- | --- |
| **Apple Developer Program 付费账号**（$99/年） | TestFlight 发布的硬性要求；免费账号只能真机调试，不能上传 TestFlight |
| App Store Connect 访问权限 | 上面账号自带 |
| GitHub 账号（dehengxu） | Codemagic 用 GitHub OAuth 连仓库 |
| Codemagic 账号 | [codemagic.io](https://codemagic.io) 注册，无付费墙，按构建分钟计费 |

计费参考：macOS M 系列实例约 $0.015–0.04/分钟，一次 iOS 构建约 20–40 分钟（≈ $0.5–1.5）。
免费额度是否覆盖 macOS 机型以 [codemagic.io/pricing](https://codemagic.io/pricing) 实际显示为准。

## 二、Apple Developer / App Store Connect 准备

### 2.1 注册 App ID（Bundle ID）

[developer.apple.com → Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list/bundleId) → Identifiers → 「+」：

- Type 选 **App IDs → App**
- Description：`LocalMind X`
- Bundle ID：**Explicit**，填 `top.headwindx.localmind`
- Capabilities 勾选 **Push Notifications**（Info.plist 有 `aps-environment`，不勾首次签名导出会报错）

### 2.2 生成 App Store Connect API Key

[appstoreconnect.com → Users and Access → Integrations](https://appstoreconnect.apple.com/access/integrations/api) → **Team Keys** → 「+」：

- 名称：`codemagic-ci`；角色选 **App Manager**（签名 + 上传必需）
- 生成后**立即下载 .p8 文件**（只能下载一次），并记下两个 ID：
  - **Key ID**（10 位）
  - **Issuer ID**（页面顶部，UUID 格式）

### 2.3 创建应用记录

[App Store Connect → Apps](https://appstoreconnect.apple.com/apps) → 「+」→ New App：

- Name：**LocalMind X**（全球唯一；`LocalMind` 已被原作者占用）
- Language：Simplified Chinese
- Bundle ID：选 2.1 注册的 `top.headwindx.localmind`
- SKU：`localmind-x`

> TestFlight 构建会挂在这条记录下；后续正式上架也复用它。名称、图标、截图等可以之后再补，
> 但 **TestFlight 对外测试需要填完隐私政策等信息**；仅内部测试不强制。

### 2.4 创建内部测试组

[App Store Connect → Users and Access → Users](https://appstoreconnect.apple.com/access/users) 里把要测试的 Apple ID 加为 App Manager / Developer；
然后 [TestFlight → LocalMind X](https://appstoreconnect.apple.com/testflight) → 「+」添加 **Internal Testing** 分组，命名为 **`Internal Testers`**
（必须与 `codemagic.yaml` 中 `beta_groups` 的名字一致），把已添加的用户加入该组。

> 内部测试组构建**无需 Beta App Review**，上传处理完即可安装；外部测试组才需要审核。

## 三、Codemagic 配置

### 3.1 注册并连接仓库

1. 打开 [codemagic.io](https://codemagic.io) → **Sign up with GitHub**（用 dehengxu 账号授权，省去配 SSH key）。
2. 登录后 Add application → 选 `dehengxu/localmind-x` → 项目类型选 **Flutter App**。

### 3.2 添加 App Store Connect 集成

右上角头像 → **Teams → Integrations → App Store Connect**（Developer Portal 部分）：

- Issuer ID：2.2 的 Issuer ID
- Key ID：2.2 的 Key ID
- 上传 `.p8` 私钥文件
- **Key 名称必须叫 `LocalMind ASC API Key`** —— 与 `codemagic.yaml` 里
  `integrations.app_store_connect:` 的值一致，CI 靠这个名字引用。

### 3.3 选择 workflow（yaml 模式）

添加应用时或应用设置里：勾选 **List user workflows / based on codemagic.yaml** → 选中 `ios-testflight`。
构建触发已配置为「push 到 main」，也可随时在应用页手动 **Start build**。

### 3.4 配置 Team ID 环境变量（关键）

仓库里 Xcode 工程的 `DEVELOPMENT_TEAM` 还是原作者的 `TZX5LG7ZW5`，CI 会在构建前用
环境变量覆盖它。应用设置 → **Environment variables** 添加：

| Key | Value | 备注 |
| --- | --- | --- |
| `XCODE_TEAM_ID` | 你的 10 位 Team ID | 在 [developer.apple.com/account](https://developer.apple.com/account) Membership details 页查看 |

> 建议同时把本地仓库 `ios/Runner.xcodeproj/project.pbxproj` 里的 3 处
> `DEVELOPMENT_TEAM = TZX5LG7ZW5` 改成你的 Team ID，本地 Xcode 构建才正常。

### 3.5 启动第一次构建

Start build → 选 `main` 分支 + `ios-testflight` workflow。流水线依次执行：

1. 覆盖 DEVELOPMENT_TEAM → 2. `flutter packages pub get` → 3. `flutter build ipa`
   （构建号取 Codemagic 自增的 `PROJECT_BUILD_NUMBER`，保证 TestFlight 要求的 CFBundleVersion 递增）
2. `xcode-project use-profiles` 自动签名：首次构建会自动创建 distribution 证书 + 描述文件
3. 上传 App Store Connect → 自动提交到 TestFlight 的 `Internal Testers` 组

## 四、验证

1. Codemagic 构建日志全绿，结尾出现 TestFlight 提交成功提示。
2. App Store Connect → TestFlight → 该 build 处理完成（约 5–15 分钟，状态变 **Ready to Test**）。
3. iPhone 装 TestFlight App → 登录已加入 `Internal Testers` 的 Apple ID → LocalMind X 出现 → Install。

## 五、注意事项

- **推送通知**：App ID 开了 Push Notifications capability 即可上传安装；真机收推送还需要在
  Developer Portal 生成 APNs Key 并配到服务端，TestFlight 本身不校验。
- **构建号冲突**：重复上传相同 build 号会被拒；本项目用 `PROJECT_BUILD_NUMBER` 自动递增避免。
- **手动触发新版本**：改版本号只需改 `pubspec.yaml` 的 `version: 1.9.1+96`（+ 后的 build 号在 CI 被覆盖）。
- **首次上架 App Store**：应用记录需补全截图、描述、隐私问卷后走 App Review，与本 CI 流程无关。

## 六、常见问题排查

| 现象 | 处理 |
| --- | --- |
| `No profiles for 'top.headwindx.localmind' were found` | App ID 未注册或没勾 Push Notifications → 重做 2.1 |
| API key 相关 401/403 | `.p8`/Key ID/Issuer ID 不匹配，或 API Key 角色不是 App Manager → 重做 2.2 |
| 签名阶段报 team 不符 | Codemagic 环境变量 `XCODE_TEAM_ID` 没配或填错 → 检查 3.4 |
| 上传后 App Store Connect 看不到 | 记录的 Bundle ID 与构建包不一致 → 核对 2.1 与仓库 pbxproj |
| `flutter: 3.44.0` 在 Codemagic 找不到 | Codemagic 会按需安装；若报版本不存在，把 yaml 里 `flutter:` 改成其控制台列出的最近版本 |
| 本地 `flutter build ipa` 报签名错 | 本地没覆盖 DEVELOPMENT_TEAM → 手动改 pbxproj 的 3 处 Team ID |
