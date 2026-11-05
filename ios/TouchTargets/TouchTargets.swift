// TouchTargets: fail a UI test when a screen's touch targets are too small or
// too close together, so a thumb aimed at one never lands on another.
//
//     import TouchTargets
//
//     app.buttons["Write to Paul"].tap()
//     assertTouchTargets(app, screen: "person")          // in any XCTestCase
//
// Two rules, measured on the screen as it is drawn:
//
//   1. SIZE. Every target is at least `minSize` (44 pt, Apple's minimum hit
//      area) in both directions. The only control in a list row is measured
//      as the row, because the row is what takes the tap; a row holding
//      several controls has each measured as itself. A row with no control in
//      it is text, not a target. Controls Apple draws itself
//      -- navigation bar, tab bar, toolbar, keyboard, segmented control,
//      alerts, and the text and context menus with their page arrows -- are left alone: their hit areas extend past what the
//      accessibility frame reports. So is a text field's size: a field that
//      grows with its text reports the text's height, not the box drawn
//      around it, so make the whole box focus the field instead (a tap
//      gesture on the outline) -- its spacing is still checked. A control
//      that reports one frame twice (a menu and its label) is one target.
//
//   2. GAP. Two targets are at least `minGap` (16 pt) apart, edge to edge,
//      when the distance between them is a layout decision: both fixed on the
//      screen (a key above a tab bar), both in the same scrolling content, or
//      both in the same row of a list. Rows of a list abut by design, and the
//      swipe buttons iOS slides out beside a row are iOS's, so targets in two
//      different rows, or outside any row, of one list are not compared. A row
//      scrolled half under a bar is not a layout decision either, so a target
//      in scrolling content is never compared with one outside it. Pairs
//      inside one of Apple's own containers are exempt, as for size, and so is
//      everything on the keyboard. Overlapping targets fail at any size; one
//      target inside another (a button in its own row) is not a pair.
//
// Before reporting, each offending target is asked whether it can be hit at
// all, so a row hidden under an opaque bar is not reported against the bar.

import XCTest

public struct TouchTargetRules: Sendable {
    /// The smallest a target may be in either direction, in points.
    public var minSize: CGFloat
    /// The smallest edge-to-edge distance between two targets, in points.
    public var minGap: CGFloat

    public init(minSize: CGFloat = 44, minGap: CGFloat = 16) {
        self.minSize = minSize
        self.minGap = minGap
    }
}

public struct TouchTargetProblem: CustomStringConvertible, Sendable {
    public let description: String
}

public enum TouchTargets {
    /// Every problem on the screen as it is now, worst first.
    public static func problems(in app: XCUIApplication, rules: TouchTargetRules = .init()) throws -> [TouchTargetProblem] {
        let root = try app.snapshot()
        var targets: [Target] = []
        var counts: [XCUIElement.ElementType: Int] = [:]
        var rows: [Int: CGRect] = [:]
        collect(root, path: [], screen: root.frame, into: &targets, counts: &counts, rows: &rows)
        // The keyboard is Apple's, and its keys are not all inside the
        // keyboard element: the dictation and globe keys sit under it, and on
        // iPad the Undo / Redo / Paste bar sits above it, in the keyboard's
        // own window.
        if let keyboardTop = keyboardTop(root) {
            targets.removeAll { $0.frame.maxY > keyboardTop }
        }
        let keyboardWindows = Set(root.children.enumerated().compactMap { index, window in
            keyboardTop(window) == nil ? nil : index
        })
        targets.removeAll { $0.window.map(keyboardWindows.contains) ?? false }
        let perRow = Dictionary(grouping: targets.compactMap(\.row), by: { $0 }).mapValues(\.count)
        // Rounding in layout reports a 44 pt row as 43.99.
        let tolerance: CGFloat = 0.5

        var problems: [(severity: CGFloat, problem: TouchTargetProblem, targets: [Target])] = []

        var measured = Set<String>()
        for target in targets where target.system == nil && !textTypes.contains(target.type) {
            guard measured.insert("\(target.frame)").inserted else { continue }
            let alone = target.row.map { perRow[$0] == 1 } ?? false
            let area = alone ? (target.row.flatMap { rows[$0] } ?? target.frame) : target.frame
            let short = min(area.width, area.height)
            if short < rules.minSize - tolerance {
                problems.append((rules.minSize - short, TouchTargetProblem(description:
                    "\(target.name) is \(points(area.width))×\(points(area.height)) pt; the minimum is \(points(rules.minSize)) pt"
                ), [target]))
            }
        }

        for i in targets.indices {
            for j in targets.indices where j > i {
                let a = targets[i], b = targets[j]
                guard a.comparable(with: b) else { continue }
                let gap = distance(a.frame, b.frame)
                if gap < rules.minGap - tolerance {
                    let what = gap < 0
                        ? "overlap"
                        : "are \(points(gap)) pt apart; the minimum is \(points(rules.minGap)) pt"
                    problems.append((rules.minGap - gap, TouchTargetProblem(description:
                        "\(a.name) and \(b.name) \(what)"
                    ), [a, b]))
                }
            }
        }

        // A target that cannot be hit -- under an opaque bar, behind a sheet --
        // is nobody's problem.
        var hittable: [Int: Bool] = [:]
        func canHit(_ target: Target) -> Bool {
            if let known = hittable[target.serial] { return known }
            let element = app.descendants(matching: target.type).element(boundBy: target.indexAmongType)
            let answer = element.exists && element.frame.equalTo(target.frame) ? element.isHittable : true
            hittable[target.serial] = answer
            return answer
        }

        return problems
            .filter { $0.targets.allSatisfy(canHit) }
            .sorted { $0.severity > $1.severity }
            .map(\.problem)
    }

