import SwiftUI
import AppKit
import HumUpThereCore

/// Идентификаторы окон приложения.
enum AppWindow {
    static let settings = "settings"
    static let history = "history"
}

@main
struct HumUpThereApp: App {
    @StateObject private var config: AppConfig
    @StateObject private var history: HistoryStore
    @StateObject private var familiar: FamiliarStore
    @StateObject private var viewModel: RadarViewModel

    init() {
        let config = AppConfig()
        let history = HistoryStore()
        let familiar = FamiliarStore()
        _config = StateObject(wrappedValue: config)
        _history = StateObject(wrappedValue: history)
        _familiar = StateObject(wrappedValue: familiar)
        _viewModel = StateObject(wrappedValue: RadarViewModel(
            config: config,
            history: history,
            familiar: familiar
        ))

        // Делегат уведомлений нужен до первого показа, иначе баннер не отобразится.
        NotificationCenterManager.shared.prepare()

        // Диагностика без интерфейса: проверяем, что именно попадёт в строку меню.
        if CommandLine.arguments.contains("--diagnose") {
            Task { @MainActor in
                await HumUpThereApp.runDiagnose(config: config)
            }
        }

        // Проверка оповещения: узкий радиус считаем прошлым снимком, рабочий — новым.
        if CommandLine.arguments.contains("--test-alert") {
            Task { @MainActor in
                await HumUpThereApp.runAlertTest(config: config)
            }
        }

        // Рендер карточки оповещения в PNG.
        if let index = CommandLine.arguments.firstIndex(of: "--render-alert"),
           index + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[index + 1]
            Task { @MainActor in
                await HumUpThereApp.renderAlert(config: config, path: path)
            }
        }

