import Foundation
import HumUpThereCore

/// Единое текстовое представление борта.
///
/// Строка списка и карточка оповещения должны описывать один и тот же борт одинаково,
/// поэтому всё форматирование живёт здесь, а не в двух видах по отдельности.
struct AircraftText {
    let text: T
    let format: DisplayFormat
    var countryStyle: CountryStyle = .name

    /// «Lufthansa · Германия · 9 449 м · С 9° · 870 км/ч»
    ///
    /// Авиакомпания идёт первой: вместе со страной она отвечает на вопрос «кто это летит».
    func details(_ aircraft: Aircraft) -> String {
        var parts: [String] = []
        if let airline = aircraft.airlineName {
            parts.append(airline)
        }
        if countryStyle == .name,
           let country = aircraft.route?.airlineCountryName(russian: text.isRussian) {
            parts.append(country)
        }
        parts.append(aircraft.altitudeText(format))
        parts.append(aircraft.bearingText(format))
        if let speed = aircraft.speedText(format) {
            parts.append(speed)
        }
        return parts.joined(separator: " · ")
    }

    /// Маршрут вместе с оценкой времени до посадки:
    /// «FRA Франкфурт-на-Майне → BER Берлин · осталось ≈ 29 мин»
    func routeLine(_ aircraft: Aircraft, route: String) -> String {
        guard let hours = aircraft.hoursToDestination else { return route }
        return route + " · " + text(.remaining, format.duration(hours: hours))
    }

    /// Подробности для всплывающей подсказки: полное название авиакомпании с кодами,
    /// страна и код рейса IATA.
    func routeHelp(_ aircraft: Aircraft, route: String) -> String {
        var lines = [route]
        if let airline = aircraft.route?.airline {
            var airlineLine = "\(text(.airlineLabel)): \(airline)"
            let codes = [aircraft.route?.airlineIATA, aircraft.route?.airlineICAO].compactMap { $0 }
            if !codes.isEmpty {
                airlineLine += " (\(codes.joined(separator: "/")))"
            }
            lines.append(airlineLine)
        }
        // Полное название страны живёт здесь: в строке списка ему не хватает места.
        if let country = aircraft.route?.airlineCountryName(russian: text.isRussian) {
            lines.append("\(text(.countryLabel)): \(country)")
        }
        if let iata = aircraft.route?.callsignIATA, iata != aircraft.displayName {
            lines.append(iata)
        }
        return lines.joined(separator: "\n")
    }
}
