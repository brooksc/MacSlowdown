import Foundation

/// Everything MacSlowdown has written to disk, and how much of it there is.
///
/// FR-029 asks the privacy surface to show retention *and* what it costs. A
/// retention period with no visible size is a promise with no consequence, so the
/// figure here is measured from the container rather than estimated — if the
/// directory cannot be read the answer is "unknown", never a guess (FR-002).
enum StoredData {
    /// The app's own Application Support directory. Under the sandbox this
    /// resolves inside our container, which is the only place we write.
    static var directory: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false)
        else { return nil }
        return base.appendingPathComponent("MacSlowdown", isDirectory: true)
    }

    /// User rules live in `policies.json`, written by `MonitorStore.policies`.
    /// Kept apart from recorded evidence so "delete all history" cannot quietly
    /// delete the user's own decisions.
    static let rulesFileName = "policies.json"

    /// Files holding recorded evidence, as opposed to configuration.
    ///
    /// The directory is a parameter so a test can point this at a scratch folder.
    /// Without that, a test exercising deletion would delete the running user's
    /// real history, which is not a cost a test may impose.
    static func recordedEvidenceFiles(in directory: URL? = StoredData.directory) -> [URL] {
        guard let directory else { return [] }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.lastPathComponent != rulesFileName }
    }

    /// Bytes on disk, or nil when the directory does not exist or cannot be read.
    static func bytesOnDisk() -> UInt64? {
        guard let directory,
              FileManager.default.fileExists(atPath: directory.path)
        else { return nil }
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.fileAllocatedSizeKey])
        else { return nil }
        var total: UInt64 = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileAllocatedSizeKey]))?
                .fileAllocatedSize ?? 0
            total += UInt64(size)
        }
        return total
    }

    /// What the privacy tab prints beside the retention period.
    ///
    /// Nothing on disk is stated as nothing on disk — a zero here is the truth
    /// rather than a failure to look. Before the first incident closes there is
    /// genuinely nothing recorded, even though history now persists.
    static func usageDescription() -> String {
        guard let bytes = bytesOnDisk() else {
            return "Currently using: unknown — the storage folder could not be read"
        }
        if bytes == 0 {
            return "Currently using no disk space"
        }
        return "Currently using \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))"
    }

    /// Deletes recorded evidence. Returns how many files and how many bytes were
    /// removed, so the interface can report what happened rather than assume it
    /// (FR-050's rule: a call returning without error is not an outcome).
    ///
    /// Sizes are read before the removal, because a deleted file has no size to
    /// ask for afterwards.
    @discardableResult
    static func deleteRecordedEvidence(
        in directory: URL? = StoredData.directory
    ) -> (files: Int, bytes: UInt64) {
        var removed = 0
        var bytes: UInt64 = 0
        for url in recordedEvidenceFiles(in: directory) {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard (try? FileManager.default.removeItem(at: url)) != nil else { continue }
            removed += 1
            bytes += UInt64(size)
        }
        return (removed, bytes)
    }

    /// The container statement the privacy surface prints.
    ///
    /// Deliberately **not** "encrypted". FileVault is the user's setting and not
    /// ours, and `NSFileProtection` on macOS is not the guarantee the word implies.
    /// What is true and checkable is that the App Sandbox container is not readable
    /// by other apps, so that is what we say.
    static let containerStatement =
        "in MacSlowdown's own container, which no other app can read"
}
