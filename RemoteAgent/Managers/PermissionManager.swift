import Foundation
import Combine

@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    @Published var pendingPermissions: [Permission] = []
    @Published var isLoading = false
    @Published var error: String?
    
    nonisolated(unsafe) private var timer: Timer?
    
    private init() {
        startPolling()
    }
    
    deinit {
        stopPolling()
    }
    
    func fetchPermissions() async {
        isLoading = true
        error = nil
        
        do {
            let client = OpenCodeAPIClient.shared
            let permissions = try await client.listPermissions()
            
            pendingPermissions = permissions
            isLoading = false
        } catch let err {
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
        do {
            let client = OpenCodeAPIClient.shared
            try await client.respondToPermission(
                sessionID: sessionID,
                permissionID: permissionID,
                response: response,
                directory: directory
            )
            
            await fetchPermissions()
            return true
        } catch let err {
            error = err.localizedDescription
            return false
        }
    }
    
    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchPermissions()
            }
        }
    }
    
    nonisolated private func stopPolling() {
        timer?.invalidate()
    }
}
