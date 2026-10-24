import AppKit

/// Single source of truth for the app version. `scripts/build-app.sh` reads the
/// `string` line below with sed, so keep it on one line in this exact form.
enum AppVersion {
    static let string = "0.2.0"

    /// True for a Semantic Versioning 2.0.0 string: three numeric core components
    /// without leading zeros, optional dot-separated prerelease identifiers (numeric
    /// ones without leading zeros) and optional dot-separated build identifiers.
    static func isValidSemVer(_ text: String) -> Bool {
        guard text.allSatisfy({ $0.isASCII }) else { return false }
        var remainder = Substring(text)
        var build: Substring?
        if let plus = remainder.firstIndex(of: "+") {
            build = remainder[remainder.index(after: plus)...]
            remainder = remainder[..<plus]
        }
        var prerelease: Substring?
        if let hyphen = remainder.firstIndex(of: "-") {
            prerelease = remainder[remainder.index(after: hyphen)...]
            remainder = remainder[..<hyphen]
        }
        let core = remainder.split(separator: ".", omittingEmptySubsequences: false)
        guard core.count == 3, core.allSatisfy(isNumericIdentifier) else { return false }
        if let prerelease, !identifiers(prerelease).allSatisfy({ isNumericIdentifier($0) || isAlphanumericIdentifier($0) }) {
            return false
        }
        if let build, !identifiers(build).allSatisfy({ isAlphanumericIdentifier($0) || isDigits($0) }) {
            return false
        }
        return true
    }

    private static func identifiers(_ part: Substring) -> [Substring] {
        part.split(separator: ".", omittingEmptySubsequences: false)
    }
    private static func isDigits(_ part: Substring) -> Bool { !part.isEmpty && part.allSatisfy(\.isNumber) }
    private static func isNumericIdentifier(_ part: Substring) -> Bool {
        !part.isEmpty && part.allSatisfy(\.isNumber) && (part == "0" || part.first != "0")
    }
    private static func isAlphanumericIdentifier(_ part: Substring) -> Bool {
        !part.isEmpty && part.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) && part.contains(where: { !$0.isNumber })
    }

    /// Text for `Limitaur --version`, or nil when the arguments are not exactly that flag.
    static func commandLineResponse(_ arguments: [String]) -> String? {
        arguments.count == 2 && arguments[1] == "--version" ? string + "\n" : nil
    }

    /// Options for the standard About panel. The build number is included only when
    /// running from the Limitaur app bundle; the bare executable and test bundles omit it.
    static func aboutPanelOptions(bundle: Bundle = .main) -> [NSApplication.AboutPanelOptionKey: Any] {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Limitaur",
            .applicationVersion: string
        ]
        if bundle.bundleIdentifier == "local.limitaur.app",
           let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            options[.version] = build
        }
        return options
    }
}
