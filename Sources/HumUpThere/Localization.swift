import Foundation
import HumUpThereCore

/// Язык интерфейса. «Системный» разрешается в конкретный язык по настройкам macOS.
enum Lang: String, CaseIterable, Identifiable {
    case system
    case ru
    case en

    var id: String { rawValue }

    static func resolve(stored: String) -> Lang {
        let candidate = Lang(rawValue: stored) ?? .system
        guard candidate == .system else { return candidate }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("ru") ? .ru : .en
    }

    func displayName(_ text: T) -> String {
        switch self {
        case .system: return text(.languageSystem)
        case .ru: return "Русский"
        case .en: return "English"
        }
    }
}

enum TextKey: String {
    // Общее
    case appName
    case radius
    case refresh
    case update
    case settings
    case quit
    case openSettings
    case retry

    // Состояния поповера
    case coordinatesNotSet
    case coordsMissingTitle
    case coordsMissingMessage
    case sourceFailedTitle
    case emptySkyTitle
    case emptySkyMessage
    case updatedAt
    case neverUpdated
    case sourceLabel

    // Строка борта
    case onGround
    case climbClimbing
    case climbDescending
    case climbLevel
    case climbUnknown
    case remaining

    // Настройки
    case coordsSection
    case coordsHint
    case latitude
    case longitude
    case placeName
    case saveAndRefresh
    case detectByIP
    case detecting
    case currentlyTracking
    case coordsError
    case savedRefreshing
    case savedWithCount
    case savedWithError
    case ipDetecting
    case ipFailed
    case ipDone
    case ipVpnWarning
    case networkError
    case showSection
    case updateSection
    case appSection
    case websiteLabel
    case versionTitle
    case aboutDataTitle
    case dataSourcesLine
    case openSkyWhy
    case openSkyDetails
    case radiusHint
    case viewSection
    case pollInterval
    case inMenuBar
    case modeNearest
    case modeCount
    case modeIconOnly
    case showGround
    case interfaceLanguage
    case languageSystem
    case dataSection
    case dataDisclaimer
    case vpnDisclaimer
    case routeDisclaimer
    case seconds
    case minutes

    // Автозапуск и уведомления
    case launchAtLogin
    case launchAtLoginHint
    case launchAtLoginError
    case notificationsSection
    case notifyNewAircraft
    case notifyHint
    case notifyTest
    case notifyGranted
    case notifyViaCard
    case notifyTitle
    case notifyTestBody
    case soundLabel
    case soundAirport
    case soundHum
    case soundHint

    // Фильтр по высоте и авиакомпания
    case altitudeLabel
    case altitudeAny
    case altitudeUpTo
    case altitudeHint
    case airlineLabel

    // Отображение страны авиакомпании
    case countryLabel
    case countryName
    case countryCode
    case countryNone
    case countryHint

    // Поворот иконки борта
    case rotateIconLabel
    case rotateIconHint

    // История пролётов
    case historyButton
    case historyTitle
    case historyRetention
    case historyCount
    case historyClear
    case historyEmptyTitle
    case historyEmptyMessage
    case historyColumnTime
    case historyColumnFlight
    case historyColumnType
    case historyColumnAirline
    case historyColumnRoute
    case historyColumnDistance
    case historyColumnAltitude
    case historyFirstSeen
    case historyLastSeen
    case historyDuration
    case historyColumnSightings

    // Наблюдение: погода и знакомые борта
    case observationSection
    case weatherToggle
    case weatherHint
    case familiarToggle
    case familiarHint
    case familiarForget
    case familiarTooltip
    case familiarCount
    case weatherClouds
    case weatherCloudBase
    case weatherVisibility
    case weatherUnavailable
    case verdictClear
    case verdictGaps
    case verdictBelowClouds
    case verdictOvercast
    case verdictHaze
    case verdictNight
    case verdictUnknown

    // Личные ключи OpenSky
    case openSkySection
    case openSkyRegistration
    case openSkyClientIdLabel
    case openSkyClientSecretLabel
    case openSkySave
    case openSkyRemove
    case openSkyVerify
    case openSkyReplace
    case openSkyCancel
    case openSkyGetKeys
    case openSkyStatusOk
    case openSkyIncomplete
    case openSkySaveFailed
    case openSkyCredits
    case openSkyActive
}

