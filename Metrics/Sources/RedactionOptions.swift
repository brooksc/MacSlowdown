import Foundation

/// What may be stripped from an export before it leaves the machine (FR-028).
///
/// These choices are applied when an `ExportDocument` is **built**, never when one
/// is rendered, so a hidden value is absent from the document itself. There is
/// exactly one builder (`IncidentReport.document`) and every path that produces a
/// report goes through it — the interactive sheet and the App Intent alike. A
/// second builder would be a way for two reports of the same incident to disagree
/// about what is private, which is precisely what FR-028 exists to prevent.
public struct RedactionOptions: Sendable, Equatable {
    public var hideUserName: Bool
    public var hideFilePaths: Bool
    public var hideProcessNames: Bool

    public init(hideUserName: Bool = true, hideFilePaths: Bool = true,
                hideProcessNames: Bool = false) {
        self.hideUserName = hideUserName
        self.hideFilePaths = hideFilePaths
        self.hideProcessNames = hideProcessNames
    }

    /// Defaults redact the two fields that identify a person without costing much
    /// interpretability. Process names are left in because removing them makes a
    /// report nearly useless, and the interface says so rather than letting a user
    /// discover it after sending.
    ///
    /// This is also the floor for any unattended path: a report produced without a
    /// person watching is never quietly less redacted than this.
    public static let `default` = RedactionOptions()

    public var redactedFieldCount: Int {
        [hideUserName, hideFilePaths, hideProcessNames].count { $0 }
    }

    /// Warning shown when a choice materially damages the report's usefulness.
    public var costWarning: String? {
        hideProcessNames
            ? "Hiding process names makes the report much harder for anyone to interpret."
            : nil
    }

    // MARK: - Stating the choices

    /// Named in the same words the export sheet uses, so a shortcut's description
    /// and the sheet's checkboxes cannot be read as different controls.
    /// Each redactable field, paired with whether these choices hide it. One list,
    /// so no caller can enumerate the fields in its own order or its own words.
    var fields: [(name: String, isHidden: Bool)] {
        [("your user name", hideUserName),
         ("file paths", hideFilePaths),
         ("app and process names", hideProcessNames)]
    }

    public var hiddenFieldNames: [String] {
        fields.filter(\.isHidden).map(\.name)
    }

    public var includedFieldNames: [String] {
        fields.filter { !$0.isHidden }.map(\.name)
    }

    /// The fields `other` hides that these choices do not — the exact respects in
    /// which this report is less redacted than `other` would have made it.
    public func fieldsLeftInComparedTo(_ other: RedactionOptions) -> [String] {
        zip(fields, other.fields)
            .filter { mine, theirs in theirs.isHidden && !mine.isHidden }
            .map(\.0.name)
    }

    /// Whether these choices hide everything `other` hides.
    public func isAtLeastAsRedacted(as other: RedactionOptions) -> Bool {
        fieldsLeftInComparedTo(other).isEmpty
    }

    /// One sentence naming what is hidden and what is not, for a caller that has to
    /// state its redaction rather than show it — an App Intent running unattended,
    /// where nobody is looking at a preview (FR-028).
    public var disclosure: String {
        let hidden = hiddenFieldNames
        let included = includedFieldNames
        let hiddenPart = hidden.isEmpty
            ? "Nothing was hidden"
            : "Hidden: " + Self.list(hidden)
        let includedPart = included.isEmpty
            ? "nothing sensitive was included"
            : "included: " + Self.list(included)
        return "\(hiddenPart); \(includedPart)."
    }

    /// Said plainly when a caller chose to hide less than `RedactionOptions.default`
    /// would have. Never silent: an unattended report that is less redacted than the
    /// interactive one has to say so in the same breath as it hands over the text.
    public var weakerThanDefaultWarning: String? {
        let leftIn = fieldsLeftInComparedTo(.default)
        guard !leftIn.isEmpty else { return nil }
        return "This report is less redacted than MacSlowdown's default, which also hides "
            + Self.list(leftIn) + "."
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }
}
