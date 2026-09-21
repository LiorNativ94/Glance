import AppKit
import UserNotifications
import GlanceCore

final class AlertNotifications: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private weak var model: AppModel?
    var openAlert: ((GlanceAlert) -> Void)?

    init(model: AppModel) {
        self.model = model
        super.init()
        center.delegate = self
        model.authorizeAlerts = { [weak self] completion in
            self?.center.requestAuthorization(options: [.alert]) { allowed, error in
                completion(allowed, error?.localizedDescription)
            }
        }
        model.onAlert = { [weak self] alert in self?.send(alert) }
    }

    private func send(_ alert: GlanceAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        var userInfo = ["kind": alert.kind.rawValue]
        if let destination = alert.destination { userInfo["destination"] = destination }
        content.userInfo = userInfo
        center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)) { [weak self] error in
            guard let error else { return }
            DispatchQueue.main.async {
                self?.model?.settingsError = "Couldn’t deliver a Glance alert: \(error.localizedDescription)"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in self?.model?.retryAlert(alert) }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let request = response.notification.request
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let raw = request.content.userInfo["kind"] as? String, let kind = AlertKind(rawValue: raw) {
            let alert = GlanceAlert(id: request.identifier, kind: kind, title: request.content.title,
                                    body: request.content.body,
                                    destination: request.content.userInfo["destination"] as? String)
            DispatchQueue.main.async { [weak self] in self?.openAlert?(alert) }
        }
        completionHandler()
    }
}
