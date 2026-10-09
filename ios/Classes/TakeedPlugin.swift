import Flutter
import UIKit
import UserNotifications

/// iOS side of Takeed: APNs token, permission, foreground display, taps and buttons.
/// Images, buttons and receipts for notifications that arrive in the background are
/// handled by the Notification Service Extension (see sdk/ios).
public class TakeedPlugin: NSObject, FlutterPlugin, UNUserNotificationCenterDelegate {
    private var channel: FlutterMethodChannel?
    private var tokenWaiters: [FlutterResult] = []
    private var initialClick: [String: Any]?
    private var engineReady = false
    private weak var previousDelegate: UNUserNotificationCenterDelegate?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = TakeedPlugin()
        let channel = FlutterMethodChannel(name: "takeed", binaryMessenger: registrar.messenger())
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)

        let center = UNUserNotificationCenter.current()
        instance.previousDelegate = center.delegate
        center.delegate = instance
    }

    // MARK: - Method channel

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "configure":
            UserDefaults.standard.set(args["app_id"] as? String, forKey: "takeed.app_id")
            UserDefaults.standard.removeObject(forKey: "takeed.api_url")
            engineReady = true
            result(nil)
        case "pushToken":
            tokenWaiters.append(result)
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        case "permission":
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                DispatchQueue.main.async { result(TakeedPlugin.isAllowed(settings.authorizationStatus)) }
            }
        case "requestPermission":
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                DispatchQueue.main.async {
                    if granted { UIApplication.shared.registerForRemoteNotifications() }
                    result(granted)
                }
            }
        case "deviceInfo":
            result(deviceInfo())
        case "initialClick":
            result(initialClick)
            initialClick = nil
        case "displayForeground":
            // iOS decides in willPresent; nothing to do afterwards.
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
        if status == .authorized || status == .provisional { return true }
        if #available(iOS 14.0, *), status == .ephemeral { return true }
        return false
    }

    private func deviceInfo() -> [String: Any?] {
        var systemInfo = utsname()
        uname(&systemInfo)
        let model = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return [
            "device_model": model,
            "os_version": "iOS \(UIDevice.current.systemVersion)",
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            "language": Locale.preferredLanguages.first.map { String($0.prefix(2)) },
            "timezone": TimeZone.current.identifier,
        ]
    }

    /// Development builds (with a development provisioning profile) use the APNs sandbox.
    private static func isSandbox() -> Bool {
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let text = String(data: data, encoding: .isoLatin1) else {
            return false // App Store builds have no embedded profile.
        }
        let compact = text.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
        return compact.contains("<key>aps-environment</key><string>development</string>")
    }

    // MARK: - APNs registration

    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        let payload: [String: Any] = [
            "type": "ios",
            "token": token,
            "config_identifier": Bundle.main.bundleIdentifier ?? "",
            "apns_sandbox": TakeedPlugin.isSandbox(),
        ]
        let waiters = tokenWaiters
        tokenWaiters.removeAll()
        if waiters.isEmpty {
            channel?.invokeMethod("onToken", arguments: ["token": token])
        }
        waiters.forEach { $0(payload) }
    }

    public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        let waiters = tokenWaiters
        tokenWaiters.removeAll()
        waiters.forEach { $0(nil) }
    }

    // MARK: - Notification center

    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        guard let takeed = userInfo["takeed"] as? [String: Any] else {
            if let previous = previousDelegate, previous.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))) {
                previous.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
            } else {
                completionHandler([])
            }
            return
        }

        let show: UNNotificationPresentationOptions
        if #available(iOS 14.0, *) { show = [.banner, .list, .sound, .badge] } else { show = [.alert, .sound, .badge] }

        guard let channel = channel, engineReady else {
            completionHandler(show)
            return
        }
        channel.invokeMethod("onForeground", arguments: payload(notification.request.content, takeed: takeed, actionId: nil, url: takeed["url"] as? String)) { result in
            completionHandler((result as? Bool) == false ? [] : show)
        }
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        guard let takeed = content.userInfo["takeed"] as? [String: Any] else {
            if let previous = previousDelegate, previous.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))) {
                previous.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
            } else {
                completionHandler()
            }
            return
        }

        let actionId = response.actionIdentifier == UNNotificationDefaultActionIdentifier ? nil : response.actionIdentifier
        let buttons = takeed["buttons"] as? [[String: Any]] ?? []
        let buttonUrl = buttons.first { ($0["id"] as? String) == actionId }?["url"] as? String
        let url = TakeedPlugin.safeUrl(buttonUrl ?? takeed["url"] as? String)

        TakeedPlugin.report(takeed: takeed, type: "clicked", buttonId: actionId)

        let click = payload(content, takeed: takeed, actionId: actionId, url: url?.absoluteString)
        if engineReady, let channel = channel {
            channel.invokeMethod("onClick", arguments: click)
        } else {
            initialClick = click
        }

        if let url = url {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
        }
        completionHandler()
    }

    private func payload(_ content: UNNotificationContent, takeed: [String: Any], actionId: String?, url: String?) -> [String: Any?] {
        return [
            "notification_id": takeed["notification_id"] as? String,
            "title": content.title,
            "body": content.body,
            "url": url,
            "action_id": actionId,
            "data": takeed["data"],
            "buttons": takeed["buttons"],
        ]
    }

    static func safeUrl(_ raw: String?) -> URL? {
        guard let raw = raw, let url = URL(string: raw), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    /// Reports a receipt or click straight to Takeed (works when Flutter isn't running).
    static func report(takeed: [String: Any], type: String, buttonId: String?) {
        guard let receipt = takeed["receipt_id"] as? String,
              let appId = (takeed["app_id"] as? String) ?? UserDefaults.standard.string(forKey: "takeed.app_id"),
              let encoded = appId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              // Always the Takeed service, never an address taken from the message.
              let url = URL(string: "https://takeed-iq.com/api/v1/apps/\(encoded)/events") else { return }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["type": type, "receipt_id": receipt]
        if let buttonId = buttonId { body["button_id"] = buttonId }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request).resume()
    }
}
