import Foundation

enum AppBundledReleaseNotes {
    static func sections(bundle: Bundle = .main) -> [AppReleaseNotesSection] {
        guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let url = bundle.url(forResource: "ReleaseNotes-\(version)", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        return AppReleaseNotesParser.sections(from: text, maxPlainNotes: .max, maxNotesPerVersion: .max)
    }
}
