# Flutter DDNS 客户端设计方案

## 目标
实现一个完全自包含、多平台（iOS, Android, Windows, Linux, macOS、HarmonyOS/OpenHarmony）、高度可配置、具备企业级 UX/UI，支持桌面端最小化到系统托盘，并支持跟随系统启动的 DDNS 客户端。

## 架构设计
*   **模式：** 模块化、分层架构（UI -> State/Logic -> Service -> Data）。
*   **状态管理：** Riverpod。
*   **服务抽象：** `IDDNSService` 接口 + `ConfigurableDDNSService` 实现，支持任意自定义 API。
*   **调度抽象：** `Scheduler` 接口（`MobileScheduler` / `DesktopScheduler`），实现平台差异化调度。

## 核心组件
1.  **`DDNSConfig`：** 包含 `hostname`, `serviceType`, `apiUrl`, `apiKey`, `updateRequestConfig` (JSON)，以及 `startOnSystemBoot` (bool)。
2.  **`ConfigurableDDNSService`：** 负责基于配置动态构建 HTTP 请求和响应解析，不依赖特定服务商的硬编码 API。
3.  **`DDNSManager`：** 核心业务逻辑，依赖 `IDDNSService`。
4.  **`Scheduler`：** 负责定时任务。移动端使用 `flutter_background_service`；桌面端使用 `Timer.periodic`。

## 多平台实现细节
*   **移动端 (iOS/Android)：** 使用 `flutter_background_service` 实现后台持续运行和定时任务。系统启动由平台权限和用户设置控制。
*   **桌面端 (Win/Linux/macOS)：**
    *   **托盘：** 使用 `tray_manager` 实现最小化到系统托盘，并处理托盘事件（打开/退出）。
    *   **定时任务：** 使用 `Timer.periodic` 在应用持久运行时执行。
    *   **系统启动：** 保存偏好后，由平台管理器注册 Windows Task Scheduler、Linux systemd 用户服务或 macOS LaunchAgent；退出应用不会删除用户配置。

## 用户体验 (UX/UI)
*   **配置界面：** 结构化表单 + **API 模板选择** + **参数 JSON 输入**，简化复杂 API 配置。
*   **实时反馈：** 企业级 Material 3 仪表盘，实时展示 IP、状态（颜色区分）、上次更新时间、清晰的非技术性错误日志。
*   **托盘交互：** 托盘图标提供快速状态概览和操作入口。

## 实施计划
1.  **阶段一：** 基础架构和数据模型实现。
2.  **阶段二：** 调度器和多平台生命周期管理（集成 `tray_manager`）。
3.  **阶段三：** UX/UI 界面设计和配置逻辑实现。
4.  **阶段四：** 集成、单元测试、端到端验证及部署指南交付。

## 正式发布版 1.0.0

### GitHub Actions 自动发布

- Pull request、推送到 `main` 及手动触发会运行依赖锁定检查、静态分析、完整测试和 Windows x64 Release 构建。
- 推送与 `pubspec.yaml` 版本一致的 `vX.Y.Z` 标签（例如 `v1.0.0`）后，检查通过会自动创建 GitHub Release，并附上 `Nebula-DDNS-X.Y.Z-Windows-x64.zip`。
- 当前自动分发仅覆盖 Windows x64；其他平台须在相应工具链和设备上单独验证后再加入发布流程。
- Windows ZIP 属于通用构建产物，本项目不将其发布到 GitHub Packages；按当前分发方式使用 GitHub Releases。

### 发布内容

- 桌面端支持系统托盘、周期更新及 Windows Task Scheduler、Linux systemd 用户服务、macOS LaunchAgent 开机启动。
- Android 使用前台服务进行周期更新；iOS 使用系统后台 Fetch，受操作系统调度限制，不能保证固定间隔。
- API 密钥保存于 Flutter Secure Storage；非敏感配置保存于 SharedPreferences。恢复旧版配置时会将遗留密钥迁移到安全存储。
- 发布前运行静态分析、完整测试，并在对应平台执行原生构建和实机验证。

### 构建与验证

```shell
flutter pub get
flutter analyze
flutter test
```

Windows:

```powershell
flutter build windows --release
```

Android（Windows 可构建；Release 发布需配置真实签名）:

