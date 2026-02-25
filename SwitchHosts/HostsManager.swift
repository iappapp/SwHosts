import Foundation
import SwiftUI

class HostsManager: ObservableObject {
    @Published var configs: [HostConfig] = []
    @Published var systemHostsContent: String = ""
    
    let hostsFilePath = "/etc/hosts"
    
    init() {
        loadInitialData()
    }
    
    func loadInitialData() {
        // 读取当前系统的 hosts 文件
        do {
            let content = try String(contentsOfFile: hostsFilePath, encoding: .utf8)
            self.systemHostsContent = content
            
            // 初始化左侧列表数据
            configs = [
                HostConfig(name: "系统 Hosts", content: content, isActive: true, isSystem: true),
                HostConfig(name: "dev.base.cn", content: "172.16.26.159 dev.base.cn\n", isActive: false),
                HostConfig(name: "k8s", content: "192.168.3.10 k8s-master.com\n", isActive: false)
            ]
        } catch {
            print("无法读取 /etc/hosts: \(error)")
        }
    }
    
    /// 将内容写入系统的 /etc/hosts
    func applyHosts(content: String) {
        // 1. 先将内容写入到一个临时文件
        let tempDir = FileManager.default.temporaryDirectory
        let tempFilePath = tempDir.appendingPathComponent("temp_hosts_\(UUID().uuidString)").path
        
        do {
            try content.write(toFile: tempFilePath, atomically: true, encoding: .utf8)
        } catch {
            print("写入临时文件失败: \(error)")
            return
        }
        
        // 2. 使用 AppleScript 调用 shell 脚本，提权执行 cp 命令覆盖 /etc/hosts
        // 注意：这会触发 macOS 的系统密码输入框
        let appleScriptSource = """
        do shell script "cp \(tempFilePath) /etc/hosts && chmod 644 /etc/hosts" with administrator privileges
        """
        
        var errorInfo: NSDictionary?
        if let scriptObject = NSAppleScript(source: appleScriptSource) {
            scriptObject.executeAndReturnError(&errorInfo)
            
            if let error = errorInfo {
                print("提权修改失败: \(error)")
            } else {
                print("Hosts 修改成功！")
                // 刷新系统 DNS 缓存
                flushDNS()
            }
        }
        
        // 3. 清理临时文件
        try? FileManager.default.removeItem(atPath: tempFilePath)
    }
    
    /// 刷新 macOS DNS 缓存
    private func flushDNS() {
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["-HUP", "mDNSResponder"]
        try? task.run()
    }
}