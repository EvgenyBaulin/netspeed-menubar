import Foundation

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

/// Looks up a localized string in the resource bundle.
func L(_ key: String) -> String {
    resourceBundle.localizedString(forKey: key, value: key, table: nil)
}
