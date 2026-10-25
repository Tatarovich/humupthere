import Foundation

/// Геометрия на сфере: расстояния, азимуты, ограничивающие рамки.
public enum Geo {
    public static let earthRadiusKm = 6371.0088

    /// Расстояние между двумя точками по большому кругу, в километрах.
    public static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let dPhi = (lat2 - lat1) * .pi / 180
        let dLambda = (lon2 - lon1) * .pi / 180

        let a = sin(dPhi / 2) * sin(dPhi / 2)
            + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
        return 2 * earthRadiusKm * asin(min(1, sqrt(a)))
    }

    /// Начальный азимут из первой точки во вторую, в градусах от севера по часовой стрелке.
    public static func bearingDeg(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let dLambda = (lon2 - lon1) * .pi / 180

        let y = sin(dLambda) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLambda)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Румб: «ССВ» по-русски, «NNE» по-английски.
    public static func compass(_ deg: Double, russian: Bool) -> String {
        let russianPoints = ["С", "ССВ", "СВ", "ВСВ", "В", "ВЮВ", "ЮВ", "ЮЮВ",
                             "Ю", "ЮЮЗ", "ЮЗ", "ЗЮЗ", "З", "ЗСЗ", "СЗ", "ССЗ"]
        let englishPoints = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                             "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let points = russian ? russianPoints : englishPoints
        let normalized = (deg.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let index = Int((normalized / 22.5).rounded()) % 16
        return points[index]
    }

    /// Прямоугольник вокруг точки, покрывающий окружность заданного радиуса.
    /// Нужен для источников, которые принимают только bbox (например OpenSky).
    public static func boundingBox(lat: Double, lon: Double, radiusKm: Double)
        -> (lamin: Double, lomin: Double, lamax: Double, lomax: Double) {
        let dLat = radiusKm / 111.32
        let cosLat = max(cos(lat * .pi / 180), 0.01)
        let dLon = radiusKm / (111.32 * cosLat)
        return (lat - dLat, lon - dLon, lat + dLat, lon + dLon)
    }
}

/// Единицы измерения, разделители и формулировки, зависящие от языка интерфейса.
public struct DisplayFormat: Sendable, Equatable {
    public let language: String

    public init(language: String) {
        self.language = language.lowercased().hasPrefix("ru") ? "ru" : "en"
    }

    public var isRussian: Bool { language == "ru" }

    /// Неразрывный пробел. Число и единица измерения не должны разрываться между строками:
    /// «305 км/ч» целиком переезжает на следующую строку, а не делится пополам.
    private static let noBreak = "\u{00A0}"

    public var kmUnit: String { isRussian ? "км" : "km" }
    public var meterUnit: String { isRussian ? "м" : "m" }
    public var kmhUnit: String { isRussian ? "км/ч" : "km/h" }

    private func number(_ value: Double, fractionDigits: Int, grouping: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = fractionDigits
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = grouping
        // Разряды тоже разделяем неразрывным пробелом: «9 449 м» не должно разрываться.
        formatter.groupingSeparator = isRussian ? Self.noBreak : ","
        formatter.decimalSeparator = isRussian ? "," : "."
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// Километры: «6,4 км» или «6.4 km».
    public func km(_ value: Double) -> String {
        number(value, fractionDigits: value < 10 ? 1 : 0) + Self.noBreak + kmUnit
    }

    /// Метры с разделителем разрядов: «10 675 м» или «10,675 m».
    public func meters(_ value: Double) -> String {
        number(value.rounded(), fractionDigits: 0, grouping: true) + Self.noBreak + meterUnit
    }

    /// Скорость: «780 км/ч» или «485 km/h».
    public func kmh(_ value: Double) -> String {
        number(value.rounded(), fractionDigits: 0) + Self.noBreak + kmhUnit
    }

    /// Вертикальная скорость: «набор 4,2 м/с» или «climb 4.2 m/s».
    public func verticalSpeed(_ feetPerMinute: Double) -> String {
        let metersPerSecond = abs(feetPerMinute) * 0.00508
        let value = number(metersPerSecond, fractionDigits: 1)
        if isRussian {
            return (feetPerMinute > 0 ? "набор " : "снижение ") + value + Self.noBreak + "м/с"
        }
        return (feetPerMinute > 0 ? "climb " : "descent ") + value + Self.noBreak + "m/s"
    }

    /// Азимут: «ССЗ 344°» или «NNW 344°».
    public func bearing(_ degrees: Double) -> String {
        Geo.compass(degrees, russian: isRussian) + Self.noBreak + "\(Int(degrees.rounded()))°"
    }

    /// Длительность: «1 ч 05 мин» / «1 h 05 min», «45 мин» / «45 min».
    public func duration(hours: Double) -> String {
        let totalMinutes = max(0, Int((hours * 60).rounded()))
        let hoursPart = totalMinutes / 60
        let minutesPart = totalMinutes % 60
        if isRussian {
            return hoursPart == 0
                ? "\(minutesPart) мин"
                : String(format: "%d ч %02d мин", hoursPart, minutesPart)
        }
        return hoursPart == 0
            ? "\(minutesPart) min"
            : String(format: "%d h %02d min", hoursPart, minutesPart)
    }
}