    // MARK: - Reading the screen

    private static let targetTypes: Set<XCUIElement.ElementType> = [
        .button, .link, .switch, .toggle, .slider, .stepper,
        .textField, .secureTextField, .searchField, .textView,
        .menuButton, .popUpButton, .disclosureTriangle, .incrementArrow,
    ]

    private static let textTypes: Set<XCUIElement.ElementType> = [
        .textField, .secureTextField, .searchField, .textView,
    ]

    /// Apple's own containers: their layout is the system's, not the app's.
    private static let systemTypes: Set<XCUIElement.ElementType> = [
        .navigationBar, .tabBar, .toolbar, .keyboard, .segmentedControl,
        .alert, .sheet, .picker, .datePicker, .menu, .menuBar, .statusBar,
    ]

    private static let scrollTypes: Set<XCUIElement.ElementType> = [
        .table, .collectionView, .scrollView, .webView,
    ]

    private struct Ancestor {
        let type: XCUIElement.ElementType
        let serial: Int
    }

    private struct Target {
        let serial: Int
        let type: XCUIElement.ElementType
        let indexAmongType: Int
        let frame: CGRect
        let name: String
        /// The nearest of Apple's own containers, if any.
        let system: Int?
        /// The nearest scrolling container, if any.
        let scroll: Int?
        /// Whether that container is a list (table or collection view).
        let inList: Bool
        /// The list row this sits in, if any.
        let row: Int?
        /// Which of the application's windows this is in.
        let window: Int?
        let ancestors: Set<Int>

        func comparable(with other: Target) -> Bool {
            if ancestors.contains(other.serial) || other.ancestors.contains(serial) { return false }
            if let system, system == other.system { return false }
            guard scroll == other.scroll else { return false }
            if inList { return row != nil && row == other.row }
            return true
        }
    }

    private nonisolated(unsafe) static var serial = 0

    private static func collect(
        _ node: XCUIElementSnapshot, path: [Ancestor], screen: CGRect, windowIndex: Int? = nil,
        into targets: inout [Target], counts: inout [XCUIElement.ElementType: Int],
        rows: inout [Int: CGRect]
    ) {
        serial += 1
        let mine = serial
        let type = node.elementType
        if type == .cell { rows[mine] = node.frame }
        var index = 0
        if targetTypes.contains(type) {
            index = counts[type, default: 0]
            counts[type] = index + 1
            let frame = node.frame
            if !frame.isEmpty, frame.intersects(screen) {
                targets.append(Target(
                    serial: mine,
                    type: type,
                    indexAmongType: index,
                    frame: frame,
                    name: describe(node),
                    system: path.last { systemTypes.contains($0.type) }?.serial,
                    scroll: path.last { scrollTypes.contains($0.type) }?.serial,
                    inList: path.last { scrollTypes.contains($0.type) }.map { [.table, .collectionView].contains($0.type) } ?? false,
                    row: path.last { $0.type == .cell }?.serial,
                    window: windowIndex,
                    ancestors: Set(path.map(\.serial))
                ))
            }
        }
        // iOS presents its text and context menus in a window of their own,
        // reporting the items as menu items with no menu around them.
        let kind = type == .window && holdsMenuItem(node) ? .menu : type
        let below = path + [Ancestor(type: kind, serial: mine)]
        for (index, child) in node.children.enumerated() {
            collect(child, path: below, screen: screen, windowIndex: windowIndex ?? (path.isEmpty ? index : nil),
                    into: &targets, counts: &counts, rows: &rows)
        }
    }

    private static func holdsMenuItem(_ node: XCUIElementSnapshot) -> Bool {
        node.elementType == .menuItem || node.children.contains(where: holdsMenuItem)
    }

    private static func keyboardTop(_ node: XCUIElementSnapshot) -> CGFloat? {
        if node.elementType == .keyboard, !node.frame.isEmpty { return node.frame.minY }
        for child in node.children {
            if let top = keyboardTop(child) { return top }
        }
        return nil
    }

    private static func describe(_ node: XCUIElementSnapshot) -> String {
        let words = [node.label, node.identifier, (node.value as? String) ?? ""]
            .first { !$0.isEmpty } ?? "unlabelled"
        return "\"\(words.prefix(40))\" (\(kind(node.elementType)))"
    }

    private static func kind(_ type: XCUIElement.ElementType) -> String {
        switch type {
        case .button: return "button"
        case .link: return "link"
        case .switch, .toggle: return "switch"
        case .textField, .secureTextField, .searchField, .textView: return "text field"
        default: return "control"
        }
    }

    /// Edge to edge; negative when the two overlap.
    private static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        if a.intersects(b) {
            let overlap = a.intersection(b)
            return -min(overlap.width, overlap.height)
        }
        let dx = max(0, max(b.minX - a.maxX, a.minX - b.maxX))
        let dy = max(0, max(b.minY - a.maxY, a.minY - b.maxY))
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func points(_ value: CGFloat) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

extension XCTestCase {
    /// Fail with every touch-target problem on the screen, by name.
    public func assertTouchTargets(
        _ app: XCUIApplication,
        screen: String,
        rules: TouchTargetRules = .init(),
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let problems = try TouchTargets.problems(in: app, rules: rules)
            guard !problems.isEmpty else { return }
            XCTFail(
                "\(screen): \(problems.count) touch-target problem\(problems.count == 1 ? "" : "s")\n"
                    + problems.map { "  - \($0)" }.joined(separator: "\n"),
                file: file, line: line
            )
        } catch {
            XCTFail("\(screen): could not read the screen: \(error)", file: file, line: line)
        }
    }
}
