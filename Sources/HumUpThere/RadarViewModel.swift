import Foundation
import Combine
import AppKit
import HumUpThereCore

/// Состояние радара: список бортов, маршруты, статус обновления, ошибки.
@MainActor
final class RadarViewModel: ObservableObject {
    @Published private(set) var aircraft: [Aircraft] = []
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var sourceName: String = "—"
    @Published private(set) var errorText: String?
    @Published private(set) var isLoading = false

    private let client: ADSBClient
    private let auth: OpenSkyAuth
    private let routeService = RouteService()
    private let weatherService = WeatherService()
    private let config: AppConfig
    private let history: HistoryStore
    private let familiar: FamiliarStore
    private var loop: Task<Void, Never>?
    private var routeTask: Task<Void, Never>?

    /// Погода в точке наблюдения: нужна, чтобы ответить, видно ли борт глазами.
    @Published private(set) var weather: WeatherSnapshot?
    @Published private(set) var weatherError: String?

    /// Результат проверки ключей: нужно и сообщение, и признак успеха.
    struct OpenSkyCheck {
        let ok: Bool
        let message: String
    }

    /// Состояние личных ключей OpenSky.
    @Published private(set) var openSkyConfigured = false
    @Published private(set) var openSkyClientId: String?
    @Published private(set) var openSkyCredits: Int?

    /// Запоминаем типы бортов: источник отдаёт поле типа не в каждом ответе.
    private var typeCache: [String: String] = [:]
    /// Помним недавно виденные борта: борт, мелькнувший на краю радиуса, не считается
    /// новым при следующем опросе.
    private var visitTracker = AircraftVisitTracker()
    private var didPrimeSnapshot = false
    private var lastLocation: (lat: Double, lon: Double)?

    init(
        config: AppConfig,
        history: HistoryStore,
        familiar: FamiliarStore,
        startsLoop: Bool = true
    ) {
        self.config = config
        self.history = history
        self.familiar = familiar

        let savedCredentials = OpenSkyCredentialsStore.load()
        let auth = OpenSkyAuth(credentials: savedCredentials)
        self.auth = auth
        self.client = ADSBClient(auth: auth)
        self.openSkyConfigured = savedCredentials != nil
        self.openSkyClientId = savedCredentials?.maskedClientId

        if startsLoop {
            startLoop()
        }
    }

    /// Подставляет готовые образцы бортов и погоду.
    ///
    /// Нужно только для отрисовки скриншотов сайта: сеть, историю и настройки
    /// пользователя такой снимок не трогает. В обычной работе не вызывается.
    func loadPreview(
        _ list: [Aircraft],
        weather: WeatherSnapshot?,
        at moment: Date,
        source: String
    ) {
        aircraft = list
        self.weather = weather
        weatherError = nil
        lastUpdate = moment
        sourceName = source
        errorText = nil
        isLoading = false
    }

    // MARK: - Ключи OpenSky

