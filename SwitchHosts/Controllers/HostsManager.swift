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
    
    private let hostsFilePath = "/etc/hosts"
    private let managedBlockStart = "# --- SWITCHHOSTS_CONTENT_START ---"
    private let managedBlockEnd = "# --- SWITCHHOSTS_CONTENT_END ---"
    private let swHostsDirectoryURL: URL
    private let configsFileURL: URL
    
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

    /// 将内容写入系统的 /etc/hosts
    @discardableResult
    private func applyHosts(content: String) -> Bool {
        lastErrorMessage = nil
        do {
            try FileManager.default.createDirectory(at: swHostsDirectoryURL, withIntermediateDirectories: true)
        } catch {
            lastErrorMessage = "创建 .swHosts 目录失败: \(error.localizedDescription)"
            return false
        }
    
        // 1. 将内容写入 ~/.swHosts 下的临时 hosts 文件
        let tempFileURL = swHostsDirectoryURL.appendingPathComponent("temp_hosts_\(UUID().uuidString)")
        let tempScriptURL = swHostsDirectoryURL.appendingPathComponent("temp_apply_hosts_\(UUID().uuidString).applescript")
        defer {
            try? FileManager.default.removeItem(at: tempFileURL)
            try? FileManager.default.removeItem(at: tempScriptURL)
        }
        
        do {
            try content.write(to: tempFileURL, atomically: true, encoding: .utf8)
        } catch {
            lastErrorMessage = "写入临时文件失败: \(error.localizedDescription)"
            return false
        }
        
        // 2. 使用 ~/.swHosts 下的临时脚本进行提权覆盖（会弹出系统管理员密码框）
        let appleScriptContent = """
        on run argv
            set tempPath to item 1 of argv
            set shellCmd to "/bin/cp " & quoted form of tempPath & " /etc/hosts && /bin/chmod 644 /etc/hosts"
            do shell script shellCmd with administrator privileges with prompt "SwitchHosts 需要管理员权限来更新 /etc/hosts"
        end run
        """

        do {
            try appleScriptContent.write(to: tempScriptURL, atomically: true, encoding: .utf8)
        } catch {
            lastErrorMessage = "写入临时脚本失败: \(error.localizedDescription)"
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [tempScriptURL.path, tempFileURL.path]

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
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if stderrText.localizedCaseInsensitiveContains("administrator user name or password was incorrect") {
                lastErrorMessage = "提权失败：管理员账号或密码不正确（也可能是当前账户无管理员权限）"
            } else if stderrText.localizedCaseInsensitiveContains("user canceled") {
                lastErrorMessage = "提权已取消"
            } else {
                lastErrorMessage = stderrText.isEmpty ? "提权修改失败（退出码: \(process.terminationStatus)）" : "提权修改失败: \(stderrText)"
            }
            return false
        }

        // 刷新系统 DNS 缓存
        flushDNS()
        return true
        
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
