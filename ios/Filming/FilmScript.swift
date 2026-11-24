// FilmScript: a product film's storyboard (video-tools' product-video grammar)
// played by a UI test while the simulator records.
//
// A product whose picture is MapKit, SwiftUI springs and UIKit transitions
// cannot draw itself one frame at a time: those run on the wall clock. So the
// test is the frame source. It plays each `"do"` gesture of the storyboard at
// its moment, measured from when the recording is rolling, and says where each
// `"camera"` move is aimed, by asking the screen. video-tools' ui-test-film
// records it with sim-film, cuts the recording at the film's zero, and hands
// the frames to product-video.
//
//     import Filming
//
//     try playFilm(in: app) { step in
//         switch step {
//         case "back": pressByHand(app.buttons["back"])
//         default: XCTFail("no gesture \"\(step)\"")
//         }
//     }
//
// A gesture takes as long as the simulator takes -- one to three seconds on a
// loaded Mac -- so the film is cut rather than played in real time: each touch
// is put on its beat by dropping the still moment before it.
//
// It reads FILM_BOARD (the storyboard) and FILM_MARK (sim-film's mark), and
// writes FILM_MARK.log: the film's zero in seconds of recording, the app's
// size in points, when each gesture began and ended, its film moment and its
// lead (how long before it lands its touch starts), and where each camera
// move's place was, in the app's points, top-left origin.
// Without FILM_BOARD it does nothing, so the test runs unfilmed.

import XCTest

public struct FilmScript {
    public struct Gesture {
        public let at: TimeInterval
        public let step: String
        /// How many times slower the app plays the stretch from this gesture to
        /// the next, in a film, so a loaded simulator draws every frame of it
        /// (the app reads it at filmPacePath). The test holds the stretch that
        /// much longer, and ui-test-film plays it back that much faster.
        public let slow: Double
    }

    public struct Move {
        public let at: TimeInterval
        public let to: Double
        public let seconds: TimeInterval
        /// An accessibility identifier, or failing that a label.
        public let place: String
    }

    public let seconds: TimeInterval
    /// How many times slower the app plays the whole film, unless a gesture
    /// says otherwise for the stretch after it: the storyboard's `"slow"`, or 1.
    public let slow: Double
    public let gestures: [Gesture]
    public let moves: [Move]

    public init(path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let board = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FilmError.unreadable(path)
        }
        let events = (board["events"] as? [[String: Any]] ?? [])
        seconds = Self.number(board["seconds"]) ?? 30
        let slow = Self.number(board["slow"]) ?? 1
        self.slow = slow
        gestures = events.compactMap { event in
            guard let step = event["do"] as? String, let at = Self.number(event["at"]) else { return nil }
            return Gesture(at: at, step: step, slow: Self.number(event["slow"]) ?? slow)
        }.sorted { $0.at < $1.at }
        moves = try events.compactMap { event in
            guard let camera = event["camera"] as? [String: Any], let at = Self.number(event["at"]) else { return nil }
            guard let place = camera["at"] as? String else { throw FilmError.aimless(at) }
            return Move(at: at, to: Self.number(camera["to"]) ?? 1,
                        seconds: Self.number(camera["seconds"]) ?? 1, place: place)
        }.sorted { $0.at < $1.at }
    }

    static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}

public enum FilmError: Error, CustomStringConvertible {
    case unreadable(String)
    case aimless(TimeInterval)
    case nowhere(String, TimeInterval)
    case notRolling

    public var description: String {
        switch self {
        case .unreadable(let path): "could not read the storyboard at \(path)"
        case .aimless(let at): "the camera move at \(at)s does not say where it is aimed"
        case .nowhere(let place, let at):
            "the camera move at \(at)s is aimed at \"\(place)\", which nothing on screen is called"
        case .notRolling: "sim-film never said the recording was rolling"
        }
    }
}

extension XCTestCase {
    /// How long after the recording rolls the film's zero is: the first
    /// frames of a simulator recording are its encoder starting up.
    public static let filmLeadIn: TimeInterval = 1.0

