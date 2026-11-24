// Filming: a UI test that is filmed acts as a person does, slowly enough to be
// seen. A tap holds long enough for the row or button to show it pressed, and
// text goes in a letter at a time. The film's script records from the test's
// start mark to its end mark, so the film opens on the app, not the build, and
// ends before the app quits.
//
//     import Filming
//
//     try filmMark("start")
//     typeByHand("Lands End", into: app.textFields["search"])
//     pressByHand(app.buttons["place"].firstMatch)
//     try filmMark("end")
//
// The script sets FILM_MARK (TEST_RUNNER_FILM_MARK to xcodebuild) to a path; a
// mark is a file beside it, PATH.start or PATH.end, which it waits for. With no
// FILM_MARK the marks do nothing, so the test runs the same unfilmed.
//
// XCUITest takes about half a second to type each letter, and types a whole
// word too fast to see. So typeByHand types a letter at a time and adds a line
// to PATH.quicken, "FROM TO SECONDS" in seconds since 1970 (a simulator shares
// its Mac's clock): the script plays FROM to TO faster, to last SECONDS, a fast
// typist's speed.

import XCTest

extension XCTestCase {
    /// Holds for a moment, as the eye needs to see what changed.
    public func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Types a letter at a time; the film plays it at a fast typist's speed, `perLetter` seconds a letter.
    public func typeByHand(_ text: String, into field: XCUIElement, perLetter: TimeInterval = 0.08) {
        let from = Date().timeIntervalSince1970
        for letter in text {
            field.typeText(String(letter))
        }
        let to = Date().timeIntervalSince1970
        quicken(from: from, to: to, lasting: perLetter * Double(text.count))
    }

    /// Asks the film's script to play from `from` to `to` (seconds since 1970) in `seconds`.
    public func quicken(from: TimeInterval, to: TimeInterval, lasting seconds: TimeInterval) {
        guard let path = ProcessInfo.processInfo.environment["FILM_MARK"] else { return }
        let url = URL(fileURLWithPath: "\(path).quicken")
        let line = Data(String(format: "%.3f %.3f %.3f\n", from, to, seconds).utf8)
        guard let file = try? FileHandle(forWritingTo: url) else { try? line.write(to: url); return }
        file.seekToEndOfFile()
        file.write(line)
        file.closeFile()
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
