import XCTest

final class StudioUITests: XCTestCase {
    func testCreateProductControlsAndArchive() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["newProduct"].waitForExistence(timeout: 10))
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

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
