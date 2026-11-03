import Foundation

/// UI strings live in Resources/{id,en}.lproj/Localizable.strings and are copied into the app bundle.
/// (String Catalogs need `xcstringstool`, which only ships with Xcode; .strings files work with SwiftPM + CLT.)
enum L10n {
    /// Bundle with the .lproj folders: the app bundle, or the source tree when run with `swift run`.
    static let bundle: Bundle = {
        if Bundle.main.path(forResource: "Localizable", ofType: "strings") != nil { return .main }
        let src = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources")
        return Bundle(path: src.path) ?? .main
    }()

    /// Language actually used for the UI ("id" or "en").
    static var language: String {
        if let forced = forcedLanguage { return forced }
        return Bundle.preferredLocalizations(from: ["id", "en"]).first ?? "en"
    }

    /// Set by `--snapshot --lang` so screenshots can be rendered in either language.
    nonisolated(unsafe) static var forcedLanguage: String?

    private static var languageBundle: Bundle {
        bundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? bundle
    }

    static var locale: Locale { Locale(identifier: language == "id" ? "id_ID" : "en_US") }

    static func string(_ key: String) -> String {
        languageBundle.localizedString(forKey: key, value: key, table: nil)
    }
}

/// `L("agent.editing", file)` → "Claude mengedit AuthService.swift".
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = L10n.string(key)
    return args.isEmpty ? format : String(format: format, locale: L10n.locale, arguments: args)
}
