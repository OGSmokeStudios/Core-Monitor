import Foundation
import XCTest
@testable import Core_Monitor

@MainActor
final class HelperXPCClientTests: XCTestCase {
    func testRequestsUseRealXPCAndReuseTheSession() async throws {
        let delegate = TestHelperListener()
        let listener = NSXPCListener.anonymous()
        listener.delegate = delegate
        listener.resume()
        defer { listener.invalidate() }
        let client = HelperXPCClient { NSXPCConnection(listenerEndpoint: listener.endpoint) }
        defer { client.disconnect() }

        for _ in 0..<2 {
            let count: Int = try await client.request(timeout: 3) { proxy, finish in
                proxy.readValue("FNum") { value, error in finish(value?.intValue, error as String?) }
            }
            XCTAssertEqual(count, 2)
        }
        XCTAssertEqual(delegate.connectionCount, 1)
    }

    func testTimeoutDoesNotBlockMainActorAndLateReplyIsIgnored() async throws {
        let delegate = TestHelperListener()
        let listener = NSXPCListener.anonymous()
        listener.delegate = delegate
        listener.resume()
        defer { withExtendedLifetime(delegate) { listener.invalidate() } }
        let client = HelperXPCClient { NSXPCConnection(listenerEndpoint: listener.endpoint) }
        var finishRequest: ((Int?, String?) -> Void)?
        let started = expectation(description: "Request started")
        let pending = Task { @MainActor in
            try await client.request(timeout: 0.2) { _, finish in
                finishRequest = finish
                started.fulfill()
            } as Int
        }
        await fulfillment(of: [started], timeout: 1)
        // Main-actor code runs while the request is still waiting.
        XCTAssertTrue(client.isConnected)
        do { _ = try await pending.value; XCTFail("Expected timeout") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Timed out")) }
        XCTAssertFalse(client.isConnected)
        finishRequest?(3, nil)
        await Task.yield()
    }

    func testDisconnectCompletesAnOutstandingRequest() async {
        let delegate = TestHelperListener()
        let listener = NSXPCListener.anonymous()
        listener.delegate = delegate
        listener.resume()
        defer { withExtendedLifetime(delegate) { listener.invalidate() } }
        let client = HelperXPCClient { NSXPCConnection(listenerEndpoint: listener.endpoint) }
        let started = expectation(description: "Request started")
        let pending = Task { @MainActor in
            try await client.request(timeout: 3) { _, _ in started.fulfill() } as Int
        }
        await fulfillment(of: [started], timeout: 1)
        client.disconnect(reason: "Test shutdown")
        do { _ = try await pending.value; XCTFail("Expected disconnect") }
        catch { XCTAssertEqual(error.localizedDescription, "Test shutdown") }
    }
}

private final class TestHelperListener: NSObject, NSXPCListenerDelegate {
    private let lock = NSLock()
    private var count = 0
    var connectionCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        lock.lock(); count += 1; lock.unlock()
        connection.exportedInterface = NSXPCInterface(with: SMCHelperXPCProtocol.self)
        connection.exportedObject = TestHelperSession()
        connection.resume()
        return true
    }
}

private final class TestHelperSession: NSObject, SMCHelperXPCProtocol {
    func readSafetyVersion(withReply reply: @escaping (NSNumber) -> Void) { reply(1) }
    func renewControlLease(withReply reply: @escaping (NSNumber, NSString?) -> Void) { reply(true, nil) }
    func setFanManual(_ fanID: Int, rpm: Int, withReply reply: @escaping (NSString?) -> Void) { reply(nil) }
    func setFanAuto(_ fanID: Int, withReply reply: @escaping (NSString?) -> Void) { reply(nil) }
    func readValue(_ key: String, withReply reply: @escaping (NSNumber?, NSString?) -> Void) { reply(2, nil) }
    func readControlMetadata(withReply reply: @escaping (NSString?, NSNumber?, NSString?) -> Void) { reply("F%dMd", false, nil) }
}
