// HostScreenshot: have the Mac photograph the simulator's screen, for a
// display XCUITest photographs as solid black (iPhone Duo's inner display).
// bin/host-shots answers each request with `simctl io screenshot`.
//
//     import TouchTargets
//
//     hostScreenshot("appstore-1-home")    // DIR/appstore-1-home.png on the Mac
//
// The test run gets DIR from TEST_RUNNER_HOST_SHOTS. Without it the call does
// nothing and returns false, so one test serves every display.

import XCTest

@discardableResult
public func hostScreenshot(_ name: String, timeout: TimeInterval = 30,
                           file: StaticString = #filePath, line: UInt = #line) -> Bool {
    guard let dir = ProcessInfo.processInfo.environment["HOST_SHOTS"], !dir.isEmpty else { return false }
    let folder = URL(fileURLWithPath: dir)
    let picture = folder.appendingPathComponent("\(name).png")
    try? FileManager.default.removeItem(at: picture)
    do {
        try Data().write(to: folder.appendingPathComponent("\(name).request"), options: .atomic)
    } catch {
        XCTFail("host-shots: cannot ask for \(name) in \(dir): \(error)", file: file, line: line)
        return false
    }
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: picture.path) { return true }
        usleep(100_000)
    }
    XCTFail("host-shots: no \(name).png in \(dir) after \(Int(timeout)) s; is bin/host-shots running?", file: file, line: line)
    return false
}
