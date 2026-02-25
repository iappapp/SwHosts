import SwiftUI

struct ContentView: View {
    @StateObject private var manager = HostsManager()
    @State private var selectedConfigId: UUID?
    
    var body: some View {
        NavigationSplitView {
            // 左侧列表
            List(selection: $selectedConfigId) {
                // 系统 Hosts 部分
                if let sysConfig = manager.configs.first(where: { $0.isSystem }) {
                    NavigationLink(value: sysConfig.id) {
                        Label(sysConfig.name, systemImage: "desktopcomputer")
                    }
                }
                
                Divider()
                
                // 自定义配置部分
                Section("自定义配置") {
                    ForEach($manager.configs.filter { !$0.isSystem.wrappedValue }) { $config in
                        NavigationLink(value: config.id) {
                            HStack {
                                Label(config.name, systemImage: "doc.text")
                                Spacer()
                                // 切换开关
                                Toggle("", isOn: $config.isActive)
                                    .labelsHidden()
                                    .onChange(of: config.isActive) { _ in
                                        handleToggleChange()
                                    }
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
            
        } detail: {
            // 右侧编辑器
            if let selectedId = selectedConfigId,
               let index = manager.configs.firstIndex(where: { $0.id == selectedId }) {
                
                VStack(spacing: 0) {
                    // 顶部工具栏区
                    HStack {
                        Text(manager.configs[index].name)
                            .font(.headline)
                        Spacer()
                        Button("保存并应用") {
                            handleToggleChange() // 点击保存时应用配置
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    Divider()
                    
                    // 文本编辑器
                    TextEditor(text: $manager.configs[index].content)
                        .font(.system(.body, design: .monospaced)) // 使用等宽字体
                        .padding()
                }
            } else {
                Text("请在左侧选择一个配置")
                    .foregroundColor(.secondary)
            }
        }
        // 默认选中第一个
        .onAppear {
            if selectedConfigId == nil {
                selectedConfigId = manager.configs.first?.id
            }
        }
    }
    
    /// 处理开关切换或保存：合并系统 Hosts 和所有激活的自定义 Hosts
    private func handleToggleChange() {
        guard let sysConfig = manager.configs.first(where: { $0.isSystem }) else { return }
        
        var finalContent = sysConfig.content
        finalContent += "\n\n# --- SWITCHHOSTS_CONTENT_START ---\n"
        
        for config in manager.configs where !config.isSystem && config.isActive {
            finalContent += "\n# 活跃配置: \(config.name)\n"
            finalContent += config.content
            finalContent += "\n"
        }
        
        // 调用提权写入
        manager.applyHosts(content: finalContent)
    }
}