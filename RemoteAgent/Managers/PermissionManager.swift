import Foundation
import Combine

@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    @Published var pendingPermissions: [Permission] = []
    @Published var isLoading = false
    @Published var error: String?
    
    nonisolated(unsafe) private var eventTask: Task<Void, Never>?
    private let eventClient = EventClient.shared
    
    private init() {
        startEventListener()
    }
    
    deinit {
        eventTask?.cancel()
        eventTask = nil
    }
    
    func fetchPermissions() async {
        isLoading = true
        error = nil
        
        do {
            let client = OpenCodeAPIClient.shared
            let permissions = try await client.listPermissions()
            
            print("PermissionManager: Fetched \(permissions.count) pending permissions")
            for perm in permissions {
                print("  - \(perm.id): \(perm.title) for session \(perm.sessionID)")
            }
            
            pendingPermissions = permissions
            isLoading = false
        } catch let err {
            print("PermissionManager: Error fetching permissions: \(err)")
            error = err.localizedDescription
            isLoading = false
        }
    }

    func respondToPermission(
        sessionID: String,
        permissionID: String,
        response: PermissionResponse,
        directory: String? = nil
    ) async -> Bool {
        print("PermissionManager: Responding to permission \(permissionID) with \(response.rawValue)")
        do {
            let client = OpenCodeAPIClient.shared
            try await client.respondToPermission(
                sessionID: sessionID,
                permissionID: permissionID,
                response: response,
                directory: directory
            )
            
            print("PermissionManager: Response sent successfully")
            return true
        } catch let err {
            print("PermissionManager: Error responding to permission: \(err)")
            error = err.localizedDescription
            return false
        }
    }
    
    private func startEventListener() {
        eventTask = Task {
            print("PermissionManager: Starting SSE event listener")
            
            // Initial fetch to get any existing permissions
            await fetchPermissions()
            
            let eventStream = eventClient.eventStream(directory: nil)
            
            do {
                for try await event in eventStream {
                    switch event.type {
                    case "permission.updated":
                        handlePermissionUpdated(event)
                    case "permission.replied":
                        handlePermissionReplied(event)
                    default:
                        break
                    }
                }
            } catch {
                print("PermissionManager: Event stream error: \(error)")
            }
        }
    }
    
    private func stopEventListener() {
        eventTask?.cancel()
        eventTask = nil
    }
    
    private func handlePermissionUpdated(_ event: ServerEvent) {
        print("PermissionManager: permission.updated event received")
        
        guard let permissionData = event.properties["permission"] as? [String: Any],
              let permission = try? Permission.decode(from: permissionData) else {
            print("PermissionManager: Failed to decode permission from event")
            return
        }
        
        print("PermissionManager: New permission request: \(permission.id)")
        
        // Add permission if not already in list
        if !pendingPermissions.contains(where: { $0.id == permission.id }) {
            pendingPermissions.append(permission)
        }
    }
    
    private func handlePermissionReplied(_ event: ServerEvent) {
        guard let sessionID = event.properties["sessionID"] as? String,
              let permissionID = event.properties["permissionID"] as? String else {
            print("PermissionManager: Invalid permission.replied event")
            return
        }
        
        print("PermissionManager: permission.replied event - removing \(permissionID)")
        
        // Remove the permission from list
        pendingPermissions.removeAll { $0.id == permissionID }
    }
    
    private func restartEventListener() {
        stopEventListener()
        startEventListener()
    }
}

// Helper to decode Permission from dictionary
extension Permission {
    static func decode(from dict: [String: Any]) throws -> Permission {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(Permission.self, from: data)
    }
}
