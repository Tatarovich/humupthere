import Foundation

public enum OpenSkyError: LocalizedError {
    case unauthorized
    case http(Int, retryAfter: TimeInterval?)
    case badResponse(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "OpenSky: ключи не подошли — проверьте clientId и clientSecret"
        case let .http(code, retryAfter):
            switch code {
            case 429:
                if let retryAfter {
                    return "OpenSky: лимит запросов исчерпан, подожду \(Self.interval(retryAfter))"
                }
                return "OpenSky: лимит запросов исчерпан, попробую позже"
            case 401:
                return "OpenSky: ключи не подошли — проверьте clientId и clientSecret"
            default:
                return "OpenSky: источник вернул код \(code)"
            }
        case let .badResponse(message):
            return "OpenSky: \(message)"
        }
    }

    private static func interval(_ seconds: TimeInterval) -> String {
        if seconds >= 3600 {
            return "\(Int((seconds / 3600).rounded())) ч"
        }
        if seconds >= 60 {
            return "\(Int((seconds / 60).rounded())) мин"
        }
        return "\(Int(seconds.rounded())) с"
    }
}

/// Доступ к OpenSky по OAuth2.
///
/// Схема простая: обмениваем clientId/clientSecret на токен, который живёт 30 минут.
/// Держим его в памяти и обновляем заранее; при 401 берём новый и повторяем запрос.
/// Ключей нет — работаем анонимно (`accessToken` вернёт nil), но у анонимного доступа
/// всего 400 кредитов в сутки.
public actor OpenSkyAuth {
    private let session: URLSession
    private var credentials: OpenSkyCredentials?
    private var token: String?
    private var tokenExpiry: Date?
    /// Если источник попросил подождать — не дёргаем его до этого момента.
    private var blockedUntil: Date?

    /// Остаток кредитов из последнего ответа: показываем в настройках и диагностике.
    public private(set) var creditsRemaining: Int?

    public init(credentials: OpenSkyCredentials? = nil, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    public var isConfigured: Bool {
        credentials?.isValid == true
    }

    public var configuredClientId: String? {
        guard let credentials, credentials.isValid else { return nil }
        return credentials.clientId
    }

    public func update(credentials newValue: OpenSkyCredentials?) {
        credentials = newValue
        token = nil
        tokenExpiry = nil
        blockedUntil = nil
        creditsRemaining = nil
    }

    /// Сколько ещё ждать после 429. nil — ждать нечего.
    public var blockedFor: TimeInterval? {
        guard let blockedUntil else { return nil }
        let remaining = blockedUntil.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    public func noteRateLimit(retryAfter: TimeInterval?) {
        // Если источник не сказал срок, ставим свой: пять минут.
        let seconds = max(retryAfter ?? 300, 5)
        blockedUntil = Date().addingTimeInterval(seconds)
    }

    public func noteCredits(_ remaining: Int?) {
        guard let remaining else { return }
        creditsRemaining = remaining
    }

    public func clearRateLimit() {
        blockedUntil = nil
    }

    /// Токен для запросов. nil означает «ключей нет, спрашиваем анонимно».
    public func accessToken(forceRefresh: Bool = false) async throws -> String? {
        guard let credentials, credentials.isValid else { return nil }

        if !forceRefresh,
           let token,
           let expiry = tokenExpiry,
           expiry.timeIntervalSinceNow > 60 {
            return token
        }

        let fresh = try await requestToken(credentials)
        token = fresh.value
        tokenExpiry = fresh.expiry
        return fresh.value
    }

    private func requestToken(_ credentials: OpenSkyCredentials) async throws -> (value: String, expiry: Date) {
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "client_id", value: credentials.clientId),
            URLQueryItem(name: "client_secret", value: credentials.clientSecret),
        ]

        guard
            let url = URL(string: "https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token"),
            let encoded = body.percentEncodedQuery?.data(using: .utf8)
        else {
            throw OpenSkyError.badResponse("некорректный адрес авторизации")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = encoded
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("HumUpThere/0.1 (macOS; personal use)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenSkyError.badResponse("нет ответа по HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            // 400 и 401 здесь означают одно: ключи не подошли.
            if http.statusCode == 400 || http.statusCode == 401 || http.statusCode == 403 {
                throw OpenSkyError.unauthorized
            }
            throw OpenSkyError.http(http.statusCode, retryAfter: nil)
        }
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let value = root["access_token"] as? String
        else {
            throw OpenSkyError.badResponse("в ответе нет токена")
        }

        let lifetime = (root["expires_in"] as? Double) ?? 1800
        return (value, Date().addingTimeInterval(lifetime))
    }
}
