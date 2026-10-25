import Foundation
import UserNotifications
import HumUpThereCore

/// Уведомления о бортах, которые только что вошли в радиус.
///
/// Борта появляются в списке каждые 15 секунд, поэтому важно не превратить это в спам.
/// Повторы отсекаются выше, в `AircraftVisitTracker`: сюда попадают только те борта,
/// которых не было в радиусе последние полчаса, не больше трёх за одно обновление.
@MainActor
final class NotificationCenterManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCenterManager()

    private(set) var isAuthorized = false

    private override init() {
        super.init()
    }

    /// `UNUserNotificationCenter` работает только у настоящего бандла. При запуске
    /// «голого» бинарника из `.build` он падает с исключением, поэтому проверяем заранее
    /// и в этом случае просто ничего не делаем.
    private static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    func prepare() {
        guard Self.isAvailable else { return }
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshStatus() }
    }

    /// Только читает состояние, ничего не спрашивая у пользователя.
    func refreshStatus() async {
        guard Self.isAvailable else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = Self.isAllowed(settings.authorizationStatus)
    }

    /// Спрашивает разрешение. Вызывается, когда пользователь включает уведомления.
    func requestAuthorization() async -> Bool {
        guard Self.isAvailable else { return false }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
        case .notDetermined:
            isAuthorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            isAuthorized = false
        }
        return isAuthorized
    }

    private static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    // MARK: - Отправка

    func notify(aircraft: [Aircraft], text: T, format: DisplayFormat, sound: AlertSound) {
        guard isAuthorized, Self.isAvailable else { return }

        for item in aircraft {
            let content = UNMutableNotificationContent()
            content.title = text(.notifyTitle)

            var parts = [item.displayName]
            if let route = item.routeTitle(russian: text.isRussian) {
                parts.append(route)
            } else {
                parts.append(item.altitudeText(format))
            }
            parts.append(item.distanceText(format))
            content.body = parts.joined(separator: " · ")
            content.sound = notificationSound(sound)

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    func sendTest(text: T, sound: AlertSound) {
        guard isAuthorized, Self.isAvailable else { return }

        let content = UNMutableNotificationContent()
        content.title = text(.appName)
        content.body = text(.notifyTestBody)
        content.sound = notificationSound(sound)

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Свой звук из бандла; если файла нет — системный, чтобы уведомление не потерялось.
    private func notificationSound(_ sound: AlertSound) -> UNNotificationSound {
        guard sound.url != nil else { return .default }
        return UNNotificationSound(named: UNNotificationSoundName(sound.fileName))
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Без этого уведомление не покажется, пока приложение на переднем плане.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
