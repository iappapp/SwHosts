# SwitchHosts

一个基于 SwiftUI 的 macOS Hosts 配置切换工具。

## 功能特性

- ✅ 系统 Hosts 自动加载与清洗
- ✅ 多配置管理（新增、删除、编辑）
- ✅ 配置启停与智能合并
- ✅ **Touch ID 指纹解锁**：支持的设备可用指纹代替输入密码
- ✅ **钥匙串支持**：首次输入密码后自动保存，之后免输
- ✅ 安全写入机制（AppleScript 提权）
- ✅ 语法高亮编辑器
- ✅ DNS 缓存自动刷新

## 🔑 鉴权与钥匙串

### 工作流程

```
点「保存并应用」
    ↓
钥匙串有保存的密码？
    ├─ 是 → 支持指纹？
    │       ├─ 是 → 弹出 Touch ID 验证
    │       │       ├─ 通过 → 静默读取钥匙串密码 → 静默写入 /etc/hosts ✅
    │       │       ├─ 点「使用密码」→ 回退到密码输入框
    │       │       └─ 取消 → 取消
    │       └─ 否 → 静默读取钥匙串密码 → 静默写入 /etc/hosts ✅
    └─ 否 → 弹出密码输入框
            ├─ 验证成功 → 存入钥匙串 → 写入 /etc/hosts ✅（下次走指纹/钥匙串）
            └─ 验证失败 → 提示错误
```

### 首次使用

1. 编辑 / 切换配置后点 **「保存并应用」**
2. 弹出密码输入框，输入管理员密码
3. 验证成功后密码**自动存入钥匙串**，本次写入 `/etc/hosts`
4. 之后每次「保存并应用」：
   - 支持 Touch ID 的设备 → 弹指纹验证
   - 不支持的设备 → 静默读取钥匙串，无需再输密码

### Touch ID 说明

- 仅在支持 Touch ID / Optic ID 的 Mac 上启用
- 指纹验证框中点「使用密码」可回退到密码输入
- 指纹验证通过后，密码从钥匙串静默读取，用于 AppleScript 提权写入 `/etc/hosts`
- 指纹本身**不直接授予管理员权限**，而是解锁钥匙串中已保存的密码

### 密码失效处理

- 管理员密码被修改后，钥匙串中的旧密码会失效
- 下次应用时自动检测失效，清除旧凭据并重新弹出密码输入框

### 安全性

- ✅ 密码使用 macOS Keychain Services API 加密存储
- ✅ 仅在设备解锁时可访问（`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`）
- ✅ 不明文存储在磁盘或代码中
- ✅ 仅保存在当前设备（`ThisDeviceOnly`，不随 iCloud 钥匙串同步）
- ✅ Touch ID 通过 `LocalAuthentication` 框架的 `LAContext.evaluatePolicy` 显式触发

## 技术架构

### 核心组件

| 组件 | 职责 |
|------|------|
| `HostsManager` | 业务逻辑层，管理 Hosts 配置、提权写入、鉴权流程编排 |
| `KeychainManager` | 钥匙串管理，封装 Security Framework API（独立文件） |
| `ContentView` | 主界面视图（SwiftUI） |
| `HostsSyntaxEditor` | 语法高亮编辑器（AppKit NSTextView） |

### 鉴权方案

| 方案 | 用途 | 说明 |
|------|------|------|
| **LAContext + 钥匙串** | Touch ID 解锁 | `evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` 显式弹指纹，通过后静默读取钥匙串密码 |
| **内联 AppleScript + 钥匙串密码** | 提权写入 | 用钥匙串中的密码通过 `do shell script ... with administrator privileges` 静默写入 `/etc/hosts` |
| **NSAlert + NSSecureTextField** | 首次输入 | 首次无凭据时弹出密码框，验证成功后存入钥匙串 |

> Touch ID 与钥匙串存储**解耦**：钥匙串只存密码（无 `SecAccessControl` 访问控制），Touch ID 用 `LAContext.evaluatePolicy` 作为读取前的显式门禁。这样指纹弹窗由标准 LocalAuthentication API 触发，更可靠。

### 提权写入流程

1. 将合并后的 Hosts 内容写入 `~/.swHosts/temp_hosts_<UUID>` 临时文件（权限 644）
2. 按鉴权流程获取密码
3. 通过 `osascript` 执行 `/bin/cp '<临时文件>' /etc/hosts && /bin/chmod 644 /etc/hosts`，附带 `user name`/`password`/`with administrator privileges`
4. 成功后刷新 DNS 缓存（`killall -HUP mDNSResponder`）
5. 清理临时文件

## 开发环境

- **macOS**: 13.5+
- **Xcode**: 最新版推荐
- **语言**: Swift
- **UI 框架**: SwiftUI + AppKit (NSTextView)
- **依赖框架**: `LocalAuthentication`、`Security`（系统框架，无需额外配置）

## 构建与运行

### Xcode

1. 打开 `SwitchHosts.xcodeproj`
2. 选择 Scheme: `SwitchHosts`
3. 点击 Run

### 命令行

```bash
# Debug 构建
xcodebuild -project SwitchHosts.xcodeproj -scheme SwitchHosts build

# Release 构建
xcodebuild -project SwitchHosts.xcodeproj \
  -scheme SwitchHosts \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build \
  build
```

### 生成 DMG

```bash
# 1. Release 构建
xcodebuild -project SwitchHosts.xcodeproj \
  -scheme SwitchHosts \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build \
  build

# 2. 准备 DMG 内容
rm -rf dmg-root
mkdir -p dmg-root
cp -R build/Build/Products/Release/SwitchHosts.app dmg-root/
ln -s /Applications dmg-root/Applications

# 3. 生成压缩 DMG
hdiutil create -volname "SwitchHosts" \
  -srcfolder dmg-root \
  -ov -format UDZO SwitchHosts.dmg
```

## 数据存储

| 数据 | 位置 |
|------|------|
| 配置文件 | `~/.swHosts/host_configs.json` |
| 临时文件 | `~/.swHosts/temp_*`（自动清理） |
| 钥匙串凭据 | macOS Keychain（Service: `com.switchhosts.admin`，Account: 当前用户名） |

## ⚠️ 分发注意事项

### 未公证应用的限制

直接打包的 DMG **未经公证（Notarization）**，分发给他人可能出现：

- **首次能运行，几天后失效**：macOS 的 App Translocation 机制导致钥匙串签名上下文变化，已保存的密码读不到
- **隐私里放行无效**：该放行是针对隔离标记（`com.apple.quarantine`）的一次性临时操作，重启/重新拷贝后失效

### 临时解决（给接收方）

```bash
# 1. 拖到 /Applications（不要从 DMG 直接运行）
# 2. 清除隔离标记
xattr -cr /Applications/SwitchHosts.app
```

### 正式分发（推荐）

需 Apple Developer Program（¥688/年）+ Developer ID Application 证书：

```bash
# 1. 用 Developer ID Application 签名
codesign --deep --force --options runtime \
  --sign "Developer ID Application: 你的名字 (TEAMID)" \
  SwitchHosts.app

# 2. 提交公证
xcrun notarytool submit SwitchHosts.zip \
  --apple-id "你的AppleID" \
  --password "app-specific-password" \
  --team-id "TEAMID" --wait

# 3. 装订公证票据
xcrun stapler staple SwitchHosts.app

# 4. DMG 同样需签名 + 公证 + 装订
```

公证后 Gatekeeper 永久放行，不再触发 App Translocation，钥匙串访问稳定。

## 许可证

MIT License