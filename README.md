# SwitchHosts

一个基于 **SwiftUI** 的 macOS Hosts 配置切换工具，用于在多个自定义 Hosts 配置之间快速启停，并安全写入系统 `/etc/hosts`。

## 项目定位

`SwitchHosts` 适合本地开发、多环境联调、域名重定向测试等场景。它提供图形化管理能力，避免手动编辑系统 Hosts 文件带来的低效和误操作。

## 已实现功能

- **系统 Hosts 基础内容自动加载**
  - 启动时读取 `/etc/hosts`。
  - 自动剔除本应用曾写入的管理区块，保留原始系统内容作为“系统 Hosts”。

- **多配置管理**
  - 支持新增自定义配置（名称 + 内容）。
  - 支持删除自定义配置。
  - 配置数据持久化到用户目录（JSON）。

- **配置启停与合并应用**
  - 每个自定义配置都有独立开关（`isActive`）。
  - 应用时会把“系统 Hosts 基础内容 + 所有已启用配置”合并生成最终内容。
  - 自定义内容写入受控区块：
    - `# --- SWITCHHOSTS_CONTENT_START ---`
    - `# --- SWITCHHOSTS_CONTENT_END ---`

- **管理员提权写入 `/etc/hosts`**
  - 通过 `osascript` 执行 AppleScript，弹出系统管理员授权框。
  - 写入完成后自动设置权限为 `644`。
  - 自动刷新 DNS 缓存（`killall -HUP mDNSResponder`）。

- **基础编辑体验**
  - 内置文本编辑器（`NSTextView` 封装）。
  - 等宽字体显示，适配 Hosts 编辑。
  - 对 IPv4 和域名进行基础语法高亮。
  - 系统 Hosts 配置只读，自定义配置可编辑。

- **状态反馈**
  - 关键操作有提示弹窗。
  - 对提权失败、取消授权、读写失败等场景给出可读错误信息。

## 技术实现概览

- **UI 层**：SwiftUI（`NavigationSplitView` + 表单/弹窗）
- **编辑器层**：`NSViewRepresentable` 封装 `NSTextView`
- **状态管理**：`ObservableObject` + `@Published`
- **数据模型**：`Codable` 的 `HostConfig`
- **持久化**：`~/.swHosts/host_configs.json`
- **系统写入**：临时文件 + AppleScript 提权覆盖 `/etc/hosts`

## 目录结构说明

```text
SwitchHosts/
  SwitchHostsApp.swift            # 应用入口
  Controllers/
    HostsManager.swift            # 核心逻辑：加载、合并、保存、提权应用
  Models/
    HostConfig.swift              # 配置数据模型
  Views/
    ContentView.swift             # 主界面：列表、开关、新增、保存与应用
    HostsSyntaxEditor.swift       # Hosts 文本编辑器与高亮
  SwitchHosts.entitlements        # 权限声明（当前为空）
SwitchHostsTests/
SwitchHostsUITests/
```

## 运行要求

- macOS（项目中应用目标配置为 13.5）
- Xcode（建议使用较新版本）
- 首次“应用 Hosts”时需要管理员权限

## 本地运行

1. 使用 Xcode 打开 `SwitchHosts.xcodeproj`
2. 选择 Scheme：`SwitchHosts`
3. 运行（`Run`）
4. 在应用中新增配置、启用开关并点击“保存并应用”

## 配置与数据存储

应用会在用户目录创建：

- `~/.swHosts/host_configs.json`：自定义配置持久化文件
- `~/.swHosts/temp_hosts_*`：应用时临时文件（任务结束后自动清理）
- `~/.swHosts/temp_apply_hosts_*.applescript`：提权脚本临时文件（任务结束后自动清理）

## 应用 Hosts 的执行流程

1. 读取并清洗系统 `/etc/hosts`（去除历史管理区块）
2. 合并所有已启用的自定义配置
3. 输出最终内容到临时文件
4. 通过 AppleScript 提权执行复制到 `/etc/hosts`
5. 执行 DNS 缓存刷新

## 打包 DMG（命令行）

在项目根目录执行：

```bash
# 1) Release 构建
xcodebuild -project SwitchHosts.xcodeproj \
  -scheme SwitchHosts \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build build

# 2) 准备 DMG 内容
rm -rf dmg-root
mkdir -p dmg-root
cp -R build/Build/Products/Release/SwitchHosts.app dmg-root/
ln -s /Applications dmg-root/Applications

# 3) 生成压缩 DMG
hdiutil create -volname "SwitchHosts" \
  -srcfolder dmg-root \
  -ov -format UDZO SwitchHosts.dmg
```

## 已知限制

- 当前未实现配置导入/导出。
- 当前未包含完整单元测试与 UI 自动化用例。
- 若需要外部分发，建议增加 Developer ID 签名与 Notarization 公证流程。

## 后续建议

- 增加配置模板（开发/测试/预发/生产）
- 增加配置搜索与分组
- 增加导入导出（JSON / hosts 文本）
- 增加“预览最终合并结果”面板

## 开源协作

- 许可证：本项目使用 [MIT License](LICENSE)
- 参与贡献：请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)
- 行为准则：请遵守 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- 安全反馈：请参考 [SECURITY.md](SECURITY.md)

---

如果你希望，我可以继续补一份 `README_EN.md`（英文版）和“一键发布脚本（build + dmg + 可选签名/公证）”。
