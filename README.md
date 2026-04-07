# SwitchHosts

一个基于 SwiftUI 的 macOS Hosts 配置切换工具。

## 功能特性

- ✅ 系统 Hosts 自动加载与清洗
- ✅ 多配置管理（新增、删除、编辑）
- ✅ 配置启停与智能合并
- ✅ **钥匙串支持**：保存管理员密码，避免重复输入
- ✅ 安全写入机制（AppleScript 提权）
- ✅ 语法高亮编辑器
- ✅ DNS 缓存自动刷新

## 🔑 钥匙串功能说明

### 什么是钥匙串支持？

钥匙串是 macOS 系统提供的安全凭据存储服务。SwitchHosts 利用钥匙串保存您的管理员密码，让您无需每次应用 Hosts 时都输入密码。

### 如何使用？

#### 首次使用（保存密码）

1. 点击工具栏的 **🔑 保存管理员凭据** 按钮
2. 在弹出的对话框中输入您的管理员密码
3. 点击"保存"
4. 之后应用 Hosts 时将自动使用该密码

#### 清除已保存的密码

当您看到工具栏显示 **🔑̸ 清除钥匙串凭据** 按钮时，表示已保存密码。点击该按钮即可清除。

### 工作流程

```
应用 Hosts
    ↓
检查是否有保存的钥匙串凭据？
    ↓ 是
尝试使用保存的凭据
    ↓ 成功
✅ 应用成功
    ↓ 失败（密码错误）
清除失效凭据 → 回退到手动输入
    ↓ 否
弹出密码输入框（可选择保存到钥匙串）
```

### 安全性

- ✅ 密码使用 macOS Keychain Services API 加密存储
- ✅ 仅在设备解锁时可访问（`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`）
- ✅ 不会明文存储在磁盘或代码中
- ✅ 可随时清除，完全由用户控制

### 常见问题

**Q: 如果我更改了管理员密码怎么办？**  
A: 下次应用 Hosts 时，如果钥匙串中的旧密码失效，系统会自动清除并提示您重新输入新密码。

**Q: 密码保存在哪里？**  
A: 保存在 macOS 钥匙串中，Service 名称为 `com.switchhosts.admin`。您可以在"钥匙串访问"应用中查看。

**Q: 可以不保存密码吗？**  
A: 当然可以。不点击保存按钮，每次都会提示输入密码。

**Q: 多台 Mac 之间会同步吗？**  
A: 不会。钥匙串数据仅保存在当前设备上（`ThisDeviceOnly` 属性）。

## 🐛 已知问题修复

### AppleScript 语法错误修复

**问题描述：**  
之前版本在某些情况下会出现以下错误：
```
提权修改失败: /Users/mac/.swHosts/temp_prompt_XXX.scpt:383:384: 
script error: 预期是行的结尾等等，却找到未知的记号。 (-2741)
```

**原因分析：**
- AppleScript 字符串中包含特殊字符（如引号、反斜杠、路径等）时未正确转义
- 使用多行字符串模板时，Swift 的字符串插值与 AppleScript 语法冲突
- `quoted form of` 的使用位置不当

**解决方案：**
1. ✅ 使用数组逐行构建 AppleScript，避免复杂的多行字符串转义
2. ✅ 正确使用 `quoted form of` 来处理文件路径
3. ✅ 对用户名等变量进行适当的转义处理
4. ✅ 添加 try-catch 错误处理机制

**技术细节：**
```swift
// ❌ 旧方案：容易出错的多行字符串
let script = """
do shell script "command \(variable)" password thePassword
"""

// ✅ 新方案：逐行构建，清晰可控
let lines = [
    "set thePassword to text returned of result",
    "do shell script \"/bin/cp \" & quoted form of \"\(path)\" & \" ...\" user name \"\(user)\" password thePassword with administrator privileges"
]
let script = lines.joined(separator: "\n")
```

## 技术架构

### 核心组件

- **HostsManager**: 业务逻辑层，管理 Hosts 配置和提权操作
- **KeychainManager**: 钥匙串管理器，封装 Security Framework API
- **ContentView**: 主界面视图
- **HostsSyntaxEditor**: 语法高亮编辑器

### 提权方案对比

| 方案 | 优点 | 缺点 |
|------|------|------|
| ~~临时 AppleScript 文件~~ | - | ❌ 安全风险，需清理临时文件 |
| ~~Authorization Services~~ | - | ❌ macOS 10.9+ 已废弃 |
| **内联 AppleScript + 钥匙串** | ✅ 简单安全，用户体验好 | 需要用户首次授权 |
| Helper Tool (SMJobBless) | ✅ 完全自动化 | ❌ 实现复杂，需额外签名 |

当前采用：**内联 AppleScript + 钥匙串**（最佳平衡方案）

## 开发环境

- **macOS**: 13.5+
- **Xcode**: 最新版推荐
- **语言**: Swift
- **UI 框架**: SwiftUI + AppKit (NSTextView)

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

- **配置文件**: `~/.swHosts/host_configs.json`
- **临时文件**: `~/.swHosts/temp_*`（自动清理）
- **钥匙串凭据**: macOS Keychain (Service: `com.switchhosts.admin`)

## 注意事项

⚠️ **权限要求**: 首次应用 Hosts 时需要管理员权限授权  
⚠️ **分发限制**: 外部分发需要 Developer ID 签名与 Notarization  
⚠️ **Gatekeeper**: 未签名的应用可能在非开发机上被拦截

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！详见 [CONTRIBUTING.md](CONTRIBUTING.md)
