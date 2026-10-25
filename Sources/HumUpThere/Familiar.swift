import Foundation
import Combine
import HumUpThereCore

/// Борт, которого мы уже видели раньше.
struct FamiliarAircraft: Codable, Hashable {
    let hex: String
    var registration: String?
    var typeCode: String?
    var lastCallsign: String?
    var lastAirline: String?
    var firstSeen: Date
    var lastSeen: Date
    /// Сколько раз борт прилетал к вам — то есть сколько отдельных визитов.
    var sightings: Int

    var isRepeatVisitor: Bool { sightings > 1 }
}

/// Реестр знакомых бортов.
///
/// В отличие от истории, которая живёт три дня, этот список не истекает: самолёты летают
/// одни и те же годами, и через полгода приложение начинает узнавать старых знакомых.
/// Функцию можно выключить в настройках — тогда реестр не пополняется.
@MainActor
final class FamiliarStore: ObservableObject {
    /// Если борт пропал и вернулся позже этого срока, это новый визит.
    static let visitGap: TimeInterval = 30 * 60
    /// Совсем старые записи убираем, чтобы файл не рос бесконечно.
    private static let retention: TimeInterval = 730 * 24 * 3600
    private static let limit = 20000

    @Published private(set) var aircraft: [String: FamiliarAircraft] = [:]

    private let fileURL: URL?
    private var lastSave = Date.distantPast

    init(fileURL: URL? = FamiliarStore.defaultFileURL()) {
        self.fileURL = fileURL
        load()
        prune(Date())
    }

    /// `nonisolated`, потому что вызывается как значение по умолчанию в init.
    nonisolated static func defaultFileURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("HumUpThere", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("familiar.json")
    }

    func info(for hex: String) -> FamiliarAircraft? {
        aircraft[hex]
    }

    func record(_ list: [Aircraft], at moment: Date = Date()) {
        guard !list.isEmpty else { return }

        var addedOrReturned = false

        for item in list {
            if var existing = aircraft[item.id] {
                if moment.timeIntervalSince(existing.lastSeen) >= Self.visitGap {
                    existing.sightings += 1
                    addedOrReturned = true
                }
                existing.lastSeen = moment
                existing.registration = existing.registration ?? item.registration
                existing.typeCode = existing.typeCode ?? item.typeCode
                existing.lastCallsign = item.callsign ?? existing.lastCallsign
                existing.lastAirline = item.route?.shortAirline ?? existing.lastAirline
                aircraft[item.id] = existing
            } else {
                aircraft[item.id] = FamiliarAircraft(
                    hex: item.id,
                    registration: item.registration,
                    typeCode: item.typeCode,
                    lastCallsign: item.callsign,
                    lastAirline: item.route?.shortAirline,
                    firstSeen: moment,
                    lastSeen: moment,
                    sightings: 1
                )
                addedOrReturned = true
            }
        }

        prune(moment)
        // Полную запись на диск делаем не чаще раза в минуту, но новые знакомства
        // и повторные визиты сохраняем сразу — это как раз то, что ценно.
        save(force: addedOrReturned)
    }

    func forgetAll() {
        aircraft.removeAll()
        save(force: true)
    }

    var count: Int { aircraft.count }

    var repeatVisitors: Int {
        aircraft.values.filter(\.isRepeatVisitor).count
    }

    private func prune(_ now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        aircraft = aircraft.filter { $0.value.lastSeen >= cutoff }

        if aircraft.count > Self.limit {
            let keep = aircraft
                .sorted { $0.value.lastSeen > $1.value.lastSeen }
                .prefix(Self.limit)
            aircraft = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode([String: FamiliarAircraft].self, from: data) else { return }
        aircraft = decoded
    }

    private func save(force: Bool) {
        guard force || Date().timeIntervalSince(lastSave) > 60 else { return }
        guard let fileURL, let data = try? JSONEncoder().encode(aircraft) else { return }
        try? data.write(to: fileURL, options: .atomic)
        lastSave = Date()
    }
}
