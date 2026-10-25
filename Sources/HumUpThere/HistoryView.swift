import SwiftUI
import HumUpThereCore

/// Раздел «История»: таблица бортов, пролетевших над точкой наблюдения за последние три дня.
struct HistoryView: View {
    @EnvironmentObject private var config: AppConfig
    @ObservedObject var history: HistoryStore
    @ObservedObject var familiar: FamiliarStore

    private var text: T { config.text }
    private var format: DisplayFormat { config.format }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if history.entries.isEmpty {
                emptyState
            } else {
                table
            }
        }
        .frame(width: 900, height: 560)
        .navigationTitle(text(.historyTitle))
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            Task { await history.fillRoutesFromCache() }
        }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(Color.accentColor)
            Text(text(.historyTitle))
                .font(.headline)
            Spacer()
            Text(text(.historyRetention, HistoryStore.retentionDays))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text(.historyCount, history.entries.count))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button {
                history.clear()
            } label: {
                Text(text(.historyClear))
            }
            .disabled(history.entries.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(text(.historyEmptyTitle))
                .font(.subheadline)
                .bold()
            Text(text(.historyEmptyMessage))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Таблица

    private var table: some View {
        Table(history.entries) {
            TableColumn(text(.historyColumnTime)) { entry in
                Text(timeText(entry))
                    .monospacedDigit()
                    .help(detailHelp(entry))
            }
            .width(min: 80, ideal: 100)

            TableColumn(text(.historyColumnFlight)) { entry in
                HStack(spacing: 4) {
                    Text(entry.flightLabel)
                        .font(.system(size: 12, weight: .medium))
                    if config.familiarEnabled,
                       let familiar = familiar.info(for: entry.hex),
                       familiar.isRepeatVisitor {
                        HStack(spacing: 2) {
                            Image(systemName: "repeat")
                                .font(.system(size: 8, weight: .semibold))
                            Text("\(familiar.sightings)")
                                .font(.system(size: 9, weight: .semibold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 70, ideal: 110)

            TableColumn(text(.historyColumnSightings)) { entry in
                if config.familiarEnabled, let familiar = familiar.info(for: entry.hex) {
                    Text("\(familiar.sightings)")
                        .monospacedDigit()
                        .foregroundStyle(familiar.isRepeatVisitor ? .primary : .secondary)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .width(min: 50, ideal: 70)

            TableColumn(text(.historyColumnType)) { entry in
                Text(entry.typeCode ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 62)

            TableColumn(text(.historyColumnAirline)) { entry in
                Text(entry.airlineName ?? "—")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 160)

            TableColumn(text(.historyColumnRoute)) { entry in
                Text(entry.routeTitle(russian: text.isRussian) ?? "—")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(entry.routeTitle(russian: text.isRussian) ?? "")
            }

            TableColumn(text(.historyColumnDistance)) { entry in
                Text(format.km(entry.closestKm))
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 80)

            TableColumn(text(.historyColumnAltitude)) { entry in
                Text(altitudeText(entry))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 130)
        }
    }

    // MARK: - Форматирование

    private func timeText(_ entry: HistoryEntry) -> String {
        let formatter = DateFormatter()
        let isToday = Calendar.current.isDateInToday(entry.firstSeen)
        formatter.dateFormat = isToday ? "HH:mm" : "dd.MM HH:mm"
        return formatter.string(from: entry.firstSeen)
    }

    private func altitudeText(_ entry: HistoryEntry) -> String {
        guard let low = entry.minAltitudeMeters else { return "—" }
        guard let high = entry.maxAltitudeMeters, high - low > 50 else {
            return format.meters(low)
        }
        return format.meters(low) + " – " + format.meters(high)
    }

    private func detailHelp(_ entry: HistoryEntry) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
        let minutes = max(0, Int(entry.lastSeen.timeIntervalSince(entry.firstSeen) / 60))
        return [
            "\(text(.historyFirstSeen)): \(formatter.string(from: entry.firstSeen))",
            "\(text(.historyLastSeen)): \(formatter.string(from: entry.lastSeen))",
            "\(text(.historyDuration)): \(format.duration(hours: Double(minutes) / 60))",
            "ICAO24: \(entry.hex.uppercased())"
        ].joined(separator: "\n")
    }
}
