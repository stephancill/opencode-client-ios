import Foundation
import UserNotifications

extension Notification.Name {
    static let registerForRemoteNotifications = Notification.Name("registerForRemoteNotifications")
}

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "notificationsEnabled")
        }
    }
    
    @Published var permissionStatus: UNAuthorizationStatus = .notDetermined
    
    @Published var deviceToken: String? {
        didSet {
            if let token = deviceToken {
                UserDefaults.standard.set(token, forKey: "deviceToken")
            } else {
                UserDefaults.standard.removeObject(forKey: "deviceToken")
            }
        }
    }
    
    private let notificationCenter = UNUserNotificationCenter.current()
    
    private override init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        self.deviceToken = UserDefaults.standard.string(forKey: "deviceToken")
        
        super.init()
        
        notificationCenter.delegate = self
        checkPermissionStatus()
    }
    
    func checkPermissionStatus() {
        notificationCenter.getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.permissionStatus = settings.authorizationStatus
            }
        }
    }
    
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        let options: UNAuthorizationOptions = [.alert, .sound]
        
        notificationCenter.requestAuthorization(options: options) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    self.isEnabled = true
                } else {
                    self.isEnabled = false
                }
                self.permissionStatus = granted ? .authorized : .denied
                completion(granted)
            }
        }
    }
    
    func toggleNotifications() {
        if permissionStatus == .notDetermined {
            requestAuthorization { _ in }
            return
        }
        
        if permissionStatus == .denied {
            return
        }
        
        isEnabled.toggle()
        
        if isEnabled {
            print("📱 Enabling notifications and requesting new token...")
            deviceToken = nil
            NotificationCenter.default.post(name: .registerForRemoteNotifications, object: nil)
        }
        
        if !isEnabled {
            print("📱 Disabling notifications...")
            deviceToken = nil
        }
    }
    
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Test Notification"
        content.body = "RemoteAgent notifications are working! 🎉"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Error sending test notification: \(error.localizedDescription)")
            }
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
