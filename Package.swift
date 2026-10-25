// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HumUpThere",
    platforms: [
        // macOS 15 нужен для Scene.defaultLaunchBehavior — без него окно настроек
        // открывалось бы при каждом запуске menu bar приложения.
        // Версия задана строкой: tools-version 5.9 не знает константы .v15.
        .macOS("15.0")
    ],
    products: [
        .executable(name: "HumUpThere", targets: ["HumUpThere"]),
        .executable(name: "humupthere-cli", targets: ["humupthere-cli"]),
        .library(name: "HumUpThereCore", targets: ["HumUpThereCore"]),
    ],
    targets: [
        // Логика: модели, геометрия, клиент открытых ADS-B источников.
        .target(
            name: "HumUpThereCore",
            path: "Sources/HumUpThereCore"
        ),
        // Menu bar приложение.
        .executableTarget(
            name: "HumUpThere",
            dependencies: ["HumUpThereCore"],
            path: "Sources/HumUpThere"
        ),
        // Утилита для проверки данных из терминала.
        .executableTarget(
            name: "humupthere-cli",
            dependencies: ["HumUpThereCore"],
            path: "Sources/humupthere-cli"
        ),
    ]
)
