import Foundation

public struct Airport: Codable, Hashable, Sendable {
    public let iata: String?
    public let icao: String?
    public let name: String?
    public let municipality: String?
    public let country: String?
    public let countryISO: String?
    public let latitude: Double?
    public let longitude: Double?

    public init(
        iata: String?,
        icao: String?,
        name: String?,
        municipality: String?,
        country: String?,
        countryISO: String?,
        latitude: Double?,
        longitude: Double?
    ) {
        self.iata = iata
        self.icao = icao
        self.name = name
        self.municipality = municipality
        self.country = country
        self.countryISO = countryISO
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Название города. Берём из справочника Wikidata на нужном языке, а если
    /// аэропорта там нет — остаётся английское название из adsbdb.
    public func city(russian: Bool) -> String? {
        if let localized = AirportNames.city(iata: iata, russian: russian) {
            return localized
        }
        return municipality
    }

    /// «SVO Москва» — трёхбуквенный код плюс город.
    public func title(russian: Bool) -> String {
        let code = iata ?? icao ?? "???"
        guard let city = city(russian: russian), !city.isEmpty else { return code }
        return "\(code) \(city)"
    }
}

/// Маршрут рейса: откуда и куда.
public struct FlightRoute: Codable, Hashable, Sendable {
    public let callsign: String
    public let callsignIATA: String?
    public let airline: String?
    public let airlineICAO: String?
    public let airlineIATA: String?
    public let airlineCountryISO: String?
    public let airlineCountry: String?
    public let origin: Airport
    public let destination: Airport
    public let fetchedAt: Date

    public init(
        callsign: String,
        callsignIATA: String?,
        airline: String?,
        airlineICAO: String?,
        airlineIATA: String?,
        airlineCountryISO: String?,
        airlineCountry: String?,
        origin: Airport,
        destination: Airport,
        fetchedAt: Date
    ) {
        self.callsign = callsign
        self.callsignIATA = callsignIATA
        self.airline = airline
        self.airlineICAO = airlineICAO
        self.airlineIATA = airlineIATA
        self.airlineCountryISO = airlineCountryISO
        self.airlineCountry = airlineCountry
        self.origin = origin
        self.destination = destination
        self.fetchedAt = fetchedAt
    }

    /// «KGD Калининград → SVO Москва».
    public func title(russian: Bool) -> String {
        origin.title(russian: russian) + " → " + destination.title(russian: russian)
    }

    /// Двухбуквенный код страны авиакомпании.
    public var airlineCountryCode: String? {
        guard let code = airlineCountryISO?.uppercased(), code.count == 2 else { return nil }
        return code
    }

    /// Название страны авиакомпании на нужном языке.
    ///
    /// Берём из своего справочника по ISO-коду. Если кода нет, остаётся английское
    /// название из adsbdb: по-русски оно будет английским, но лучше, чем ничего.
    public func airlineCountryName(russian: Bool) -> String? {
        if let localized = CountryNames.name(iso: airlineCountryISO, russian: russian) {
            return localized
        }
        return airlineCountry
    }

    /// Короткое имя авиакомпании для строки списка.
    ///
    /// Убираем только то, что действительно является шумом: родовые «Airlines»,
    /// «System», «International» и юридические формы. «Airways» не трогаем — для
    /// British Airways и Kenya Airways это часть названия, а не суффикс.
    public var shortAirline: String? {
        guard let airline, !airline.isEmpty else { return nil }

        let suffixes = [" Airlines", " Air Lines", " Airways Inc", " System",
                        " International", " Company", " Co.", " Holding", " Holdings",
                        " Group", " AOC", " GmbH", " AG", " Inc.", " Inc", " Ltd",
                        " LLC", " PLC", " S.A.", " S.A", " OJSC", " PJSC"]
        var value = airline
        var didStrip = true
        while didStrip {
            didStrip = false
            for suffix in suffixes where value.hasSuffix(suffix) {
                value = String(value.dropLast(suffix.count))
                didStrip = true
            }
        }

        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? airline : trimmed
    }
}

/// Клиент справочника маршрутов adsbdb.
public struct RouteClient: Sendable {
    private static let userAgent = "HumUpThere/0.1 (macOS; personal use)"

    public init() {}

    /// `nil` означает, что для позывного маршрута в справочнике нет — это не ошибка.
    public func route(for callsign: String) async throws -> FlightRoute? {
        let trimmed = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty,
              let url = URL(string: "https://api.adsbdb.com/v0/callsign/\(trimmed)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else {
            throw ADSBError.http(http.statusCode, String(data: data.prefix(200), encoding: .utf8) ?? "")
        }
        return Self.parse(data)
    }

