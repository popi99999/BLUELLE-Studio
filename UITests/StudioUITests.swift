import XCTest

final class StudioUITests: XCTestCase {
    func testCreateProductControlsAndArchive() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["newProduct"].waitForExistence(timeout: 10))
        expectNoAlert(app)
        XCTAssertFalse(app.buttons["shutter"].isEnabled, "Simulator must not pretend to capture photos")
        app.buttons["newProduct"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("Celine bianca")
        app.alerts.buttons["Crea sessione"].tap()
        XCTAssertTrue(app.staticTexts["Celine bianca"].waitForExistence(timeout: 3))
        attach(app, name: "01-studio")

        app.buttons["cameraControls"].tap()
        XCTAssertTrue(app.buttons["closeControls"].waitForExistence(timeout: 3))
        attach(app, name: "02-controlli")
        app.buttons["closeControls"].tap()

        app.buttons["openLibrary"].tap()
        XCTAssertTrue(app.navigationBars["Archivio"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Celine bianca"].exists)
        attach(app, name: "03-archivio")
        app.cells.containing(.staticText, identifier: "Celine bianca").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Pronto per il primo scatto"].waitForExistence(timeout: 3))
        app.buttons["Continua a fotografare"].tap()
        XCTAssertTrue(app.buttons["shutter"].waitForExistence(timeout: 3))
    }

    func testOverlayTogglesRenameAndDeleteProduct() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["newProduct"].waitForExistence(timeout: 10))
        expectNoAlert(app)
        XCTAssertTrue(app.buttons["togglePeaking"].exists)
        app.buttons["togglePeaking"].tap()
        app.buttons["togglePeaking"].tap()

        app.buttons["newProduct"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("Gucci polo")
        app.alerts.buttons["Crea sessione"].tap()
        XCTAssertTrue(app.staticTexts["Gucci polo"].waitForExistence(timeout: 3))

        app.buttons["openLibrary"].tap()
        XCTAssertTrue(app.navigationBars["Archivio"].waitForExistence(timeout: 3))
        let row = app.cells.containing(.staticText, identifier: "Gucci polo").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.swipeLeft()
        XCTAssertTrue(app.buttons["Rinomina"].waitForExistence(timeout: 3))
        app.buttons["Rinomina"].tap()
        let rename = app.alerts.textFields.firstMatch
        XCTAssertTrue(rename.waitForExistence(timeout: 3))
        // The alert focuses its field with the cursor after the current name.
        if (rename.value(forKey: "hasKeyboardFocus") as? Bool) != true { rename.tap() }
        rename.typeText(" nera")
        app.alerts.buttons["Salva"].tap()
        let renamed = app.cells.containing(.staticText, identifier: "Gucci polo nera").firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 3))

        renamed.swipeLeft()
        XCTAssertTrue(app.buttons["Elimina"].waitForExistence(timeout: 3))
        app.buttons["Elimina"].tap()
        XCTAssertTrue(app.alerts.buttons["Elimina"].waitForExistence(timeout: 3))
        app.alerts.buttons["Elimina"].tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: renamed)
        wait(for: [gone], timeout: 5)
        attach(app, name: "04-archivio-vuoto")
    }

    /// A fresh launch must not greet the user with an error.
    private func expectNoAlert(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let alert = app.alerts.firstMatch
        guard alert.waitForExistence(timeout: 2) else { return }
        let texts = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
        XCTFail("Unexpected alert at launch: \(texts)", file: file, line: line)
        if alert.buttons["OK"].exists { alert.buttons["OK"].tap() }
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
