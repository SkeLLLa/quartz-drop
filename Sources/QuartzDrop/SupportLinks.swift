import Foundation

/// Funds suggested instead of donating to the author; the same list as the README.
enum SupportLinks {
    struct Link: Identifiable {
        var id: String { title }
        let title: String
        let url: URL
    }

    static let note =
        "If quartz-drop is useful to you, please consider supporting Ukrainian defenders instead of sending money to the author."

    static let all: [Link] = [
        Link(title: "Come Back Alive", url: URL(string: "https://savelife.in.ua/en/donate-en/")!),
        Link(title: "Sternenko Fund", url: URL(string: "https://www.sternenkofund.org/en/donate")!),
        Link(
            title: "Prytula Foundation",
            url: URL(string: "https://prytulafoundation.org/en/donation")!),
    ]
}