    private static func parse(_ data: Data) -> FlightRoute? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let payload = root["response"] as? [String: Any],
            let route = payload["flightroute"] as? [String: Any],
            let origin = airport(route["origin"]),
            let destination = airport(route["destination"])
        else {
            return nil
        }

        let airline = route["airline"] as? [String: Any]
        return FlightRoute(
            callsign: (route["callsign"] as? String) ?? "",
            callsignIATA: route["callsign_iata"] as? String,
            airline: airline?["name"] as? String,
            airlineICAO: airline?["icao"] as? String,
            airlineIATA: airline?["iata"] as? String,
            airlineCountryISO: airline?["country_iso"] as? String,
            airlineCountry: airline?["country"] as? String,
            origin: origin,
            destination: destination,
            fetchedAt: Date()
        )
    }

    private static func airport(_ value: Any?) -> Airport? {
        guard let dictionary = value as? [String: Any] else { return nil }
        let iata = (dictionary["iata_code"] as? String)?.uppercased()
        let icao = (dictionary["icao_code"] as? String)?.uppercased()
        // Совсем без кодов показывать нечего.
        guard iata != nil || icao != nil else { return nil }
        return Airport(
            iata: iata,
            icao: icao,
            name: dictionary["name"] as? String,
            municipality: dictionary["municipality"] as? String,
            country: dictionary["country_name"] as? String,
            countryISO: dictionary["country_iso_name"] as? String,
            latitude: dictionary["latitude"] as? Double,
            longitude: dictionary["longitude"] as? Double
        )
    }
}

/// Кэш маршрутов: маршруты рейсов стабильны, поэтому держим их на диске
/// и не спрашиваем справочник повторно. Неудачи тоже кэшируем, но ненадолго.
public actor RouteService {
    private struct Entry: Codable {
        let route: FlightRoute?
        let fetchedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var inFlight: Set<String> = []
    private var didLoad = false
    private let fileURL: URL?
    private let client = RouteClient()

    private let positiveTTL: TimeInterval = 30 * 24 * 3600
    private let negativeTTL: TimeInterval = 12 * 3600

    public init(fileURL: URL? = RouteService.defaultCacheURL()) {
        self.fileURL = fileURL
    }

    public static func defaultCacheURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("HumUpThere", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // v2: в записях появилась страна авиакомпании, старый кэш не подходит.
        return directory.appendingPathComponent("routes-v2.json")
    }

    /// Маршрут из кэша, если он ещё не устарел.
    public func cachedRoute(for callsign: String) -> FlightRoute? {
        loadIfNeeded()
        let key = callsign.uppercased()
        guard let entry = entries[key] else { return nil }
        let ttl = entry.route == nil ? negativeTTL : positiveTTL
        guard Date().timeIntervalSince(entry.fetchedAt) < ttl else { return nil }
        return entry.route
    }

    public func cachedRoutes(for callsigns: [String]) -> [String: FlightRoute] {
        loadIfNeeded()
        var result: [String: FlightRoute] = [:]
        for callsign in callsigns {
            let key = callsign.uppercased()
            if let route = cachedRoute(for: key) {
                result[key] = route
            }
        }
        return result
    }

    /// Догружает маршруты для тех позывных, которых нет в кэше.
    /// Возвращает только новые маршруты, чтобы вызывающий не переспрашивал кэш.
    public func loadMissing(
        _ callsigns: [String],
        limit: Int = 8,
        concurrency: Int = 3
    ) async -> [String: FlightRoute] {
        loadIfNeeded()

        let targets = callsigns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty && cachedRoute(for: $0) == nil && !inFlight.contains($0) }
        let batch = Array(targets.prefix(limit))
        guard !batch.isEmpty else { return [:] }

        inFlight.formUnion(batch)
        defer { inFlight.subtract(batch) }

        var resolved: [String: FlightRoute] = [:]
        for chunk in batch.chunked(into: max(1, concurrency)) {
            await withTaskGroup(of: (String, FlightRoute?).self) { group in
                for callsign in chunk {
                    group.addTask { [client] in
                        let route = try? await client.route(for: callsign)
                        return (callsign, route)
                    }
                }
                for await (callsign, route) in group {
                    entries[callsign] = Entry(route: route, fetchedAt: Date())
                    if let route {
                        resolved[callsign] = route
                    }
                }
            }
        }

        persist()
        return resolved
    }

    // MARK: - Диск

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        entries = decoded
    }

    private func persist() {
        guard let fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 1 else { return map { [$0] } }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
