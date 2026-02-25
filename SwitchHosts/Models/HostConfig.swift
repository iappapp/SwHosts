//
//  HostConfig.swift
//  SwitchHosts
//
//  Created by mac on 2026/2/25.
//


import Foundation

struct HostConfig: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var content: String
    var isActive: Bool
    var isSystem: Bool = false
}