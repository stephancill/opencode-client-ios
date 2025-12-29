import Foundation

struct SSEEvent {
    let type: String
    let properties: [String: Any]
}

struct GlobalEvent {
    let directory: String
    let payload: [String: Any]
}
