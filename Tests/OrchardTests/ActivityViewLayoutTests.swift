import AppKit
import SwiftUI
import Testing
@testable import Orchard

@MainActor
struct ActivityViewLayoutTests {
    /// Expanding a deploy's commits used to grow its List row in place; the row kept its old
    /// height and SwiftUI centered the taller content in it, clipping the deploy's header.
    @Test func expandingChangesAddsRowsWithoutResizingTheDeployRow() throws {
        let store = makeTestStore()
        let runner = store.pipelines[0]
        let iPhone = Device(id: "iphone", name: "iPhone", model: "iPhone", kind: .physical,
                            platform: .iOS, osVersion: "26.0")
        runner.config.devices = [iPhone]
        var run = RunRecord(commit: String(repeating: "c", count: 40), subject: "Latest",
                            baseCommit: String(repeating: "a", count: 40))
        run.changes = (0..<20).map {
            CommitSummary(sha: String(format: "%040x", $0), author: "Someone",
                          subject: "A subject long enough to be truncated in the activity column, number \($0)")
        }
        run.outcome = .succeeded
        run.deviceOutcomes = [iPhone.id: .succeeded]
        runner.runs = [run]

        let harness = WindowHarness(ActivityView(runner: runner), size: NSSize(width: 600, height: 500))
        defer { harness.close() }
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        let table = try #require(all(harness.window.contentView!).compactMap { $0 as? NSTableView }.first)
        let rows = table.numberOfRows
        let deployRow = rows - 1
        let deployHeight = table.rect(ofRow: deployRow).height

        // Click the "20 commits since …" toggle, the deploy row's last line.
        let rect = table.convert(table.rect(ofRow: deployRow), to: nil)
        let point = NSPoint(x: rect.minX + 40, y: rect.minY + 8)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            harness.window.sendEvent(try #require(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: harness.window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1)))
        }
        harness.settle()

        #expect(table.numberOfRows == rows + 20)
        #expect(table.rect(ofRow: deployRow).height == deployHeight)
    }
}
