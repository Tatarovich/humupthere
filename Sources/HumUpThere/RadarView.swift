import SwiftUI
import AppKit
import HumUpThereCore

/// Содержимое иконки в строке меню: что видно при клике.
struct RadarView: View {
    @EnvironmentObject private var config: AppConfig
    @ObservedObject var viewModel: RadarViewModel
    @ObservedObject var familiar: FamiliarStore
    @Environment(\.openWindow) private var openWindow

    /// Режим для скриншотов сайта: ImageRenderer не отрисовывает LazyVStack и кнопки,
    /// поэтому список рисуется обычным VStack, а подвал — статичными подписями.
    var previewMode = false

    private var text: T { config.text }
    private var format: DisplayFormat { config.format }

    var body: some View {
        VStack(spacing: 0) {
            header
            weatherStrip
            Divider()
            content
            Divider()
            footer
        }
        // 420 вместо 380: в узком окне маршрут и детали обрезались многоточием.
        .frame(width: 420)
    }

    // MARK: - Шапка

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "airplane")
                    .foregroundStyle(Color.accentColor)
                Text(text(.appName))
                    .font(.headline)
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            Text("\(text(.radius)) \(config.radiusKm) \(format.kmUnit) · \(config.coordinateText)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text("\(viewModel.lastUpdateText) · \(text(.sourceLabel, viewModel.sourceName))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Погода

    /// Погода и вердикт по ближайшему борту.
    ///
    /// Раньше это была одна строка: слева сводка погоды, справа вердикт. В поповере шириной
    /// 380 точек обе части не помещались и обрезались. Теперь это две строки: сначала цифры,
    /// под ними — ответ на главный вопрос, увидите вы борт или только услышите.
    @ViewBuilder
    private var weatherStrip: some View {
        if config.weatherEnabled, viewModel.weather != nil || viewModel.weatherError != nil {
            VStack(alignment: .leading, spacing: 3) {
                if let weather = viewModel.weather {
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: weatherSymbol(weather))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 12, alignment: .center)

                        Text(weatherSummary(weather))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)

                        Spacer(minLength: 0)
                    }

                    if let verdict = verdictForNearest, let nearest = viewModel.nearest {
                        HStack(alignment: .top, spacing: 5) {
                            // Если вердикт показывает ту же облачность, что и строка выше,
                            // второй одинаковый значок только мешает: оставляем пустое место.
                            Group {
                                if verdict.symbolName == weatherSymbol(weather) {
                                    Color.clear
                                } else {
                                    Image(systemName: verdict.symbolName)
                                        .foregroundStyle(verdict.isVisible ? Color.primary : Color.secondary)
                                }
                            }
                            .font(.system(size: 10))
                            .frame(width: 12, height: 12, alignment: .center)

                            Text("\(nearest.displayName) — \(verdict.title(text))")
                                .font(.system(size: 10))
                                .foregroundStyle(verdict.isVisible ? Color.primary : Color.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)

                            Spacer(minLength: 0)
                        }
                    }
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "cloud.drizzle")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .frame(width: 12, alignment: .center)
                        Text(text(.weatherUnavailable))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 9)
        }
    }

    /// Иконка по погоде: ночь, ясно, просветы или сплошная облачность.
    private func weatherSymbol(_ weather: WeatherSnapshot) -> String {
        if weather.isDay == false { return "moon.stars" }
        guard let cover = weather.cloudCover else { return "cloud" }
        if cover <= 25 { return "sun.max" }
        if cover <= 60 { return "cloud.sun" }
        return "cloud"
    }

    private var verdictForNearest: VisibilityVerdict? {
        guard let nearest = viewModel.nearest else { return nil }
        let verdict = viewModel.visibility(for: nearest)
        return verdict == .unknown ? nil : verdict
    }

    private func weatherSummary(_ weather: WeatherSnapshot) -> String {
        var parts: [String] = []
        if let cover = weather.cloudCover {
            parts.append(text(.weatherClouds, cover))
        }
        if let base = weather.estimatedCloudBaseMeters {
            parts.append(text(.weatherCloudBase, format.meters(base)))
        }
        if let visibility = weather.visibilityKm {
            parts.append(text(.weatherVisibility, format.km(visibility)))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Основная часть

    @ViewBuilder
    private var content: some View {
        if !config.locationConfigured {
            placeholder(
                icon: "location.magnifyingglass",
                title: text(.coordsMissingTitle),
                message: text(.coordsMissingMessage),
                actionTitle: text(.openSettings)
            ) { openPreferences() }
        } else if let errorText = viewModel.errorText, viewModel.aircraft.isEmpty {
            placeholder(
                icon: "exclamationmark.triangle",
                title: text(.sourceFailedTitle),
                message: errorText,
                actionTitle: text(.retry)
            ) { Task { await viewModel.refresh() } }
        } else if viewModel.aircraft.isEmpty {
            placeholder(
                icon: "moon.stars",
                title: text(.emptySkyTitle),
                message: text(.emptySkyMessage, config.radiusKm, text.interval(config.refreshSeconds)),
                actionTitle: text(.update)
            ) { Task { await viewModel.refresh() } }
        } else {
            VStack(spacing: 0) {
                if let errorText = viewModel.errorText {
                    warningStrip(errorText)
                }
                list
            }
        }
    }

    private var list: some View {
        Group {
            if previewMode {
                // ImageRenderer не прокручивает и не раскладывает LazyVStack: для снимка
                // с сайта все строки рисуем обычным VStack в фиксированной высоте.
                VStack(spacing: 0) { listRows }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) { listRows }
                }
            }
        }
        // У ScrollView нет собственной высоты, а окно поповера подстраивается
        // под идеальный размер содержимого: без явной высоты список схлопывался в ноль.
        .frame(height: listHeight)
    }

    @ViewBuilder
    private var listRows: some View {
        ForEach(viewModel.aircraft.prefix(20)) { aircraft in
            AircraftRow(
                aircraft: aircraft,
                text: text,
                format: format,
                countryStyle: config.countryStyleValue,
                rotateByCourse: config.rotateIconByCourse,
                visibility: viewModel.visibility(for: aircraft),
                familiar: config.familiarEnabled ? familiar.info(for: aircraft.id) : nil
            )
            Divider()
                .padding(.leading, 50)
        }
    }

    /// Высота списка: растёт по числу бортов и упирается в потолок, дальше — прокрутка.
    private var listHeight: CGFloat {
        let rows = min(viewModel.aircraft.count, 20)
        let rowHeight: CGFloat = 76
        return min(max(CGFloat(rows) * rowHeight, 76), 380)
    }

    private func warningStrip(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .lineLimit(2)
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08))
    }

    private func placeholder(
        icon: String,
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline)
                .bold()
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: action)
                .controlSize(.small)
                .padding(.top, 2)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Подвал

    private var footer: some View {
        HStack(spacing: 14) {
            if previewMode {
                // ImageRenderer рисует кнопки жёлтыми заглушками, поэтому для снимка
                // оставляем те же подписи, но без Button.
                Label(text(.refresh), systemImage: "arrow.clockwise")
                Spacer()
                Label(text(.historyButton), systemImage: "clock.arrow.circlepath")
                Label(text(.settings), systemImage: "gearshape")
                Label(text(.quit), systemImage: "power")
            } else {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label(text(.refresh), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isLoading)

                Spacer()

                Button {
                    openHistory()
                } label: {
                    Label(text(.historyButton), systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.borderless)

                Button {
                    openPreferences()
                } label: {
                    Label(text(.settings), systemImage: "gearshape")
                }
                .buttonStyle(.borderless)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label(text(.quit), systemImage: "power")
                }
                .buttonStyle(.borderless)
            }
        }
        .font(.caption)
        .foregroundStyle(previewMode ? Color.secondary : Color.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func openPreferences() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: AppWindow.settings)
    }

    private func openHistory() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: AppWindow.history)
    }
}

