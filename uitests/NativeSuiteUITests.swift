import XCTest

final class NativeSuiteUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    @discardableResult
    private func launch(mode: String) -> XCUIApplication {
        let application = XCUIApplication(bundleIdentifier: "com.example.TouchTestDemo")
        application.launchArguments = ["--native-mode", mode, "--ui-testing"]
        application.launch()
        XCTAssertTrue(application.wait(for: .runningForeground, timeout: 10), "App did not reach the foreground for mode \(mode)")
        XCTAssertEqual(application.webViews.count, 0, "The native suite must not create a web view")
        app = application
        return application
    }

    private func identified(_ identifier: String, timeout: TimeInterval = 6) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing accessibility element: \(identifier)")
        return element
    }

    private func wait(
        _ description: String,
        timeout: TimeInterval = 6,
        until condition: @escaping () -> Bool
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() },
            object: nil
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, description)
    }

    private func retainedSamples(in text: String) -> Int? {
        let expression = try? NSRegularExpression(pattern: #"保留\s+(\d+)\s*/"#)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = expression?.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[valueRange])
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNativeMultiCanvasAndRealTouchSampling() {
        launch(mode: "multi")
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let canvas = identified("native-scene-multi")

        XCTAssertEqual(canvas.frame.minX, window.frame.minX, accuracy: 2)
        XCTAssertEqual(canvas.frame.minY, window.frame.minY, accuracy: 2)
        XCTAssertEqual(canvas.frame.width, window.frame.width, accuracy: 2)
        XCTAssertEqual(canvas.frame.height, window.frame.height, accuracy: 2)

        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.14, dy: 0.24))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.72))
        start.press(forDuration: 0.05, thenDragTo: end)

        let metrics = identified("native-metrics")
        wait("Touch release should leave zero active contacts and retain native UITouch samples") {
            metrics.label.contains("触点 0") && (self.retainedSamples(in: metrics.label) ?? 0) > 0
        }
        XCTAssertGreaterThan(retainedSamples(in: metrics.label) ?? 0, 0)
        attachScreenshot("native-multi-sampled")
    }

    func testNativeTypingKeepsInsertionAreaAboveKeyboard() {
        launch(mode: "type")
        _ = identified("native-scene-type")
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 6))
        XCTAssertTrue(editor.isHittable)

        editor.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "The native UITextView did not present a software keyboard")
        editor.typeText("touch test")
        XCTAssertTrue(String(describing: editor.value).contains("touch test"))

        XCTAssertLessThanOrEqual(editor.frame.maxY, keyboard.frame.minY + 2, "The native editor is obscured by the keyboard")
        XCTAssertTrue(editor.isHittable, "The UITextView must remain usable after the keyboard appears")
        editor.typeText(" usable")
        XCTAssertTrue(String(describing: editor.value).contains("touch test usable"))
        attachScreenshot("native-typing-keyboard")
    }

    func testNativeSettingsControlsChangeState() {
        launch(mode: "ui")
        _ = identified("native-scene-ui")

        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let toggleBefore = String(describing: toggle.value)
        toggle.tap()
        wait("UISwitch did not toggle") { String(describing: toggle.value) != toggleBefore }

        let slider = app.sliders.firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        let sliderBefore = String(describing: slider.value)
        slider.adjust(toNormalizedSliderPosition: 0.84)
        wait("UISlider did not report a changed native value") { String(describing: slider.value) != sliderBefore }
        attachScreenshot("native-settings-controls")
    }

    func testNativePhotoReceivesRealPinchGesture() {
        launch(mode: "pinch")
        let scene = identified("native-scene-pinch")
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollView.isHittable)

        let scaleBefore=String(describing:scrollView.value)
        scrollView.pinch(withScale: 1.8, velocity: 1.2)
        wait("Native photo pinch did not change zoom") {String(describing:scrollView.value) != scaleBefore}
        XCTAssertTrue(scene.exists)
        XCTAssertTrue(app.state == .runningForeground)
        attachScreenshot("native-photo-pinched")
    }

    func testNativeGameRequestsLandscapeAndOpensNativeSettings() {
        XCUIDevice.shared.orientation = .portrait
        launch(mode: "moba")
        wait("MOBA mode did not request a stable landscape window", timeout: 10) {
            let frame = self.app.windows.firstMatch.frame
            return frame.width > frame.height && frame.width > 0
        }
        XCTAssertEqual(app.webViews.count, 0)

        let settings = identified("game-control-settings")
        if settings.isHittable {
            settings.tap()
        } else {
            // The HUD view deliberately forwards touches to its parent scene; use
            // the identified element's live frame rather than a guessed position.
            settings.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        let title = app.staticTexts["游戏设置"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "The native game settings sheet did not open")
        XCTAssertEqual(app.webViews.count, 0)
        attachScreenshot("native-moba-settings")
    }
}
