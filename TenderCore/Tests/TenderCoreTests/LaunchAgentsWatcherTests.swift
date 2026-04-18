import XCTest
@testable import TenderCore

final class LaunchAgentsWatcherTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tender-watcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testDetectsNewFile() async throws {
        let watcher = LaunchAgentsWatcher(directoryURL: tempDir)
        let expectation = expectation(description: "change detected on new file")
        expectation.assertForOverFulfill = false

        watcher.start {
            expectation.fulfill()
        }

        // 監視開始直後の自己トリガーを避けるため少し待つ
        try await Task.sleep(for: .milliseconds(100))
        try Data("hello".utf8).write(to: tempDir.appendingPathComponent("new.plist"))

        await fulfillment(of: [expectation], timeout: 2.0)
        watcher.stop()
    }

    func testDetectsFileDeletion() async throws {
        let target = tempDir.appendingPathComponent("existing.plist")
        try Data("hello".utf8).write(to: target)

        let watcher = LaunchAgentsWatcher(directoryURL: tempDir)
        let expectation = expectation(description: "change detected on delete")
        expectation.assertForOverFulfill = false

        watcher.start {
            expectation.fulfill()
        }

        try await Task.sleep(for: .milliseconds(100))
        try FileManager.default.removeItem(at: target)

        await fulfillment(of: [expectation], timeout: 2.0)
        watcher.stop()
    }

    func testNoCallbackAfterStop() async throws {
        let watcher = LaunchAgentsWatcher(directoryURL: tempDir)
        let counter = CallCounter()

        watcher.start {
            counter.increment()
        }

        try await Task.sleep(for: .milliseconds(100))
        watcher.stop()

        // stop 後のイベントを捕捉しないことを確認
        try await Task.sleep(for: .milliseconds(100))
        try Data("hello".utf8).write(to: tempDir.appendingPathComponent("after-stop.plist"))

        // イベントが background queue で流れる可能性を考慮して少し待つ
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(counter.value, 0, "handler should not be called after stop()")
    }

    func testStartOnNonexistentDirectoryDoesNotCrash() async throws {
        let missing = tempDir.appendingPathComponent("does-not-exist", isDirectory: true)
        let watcher = LaunchAgentsWatcher(directoryURL: missing)

        // クラッシュせず、コールバックも呼ばれないことだけ確認
        let counter = CallCounter()
        watcher.start {
            counter.increment()
        }

        try await Task.sleep(for: .milliseconds(200))
        watcher.stop()

        XCTAssertEqual(counter.value, 0)
    }

    func testDoubleStopIsSafe() async throws {
        let watcher = LaunchAgentsWatcher(directoryURL: tempDir)
        watcher.start { }
        watcher.stop()
        watcher.stop()  // 二回呼んでもクラッシュしない
    }
}

/// イベント回数をスレッドセーフにカウントするヘルパー。
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func increment() {
        lock.lock()
        _value += 1
        lock.unlock()
    }
}
