import Foundation
import ServiceManagement

/// Автозапуск вместе с системой.
///
/// Используем SMAppService — системный механизм macOS 13+: приложение появляется
/// в «Объектах входа» и в настройках уведомлений, а не подсовывает LaunchAgent
/// в ~/Library/LaunchAgents, как делают вручную.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status == .enabled else { return }
            try SMAppService.mainApp.unregister()
        }
    }

    /// Текст состояния для настроек и диагностики.
    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "включён"
        case .notRegistered: return "не зарегистрирован"
        case .notFound: return "приложение не найдено системой"
        case .requiresApproval: return "требуется подтверждение в настройках macOS"
        @unknown default: return "неизвестное состояние"
        }
    }
}
