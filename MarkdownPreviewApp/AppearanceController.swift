import AppKit
import Combine
import Foundation

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    fileprivate var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class AppearanceController: ObservableObject {
    static let shared = AppearanceController()

    @Published private(set) var selection: AppAppearance

    private let defaultsKey = "ApplicationAppearance"

    private init() {
        let stored = UserDefaults.standard.string(forKey: defaultsKey)
        selection = stored.flatMap(AppAppearance.init(rawValue:)) ?? .system
    }

    func apply() {
        NSApp.appearance = selection.appearance
    }

    func setAppearance(_ appearance: AppAppearance) {
        guard appearance != selection else { return }
        selection = appearance
        UserDefaults.standard.set(appearance.rawValue, forKey: defaultsKey)
        apply()
    }
}
