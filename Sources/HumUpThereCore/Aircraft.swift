import Foundation

/// Направление движения борта по вертикали.
public enum ClimbState: String, Sendable {
    case climbing
    case descending
    case level
    case unknown

    public var symbolName: String {
        switch self {
        case .climbing: return "arrow.up.right"
        case .descending: return "arrow.down.right"
        case .level: return "arrow.right"
        case .unknown: return "questionmark"
        }
    }
}

/// Один борт, приведённый к общему виду независимо от источника данных.
public struct Aircraft: Identifiable, Hashable, Sendable {
    public let id: String              // ICAO24, он же hex
    public let callsign: String?
    public let registration: String?
    /// Тип борта источник отдаёт непостоянно, поэтому значение может уточняться кэшем.
    public var typeCode: String?
    /// Маршрут подставляется отдельным справочником уже после получения списка бортов.
    public var route: FlightRoute?
    public let altitudeFt: Double?
    public let groundSpeedKt: Double?
    public let trackDeg: Double?
    public let verticalRateFpm: Double?
    public let squawk: String?
    public let onGround: Bool
    public let lat: Double
    public let lon: Double
    public let distanceKm: Double
    public let bearingDeg: Double

    public init(
        id: String,
        callsign: String?,
        registration: String?,
        typeCode: String?,
        route: FlightRoute? = nil,
        altitudeFt: Double?,
        groundSpeedKt: Double?,
        trackDeg: Double?,
        verticalRateFpm: Double?,
        squawk: String?,
        onGround: Bool,
        lat: Double,
        lon: Double,
        distanceKm: Double,
        bearingDeg: Double
    ) {
        self.id = id
        self.callsign = callsign
        self.registration = registration
        self.typeCode = typeCode
        self.route = route
        self.altitudeFt = altitudeFt
        self.groundSpeedKt = groundSpeedKt
        self.trackDeg = trackDeg
        self.verticalRateFpm = verticalRateFpm
        self.squawk = squawk
        self.onGround = onGround
        self.lat = lat
        self.lon = lon
        self.distanceKm = distanceKm
        self.bearingDeg = bearingDeg
    }

    /// Что показывать крупно: позывной, иначе регистрация, иначе hex.
    public var displayName: String {
        if let callsign, !callsign.isEmpty { return callsign }
        if let registration, !registration.isEmpty { return registration }
        return id.uppercased()
    }

    public var altitudeMeters: Double? {
        altitudeFt.map { $0 * 0.3048 }
    }

    public var speedKmh: Double? {
        groundSpeedKt.map { $0 * 1.852 }
    }

    public var climbState: ClimbState {
        guard let fpm = verticalRateFpm else { return .unknown }
        if fpm > 150 { return .climbing }
        if fpm < -150 { return .descending }
        return .level
    }

    // MARK: - Путь до пункта назначения

    /// Сколько ещё километров по прямой до аэропорта назначения.
    public var distanceToDestinationKm: Double? {
        guard
            let destination = route?.destination,
            let lat = destination.latitude,
            let lon = destination.longitude
        else {
            return nil
        }
        return Geo.distanceKm(self.lat, self.lon, lat, lon)
    }

    /// Оценка времени до посадки по текущей путевой скорости.
    ///
    /// Считаем только для бортов в крейсерском режиме. У только что взлетевшего
    /// путевая скорость может быть 300 км/ч, и деление дистанции на неё даёт
    /// фантастику вроде «Москва — Владивосток за 19 часов». В крейсере скорость
    /// точна, поэтому и оценка честная: лучше промолчать, чем соврать.
    public var hoursToDestination: Double? {
        guard
            !onGround,
            let distance = distanceToDestinationKm,
            let speed = speedKmh,
            speed >= 500
        else {
            return nil
        }
        let hours = distance / speed
        return hours <= 24 ? hours : nil
    }

    // MARK: - Тексты для интерфейса

    public func distanceText(_ format: DisplayFormat) -> String {
        format.km(distanceKm)
    }

    public func bearingText(_ format: DisplayFormat) -> String {
        format.bearing(bearingDeg)
    }

    public func altitudeText(_ format: DisplayFormat) -> String {
        guard !onGround else {
            return format.isRussian ? "на земле" : "on ground"
        }
        guard let meters = altitudeMeters else {
            return format.isRussian ? "высота н/д" : "altitude n/a"
        }
        return format.meters(meters)
    }

    public func speedText(_ format: DisplayFormat) -> String? {
        speedKmh.map { format.kmh($0) }
    }

    public func verticalText(_ format: DisplayFormat) -> String? {
        guard let fpm = verticalRateFpm, abs(fpm) >= 50 else { return nil }
        return format.verticalSpeed(fpm)
    }

    /// Короткое название авиакомпании для строки списка.
    public var airlineName: String? {
        route?.shortAirline
    }

    public func routeTitle(russian: Bool) -> String? {
        route?.title(russian: russian)
    }

    public func squawkText() -> String? {
        guard let squawk, !squawk.isEmpty, squawk != "0000" else { return nil }
        return "сквок \(squawk)"
    }
}
