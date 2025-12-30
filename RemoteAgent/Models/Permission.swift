import Foundation

struct Permission: Codable, Identifiable {
    let id: String
    let type: String
    let pattern: PermissionPattern?
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

enum PermissionPattern: Codable {
    case string(String)
    case array([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let arrayValue = try? container.decode([String].self) {
            self = .array(arrayValue)
        } else {
            throw DecodingError.typeMismatch(PermissionPattern.self, DecodingError.Context(codingPath: container.codingPath, debugDescription: "Expected String or [String]"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let string):
            try container.encode(string)
        case .array(let array):
            try container.encode(array)
        }
    }
}

enum PermissionResponse: String, Codable {
    case once
    case always
    case reject
}
