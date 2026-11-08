import XCTest

extension XCUIApplication {
    /// iOS confirms every change of the home-screen icon with an alert of
    /// its own (spec 66). The app under test is installed afresh, on the
    /// primary icon, so its first launch switches to the icon of the set in
    /// play and the alert comes up — and eats the next tap. Closes it if it
    /// is there, then gives the game a moment: it stood still under the
    /// alert, and a new board's half-second cannon lockout runs out only
    /// once it is going again.
    func dismissIconChangeAlert() {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 2) {
            alert.buttons["OK"].tap()
            Thread.sleep(forTimeInterval: 2)
        }
    }
}
