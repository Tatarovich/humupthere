import Foundation
import Combine
import HumUpThereCore

/// Радиусы отслеживания, которые видит пользователь в настройках.
enum RadiusOption: Int, CaseIterable, Identifiable {
    case km10 = 10
    case km20 = 20
    case km50 = 50
    case km100 = 100

    var id: Int { rawValue }
    var label: String { "\(rawValue) км" }
}

/// Что показывать в строке меню.
enum MenuBarMode: String, CaseIterable, Identifiable {
    case nearest
    case count
    case iconOnly

    var id: String { rawValue }

    func label(_ text: T) -> String {
        switch self {
        case .nearest: return text(.modeNearest)
        case .count: return text(.modeCount)
        case .iconOnly: return text(.modeIconOnly)
        }
    }
}

/// Как показывать страну авиакомпании в списке бортов.
///
/// Флага-эмодзи здесь нет намеренно: в мелком кегле он превращается в пёстрый
/// прямоугольник, и строка от него рябит.
enum CountryStyle: String, CaseIterable, Identifiable {
    case name
    case code
    case none

    var id: String { rawValue }

    func label(_ text: T) -> String {
        switch self {
        case .name: return text(.countryName)
        case .code: return text(.countryCode)
        case .none: return text(.countryNone)
        }
    }
}

/// Фильтр по высоте: «что реально слышно». Над головой заметны в основном те борта,
/// что летят низко, поэтому список можно ограничить по высоте.
enum AltitudeFilter: Int, CaseIterable, Identifiable {
    case any = 0
    case km1 = 1000
    case km3 = 3000
    case km5 = 5000

    var id: Int { rawValue }

    /// `nil` означает «без ограничения».
    var meters: Int? { self == .any ? nil : rawValue }

    func label(_ text: T) -> String {
        self == .any ? text(.altitudeAny) : text(.altitudeUpTo, rawValue / 1000)
    }
}

/// Настройки приложения с сохранением в UserDefaults.
final class AppConfig: ObservableObject {
    private enum Key {
        static let latitude = "latitude"
        static let longitude = "longitude"
        static let locationConfigured = "locationConfigured"
        static let placeName = "placeName"
        static let radiusKm = "radiusKm"
        static let refreshSeconds = "refreshSeconds"
        static let includeGround = "includeGround"
        static let menuBarMode = "menuBarMode"
        static let language = "language"
        static let notifyOnNewAircraft = "notifyOnNewAircraft"
        static let alertSound = "alertSound"
        static let maxAltitudeMeters = "maxAltitudeMeters"
        static let countryStyle = "countryStyle"
        static let rotateIconByCourse = "rotateIconByCourse"
        static let weatherEnabled = "weatherEnabled"
        static let familiarEnabled = "familiarEnabled"
    }

    /// Опрос раз в две минуты по умолчанию: за это время борт успевает пройти заметную
    /// часть зоны, а расход кредитов OpenSky остаётся скромным (720 в сутки из 4000).
    static let refreshOptions = [15, 30, 60, 120]
    private static let defaultRefreshSeconds = 120

    private let defaults: UserDefaults

    @Published var latitude: Double {
        didSet { defaults.set(latitude, forKey: Key.latitude) }
    }

    @Published var longitude: Double {
        didSet { defaults.set(longitude, forKey: Key.longitude) }
    }

    @Published var locationConfigured: Bool {
        didSet { defaults.set(locationConfigured, forKey: Key.locationConfigured) }
    }

    @Published var placeName: String {
        didSet { defaults.set(placeName, forKey: Key.placeName) }
    }

    @Published var radiusKm: Int {
        didSet { defaults.set(radiusKm, forKey: Key.radiusKm) }
    }

    @Published var refreshSeconds: Int {
        didSet { defaults.set(refreshSeconds, forKey: Key.refreshSeconds) }
    }

    @Published var includeGround: Bool {
        didSet { defaults.set(includeGround, forKey: Key.includeGround) }
    }

    @Published var menuBarMode: String {
        didSet { defaults.set(menuBarMode, forKey: Key.menuBarMode) }
    }

    /// Хранится как «system», «ru» или «en».
    @Published var language: String {
        didSet { defaults.set(language, forKey: Key.language) }
    }

    /// Что показывать в поповере: «list» или «radar».
    @Published var notifyOnNewAircraft: Bool {
        didSet { defaults.set(notifyOnNewAircraft, forKey: Key.notifyOnNewAircraft) }
    }

    /// Звук оповещения: «airport» или «hum».
    @Published var alertSound: String {
        didSet { defaults.set(alertSound, forKey: Key.alertSound) }
    }