    /// Сохраняет ключи и сразу проверяет их живым запросом, чтобы человек видел результат.
    func saveOpenSkyCredentials(clientId: String, clientSecret: String) async -> OpenSkyCheck {
        let credentials = OpenSkyCredentials(
            clientId: clientId.trimmingCharacters(in: .whitespacesAndNewlines),
            clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard credentials.isValid else {
            return OpenSkyCheck(ok: false, message: config.text(.openSkyIncomplete))
        }
        guard OpenSkyCredentialsStore.save(credentials) else {
            return OpenSkyCheck(ok: false, message: config.text(.openSkySaveFailed))
        }

        await auth.update(credentials: credentials)
        openSkyConfigured = true
        openSkyClientId = credentials.maskedClientId

        do {
            // Обмен ключей на токен кредитов не тратит — это самая дешёвая проверка.
            _ = try await auth.accessToken(forceRefresh: true)
        } catch {
            return OpenSkyCheck(ok: false, message: error.localizedDescription)
        }

        await refresh()
        return OpenSkyCheck(
            ok: true,
            message: config.text(.openSkyStatusOk, openSkyCredits.map(String.init) ?? "—")
        )
    }

    /// Проверяет уже сохранённые ключи.
    func verifyOpenSky() async -> OpenSkyCheck {
        guard openSkyConfigured else {
            return OpenSkyCheck(ok: false, message: config.text(.openSkyIncomplete))
        }
        do {
            _ = try await auth.accessToken(forceRefresh: true)
        } catch {
            return OpenSkyCheck(ok: false, message: error.localizedDescription)
        }
        await refresh()
        return OpenSkyCheck(
            ok: true,
            message: config.text(.openSkyStatusOk, openSkyCredits.map(String.init) ?? "—")
        )
    }

    func removeOpenSkyCredentials() async {
        OpenSkyCredentialsStore.delete()
        await auth.update(credentials: nil)
        openSkyConfigured = false
        openSkyClientId = nil
        openSkyCredits = nil
    }

    /// Страница, где создаётся API-клиент OpenSky.
    func openOpenSkyAccountPage() {
        guard let url = URL(string: "https://opensky-network.org/my-opensky/account") else { return }
        NSWorkspace.shared.open(url)
    }

    deinit {
        loop?.cancel()
        routeTask?.cancel()
    }

    /// Бесконечный цикл обновления: работает, даже когда поповер закрыт,
    /// чтобы строка меню всегда показывала актуальный борт.
    func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let seconds = self?.config.refreshSeconds ?? 120
                try? await Task.sleep(for: .seconds(Double(max(5, seconds))))
            }
        }
    }

    func refresh() async {
        guard config.locationConfigured else {
            aircraft = []
            errorText = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        // Погода не зависит от источника бортов: спрашиваем её в любом случае,
        // иначе при ошибке источника строка о погоде остаётся пустой.
        await refreshWeatherIfNeeded()

        do {
            let result = try await client.fetch(
                lat: config.latitude,
                lon: config.longitude,
                radiusKm: Double(config.radiusKm),
                includeGround: config.includeGround
            )
            var list = result.aircraft.map(enrichWithCachedType)

            // В историю пишем всё, что реально пролетело, независимо от фильтра по высоте:
            // это журнал того, что было над головой, а фильтр — настройка отображения.
            history.record(result.aircraft)

            if config.familiarEnabled {
                familiar.record(result.aircraft)
            }

            list = applyAltitudeFilter(to: list)
            list = await attachCachedRoutes(to: list)
            aircraft = list.sorted { $0.distanceKm < $1.distanceKm }
            sourceName = result.source.rawValue
            lastUpdate = Date()
            errorText = nil

            // Остаток кредитов OpenSky приходит в заголовке ответа.
            if let credits = result.creditsRemaining {
                openSkyCredits = credits
            }

            // При смене точки наблюдения весь список для нас новый: сбрасываем и память
            // о бортах, и предыдущий снимок, иначе придёт пачка уведомлений.
            let location = (config.latitude, config.longitude)
            if let last = lastLocation, last != location {
                didPrimeSnapshot = false
                visitTracker.reset()
            }
            lastLocation = location

            handleNewAircraft(shouldNotify: didPrimeSnapshot)
            didPrimeSnapshot = true

            loadMissingRoutes()
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Погода и видимость

    /// Погода меняется медленно: сервис сам держит снимок 15 минут, так что здесь
    /// на каждом цикле происходит только обращение к кэшу.
    private func refreshWeatherIfNeeded() async {
        guard config.weatherEnabled, config.locationConfigured else {
            weather = nil
            weatherError = nil
            return
        }

        do {
            weather = try await weatherService.weather(lat: config.latitude, lon: config.longitude)
            weatherError = nil
        } catch {
            // Без погоды приложение просто не показывает вердикт — это не ошибка работы.
            weatherError = error.localizedDescription
        }
    }

    /// Увидит ли человек этот борт глазами.
    func visibility(for aircraft: Aircraft) -> VisibilityVerdict {
        guard config.weatherEnabled, let weather else { return .unknown }
        return weather.verdict(forAltitudeMeters: aircraft.altitudeMeters)
    }

    // MARK: - Маршруты

    // MARK: - Фильтр по высоте

    /// Оставляем только борта ниже выбранной высоты — «что реально слышно».
    /// Борта с неизвестной высотой не выбрасываем: лучше показать, чем потерять.
    private func applyAltitudeFilter(to list: [Aircraft]) -> [Aircraft] {
        guard let limit = config.altitudeLimitMeters else { return list }
        return list.filter { item in
            guard let meters = item.altitudeMeters else { return true }
            return meters <= Double(limit)
        }
    }

    // MARK: - Уведомления о новых бортах

    /// Уведомляем только про те борта, которых не было в радиусе последние полчаса.
    /// Это защищает от ложных срабатываний, когда борт идёт по краю радиуса и на одном
    /// опросе пропадает, а на следующем появляется снова. Первый снимок после запуска
    /// только запоминаем — в небе уже кто-то есть, и это не «новый борт».
    private func handleNewAircraft(shouldNotify: Bool) {
        let fresh = visitTracker.newAircraft(in: aircraft)

        guard shouldNotify, config.notifyOnNewAircraft else { return }

        let candidates = fresh.filter { !$0.onGround }
        guard !candidates.isEmpty else { return }

        AircraftAlert.deliver(
            aircraft: Array(candidates.prefix(3)),
            text: config.text,
            format: config.format,
            sound: config.alertSoundValue,
            countryStyle: config.countryStyleValue
        )
    }

    /// Подставляет маршруты из кэша — это мгновенно и не требует сети.
    private func attachCachedRoutes(to list: [Aircraft]) async -> [Aircraft] {
        let callsigns = list.compactMap { $0.callsign }
        guard !callsigns.isEmpty else { return list }

        let routes = await routeService.cachedRoutes(for: callsigns)
        guard !routes.isEmpty else { return list }

        return list.map { item in
            guard
                let callsign = item.callsign?.uppercased(),
                let route = routes[callsign]
            else {
                return item
            }
            var copy = item
            copy.route = route
            return copy
        }
    }

    /// Недостающие маршруты догружаются в фоне: список бортов показывается сразу,
    /// не дожидаясь справочника. Иначе интерфейс ждал бы лишнюю секунду-две.
    private func loadMissingRoutes() {
        guard routeTask == nil else { return }

        let targets = aircraft.prefix(8).compactMap { $0.callsign }
        guard !targets.isEmpty else { return }

        routeTask = Task { [weak self] in
            guard let self else { return }
            let resolved = await self.routeService.loadMissing(targets, limit: 8, concurrency: 3)
            self.applyResolvedRoutes(resolved)
            self.routeTask = nil
        }
    }

    private func applyResolvedRoutes(_ routes: [String: FlightRoute]) {
        guard !routes.isEmpty else { return }
        aircraft = aircraft.map { item in
            guard
                item.route == nil,
                let callsign = item.callsign?.uppercased(),
                let route = routes[callsign]
            else {
                return item
            }
            var copy = item
            copy.route = route
            return copy
        }
        // Маршруты приходят уже после первой записи в историю — дописываем их в тот же визит.
        history.record(aircraft)
    }

    /// Подставляет тип борта из кэша, если источник его не прислал.
    private func enrichWithCachedType(_ aircraft: Aircraft) -> Aircraft {
        if let type = aircraft.typeCode {
            typeCache[aircraft.id] = type
            return aircraft
        }
        guard let cached = typeCache[aircraft.id] else { return aircraft }
        var enriched = aircraft
        enriched.typeCode = cached
        return enriched
    }

    // MARK: - Тексты состояния

    var nearest: Aircraft? { aircraft.first }

    var lastUpdateText: String {
        let text = config.text
        guard let lastUpdate else { return text(.neverUpdated) }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return text(.updatedAt, formatter.string(from: lastUpdate))
    }

    func menuBarText(format: DisplayFormat) -> String {
        switch config.menuBarModeValue {
        case .iconOnly:
            return ""
        case .count:
            return aircraft.isEmpty ? "" : "\(aircraft.count)"
        case .nearest:
            guard let nearest else { return "" }
            return "\(nearest.displayName) · \(nearest.distanceText(format))"
        }
    }
}
