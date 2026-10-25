import SwiftUI
import AppKit
import HumUpThereCore

/// Звук оповещения. Оба файла короткие и специально тихие: оповещение должно
/// обращать внимание, а не заставлять вздрогнуть.
enum AlertSound: String, CaseIterable, Identifiable {
    case airport
    case hum

    var id: String { rawValue }

    var fileName: String { rawValue + ".aiff" }

    /// URL файла в бандле, если он там есть.
    var url: URL? {
        Bundle.main.url(forResource: rawValue, withExtension: "aiff")
    }

    func label(_ text: T) -> String {
        switch self {
        case .airport: return text(.soundAirport)
        case .hum: return text(.soundHum)
        }
    }

    static func resolved(_ stored: String) -> AlertSound {
        AlertSound(rawValue: stored) ?? .airport
    }
}

/// Канал оповещения о новом борте.
///
/// Системные уведомления требуют разрешения, а его ещё нужно получить и подтвердить.
/// Поэтому есть второй канал, которому никакие разрешения не нужны: всплывающая
/// карточка поверх окон и звук. Если уведомления разрешены — идём через них,
/// иначе показываем карточку, и оповещение работает в любом случае.
@MainActor
enum AircraftAlert {
    static func deliver(
        aircraft: [Aircraft],
        text: T,
        format: DisplayFormat,
        sound: AlertSound,
        countryStyle: CountryStyle
    ) {
        guard !aircraft.isEmpty else { return }
        if NotificationCenterManager.shared.isAuthorized {
            NotificationCenterManager.shared.notify(
                aircraft: aircraft, text: text, format: format, sound: sound
            )
        } else {
            AircraftAlertPresenter.shared.show(
                aircraft: aircraft, text: text, format: format, sound: sound, countryStyle: countryStyle
            )
        }
    }

    /// Проверка из настроек: используем тот же путь, что и в работе.
    static func test(text: T, format: DisplayFormat, sound: AlertSound, countryStyle: CountryStyle) {
        if NotificationCenterManager.shared.isAuthorized {
            NotificationCenterManager.shared.sendTest(text: text, sound: sound)
        } else {
            AircraftAlertPresenter.shared.show(
                aircraft: [],
                text: text,
                format: format,
                sound: sound,
                countryStyle: countryStyle,
                overrideMessage: text(.notifyTestBody)
            )
        }
    }

    /// Просто проиграть звук — чтобы услышать выбор в настройках.
    static func previewSound(_ sound: AlertSound) {
        guard let url = sound.url else { return }
        NSSound(contentsOf: url, byReference: true)?.play()
    }
}

/// Всплывающая карточка в правом верхнем углу, под строкой меню.
@MainActor
final class AircraftAlertPresenter {
    static let shared = AircraftAlertPresenter()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private static let humDuration: TimeInterval = 7

    func show(
        aircraft: [Aircraft],
        text: T,
        format: DisplayFormat,
        sound: AlertSound,
        countryStyle: CountryStyle,
        overrideMessage: String? = nil
    ) {
        playSound(sound)

        let view = AircraftAlertView(
            aircraft: aircraft,
            text: text,
            format: format,
            countryStyle: countryStyle,
            overrideMessage: overrideMessage
        )
        let hosting = NSHostingView(rootView: view)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        panel?.orderOut(nil)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = hosting

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - size.width - 16,
                y: visible.maxY - size.height - 12
            ))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.humDuration))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
            self?.panel = nil
        }
    }

    /// Звук оповещения из бандла. Если файла нет — просто молчим, это не ошибка.
    private func playSound(_ sound: AlertSound) {
        guard let url = sound.url else { return }
        NSSound(contentsOf: url, byReference: true)?.play()
    }
}

/// Содержимое карточки: кто появился и куда летит.
struct AircraftAlertView: View {
    /// Ширина текстовой части. Карточка держит прежние 320 точек: раньше её раздувала
    /// самая длинная строка маршрута, потому что переносимый текст сообщает идеальную
    /// ширину как однострочную. Явная ширина возвращает карточке исходный размер.
    private static let contentWidth: CGFloat = 292

    let aircraft: [Aircraft]
    let text: T
    let format: DisplayFormat
    var countryStyle: CountryStyle = .name
    var overrideMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "airplane")
                    .foregroundStyle(Color.accentColor)
                Text(text(.appName))
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 12)
                Text(text(.notifyTitle))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let overrideMessage {
                Text(overrideMessage)
                    .font(.system(size: 12))
            } else {
                ForEach(aircraft) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        // Кто летит и как далеко от вас.
                        HStack(alignment: .top, spacing: 5) {
                            if countryStyle == .code, let code = item.route?.airlineCountryCode {
                                badge(code, monospaced: true)
                            }

                            Text(item.displayName)
                                .font(.system(size: 12, weight: .semibold))

                            if let type = item.typeCode {
                                badge(type, monospaced: false)
                            }

                            if let registration = item.registration, item.callsign != nil {
                                Text(registration)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer(minLength: 8)

                            VStack(alignment: .trailing, spacing: 1) {
                                Text(item.distanceText(format))
                                    .font(.system(size: 12, weight: .semibold))
                                    .monospacedDigit()
                                HStack(spacing: 3) {
                                    Image(systemName: item.climbState.symbolName)
                                        .font(.system(size: 9))
                                    Text(item.climbState.title(text))
                                        .font(.system(size: 9))
                                }
                                .foregroundStyle(.secondary)
                            }
                        }

                        // Куда летит и сколько ему осталось — главное в карточке.
                        if let route = item.routeTitle(russian: text.isRussian) {
                            Text(presenter.routeLine(item, route: route))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: Self.contentWidth, alignment: .leading)
                                .help(presenter.routeHelp(item, route: route))
                        }

                        // Кто именно, на какой высоте, куда и как быстро.
                        Text(presenter.details(item))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: Self.contentWidth, alignment: .leading)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(width: Self.contentWidth + 28, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    /// Общее форматирование с карточкой и списком.
    private var presenter: AircraftText {
        AircraftText(text: text, format: format, countryStyle: countryStyle)
    }

    private func badge(_ value: String, monospaced: Bool) -> some View {
        Text(value)
            .font(.system(size: 9, weight: .semibold, design: monospaced ? .monospaced : .default))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
            )
            .foregroundStyle(.secondary)
    }
}
