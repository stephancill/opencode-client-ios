import Foundation

struct Session: Codable, Identifiable, Equatable {
    let id: String
    let projectID: String
    let directory: String
    let parentID: String?
    let title: String
    let version: String
    let time: SessionTime
    let summary: SessionSummary?
    let share: ShareInfo?
    let revert: RevertInfo?

    struct SessionTime: Codable, Equatable {
        let created: Date
        let updated: Date
        let compacting: Date?
        let archived: Date?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let createdDouble = try container.decode(Double.self, forKey: .created)
            let updatedDouble = try container.decode(Double.self, forKey: .updated)
            self.created = Date(timeIntervalSince1970: createdDouble / 1000)
            self.updated = Date(timeIntervalSince1970: updatedDouble / 1000)
            self.compacting = try container.decodeIfPresent(Date.self, forKey: .compacting)
            self.archived = try container.decodeIfPresent(Date.self, forKey: .archived)
        }

        enum CodingKeys: String, CodingKey {
            case created, updated, compacting, archived
        }
    }

    struct SessionSummary: Codable, Equatable {
        let additions: Int?
        let deletions: Int?
        let files: Int?
    }

    struct ShareInfo: Codable, Equatable {
        let url: String
    }

    struct RevertInfo: Codable, Equatable {
        let messageID: String
        let partID: String?
        let snapshot: String?
        let diff: String?
    }

    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id
    }
}
