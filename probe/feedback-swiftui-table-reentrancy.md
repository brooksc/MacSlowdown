# Apple Feedback draft — SwiftUI `Table` performs a reentrant `NSTableView` delegate operation when rows are reordered

**Status: not filed.** Filing needs the product owner's Apple account, so this file
exists so that filing is a copy-paste. TASK-74 criterion #7 stays unchecked until the
Feedback number is recorded in the task.

Where to file: <https://feedbackassistant.apple.com> → macOS → SwiftUI. Attach a
sysdiagnose if Feedback Assistant asks for one; the reproduction below is small
enough that it should not be needed.

---

## Title

SwiftUI Table performs a reentrant NSTableView delegate operation when its rows are reordered

## Area

macOS → SwiftUI

## Type

Incorrect/Unexpected Behavior

## Description

A SwiftUI `Table` whose row array is **reordered** between updates causes AppKit to log:

> WARNING: Application performed a reentrant operation in its NSTableView delegate. This warning will become an assert in the future.

The application does nothing reentrant. The rows are `Identifiable` with stable,
unique identities; the row values and the row count are identical between updates;
only the order of the array differs. The warning is emitted from inside SwiftUI's own
`NSTableView` backing, via `NSLog` (it appears on stderr, not in `log show`).

This matters beyond the noise: AppKit's own message says the warning will become an
assert, which would turn a live, continuously re-ranked table — a completely ordinary
thing to build with `Table` — into a crash on some future macOS.

## Steps to reproduce

1. Build and run the attached sample (single file, SwiftUI, macOS).
2. Watch the process's standard error.

The sample holds a fixed array of 25 identical rows and, on a 1-second timer,
shuffles them. Nothing else changes: same ids, same values, same count.

## Expected result

No warning. Reordering rows in a `Table` is ordinary use of the API, and the
application performs no reentrant call of its own.

## Actual result

The warning is logged repeatedly — in our measurements roughly one per reordering
update.

## Notes from bisecting it (may save triage time)

Measured in an offscreen `NSWindow` hosting the real view, over 8–25 second windows,
counting occurrences of the warning on stderr:

| Variant | Warnings |
|---|---|
| Rows frozen, never changed | 0 |
| A new array each update, containing identical rows | 0 |
| Same identities, changing *values*, order fixed | 0 |
| Rows rotated by **one** position each update | 0 |
| Rows **shuffled** each update — identical ids *and* values | **21** |
| 25 rows re-sorted on changing values each update | **6** |

So it is specifically a bulk reorder. Row count is irrelevant: 15 rows reordering
warns as readily as 425.

Ruled out as causes, each by its own variant: the `sortOrder` binding; the selection
binding; sortable `TableColumn(value:)`; `DisclosureTableRow`; images in the cell
body; a `safeAreaInset` footer; `onChange` handlers; `.searchable`; `Section` in the
rows builder; the data-driven `Table(data)` initialiser;
`.transaction { $0.disablesAnimations = true }`; duplicate row identities (there are
none); and `Equatable` conformance on the row type.

## Configuration

- macOS 27 (also expected on 26; not yet re-measured there)
- Apple Silicon (M2)
- Xcode / Swift toolchain as shipped with the above
- App Sandbox enabled (irrelevant to the warning, but it is how we ship)

## Sample code (single file, no project settings required)

```swift
// TableReentrancy.swift
// swiftc TableReentrancy.swift -o TableReentrancy && ./TableReentrancy
//
// Shuffles a fixed array of rows in a SwiftUI Table once a second. Identities,
// values and count are identical between updates; only the order differs.
// AppKit logs "reentrant operation in its NSTableView delegate" on stderr.

import SwiftUI

struct Row: Identifiable, Equatable {
    let id: Int
    let name: String
    let value: Int
}

@Observable
final class Model {
    var rows: [Row] = (0..<25).map { Row(id: $0, name: "Row \($0)", value: $0 * 7) }

    func start() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [self] _ in
            // Only the order changes. Same ids, same values, same count.
            rows.shuffle()
        }
    }
}

struct ContentView: View {
    @State private var model = Model()
    @State private var selection: Row.ID?

    var body: some View {
        Table(model.rows, selection: $selection) {
            TableColumn("Name", value: \.name)
            TableColumn("Value") { Text("\($0.value)") }
        }
        .frame(minWidth: 400, minHeight: 500)
        .onAppear { model.start() }
    }
}

@main
struct ReentrancyApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

Run it and watch stderr:

```
./TableReentrancy 2>&1 | grep -c reentrant
```

## Our workaround, and why it is not a fix

We stopped re-ranking the list on every sample: the displayed order is held and
re-ranked at most once every 10 seconds, with rows that appear or disappear spliced
in and out immediately. That reduces the frequency of the warning because it reduces
the number of reorders — it does not remove the reentrancy, and a table that is
genuinely re-ranked still triggers it. The only complete workaround we can see is to
abandon `Table` for a hand-built `NSTableView` behind `NSViewRepresentable`.
