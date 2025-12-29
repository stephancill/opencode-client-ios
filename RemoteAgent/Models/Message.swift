import Foundation

enum MessagePartType: String, Codable {
    case text
    case tool
    case reasoning
    case stepStart = "step-start"
    case stepFinish = "step-finish"
    case file
    case snapshot
    case patch
    case agent
    case subtask
    case retry
    case compaction
}

struct MessagePart: Identifiable, Codable {
    let id: String
    let sessionID: String
    let messageID: String
    let type: MessagePartType
    let text: String?
    let file: FilePart?
    let synthetic: Bool?
    let reasoning: String?
    let tool: ToolPart?
    let snapshot: String?
    let title: String?
    let metadata: PartMetadata?
    let time: PartTime?
    let callID: String?

    struct FilePart: Codable {
        let filename: String?
        let url: String?
        let mime: String?
        let source: Source?
    }

    struct Source: Codable {
        let text: TextSource?
        let type: String?
        let path: String?
    }

    struct TextSource: Codable {
        let value: String?
        let start: Int?
        let end: Int?
    }

    struct ToolPart: Codable {
        let command: String?
        let output: String?
        let tool: String?
        let state: ToolState?

        struct ToolState: Codable {
            let status: String?
            let input: ToolInput?
            let output: String?
        }

        struct ToolInput: Codable {
            let filePath: String?
            let offset: Int?
            let limit: Int?
        }
    }

    struct PartMetadata: Codable {
        let preview: String?
    }

    struct PartTime: Codable {
        let start: Double?
        let end: Double?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.sessionID = try container.decode(String.self, forKey: .sessionID)
        self.messageID = try container.decode(String.self, forKey: .messageID)
        self.type = try container.decode(MessagePartType.self, forKey: .type)
        self.text = try container.decodeIfPresent(String.self, forKey: .text)
        self.file = try container.decodeIfPresent(FilePart.self, forKey: .file)
        self.synthetic = try container.decodeIfPresent(Bool.self, forKey: .synthetic)
        self.reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning)
        self.snapshot = try container.decodeIfPresent(String.self, forKey: .snapshot)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.metadata = try container.decodeIfPresent(PartMetadata.self, forKey: .metadata)
        self.time = try container.decodeIfPresent(PartTime.self, forKey: .time)
        self.callID = try container.decodeIfPresent(String.self, forKey: .callID)

        // Handle tool field - can be string or object
        if let toolString = try? container.decode(String.self, forKey: .tool) {
            self.tool = ToolPart(command: toolString, output: nil, tool: toolString, state: nil)
        } else if let toolObject = try? container.decode(ToolPart.self, forKey: .tool) {
            self.tool = toolObject
        } else {
            self.tool = nil
        }
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
}

struct UserInfo: Codable {
    let title: String?
    let diffs: [DiffInfo]?
    let body: String?

    struct DiffInfo: Codable, Identifiable {
        let file: String?
        let before: String?
        let after: String?
        let additions: Int?
        let deletions: Int?

        var id: String {
            file ?? UUID().uuidString
        }
    }
}

struct ModelInfo: Codable {
    let providerID: String
    let modelID: String
}

struct UserMessageTime: Codable {
    let created: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let createdDouble = try container.decode(Double.self, forKey: .created)
        self.created = Date(timeIntervalSince1970: createdDouble / 1000)
    }

    enum CodingKeys: String, CodingKey {
        case created
    }
}

struct UserMessageInfo: Codable {
    let id: String
    let sessionID: String
    let role: MessageRole
    let time: UserMessageTime
    let summary: UserInfo?
    let agent: String?
    let model: ModelInfo?
    let system: String?
    let tools: [String: Bool]?
}

struct AssistantMessageTime: Codable {
    let created: Date
    let completed: Date?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let createdDouble = try container.decode(Double.self, forKey: .created)
        self.created = Date(timeIntervalSince1970: createdDouble / 1000)
        if let completedDouble = try? container.decode(Double.self, forKey: .completed) {
            self.completed = Date(timeIntervalSince1970: completedDouble / 1000)
        } else {
            self.completed = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case created, completed
    }
}

struct MessageError: Codable {
    let name: String?
    let message: String?
}

struct MessagePath: Codable {
    let cwd: String?
    let root: String?
}

struct TokenInfo: Codable {
    let input: Int
    let output: Int
    let reasoning: Int
    let cache: CacheInfo

    struct CacheInfo: Codable {
        let read: Int
        let write: Int
    }
}

struct AssistantMessageInfo: Codable {
    let id: String
    let sessionID: String
    let role: MessageRole
    let time: AssistantMessageTime
    let error: MessageError?
    let parentID: String?
    let modelID: String
    let providerID: String
    let mode: String?
    let agent: String
    let path: MessagePath?
    let summary: Bool?
    let cost: Double
    let tokens: TokenInfo
    let finish: String?
}

protocol Message: Identifiable {
    var id: String { get }
    var sessionID: String { get }
    var role: MessageRole { get }
    var timeCreated: Date { get }
}

struct UserMessage: Message, Codable {
    let info: UserMessageInfo
    let parts: [MessagePart]

    var id: String { info.id }
    var sessionID: String { info.sessionID }
    var role: MessageRole { info.role }
    var timeCreated: Date { info.time.created }
}

struct AssistantMessage: Message, Codable {
    let info: AssistantMessageInfo
    let parts: [MessagePart]

    var id: String { info.id }
    var sessionID: String { info.sessionID }
    var role: MessageRole { info.role }
    var timeCreated: Date { info.time.created }
}

enum APIResponseMessage: Message, Codable {
    case user(UserMessage)
    case assistant(AssistantMessage)

    var id: String {
        switch self {
        case .user(let msg): return msg.id
        case .assistant(let msg): return msg.id
        }
    }

    var sessionID: String {
        switch self {
        case .user(let msg): return msg.sessionID
        case .assistant(let msg): return msg.sessionID
        }
    }

    var role: MessageRole {
        switch self {
        case .user: return .user
        case .assistant: return .assistant
        }
    }

    var timeCreated: Date {
        switch self {
        case .user(let msg): return msg.timeCreated
        case .assistant(let msg): return msg.timeCreated
        }
    }

    var parts: [MessagePart] {
        switch self {
        case .user(let msg): return msg.parts
        case .assistant(let msg): return msg.parts
        }
    }

    enum CodingKeys: String, CodingKey {
        case info, parts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let info = try container.nestedContainer(keyedBy: InfoCodingKeys.self, forKey: .info)
        let role = try info.decode(MessageRole.self, forKey: .role)
        let parts = try container.decode([MessagePart].self, forKey: .parts)

        if role == .user {
            let userInfo = try container.decode(UserMessageInfo.self, forKey: .info)
            self = .user(UserMessage(info: userInfo, parts: parts))
        } else {
            let assistantInfo = try container.decode(AssistantMessageInfo.self, forKey: .info)
            self = .assistant(AssistantMessage(info: assistantInfo, parts: parts))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .user(let msg):
            try container.encode(msg.info, forKey: .info)
            try container.encode(msg.parts, forKey: .parts)
        case .assistant(let msg):
            try container.encode(msg.info, forKey: .info)
            try container.encode(msg.parts, forKey: .parts)
        }
    }

    enum InfoCodingKeys: String, CodingKey {
        case role
    }
}
