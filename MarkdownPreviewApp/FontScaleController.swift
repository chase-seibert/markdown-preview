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

    private let step: CGFloat = 0.1

    private override init() {
        let stored = MarkdownFontScalePreference.storedValue(in: .standard)
            ?? MarkdownFontScalePreference.defaultScale
        scale = CGFloat(stored)
        super.init()
        MarkdownFontScalePreference.save(
            stored,
            inDomain: MarkdownFontScalePreference.sharedPreferenceDomain
        )
    }

    func setScale(_ value: CGFloat) {
        let newValue = Self.clamped(value)
        guard abs(newValue - scale) > 0.0001 else { return }
        scale = newValue
        MarkdownFontScalePreference.save(Double(newValue), in: .standard)
        MarkdownFontScalePreference.save(
            Double(newValue),
            inDomain: MarkdownFontScalePreference.sharedPreferenceDomain
        )
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
        CGFloat(MarkdownFontScalePreference.clamped(Double(value)))
    }
}
