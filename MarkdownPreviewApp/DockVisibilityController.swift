import AppKit
import Combine
import Foundation

@MainActor
final class DockVisibilityController: ObservableObject {
    static let shared = DockVisibilityController()

    @Published private(set) var showsDockItem: Bool

    private let defaultsKey = "ShowDockItem"

    private init() {
        let stored = UserDefaults.standard.object(forKey: defaultsKey) as? NSNumber
        showsDockItem = stored?.boolValue ?? true
    }

    func apply() {
        NSApp.setActivationPolicy(showsDockItem ? .regular : .accessory)
    }

    func setShowsDockItem(_ showsDockItem: Bool) {
        guard showsDockItem != self.showsDockItem else { return }
        self.showsDockItem = showsDockItem
        UserDefaults.standard.set(showsDockItem, forKey: defaultsKey)
        apply()
    }
}
