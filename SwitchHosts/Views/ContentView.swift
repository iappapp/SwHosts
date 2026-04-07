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
    @State private var showCredentialDialog = false
    @State private var adminPassword = ""
    
    var body: some View {
        NavigationSplitView {
            // 左侧列表
            List(selection: $selectedConfigId) {
                // 系统 Hosts 部分
                if let sysConfig = manager.configs.first(where: { $0.isSystem }) {
                    HStack {
                        Label(sysConfig.name, systemImage: "desktopcomputer")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .tag(sysConfig.id)
                    .onTapGesture {
                        selectedConfigId = sysConfig.id
                    }
                }
                
                Divider()
                
                // 自定义配置部分
                Section("自定义配置") {
                    ForEach(customConfigIndices, id: \.self) { index in
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
                        .contentShape(Rectangle())
                        .tag(manager.configs[index].id)
                        .onTapGesture {
                            selectedConfigId = manager.configs[index].id
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
                
                ToolbarItem(placement: .automatic) {
                    if manager.hasSavedCredentials {
                        Button {
                            manager.clearAdminCredentials()
                            alertMessage = "已清除保存的管理员凭据"
                        } label: {
                            Label("清除钥匙串凭据", systemImage: "key.slash.fill")
                        }
                        .help("清除保存的管理员密码，下次将重新提示输入")
                    } else {
                        Button {
                            showCredentialDialog = true
                        } label: {
                            Label("保存管理员凭据", systemImage: "key.fill")
                        }
                        .help("保存管理员密码到钥匙串，避免重复输入")
                    }
                }
            }
            
        } detail: {
            // 右侧编辑器
            if let selectedId = selectedConfigId,
               let configBinding = bindingForConfig(id: selectedId) {
                
                VStack(spacing: 0) {
                    // 顶部工具栏区
                    HStack {
                        Text(configBinding.wrappedValue.name)
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
                    HostsSyntaxEditor(text: configBinding.content, isEditable: !configBinding.wrappedValue.isSystem)
                        .id(selectedId)
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
        .alert("保存管理员凭据", isPresented: $showCredentialDialog) {
            SecureField("管理员密码", text: $adminPassword)
            Button("取消", role: .cancel) {
                adminPassword = ""
            }
            Button("保存") {
                if !adminPassword.isEmpty {
                    let success = manager.saveAdminCredentials(password: adminPassword)
                    adminPassword = ""
                    if success {
                        alertMessage = "管理员凭据已保存到钥匙串"
                    } else {
                        alertMessage = "保存凭据失败"
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text("请输入您的管理员密码以保存到钥匙串。之后应用 Hosts 时将自动使用该密码，无需重复输入。")
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
            // 刷新钥匙串状态
            manager.checkSavedCredentials()
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

    private func bindingForConfig(id: UUID) -> Binding<HostConfig>? {
        guard let index = manager.configs.firstIndex(where: { $0.id == id }) else { return nil }
        return $manager.configs[index]
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