    /// Верхняя граница высоты в метрах; 0 — без ограничения.
    @Published var maxAltitudeMeters: Int {
        didSet { defaults.set(maxAltitudeMeters, forKey: Key.maxAltitudeMeters) }
    }

    /// Как показывать страну авиакомпании: «name», «code» или «none».
    @Published var countryStyle: String {
        didSet { defaults.set(countryStyle, forKey: Key.countryStyle) }
    }

    /// Поворачивать иконку борта по курсу. Выключено — все иконки смотрят вверх.
    @Published var rotateIconByCourse: Bool {
        didSet { defaults.set(rotateIconByCourse, forKey: Key.rotateIconByCourse) }
    }

    /// Спрашивать погоду, чтобы понимать, видно ли борт глазами.
    @Published var weatherEnabled: Bool {
        didSet { defaults.set(weatherEnabled, forKey: Key.weatherEnabled) }
    }

    /// Помнить знакомые борта и считать встречи.
    @Published var familiarEnabled: Bool {
        didSet { defaults.set(familiarEnabled, forKey: Key.familiarEnabled) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.latitude = defaults.object(forKey: Key.latitude) as? Double ?? 0
        self.longitude = defaults.object(forKey: Key.longitude) as? Double ?? 0
        self.locationConfigured = defaults.bool(forKey: Key.locationConfigured)
        self.placeName = defaults.string(forKey: Key.placeName) ?? ""
        let storedRadius = defaults.object(forKey: Key.radiusKm) as? Int ?? 50
        self.radiusKm = RadiusOption(rawValue: storedRadius)?.rawValue ?? 50
        let storedRefresh = defaults.object(forKey: Key.refreshSeconds) as? Int ?? Self.defaultRefreshSeconds
        self.refreshSeconds = Self.refreshOptions.contains(storedRefresh)
            ? storedRefresh
            : Self.defaultRefreshSeconds
        self.includeGround = defaults.bool(forKey: Key.includeGround)
        self.menuBarMode = defaults.string(forKey: Key.menuBarMode) ?? MenuBarMode.nearest.rawValue
        self.language = defaults.string(forKey: Key.language) ?? Lang.system.rawValue
        self.notifyOnNewAircraft = defaults.bool(forKey: Key.notifyOnNewAircraft)
        self.alertSound = defaults.string(forKey: Key.alertSound) ?? AlertSound.airport.rawValue
        let storedAltitude = defaults.object(forKey: Key.maxAltitudeMeters) as? Int ?? 0
        self.maxAltitudeMeters = AltitudeFilter(rawValue: storedAltitude)?.rawValue ?? 0
        self.countryStyle = defaults.string(forKey: Key.countryStyle) ?? CountryStyle.name.rawValue
        // По умолчанию иконка показывает курс: ключа может не быть у тех, кто обновился.
        self.rotateIconByCourse = defaults.object(forKey: Key.rotateIconByCourse) as? Bool ?? true
        // Обе новые функции по умолчанию включены: ключей ещё нет у тех, кто обновился.
        self.weatherEnabled = defaults.object(forKey: Key.weatherEnabled) as? Bool ?? true
        self.familiarEnabled = defaults.object(forKey: Key.familiarEnabled) as? Bool ?? true
    }

    // MARK: - Язык и формат

    var resolvedLang: Lang { Lang.resolve(stored: language) }

    var text: T { T(lang: resolvedLang) }

    var format: DisplayFormat { DisplayFormat(language: resolvedLang.rawValue) }

    // MARK: - Вспомогательное

    var menuBarModeValue: MenuBarMode {
        MenuBarMode(rawValue: menuBarMode) ?? .nearest
    }

    var alertSoundValue: AlertSound {
        AlertSound.resolved(alertSound)
    }

    var altitudeFilterValue: AltitudeFilter {
        AltitudeFilter(rawValue: maxAltitudeMeters) ?? .any
    }

    /// Предел высоты в метрах или `nil`, если фильтр выключен.
    var altitudeLimitMeters: Int? {
        altitudeFilterValue.meters
    }

    var countryStyleValue: CountryStyle {
        CountryStyle(rawValue: countryStyle) ?? .name
    }

    var coordinateText: String {
        guard locationConfigured else { return text(.coordinatesNotSet) }
        let coordinates = String(format: "%.4f, %.4f", latitude, longitude)
        return placeName.isEmpty ? coordinates : "\(coordinates) · \(placeName)"
    }

    /// Сохранить координаты, введённые пользователем.
    func saveCoordinates(latitude: Double, longitude: Double, placeName: String = "") {
        self.latitude = latitude
        self.longitude = longitude
        self.placeName = placeName
        self.locationConfigured = true
    }
}