enum LocalizationTable {
    typealias Entry = (ru: String, en: String)

    static let entries: [TextKey: Entry] = [
        .appName: ("Hum Up There", "Hum Up There"),
        .radius: ("Радиус", "Radius"),
        .refresh: ("Обновить", "Refresh"),
        .update: ("Обновить", "Update"),
        .settings: ("Настройки", "Settings"),
        .quit: ("Выход", "Quit"),
        .openSettings: ("Открыть настройки", "Open Settings"),
        .retry: ("Повторить", "Retry"),

        .coordinatesNotSet: ("координаты не заданы", "location not set"),
        .coordsMissingTitle: ("Координаты не заданы", "Location not set"),
        .coordsMissingMessage: (
            "Откройте настройки и укажите широту и долготу места, над которым следить за бортами.",
            "Open Settings and enter the latitude and longitude of the place you want to watch."
        ),
        .sourceFailedTitle: ("Источник не ответил", "Source did not respond"),
        .emptySkyTitle: ("Небо пустое", "Empty sky"),
        .emptySkyMessage: (
            "В радиусе %d км сейчас нет бортов. Обновление каждые %@.",
            "No aircraft within %d km right now. Refreshing every %@."
        ),
        .updatedAt: ("обновлено в %@", "updated at %@"),
        .neverUpdated: ("ещё не обновлялось", "not updated yet"),
        .sourceLabel: ("источник %@", "source %@"),

        .onGround: ("на земле", "on ground"),
        .climbClimbing: ("набор", "climbing"),
        .climbDescending: ("снижение", "descending"),
        .climbLevel: ("эшелон", "level"),
        .climbUnknown: ("нет данных", "no data"),
        .remaining: ("осталось ≈ %@", "≈ %@ left"),

        .coordsSection: ("Место наблюдения", "Observation point"),
        .coordsHint: (
            "Можно ввести вручную или определить по IP. Название места — просто подпись в списке.",
            "Type the coordinates yourself or detect them by IP. The place name is just a label in the list."
        ),
        .updateSection: ("Обновление", "Updates"),
        .appSection: ("Приложение", "Application"),
        .websiteLabel: ("Сайт приложения", "Website"),
        .versionTitle: ("Версия", "Version"),
        .aboutDataTitle: ("Откуда берутся данные и чего ждать", "Where the data comes from and what to expect"),
        .dataSourcesLine: (
            "Борта: adsb.lol и OpenSky Network. Маршруты: adsbdb.",
            "Aircraft: adsb.lol and OpenSky Network. Routes: adsbdb."
        ),
        .openSkyWhy: ("Зачем это нужно", "Why this helps"),
        .openSkyDetails: (
            "OpenSky определяет положение борта по нескольким приёмникам сразу, поэтому видит больше, чем сети, собранные только на ADS-B приёмниках. С личными ключами суточный лимит запросов растёт с 400 до 4000 — при опросе раз в две минуты расходуется около 720. Ключи лежат в файле, который читаете только вы.",
            "OpenSky locates an aircraft using several receivers at once, so it sees more than networks built on ADS-B receivers alone. With personal keys the daily request limit grows from 400 to 4,000 — polling every two minutes uses about 720. The keys are stored in a file only you can read."
        ),
        .latitude: ("Широта", "Latitude"),
        .longitude: ("Долгота", "Longitude"),
        .placeName: ("Название места", "Place name"),
        .saveAndRefresh: ("Сохранить и обновить", "Save and refresh"),
        .detectByIP: ("Определить по IP", "Detect by IP"),
        .detecting: ("Определяю…", "Detecting…"),
        .currentlyTracking: ("Сейчас отслеживается: %@", "Currently tracking: %@"),
        .coordsError: (
            "Проверьте координаты: широта от -90 до 90, долгота от -180 до 180.",
            "Check the coordinates: latitude from -90 to 90, longitude from -180 to 180."
        ),
        .savedRefreshing: ("Сохранено, обновляю данные…", "Saved, refreshing…"),
        .savedWithCount: (
            "Сохранено. В радиусе %d км сейчас %d бортов.",
            "Saved. %d aircraft within %d km right now."
        ),
        .savedWithError: (
            "Сохранено, но источник не ответил: %@",
            "Saved, but the source did not respond: %@"
        ),
        .ipDetecting: ("Определяю координаты по IP…", "Detecting coordinates by IP…"),
        .ipFailed: (
            "Не удалось определить координаты по IP. Введите их вручную.",
            "Could not detect coordinates by IP. Enter them manually."
        ),
        .ipDone: ("Координаты взяты по IP%@", "Coordinates taken from IP%@"),
        .ipVpnWarning: (
            "Если включён VPN, это может быть чужая точка — проверьте перед использованием.",
            "With a VPN this may be the wrong place — check before use."
        ),
        .networkError: ("Ошибка сети: %@", "Network error: %@"),
        .showSection: (
            "Что показывать",
            "What to show"
        ),
        .radiusHint: (
            "Борта внутри радиуса попадают в список, ближайший — в строку меню.",
            "Aircraft inside the radius are listed; the nearest one goes to the menu bar."
        ),
        .viewSection: (
            "Вид списка",
            "List appearance"
        ),
        .pollInterval: ("Интервал опроса", "Poll interval"),
        .inMenuBar: ("В строке меню", "In the menu bar"),
        .modeNearest: ("Ближайший борт и дистанция", "Nearest aircraft and distance"),
        .modeCount: ("Только количество бортов", "Aircraft count only"),
        .modeIconOnly: ("Только иконка", "Icon only"),
        .showGround: ("Показывать борта на земле", "Include aircraft on the ground"),
        .interfaceLanguage: ("Язык интерфейса", "Interface language"),
        .languageSystem: ("Как в системе", "Same as system"),
        .dataSection: (
            "О данных",
            "About the data"
        ),
        .dataDisclaimer: (
            "Данные собирает сообщество наземных ADS-B приёмников. Борт виден только там, где есть приёмник, а координаты могут запаздывать на несколько секунд. Приложение не заменяет диспетчерские службы.",
            "Data comes from the community of ground ADS-B receivers. An aircraft is visible only where a receiver covers it, and positions may lag a few seconds behind. This app is not a substitute for air traffic services."
        ),
        .vpnDisclaimer: (
            "Если включён VPN, определение по IP покажет место выхода VPN, а не ваше реальное. Координаты всегда можно ввести руками — это надёжнее.",
            "With a VPN enabled, IP detection shows the VPN exit location rather than your real one. Entering coordinates manually is always more reliable."
        ),
        .routeDisclaimer: (
            "Маршрут и время до посадки справочные: маршруты берутся из открытого справочника adsbdb по позывному, а время считается по прямой до аэропорта и текущей скорости. У чартеров, грузовых и военных рейсов маршрута может не быть.",
            "Route and time to landing are indicative: routes come from the open adsbdb directory by callsign, and the time is estimated from the straight-line distance to the airport and the current speed. Charter, cargo and military flights may have no route."
        ),
        .seconds: ("%d с", "%d s"),
        .minutes: ("%d мин", "%d min"),

        .launchAtLogin: ("Запускать при входе в систему", "Launch at login"),
        .launchAtLoginHint: (
            "Приложение будет открываться само после входа в macOS и сразу появится в строке меню.",
            "The app starts automatically after you log in to macOS and appears in the menu bar."
        ),
        .launchAtLoginError: ("Не удалось изменить автозапуск: %@", "Could not change the login item: %@"),

        .notificationsSection: ("Уведомления", "Notifications"),
        .notifyNewAircraft: ("Сообщать о новых бортах", "Notify about new aircraft"),
        .notifyHint: (
            "Если уведомления запрещены, покажу карточку в углу экрана — разрешения для неё не нужны. Про один борт — не чаще раза в полчаса.",
            "If notifications are denied I show a card in the corner instead — it needs no permission. At most once every half hour per aircraft."
        ),
        .notifyTest: ("Проверить уведомление", "Test notification"),
        .notifyGranted: ("Системные уведомления разрешены.", "System notifications are allowed."),
        .notifyViaCard: (
            "Уведомления не разрешены — показываю карточку в углу экрана. Разрешить можно в Системных настройках → Уведомления.",
            "Notifications are not allowed — showing a card in the screen corner. You can allow them in System Settings → Notifications."
        ),
        .notifyTitle: ("Над вами борт", "Aircraft overhead"),
        .notifyTestBody: (
            "Так будет выглядеть уведомление о новом борте.",
            "This is how a new-aircraft notification will look."
        ),
        .soundLabel: ("Звук оповещения", "Alert sound"),
        .soundAirport: ("Объявление в аэропорту", "Airport announcement"),
        .soundHum: ("Гул самолёта", "Aircraft hum"),
        .soundHint: (
            "Звук короткий и специально тихий — чтобы обратить внимание, а не заставить вздрогнуть.",
            "The sound is short and deliberately quiet — enough to catch your attention, not to make you jump."
        ),

        .altitudeLabel: ("Высота", "Altitude"),
        .altitudeAny: ("Любая", "Any"),
        .altitudeUpTo: ("до %d км", "up to %d km"),
        .altitudeHint: (
            "Низко летящие обычно и слышно. Ограничение действует и на оповещения, а борта с неизвестной высотой остаются в списке.",
            "Mostly you hear the low-flying ones. The limit applies to alerts too, and aircraft with unknown altitude stay in the list."
        ),
        .airlineLabel: ("Авиакомпания", "Airline"),

        .countryLabel: ("Страна авиакомпании", "Airline country"),
        .countryName: ("Название страны", "Country name"),
        .countryCode: ("Код страны", "Country code"),
        .countryNone: ("Не показывать", "Hide"),
        .countryHint: (
            "Название понятнее, код компактнее. Полное название всегда есть в подсказке.",
            "The name is clearer, the code is more compact. The full name is always in the tooltip."
        ),
        .rotateIconLabel: ("Поворачивать иконку по курсу", "Rotate the icon to the course"),
        .rotateIconHint: (
            "Иконка показывает, куда летит борт. Выключите, чтобы все смотрели одинаково.",
            "The icon shows where the aircraft is heading. Turn it off to keep them all pointing the same way."
        ),

        .historyButton: ("История", "History"),
        .historyTitle: ("История пролётов", "Flight history"),
        .historyRetention: ("хранится %d дня", "kept for %d days"),
        .historyCount: ("записей: %d", "entries: %d"),
        .historyClear: ("Очистить", "Clear"),
        .historyEmptyTitle: ("Пока пусто", "Nothing yet"),
        .historyEmptyMessage: (
            "Здесь появятся борта, которые пролетели над вашей точкой наблюдения. Записи хранятся три дня и потом удаляются сами.",
            "Aircraft that pass over your observation point will appear here. Entries are kept for three days and then removed automatically."
        ),
        .historyColumnTime: ("Время", "Time"),
        .historyColumnFlight: ("Борт", "Flight"),
        .historyColumnType: ("Тип", "Type"),
        .historyColumnAirline: ("Авиакомпания", "Airline"),
        .historyColumnRoute: ("Маршрут", "Route"),
        .historyColumnDistance: ("Ближе всего", "Closest"),
        .historyColumnAltitude: ("Высота", "Altitude"),
        .historyFirstSeen: ("Впервые замечен", "First seen"),
        .historyLastSeen: ("Последний раз", "Last seen"),
        .historyDuration: ("Был в радиусе", "In range for"),
        .historyColumnSightings: ("Встречи", "Sightings"),

        .observationSection: ("Наблюдение", "Observation"),
        .weatherToggle: ("Учитывать погоду", "Use weather"),
        .weatherHint: (
            "Показывать, видно ли борт глазами: по облачности и видимости в вашей точке.",
            "Show whether you can actually see an aircraft: based on cloud cover and visibility at your location."
        ),
        .familiarToggle: ("Помнить знакомые борта", "Remember familiar aircraft"),
        .familiarHint: (
            "Приложение запоминает борт и показывает, сколько раз вы его встречали: «этот над вами уже третий раз».",
            "The app remembers each aircraft and shows how many times you have met it: “this one is above you for the third time”."
        ),
        .familiarForget: ("Забыть все", "Forget all"),
        .familiarTooltip: ("Встреч: %d · впервые %@", "Sightings: %d · first seen %@"),
        .familiarCount: ("знакомых бортов: %d", "familiar aircraft: %d"),
        .weatherClouds: ("облачность %d%%", "cloud cover %d%%"),
        .weatherCloudBase: ("низ облаков ≈ %@", "cloud base ≈ %@"),
        .weatherVisibility: ("видимость %@", "visibility %@"),
        .weatherUnavailable: ("погода недоступна", "weather unavailable"),
        .verdictClear: ("небо почти чистое, видно", "sky almost clear, visible"),
        .verdictGaps: ("облака с просветами, видно если повезёт", "broken clouds, visible if you are lucky"),
        .verdictBelowClouds: ("ниже облаков, видно", "below the clouds, visible"),
        .verdictOvercast: ("за облаками, только слышно", "above the clouds, only audible"),
        .verdictHaze: ("дымка, неба не видно", "haze, you cannot see the sky"),
        .verdictNight: ("ночью только огни и вблизи", "at night only lights, and only nearby"),
        .verdictUnknown: ("нет данных о видимости", "no visibility data"),

        .openSkySection: ("Данные OpenSky", "OpenSky account"),
        .openSkyRegistration: (
            "Не обязательно. Ключи помогают, если над вашим регионом мало данных: зарегистрируйтесь на opensky-network.org и создайте API-клиент в разделе Account.",
            "Optional. Keys help when your area has little coverage: sign up at opensky-network.org and create an API client on the Account page."
        ),
        .openSkyClientIdLabel: ("clientId", "clientId"),
        .openSkyClientSecretLabel: ("clientSecret", "clientSecret"),
        .openSkySave: ("Сохранить и проверить", "Save and verify"),
        .openSkyRemove: ("Удалить ключи", "Remove keys"),
        .openSkyVerify: ("Проверить", "Verify"),
        .openSkyReplace: ("Заменить ключи", "Replace keys"),
        .openSkyCancel: ("Отмена", "Cancel"),
        .openSkyGetKeys: ("Создать ключи", "Create keys"),
        .openSkyStatusOk: ("Ключи приняты. Осталось кредитов: %@.", "Keys accepted. Credits left: %@."),
        .openSkyIncomplete: ("Заполните оба поля.", "Fill in both fields."),
        .openSkySaveFailed: ("Не удалось сохранить ключи.", "Could not save the keys."),
        .openSkyCredits: ("осталось кредитов: %d", "credits left: %d"),
        .openSkyActive: ("Ключи подключены", "Keys are in use"),
    ]
}

