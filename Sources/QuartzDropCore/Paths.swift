import Foundation

/// Makes `path` absolute: expands a leading `~` or `~/` with `home`, joins a relative path to
/// `currentDirectory`, and removes `.` and `..` components. The result is computed lexically;
/// symlinks are not resolved.
public func absolutePath(_ path: String, currentDirectory: String, home: String) -> String {
    var expanded = path
    if expanded == "~" {
        expanded = home
    } else if expanded.hasPrefix("~/") {
        expanded = home + "/" + expanded.dropFirst(2)
    }
    let joined = expanded.hasPrefix("/") ? expanded : currentDirectory + "/" + expanded
    return URL(fileURLWithPath: joined).standardized.path
}