```powershell
flutter build apk --debug
flutter build appbundle --release
```

正式 Android Release 签名：将 `android/key.properties.example` 复制为 `android/key.properties`，填写自己的 JKS 路径、密码和别名。不要提交 `key.properties` 或 keystore 文件。当前 Gradle 配置在未提供签名配置时使用 Debug 签名，只适用于本地验证，不可作为商店发布包。

Linux:

```shell
flutter build linux --release
```

Linux 构建须在 Linux 主机上执行，并安装 GTK、系统托盘和安全存储所需开发依赖（Ubuntu/Debian 示例）：

```shell
sudo apt-get update
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev libayatana-appindicator3-dev
```

macOS 和 iOS 构建须在安装 Xcode 与 CocoaPods 的 macOS 主机上执行：

```shell
flutter build macos --release
flutter build ios --release
```

iOS 发布还需 Apple Developer 账号、有效证书、Provisioning Profile 和 Xcode 签名设置。iOS Background Fetch 由系统择机执行，通常约 15 分钟或更长间隔，不能作为持续后台定时器。

#### HarmonyOS / OpenHarmony 原生 HAP

原生 HAP 使用 CPF-Flutter 的 OpenHarmony SDK，不使用上游 Flutter SDK。目标 API、DevEco Studio 和 CPF-Flutter 版本必须采用其当前兼容矩阵中相互匹配的版本；本项目目标为 API 18 / DevEco Studio 5.1。安装并配置对应工具链后，在 Windows PowerShell 中运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\platforms\ohos\build_hap.ps1 -Mode release
```

脚本会在被忽略的 `build\openharmony\app` 下生成 OHOS 工程并构建 HAP，不会把生成的原生工程文件写入源码目录。Pub 默认使用系统缓存，也可通过 `PUB_CACHE` 指定缓存目录。HAP 的签名、设备安装、配置持久化、安全密钥读写和手动 DDNS 更新仍须在 API 18 设备/对应 CI 上完成验收；OHOS 后台常驻和系统托盘不属于此基础支持。

OHOS 壳工程通过固定 Git commit 的 [shared_preferences_ohos](https://github.com/naizhao/shared_preferences_ohos/commit/1562f7cc77e3bd2ca467ed2a927ee3497f3d96bf) 与 [flutter_secure_storage_ohos](https://github.com/ClosedHarmony/flutter_secure_storage_ohos/commit/545fb022eed8ce7891028d4851a617b9a8328177) 适配配置和密钥存储。两者是社区插件，不属于 Flutter 上游；发布前须在目标设备验证配置读写、密钥写入/读回、升级迁移及失败提示，不得改用明文存储作为回退方案。

### 平台安装与排障

#### Windows

使用 `build\windows\x64\runner\Release\nebuladdnsa.exe` 及同目录运行时文件。应用注册名为 `NebulaDDNSClient` 的当前用户登录任务。可用以下命令检查：

```powershell
schtasks /Query /TN NebulaDDNSClient
```

启用自启前请将应用放在固定路径；移动或删除程序后应更新/注销任务。

#### Linux

应用在 `~/.config/systemd/user/nebula-ddns.service` 写入用户级服务。检查状态：

```shell
systemctl --user status nebula-ddns.service
```

桌面会话需支持 systemd user services；程序路径变更后应重新注册。

#### macOS

应用在 `~/Library/LaunchAgents/nebula.ddns.client.plist` 创建用户启动项。构建需使用 Xcode；应用包位置应保持稳定。检查状态：

```shell
launchctl list nebula.ddns.client
```

#### Android

后台前台服务会显示持续通知。若更新被系统暂停，请检查通知/后台服务权限、电池优化和厂商自启动策略。Android 可在 Windows 上构建，但首次构建需要 Android SDK、Java、Gradle 插件和 Maven 依赖可正常下载。

#### iOS

需在 Xcode 中启用 `dev.flutter.background.refresh` 对应的 Background Fetch 配置和签名能力。系统可能暂停或延迟后台任务，应用无法保证应用挂起后的固定更新周期。

#### 常见错误

- `Network or Parsing Error`：检查网络、DNS、代理和 TLS 证书。
- HTTP `401/403`：检查账号凭据及 API Token 权限。
- HTTP `429`：服务端限流；客户端按指数退避策略重试。
- Android Gradle 下载失败：检查到 Gradle Plugin Portal、Google Maven、Maven Central 的网络、DNS 和 TLS 连接。
- 在 Windows 上构建 Linux/macOS/iOS 失败：属于 Flutter 原生工具链限制，请使用相应操作系统或 CI Runner。

### 平台与 ARM 架构支持确认（2026-11）

Flutter 上游的支持矩阵列有 Android `arm32/arm64`、Windows `x64/arm64`、macOS `x64/arm64`，以及 Debian/Ubuntu Linux `x64/arm64`。这只表示 Flutter SDK 支持这些目标，不代表项目依赖的每个原生插件都支持目标平台，也不代表本项目已在这些架构上完成构建或实机验收。请以 [Flutter 官方平台支持矩阵](https://docs.flutter.dev/reference/supported-platforms) 和各插件的平台声明为准。

| 目标平台 / 架构 | 特殊构建要求 | 本项目验证状态 |
| --- | --- | --- |
| Android ARM32/ARM64 | 可从 Windows/Linux/macOS 主机交叉构建；需要 Android SDK、NDK 和可下载的 Gradle 依赖。APK/AAB 中的 ABI 由构建选项和打包方式决定；发布需用正式密钥签名。还需在目标设备上验证后台服务和厂商省电策略。 | 本机 Android Debug 构建仍因无法解析 `plugins.gradle.org`、下载 Kotlin Gradle 插件失败；ARM 架构产物未验证。 |
| Windows ARM64 | 需要 Windows 构建环境及能生成 ARM64 目标的 Visual Studio C++ 工具链；依赖的插件及本地二进制也必须提供 ARM64 实现。发布前应在 ARM64 Windows 设备上验证安装、托盘和开机启动。 | 只验证过 Windows x64 Release；当前产物位于 `build\windows\x64\...`，不能据此认定 ARM64 已构建。 |
| Linux ARM64 | Flutter 上游支持指定的 Debian/Ubuntu ARM64 目标。建议在相应 ARM64 Linux 主机或匹配的 CI Runner 构建；从 x64 主机交叉构建通常还需配置 C/C++ 交叉工具链、GTK 开发库及目标架构依赖，不能只靠 Flutter 命令自动完成。 | 未构建或实机验证。 |
| macOS ARM64 | 需要 macOS 和 Xcode。签名、沙盒权限及公证要求取决于分发渠道；还需确认所用原生插件包含 arm64 支持。 | 未构建或实机验证。 |
| iOS ARM64 | 需要 macOS、Xcode 和 Apple 签名/配置文件；设备发布包及后台 Fetch 行为需要真机验证。 | 未构建或实机验证。 |
| HarmonyOS / OpenHarmony | 不是上游 Flutter 的标准构建目标。使用 CPF-Flutter OpenHarmony SDK、匹配的 OpenHarmony SDK/DevEco 工具链和 HAP 发布流程；普通 Android APK 兼容运行不等于原生 HAP。构建入口为 `platforms/ohos/build_hap.ps1`，生成的 OHOS 工程位于忽略的 `build/openharmony/app`。 | 已添加 HAP 壳工程和构建脚本，并固定 `shared_preferences_ohos`、`flutter_secure_storage_ohos` 插件版本；未在当前 Windows 环境构建或真机验证。后台常驻与系统托盘暂不支持。 |

HarmonyOS 的社区 SDK 已迁移至 [CPF-Flutter](https://gitcode.com/CPF-Flutter/flutter_flutter)。它是上游 Flutter 之外的独立分支，OHOS 插件也有独立兼容性与发布周期，不等同于 Flutter 上游支持。采用前须核对当前维护分支、目标设备系统版本、SDK/DevEco 兼容矩阵及相关插件实现；不能只依赖旧版 Gitee 示例或把普通 Android APK 当作原生 HAP 发布。

本项目记录的本机 Flutter 工具链为 3.41.4；以上上游平台矩阵页面当前描述的是 Flutter 3.50。应在实际发布所用 Flutter 版本上重新运行 `flutter doctor -v`、目标架构构建，并完成至少一次目标设备安装验证。平台可构建性、插件可用性、签名/商店审核和设备运行验证是彼此独立的验收项。
