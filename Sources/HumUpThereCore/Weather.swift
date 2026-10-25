import Foundation

/// Погода в точке наблюдения — нужна, чтобы ответить на вопрос «увижу ли я этот борт глазами».
public struct WeatherSnapshot: Codable, Sendable, Equatable {
    public let fetchedAt: Date
    public let temperatureC: Double?
    public let dewpointC: Double?
    public let cloudCover: Int?
    public let cloudCoverLow: Int?
    public let cloudCoverMid: Int?
    public let cloudCoverHigh: Int?
    public let visibilityMeters: Double?
    public let windSpeedKmh: Double?
    public let windDirectionDeg: Double?
    public let isDay: Bool?
    public let weatherCode: Int?

    public init(
        fetchedAt: Date,
        temperatureC: Double?,
        dewpointC: Double?,
        cloudCover: Int?,
        cloudCoverLow: Int?,
        cloudCoverMid: Int?,
        cloudCoverHigh: Int?,
        visibilityMeters: Double?,
        windSpeedKmh: Double?,
        windDirectionDeg: Double?,
        isDay: Bool?,
        weatherCode: Int?
    ) {
        self.fetchedAt = fetchedAt
        self.temperatureC = temperatureC
        self.dewpointC = dewpointC
        self.cloudCover = cloudCover
        self.cloudCoverLow = cloudCoverLow
        self.cloudCoverMid = cloudCoverMid
        self.cloudCoverHigh = cloudCoverHigh
        self.visibilityMeters = visibilityMeters
        self.windSpeedKmh = windSpeedKmh
        self.windDirectionDeg = windDirectionDeg
        self.isDay = isDay
        self.weatherCode = weatherCode
    }

    /// Оценка низа облаков по правилу «125 метров на градус» разницы между температурой
    /// и точкой росы. Это высота конденсации, а не измерение: готовой высоты облаков
    /// открытый источник не отдаёт (проверено — поле приходит пустым).
    public var estimatedCloudBaseMeters: Double? {
        guard let temperature = temperatureC, let dewpoint = dewpointC else { return nil }
        let spread = temperature - dewpoint
        guard spread >= 0 else { return nil }
        return min(max(spread * 125, 30), 6000)
    }

    public var visibilityKm: Double? {
        visibilityMeters.map { $0 / 1000 }
    }
}

/// Ответ на вопрос «увижу ли я борт глазами».
public enum VisibilityVerdict: String, Sendable {
    case clear        // небо почти чистое
    case gaps         // облака с просветами
    case belowClouds  // борт идёт ниже облаков
    case overcast     // сплошная облачность, борт за облаками
    case haze         // дымка или туман
    case night        // темно: видно только огни и только вблизи
    case unknown

    public var symbolName: String {
        switch self {
        case .clear: return "sun.max"
        case .gaps: return "cloud.sun"
        case .belowClouds: return "eye"
        case .overcast: return "cloud"
        case .haze: return "cloud.fog"
        case .night: return "moon.stars"
        case .unknown: return "questionmark"
        }
    }

    /// Стоит ли вообще поднимать голову.
    public var isVisible: Bool {
        self == .clear || self == .gaps || self == .belowClouds
    }
}

public extension WeatherSnapshot {
    /// Оценка видимости борта на заданной высоте.
    func verdict(forAltitudeMeters altitude: Double?) -> VisibilityVerdict {
        guard let isDay else { return .unknown }
        if !isDay { return .night }

        if let visibility = visibilityMeters, visibility < 2000 {
            return .haze
        }

        let cover = cloudCover ?? 0
        if cover <= 25 { return .clear }
        if cover <= 60 { return .gaps }

        // Облачность сплошная: увидеть можно только то, что ниже облаков.
        if let altitude, let base = estimatedCloudBaseMeters, altitude <= base {
            return .belowClouds
        }
        return .overcast
    }
}

public enum WeatherError: LocalizedError {
    case http(Int)
    case badResponse(String)

    public var errorDescription: String? {
        switch self {
        case let .http(code):
            return "Погода: источник вернул код \(code)"
        case let .badResponse(message):
            return "Погода: \(message)"
        }
    }
}

/// Клиент Open-Meteo: бесплатно и без ключа.
///
/// Погода меняется медленно, поэтому держим снимок 15 минут: каждые 15 секунд
/// опрашивать её было бы бессмысленно.
public actor WeatherService {
    private var cache: [String: WeatherSnapshot] = [:]
    private let ttl: TimeInterval
    private let session: URLSession

    public init(ttl: TimeInterval = 15 * 60, session: URLSession = .shared) {
        self.ttl = ttl
        self.session = session
    }

    public func weather(lat: Double, lon: Double, force: Bool = false) async throws -> WeatherSnapshot {
        let key = String(format: "%.2f,%.2f", lat, lon)

        if !force, let cached = cache[key], Date().timeIntervalSince(cached.fetchedAt) < ttl {
            return cached
        }

        let snapshot = try await fetch(lat: lat, lon: lon)
        cache[key] = snapshot
        return snapshot
    }

    private func fetch(lat: Double, lon: Double) async throws -> WeatherSnapshot {
        let fields = [
            "temperature_2m", "dewpoint_2m", "cloud_cover", "cloud_cover_low",
            "cloud_cover_mid", "cloud_cover_high", "visibility", "weather_code",
            "wind_speed_10m", "wind_direction_10m", "is_day",
        ].joined(separator: ",")

        let urlText = "https://api.open-meteo.com/v1/forecast"
            + "?latitude=\(lat)&longitude=\(lon)"
            + "&current=\(fields)"
            + "&wind_speed_unit=kmh&timezone=UTC"
        guard let url = URL(string: urlText) else {
            throw WeatherError.badResponse("некорректный адрес запроса")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("HumUpThere/0.1 (macOS; personal use)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WeatherError.badResponse("нет ответа по HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WeatherError.http(http.statusCode)
        }
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let current = root["current"] as? [String: Any]
        else {
            throw WeatherError.badResponse("ответ не разобран")
        }

        func double(_ key: String) -> Double? {
            if let value = current[key] as? Double { return value }
            if let value = current[key] as? Int { return Double(value) }
            return nil
        }

        func integer(_ key: String) -> Int? {
            if let value = current[key] as? Int { return value }
            if let value = current[key] as? Double { return Int(value) }
            return nil
        }

        return WeatherSnapshot(
            fetchedAt: Date(),
            temperatureC: double("temperature_2m"),
            dewpointC: double("dewpoint_2m"),
            cloudCover: integer("cloud_cover"),
            cloudCoverLow: integer("cloud_cover_low"),
            cloudCoverMid: integer("cloud_cover_mid"),
            cloudCoverHigh: integer("cloud_cover_high"),
            visibilityMeters: double("visibility"),
            windSpeedKmh: double("wind_speed_10m"),
            windDirectionDeg: double("wind_direction_10m"),
            isDay: integer("is_day").map { $0 == 1 },
            weatherCode: integer("weather_code")
        )
    }
}
