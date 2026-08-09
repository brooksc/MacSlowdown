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
    static func recordedEvidenceFiles() -> [URL] {
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
    /// Nothing on disk is stated as nothing on disk. History is currently held in
    /// memory only (`MetricsHistory` defaults to `.memoryOnly`), so a zero here is
    /// the truth rather than a failure to look.
    static func usageDescription() -> String {
        guard let bytes = bytesOnDisk() else {
            return "Currently using: unknown — the storage folder could not be read"
        }
        if bytes == 0 {
            return "Currently using no disk space"
        }
        return "Currently using \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))"
    }

    /// Deletes recorded evidence. Returns how many files were removed, so the
    /// interface can report what happened rather than assume it (FR-050's rule:
    /// a call returning without error is not an outcome).
    @discardableResult
    static func deleteRecordedEvidence() -> Int {
        var removed = 0
        for url in recordedEvidenceFiles() where (try? FileManager.default.removeItem(at: url)) != nil {
            removed += 1
        }
        return removed
    }
}
