//
//  AppDelegate.swift
//  RemoteAgent
//
//  Created for notification support
//

import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(registerForRemoteNotifications),
            name: .registerForRemoteNotifications,
            object: nil
        )
        
        if NotificationManager.shared.isEnabled && NotificationManager.shared.deviceToken == nil {
            application.registerForRemoteNotifications()
        }
        
        return true
    }
    
    @objc private func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        NotificationManager.shared.deviceToken = tokenString
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
}
