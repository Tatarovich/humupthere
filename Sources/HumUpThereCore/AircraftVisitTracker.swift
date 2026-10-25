import Foundation

/// Помнит, какие борта уже были в радиусе, чтобы не считать их новыми повторно.
///
/// Сравнивать только с предыдущим снимком нельзя: борт, идущий по краю радиуса, на одном
/// опросе может пропасть, а на следующем появиться снова — и выглядел бы как новый. То же
/// бывает при переключении на запасной источник: он видит другой набор бортов.
///
/// Поэтому борт считается новым, только если его не было в радиусе последние `memory` секунд.
public struct AircraftVisitTracker {
    private var lastSeen: [String: Date]
    private let memory: TimeInterval

    public init(memory: TimeInterval = 30 * 60) {
        self.lastSeen = [:]
        self.memory = memory
    }

    /// Борта, которых не было в радиусе дольше, чем `memory`.
    public mutating func newAircraft(in current: [Aircraft], at now: Date = Date()) -> [Aircraft] {
        var fresh: [Aircraft] = []

        for item in current {
            if let seen = lastSeen[item.id] {
                if now.timeIntervalSince(seen) >= memory {
                    fresh.append(item)
                }
            } else {
                fresh.append(item)
            }
            lastSeen[item.id] = now
        }

        prune(now)
        return fresh
    }

    /// Забыть всё: например, при смене точки наблюдения или источника.
    public mutating func reset() {
        lastSeen.removeAll()
    }

    public var trackedCount: Int { lastSeen.count }

    /// Записи держим вдвое дольше памяти — чтобы не терять горячие данные.
    private mutating func prune(_ now: Date) {
        lastSeen = lastSeen.filter { now.timeIntervalSince($0.value) < memory * 2 }
    }
}
