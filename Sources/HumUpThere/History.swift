import Foundation
import Combine
import HumUpThereCore

/// Один визит борта в радиус наблюдения.
///
/// Именно визит, а не просто борт: один и тот же самолёт за сутки может пролететь дважды,
/// и это две разные строки истории — с разным временем, маршрутом и высотой.
struct HistoryEntry: Codable, Identifiable, Hashable {
    let id: String
    let hex: String
    var callsign: String?
    var registration: String?
    var typeCode: String?
    var route: FlightRoute?
    var firstSeen: Date
    var lastSeen: Date
    var closestKm: Double
    var minAltitudeMeters: Double?
    var maxAltitudeMeters: Double?

    init(from aircraft: Aircraft, at moment: Date) {
        self.id = "\(aircraft.id)-\(Int(moment.timeIntervalSince1970))"
        self.hex = aircraft.id
        self.callsign = aircraft.callsign
        self.registration = aircraft.registration
        self.typeCode = aircraft.typeCode
        self.route = aircraft.route
        self.firstSeen = moment
        self.lastSeen = moment
        self.closestKm = aircraft.distanceKm
        self.minAltitudeMeters = aircraft.altitudeMeters
        self.maxAltitudeMeters = aircraft.altitudeMeters
    }

    var airlineName: String? { route?.shortAirline }

    var flightLabel: String {
        callsign ?? registration ?? hex.uppercased()
    }

    func routeTitle(russian: Bool) -> String? {
        route?.title(russian: russian)
    }
}

/// История пролетевших бортов.
///
/// Хранится три дня и живёт в файле, чтобы переживать перезапуск приложения.
/// Пишем всё, что видел источник, независимо от фильтра по высоте: это журнал того,
/// что действительно было над головой, а фильтр — настройка отображения.
@MainActor
final class HistoryStore: ObservableObject {
    static let retentionDays = 3
    static let retention: TimeInterval = TimeInterval(retentionDays) * 24 * 3600
    /// Если борт пропал и вернулся в пределах этого времени, это тот же визит.
    static let visitGap: TimeInterval = 30 * 60
    private static let limit = 3000

    @Published private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL?

    init(fileURL: URL? = HistoryStore.defaultFileURL()) {
        self.fileURL = fileURL
        load()
        prune(Date())
        entries.sort { $0.firstSeen > $1.firstSeen }
    }

    /// `nonisolated`, потому что вызывается как значение по умолчанию в init.
    nonisolated static func defaultFileURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("HumUpThere", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("history.json")
    }

    /// Дописывает визиты: обновляет текущие и создаёт новые.
    func record(_ aircraft: [Aircraft], at moment: Date = Date()) {
        guard !aircraft.isEmpty else {
            prune(moment)
            return
        }

        // Индекс самого свежего визита для каждого борта.
        var newest: [String: Int] = [:]
        for (offset, entry) in entries.enumerated() {
            if let existing = newest[entry.hex], entries[existing].lastSeen >= entry.lastSeen {
                continue
            }
            newest[entry.hex] = offset
        }

        for item in aircraft {
            if let index = newest[item.id],
               moment.timeIntervalSince(entries[index].lastSeen) < Self.visitGap {
                update(&entries[index], with: item, at: moment)
            } else {
                entries.append(HistoryEntry(from: item, at: moment))
                newest[item.id] = entries.count - 1
            }
        }

        prune(moment)
        entries.sort { $0.firstSeen > $1.firstSeen }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    /// Дополняет записи маршрутами из кэша — без сети.
    ///
    /// Справочник спрашивается только для ближайших бортов, поэтому у части записей
    /// маршрута нет. Но если позывной когда-нибудь попадал в ближайшие, маршрут уже
    /// лежит в кэше и его можно подставить бесплатно.
    func fillRoutesFromCache() async {
        let missing = entries.filter { $0.route == nil }.compactMap { $0.callsign }
        guard !missing.isEmpty else { return }

        let routes = await RouteService().cachedRoutes(for: missing)
        guard !routes.isEmpty else { return }

        var changed = false
        for index in entries.indices {
            guard
                entries[index].route == nil,
                let callsign = entries[index].callsign?.uppercased(),
                let route = routes[callsign]
            else {
                continue
            }
            entries[index].route = route
            changed = true
        }

        if changed { save() }
    }

    private func update(_ entry: inout HistoryEntry, with item: Aircraft, at moment: Date) {
        entry.lastSeen = moment
        entry.closestKm = min(entry.closestKm, item.distanceKm)

        if let meters = item.altitudeMeters {
            entry.minAltitudeMeters = min(entry.minAltitudeMeters ?? meters, meters)
            entry.maxAltitudeMeters = max(entry.maxAltitudeMeters ?? meters, meters)
        }

        // Поля, которые могли появиться позже: справочник маршрутов отвечает не сразу.
        if entry.callsign == nil { entry.callsign = item.callsign }
        if entry.registration == nil { entry.registration = item.registration }
        if entry.typeCode == nil { entry.typeCode = item.typeCode }
        if entry.route == nil { entry.route = item.route }
    }

    /// Убираем всё, что старше срока хранения.
    private func prune(_ now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        entries.removeAll { $0.lastSeen < cutoff }

        if entries.count > Self.limit {
            entries.sort { $0.lastSeen > $1.lastSeen }
            entries = Array(entries.prefix(Self.limit))
        }
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
