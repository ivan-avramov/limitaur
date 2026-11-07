import AppKit
import Foundation
import Testing
@testable import Limitaur

private let revision = "0123456789abcdef0123456789abcdef01234567-dirty"
private let buildDate = "2026-11-07T16:23:45Z"
private let repository = "https://github.com/ivan-avramov/limitaur"

@Test(arguments: ["packaged", "missing", "empty", "other"])
func aboutInformationReflectsBundleMetadata(scenario: String) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let app = root.appendingPathComponent("Fixture.app")
    let resources = app.appendingPathComponent("Contents/Resources")
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    let license = resources.appendingPathComponent("LICENSE")
    var info = ["CFBundleIdentifier": scenario == "other" ? "example.other.app" : "local.limitaur.app",
                "CFBundleVersion": "42", "CFBundlePackageType": "APPL"]
    if scenario != "missing" {
        info["LimitaurSourceRevision"] = scenario == "empty" ? "" : revision
        info["LimitaurBuildDate"] = scenario == "empty" ? "" : buildDate
    }
    if scenario == "packaged" {
        try Data("MIT License".utf8).write(to: license)
    }
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: app.appendingPathComponent("Contents/Info.plist"))
    let options = AppVersion.aboutPanelOptions(bundle: try #require(Bundle(url: app)))
    #expect(options[.applicationVersion] as? String == AppVersion.string)
    #expect(options[NSApplication.AboutPanelOptionKey(rawValue: "Copyright")] as? String == "© 2026 Ivan Avramov")
    let credits = try #require(options[.credits] as? NSAttributedString)
    var links: [URL] = []
    credits.enumerateAttribute(.link, in: NSRange(location: 0, length: credits.length)) { value, _, _ in
        if let url = value as? URL { links.append(url) }
        else if let string = value as? String, let url = URL(string: string) { links.append(url) }
    }
    #expect(links.contains { $0.absoluteString == repository })
    #expect(credits.string.contains(repository))
    #expect(credits.string.contains("MIT"))
    if scenario == "packaged" {
        #expect(options[.version] as? String == "42")
        #expect(credits.string.contains(revision))
        #expect(credits.string.contains(buildDate))
        #expect(links.contains { $0.isFileURL && $0.standardizedFileURL.path == license.standardizedFileURL.path })
    } else {
        #expect(!credits.string.contains(revision) && !credits.string.contains(buildDate))
        #expect(credits.string.components(separatedBy: "Unavailable").count == 3)
        #expect(links.contains { $0.absoluteString.hasPrefix(repository + "/") && $0.lastPathComponent == "LICENSE" })
    }
}
