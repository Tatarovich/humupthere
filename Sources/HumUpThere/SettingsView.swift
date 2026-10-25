import SwiftUI
import AppKit

/// Окно настроек: координаты, радиус, интервал обновления, язык.
struct SettingsView: View {
    @EnvironmentObject private var config: AppConfig
    @ObservedObject var viewModel: RadarViewModel
    @ObservedObject var familiar: FamiliarStore

    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var placeText = ""
    @State private var statusText: String?
    @State private var isDetecting = false
    @State private var launchAtLogin = false
    @State private var launchError: String?
    @State private var notificationStatus: String?

    // Личные ключи OpenSky
    @State private var openSkyClientId = ""
    @State private var openSkyClientSecret = ""
    @State private var openSkyStatus: String?
    @State private var openSkyStatusIsError = false
    @State private var isCheckingOpenSky = false
    /// Показываем поля ввода поверх уже подключённых ключей.
    @State private var isReplacingOpenSky = false

    private var text: T { config.text }

    var body: some View {
        Form {
            // 1. Где мы смотрим: без этого приложение ни на что не смотрит.
            Section {
                coordinatesFields
                footnote(text(.coordsHint))
            } header: {
                Text(text(.coordsSection))
            }

            // 2. Что вообще попадает в список.
            Section {
                Picker(selection: $config.radiusKm) {
                    ForEach(RadiusOption.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                } label: {
                    Text(text(.radius))
                }
                .pickerStyle(.segmented)

                footnote(text(.radiusHint))

                Picker(selection: $config.maxAltitudeMeters) {
                    ForEach(AltitudeFilter.allCases) { option in
                        Text(option.label(text)).tag(option.rawValue)
                    }
                } label: {
                    Text(text(.altitudeLabel))
                }

                footnote(text(.altitudeHint))

                Toggle(isOn: $config.includeGround) {
                    Text(text(.showGround))
                }
            } header: {
                Text(text(.showSection))
            }

            // 3. Как часто обновляется и что видно в строке меню.
            Section {
                Picker(selection: $config.refreshSeconds) {
                    ForEach(AppConfig.refreshOptions, id: \.self) { seconds in
                        Text(text.interval(seconds)).tag(seconds)
                    }
                } label: {
                    Text(text(.pollInterval))
                }

                Picker(selection: $config.menuBarMode) {
                    ForEach(MenuBarMode.allCases) { mode in
                        Text(mode.label(text)).tag(mode.rawValue)
                    }
                } label: {
                    Text(text(.inMenuBar))
                }
            } header: {
                Text(text(.updateSection))
            }

            // 4. Как выглядит список.
            Section {
                Picker(selection: $config.countryStyle) {
                    ForEach(CountryStyle.allCases) { style in
                        Text(style.label(text)).tag(style.rawValue)
                    }
                } label: {
                    Text(text(.countryLabel))
                }

                footnote(text(.countryHint))

                Toggle(isOn: $config.rotateIconByCourse) {
                    Text(text(.rotateIconLabel))
                }

                footnote(text(.rotateIconHint))
            } header: {
                Text(text(.viewSection))
            }

            // 5. Оповещения.
            Section {
                Toggle(isOn: $config.notifyOnNewAircraft) {
                    Text(text(.notifyNewAircraft))
                }

                Picker(selection: $config.alertSound) {
                    ForEach(AlertSound.allCases) { sound in
                        Text(sound.label(text)).tag(sound.rawValue)
                    }
                } label: {
                    Text(text(.soundLabel))
                }
                .onChange(of: config.alertSound) { _, _ in
                    AircraftAlert.previewSound(config.alertSoundValue)
                }
                .disabled(!config.notifyOnNewAircraft)

                footnote(text(.notifyHint))
                footnote(text(.soundHint))

                Button {
                    AircraftAlert.test(
                        text: text,
                        format: config.format,
                        sound: config.alertSoundValue,
                        countryStyle: config.countryStyleValue
                    )
                } label: {
                    Text(text(.notifyTest))
                }
                .disabled(!config.notifyOnNewAircraft)

                if let notificationStatus {
                    Text(notificationStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(text(.notificationsSection))
            }

            // 6. Что приложение умеет дополнительно.
            Section {
                Toggle(isOn: $config.weatherEnabled) {
                    Text(text(.weatherToggle))
                }
                footnote(text(.weatherHint))

                Toggle(isOn: $config.familiarEnabled) {
                    Text(text(.familiarToggle))
                }

                HStack(spacing: 10) {
                    Button {
                        familiar.forgetAll()
                    } label: {
                        Text(text(.familiarForget))
                    }
                    .disabled(familiar.count == 0)

                    Text(text(.familiarCount, familiar.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                footnote(text(.familiarHint))
            } header: {
                Text(text(.observationSection))
            }

            // 7. Личные ключи: не обязательны, поэтому в конце.
            Section {
                openSkySection
            } header: {
                Text(text(.openSkySection))
            }

            // 8. Язык и запуск.
            Section {
                Picker(selection: $config.language) {
                    ForEach(Lang.allCases) { lang in
                        Text(lang.displayName(text)).tag(lang.rawValue)
                    }
                } label: {
                    Text(text(.interfaceLanguage))
                }
                .pickerStyle(.segmented)

                Toggle(isOn: $launchAtLogin) {
                    Text(text(.launchAtLogin))
                }
                .onChange(of: launchAtLogin) { _, value in
                    applyLaunchAtLogin(value)
                }

                footnote(text(.launchAtLoginHint))

                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                }

                // Сайт и версия: сюда смотрит человек, который только что поставил приложение.
                HStack {
                    Label(text(.websiteLabel), systemImage: "globe")
                    Spacer()
                    Link("humupthere.ru", destination: AppLinks.website)
                }

                HStack {
                    Text(text(.versionTitle))
                    Spacer()
                    Text(appVersion)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(text(.appSection))
            }

            // 9. Технические подробности — свёрнуты, чтобы не мешали.
            Section {
                DisclosureGroup(text(.aboutDataTitle)) {
                    VStack(alignment: .leading, spacing: 6) {
                        footnote(text(.dataSourcesLine))
                        footnote(text(.dataDisclaimer))
                        footnote(text(.vpnDisclaimer))
                        footnote(text(.routeDisclaimer))
                    }
                    .padding(.top, 4)
                }
            } header: {
                Text(text(.dataSection))
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 620)
        .navigationTitle(text(.appName))
        .onAppear {
            syncFieldsFromConfig()
            launchAtLogin = LaunchAtLogin.isEnabled
            NSApp.activate(ignoringOtherApps: true)
            Task { await syncNotificationStatus() }
        }
        .onChange(of: config.refreshSeconds) { _, _ in
            viewModel.startLoop()
        }
    }

    /// Версия приложения из Info.plist: у запуска из .build её может не быть.
    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1"
    }

    /// Раздел с личными ключами OpenSky: подключённые, замена или первичный ввод.
    @ViewBuilder
    private var openSkySection: some View {
        if viewModel.openSkyConfigured {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(Color.accentColor)
                Text(text(.openSkyActive))
                Spacer()
                Text(viewModel.openSkyClientId ?? "—")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let credits = viewModel.openSkyCredits {
                Text(text(.openSkyCredits, credits))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if isReplacingOpenSky {
                openSkyFields
                HStack(spacing: 10) {
                    Button {
                        Task { await saveOpenSky() }
                    } label: {
                        Text(text(.openSkySave))
                    }
                    .disabled(isCheckingOpenSky)

                    Button {
                        cancelOpenSkyReplacement()
                    } label: {
                        Text(text(.openSkyCancel))
                    }

                    if isCheckingOpenSky {
                        ProgressView().controlSize(.small)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Button {
                        Task { await checkOpenSky() }
                    } label: {
                        Text(text(.openSkyVerify))
                    }
                    .disabled(isCheckingOpenSky)

                    Button {
                        openSkyStatus = nil
                        openSkyStatusIsError = false
                        openSkyClientId = ""
                        openSkyClientSecret = ""
                        isReplacingOpenSky = true
                    } label: {
                        Text(text(.openSkyReplace))
                    }

                    Button {
                        Task {
                            await viewModel.removeOpenSkyCredentials()
                            openSkyStatus = nil
                            openSkyClientSecret = ""
                            isReplacingOpenSky = false
                        }
                    } label: {
                        Text(text(.openSkyRemove))
                    }
                }
            }
        } else {
            openSkyFields

            HStack(spacing: 10) {
                Button {
                    Task { await saveOpenSky() }
                } label: {
                    Text(text(.openSkySave))
                }
                .disabled(isCheckingOpenSky)

                Button {
                    viewModel.openOpenSkyAccountPage()
                } label: {
                    Text(text(.openSkyGetKeys))
                }

                if isCheckingOpenSky {
                    ProgressView().controlSize(.small)
                }
            }

            footnote(text(.openSkyRegistration))
        }

        if let openSkyStatus {
            Text(openSkyStatus)
                .font(.caption)
                .foregroundStyle(openSkyStatusIsError ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        DisclosureGroup(text(.openSkyWhy)) {
            footnote(text(.openSkyDetails))
                .padding(.top, 4)
        }
    }

    // MARK: - Секция координат

    @ViewBuilder
    private var coordinatesFields: some View {
        TextField(text: $latitudeText, prompt: Text("55.7558")) {
            Text(text(.latitude))
        }
        TextField(text: $longitudeText, prompt: Text("37.6173")) {
            Text(text(.longitude))
        }
        TextField(text: $placeText, prompt: Text("Москва")) {
            Text(text(.placeName))
        }

        HStack(spacing: 8) {
            Button {
                saveCoordinates()
            } label: {
                Text(text(.saveAndRefresh))
            }

            Button {
                Task { await detectByIP() }
            } label: {
                Text(isDetecting ? text(.detecting) : text(.detectByIP))
            }
            .disabled(isDetecting)
        }

        if let statusText {
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if config.locationConfigured {
            Text(text(.currentlyTracking, config.coordinateText))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// Поля для clientId и clientSecret — одни и те же при настройке и при замене.
    @ViewBuilder
    private var openSkyFields: some View {
        TextField(text(.openSkyClientIdLabel), text: $openSkyClientId)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))

        SecureField(text(.openSkyClientSecretLabel), text: $openSkyClientSecret)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))
    }

    private func footnote(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Действия

    /// Сохраняет ключи и проверяет их: результат показываем прямо под полями.
    private func saveOpenSky() async {
        isCheckingOpenSky = true
        defer { isCheckingOpenSky = false }

        let check = await viewModel.saveOpenSkyCredentials(
            clientId: openSkyClientId,
            clientSecret: openSkyClientSecret
        )
        openSkyStatus = check.message
        openSkyStatusIsError = !check.ok
        if check.ok {
            // Секрет больше не нужен в поле — он уже в файле.
            openSkyClientSecret = ""
            openSkyClientId = ""
            isReplacingOpenSky = false
        }
    }

    /// Отказ от замены: старые ключи остаются рабочими, поля очищаем.
    private func cancelOpenSkyReplacement() {
        isReplacingOpenSky = false
        openSkyClientId = ""
        openSkyClientSecret = ""
        openSkyStatus = nil
        openSkyStatusIsError = false
    }

    private func checkOpenSky() async {
        isCheckingOpenSky = true
        defer { isCheckingOpenSky = false }

        let check = await viewModel.verifyOpenSky()
        openSkyStatus = check.message
        openSkyStatusIsError = !check.ok
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchError = nil
        } catch {
            launchError = text(.launchAtLoginError, error.localizedDescription)
            // Возвращаем переключатель в реальное состояние системы.
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    private func applyNotifications(_ enabled: Bool) async {
        guard enabled else {
            notificationStatus = nil
            return
        }
        let manager = NotificationCenterManager.shared
        let granted = await manager.requestAuthorization()
        notificationStatus = granted ? text(.notifyGranted) : text(.notifyViaCard)
        AircraftAlert.test(
            text: text,
            format: config.format,
            sound: config.alertSoundValue,
            countryStyle: config.countryStyleValue
        )
    }

    private func syncNotificationStatus() async {
        let manager = NotificationCenterManager.shared
        await manager.refreshStatus()
        guard config.notifyOnNewAircraft else { return }
        notificationStatus = manager.isAuthorized ? text(.notifyGranted) : text(.notifyViaCard)
    }

    private func syncFieldsFromConfig() {
        guard config.locationConfigured else { return }
        latitudeText = String(format: "%.4f", config.latitude)
        longitudeText = String(format: "%.4f", config.longitude)
        placeText = config.placeName
    }

    private func saveCoordinates() {
        let latitude = Double(latitudeText.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces))
        let longitude = Double(longitudeText.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces))

        guard let latitude, let longitude, (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            statusText = text(.coordsError)
            return
        }

        config.saveCoordinates(
            latitude: latitude,
            longitude: longitude,
            placeName: placeText.trimmingCharacters(in: .whitespaces)
        )
        statusText = text(.savedRefreshing)

        Task { @MainActor in
            await viewModel.refresh()
            if let error = viewModel.errorText {
                statusText = text(.savedWithError, error)
            } else {
                statusText = text(.savedWithCount, config.radiusKm, viewModel.aircraft.count)
            }
        }
    }

    private func detectByIP() async {
        isDetecting = true
        statusText = text(.ipDetecting)
        defer { isDetecting = false }

        guard let url = URL(string: "https://ipwho.is/") else { return }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, _) = try await URLSession.shared.data(for: request)
            guard
                let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                (root["success"] as? Bool) == true,
                let latitude = root["latitude"] as? Double,
                let longitude = root["longitude"] as? Double
            else {
                statusText = text(.ipFailed)
                return
            }

            latitudeText = String(format: "%.4f", latitude)
            longitudeText = String(format: "%.4f", longitude)

            let city = root["city"] as? String ?? ""
            let country = root["country"] as? String ?? ""
            let place = [city, country].filter { !$0.isEmpty }.joined(separator: ", ")
            if placeText.isEmpty { placeText = place }

            saveCoordinates()
            let suffix = place.isEmpty ? "" : " (\(place))"
            statusText = text(.ipDone, suffix) + " " + text(.ipVpnWarning)
        } catch {
            statusText = text(.networkError, error.localizedDescription)
        }
    }
}
