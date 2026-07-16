//
//  HostsManager.swift
//  SwitchHosts
//
//  Created by mac on 2026/2/25.
//


import Foundation
import SwiftUI
import AppKit
import LocalAuthentication
import Security

final class HostsManager: ObservableObject {
    @Published var configs: [HostConfig] = []
    @Published var systemHostsContent: String = ""
    @Published var lastErrorMessage: String?
    @Published var hasSavedCredentials: Bool = false
    
    private let hostsFilePath = "/etc/hosts"
    private let managedBlockStart = "# --- SWITCHHOSTS_CONTENT_START ---"
    private let managedBlockEnd = "# --- SWITCHHOSTS_CONTENT_END ---"
    private let swHostsDirectoryURL: URL
    private let configsFileURL: URL
    private var savedPassword: String? = nil  // 在内存中保存密码
    
    init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        self.swHostsDirectoryURL = homeDirectory.appendingPathComponent(".swHosts", isDirectory: true)
        self.configsFileURL = swHostsDirectoryURL.appendingPathComponent("host_configs.json")
        do {
            try FileManager.default.createDirectory(at: swHostsDirectoryURL, withIntermediateDirectories: true)
        } catch {
            self.lastErrorMessage = "创建 .swHosts 目录失败: \(error.localizedDescription)"
        }
        loadInitialData()
    }
    
    func loadInitialData() {
        let hostsContent: String
        do {
            hostsContent = try String(contentsOfFile: hostsFilePath, encoding: .utf8)
        } catch {
            hostsContent = ""
            lastErrorMessage = "无法读取 /etc/hosts: \(error.localizedDescription)"
        }

        let cleanSystemContent = removingManagedBlock(from: hostsContent)
        self.systemHostsContent = cleanSystemContent

        let systemConfig = HostConfig(name: "系统 Hosts", content: cleanSystemContent, isActive: true, isSystem: true)
        let savedCustomConfigs = loadSavedConfigs()

        configs = [systemConfig] + (savedCustomConfigs.isEmpty ? defaultCustomConfigs() : savedCustomConfigs)
        saveUserConfigs()
    }

    func addConfig(name: String, content: String = "") -> UUID {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = trimmedName.isEmpty ? "未命名配置" : trimmedName
        let newConfig = HostConfig(name: safeName, content: content, isActive: false, isSystem: false)
        configs.append(newConfig)
        saveUserConfigs()
        return newConfig.id
    }

    @discardableResult
    func removeConfig(id: UUID) -> HostConfig? {
        guard let index = configs.firstIndex(where: { $0.id == id && !$0.isSystem }) else {
            return nil
        }
        let removed = configs.remove(at: index)
        saveUserConfigs()
        return removed
    }

    func saveUserConfigs() {
        let customConfigs = configs.filter { !$0.isSystem }
        do {
            let directoryURL = configsFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(customConfigs)
            try data.write(to: configsFileURL, options: .atomic)
        } catch {
            lastErrorMessage = "保存配置失败: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func applyCurrentActiveConfigs() -> Bool {
        let finalContent = buildFinalHostsContent()
        return applyHosts(content: finalContent)
    }
    
    /// 保存管理员密码到钥匙串（支持 Touch ID 的设备启用生物识别保护）
    func saveAdminCredentials(password: String) -> Bool {
        savedPassword = password
        let ok = KeychainManager.savePassword(password, requireBiometrics: canUseBiometrics())
        hasSavedCredentials = ok || savedPassword != nil
        return hasSavedCredentials
    }
    
    /// 清除保存的管理员密码
    func clearAdminCredentials() {
        savedPassword = nil
        KeychainManager.deletePassword()
        hasSavedCredentials = false
    }
    
    /// 检查是否有保存的密码
    func checkSavedCredentials() -> Bool {
        hasSavedCredentials = savedPassword != nil || KeychainManager.hasStoredPassword()
        return hasSavedCredentials
    }

    /// 将内容写入系统的 /etc/hosts
    @discardableResult
    private func applyHosts(content: String) -> Bool {
        lastErrorMessage = nil
        
        // 1. 将内容写入 ~/.swHosts 下的临时 hosts 文件
        let tempFileURL = swHostsDirectoryURL.appendingPathComponent("temp_hosts_\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: tempFileURL)
        }
        
        do {
            try content.write(to: tempFileURL, atomically: true, encoding: .utf8)
            // 设置临时文件权限为 644
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tempFileURL.path)
        } catch {
            lastErrorMessage = "写入临时文件失败: \(error.localizedDescription)"
            return false
        }
        
        // 2. 钥匙串凭据 + Touch ID 解锁（弹出系统指纹面板，无密码免输）
        if KeychainManager.hasStoredPassword() {
            switch KeychainManager.loadPassword(useBiometrics: canUseBiometrics()) {
            case .success(let password):
                if executeWithSavedCredentials(tempFileURL: tempFileURL, password: password) {
                    savedPassword = password
                    hasSavedCredentials = true
                    flushDNS()
                    return true
                }
                // 密码失效，清理后回退
                KeychainManager.deletePassword()
                savedPassword = nil
                hasSavedCredentials = false
            case .canceled:
                lastErrorMessage = "提权已取消"
                return false
            case .fallback:
                // 用户在指纹框点击「使用密码」，回退到密码输入框
                break
            case .notFound:
                break
            case .failed(let message):
                lastErrorMessage = message
            }
        }

        // 3. 尝试使用内存中的密码进行提权
        if let password = savedPassword {
            if executeWithSavedCredentials(tempFileURL: tempFileURL, password: password) {
                flushDNS()
                return true
            }
            savedPassword = nil
            hasSavedCredentials = false
        }

        // 4. 无保存凭据：弹出密码输入框，验证成功后存入钥匙串供下次使用
        let success = executeWithPasswordInput(tempFileURL: tempFileURL)
        if success {
            flushDNS()
        }
        return success
    }
    
    /// 使用保存的钥匙串凭据执行提权操作
    private func executeWithSavedCredentials(tempFileURL: URL, password: String) -> Bool {
        // 获取当前用户名
        let username = NSUserName()
        
        // 构建 AppleScript，使用保存的凭据
        let shellCommand = "/bin/cp '\(tempFileURL.path)' /etc/hosts && /bin/chmod 644 /etc/hosts"
        // 注意：密码中的双引号需要转义，以防破坏 AppleScript 字符串结构
        let escapedPassword = password.replacingOccurrences(of: "\"", with: "\\\"")
        let appleScriptSource = """
        do shell script "\(shellCommand)" user name "\(username)" password "\(escapedPassword)" with administrator privileges
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScriptSource]
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            lastErrorMessage = "无法启动提权流程: \(error.localizedDescription)"
            return false
        }
        
        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            // 如果是凭据错误，返回 false 以便回退到手动输入
            if stderrText.localizedCaseInsensitiveContains("incorrect password") ||
               stderrText.localizedCaseInsensitiveContains("authentication failed") ||
               stderrText.localizedCaseInsensitiveContains("permission denied") {
                return false
            }
            
            lastErrorMessage = stderrText.isEmpty ? "提权修改失败（退出码: \(process.terminationStatus)）" : "提权修改失败: \(stderrText)"
            return false
        }
        
        // 凭据验证成功，更新内存状态
        hasSavedCredentials = true
        
        return true
    }
    
    /// 弹出密码输入框，验证成功后存入钥匙串（支持 Touch ID 的设备下次可用指纹解锁）
    private func executeWithPasswordInput(tempFileURL: URL) -> Bool {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "需要管理员密码"
        alert.informativeText = "SwitchHosts 需要管理员密码来更新 /etc/hosts。"
        alert.alertStyle = .warning

        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        passwordField.placeholderString = "请输入管理员密码"
        alert.accessoryView = passwordField

        alert.addButton(withTitle: "确认")
        alert.addButton(withTitle: "取消")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            lastErrorMessage = "提权已取消"
            return false
        }

        let password = passwordField.stringValue
        if password.isEmpty {
            lastErrorMessage = "密码不能为空"
            return false
        }

        guard executeWithSavedCredentials(tempFileURL: tempFileURL, password: password) else {
            return false
        }

        // 验证成功，存入钥匙串供下次使用
        savedPassword = password
        if KeychainManager.savePassword(password, requireBiometrics: canUseBiometrics()) {
            hasSavedCredentials = true
        }
        return true
    }

    /// 检测当前硬件是否支持 Touch ID / Optic ID
    private func canUseBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        if context.biometryType == .touchID { return true }
        if #available(macOS 14.0, *) {
            return context.biometryType == .opticID
        }
        return false
    }

    /// 刷新 macOS DNS 缓存
    private func flushDNS() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["-HUP", "mDNSResponder"]
        try? task.run()
    }

    private func loadSavedConfigs() -> [HostConfig] {
        guard FileManager.default.fileExists(atPath: configsFileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: configsFileURL)
            return try JSONDecoder().decode([HostConfig].self, from: data)
                .filter { !$0.isSystem }
        } catch {
            lastErrorMessage = "读取本地配置失败: \(error.localizedDescription)"
            return []
        }
    }

    private func defaultCustomConfigs() -> [HostConfig] {
        [
        ]
    }

    private func buildFinalHostsContent() -> String {
        let latestSystemContent = loadSystemBaseContent()
        if let systemIndex = configs.firstIndex(where: { $0.isSystem }) {
            configs[systemIndex].content = latestSystemContent
        }
        systemHostsContent = latestSystemContent

        var finalContent = latestSystemContent
        finalContent += "\n\n\(managedBlockStart)\n"

        for config in configs where !config.isSystem && config.isActive {
            finalContent += "\n# 活跃配置: \(config.name)\n"
            finalContent += config.content
            if !config.content.hasSuffix("\n") {
                finalContent += "\n"
            }
        }

        finalContent += "\(managedBlockEnd)\n"
        return finalContent
    }

    private func loadSystemBaseContent() -> String {
        do {
            let latest = try String(contentsOfFile: hostsFilePath, encoding: .utf8)
            return removingManagedBlock(from: latest)
        } catch {
            lastErrorMessage = "读取系统 Hosts 失败，使用内存缓存: \(error.localizedDescription)"
            return removingManagedBlock(from: systemHostsContent)
        }
    }

    private func removingManagedBlock(from content: String) -> String {
        guard let startRange = content.range(of: managedBlockStart) else { return content }
        if let endRange = content.range(of: managedBlockEnd), endRange.lowerBound >= startRange.upperBound {
            let prefix = String(content[..<startRange.lowerBound])
            let suffix = String(content[endRange.upperBound...])
            let combined = (prefix + suffix).trimmingCharacters(in: .whitespacesAndNewlines)
            return combined
        }
        return String(content[..<startRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Keychain

