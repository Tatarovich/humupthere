import Foundation

/// Откуда пришли данные — показываем это в интерфейсе, чтобы не выглядело как магия.
public enum ADSBSource: String, Sendable {
    case adsbLol = "adsb.lol"
    case openSky = "OpenSky Network"
}

public struct ADSBFetchResult: Sendable {
    public let aircraft: [Aircraft]
    public let source: ADSBSource
    /// Остаток кредитов OpenSky из заголовка ответа — показываем пользователю.
    public let creditsRemaining: Int?

    public init(aircraft: [Aircraft], source: ADSBSource, creditsRemaining: Int? = nil) {
        self.aircraft = aircraft
        self.source = source
        self.creditsRemaining = creditsRemaining
    }
}

public enum ADSBError: LocalizedError {
    case invalidLocation
    case noHTTPResponse
    case http(Int, String)
    case decoding(String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidLocation:
            return "Некорректные координаты"
        case .noHTTPResponse:
            return "Источник не ответил по HTTP"
        case let .http(code, body):
            return "Источник вернул код \(code)" + Self.explanation(for: code, body: body)
        case let .decoding(message):
            return "Не удалось разобрать ответ: \(message)"
        case let .transport(message):
            return "Сеть недоступна: \(message)"
        }
    }

    /// Понятное пояснение вместо сырого тела ответа: у 429 и 403 это HTML-страница,
    /// и показывать её в интерфейсе бессмысленно.
    private static func explanation(for code: Int, body: String) -> String {
        switch code {
        case 429:
            return " — слишком много запросов, попробую позже"
        case 403:
            return " — источник закрыл доступ"
        case 404:
            return " — не найдено"
        default:
            let cleaned = plainText(body)
            return cleaned.isEmpty ? "" : ": \(cleaned.prefix(100))"
        }
    }

    /// Грубо вырезает HTML-теги и схлопывает пробелы.
    private static func plainText(_ text: String) -> String {
        var result = ""
        var insideTag = false
        for character in text {
            switch character {
            case "<": insideTag = true
            case ">": insideTag = false
            default: if !insideTag { result.append(character) }
            }
        }
        return result.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

/// Клиент открытых ADS-B источников.
///
/// Порядок источников зависит от того, есть ли у пользователя ключи OpenSky.
/// Без ключей основной — adsb.lol: он отдаёт окружность «точка + радиус» и не требует
/// регистрации. С ключами основным становится OpenSky: за пределами Европы он видит
/// заметно больше, потому что добирает борта мультилатерацией, а личные ключи поднимают
/// суточный лимит с 400 кредитов до 4000.
public struct ADSBClient: Sendable {
    private static let userAgent = "HumUpThere/0.1 (macOS; personal use)"

    private let auth: OpenSkyAuth

    public init(auth: OpenSkyAuth = OpenSkyAuth()) {
        self.auth = auth
    }

    public func fetch(
        lat: Double,
        lon: Double,
        radiusKm: Double,
        includeGround: Bool
    ) async throws -> ADSBFetchResult {
        let hasCredentials = await auth.isConfigured

        // С ключами первым спрашиваем OpenSky, без ключей — adsb.lol.
        let order: [ADSBSource] = hasCredentials ? [.openSky, .adsbLol] : [.adsbLol, .openSky]

        var firstError: Error?
        for source in order {
            do {
                switch source {
                case .adsbLol:
                    let aircraft = try await fetchAdsbLol(
                        lat: lat, lon: lon, radiusKm: radiusKm, includeGround: includeGround
                    )
                    return ADSBFetchResult(aircraft: aircraft, source: .adsbLol)
                case .openSky:
                    let outcome = try await fetchOpenSky(
                        lat: lat, lon: lon, radiusKm: radiusKm, includeGround: includeGround
                    )
                    return ADSBFetchResult(
                        aircraft: outcome.aircraft,
                        source: .openSky,
                        creditsRemaining: outcome.creditsRemaining
                    )
                }
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        throw firstError ?? ADSBError.transport("ни один источник не ответил")
    }

    // MARK: - adsb.lol

    private func fetchAdsbLol(
        lat: Double,
        lon: Double,
        radiusKm: Double,
        includeGround: Bool
    ) async throws -> [Aircraft] {
        // Источник принимает радиус в морских милях, максимум 250.
        let nauticalMiles = max(1, min(250, Int((radiusKm / 1.852).rounded(.up))))
        let latText = String(format: "%.6f", lat)
        let lonText = String(format: "%.6f", lon)
        guard let url = URL(string: "https://api.adsb.lol/v2/point/\(latText)/\(lonText)/\(nauticalMiles)") else {
            throw ADSBError.invalidLocation
        }

        let data = try await get(url)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ADSBError.decoding("ответ adsb.lol не является JSON-объектом")
        }
        let items = root["ac"] as? [[String: Any]] ?? []

        var result: [Aircraft] = []
        for item in items {
            guard let aircraftLat = number(item["lat"]), let aircraftLon = number(item["lon"]) else {
                continue
            }

            var onGround = false
            var altitudeFt: Double?
            if let altitudeValue = item["alt_baro"] {
                if let text = altitudeValue as? String {
                    if text.lowercased() == "ground" {
                        onGround = true
                        altitudeFt = 0
                    }
                } else if let value = number(altitudeValue) {
                    altitudeFt = value
                }
            }
            if item["alt_baro"] == nil, let ground = number(item["alt_geom"]) {
                altitudeFt = ground
            }

            if onGround && !includeGround { continue }

            let distance = Geo.distanceKm(lat, lon, aircraftLat, aircraftLon)
            guard distance <= radiusKm else { continue }

            let callsign = (item["flight"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            result.append(
                Aircraft(
                    id: (item["hex"] as? String) ?? UUID().uuidString,
                    callsign: (callsign?.isEmpty ?? true) ? nil : callsign,
                    registration: nonEmpty(item["r"] as? String),
                    typeCode: nonEmpty(item["t"] as? String),
                    altitudeFt: altitudeFt,
                    groundSpeedKt: number(item["gs"]),
                    trackDeg: number(item["track"]),
                    verticalRateFpm: number(item["baro_rate"]) ?? number(item["geom_rate"]),
                    squawk: nonEmpty(item["squawk"] as? String),
                    onGround: onGround,
                    lat: aircraftLat,
                    lon: aircraftLon,
                    distanceKm: distance,
                    bearingDeg: Geo.bearingDeg(lat, lon, aircraftLat, aircraftLon)
                )
            )
        }
        return result
    }

    // MARK: - OpenSky Network

    /// Запрос бортов у OpenSky. С ключами — по токену, без ключей — анонимно.
    ///
    /// Возвращает ещё и остаток кредитов, а при 429 запоминает, сколько просил подождать,
    /// чтобы не дёргать источник впустую.
    private func fetchOpenSky(
        lat: Double,
        lon: Double,
        radiusKm: Double,
        includeGround: Bool
    ) async throws -> (aircraft: [Aircraft], creditsRemaining: Int?) {
        if let blocked = await auth.blockedFor {
            throw OpenSkyError.http(429, retryAfter: blocked)
        }

        var token = try await auth.accessToken()
        do {
            return try await requestOpenSky(
                lat: lat, lon: lon, radiusKm: radiusKm, includeGround: includeGround, token: token
            )
        } catch OpenSkyError.unauthorized {
            // Токен мог протухнуть раньше срока — берём новый и пробуем ещё раз.
            token = try await auth.accessToken(forceRefresh: true)
            return try await requestOpenSky(
                lat: lat, lon: lon, radiusKm: radiusKm, includeGround: includeGround, token: token
            )
        }
    }

    private func requestOpenSky(
        lat: Double,
        lon: Double,
        radiusKm: Double,
        includeGround: Bool,
        token: String?
    ) async throws -> (aircraft: [Aircraft], creditsRemaining: Int?) {
        let box = Geo.boundingBox(lat: lat, lon: lon, radiusKm: radiusKm)
        let urlText = "https://opensky-network.org/api/states/all"
            + "?lamin=\(box.lamin)&lomin=\(box.lomin)&lamax=\(box.lamax)&lomax=\(box.lomax)"
        guard let url = URL(string: urlText) else { throw ADSBError.invalidLocation }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ADSBError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw ADSBError.noHTTPResponse }

        let credits = http.value(forHTTPHeaderField: "X-Rate-Limit-Remaining").flatMap(Int.init)
        await auth.noteCredits(credits)

        if http.statusCode == 401 {
            throw OpenSkyError.unauthorized
        }
        if http.statusCode == 429 {
            let retryAfter = http.value(forHTTPHeaderField: "X-Rate-Limit-Retry-After-Seconds")
                .flatMap(TimeInterval.init)
            await auth.noteRateLimit(retryAfter: retryAfter)
            throw OpenSkyError.http(429, retryAfter: retryAfter)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenSkyError.http(http.statusCode, retryAfter: nil)
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ADSBError.decoding("ответ OpenSky не является JSON-объектом")
        }
        let states = root["states"] as? [[Any]] ?? []

        var result: [Aircraft] = []
        for state in states {
            guard state.count > 14 else { continue }
            guard let aircraftLat = state[6] as? Double, let aircraftLon = state[5] as? Double else {
                continue
            }

            let onGround = (state[8] as? Bool) ?? false
            if onGround && !includeGround { continue }

            let distance = Geo.distanceKm(lat, lon, aircraftLat, aircraftLon)
            guard distance <= radiusKm else { continue }

            let altitudeMeters = (state[7] as? Double) ?? (state[13] as? Double)
            let velocityMs = state[9] as? Double
            let verticalRateMs = state[11] as? Double
            let callsign = (state[1] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            result.append(
                Aircraft(
                    id: (state[0] as? String) ?? UUID().uuidString,
                    callsign: (callsign?.isEmpty ?? true) ? nil : callsign,
                    registration: nil,
                    typeCode: nil,
                    altitudeFt: altitudeMeters.map { $0 * 3.280_839_895 },
                    groundSpeedKt: velocityMs.map { $0 * 1.943_844 },
                    trackDeg: state[10] as? Double,
                    verticalRateFpm: verticalRateMs.map { $0 * 196.850_394 },
                    squawk: nonEmpty(state[14] as? String),
                    onGround: onGround,
                    lat: aircraftLat,
                    lon: aircraftLon,
                    distanceKm: distance,
                    bearingDeg: Geo.bearingDeg(lat, lon, aircraftLat, aircraftLon)
                )
            )
        }
        return (result, credits)
    }

    // MARK: - Сеть и вспомогательное

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ADSBError.noHTTPResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw ADSBError.http(http.statusCode, String(data: data.prefix(300), encoding: .utf8) ?? "")
            }
            return data
        } catch let error as ADSBError {
            throw error
        } catch {
            throw ADSBError.transport(error.localizedDescription)
        }
    }

    private func number(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let text = value as? String { return Double(text) }
        return nil
    }

    private func nonEmpty(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
