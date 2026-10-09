// Takeed Notification Service Extension.
// The same file goes in every app: it replaces the OneSignal extension file.
// It downloads the notification image, adds the action buttons, and reports the
// receipt using the IDs the server puts in each notification (no App Group needed).

import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var content: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent,
              let takeed = content.userInfo["takeed"] as? [String: Any] else {
            return contentHandler(request.content)
        }
        self.content = content
        let group = DispatchGroup()

        // Receipt confirmation.
        if let receipt = takeed["receipt_id"] as? String, let appId = takeed["app_id"] as? String, let api = takeed["api"] as? String,
           let url = URL(string: "\(api)/api/v1/apps/\(appId)/events"), url.scheme == "https" || url.scheme == "http" {
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["type": "received", "receipt_id": receipt])
            group.enter()
            URLSession.shared.dataTask(with: req) { _, _, _ in group.leave() }.resume()
        }

        // Action buttons: one category per notification, registered on the fly.
        if let buttons = takeed["buttons"] as? [[String: Any]], !buttons.isEmpty, let id = takeed["notification_id"] as? String {
            let actions = buttons.prefix(3).compactMap { b -> UNNotificationAction? in
                guard let bid = b["id"] as? String, let text = b["text"] as? String else { return nil }
                return UNNotificationAction(identifier: bid, title: text, options: [.foreground])
            }
            let category = UNNotificationCategory(identifier: "takeed_\(id)", actions: actions, intentIdentifiers: [], options: [])
            group.enter()
            UNUserNotificationCenter.current().getNotificationCategories { existing in
                let kept = existing.filter { !$0.identifier.hasPrefix("takeed_") }
                UNUserNotificationCenter.current().setNotificationCategories(kept.union([category]))
                content.categoryIdentifier = category.identifier
                group.leave()
            }
        }

        // Image.
        if let raw = takeed["image"] as? String, let url = URL(string: raw), url.scheme == "https" || url.scheme == "http" {
            group.enter()
            URLSession.shared.downloadTask(with: url) { file, response, _ in
                defer { group.leave() }
                guard let file = file else { return }
                let ext = (response?.suggestedFilename as NSString?)?.pathExtension.lowercased()
                let name = UUID().uuidString + "." + ((ext?.isEmpty == false ? ext : nil) ?? "jpg")
                let target = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
                try? FileManager.default.moveItem(at: file, to: target)
                if let attachment = try? UNNotificationAttachment(identifier: "image", url: target) {
                    content.attachments = [attachment]
                }
            }.resume()
        }

        group.notify(queue: .main) { contentHandler(content) }
    }

    override func serviceExtensionTimeWillExpire() {
        if let handler = contentHandler, let content = content { handler(content) }
    }
}