    /// Plays the storyboard in FILM_BOARD against APP: marks the start, waits
    /// for the recording, then begins each gesture LEAD seconds before its
    /// moment (a press is held before it lands), aims each camera move at what
    /// the screen calls its place, and marks the end when the film is over.
    public func playFilm(in app: XCUIApplication,
                         lead: (String) -> TimeInterval = { _ in 0 },
                         perform: (String) throws -> Void) throws {
        let environment = ProcessInfo.processInfo.environment
        guard let board = environment["FILM_BOARD"] else { return }
        let script = try FilmScript(path: board)
        Self.skipQuiescence()
        try Self.setFilmPace(script.slow)
        try filmMark("start")
        let rolling = try filmRolling()
        let zero = rolling + Self.filmLeadIn
        let size = app.windows.firstMatch.frame.size

        var gestures: [[String: Any]] = []
        var camera: [[String: Any]] = []
        var pendingMoves = script.moves[...]

        func aim(until time: TimeInterval) throws {
            while let move = pendingMoves.first, move.at <= time {
                pendingMoves.removeFirst()
                guard let box = settledPlace(move.place, in: app) else { throw FilmError.nowhere(move.place, move.at) }
                camera.append(["at": move.at, "place": move.place, "x": box.midX, "y": box.midY])
            }
        }

        // A gesture takes as long as the simulator takes, so the film is cut, not
        // played in real time: each gesture's touch is at `at - lead` in the film
        // and at `ended - lead` in the recording, and the recording between one
        // touch and the next is at least as long as the film's, so the cut before
        // a touch only ever drops a moment of the screen standing still.
        var lastFilm: TimeInterval = 0, lastRecording: TimeInterval = 0, lastSlow = script.slow
        for gesture in script.gestures {
            // LEAD is the recording's seconds from touch to landing; a slowed film
            // shows them that many times shorter.
            let touch = gesture.at - lead(gesture.step) / gesture.slow
            try aim(until: touch)
            let begin = max(touch, lastRecording + (touch - lastFilm) * lastSlow)
            wait(until: zero + begin)
            let began = Date().timeIntervalSince1970 - zero
            try Self.setFilmPace(gesture.slow)
            try perform(gesture.step)
            let ended = Date().timeIntervalSince1970 - zero
            lastFilm = touch
            lastSlow = gesture.slow
            lastRecording = max(ended - lead(gesture.step), began)
            gestures.append(["at": gesture.at, "do": gesture.step, "touch": touch, "began": began,
                             "ended": ended, "cut": lastRecording, "slow": gesture.slow])
        }
        try aim(until: script.seconds)
        // Half a second over, so the cut never runs a frame short of the end.
        wait(until: zero + lastRecording + (script.seconds - lastFilm) * lastSlow + 0.5)
        try filmMark("end")

        guard let mark = environment["FILM_MARK"] else { return }
        let log: [String: Any] = ["zero": zero - rolling, "width": size.width, "height": size.height,
                                  "gestures": gestures, "camera": camera]
        try JSONSerialization.data(withJSONObject: log, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: "\(mark).log"))
    }

    /// Where the app reads how many times slower it is to play right now: pass
    /// it to the app as FILM_PACE. playFilm writes each stretch's `"slow"` there
    /// as the stretch begins; an app that paces its own clocks and animations by
    /// it gives a loaded simulator that many times the wall time per frame.
    public static var filmPacePath: String? {
        ProcessInfo.processInfo.environment["FILM_MARK"].map { "\($0).pace" }
    }

    private static func setFilmPace(_ slow: Double) throws {
        guard let path = filmPacePath else { return }
        try "\(slow)".write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// When sim-film's recording began, in seconds since 1970: it writes the
    /// moment `simctl io recordVideo` says it is recording beside the mark.
    public func filmRolling(timeout: TimeInterval = 30) throws -> TimeInterval {
        guard let mark = ProcessInfo.processInfo.environment["FILM_MARK"] else {
            return Date().timeIntervalSince1970
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let said = try? String(contentsOfFile: "\(mark).rolling", encoding: .utf8),
               let rolling = TimeInterval(said.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return rolling
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw FilmError.notRolling
    }

    /// Where PLACE is once it has stopped moving: a page still sliding in
    /// would aim the camera where the thing is passing through.
    public func settledPlace(_ name: String, in app: XCUIApplication, timeout: TimeInterval = 20) -> CGRect? {
        let deadline = Date().addingTimeInterval(timeout)
        var last = place(name, in: app)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            let now = place(name, in: app)
            if let now, let was = last, abs(now.midX - was.midX) < 1, abs(now.midY - was.midY) < 1 { return now }
            last = now
        }
        return last
    }

    /// Where PLACE is on screen, in the app's points: the element with that
    /// identifier, or else the one with that label.
    public func place(_ name: String, in app: XCUIApplication) -> CGRect? {
        let everything = app.descendants(matching: .any)
        for query in [everything.matching(identifier: name),
                      everything.matching(NSPredicate(format: "label == %@", name))] {
            let found = query.firstMatch
            if found.exists, !found.frame.isEmpty { return found.frame }
        }
        return nil
    }

    /// A gesture normally waits for the app to go idle before and after it.
    /// An app with a live map or a running animation is seldom idle, and a tap
    /// waited seconds for it, so a filmed test played each gesture late. While
    /// a film plays, XCUIAutomation's own switches for skipping those waits
    /// are on.
    private static func skipQuiescence() {
        guard let process = NSClassFromString("XCUIApplicationProcess") else { return }
        let yes: @convention(block) (AnyObject) -> Bool = { _ in true }
        for name in ["shouldSkipPreEventQuiescence", "shouldSkipPostEventQuiescence"] {
            guard let method = class_getInstanceMethod(process, NSSelectorFromString(name)) else { continue }
            method_setImplementation(method, imp_implementationWithBlock(yes))
        }
    }

    private func wait(until moment: TimeInterval) {
        let left = moment - Date().timeIntervalSince1970
        if left > 0 { Thread.sleep(forTimeInterval: left) }
    }
}
