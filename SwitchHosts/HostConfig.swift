import Foundation

struct HostConfig: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var content: String
    var isActive: Bool
    var isSystem: Bool = false
}