/// Строка списка: кто летит, откуда и куда, на какой высоте и как далеко.
struct AircraftRow: View {
    let aircraft: Aircraft
    let text: T
    let format: DisplayFormat
    var countryStyle: CountryStyle = .name
    var rotateByCourse: Bool = true
    /// Увидит ли человек этот борт глазами при текущей погоде.
    var visibility: VisibilityVerdict = .unknown
    /// Знакомый борт: сколько раз его уже встречали.
    var familiar: FamiliarAircraft?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            planeIcon
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                titleLine

                if let route = aircraft.routeTitle(russian: text.isRussian) {
                    Text(presenter.routeLine(aircraft, route: route))
                        .font(.system(size: 11, weight: .medium))
                        // Синий в списке отвлекал: маршрут выделяется размером и насыщенностью.
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(presenter.routeHelp(aircraft, route: route))
                }

                Text(presenter.details(aircraft))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                Text(aircraft.distanceText(format))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                HStack(spacing: 3) {
                    Image(systemName: aircraft.climbState.symbolName)
                        .font(.system(size: 9))
                    Text(aircraft.climbState.title(text))
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var planeIcon: some View {
        // Базовый символ «airplane» смотрит вправо, то есть на восток (курс 90°).
        // Поэтому поворот = курс − 90: на север иконка смотрит вверх, на юг — вниз.
        // Без поворота по курсу ставим нос вверх — так же, как на иконке приложения.
        let rotation = rotateByCourse ? (aircraft.trackDeg ?? 90) - 90 : -90
        return ZStack {
            // Серый на сером: цветные иконки в списке отвлекали от самих данных.
            Circle()
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 32, height: 32)
            Image(systemName: "airplane")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.secondary)
                .rotationEffect(.degrees(rotation))
        }
    }

    /// Значок страны перед позывным: компактный код. Название страны показывается
    /// в строке деталей, чтобы не растягивать первую строку.
    @ViewBuilder
    private var countryBadge: some View {
        switch countryStyle {
        case .code:
            if let code = aircraft.route?.airlineCountryCode {
                Text(code)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.secondary.opacity(0.15))
                    )
                    .foregroundStyle(.secondary)
            }
        case .name, .none:
            EmptyView()
        }
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            countryBadge
            Text(aircraft.displayName)
                .font(.system(size: 13, weight: .semibold))
            if let type = aircraft.typeCode {
                Text(type)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    .foregroundStyle(.secondary)
            }
            if let registration = aircraft.registration, aircraft.callsign != nil {
                Text(registration)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            visibilityMark
            familiarMark
        }
    }

    /// Глаз — только у тех бортов, которые сейчас действительно видно.
    @ViewBuilder
    private var visibilityMark: some View {
        if visibility.isVisible {
            Image(systemName: "eye")
                .font(.system(size: 10))
                .foregroundStyle(Color.primary)
                .help(visibility.title(text))
        }
    }

    /// Знакомый борт: показываем счётчик встреч, начиная со второй.
    @ViewBuilder
    private var familiarMark: some View {
        if let familiar, familiar.isRepeatVisitor {
            HStack(spacing: 2) {
                Image(systemName: "repeat")
                    .font(.system(size: 8, weight: .semibold))
                Text("\(familiar.sightings)")
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
            .foregroundStyle(.secondary)
            .help(familiarHelp(familiar))
        }
    }

    private func familiarHelp(_ familiar: FamiliarAircraft) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return text(.familiarTooltip, familiar.sightings, formatter.string(from: familiar.firstSeen))
    }

    /// Маршрут плюс оценка времени до посадки, если её можно посчитать.
    /// Общее форматирование: то же самое использует карточка оповещения.
    private var presenter: AircraftText {
        AircraftText(text: text, format: format, countryStyle: countryStyle)
    }
}
