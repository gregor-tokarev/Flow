import XCTest

final class FlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-library"]
        app.launch()
    }

    func testCreateEditCompleteDeleteUndoAndRelaunch() {
        app.buttons["newEntry"].tap()
        let editor = app.textViews["entryText"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Pack for the weekend")
        app.segmentedControls.buttons["Task"].tap()
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Pack for the weekend"].waitForExistence(timeout: 5))
        app.buttons["Complete task"].tap()
        XCTAssertTrue(app.buttons["Mark incomplete"].exists)
        app.staticTexts["Pack for the weekend"].tap()
        editor.tap()
        editor.typeText("\nBring a notebook")
        let editedText = editor.value as! String
        XCTAssertTrue(editedText.contains("Bring a notebook"))
        app.navigationBars.buttons["Done"].tap()
        let cell = app.tables["entries"].cells.firstMatch
        cell.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertEqual(app.tables["entries"].cells.count, 0)
        app.toolbars.buttons["Undo"].tap()
        XCTAssertTrue(app.tables["entries"].cells.firstMatch.waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.tables["entries"].cells.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Mark incomplete"].exists)
        capture("Home")
        app.tables["entries"].cells.firstMatch.tap()
        XCTAssertEqual(editor.value as? String, editedText)
    }

    func testFoldersSettingsAndEmptyDraft() {
        app.buttons["newEntry"].tap()
        app.navigationBars.buttons["Done"].tap()
        XCTAssertEqual(app.tables["entries"].cells.count, 0)
        app.buttons["Settings"].tap()
        app.switches["Folders"].tap()
        app.navigationBars.buttons["Done"].tap()
        app.buttons["Folders"].tap()
        app.buttons["New folder"].tap()
        app.alerts.textFields.firstMatch.typeText("Travel")
        app.alerts.buttons["Save"].tap()
        app.staticTexts["Travel"].tap()
        app.buttons["newEntry"].tap()
        let editor = app.textViews["entryText"]
        editor.tap()
        editor.typeText("A quiet place to write")
        app.navigationBars.buttons["Done"].tap()
        app.buttons["Folders"].tap()
        app.staticTexts["Master"].tap()
        XCTAssertFalse(app.staticTexts["A quiet place to write"].exists)
        app.buttons["Settings"].tap()
        app.switches["Folders"].tap()
        capture("Settings")
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["A quiet place to write"].exists)
    }

    func testSearchAndTaskDefault() {
        app.buttons["Settings"].tap()
        app.staticTexts["Default entry type"].tap()
        app.staticTexts["Task"].tap()
        app.navigationBars.buttons["Done"].tap()
        app.buttons["newEntry"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Task"].isSelected)
        app.textViews["entryText"].tap()
        app.textViews["entryText"].typeText("Read the next chapter")
        capture("Editor")
        app.navigationBars.buttons["Done"].tap()
        app.swipeDown()
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("missing")
        XCTAssertTrue(app.staticTexts["No matching entries."].exists)
    }

    func testKeyboardAndAttachmentPickerCancellation() {
        app.buttons["newEntry"].tap()
        XCTAssertTrue(app.textViews["entryText"].waitForExistence(timeout: 5))
        app.buttons["hideEntryKeyboard"].tap()
        app.buttons["Attach file"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        app.navigationBars.buttons["Done"].tap()
        XCTAssertEqual(app.tables["entries"].cells.count, 0)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
