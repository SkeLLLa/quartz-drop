/// Directories searched for a bare `command[0]`: the `PATH` entries, then the common install
/// locations a Finder-launched app does not inherit in its `PATH`. Duplicates are dropped, order
/// is kept.
public func executableSearchDirectories(path: String?, home: String) -> [String] {
    let fromPath = (path ?? "").split(separator: ":", omittingEmptySubsequences: true).map(
        String.init)
    let candidates = fromPath + ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin"]
    var seen = Set<String>()
    return candidates.filter { seen.insert($0).inserted }
}

/// Resolves a command name the way a shell would. A name containing `/` is returned as is (with a
/// leading `~` expanded against `home`); a bare name is looked up in
/// `executableSearchDirectories(path:home:)`.
public func resolveExecutable(
    _ name: String, path: String?, home: String, isExecutable: (String) -> Bool
) -> String? {
    if name.contains("/") {
        if name == "~" || name.hasPrefix("~/") {
            return home + name.dropFirst()
        }
        return name
    }
    for directory in executableSearchDirectories(path: path, home: home) {
        let candidate = directory + "/" + name
        if isExecutable(candidate) {
            return candidate
        }
    }
    return nil
}
