import XCTest

/// The background slider in the palette-sets sheet (spec 73) is taken only by
/// its inner capsule, and only dragged (spec 77): dragged past either end it
/// settles there, a tap on the empty track moves nothing, and a drag puts it
/// back. A tap outside the sheet closes it without touching the board (spec
/// 74).
final class PaletteSheetUITests: XCTestCase {
    func testBackgroundSliderFollowsFinger() {
        let app = XCUIApplication()
        app.launch()
        openSheet(app)

        let slider = app.descendants(matching: .any)["backgroundSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        let initial = percent(slider)

        slider.press(at: knob(slider, at: 0.5 * Double(initial) / 100), dragTo: 1.2)
        XCTAssertEqual(percent(slider), 100)
        slider.press(at: knob(slider, at: 1), dragTo: -0.2)
        XCTAssertEqual(percent(slider), 0)

        // The empty track, right of the inner capsule: nothing moves.
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        XCTAssertEqual(percent(slider), 0, "a tap on the empty track moved the slider")

        // Back where it was, by the end of the inner capsule.
        slider.press(at: knob(slider, at: 0), dragTo: knob(slider, at: Double(initial) / 100))
        XCTAssertEqual(Double(percent(slider)), Double(initial), accuracy: 2)

        // A tap on the board outside the sheet closes it and fires nothing
        // (spec 74).
        let scene = app.otherElements["gameScene"]
        let before = scene.value as? String
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        XCTAssertTrue(slider.waitForNonExistence(timeout: 5), "the sheet stayed open")
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(scene.value as? String, before, "the tap reached the board")
    }

    /// The icon carousel (`IconCarousel`, specs 75, 79, 83): the icon
    /// brought to the middle is the set in play, by a drag or by a tap on it.
    func testIconCarouselPicksTheMiddleSet() {
        let app = XCUIApplication()
        app.launch()
        openSheet(app)

        let selected = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'paletteSet.' AND selected == true")
        ).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 10), "no set selected")
        Thread.sleep(forTimeInterval: 1)
        let original = selected.identifier

        // One icon over to the left: its right-hand neighbor comes to the
        // middle and is picked.
        // One step: an icon (72) and the gap after it (22).
        let step = selected.frame.width * 94 / 72
        let start = selected.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // Slow, and held at the end, so the drag carries on by no momentum.
        start.press(
            forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: -step, dy: 0)),
            withVelocity: .slow, thenHoldForDuration: 0.3
        )
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertNotEqual(selected.identifier, original, "the drag picked nothing")

        // A tap on the first one brings it back. The row goes round, every
        // set showing up again further along: tap the one in view.
        let copies = app.descendants(matching: .any).matching(identifier: original).allElementsBoundByIndex
        guard let back = copies.first(where: { $0.isHittable }) else {
            XCTFail("the first icon is out of view")
            return
        }
        back.tap()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(selected.identifier, original, "the tap didn't bring the set back")
    }

    /// Opens the sheet as a player does, once the game is up: by `settings`.
    /// (Opening it at launch, with `-showPaletteSets`, raced the game coming
    /// up: now and then the sheet's elements went missing for a while.)
    private func openSheet(_ app: XCUIApplication) {
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15), "the game never came up")
        app.dismissIconChangeAlert()
        Thread.sleep(forTimeInterval: 0.5)
        settings.tap()
        Thread.sleep(forTimeInterval: 1)
    }

    /// Normalized x of the round end of the inner capsule at `value`: it
    /// runs from half its height in from the slider's left end at 0 to as far
    /// in from the right end at 1 (`CapsuleSlider`: 56 high, inset 6).
    private func knob(_ slider: XCUIElement, at value: Double) -> Double {
        let width = slider.frame.width
        let inner: CGFloat = 56 - 2 * 6
        return Double((6 + inner / 2 + CGFloat(value) * (width - 12 - inner)) / width)
    }

    private func percent(_ slider: XCUIElement) -> Int {
        Int((slider.value as? String ?? "").dropLast()) ?? -1
    }
}

private extension XCUIElement {
    /// Presses at normalized x `from` across the middle and drags to `to`.
    func press(at from: Double, dragTo to: Double) {
        let start = coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.5)))
    }
}
