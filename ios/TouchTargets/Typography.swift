// Typography: fail a UI test when a screen shows a straight quote or
// apostrophe. Typeset text uses curly ones: ’ for an apostrophe, ‘ ’ and “ ”
// for quotes. The rule covers every string the screen shows, whether the app
// wrote it or a server sent it.
//
//     import TouchTargets
//
//     assertTypography(app, screen: "search")          // beside assertTouchTargets
//
// It reads each element's label, title and placeholder. A text field's value
// is what the user typed, so it is not read.

import XCTest

public struct TypographyProblem: CustomStringConvertible, Sendable {
    public let description: String
}

public enum Typography {
    /// The characters a typeset screen never shows.
    public static let straight: Set<Character> = ["'", "\""]

    /// Every string on the screen as it is now that holds a straight quote.
    public static func problems(in app: XCUIApplication) throws -> [TypographyProblem] {
        var seen = Set<String>()
        var problems: [TypographyProblem] = []
        func visit(_ node: XCUIElementSnapshot) {
            for text in [node.label, node.title, node.placeholderValue ?? ""] where text.contains(where: straight.contains) {
                if seen.insert(text).inserted {
                    problems.append(TypographyProblem(description: "\u{201C}\(text)\u{201D} has a straight quote; use \u{2019} \u{2018} \u{201C} \u{201D}"))
                }
            }
            node.children.forEach(visit)
        }
        visit(try app.snapshot())
        return problems
    }

}

extension XCTestCase {
    /// Fail with every string on the screen that holds a straight quote.
    public func assertTypography(
        _ app: XCUIApplication,
        screen: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let problems = try Typography.problems(in: app)
            guard !problems.isEmpty else { return }
            XCTFail(
                "\(screen): \(problems.count) straight quote\(problems.count == 1 ? "" : "s")\n"
                    + problems.map { "  - \($0)" }.joined(separator: "\n"),
                file: file, line: line
            )
        } catch {
            XCTFail("\(screen): could not read the screen: \(error)", file: file, line: line)
        }
    }
}
