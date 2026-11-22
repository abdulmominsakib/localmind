# LocalMind X → Codemagic CI + TestFlight 部署清单

> 这是一份**照着点就能做完**的控制台清单。CI 侧的配置文件是仓库根的 `codemagic.yaml`
> （workflow：`ios-testflight`），本文只讲控制台要填什么、字段名必须怎么写、值从哪来。
>
> 本仓库 fork 自 `abdulmominsakib/localmind`，原 Bundle ID `pro.momin.localmind`、
> 原 Team ID `TZX5LG7ZW5` 属于原作者，已全部换掉：Bundle ID 现在是 `top.headwindx.localmind`，
> `ios/Runner.xcodeproj/project.pbxproj` 里的 `DEVELOPMENT_TEAM` 现在是**空占位**（`DEVELOPMENT_TEAM = "";`），
> 由 CI 用环境变量 `XCODE_TEAM_ID` 覆盖（见 §3.4）。

## 0. 仓库正本在哪（先看这段）

- **正本**：`code.headwindx.top`（自建 Gitea）上的 `one/localmind-x`（迁移中；仓库尚未在 Gitea 上创建）。
- 迁移完成后，Codemagic 直接连 Gitea（§2.2 的 HTTPS/SSH 方式），**不再依赖 GitHub OAuth**。
- 迁移前过渡：可以先按 §2.1 用 GitHub 授权接入 `dehengxu/localmind-x`，跑通第一次构建；
  仓库迁到 Gitea 后，把 Codemagic 里的应用重新指向 Gitea 即可（§2.2），CI 配置一行都不用改。
- GitHub 侧的 `dehengxu/localmind-x` 迁移后降级为只读镜像，不再作为构建源。

## 1. 一次性前置条件（Apple 侧，只做一次）

### 1.1 账号