/// Доступ к строкам интерфейса на выбранном языке.
struct T {
    let lang: Lang

    var isRussian: Bool { lang == .ru }
    var format: DisplayFormat { DisplayFormat(language: lang.rawValue) }

    func callAsFunction(_ key: TextKey) -> String {
        guard let entry = LocalizationTable.entries[key] else { return key.rawValue }
        return isRussian ? entry.ru : entry.en
    }

    func callAsFunction(_ key: TextKey, _ arguments: CVarArg...) -> String {
        String(format: self(key), arguments: arguments)
    }
}

extension ClimbState {
    func title(_ text: T) -> String {
        switch self {
        case .climbing: return text(.climbClimbing)
        case .descending: return text(.climbDescending)
        case .level: return text(.climbLevel)
        case .unknown: return text(.climbUnknown)
        }
    }
}

extension VisibilityVerdict {
    func title(_ text: T) -> String {
        switch self {
        case .clear: return text(.verdictClear)
        case .gaps: return text(.verdictGaps)
        case .belowClouds: return text(.verdictBelowClouds)
        case .overcast: return text(.verdictOvercast)
        case .haze: return text(.verdictHaze)
        case .night: return text(.verdictNight)
        case .unknown: return text(.verdictUnknown)
        }
    }
}

extension T {
    /// «15 с» или «2 мин» — так интервал читается лучше, чем «120 с».
    func interval(_ seconds: Int) -> String {
        if seconds >= 60, seconds % 60 == 0 {
            return self(.minutes, seconds / 60)
        }
        return self(.seconds, seconds)
    }
}
