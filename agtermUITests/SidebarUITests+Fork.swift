import AppKit
import XCTest

// Fork: kept out of upstream's SidebarUITests.swift.
extension SidebarUITests {
    // the real-click leg of `SidebarControlClickTests`, which can only dispatch the outline's actions itself:
    // with `renameOnDoubleClick` off, a double-click's first click collapses and its second neither re-expands
    // nor opens the rename field.
    func testWorkspaceDoubleClickTogglesOnceWhenRenameOnDoubleClickIsOff() throws {
        XCTAssertTrue(app.staticTexts["workspace 1"].waitForExistence(timeout: 20), "seeded workspace should exist")
        XCTAssertTrue(pollSessionRowCount(1, timeout: 10), "seeded session should be visible")

        app.terminate()
        let settings = try JSONSerialization.data(withJSONObject: ["renameOnDoubleClick": false])
        try settings.write(to: stateDir.appendingPathComponent("settings.json"))
        app = XCUIApplication()
        app.launchEnvironment["AGTERM_STATE_DIR"] = stateDir.path
        app.launchForUITest()
        let ws = app.staticTexts["workspace 1"]
        XCTAssertTrue(ws.waitForExistence(timeout: 20), "workspace 1 should restore")
        XCTAssertTrue(pollSessionRowCount(1, timeout: 10), "the session row should be visible after relaunch")

        ws.doubleClick()
        XCTAssertTrue(pollSessionRowCount(0, timeout: 5), "the first click should collapse the workspace")
        let field = app.descendants(matching: .any).matching(identifier: "edit-field").firstMatch
        XCTAssertFalse(field.waitForExistence(timeout: 2), "a workspace double-click must not open the rename field")
        XCTAssertFalse(pollSessionRowCount(1, timeout: 2), "the second click must not re-expand the workspace")
    }
}
