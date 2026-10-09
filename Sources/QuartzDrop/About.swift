import AppKit

/// Build metadata and the standard About panel.
enum About {
    static let repository = URL(string: "https://github.com/SkeLLLa/quartz-drop")!

    /// The app bundle, also when started through a symlink (packslip and mise link
    /// `Contents/MacOS/quartz-drop` into a bin directory, and `Bundle.main` then looks next to
    /// the link instead of the real executable).
    static let bundle: Bundle = {
        guard Bundle.main.bundleIdentifier == nil,
            let executable = Bundle.main.executableURL?.resolvingSymlinksInPath()
        else { return Bundle.main }
        let contents = executable.deletingLastPathComponent().deletingLastPathComponent()
        return Bundle(url: contents.deletingLastPathComponent()) ?? Bundle.main
    }()

    /// Full commit SHA stamped into Info.plist by scripts/bundle.sh; nil for `swift run` builds.
    static var commit: String? { bundleValue("QDGitCommit") }

    /// UTC build timestamp stamped into Info.plist by scripts/bundle.sh.
    static var buildDate: String? { bundleValue("QDBuildDate") }

    static var shortCommit: String? {
        guard let commit else { return nil }
        let dirty = commit.hasSuffix("-dirty")
        let sha = String(commit.prefix(12))
        return dirty ? "\(sha)-dirty" : sha
    }

    /// "1.0.0 (abcdef123456)", or "1.0.0 (development build)" outside an app bundle.
    static var versionLine: String {
        "\(appVersion) (\(shortCommit ?? "development build"))"
    }

    @MainActor
    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "quartz-drop",
            .applicationVersion: appVersion,
            .version: shortCommit ?? "development build",
            .credits: credits(),
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"):
                "Copyright © SkeLLLa and contributors. Licensed under GPL-3.0-or-later.",
        ])
    }

    private static func bundleValue(_ key: String) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String,
            !value.isEmpty, !value.hasPrefix("__")
        else { return nil }
        return value
    }

    private static func credits() -> NSAttributedString {
        let text = NSMutableAttributedString()
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
        ]
        let heading: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
        ]
        func append(_ string: String, _ attributes: [NSAttributedString.Key: Any] = body) {
            text.append(NSAttributedString(string: string, attributes: attributes))
        }
        func link(_ title: String, _ url: URL) {
            var attributes = body
            attributes[.link] = url
            text.append(NSAttributedString(string: title, attributes: attributes))
        }

        append("Dropdown windows for any Mac app, on a hotkey. The macOS sibling of ")
        link("plasma-drop", URL(string: "https://github.com/SkeLLLa/plasma-drop")!)
        append(".\n\n")

        append("Build\n", heading)
        append("Version: \(appVersion)\n")
        if let commit {
            append("Commit: ")
            let sha = commit.replacingOccurrences(of: "-dirty", with: "")
            link(commit, repository.appendingPathComponent("commit/\(sha)"))
            append("\n")
        } else {
            append("Commit: development build\n")
        }
        if let buildDate { append("Built: \(buildDate)\n") }
        append("Source: ")
        link(repository.absoluteString, repository)
        append("\n\n")

        append("License\n", heading)
        append(
            "quartz-drop is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3 or (at your option) any later version. It comes with ABSOLUTELY NO WARRANTY. "
        )
        if let copying = bundle.url(forResource: "COPYING", withExtension: nil) {
            link("Full license text", copying)
        } else {
            link("Full license text", repository.appendingPathComponent("blob/master/COPYING"))
        }
        append(".\n\n")

        append("Third-party software\n", heading)
        for notice in ThirdPartyNotices.all {
            link(notice.name, notice.url)
            append(" (\(notice.license))\n\(notice.text)\n\n")
        }

        append("Support Ukraine\n", heading)
        append(SupportLinks.note + "\n")
        for (index, support) in SupportLinks.all.enumerated() {
            if index > 0 { append(" · ") }
            link(support.title, support.url)
        }
        return text
    }
}

/// Licenses of bundled dependencies (see Package.resolved). Keep in sync when adding one.
enum ThirdPartyNotices {
    struct Notice {
        let name: String
        let url: URL
        let license: String
        let text: String
    }

    static let all: [Notice] = [
        Notice(
            name: "TOMLDecoder",
            url: URL(string: "https://github.com/dduan/TOMLDecoder")!,
            license: "MIT",
            text: """
                Copyright (c) 2019 TOMLDecoder contributors

                Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

                The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

                THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
                """)
    ]
}
