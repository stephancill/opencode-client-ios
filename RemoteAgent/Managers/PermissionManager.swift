import Foundation
import Combine

class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    
    @Published var pendingPermissions: [Permission] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private var timer: Timer?
    
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
            
            await MainActor.run {
                self.pendingPermissions = permissions
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
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
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
            return false
        }
    }

    @MainActor
    private func updatePermissions(_ permissions: [Permission]) {
        self.pendingPermissions = permissions
        self.isLoading = false
        self.error = nil
    }

    @MainActor
    private func updateError(_ error: Error) {
        self.error = error.localizedDescription
        self.isLoading = false
    }
    
    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task {
                await self?.fetchPermissions()
            }
        }
    }
    
    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}