        // Рендер вариантов строки списка в PNG.
        if let index = CommandLine.arguments.firstIndex(of: "--render-rows"),
           index + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[index + 1]
            Task { @MainActor in
                await HumUpThereApp.renderRows(config: config, path: path)
            }
        }

        // Управление автозапуском из терминала: --login-item on|off
        if let index = CommandLine.arguments.firstIndex(of: "--login-item"),           index + 1 < CommandLine.arguments.count {
            let value = CommandLine.arguments[index + 1].lowercased()
            let enable = ["on", "true", "1", "yes"].contains(value)
            print(enable ? "Включаю автозапуск…" : "Выключаю автозапуск…")
            do {
                try LaunchAtLogin.set(enable)
                print("Автозапуск: \(LaunchAtLogin.statusDescription)")
            } catch {
                print("Не удалось изменить автозапуск: \(error.localizedDescription)")
                exit(1)
            }
            exit(0)
        }

        // Проверка логики «новых бортов» на синтетических снимках.
        if CommandLine.arguments.contains("--test-detection") {
            HumUpThereApp.runDetectionTest()
        }

        // Проверка сохранённых ключей OpenSky.
        if CommandLine.arguments.contains("--test-opensky") {
            Task {
                await HumUpThereApp.runOpenSkyTest(config: config)
            }
        }

        // Проверка реестра знакомых бортов.
        if CommandLine.arguments.contains("--test-familiar") {
            Task { @MainActor in
                HumUpThereApp.runFamiliarTest()
            }
        }

        // Отрисовка поповера целиком: проверяем вёрстку на живых данных.
        if let index = CommandLine.arguments.firstIndex(of: "--render-popover"),
           index + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[index + 1]
            Task { @MainActor in
                await HumUpThereApp.renderPopover(
                    config: config, history: history, familiar: familiar, path: path
                )
            }
        }

        // Образцы строк списка с маркерами — чтобы проверять вид, не трогая настройки.
        if let index = CommandLine.arguments.firstIndex(of: "--render-row-samples"),
           index + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[index + 1]
            Task { @MainActor in
                HumUpThereApp.renderRowSamples(config: config, path: path)
            }
        }

        // Скриншоты для сайта: поповер, карточка оповещения и строки списка.
        if let index = CommandLine.arguments.firstIndex(of: "--render-marketing"),
           index + 1 < CommandLine.arguments.count {
            let directory = CommandLine.arguments[index + 1]
            Task { @MainActor in
                HumUpThereApp.renderMarketing(directory: directory)
            }
        }
    }

    /// Координаты для диагностики: `--at <широта> <долгота>`. Настройки не трогаем —
    /// иначе проверка на чужой точке затрёт координаты пользователя.
    private static func diagnosticLocation(_ arguments: [String]) -> (lat: Double, lon: Double)? {
        guard let index = arguments.firstIndex(of: "--at"),
              index + 2 < arguments.count,
              let lat = Double(arguments[index + 1]),
              let lon = Double(arguments[index + 2]) else {
            return nil
        }
        return (lat, lon)
    }

    /// Рисует поповер целиком с живыми данными: так проверяется вёрстка без скриншотов экрана.
    @MainActor
    private static func renderPopover(
        config: AppConfig,
        history: HistoryStore,
        familiar: FamiliarStore,
        path: String
    ) async {
        let model = RadarViewModel(config: config, history: history, familiar: familiar)
        await model.refresh()
        let view = RadarView(viewModel: model, familiar: familiar)
            .environmentObject(config)
        print(writePNG(view, to: path) ? "поповер отрисован: \(path)" : "не удалось отрисовать поповер")
        exit(0)
    }

    /// Рисует три образца строки: обычную, видимую глазами и знакомый борт.
    @MainActor
    private static func renderRowSamples(config: AppConfig, path: String) {
        func sample(
            _ hex: String,
            _ callsign: String,
            _ type: String,
            _ registration: String,
            altitudeMeters: Double,
            distanceKm: Double
        ) -> Aircraft {
            Aircraft(
                id: hex,
                callsign: callsign,
                registration: registration,
                typeCode: type,
                altitudeFt: altitudeMeters / 0.3048,
                groundSpeedKt: 450,
                trackDeg: 90,
                verticalRateFpm: 0,
                squawk: nil,
                onGround: false,
                lat: 59.63,
                lon: 56.76,
                distanceKm: distanceKm,
                bearingDeg: 90
            )
        }

        let plain = sample("aaa111", "AFL111", "B738", "RA-73001", altitudeMeters: 10_600, distanceKm: 24)
        let visible = sample("bbb222", "SBI222", "A320", "RA-73002", altitudeMeters: 2_400, distanceKm: 8)
        let repeatVisitor = sample("ccc333", "NWS333", "A321", "RA-73003", altitudeMeters: 9_800, distanceKm: 15)

        let familiar = FamiliarAircraft(
            hex: "ccc333",
            registration: "RA-73003",
            typeCode: "A321",
            lastCallsign: "NWS333",
            lastAirline: "Nordwind",
            firstSeen: Date().addingTimeInterval(-60 * 24 * 3600),
            lastSeen: Date(),
            sightings: 4
        )

        func caption(_ value: String) -> some View {
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)
        }

        let view = VStack(alignment: .leading, spacing: 0) {
            caption("обычный борт")
            AircraftRow(
                aircraft: plain,
                text: config.text,
                format: config.format,
                countryStyle: config.countryStyleValue,
                rotateByCourse: config.rotateIconByCourse
            )
            Divider().padding(.leading, 50)

            caption("видно глазами — маркер глаза")
            AircraftRow(
                aircraft: visible,
                text: config.text,
                format: config.format,
                countryStyle: config.countryStyleValue,
                rotateByCourse: config.rotateIconByCourse,
                visibility: .clear
            )
            Divider().padding(.leading, 50)

            caption("знакомый борт — счётчик встреч")
            AircraftRow(
                aircraft: repeatVisitor,
                text: config.text,
                format: config.format,
                countryStyle: config.countryStyleValue,
                rotateByCourse: config.rotateIconByCourse,
                visibility: .overcast,
                familiar: familiar
            )
            Divider()
        }
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))

        print(writePNG(view, to: path) ? "образцы строк отрисованы: \(path)" : "не удалось отрисовать образцы")
        exit(0)
    }

    // MARK: - Скриншоты для сайта

    /// Отдельный домен настроек: снимки для сайта не должны менять настройки приложения.
    private static let previewDefaultsSuite = "io.humupthere.marketing-preview"

    /// Рисует набор снимков для лендинга — на русском и английском.
    ///
    /// Борта вымышленные, но проходят через те же представления, что и в приложении,
    /// поэтому на сайте оказывается ровно то, что человек увидит после установки.
    @MainActor
    private static func renderMarketing(directory: String) {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        } catch {
            print("не удалось создать папку: \(error.localizedDescription)")
            exit(1)
        }

        // Одно и то же время на всех снимках: часы в шапке не должны «прыгать».
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 25
        components.hour = 21
        components.minute = 42
        components.second = 7
        let moment = Calendar(identifier: .gregorian).date(from: components) ?? Date()

        for language in ["ru", "en"] {
            let config = previewConfig(language: language)
            let familiar = previewFamiliarStore(at: moment)
            let aircraft = previewAircraft(language: language)
            let weather = WeatherSnapshot(
                fetchedAt: moment,
                temperatureC: 10,
                dewpointC: -14,
                cloudCover: 80,
                cloudCoverLow: 80,
                cloudCoverMid: 45,
                cloudCoverHigh: 10,
                visibilityMeters: 15_000,
                windSpeedKmh: 12,
                windDirectionDeg: 240,
                isDay: true,
                weatherCode: 3
            )

            let history = HistoryStore(
                fileURL: fileManager.temporaryDirectory
                    .appendingPathComponent("humupthere-marketing-history-\(language).json")
            )
            let model = RadarViewModel(
                config: config,
                history: history,
                familiar: familiar,
                startsLoop: false
            )
            model.loadPreview(aircraft, weather: weather, at: moment, source: "adsb.lol")

            let suffix = language == "ru" ? "ru" : "en"

            let popover = RadarView(viewModel: model, familiar: familiar, previewMode: true)
                .environmentObject(config)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            print(writePNG(popover, to: "\(directory)/popover-\(suffix).png")
                ? "поповер (\(language)) отрисован"
                : "не удалось отрисовать поповер (\(language))")

            let alert = AircraftAlertView(
                aircraft: Array(aircraft.prefix(2)),
                text: config.text,
                format: config.format,
                countryStyle: config.countryStyleValue
            )
            .padding(24)
            .background(
                LinearGradient(
                    colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            print(writePNG(alert, to: "\(directory)/alert-\(suffix).png")
                ? "карточка (\(language)) отрисована"
                : "не удалось отрисовать карточку (\(language))")

            // Вариант без подложки: на сайте карточку можно положить на тёмный фон.
            let alertCard = AircraftAlertView(
                aircraft: Array(aircraft.prefix(2)),
                text: config.text,
                format: config.format,
                countryStyle: config.countryStyleValue
            )
            .padding(24)
            print(writePNG(alertCard, to: "\(directory)/alert-clear-\(suffix).png")
                ? "карточка без фона (\(language)) отрисована"
                : "не удалось отрисовать карточку без фона (\(language))")

            let rows = VStack(spacing: 0) {
                ForEach(Array(aircraft.prefix(3))) { item in
                    AircraftRow(
                        aircraft: item,
                        text: config.text,
                        format: config.format,
                        countryStyle: config.countryStyleValue,
                        rotateByCourse: config.rotateIconByCourse,
                        visibility: weather.verdict(forAltitudeMeters: item.altitudeMeters),
                        familiar: config.familiarEnabled ? familiar.info(for: item.id) : nil
                    )
                    Divider().padding(.leading, 50)
                }
            }
            .frame(width: 420)
            .background(Color(nsColor: .windowBackgroundColor))
            print(writePNG(rows, to: "\(directory)/rows-\(suffix).png")
                ? "строки (\(language)) отрисованы"
                : "не удалось отрисовать строки (\(language))")
        }

        UserDefaults.standard.removePersistentDomain(forName: previewDefaultsSuite)
        print("скриншоты для сайта готовы: \(directory)")
        exit(0)
    }

    /// Конфигурация для снимков: Москва, 50 км, включённые погода и знакомые борта.
    /// Отдельный домен UserDefaults не пересекается с настройками пользователя.
    private static func previewConfig(language: String) -> AppConfig {
        let defaults = UserDefaults(suiteName: previewDefaultsSuite) ?? .standard
        defaults.set(55.7558, forKey: "latitude")
        defaults.set(37.6173, forKey: "longitude")
        defaults.set(true, forKey: "locationConfigured")
        defaults.set(language == "en" ? "Moscow" : "Москва", forKey: "placeName")
        defaults.set(50, forKey: "radiusKm")
        defaults.set(120, forKey: "refreshSeconds")
        defaults.set(language, forKey: "language")
        defaults.set(true, forKey: "weatherEnabled")
        defaults.set(true, forKey: "familiarEnabled")
        defaults.set("name", forKey: "countryStyle")
        defaults.set(true, forKey: "rotateIconByCourse")
        defaults.set("nearest", forKey: "menuBarMode")
        defaults.set(0, forKey: "maxAltitudeMeters")
        defaults.set(false, forKey: "includeGround")
        defaults.set(false, forKey: "notifyOnNewAircraft")
        defaults.set("airport", forKey: "alertSound")
        return AppConfig(defaults: defaults)
    }

    /// Знакомый борт для снимка: четыре встречи за последние две недели.
    @MainActor
    private static func previewFamiliarStore(at moment: Date) -> FamiliarStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("humupthere-marketing-familiar.json")
        try? FileManager.default.removeItem(at: url)
        let store = FamiliarStore(fileURL: url)
        let sample = previewAircraft(language: "ru").first { $0.callsign == "NWS333" }
        if let sample {
            for offset in [14.0, 9, 4, 0.5] {
                store.record([sample], at: moment.addingTimeInterval(-offset * 24 * 3600))
            }
        }
        return store
    }

    /// Правдоподобный вечер над Москвой: посадка, два крейсера и рейс во Франкфурт.
    private static func previewAircraft(language: String) -> [Aircraft] {
        func airport(
            _ iata: String,
            _ city: String,
            _ country: String,
            _ iso: String,
            _ lat: Double,
            _ lon: Double
        ) -> Airport {
            Airport(
                iata: iata,
                icao: nil,
                name: nil,
                municipality: city,
                country: country,
                countryISO: iso,
                latitude: lat,
                longitude: lon
            )
        }

        let moscow = airport("SVO", "Moscow", "Russia", "RU", 55.9726, 37.4146)
        let domodedovo = airport("DME", "Moscow", "Russia", "RU", 55.4088, 37.9063)
        let petersburg = airport("LED", "Saint Petersburg", "Russia", "RU", 59.8003, 30.2625)
        let sochi = airport("AER", "Sochi", "Russia", "RU", 43.4499, 39.9566)
        let frankfurt = airport("FRA", "Frankfurt", "Germany", "DE", 50.0379, 8.5622)

        func route(
            _ callsign: String,
            _ airline: String,
            _ icao: String,
            _ iata: String,
            _ countryISO: String,
            _ country: String,
            from origin: Airport,
            to destination: Airport
        ) -> FlightRoute {
            FlightRoute(
                callsign: callsign,
                callsignIATA: nil,
                airline: airline,
                airlineICAO: icao,
                airlineIATA: iata,
                airlineCountryISO: countryISO,
                airlineCountry: country,
                origin: origin,
                destination: destination,
                fetchedAt: Date()
            )
        }

        func aircraft(
            _ hex: String,
            _ callsign: String,
            _ registration: String,
            _ type: String,
            _ route: FlightRoute,
            altitudeMeters: Double,
            speedKmh: Double,
            track: Double,
            verticalRate: Double,
            distanceKm: Double,
            bearing: Double
        ) -> Aircraft {
            Aircraft(
                id: hex,
                callsign: callsign,
                registration: registration,
                typeCode: type,
                route: route,
                altitudeFt: altitudeMeters / 0.3048,
                groundSpeedKt: speedKmh / 1.852,
                trackDeg: track,
                verticalRateFpm: verticalRate,
                squawk: nil,
                onGround: false,
                lat: 55.72,
                lon: 37.66,
                distanceKm: distanceKm,
                bearingDeg: bearing
            )
        }

        return [
            aircraft(
                "afl111",
                "AFL111",
                "RA-73701",
                "A320",
                route("AFL111", "Aeroflot", "AFL", "SU", "RU", "Russia",
                      from: petersburg, to: moscow),
                altitudeMeters: 1_200,
                speedKmh: 380,
                track: 240,
                verticalRate: -780,
                distanceKm: 4.2,
                bearing: 232
            ),
            aircraft(
                "sbi222",
                "SBI222",
                "RA-73702",
                "A321",
                route("SBI222", "S7 Airlines", "SBI", "S7", "RU", "Russia",
                      from: domodedovo, to: sochi),
                altitudeMeters: 10_600,
                speedKmh: 830,
                track: 164,
                verticalRate: 0,
                distanceKm: 8.6,
                bearing: 151
            ),
            aircraft(
                "nws333",
                "NWS333",
                "RA-73703",
                "A321",
                route("NWS333", "Nordwind", "NWS", "N4", "RU", "Russia",
                      from: petersburg, to: sochi),
                altitudeMeters: 9_800,
                speedKmh: 850,
                track: 172,
                verticalRate: 320,
                distanceKm: 14,
                bearing: 188
            ),
            aircraft(
                "dlh1455",
                "DLH1455",
                "D-AIWA",
                "A320",
                route("DLH1455", "Lufthansa", "DLH", "LH", "DE", "Germany",
                      from: domodedovo, to: frankfurt),
                altitudeMeters: 11_000,
                speedKmh: 870,
                track: 268,
                verticalRate: 0,
                distanceKm: 21,
                bearing: 264
            ),
        ]
    }

    var body: some Scene {
        MenuBarExtra {
            RadarView(viewModel: viewModel, familiar: familiar)
                .environmentObject(config)
        } label: {
            MenuBarLabel(viewModel: viewModel, config: config)
        }
        .menuBarExtraStyle(.window)

        // Обычное окно вместо сцены Settings: сцена Settings закрывалась, стоило
        // приложению потерять фокус — например, при переходе в браузер за координатами.
        Window("Hum Up There", id: AppWindow.settings) {
            SettingsView(viewModel: viewModel, familiar: familiar)
                .environmentObject(config)
        }
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentSize)

        Window("Hum Up There", id: AppWindow.history) {
            HistoryView(history: history, familiar: familiar)
                .environmentObject(config)
        }
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentSize)
    }

    /// Проверяет сохранённые ключи OpenSky: обмен на токен, запрос бортов, остаток кредитов.
    private static func runOpenSkyTest(config: AppConfig) async {
        let fileURL = OpenSkyCredentialsStore.defaultFileURL()
        print("Проверка ключей OpenSky")
        print("файл: \(fileURL?.path ?? "—")")

        guard let credentials = OpenSkyCredentialsStore.load() else {
            print("ключей нет — приложение будет спрашивать анонимно (400 кредитов в сутки)")
            exit(0)
        }

        print("clientId: \(credentials.maskedClientId)")
        let auth = OpenSkyAuth(credentials: credentials)

        do {
            let token = try await auth.accessToken(forceRefresh: true)
            print("токен получен: \(token == nil ? "нет" : "да")")
        } catch {
            print("ошибка авторизации: \(error.localizedDescription)")
            exit(1)
        }

        let client = ADSBClient(auth: auth)
        do {
            let result = try await client.fetch(
                lat: config.latitude,
                lon: config.longitude,
                radiusKm: Double(config.radiusKm),
                includeGround: config.includeGround
            )
            print("источник: \(result.source.rawValue) · бортов: \(result.aircraft.count)")
            if let credits = result.creditsRemaining {
                print("осталось кредитов: \(credits)")
            }
            if let blocked = await auth.blockedFor {
                print("пауза после 429: \(Int(blocked)) с")
            }
        } catch {
            print("ошибка запроса: \(error.localizedDescription)")
            exit(1)
        }
        exit(0)
    }

    /// Прогоняет реестр знакомых бортов по синтетическим визитам.
    ///
    /// Проверяет главное: один и тот же борт, летающий над вами постоянно, не превращается
    /// в десяток «знакомств», а новый визит после долгого перерыва — считается.
    @MainActor
    private static func runFamiliarTest() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("humupthere-familiar-test.json")
        try? FileManager.default.removeItem(at: fileURL)

        let store = FamiliarStore(fileURL: fileURL)
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        func sample(_ hex: String, _ callsign: String) -> Aircraft {
            Aircraft(
                id: hex,
                callsign: callsign,
                registration: "RA-00001",
                typeCode: "B738",
                altitudeFt: 30_000,
                groundSpeedKt: 450,
                trackDeg: 90,
                verticalRateFpm: 0,
                squawk: nil,
                onGround: false,
                lat: 59.63,
                lon: 56.76,
                distanceKm: 20,
                bearingDeg: 90
            )
        }

        let first = sample("abc123", "AFL111")
        let second = sample("def456", "SBI222")

        /// Минута от начала и что в этот момент в небе.
        let steps: [(minute: Double, aircraft: [Aircraft], note: String)] = [
            (0, [first], "борт появился — первое знакомство"),
            (0.25, [first], "через 15 секунд — всё ещё тот же визит"),
            (5, [first], "через 5 минут — тот же визит"),
            (40, [first], "через 40 минут — новый визит"),
            (120, [first, second], "через 2 часа: первый в третий раз, второй впервые"),
        ]

        print("Проверка реестра знакомых бортов")
        print("Новым визитом считается возвращение позже чем через 30 минут.\n")

        for step in steps {
            store.record(step.aircraft, at: start.addingTimeInterval(step.minute * 60))
            let summary = step.aircraft
                .map { "\($0.displayName)=\(store.info(for: $0.id)?.sightings ?? 0)" }
                .joined(separator: ", ")
            print(String(format: "%6.2f мин  %-24@  %@",
                         step.minute,
                         summary as NSString,
                         step.note))
        }

        print("\nИтог по реестру:")
        for hex in ["abc123", "def456"] {
            guard let entry = store.info(for: hex) else { continue }
            let formatter = DateFormatter()
            formatter.dateFormat = "dd.MM.yyyy HH:mm"
            print("  \(entry.lastCallsign ?? hex): встреч \(entry.sightings),"
                + " впервые \(formatter.string(from: entry.firstSeen)),"
                + " последний раз \(formatter.string(from: entry.lastSeen))")
        }

        // Проверяем, что реестр переживает перезапуск: читаем тот же файл заново.
        let reloaded = FamiliarStore(fileURL: fileURL)
        print("\nПосле перезапуска: записей \(reloaded.count),"
            + " повторных визитов \(reloaded.repeatVisitors),"
            + " встреч у первого борта \(reloaded.info(for: "abc123")?.sightings ?? 0)")
        try? FileManager.default.removeItem(at: fileURL)
        exit(0)
    }

    /// Прогоняет трекер посещений по синтетическим снимкам и печатает решения.
    ///
    /// Отвечает на вопрос «не придёт ли уведомление повторно про тот же борт»:
    /// видно, что короткое пропадание ничего не меняет, а долгое отсутствие — меняет.
    private static func runDetectionTest() {
        var tracker = AircraftVisitTracker()
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        func sample(_ hex: String, _ callsign: String) -> Aircraft {
            Aircraft(
                id: hex,
                callsign: callsign,
                registration: nil,
                typeCode: nil,
                altitudeFt: 30_000,
                groundSpeedKt: 450,
                trackDeg: 90,
                verticalRateFpm: 0,
                squawk: nil,
                onGround: false,
                lat: 55.75,
                lon: 37.61,
                distanceKm: 20,
                bearingDeg: 90
            )
        }

        let afl = sample("abc123", "AFL111")
        let sbi = sample("def456", "SBI222")

        struct Step {
            let minute: Double
            let aircraft: [Aircraft]
            let note: String
        }

        let steps: [Step] = [
            Step(minute: 0, aircraft: [afl], note: "борт появился"),
            Step(minute: 0.25, aircraft: [afl], note: "через 15 секунд, всё ещё в радиусе"),
            Step(minute: 0.5, aircraft: [], note: "пропал на один опрос (идёт по краю радиуса)"),
            Step(minute: 0.75, aircraft: [afl], note: "вернулся через 15 секунд"),
            Step(minute: 1, aircraft: [afl, sbi], note: "появился второй борт"),
            Step(minute: 2, aircraft: [sbi], note: "первый ушёл"),
            Step(minute: 20, aircraft: [sbi, afl], note: "первый вернулся через 20 минут"),
            Step(minute: 90, aircraft: [sbi, afl], note: "и ещё раз через полтора часа"),
        ]

        func pad(_ value: String, _ width: Int) -> String {
            value.count >= width
                ? String(value.prefix(width))
                : value + String(repeating: " ", count: width - value.count)
        }

        print("Проверка оповещений о новых бортах")
        print("Борт считается новым, если его не было в радиусе дольше 30 минут.\n")
        print("время    в радиусе            новых   уведомление")
        print(String(repeating: "─", count: 68))

        var didPrimeSnapshot = false

        for step in steps {
            let moment = start.addingTimeInterval(step.minute * 60)
            let fresh = tracker.newAircraft(in: step.aircraft, at: moment)

            // Ровно та же логика, что в RadarViewModel: первый снимок только запоминаем.
            let reason = didPrimeSnapshot
                ? (fresh.isEmpty ? "нет" : "да: " + fresh.map(\.displayName).joined(separator: ", "))
                : "нет (первый снимок)"
            didPrimeSnapshot = true

            let names = step.aircraft.map(\.displayName).joined(separator: ", ")
            print("\(pad("\(Int(step.minute)) мин", 8)) \(pad(names.isEmpty ? "—" : names, 20)) "
                + "\(pad("\(fresh.count)", 7)) \(reason)")
            print("         └ \(step.note)")
        }

        print("""

        Короткое пропадание (15 секунд, один опрос) повторного уведомления не даёт: \
        борт остаётся в памяти 30 минут с момента, когда его видели последний раз. \
        А после долгого отсутствия он снова считается новым — как и должно быть.
        """)
        exit(0)
    }

    @MainActor
    private static func runDiagnose(config: AppConfig) async {
        let format = DisplayFormat(language: "ru")
        print("Hum Up There — диагностика")
        print("Язык: \(config.resolvedLang.rawValue) · координаты: \(config.coordinateText)")
        print("Радиус: \(config.radiusKm) км · интервал \(config.refreshSeconds) с"
            + " · строка меню: \(config.menuBarModeValue.label(config.text))")
        print("Фильтр по высоте: \(config.altitudeFilterValue.label(config.text))")
        print("Автозапуск: \(LaunchAtLogin.statusDescription)")

        let notifications = NotificationCenterManager.shared
        await notifications.refreshStatus()
        print("Уведомления: \(notifications.isAuthorized ? "разрешены" : "не разрешены")"
            + " · сообщать о новых бортах: \(config.notifyOnNewAircraft ? "да" : "нет")")

        // Погода и знакомые борта не зависят от источника бортов, поэтому печатаем их
        // до запроса: даже если источник ограничил частоту, эти строки будут видны.
        if config.weatherEnabled {
            do {
                let weather = try await WeatherService().weather(
                    lat: config.latitude,
                    lon: config.longitude
                )
                let base = weather.estimatedCloudBaseMeters.map { format.meters($0) } ?? "—"
                let visibility = weather.visibilityKm.map { format.km($0) } ?? "—"
                let cover = weather.cloudCover.map { "\($0)%" } ?? "—"
                print("Погода: облачность \(cover) · низ облаков ≈ \(base)"
                    + " · видимость \(visibility)"
                    + " · \(weather.isDay == true ? "день" : "ночь")")
            } catch {
                print("Погода: \(error.localizedDescription)")
            }
        } else {
            print("Погода: выключена в настройках")
        }

        // Знакомые борта: сервисный экземпляр читает тот же файл, что и приложение.
        let familiarStore = FamiliarStore()
        print("Знакомые борта: \(familiarStore.count) записей,"
            + " повторных визитов: \(familiarStore.repeatVisitors)")

        let storedKeys = OpenSkyCredentialsStore.load()
        print("OpenSky: " + (storedKeys == nil
            ? "ключей нет — спрашиваем анонимно (400 кредитов в сутки)"
            : "ключи есть (\(storedKeys?.maskedClientId ?? "—")) — основной источник"))

        // Клиент собираем так же, как приложение: с ключами, если они сохранены.
        let diagnosticAuth = OpenSkyAuth(credentials: storedKeys)
        let client = ADSBClient(auth: diagnosticAuth)
        do {
            let result = try await client.fetch(
                lat: config.latitude,
                lon: config.longitude,
                radiusKm: Double(config.radiusKm),
                includeGround: config.includeGround
            )
            let all = result.aircraft.sorted { $0.distanceKm < $1.distanceKm }
            let sorted: [Aircraft]
            if let limit = config.altitudeLimitMeters {
                sorted = all.filter { ($0.altitudeMeters ?? 0) <= Double(limit) }
            } else {
                sorted = all
            }
            print("Источник: \(result.source.rawValue) · бортов в радиусе: \(all.count)"
                + (sorted.count == all.count ? "" : " · после фильтра по высоте: \(sorted.count)"))

            guard !sorted.isEmpty else {
                print("Строка меню: пусто (в радиусе нет бортов)")
                exit(0)
            }

            let nearest = sorted[0]
            let country = [nearest.route?.airlineCountryCode, nearest.airlineName]
                .compactMap { $0 }
                .joined(separator: " ")
            print("Ближайший: \(nearest.displayName) \(nearest.typeCode ?? "")"
                + (country.isEmpty ? "" : " · \(country)")
                + " — \(nearest.distanceText(format)), \(nearest.altitudeText(format)),"
                + " \(nearest.bearingText(format))")

            // Вердикт «видно ли глазами» для ближайшего борта.
            if config.weatherEnabled {
                do {
                    let weather = try await WeatherService().weather(
                        lat: config.latitude,
                        lon: config.longitude
                    )
                    let verdict = weather.verdict(forAltitudeMeters: nearest.altitudeMeters)
                    print("Видимость ближайшего: \(verdict.title(config.text))")
                } catch {
                    print("Видимость ближайшего: погода недоступна")
                }
            }
            print("Строка меню покажет: «\(nearest.displayName) · \(nearest.distanceText(format))»")

            // Проверяем справочник маршрутов.
            let routeService = RouteService()
            let callsigns = sorted.prefix(8).compactMap { $0.callsign }
            var routes = await routeService.cachedRoutes(for: callsigns)
            let missing = callsigns.filter { routes[$0.uppercased()] == nil }
            routes.merge(await routeService.loadMissing(missing, limit: 8)) { _, new in new }

            print("")
            print("Маршруты (из \(callsigns.count) ближайших найдено \(routes.count)):")
            for aircraft in sorted.prefix(8) {
                let route = aircraft.callsign.flatMap { routes[$0.uppercased()] }
                let line = route.map { $0.title(russian: true) } ?? "маршрут неизвестен"
                print("  \(aircraft.displayName.padding(toLength: 9, withPad: " ", startingAt: 0))"
                    + " \(aircraft.distanceText(format).padding(toLength: 10, withPad: " ", startingAt: 0))"
                    + " \(line)")
                if let hours = aircraft.hoursToDestination {
                    print("            осталось ≈ \(format.duration(hours: hours))")
                }
            }
        } catch {
            print("Ошибка: \(error.localizedDescription)")
        }
        exit(0)
    }
    /// Проверка канала оповещения без ожидания реального борта.
    ///
    /// Узкий радиус (3 км) играет роль прошлого снимка: всё, что появится в рабочем
    /// радиусе, для приложения — новые борта. Дальше идёт обычный путь оповещения.
    @MainActor
    private static func runAlertTest(config: AppConfig) async {
        let client = ADSBClient()
        print("Проверка оповещения: рабочий радиус \(config.radiusKm) км")

        var known: Set<String> = []
        if let narrow = try? await client.fetch(
            lat: config.latitude,
            lon: config.longitude,
            radiusKm: 3,
            includeGround: false
        ) {
            known = Set(narrow.aircraft.map(\.id))
            print("прошлый снимок (3 км): \(known.count) бортов")
        }

        guard let wide = try? await client.fetch(
            lat: config.latitude,
            lon: config.longitude,
            radiusKm: Double(config.radiusKm),
            includeGround: config.includeGround
        ) else {
            print("источник не ответил")
            exit(1)
        }

        let fresh = wide.aircraft.filter { !known.contains($0.id) && !$0.onGround }
        print("бортов в рабочем радиусе: \(wide.aircraft.count), из них новых: \(fresh.count)")
        let sound = config.alertSoundValue
        print("канал: \(NotificationCenterManager.shared.isAuthorized ? "системное уведомление" : "карточка в углу экрана + звук"), звук: \(sound.rawValue)")

        AircraftAlert.deliver(
            aircraft: Array(fresh.prefix(3)),
            text: config.text,
            format: config.format,
            sound: sound,
            countryStyle: config.countryStyleValue
        )
        print("оповещение отправлено, карточка держится 7 секунд")

        try? await Task.sleep(for: .seconds(12))
        exit(0)
    }

    /// Забирает ближайшие борта и подставляет маршруты — общее для рендеров.
    @MainActor
    private static func fetchAircraft(config: AppConfig, limit: Int) async -> [Aircraft] {
        do {
            let result = try await ADSBClient().fetch(
                lat: config.latitude,
                lon: config.longitude,
                radiusKm: Double(config.radiusKm),
                includeGround: false
            )
            let sorted = result.aircraft.sorted { $0.distanceKm < $1.distanceKm }
            let routeService = RouteService()
            let callsigns = sorted.prefix(limit * 2).compactMap { $0.callsign }

            var routes = await routeService.cachedRoutes(for: callsigns)
            let missing = callsigns.filter { routes[$0.uppercased()] == nil }
            if !missing.isEmpty {
                let loaded = await routeService.loadMissing(missing, limit: limit * 2)
                routes.merge(loaded) { _, new in new }
            }

            return sorted.map { item in
                guard let callsign = item.callsign?.uppercased(), let route = routes[callsign] else { return item }
                var copy = item
                copy.route = route
                return copy
            }
        } catch {
            print("источник не ответил: \(error.localizedDescription)")
            return []
        }
    }

    /// Рендер вариантов строки списка — чтобы выбирать внешний вид глазами, а не по описанию.
    @MainActor
    private static func renderRows(config: AppConfig, path: String) async {
        let all = await fetchAircraft(config: config, limit: 12)
        // Для сравнения нужны борта, у которых известна страна авиакомпании.
        let withCountry = all.filter { $0.route?.airlineCountryISO != nil }
        let sample = Array((withCountry.isEmpty ? all : withCountry).prefix(3))

        guard !sample.isEmpty else {
            print("нет бортов для превью")
            exit(1)
        }

        let view = VStack(alignment: .leading, spacing: 0) {
            ForEach(CountryStyle.allCases) { style in
                VStack(alignment: .leading, spacing: 0) {
                    Text(style.label(config.text))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

                    ForEach(sample) { item in
                        AircraftRow(
                            aircraft: item,
                            text: config.text,
                            format: config.format,
                            countryStyle: style,
                            rotateByCourse: config.rotateIconByCourse
                        )
                        if item.id != sample.last?.id {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                Divider()
            }
        }
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))

        print(writePNG(view, to: path) ? "варианты отрисованы: \(path)" : "не удалось отрисовать варианты")
        exit(0)
    }

    /// Рендер карточки оповещения — чтобы проверить её вид без ожидания борта.
    @MainActor
    private static func renderAlert(config: AppConfig, path: String) async {
        let all = await fetchAircraft(config: config, limit: 3)
        let aircraft = all.filter { $0.route != nil }
        let sample = Array((aircraft.isEmpty ? all : aircraft).prefix(2))

        let view = AircraftAlertView(
            aircraft: sample,
            text: config.text,
            format: config.format,
            countryStyle: config.countryStyleValue
        )
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)],
                startPoint: .top,
                endPoint: .bottom
            )
        )

        print(writePNG(view, to: path) ? "карточка отрисована: \(path)" : "не удалось отрисовать карточку")
        exit(0)
    }

    @MainActor
    private static func writePNG<V: View>(_ view: V, to path: String) -> Bool {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return false
        }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}

/// Содержимое иконки в строке меню рядом с часами.
struct MenuBarLabel: View {
    @ObservedObject var viewModel: RadarViewModel
    @ObservedObject var config: AppConfig

    var body: some View {
        let text = viewModel.menuBarText(format: config.format)
        HStack(spacing: 4) {
            Image(systemName: symbolName)
            if !text.isEmpty {
                Text(text)
            }
        }
        // Без явного описания система берёт его из имени SF Symbol «airplane»,
        // и пункт объявляется как «Авиарежим» — и в VoiceOver, и в Accessibility.
        .accessibilityLabel(Text(description(for: text)))
    }

    private var symbolName: String {
        viewModel.aircraft.isEmpty ? "airplane" : "airplane.circle.fill"
    }

    private func description(for text: String) -> String {
        text.isEmpty ? "Hum Up There" : "Hum Up There: \(text)"
    }
}
