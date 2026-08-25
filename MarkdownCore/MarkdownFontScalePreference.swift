import Foundation

public enum MarkdownFontScalePreference {
    public static let sharedPreferenceDomain = "com.cseibert.MarkdownPreview.shared"
    public static let defaultsKey = "MarkdownContentFontScale"
    public static let minimumScale = 0.65
    public static let maximumScale = 2.5
    public static let defaultScale = 1.0

    public static func storedValue(in defaults: UserDefaults?) -> Double? {
        guard let stored = defaults?.object(forKey: defaultsKey) as? NSNumber else {
            return nil
        }
        return clamped(stored.doubleValue)
    }

    public static func storedValue(inDomain domain: String) -> Double? {
        guard let stored = CFPreferencesCopyAppValue(
            defaultsKey as CFString,
            domain as CFString
        ) as? NSNumber else {
            return nil
        }
        return clamped(stored.doubleValue)
    }

    public static func save(_ value: Double, in defaults: UserDefaults?) {
        defaults?.set(clamped(value), forKey: defaultsKey)
    }

    @discardableResult
    public static func save(_ value: Double, inDomain domain: String) -> Bool {
        CFPreferencesSetAppValue(
            defaultsKey as CFString,
            NSNumber(value: clamped(value)),
            domain as CFString
        )
        return CFPreferencesAppSynchronize(domain as CFString)
    }

    public static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return defaultScale }
        return min(max(value, minimumScale), maximumScale)
    }
}

public enum MarkdownReadingLayout {
    public static let baseMaximumTextContainerWidth = 900.0

    public static func maximumTextContainerWidth(fontScale: Double) -> Double {
        baseMaximumTextContainerWidth * MarkdownFontScalePreference.clamped(fontScale)
    }
}
