//
//  YavenNotificationManager.swift
//  leanring-buddy
//

import Foundation
import UserNotifications

@MainActor
final class YavenNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static var onThreadSelected: ((UUID) -> Void)?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func send(title: String, body: String, threadID: UUID? = nil) async {
        guard await requestAuthorizationIfNeeded() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let threadID {
            content.userInfo = ["threadID": threadID.uuidString]
        }

        let request = UNNotificationRequest(
            identifier: "yaven-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Yaven notification failed: \(error)")
        }
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch {
                print("Yaven notification permission failed: \(error)")
                return false
            }
        @unknown default:
            return false
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let threadIDString = response.notification.request.content.userInfo["threadID"] as? String,
              let threadID = UUID(uuidString: threadIDString) else {
            return
        }
        await MainActor.run {
            Self.onThreadSelected?(threadID)
        }
    }
}
