import XCTest
@testable import TenderCore

final class MockKeychainClientTests: XCTestCase {
    func testAddAndRecordCall() async throws {
        let client = MockKeychainClient()
        await client.enqueueAddSuccess()

        try await client.add(service: "com.uto-usui.tender", account: "job.GH_TOKEN",
                             password: "ghp_xxx", overwrite: true)

        let calls = await client.recordedCalls()
        XCTAssertEqual(calls, [.add(.init(service: "com.uto-usui.tender", account: "job.GH_TOKEN"),
                                     password: "ghp_xxx", overwrite: true)])
    }

    func testFindReturnsEnqueuedPassword() async throws {
        let client = MockKeychainClient()
        await client.enqueueFindSuccess(password: "secret-value")

        let found = try await client.find(service: "s", account: "a")

        XCTAssertEqual(found, "secret-value")
    }

    func testDeleteRecordsCall() async throws {
        let client = MockKeychainClient()
        await client.enqueueDeleteSuccess()

        try await client.delete(service: "s", account: "a")

        let calls = await client.recordedCalls()
        XCTAssertEqual(calls, [.delete(.init(service: "s", account: "a"))])
    }

    func testErrorPropagates() async {
        let client = MockKeychainClient()
        await client.enqueueError(.notFound)

        do {
            _ = try await client.find(service: "s", account: "a")
            XCTFail("expected to throw")
        } catch let error as KeychainError {
            XCTAssertEqual(error, .notFound)
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testMixedSequencePreservesOrder() async throws {
        let client = MockKeychainClient()
        await client.enqueueAddSuccess()
        await client.enqueueFindSuccess(password: "p1")
        await client.enqueueDeleteSuccess()

        try await client.add(service: "s", account: "a1", password: "x", overwrite: false)
        let got = try await client.find(service: "s", account: "a2")
        try await client.delete(service: "s", account: "a3")

        XCTAssertEqual(got, "p1")
        let calls = await client.recordedCalls()
        XCTAssertEqual(calls.count, 3)
    }

    func testDuplicateItemErrorPropagates() async {
        let client = MockKeychainClient()
        await client.enqueueError(.duplicateItem)
        do {
            try await client.add(service: "s", account: "a", password: "p", overwrite: false)
            XCTFail("expected to throw")
        } catch let error as KeychainError {
            XCTAssertEqual(error, .duplicateItem)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
