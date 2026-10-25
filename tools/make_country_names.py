#!/usr/bin/env python3
import json, subprocess, urllib.parse, sys

query = """
SELECT ?iso ?ru ?en WHERE {
  ?item wdt:P297 ?iso .
  ?item rdfs:label ?ru . FILTER(lang(?ru) = "ru")
  ?item rdfs:label ?en . FILTER(lang(?en) = "en")
}
"""
url = "https://query.wikidata.org/sparql?" + urllib.parse.urlencode({"query": query})
out = subprocess.run([
    "curl", "-s", "--max-time", "150", url,
    "-H", "Accept: application/sparql-results+json",
    "-H", "User-Agent: HumUpThere/0.1 (macOS)"
], capture_output=True, text=True).stdout
rows = json.loads(out)["results"]["bindings"]

# На один код бывает несколько сущностей (например, страна и королевство).
# Берём самое короткое русское название — оно обычно и есть обиходное.
best = {}
for row in rows:
    iso = row["iso"]["value"].upper()
    ru, en = row["ru"]["value"].strip(), row["en"]["value"].strip()
    if len(iso) != 2 or not iso.isalpha() or not ru:
        continue
    if iso not in best or len(ru) < len(best[iso][0]):
        best[iso] = (ru, en)

# Обиходные короткие формы: официальные названия в строке списка не помещаются.
overrides = {
    "CN": ("Китай", "China"),
    "TW": ("Тайвань", "Taiwan"),
    "US": ("США", "United States"),
    "AE": ("ОАЭ", "UAE"),
    "GB": ("Великобритания", "United Kingdom"),
    "KR": ("Южная Корея", "South Korea"),
    "KP": ("КНДР", "North Korea"),
    "NL": ("Нидерланды", "Netherlands"),
    "CZ": ("Чехия", "Czechia"),
    "CD": ("Конго", "DR Congo"),
    "CG": ("Конго", "Congo"),
    "LA": ("Лаос", "Laos"),
    "SY": ("Сирия", "Syria"),
    "VN": ("Вьетнам", "Vietnam"),
    "MD": ("Молдова", "Moldova"),
    "MK": ("Северная Македония", "North Macedonia"),
}
for iso, (ru, en) in overrides.items():
    best.setdefault(iso, (ru, en))
    best[iso] = (ru, en)

print(f"стран в справочнике: {len(best)}", file=sys.stderr)

def clean(value):
    return value.replace("\\", "").replace("\n", " ").replace('"', "").strip()

ru_lines = [f"{iso}={clean(best[iso][0])}" for iso in sorted(best) if clean(best[iso][0])]
en_lines = [f"{iso}={clean(best[iso][1])}" for iso in sorted(best) if clean(best[iso][1])]

header = '''import Foundation

/// Названия стран из кода ISO 3166-1: «GB» → «Великобритания» / «United Kingdom».
///
/// Сгенерировано из Wikidata (свойство P297). Если у кода несколько сущностей
/// (страна и, например, королевство), берётся самое короткое название — обиходное.
/// Для длинных официальных названий добавлены короткие формы: США, ОАЭ, Нидерланды.
enum CountryNames {
    static let ru: [String: String] = parse(rawRu)
    static let en: [String: String] = parse(rawEn)

    static func name(iso: String?, russian: Bool) -> String? {
        guard let code = iso?.uppercased() else { return nil }
        let table = russian ? ru : en
        guard let value = table[code], !value.isEmpty else { return nil }
        return value
    }

    private static func parse(_ raw: String) -> [String: String] {
        var map: [String: String] = [:]
        map.reserveCapacity(256)
        for line in raw.split(separator: "\\n") {
            guard let separator = line.firstIndex(of: "=") else { continue }
            map[String(line[line.startIndex..<separator])] = String(line[line.index(after: separator)...])
        }
        return map
    }

    private static let rawRu = """
'''

middle = '''
"""

    private static let rawEn = """
'''

footer = '''
"""
}
'''

with open("Sources/HumUpThereCore/CountryNames.swift", "w", encoding="utf-8") as handle:
    handle.write(header)
    handle.write("\n".join(ru_lines))
    handle.write(middle)
    handle.write("\n".join(en_lines))
    handle.write(footer)
print("файл записан", file=sys.stderr)
