import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case russian

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return L("System")
        // Endonyms, as is conventional for language pickers.
        case .english: return "English"
        case .russian: return "Русский"
        }
    }
}

/// The active UI language. Default follows the device; the user can force
/// English or Russian in Settings. Thread-safe because `L()` is called from
/// nonisolated contexts (enum label properties) as well as views.
final class LocalizationState: @unchecked Sendable {
    static let shared = LocalizationState()

    private let lock = NSLock()
    private var _language: AppLanguage = .system

    var language: AppLanguage {
        get { lock.withLock { _language } }
        set { lock.withLock { _language = newValue } }
    }

    /// Locale used for number formatting, kept consistent with the forced
    /// UI language (decimal comma in Russian).
    var locale: Locale {
        switch language {
        case .system: return .current
        case .english: return Locale(identifier: "en_US")
        case .russian: return Locale(identifier: "ru_RU")
        }
    }
}

/// The bundle that actually holds localized resources.
///
/// In an executable package target, localized resources live in a SwiftPM
/// resource bundle, not `Bundle.main`. The accessor SwiftPM generates for
/// `Bundle.module` only checks the .app ROOT (next to Contents/) and the
/// absolute build path baked in at compile time — neither exists for an
/// installed .app, and the latter makes a "working" app silently read
/// resources from the dev machine's .build tree. So: prefer the bundle that
/// scripts/bundle.sh copies into Contents/Resources, and fall back to
/// `Bundle.module` for the `swift run` / debugger workflow.
private let resourceBundle: Bundle = {
    if let url = Bundle.main.resourceURL?
        .appendingPathComponent("NetSpeedMenuBar_NetSpeedMenuBar.bundle"),
        let bundle = Bundle(url: url) {
        return bundle
    }
    return Bundle.module
}()

/// The Russian table, loaded directly so a forced language works regardless
/// of the system locale.
private let russianBundle: Bundle? = {
    resourceBundle.url(forResource: "ru", withExtension: "lproj")
        .flatMap(Bundle.init(url:))
}()

/// Looks up a localized string according to the selected app language.
func L(_ key: String) -> String {
    switch LocalizationState.shared.language {
    case .system:
        return resourceBundle.localizedString(forKey: key, value: key, table: nil)
    case .english:
        // English is the source language: values equal keys.
        return key
    case .russian:
        return russianBundle?.localizedString(forKey: key, value: key, table: nil) ?? key
    }
}
