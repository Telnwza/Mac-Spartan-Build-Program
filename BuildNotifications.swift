import AppKit
import UserNotifications

final class BuildNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = BuildNotifications()

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorizationIfNeeded() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            return try await center.requestAuthorization(options: [.alert, .sound])
        }
        return settings.authorizationStatus == .authorized
    }

    static func content(
        topEntity: String,
        succeeded: Bool,
        message: String,
        destination: URL?,
        sound: Bool
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = succeeded ? "Build สำเร็จ — \(topEntity)" : "Build ไม่สำเร็จ — \(topEntity)"
        content.body = message
        content.sound = sound ? .default : nil
        if let destination { content.userInfo = ["resultPath": destination.path] }
        return content
    }

    func send(
        topEntity: String,
        succeeded: Bool,
        message: String,
        destination: URL?,
        sound: Bool
    ) async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        let request = UNNotificationRequest(
            identifier: "local-build-\(UUID().uuidString)",
            content: Self.content(
                topEntity: topEntity, succeeded: succeeded, message: message,
                destination: destination, sound: sound
            ),
            trigger: nil
        )
        try await center.add(request)
    }

    @MainActor
    func runSmokeTest() async -> Bool {
        do {
            guard try await requestAuthorizationIfNeeded() else {
                print("NOTIFICATION TEST: authorization denied")
                return false
            }
            let top = "notification_test_\(UUID().uuidString.prefix(6))"
            let result = ProcessInfo.processInfo.environment["EDGE_NOTIFICATION_TEST_RESULT"]
                .map { URL(fileURLWithPath: $0) }
            try await send(topEntity: top, succeeded: true,
                           message: "ทดสอบแจ้งเตือนสำเร็จ", destination: result, sound: false)
            try await send(topEntity: top, succeeded: false,
                           message: "ทดสอบแจ้งเตือนล้มเหลว", destination: result, sound: false)
            try await Task.sleep(nanoseconds: 2_000_000_000)
            let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
                .filter { $0.request.content.title.contains(top) }
            print("NOTIFICATION TEST: delivered \(delivered.count)/2")
            return delivered.count == 2
        } catch {
            print("NOTIFICATION TEST: \(error.localizedDescription)")
            return false
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            completionHandler()
            return
        }
        let path = response.notification.request.content.userInfo["resultPath"] as? String
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let path {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            completionHandler()
        }
    }
}
