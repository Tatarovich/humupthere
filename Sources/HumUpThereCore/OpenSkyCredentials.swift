import Foundation

/// Личные ключи доступа к OpenSky.
///
/// OpenSky требует регистрации: каждый пользователь создаёт свой API-клиент на странице
/// Account и вводит clientId/clientSecret в настройках приложения. Анонимный доступ тоже
/// работает, но у него всего 400 кредитов в сутки против 4000 у обычного пользователя.
public struct OpenSkyCredentials: Codable, Sendable, Equatable {
    public let clientId: String
    public let clientSecret: String

    public init(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
    }

    public var isValid: Bool {
        !clientId.trimmingCharacters(in: .whitespaces).isEmpty
            && !clientSecret.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Маска для показа в интерфейсе: сам секрет не светим.
    public var maskedClientId: String {
        guard clientId.count > 6 else { return "•••" }
        return "\(clientId.prefix(4))…\(clientId.suffix(2))"
    }
}

/// Хранилище ключей: отдельный файл в папке данных приложения с правами «только владелец».
public enum OpenSkyCredentialsStore {
    public static func defaultFileURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("HumUpThere", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("credentials.json")
    }

    /// Читает ключи. Понимает и camelCase, и snake_case: люди сохраняют по-разному.
    public static func load(from url: URL? = defaultFileURL()) -> OpenSkyCredentials? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }

        if let decoded = try? JSONDecoder().decode(OpenSkyCredentials.self, from: data), decoded.isValid {
            return decoded
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let identifier = (root["clientId"] ?? root["client_id"]) as? String
        let secret = (root["clientSecret"] ?? root["client_secret"]) as? String
        guard let identifier, let secret else { return nil }

        let credentials = OpenSkyCredentials(clientId: identifier, clientSecret: secret)
        return credentials.isValid ? credentials : nil
    }

    @discardableResult
    public static func save(_ credentials: OpenSkyCredentials, to url: URL? = nil) -> Bool {
        // Значение по умолчанию нельзя вычислять в сигнатуре: путь зависит от FileManager.
        guard let target = url ?? defaultFileURL() else { return false }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(credentials) else { return false }

        do {
            try data.write(to: target, options: .atomic)
            // В файле лежит секрет — доступ только владельцу.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            return true
        } catch {
            return false
        }
    }

    public static func delete(at url: URL? = nil) {
        guard let target = url ?? defaultFileURL() else { return }
        try? FileManager.default.removeItem(at: target)
    }
}
