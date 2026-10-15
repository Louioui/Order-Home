import Foundation

/// Shared filesystem helper connecting the main OrderHome app and the iMessage extension.
/// Uses the shared App Group container when available, with automatic one-time migration
/// and a transparent fallback for test runners or environments without App Group entitlements.
enum SharedKitchenContainer {
    /// Update this identifier if a different App Group ID is configured in Xcode.
    static let appGroupID = "group.com.partnershipwithmedia.orderhome"

    /// Primary location for `kitchen.json` accessible by both OrderHome and OrderHomeMessages.
    static var kitchenFileURL: URL {
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            let folder = groupURL.appendingPathComponent("OrderHome", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let sharedFile = folder.appendingPathComponent("kitchen.json")
            migrateLegacyStoreIfNeeded(to: sharedFile)
            return sharedFile
        }

        // Fallback for unit test runners without App Group entitlements
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let fallbackFolder = appSupport.appendingPathComponent("OrderHome", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallbackFolder, withIntermediateDirectories: true)
        return fallbackFolder.appendingPathComponent("kitchen.json")
    }

    /// Temporary handoff file URL written by iMessage when the Chef taps "Open Kitchen Ticket".
    static var pendingChatPollURL: URL {
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            let folder = groupURL.appendingPathComponent("OrderHome", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder.appendingPathComponent("pending_poll.json")
        }
        let tempFolder = FileManager.default.temporaryDirectory.appendingPathComponent("OrderHome", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
        return tempFolder.appendingPathComponent("pending_poll.json")
    }

    /// Writes a completed ChatPoll to the shared container for instantaneous handoff.
    static func writePendingChatPoll(_ poll: ChatPoll) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(poll) {
            try? data.write(to: pendingChatPollURL, options: .atomic)
        }
    }

    /// Reads and deletes the pending ChatPoll handoff if one exists.
    static func consumePendingChatPoll() -> ChatPoll? {
        let file = pendingChatPollURL
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(ChatPoll.self, from: data)
    }

    private static func migrateLegacyStoreIfNeeded(to sharedFile: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: sharedFile.path),
              let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let legacyFile = appSupport.appendingPathComponent("OrderHome/kitchen.json")
        if fm.fileExists(atPath: legacyFile.path) {
            try? fm.copyItem(at: legacyFile, to: sharedFile)
        }
    }
}
