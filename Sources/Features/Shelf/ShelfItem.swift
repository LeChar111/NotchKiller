import AppKit
import UniformTypeIdentifiers

enum ShelfItemKind: Codable, Equatable {
    case file(path: String)
    case text(string: String)
    case link(url: URL)

    enum CodingKeys: String, CodingKey { case type, value }
    enum KindTag: String, Codable { case file, text, link }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try container.decode(KindTag.self, forKey: .type)
        switch tag {
        case .file: self = .file(path: try container.decode(String.self, forKey: .value))
        case .text: self = .text(string: try container.decode(String.self, forKey: .value))
        case .link: self = .link(url: try container.decode(URL.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .file(let path):
            try container.encode(KindTag.file, forKey: .type)
            try container.encode(path, forKey: .value)
        case .text(let string):
            try container.encode(KindTag.text, forKey: .type)
            try container.encode(string, forKey: .value)
        case .link(let url):
            try container.encode(KindTag.link, forKey: .type)
            try container.encode(url, forKey: .value)
        }
    }
}

struct ShelfItem: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ShelfItemKind

    init(id: UUID = UUID(), kind: ShelfItemKind) {
        self.id = id
        self.kind = kind
    }

    var displayName: String {
        switch kind {
        case .file(let path):
            return URL(fileURLWithPath: path).lastPathComponent
        case .text(let string):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count > 40 ? String(trimmed.prefix(37)) + "..." : trimmed
        case .link(let url):
            return url.host ?? url.absoluteString
        }
    }

    var icon: NSImage {
        switch kind {
        case .file(let path):
            return NSWorkspace.shared.icon(forFile: path)
        case .text:
            return NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil) ?? NSImage()
        case .link:
            return NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage()
        }
    }

    func open() {
        switch kind {
        case .file(let path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .text(let string):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        case .link(let url):
            NSWorkspace.shared.open(url)
        }
    }

    func revealInFinder() {
        if case .file(let path) = kind {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        }
    }
}
