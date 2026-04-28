import Foundation

struct WorkspaceBookmark: Codable, Identifiable, Hashable {
    var id: UUID
    var path: String
    var displayName: String?
    var lastAccessedAt: Date

    var label: String {
        displayName ?? (path as NSString).lastPathComponent
    }

    init(id: UUID = UUID(), path: String, displayName: String? = nil, lastAccessedAt: Date = Date()) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.lastAccessedAt = lastAccessedAt
    }
}

final class WorkspaceBookmarkStore {
    private let storageURL: URL

    init() {
        let fileManager = FileManager.default
        let baseDirectory: URL
        if let appGroupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.morningstar.MacTortoiseSVN"
        ) {
            baseDirectory = appGroupURL
        } else {
            baseDirectory = fileManager.homeDirectoryForCurrentUser
                .appending(path: "Library")
                .appending(path: "Application Support")
        }
        storageURL = baseDirectory
            .appending(path: "MacTortoiseSVN")
            .appending(path: "workspace-bookmarks.json")
    }

    func load() -> [WorkspaceBookmark] {
        guard
            let data = try? Data(contentsOf: storageURL),
            let bookmarks = try? JSONDecoder().decode([WorkspaceBookmark].self, from: data)
        else {
            return []
        }
        return bookmarks
    }

    func save(_ bookmarks: [WorkspaceBookmark]) {
        let directoryURL = storageURL.deletingLastPathComponent()
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(bookmarks)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            return
        }
    }
}
