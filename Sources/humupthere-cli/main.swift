import Foundation
import HumUpThereCore

// Небольшая утилита для проверки источников из терминала:
//   swift run humupthere-cli --lat 55.755864 --lon 37.617698 --radius 50

struct Options {
    var lat = 55.755864
    var lon = 37.617698
    var radius = 50.0
    var includeGround = false
    var limit = 12
    var withRoutes = true
    var maxAltitude: Int?
}

func parseOptions() -> Options {
    var options = Options()
    let args = CommandLine.arguments
    var index = 1
    while index < args.count {
        let key = args[index]
        let value = index + 1 < args.count ? args[index + 1] : nil
        switch key {
        case "--lat":
            if let value, let parsed = Double(value) { options.lat = parsed; index += 1 }
        case "--lon":
            if let value, let parsed = Double(value) { options.lon = parsed; index += 1 }
        case "--radius":
            if let value, let parsed = Double(value) { options.radius = parsed; index += 1 }
        case "--limit":
            if let value, let parsed = Int(value) { options.limit = parsed; index += 1 }
        case "--max-altitude":
            if let value, let parsed = Int(value) { options.maxAltitude = parsed; index += 1 }
        case "--ground":
            options.includeGround = true
        case "--no-routes":
            options.withRoutes = false
        case "--help", "-h":
            print("""
            humupthere-cli — проверка открытых источников

              --lat <широта>        по умолчанию 55.755864 (Москва)
              --lon <долгота>       по умолчанию 37.617698
              --radius <км>         по умолчанию 50
              --max-altitude <м>    только борта ниже этой высоты
              --limit <n>           сколько строк показать, по умолчанию 12
              --ground              включать борта на земле
              --no-routes           не запрашивать справочник маршрутов
            """)
            exit(0)
        default:
            break
        }
        index += 1
    }
    return options
}

func pad(_ text: String, _ width: Int) -> String {
    let count = text.count
    if count >= width { return String(text.prefix(width)) }
    return text + String(repeating: " ", count: width - count)
}

func climbTitle(_ state: ClimbState) -> String {
    switch state {
    case .climbing: return "набор"
    case .descending: return "снижение"
    case .level: return "эшелон"
    case .unknown: return "нет данных"
    }
}

let options = parseOptions()
let format = DisplayFormat(language: "ru")
let client = ADSBClient()

print("Координаты: \(String(format: "%.4f", options.lat)), \(String(format: "%.4f", options.lon))"
    + " · радиус \(Int(options.radius)) км"
    + (options.includeGround ? " · с бортами на земле" : ""))

let started = Date()
do {
    let result = try await client.fetch(
        lat: options.lat,
        lon: options.lon,
        radiusKm: options.radius,
        includeGround: options.includeGround
    )
    let elapsed = Date().timeIntervalSince(started)
    let all = result.aircraft.sorted { $0.distanceKm < $1.distanceKm }
    let sorted = all.filter { item in
        guard let limit = options.maxAltitude else { return true }
        guard let meters = item.altitudeMeters else { return true }
        return meters <= Double(limit)
    }

    print("Источник: \(result.source.rawValue) · ответ за \(String(format: "%.2f", elapsed)) с")
    print("Бортов в радиусе: \(all.count)"
        + (sorted.count == all.count ? "" : " · после фильтра по высоте: \(sorted.count)"))
    print("")

    guard !sorted.isEmpty else {
        print("В радиусе сейчас никого.")
        exit(0)
    }

    var routes: [String: FlightRoute] = [:]
    if options.withRoutes {
        let routeService = RouteService()
        let callsigns = sorted.prefix(options.limit).compactMap { $0.callsign }
        routes = await routeService.cachedRoutes(for: callsigns)
        let missing = callsigns.filter { routes[$0.uppercased()] == nil }
        if !missing.isEmpty {
            let loaded = await routeService.loadMissing(missing, limit: 8, concurrency: 3)
            routes.merge(loaded) { _, new in new }
        }
        print("Справочник маршрутов: известно \(routes.count) из \(callsigns.count)")
        print("")
    }

    // Подставляем маршруты в сами борта: от этого зависит расчёт времени до посадки.
    let display = sorted.map { item -> Aircraft in
        guard options.withRoutes,
              let callsign = item.callsign?.uppercased(),
              let route = routes[callsign] else {
            return item
        }
        var copy = item
        copy.route = route
        return copy
    }

    print(pad("#", 3) + pad("дистанция", 11) + pad("азимут", 12) + pad("борт", 10)
        + pad("тип", 7) + pad("высота", 11) + pad("скорость", 11) + "вертикально")
    print(String(repeating: "─", count: 92))

    for (offset, aircraft) in display.prefix(options.limit).enumerated() {
        let vertical = aircraft.verticalText(format) ?? climbTitle(aircraft.climbState)
        var line = pad("\(offset + 1)", 3)
        line += pad(aircraft.distanceText(format), 11)
        line += pad(aircraft.bearingText(format), 12)
        line += pad(aircraft.displayName, 10)
        line += pad(aircraft.typeCode ?? "—", 7)
        line += pad(aircraft.altitudeText(format), 11)
        line += pad(aircraft.speedText(format) ?? "—", 11)
        line += vertical
        print(line)

        if options.withRoutes {
            var parts: [String] = []
            if let airline = aircraft.airlineName { parts.append(airline) }
            if let country = aircraft.route?.airlineCountryName(russian: true) {
                parts.append(country)
            } else if let code = aircraft.route?.airlineCountryCode {
                parts.append(code)
            }
            if let route = aircraft.route.map({ $0.title(russian: true) }) { parts.append(route) }
            if let hours = aircraft.hoursToDestination {
                parts.append("осталось ≈ " + format.duration(hours: hours))
            }
            print("     → " + (parts.isEmpty ? "маршрут неизвестен" : parts.joined(separator: " · ")))
        }
    }

    if sorted.count > options.limit {
        print("… и ещё \(sorted.count - options.limit)")
    }
} catch {
    print("Ошибка: \(error.localizedDescription)")
    exit(1)
}
