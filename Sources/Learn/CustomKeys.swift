import Foundation

/// Read-only view of App Shortcuts made in System Settings (NSUserKeyEquivalents), used to notice edits there.
/// Never touches ~/Library/Containers: reading another app's container makes macOS ask "Learn would like to access
/// data from other apps" again and again. Sandboxed apps' custom keys are still picked up by menu rescans.
enum CustomKeys {
    private static let key = "NSUserKeyEquivalents"

    static func read(_ bundleID: String) -> [String: String] {
        CFPreferencesAppSynchronize(bundleID as CFString)
        return CFPreferencesCopyAppValue(key as CFString, bundleID as CFString) as? [String: String] ?? [:]
    }

    static func signature(for bundleID: String) -> String {
        func flat(_ d: [String: String]) -> String { d.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ";") }
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let global = CFPreferencesCopyAppValue(key as CFString, kCFPreferencesAnyApplication) as? [String: String] ?? [:]
        return flat(read(bundleID)) + "|" + flat(global)
    }
}
