import XCTest
@testable import TenderCore

final class UnifiedLogClientTests: XCTestCase {
    // MARK: - argv

    func testBuildArgumentsEmbedsPredicateAndLastDuration() {
        let args = ProcessUnifiedLogClient.buildArguments(process: "python3", lastSeconds: 3600)
        XCTAssertEqual(args, [
            "show", "--predicate", "process == \"python3\"",
            "--style", "ndjson", "--last", "3600s"
        ])
    }

    // MARK: - levelFromMessageType

    func testLevelMapping() {
        XCTAssertEqual(ProcessUnifiedLogClient.levelFromMessageType("Default"), .default)
        XCTAssertEqual(ProcessUnifiedLogClient.levelFromMessageType("Info"), .info)
        XCTAssertEqual(ProcessUnifiedLogClient.levelFromMessageType("Debug"), .debug)
        XCTAssertEqual(ProcessUnifiedLogClient.levelFromMessageType("Error"), .error)
        XCTAssertEqual(ProcessUnifiedLogClient.levelFromMessageType("Fault"), .fault)
        XCTAssertEqual(ProcessUnifiedLogClient.levelFromMessageType(nil), .unknown)
        XCTAssertEqual(ProcessUnifiedLogClient.levelFromMessageType("Weird"), .unknown)
    }

    func testLevelIsError() {
        XCTAssertTrue(LogLineLevel.error.isError)
        XCTAssertTrue(LogLineLevel.fault.isError)
        XCTAssertFalse(LogLineLevel.default.isError)
        XCTAssertFalse(LogLineLevel.info.isError)
    }

    // MARK: - timestamp

    func testParseTimestampMicroseconds() {
        let date = ProcessUnifiedLogClient.parseTimestamp("2026-04-19 09:39:17.629838+0900")
        XCTAssertNotNil(date)
    }

    func testParseTimestampMillisecondsFallback() {
        let date = ProcessUnifiedLogClient.parseTimestamp("2026-04-19 09:39:17.629+0900")
        XCTAssertNotNil(date)
    }

    func testParseTimestampInvalidReturnsNil() {
        XCTAssertNil(ProcessUnifiedLogClient.parseTimestamp("not a date"))
    }

    // MARK: - ndjson parsing

    func testParsesLogEventLines() {
        let ndjson = #"""
        {"eventType":"logEvent","messageType":"Default","eventMessage":"hello","timestamp":"2026-04-19 09:39:17.629838+0900","processImagePath":"/usr/local/bin/poller","category":"runtime","subsystem":"com.example"}
        {"eventType":"logEvent","messageType":"Error","eventMessage":"boom","timestamp":"2026-04-19 09:39:18.000000+0900","processImagePath":"/usr/local/bin/poller","category":"","subsystem":""}
        """#
        let lines = ProcessUnifiedLogClient.parseNDJSON(ndjson)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].message, "hello")
        XCTAssertEqual(lines[0].level, .default)
        XCTAssertEqual(lines[0].category, "runtime")
        XCTAssertEqual(lines[0].subsystem, "com.example")
        XCTAssertEqual(lines[1].message, "boom")
        XCTAssertEqual(lines[1].level, .error)
        XCTAssertNil(lines[1].category)
        XCTAssertNil(lines[1].subsystem)
    }

    func testSkipsNonLogEventEntries() {
        let ndjson = #"""
        {"eventType":"activityCreateEvent","eventMessage":"ignore me","timestamp":"2026-04-19 09:39:17.629838+0900"}
        {"eventType":"logEvent","messageType":"Default","eventMessage":"keep","timestamp":"2026-04-19 09:39:18.000000+0900"}
        """#
        let lines = ProcessUnifiedLogClient.parseNDJSON(ndjson)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].message, "keep")
    }

    func testSkipsEmptyMessages() {
        let ndjson = #"""
        {"eventType":"logEvent","messageType":"Default","eventMessage":"","timestamp":"2026-04-19 09:39:17.629838+0900"}
        {"eventType":"logEvent","messageType":"Default","eventMessage":"real","timestamp":"2026-04-19 09:39:18.000000+0900"}
        """#
        let lines = ProcessUnifiedLogClient.parseNDJSON(ndjson)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].message, "real")
    }

    func testSkipsMalformedJSON() {
        let ndjson = #"""
        not json
        {"eventType":"logEvent","messageType":"Default","eventMessage":"ok","timestamp":"2026-04-19 09:39:17.629838+0900"}
        """#
        let lines = ProcessUnifiedLogClient.parseNDJSON(ndjson)
        XCTAssertEqual(lines.count, 1)
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertTrue(ProcessUnifiedLogClient.parseNDJSON("").isEmpty)
    }

    // MARK: - MockUnifiedLogClient

    func testMockReturnsEnqueuedLines() async throws {
        let client = MockUnifiedLogClient()
        let sample = [LogLine(timestamp: Date(), message: "test", level: .default)]
        await client.enqueueSuccess(sample)

        let got = try await client.fetch(process: "p", lastSeconds: 60, maxLines: 100)
        XCTAssertEqual(got.count, 1)

        let calls = await client.fetchCalls
        XCTAssertEqual(calls, [.init(process: "p", lastSeconds: 60, maxLines: 100)])
    }

    func testMockPropagatesErrors() async {
        let client = MockUnifiedLogClient()
        await client.enqueueError(UnifiedLogError.timeout)
        do {
            _ = try await client.fetch(process: "p", lastSeconds: 60, maxLines: 100)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? UnifiedLogError, .timeout)
        }
    }
}
