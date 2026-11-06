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

    private func state(of element: XCUIElement) -> String {
        String(describing: element.value)
    }

    private func scalar(_ key: String, in state: String) -> Double? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let expression = try? NSRegularExpression(pattern: "(?:^|;)\(escaped)=(-?[0-9]+(?:\\.[0-9]+)?)")
        let range = NSRange(state.startIndex..., in: state)
        guard let match = expression?.firstMatch(in: state, range: range),
              let valueRange = Range(match.range(at: 1), in: state) else { return nil }
        return Double(state[valueRange])
    }

    private func point(_ key: String, in state: String) -> CGVector? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let expression = try? NSRegularExpression(pattern: "(?:^|;)\(escaped)=(-?[0-9]+(?:\\.[0-9]+)?),(-?[0-9]+(?:\\.[0-9]+)?)")
        let range = NSRange(state.startIndex..., in: state)
        guard let match = expression?.firstMatch(in: state, range: range),
              let xRange = Range(match.range(at: 1), in: state),
              let yRange = Range(match.range(at: 2), in: state),
              let x = Double(state[xRange]), let y = Double(state[yRange]) else { return nil }
        return CGVector(dx: x, dy: y)
    }

    private func localCoordinate(_ point: CGVector, in element: XCUIElement) -> XCUICoordinate {
        element.coordinate(withNormalizedOffset: .zero).withOffset(point)
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
        canvas.pinch(withScale:1.3,velocity:1.5)
        wait("Two real fingers must be tracked independently") {metrics.label.contains("最大 2")}
        attachScreenshot("native-multi-sampled")
        identified("native-clear").tap()
        wait("Clear must reset this trial's retained samples") {(self.retainedSamples(in:metrics.label) ?? -1)==0}
    }

    func testNativeTapUsesActualTargetErrorAndReachableGeometry() {
        launch(mode: "tap")
        let canvas = identified("native-scene-tap")
        wait("Tap state must expose a reachable target and the geometry-only 200 point validation") {
            let value = self.state(of: canvas)
            return value.contains("targetValid=1") && value.contains("geometry-only 200/200") && self.point("target", in: value) != nil
        }
        if let target=point("target",in:state(of:canvas)) {
            let targetCircle=CGRect(x:canvas.frame.minX+target.dx-36,y:canvas.frame.minY+target.dy-36,width:72,height:72)
            for identifier in ["native-metrics","native-project-menu","native-clear"] {
                XCTAssertFalse(targetCircle.intersects(identified(identifier).frame), "Generated target overlaps \(identifier)")
            }
        }

        func tapCurrentTarget(offset: CGFloat) -> CGVector {
            let before = state(of: canvas)
            guard let target = point("target", in: before) else {
                XCTFail("Missing current target in \(before)")
                return .zero
            }
            let blockers=["native-metrics","native-project-menu","native-clear"].map{identified($0).frame}
            let candidates=[CGVector(dx:target.dx+offset,dy:target.dy),CGVector(dx:target.dx-offset,dy:target.dy),CGVector(dx:target.dx,dy:target.dy+offset),CGVector(dx:target.dx,dy:target.dy-offset)]
            let selected=candidates.first { candidate in
                let global=CGPoint(x:canvas.frame.minX+candidate.dx,y:canvas.frame.minY+candidate.dy)
                return candidate.dx>=1 && candidate.dx<=canvas.frame.width-1 && candidate.dy>=1 && candidate.dy<=canvas.frame.height-1
                    && !blockers.contains{$0.contains(global)}
            } ?? target
            localCoordinate(selected, in: canvas).tap()
            return target
        }

        let first = tapCurrentTarget(offset: 0)
        wait("Center tap must be recorded before a new target is generated") {
            let value = self.state(of: canvas)
            return self.scalar("tapCount", in: value) == 1 && (self.scalar("lastError", in: value) ?? 999) < 4
        }
        let secondState = state(of: canvas)
        guard let second = point("target", in: secondState) else {XCTFail("Missing new target in \(secondState)");return}
        XCTAssertTrue(second.dx != first.dx || second.dy != first.dy, "A successful tap must advance the target")

        _ = tapCurrentTarget(offset: 20)
        wait("A 20 point offset must be a hit and contribute its measured error") {
            let value = self.state(of: canvas)
            return self.scalar("tapCount", in: value) == 2 && self.scalar("hitCount", in: value) == 2 && abs((self.scalar("lastError", in: value) ?? 999) - 20) < 4
        }
        _ = tapCurrentTarget(offset: 40)
        wait("A 40 point offset must miss and update last, average, and maximum error") {
            let value = self.state(of: canvas)
            return self.scalar("tapCount", in: value) == 3 && self.scalar("hitCount", in: value) == 2
                && abs((self.scalar("lastError", in: value) ?? 999) - 40) < 4
                && abs((self.scalar("averageError", in: value) ?? 999) - 20) < 4
                && abs((self.scalar("maxError", in: value) ?? 999) - 40) < 4
        }
        attachScreenshot("native-tap-error")
    }

    func testNativeCoverageResetsOnRealOrientationChangeAndCanContinue() {
        for mode in ["grid", "edge", "line"] {
            XCUIDevice.shared.orientation = .portrait
            launch(mode: mode)
            let canvas = identified("native-scene-\(mode)")
            func drawCoverage() {
                var start=CGVector.zero,end=CGVector.zero
                switch mode {
                case "edge": (start,end)=(CGVector(dx:0.12,dy:0.97),CGVector(dx:0.82,dy:0.97))
                case "line": (start,end)=(CGVector(dx:0.12,dy:0.50),CGVector(dx:0.82,dy:0.50))
                default: (start,end)=(CGVector(dx:0.12,dy:0.22),CGVector(dx:0.78,dy:0.72))
                }
                canvas.coordinate(withNormalizedOffset:start).press(forDuration:0.05,thenDragTo:canvas.coordinate(withNormalizedOffset:end))
            }
            drawCoverage()
            wait("\(mode) must record real drawn coverage") {(self.scalar("coverage", in:self.state(of:canvas)) ?? 0)>0}
            XCUIDevice.shared.orientation = .landscapeLeft
            wait("\(mode) must clear incompatible coverage after a real size change", timeout:10) {
                self.app.windows.firstMatch.frame.width>self.app.windows.firstMatch.frame.height
                    && (self.scalar("layoutResetCount",in:self.state(of:canvas)) ?? 0)>=1
                    && self.scalar("coverage",in:self.state(of:canvas))==0
            }
            drawCoverage()
            wait("\(mode) must accept new coverage in the new coordinate space") {(self.scalar("coverage",in:self.state(of:canvas)) ?? 0)>0}
            app.terminate();app=nil
        }
    }

    func testNativeCrossCursorRemapsAndStaysVisibleAfterRotation() {
        launch(mode:"cross")
        let canvas=identified("native-scene-cross")
        canvas.coordinate(withNormalizedOffset:CGVector(dx:0.88,dy:0.78)).tap()
        wait("Cross cursor must follow a real right-side touch") {
            guard let cursor=self.point("cursor",in:self.state(of:canvas)) else{return false}
            return cursor.dx>canvas.frame.width/2 && cursor.dy>canvas.frame.height/2
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        wait("Cross cursor must remap and remain a visible circle after rotation",timeout:10) {
            guard self.app.windows.firstMatch.frame.width>self.app.windows.firstMatch.frame.height,
                  (self.scalar("layoutResetCount",in:self.state(of:canvas)) ?? 0)>=1,
                  let cursor=self.point("cursor",in:self.state(of:canvas)) else{return false}
            return cursor.dx>=canvas.frame.width/2+13 && cursor.dx<=canvas.frame.width-13
                && cursor.dy>=13 && cursor.dy<=canvas.frame.height-13
        }
        attachScreenshot("native-cross-rotated")
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
        let picture=identified("native-photo-image"),window=app.windows.firstMatch
        XCTAssertLessThanOrEqual(picture.frame.width,window.frame.width*0.82)
        XCTAssertLessThanOrEqual(picture.frame.height,window.frame.height*0.62)

        let scaleBefore=String(describing:scrollView.value)
        scrollView.pinch(withScale: 1.8, velocity: 1.2)
        wait("Native photo pinch did not change zoom") {String(describing:scrollView.value) != scaleBefore}
        XCTAssertTrue(scene.exists)
        XCTAssertTrue(app.state == .runningForeground)
        attachScreenshot("native-photo-pinched")
        identified("photo-change").tap()
        app.buttons["战场细节"].tap()
        wait("Built-in photo must change") {picture.label.contains("战场细节")}
        identified("native-clear").tap()
        wait("Clear must reset zoom while retaining the selected photo") {picture.label.contains("战场细节") && String(describing:picture.value).contains("scale 1.00")}
    }

    func testNativeReaderDefaultsToVerticalScrolling() {
        launch(mode:"read")
        let article=identified("native-reader-scroll")
        let before=String(describing:article.value)
        article.swipeUp()
        wait("Default reader must scroll vertically through the text") {String(describing:article.value) != before}
        attachScreenshot("native-reader-scrolled")
    }

    func testNativeProjectMenuShortDragKeepsClearAccessible() {
        launch(mode:"multi")
        let menu=identified("native-project-menu"),original=menu.frame
        let window=app.windows.firstMatch,frame=window.frame,anchor=window.coordinate(withNormalizedOffset:.zero)
        let origin=anchor.withOffset(CGVector(dx:original.midX-frame.minX,dy:original.midY-frame.minY))
        let target=anchor.withOffset(CGVector(dx:original.midX-frame.minX-64,dy:original.midY-frame.minY+30))
        origin.press(forDuration:0.1,thenDragTo:target)
        wait("Project menu must follow a short drag; original=\(original), moved=\(menu.frame), diagnostics=\(identified("native-metrics").label)") {abs(menu.frame.midX-original.midX+64)<3 && abs(menu.frame.midY-original.midY-30)<3}
        XCTAssertTrue(identified("native-clear").isHittable)
        let moved=menu.frame
        let backStart=anchor.withOffset(CGVector(dx:moved.midX-frame.minX,dy:moved.midY-frame.minY))
        let backEnd=anchor.withOffset(CGVector(dx:original.midX-frame.minX,dy:original.midY-frame.minY))
        backStart.press(forDuration:0.1,thenDragTo:backEnd)
        wait("Project menu must return without losing its controls; original=\(original), moved=\(moved), returned=\(menu.frame), diagnostics=\(identified("native-metrics").label)") {abs(menu.frame.midX-original.midX)<3 && abs(menu.frame.midY-original.midY)<3}
        attachScreenshot("native-project-menu-dragged")
    }

    func testNativeGameFloatingStickAndMovableSavedLayout() {
        launch(mode:"moba")
        wait("Game must enter landscape") {self.app.windows.firstMatch.frame.width>self.app.windows.firstMatch.frame.height}
        let window=app.windows.firstMatch,frame=window.frame
        let start=window.coordinate(withNormalizedOffset:CGVector(dx:0.22,dy:0.66))
        start.press(forDuration:0.05,thenDragTo:window.coordinate(withNormalizedOffset:CGVector(dx:0.30,dy:0.55)))
        let metrics=identified("native-metrics")
        let expectedX=Int(frame.width*0.22),expectedY=Int(frame.height*0.66)
        wait("Floating joystick must use the actual left-hand landing point") {
            let value=metrics.label
            return (-2...2).contains {dx in (-2...2).contains{dy in value.contains("落指 \(expectedX+dx),\(expectedY+dy)")}}
        }
        identified("game-control-settings").tap()
        app.segmentedControls.buttons["布局"].tap()
        app.buttons["移动按钮与菜单"].tap()
        let skill=identified("game-control-skill1"),original=skill.frame
        let viewport=app.windows.firstMatch,anchor=viewport.coordinate(withNormalizedOffset:.zero),viewportFrame=viewport.frame
        let origin=anchor.withOffset(CGVector(dx:original.midX-viewportFrame.minX,dy:original.midY-viewportFrame.minY))
        let destination=anchor.withOffset(CGVector(dx:original.midX-viewportFrame.minX-28,dy:original.midY-viewportFrame.minY-24))
        origin.press(forDuration:0.1,thenDragTo:destination)
        wait("Native HUD must move by the fixed requested delta; before=\(original), after=\(skill.frame), diagnostics=\(metrics.label)") {abs(skill.frame.midX-original.midX+28)<3 && abs(skill.frame.midY-original.midY+24)<3}
        let moved=skill.frame
        app.terminate();launch(mode:"moba")
        wait("Game must return to landscape") {self.app.windows.firstMatch.frame.width>self.app.windows.firstMatch.frame.height}
        let restored=identified("game-control-skill1")
        wait("Edited native HUD position must survive relaunch") {abs(restored.frame.midX-moved.midX)<3 && abs(restored.frame.midY-moved.midY)<3}
        attachScreenshot("native-moba-layout-restored")
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
