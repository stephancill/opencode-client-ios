import Foundation

struct Permission: Codable, Identifiable {
    let id: String
    let type: String
    let pattern: String?
    let sessionID: String
    let messageID: String
    let callID: String?
    let title: String
    let metadata: [String: String]?
    let time: PermissionTime

    struct PermissionTime: Codable {
        let created: Date
    }
}

enum PermissionResponse: String, Codable {
    case once
    case always
    case reject
}
