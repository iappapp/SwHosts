//
//  HostsManager.swift
//  SwitchHosts
//
//  Created by mac on 2026/2/25.
//


import Foundation
import SwiftUI

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
    
    /// 保存管理员密码到内存
    func saveAdminCredentials(password: String) -> Bool {
        savedPassword = password
        hasSavedCredentials = true
        return true
    }
    
    /// 清除保存的管理员密码
    func clearAdminCredentials() {
        savedPassword = nil
        hasSavedCredentials = false
    }
    
    /// 检查是否有保存的密码
    func checkSavedCredentials() -> Bool {
        hasSavedCredentials = (savedPassword != nil)
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
        
        // 2. 尝试使用保存的密码进行提权
        if let password = savedPassword {
            if executeWithSavedCredentials(tempFileURL: tempFileURL, password: password) {
                flushDNS()
                return true
            }
            // 如果密码失败，清除并回退到手动输入
            savedPassword = nil
            hasSavedCredentials = false
        }
        
        // 3. 使用 AppleScript 进行提权（会弹出系统管理员密码框）
        let success = executeWithAppleScriptPrompt(tempFileURL: tempFileURL)
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
    
    /// 使用 AppleScript 弹窗让用户输入密码，并提供记住密码的选项
    private func executeWithAppleScriptPrompt(tempFileURL: URL) -> Bool {
        // 获取当前用户名
        let username = NSUserName()
        
        // 使用 -e 参数多次传递，避免复杂的字符串转义
        let appleScriptLines = [
            // 显示密码输入对话框，提供记住密码选项
            "set theResult to display dialog \"SwitchHosts 需要管理员权限来更新 /etc/hosts\" default answer \"\" with hidden answer buttons {\"取消\", \"确认并记住\", \"确认\"} default button 3 cancel button 1 with icon caution",
            "set thePassword to text returned of theResult",
            "set theButton to button returned of theResult",
            "",
            // 返回按钮选择和密码（通过标准输出传递给 Swift）
            "if theButton is \"确认并记住\" then",
            "    set resultText to \"REMEMBER:\" & thePassword",
            "else",
            "    set resultText to \"REMEMBER:\" & thePassword",
            "end if",
            "return resultText"
        ]
        
        let appleScriptContent = appleScriptLines.joined(separator: "\n")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScriptContent]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
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
            
            if stderrText.localizedCaseInsensitiveContains("user canceled") {
                lastErrorMessage = "提权已取消"
            } else if stderrText.localizedCaseInsensitiveContains("incorrect password") ||
                      stderrText.localizedCaseInsensitiveContains("authentication failed") {
                lastErrorMessage = "提权失败：管理员账号或密码不正确"
            } else {
                lastErrorMessage = stderrText.isEmpty ? "提权修改失败（退出码: \(process.terminationStatus)）" : "提权修改失败: \(stderrText)"
            }
            return false
        }
        
        // 读取 AppleScript 的输出，获取密码和是否记住的选择
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        if let outputText = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if outputText.hasPrefix("REMEMBER:") {
                // 用户选择记住密码
                let password = String(outputText.dropFirst(9)) // 移除 "REMEMBER:" 前缀
                savedPassword = password
                hasSavedCredentials = true
            }
        }
        
        // 现在使用获取到的密码执行提权命令
        guard let password = savedPassword ?? (savedPassword != nil ? savedPassword : nil) else {
            lastErrorMessage = "未获取到密码"
            return false
        }
        
        return executeWithSavedCredentials(tempFileURL: tempFileURL, password: password)
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
