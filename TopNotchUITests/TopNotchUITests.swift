//
//  TopNotchUITests.swift
//  TopNotchUITests
//
//  Created by Yash Sharma on 28/04/26.
//

import XCTest

final class TopNotchUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it's important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    /// TopNotch is an LSUIElement app: no Dock icon, no window, the notch panel is
    /// the whole UI. So the meaningful smoke test is that it launches and keeps
    /// running, not that a window appeared.
    @MainActor
    func testLaunchesAndStaysRunning() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10) || app.state == .runningBackground,
                      "app did not reach a running state")
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertNotEqual(app.state, .notRunning, "app exited shortly after launch")
    }

}
