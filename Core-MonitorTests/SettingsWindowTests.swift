import AppKit
import SwiftUI
import XCTest
@testable import Core_Monitor

@MainActor
final class SettingsWindowTests: XCTestCase {
    func testRequestedTabUpdatesExistingWindowAndHostedSelection() throws {
        let manager = SettingsWindowManager(startupManager: StartupManager())
        manager.show(tab: .general)
        let window = try XCTUnwrap(manager.window)
        defer { window.close() }
        let host = try XCTUnwrap(window.contentViewController as? NSHostingController<SettingsView>)

        XCTAssertEqual(host.rootView.selection.tab, .general)
        // Simulate a user selecting a tab before another entry point opens Settings.
        host.rootView.selection.tab = .menuBar
        manager.show(tab: .touchBar)

        XCTAssertTrue(manager.window === window)
        XCTAssertEqual(host.rootView.selection.tab, .touchBar)

        manager.show(tab: .about)
        XCTAssertEqual(host.rootView.selection.tab, .about)
    }

    func testReopenedWindowUsesRequestedTab() throws {
        let manager = SettingsWindowManager(startupManager: StartupManager())
        manager.show(tab: .touchBar)
        let firstWindow = try XCTUnwrap(manager.window)
        firstWindow.close()
        XCTAssertNil(manager.window)

        manager.show(tab: .menuBar)
        let reopenedWindow = try XCTUnwrap(manager.window)
        defer { reopenedWindow.close() }
        let host = try XCTUnwrap(reopenedWindow.contentViewController as? NSHostingController<SettingsView>)

        XCTAssertFalse(reopenedWindow === firstWindow)
        XCTAssertEqual(host.rootView.selection.tab, .menuBar)
    }
}