| 条件 | 说明 | 取值来源 |
| --- | --- | --- |
| Apple Developer Program 付费账号 | $99/年；免费账号不能上传 TestFlight | [developer.apple.com/programs](https://developer.apple.com/programs/enroll/) |
| App Store Connect 访问权限 | 上面账号自带 | [appstoreconnect.apple.com](https://appstoreconnect.apple.com) |
| 10 位 Team ID | 签名用，CI 里填进 `XCODE_TEAM_ID` | [developer.apple.com/account](https://developer.apple.com/account) → Membership details → Team ID |
| Codemagic 账号 | [codemagic.io](https://codemagic.io) 注册，按构建分钟计费 | — |

> 计费参考：macOS M2 实例约 $0.015–0.04/分钟，一次 iOS 构建约 20–40 分钟（≈ $0.5–1.5）。
> 免费额度是否覆盖 macOS 机型以 [codemagic.io/pricing](https://codemagic.io/pricing) 实际显示为准。

### 1.2 注册 App ID（Bundle ID）

位置：[developer.apple.com → Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list/bundleId) → Identifiers → 「+」

| 字段 | 填什么 | 说明 |
| --- | --- | --- |
| Type | **App IDs → App** | |
| Description | `LocalMind X` | |
| Bundle ID | **Explicit**：`top.headwindx.localmind` | **必须与 `codemagic.yaml` 的 `environment.ios_signing.bundle_identifier` 完全一致** |
| Capabilities | 勾 **Push Notifications** | 仓库 `ios/Runner/Runner.entitlements` 里有 `aps-environment`，不勾首次导出会报描述文件缺 capability |

### 1.3 创建 App Store Connect API Key（.p8）

位置：[App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api) → **Team Keys** → 「+」

| 字段 | 填什么 | 说明 |
| --- | --- | --- |
| 名称 | `codemagic-ci` | 只在 App Store Connect 侧的名字，随便起；**Codemagic 侧的名字是另一回事，见 §3.2** |
| 角色 | **App Manager** | 签名（建描述文件）+ 上传必需；比 Admin 权限小，够用 |

生成后**立刻下载 `.p8`**（只能下载一次），并记下：

- **Key ID**（10 位，如 `ABC1234567`）
- **Issuer ID**（页面顶部 UUID）

> **不要把 `.p8` / Key ID / Issuer ID 发到聊天、Issue 或仓库里**，只在 Codemagic 控制台上传。

### 1.4 建 App 记录

位置：[App Store Connect → Apps](https://appstoreconnect.apple.com/apps) → 「+」→ New App

| 字段 | 填什么 |
| --- | --- |
| Name | `LocalMind X`（全球唯一，`LocalMind` 已被原作者占用） |
| Language | Simplified Chinese |
| Bundle ID | 选 §1.2 建的 `top.headwindx.localmind` |
| SKU | `localmind-x` |

> 上传后要在这条记录下找 **数字 Apple ID**（App 页面 → App 信息 / URL 里的 `id`），§3.5 要用。

### 1.5 建内部测试组

位置：[App Store Connect → TestFlight → LocalMind X](https://appstoreconnect.apple.com/testflight) → 「+」→ **Internal Testing**

- 分组名必须叫 **`Internal Testers`** —— 与 `codemagic.yaml` 的 `publishing.app_store_connect.beta_groups` 一字不差。
- 再把要测试的 Apple ID 加进 [Users and Access](https://appstoreconnect.apple.com/access/users)（角色 Developer 即可）。
- 内部测试组**不需要 Beta App Review**，构建处理完就能装。

## 2. Codemagic：把仓库接进来

### 2.1 迁移前过渡：GitHub 授权接入

1. [codemagic.io](https://codemagic.io) → **Sign up with GitHub**（用 `dehengxu` 授权，最省事）。
2. **Add application** → 选 **GitHub** → 授权 → **Install GitHub App**（选账号 `dehengxu` → 只选 `localmind-x` 或全部都行）→ **Next: Select repository** → 选 `dehengxu/localmind-x`。
3. 项目类型选 **Flutter App** → **Finish: Add application**。

### 2.2 正本方式：Gitea HTTPS/SSH 接入（迁移后按这个来）

自建 Gitea 没有官方 App，只能走 Codemagic 的 **HTTPS/SSH** 方式：

1. **Add application** → 选 **HTTPS/SSH** → **Next: Select repository**。
2. **Repository URL** 填：`git@git.headwindx.top:one/localmind-x.git`
   （Gitea 仓库页 → **Clone** → SSH 那一行；注意是 `git.headwindx.top`，不是 `code.headwindx.top`）。
3. 点 **Generate key pair** → Codemagic 生成 4096 位密钥对 → **Copy to clipboard** 复制**公钥**。
   （也可以自己上传私钥；用 Generate key pair 更简单，公钥放 Gitea 即可。）
4. 到 Gitea 仓库 → **Settings → Deploy Keys → Add Deploy Key**：
   - Title：随意（如 `codemagic`）
   - Key：粘贴刚才的公钥
   - **勾上 `Write` 权限**（要拉分支才能触发构建；只读只能拉默认分支）
   - 点 **Add Key**
5. 回到 Codemagic → **Next: Select repository** → 选 `one/localmind-x` → 项目类型 **Flutter App** → **Finish: Add application**。
6. 不要在第 3 步之后关掉弹窗，否则要重新生成密钥对。

> 自建 Gitea 的 SSH 端点是 `git.headwindx.top`（22 端口），Codemagic 需要能出网到它。

### 2.3 选 workflow

应用设置 → **Workflow** → 勾 **List user workflows / based on codemagic.yaml** → 选中 `ios-testflight`。
构建触发已配置为「push 到 main」，也可以在应用页手动 **Start build**。

## 3. Codemagic：填签名与应用配置

### 3.1 建 Developer Portal 集成（Apple Developer API Key）

位置：**Team settings → Integrations → Developer Portal** → **Manage keys**

| 字段 | 填什么 | 取值来源 |
| --- | --- | --- |
| **App Store Connect API key name** | **`App Manager`** | **字段名必须一字不差**：与 `codemagic.yaml` 的 `integrations.app_store_connect` 一致。这条是**已存在**的集成（`one/ToMobileScreen` 在用，同一个 Apple 团队），直接复用，不用重建 .p8 |
| Issuer ID | §1.3 的 Issuer ID | appstoreconnect.apple.com → Users and Access → Integrations |
| Key ID | §1.3 的 Key ID | 同上 |
| API key | 上传 `.p8` | §1.3 下载的文件（如果复用现有集成就**不用再传**） |

> 想用新名字也可以，但必须**同时**改 `codemagic.yaml` 里的 `integrations.app_store_connect`，两边必须同名。

### 3.2 应用级环境变量

位置：应用设置 → **Environment variables**

| 变量名 | 值 | 必填？ | 取值来源 |
| --- | --- | --- | --- |
| `XCODE_TEAM_ID` | 你的 10 位 Team ID | 可选但建议填 | developer.apple.com/account → Membership details |
| `APP_STORE_APPLE_ID` | App 的**数字** Apple ID | 可选 | App Store Connect → Apps → LocalMind X → App 信息里的 `id` |

- `XCODE_TEAM_ID`：CI 用它覆盖 `project.pbxproj` 里的 `DEVELOPMENT_TEAM = "";`；不填也能构建（签名团队由
  `xcode-project use-profiles` 按证书/描述文件决定），但填了更可控。格式必须是 10 位字母数字，填错 CI 会直接报错退出。
- `APP_STORE_APPLE_ID`：填了以后，构建号会参考「App Store Connect 上该 app 的最新 build 号」（`one/ToMobileScreen` 就是这么做的）。
  不填也能构建，但构建号只按 Codemagic 计数与 `pubspec.yaml` 推导，手工上传过的构建可能撞号（TestFlight 会拒收重复构建号）。

### 3.3 环境变量组 `app_store`（可选）

`codemagic.yaml` 里引用了一个叫 `app_store` 的环境变量组，里面放 ASC 凭据
（`APP_STORE_CONNECT_PRIVATE_KEY` / `APP_STORE_CONNECT_KEY_IDENTIFIER` / `APP_STORE_CONNECT_ISSUER_ID`），
供构建脚本调 `app-store-connect` CLI 查最新构建号。

- 你的 Codemagic 账号里**已经有**这个组（`one/ToMobileScreen` 在用）→ 不用动。
- 没有 → 把 `codemagic.yaml` 里 `environment.groups` 那两行删掉，构建号自动退回 `PROJECT_BUILD_NUMBER`，不影响其它环节。

### 3.4 Team ID 与工程里的占位符

仓库里的 `ios/Runner.xcodeproj/project.pbxproj` 有 3 处 `DEVELOPMENT_TEAM = "";`（Profile / Debug / Release）。
这是**故意的空占位**：原作者的 Team ID 已移除。

- 本地 Xcode 打开工程 → 选中 **Runner** target → **Signing & Capabilities** → 勾 **Automatically manage signing** → 选你的 Team。
  选完 Xcode 会把这 3 处写成你的 Team ID；**这个改动不要提交**（它含你的 Team ID，且属于本机配置）。
- CI 不依赖上面的本地操作：CI 会用 `XCODE_TEAM_ID` 覆盖这 3 处，再由 `xcode-project use-profiles` 按
  App Store Connect 集成里的证书 + 描述文件把签名配置写回工程。

### 3.5 首次构建

应用页 → **Start build** → 分支选 `main` → workflow 选 `ios-testflight` → 开始。

流水线依次执行：

1. `Override Xcode development team` —— 有 `XCODE_TEAM_ID` 就覆盖工程里的 3 处 Team ID；没配就跳过并打 warning。
2. `Set up code signing settings on Xcode project` —— `xcode-project use-profiles`：从 App Store Connect 集成取
   distribution 证书 + 描述文件（按 `bundle_identifier: top.headwindx.localmind`），写进工程签名设置。
3. `Get Flutter packages` —— `flutter pub get`。
4. `Install pods` —— 在含 `Podfile` 的目录跑 `pod install`（仓库里是 `ios/Podfile`）。
5. `Build IPA` —— `flutter build ipa --release --build-number=<号> --export-options-plist=<路径>`。
   构建号取三者的较大值：`PROJECT_BUILD_NUMBER`、`ASC 最新号 + 1`（需 `APP_STORE_APPLE_ID`）、
   `pubspec.yaml` 里 `version` 的 build 号 + 1（当前 `1.9.1+96` → 97，防止首次构建号低于手工上传过的号）。
   导出配置优先用 `xcode-project use-profiles` 生成的 `/Users/builder/export_options.plist`；
   没有就退回仓库里的 `ios/ExportOptions.plist`（method `app-store` / signingStyle `automatic` / destination `upload`）。
6. 发布：`publishing.app_store_connect`（`auth: integration`）→ 上传并提交到 TestFlight 组 **`Internal Testers`**。

## 4. 验收

1. Codemagic 构建日志全绿，结尾有上传 App Store Connect 成功的提示，Artifacts 里有 `build/ios/ipa/*.ipa`。
2. App Store Connect → TestFlight → LocalMind X → 构建列表出现新 build，处理完成（约 5–15 分钟）后状态变 **Ready to Test**。
3. iPhone 装 TestFlight App → 登录已加入 `Internal Testers` 的 Apple ID → 出现 LocalMind X → Install。
4. 内部测试不需要 Beta 审核，所以到这一步应该已经能装上。

## 5. 排错表

| 现象 | 处理 |
| --- | --- |
| 构建报 `Flutter version 3.44.2 not available` | Codemagic 版本列表落后：`codemagic.yaml` 的 `environment.flutter` 改成 `stable`，或改成控制台 Flutter 下拉里有的版本（仓库 `.fvmrc` 锁的是 3.44.2） |
| `No profiles for 'top.headwindx.localmind' were found` | App ID 没注册 / 勾了 Push Notifications 但描述文件没有该 capability → 重做 §1.2；或 §3.1 的集成没连上 |
| 签名报 team 不符 / `requires a development team` | `XCODE_TEAM_ID` 没配或格式不对（必须 10 位字母数字）→ §3.2；CI 也会把该错误直接打出来 |
| 401 / 403（ASC 相关） | `.p8` / Key ID / Issuer ID 不匹配，或角色不是 App Manager → 重做 §1.3 / §3.1 |
| 上传被拒：`The bundle version must be greater than the previously uploaded version` | 构建号撞号：配 `APP_STORE_APPLE_ID`（§3.2），让号取自 ASC 最新号 + 1；不配则至少靠 `pubspec.yaml` 的 build 号兜底 |
| `No such file or directory: /Users/builder/export_options.plist` | `xcode-project use-profiles` 没跑成 → 看第 2 步日志；仓库里的 `ios/ExportOptions.plist` 是兜底 |
| `pod install` 失败 | CocoaPods 仓库拉取超时；重跑构建，或在本地 `cd ios && pod install` 后再触发 |
| Codemagic 找不到 `app_store` 环境变量组 | 删掉 `codemagic.yaml` 里 `environment.groups` 两行 → §3.3 |
| 上传后 TestFlight 看不到 | App 记录的 Bundle ID 与构建包不一致 → 核对 §1.2 与工程里的 `PRODUCT_BUNDLE_IDENTIFIER`（应为 `top.headwindx.localmind`） |

## 6. 配置对照表（yaml ↔ 控制台）

| `codemagic.yaml` 位置 | 必须一致的值 | 控制台位置 |
| --- | --- | --- |
| `integrations.app_store_connect` | `App Manager` | Team settings → Integrations → Developer Portal → API key 名字 |
| `publishing.app_store_connect.beta_groups` | `Internal Testers` | App Store Connect → TestFlight → 内部测试组名 |
| `environment.ios_signing.bundle_identifier` | `top.headwindx.localmind` | developer.apple.com → App ID |
| `environment.flutter` | `3.44.2`（同 `.fvmrc`） | Codemagic Flutter 版本 |
| `environment.instance_type` | `mac_mini_m2` | Codemagic 构建机型 |
| `XCODE_TEAM_ID` | 10 位 Team ID | 应用 → Environment variables |
| `APP_STORE_APPLE_ID` | 数字 Apple ID | 应用 → Environment variables |
