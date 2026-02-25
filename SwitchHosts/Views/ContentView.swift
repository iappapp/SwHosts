//
//  ContentView 2.swift
//  SwitchHosts
//
//  Created by mac on 2026/2/25.
//


import SwiftUI

struct ContentView: View {
    @StateObject private var manager = HostsManager()
    @State private var selectedConfigId: UUID?
    @State private var showAddConfigSheet = false
    @State private var newConfigName = ""
    @State private var newConfigContent = ""
    @State private var alertMessage: String?
    
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
                    ForEach(customConfigIndices, id: \.self) { index in
                        NavigationLink(value: manager.configs[index].id) {
                            HStack {
                                Label(manager.configs[index].name, systemImage: "doc.text")
                                Spacer()
                                // 切换开关
                                Toggle("", isOn: $manager.configs[index].isActive)
                                    .labelsHidden()
                                    .onChange(of: manager.configs[index].isActive) { _ in
                                        handleToggleChange()
                                    }
                            }
                        }
                        .contextMenu {
                            Button("删除", role: .destructive) {
                                deleteConfig(id: manager.configs[index].id)
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddConfigSheet = true
                    } label: {
                        Label("新增配置", systemImage: "plus")
                    }
                }
            }
            
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
                        Button("保存配置") {
                            manager.saveUserConfigs()
                            alertMessage = "配置已保存"
                        }
                        Button("保存并应用") {
                            handleToggleChange() // 点击保存时应用配置
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    Divider()
                    
                    // 文本编辑器
                    HostsSyntaxEditor(text: $manager.configs[index].content, isEditable: !manager.configs[index].isSystem)
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
        .sheet(isPresented: $showAddConfigSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("新增配置")
                    .font(.headline)

                TextField("配置名称", text: $newConfigName)

                HostsSyntaxEditor(text: $newConfigContent)
                    .frame(minHeight: 180)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    }

                HStack {
                    Spacer()
                    Button("取消") {
                        resetAddConfigInputs()
                        showAddConfigSheet = false
                    }
                    Button("保存") {
                        let newId = manager.addConfig(name: newConfigName, content: newConfigContent)
                        selectedConfigId = newId
                        resetAddConfigInputs()
                        showAddConfigSheet = false
                        alertMessage = "新增配置已保存"
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .frame(minWidth: 500, minHeight: 320)
        }
        .alert("提示", isPresented: isAlertPresented) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }
    
    /// 处理开关切换或保存：合并系统 Hosts 和所有激活的自定义 Hosts
    private func handleToggleChange() {
        let result = manager.applyCurrentActiveConfigs()
        if result {
            manager.saveUserConfigs()
            alertMessage = "Hosts 已保存并应用"
        } else {
            alertMessage = manager.lastErrorMessage ?? "Hosts 应用失败"
        }
    }

    private func deleteConfig(id: UUID) {
        let removedConfig = manager.removeConfig(id: id)
        if selectedConfigId == id {
            selectedConfigId = manager.configs.first?.id
        }
        if removedConfig?.isActive == true {
            let result = manager.applyCurrentActiveConfigs()
            alertMessage = result ? "配置已删除并同步应用" : (manager.lastErrorMessage ?? "删除后同步应用失败")
        } else {
            alertMessage = "配置已删除并保存"
        }
    }

    private var customConfigIndices: [Int] {
        manager.configs.indices.filter { !manager.configs[$0].isSystem }
    }

    private var isAlertPresented: Binding<Bool> {
        Binding(
            get: { alertMessage != nil },
            set: { newValue in
                if !newValue { alertMessage = nil }
            }
        )
    }

    private func resetAddConfigInputs() {
        newConfigName = ""
        newConfigContent = ""
    }
}