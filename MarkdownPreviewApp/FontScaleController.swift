import AppKit
import Combine
import Foundation

extension Notification.Name {
    static let markdownFontScaleDidChange = Notification.Name("MarkdownFontScaleDidChange")
}

@MainActor
final class FontScaleController: NSObject, ObservableObject {
    static let shared = FontScaleController()

    @Published private(set) var scale: CGFloat

    private let defaultsKey = "MarkdownContentFontScale"
    private let step: CGFloat = 0.1

    private override init() {
        let stored = UserDefaults.standard.object(forKey: defaultsKey) as? NSNumber
        scale = Self.clamped(stored.map(CGFloat.init(truncating:)) ?? MarkdownRenderOptions.defaultScale)
        super.init()
    }

    func setScale(_ value: CGFloat) {
        let newValue = Self.clamped(value)
        guard abs(newValue - scale) > 0.0001 else { return }
        scale = newValue
        UserDefaults.standard.set(Double(newValue), forKey: defaultsKey)
        NotificationCenter.default.post(name: .markdownFontScaleDidChange, object: self)
    }

    @objc func increaseFontSize(_ sender: Any?) {
        setScale((scale * 10).rounded() / 10 + step)
    }

    @objc func decreaseFontSize(_ sender: Any?) {
        setScale((scale * 10).rounded() / 10 - step)
    }

    @objc func resetFontSize(_ sender: Any?) {
        setScale(MarkdownRenderOptions.defaultScale)
    }

    var percentageLabel: String {
        "\(Int((scale * 100).rounded()))%"
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return MarkdownRenderOptions.defaultScale }
        return min(max(value, MarkdownRenderOptions.minimumScale), MarkdownRenderOptions.maximumScale)
    }
}

