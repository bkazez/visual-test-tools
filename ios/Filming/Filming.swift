// Filming: a UI test that is filmed acts as a person does, slowly enough to be
// seen. A tap holds long enough for the row or button to show it pressed, and
// text goes in a letter at a time. The film's script records from the test's
// start mark to its end mark, so the film opens on the app, not the build, and
// ends before the app quits.
//
//     import Filming
//
//     try filmMark("start")
//     typeByHand("Coit Tower", into: app.textFields["search"])
//     pressByHand(app.buttons["place"].firstMatch)
//     try filmMark("end")
//
// The script sets FILM_MARK (TEST_RUNNER_FILM_MARK to xcodebuild) to a path; a
// mark is a file beside it, PATH.start or PATH.end, which it waits for. With no
// FILM_MARK the marks do nothing, so the test runs the same unfilmed.

import XCTest

extension XCTestCase {
    /// Holds for a moment, as the eye needs to see what changed.
    public func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Types the way a person does, a letter at a time.
    public func typeByHand(_ text: String, into field: XCUIElement, every seconds: TimeInterval = 0.18) {
        for letter in text {
            field.typeText(String(letter))
            pause(seconds)
        }
    }

    /// Taps the way a person does: down long enough for the pressed state to show, then a beat to see what it did.
    public func pressByHand(_ element: XCUIElement, held: TimeInterval = 0.3, after: TimeInterval = 0.3) {
        element.press(forDuration: held)
        pause(after)
    }

    /// Tells the film's script the film starts or ends here.
    public func filmMark(_ moment: String) throws {
        guard let path = ProcessInfo.processInfo.environment["FILM_MARK"] else { return }
        try Data().write(to: URL(fileURLWithPath: "\(path).\(moment)"))
    }
}
