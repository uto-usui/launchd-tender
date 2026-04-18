import XCTest
@testable import TenderCore

final class KeychainMigrationServiceTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 0)
    private let keychainService = "com.uto-usui.tender"

    // MARK: - Helpers

    /// tmp ディレクトリと既存 plist ファイルを作り、plan と service を組み立てる。
    private struct Fixture {
        let tmpRoot: URL
        let plistURL: URL
        let wrapperDir: URL
        let backupsRoot: URL
        let agent: LaunchAgent
        let keychain: MockKeychainClient
        let fileWriter: InMemoryWrapperFileWriter
        let service: KeychainMigrationService
    }

    private func makeFixture(
        envToMigrate: [String] = ["GH_TOKEN"],
        envs: [String: String] = ["GH_TOKEN": "ghp_xxx", "SENTRY_DSN": "https://e"]
    ) throws -> Fixture {
        let tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("tender-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)

        let plistURL = tmpRoot.appendingPathComponent("com.example.job.plist")
        let wrapperDir = tmpRoot.appendingPathComponent("wrappers", isDirectory: true)
        let backupsRoot = tmpRoot.appendingPathComponent("backups", isDirectory: true)

        // 既存 plist を書く
        let plistDict: [String: Any] = [
            "Label": "com.example.job",
            "ProgramArguments": ["/usr/bin/poller", "--once"],
            "EnvironmentVariables": envs,
            "RunAtLoad": true
        ]
        let originalData = try PropertyListSerialization.data(
            fromPropertyList: plistDict, format: .xml, options: 0
        )
        try originalData.write(to: plistURL)

        let agent = LaunchAgent(
            label: "com.example.job",
            programArguments: ["/usr/bin/poller", "--once"],
            environmentVariables: envs,
            sourcePath: plistURL
        )

        let keychain = MockKeychainClient()
        let fileWriter = InMemoryWrapperFileWriter()
        let plistWriter = PlistAtomicWriter(backupsRootURL: backupsRoot, clock: { Date(timeIntervalSince1970: 1_000_000_000) })
        let service = KeychainMigrationService(
            keychain: keychain, plistWriter: plistWriter, fileWriter: fileWriter
        )

        return Fixture(
            tmpRoot: tmpRoot, plistURL: plistURL, wrapperDir: wrapperDir,
            backupsRoot: backupsRoot, agent: agent,
            keychain: keychain, fileWriter: fileWriter, service: service
        )
    }

    private func tearDownFixture(_ fx: Fixture) {
        try? FileManager.default.removeItem(at: fx.tmpRoot)
    }

    private func makePlan(from fx: Fixture, selectedEnvs: [String] = ["GH_TOKEN"]) throws -> KeychainMigrationPlan {
        try KeychainMigrationPlan.make(
            agent: fx.agent, selectedEnvs: selectedEnvs,
            wrapperDirectory: fx.wrapperDir, keychainService: keychainService, now: epoch
        )
    }

    // MARK: - Happy path

    func testHappyPathWritesAllArtifacts() async throws {
        let fx = try makeFixture()
        defer { tearDownFixture(fx) }
        await fx.keychain.enqueueAddSuccess()

        let plan = try makePlan(from: fx)
        let receipt = try await fx.service.execute(plan: plan)

        // Keychain
        let keychainCalls = await fx.keychain.recordedCalls()
        XCTAssertEqual(keychainCalls.count, 1)

        // Wrapper
        let written = await fx.fileWriter.written
        XCTAssertEqual(written.count, 1)
        XCTAssertNotNil(written[plan.wrapperURL])
        XCTAssertTrue(written[plan.wrapperURL]!.contains("exec '/usr/bin/poller' '--once'"))

        // Plist rewritten
        let newPlistData = try Data(contentsOf: fx.plistURL)
        let newDict = try PropertyListSerialization.propertyList(from: newPlistData, options: [], format: nil) as! [String: Any]
        XCTAssertEqual(newDict["ProgramArguments"] as? [String], ["/bin/bash", plan.wrapperURL.path])
        XCTAssertEqual(newDict["TenderManaged"] as? Bool, true)

        // Backup exists
        XCTAssertNotNil(receipt.backup)
        XCTAssertEqual(receipt.backup?.label, "com.example.job")
    }

    func testHappyPathReturnsAllAddedAccounts() async throws {
        let fx = try makeFixture(
            envToMigrate: ["A", "B"],
            envs: ["A": "a-val", "B": "b-val"]
        )
        defer { tearDownFixture(fx) }
        await fx.keychain.enqueueAddSuccess()
        await fx.keychain.enqueueAddSuccess()

        let plan = try makePlan(from: fx, selectedEnvs: ["A", "B"])
        let receipt = try await fx.service.execute(plan: plan)

        XCTAssertEqual(receipt.writtenAccounts.count, 2)
    }

    // MARK: - Rollback

    func testRollbackOnWrapperWriteFailure() async throws {
        let fx = try makeFixture()
        defer { tearDownFixture(fx) }
        await fx.keychain.enqueueAddSuccess()
        await fx.fileWriter.enqueueWriteError(NSError(domain: "test", code: 1))
        await fx.keychain.enqueueDeleteSuccess() // rollback 削除用

        let plan = try makePlan(from: fx)

        do {
            _ = try await fx.service.execute(plan: plan)
            XCTFail("expected to throw")
        } catch {
            // 期待: Keychain 追加分が delete 呼び出しで rollback されている
        }

        let deletes = await fx.keychain.recordedCalls().filter {
            if case .delete = $0 { return true } else { return false }
        }
        XCTAssertEqual(deletes.count, 1)

        // wrapper は書かれていない
        let written = await fx.fileWriter.written
        XCTAssertTrue(written.isEmpty)

        // plist は元のまま
        let plistData = try Data(contentsOf: fx.plistURL)
        let dict = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as! [String: Any]
        XCTAssertNil(dict["TenderManaged"])
        XCTAssertEqual(dict["ProgramArguments"] as? [String], ["/usr/bin/poller", "--once"])
    }

    func testRollbackOnKeychainAddFailure() async throws {
        let fx = try makeFixture()
        defer { tearDownFixture(fx) }
        await fx.keychain.enqueueError(.commandFailed(exitCode: 1, stderr: "boom"))

        let plan = try makePlan(from: fx)
        do {
            _ = try await fx.service.execute(plan: plan)
            XCTFail("expected to throw")
        } catch {}

        // wrapper は書かれていない、plist も変更なし
        let written = await fx.fileWriter.written
        XCTAssertTrue(written.isEmpty)

        let plistData = try Data(contentsOf: fx.plistURL)
        let dict = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as! [String: Any]
        XCTAssertNil(dict["TenderManaged"])
    }

    func testRollbackDeletesInReverseOrder() async throws {
        let fx = try makeFixture(
            envToMigrate: ["A", "B"],
            envs: ["A": "a-val", "B": "b-val"]
        )
        defer { tearDownFixture(fx) }
        // 2 件追加 → wrapper で失敗
        await fx.keychain.enqueueAddSuccess()
        await fx.keychain.enqueueAddSuccess()
        await fx.fileWriter.enqueueWriteError(NSError(domain: "test", code: 1))
        await fx.keychain.enqueueDeleteSuccess()
        await fx.keychain.enqueueDeleteSuccess()

        let plan = try makePlan(from: fx, selectedEnvs: ["A", "B"])
        do {
            _ = try await fx.service.execute(plan: plan)
            XCTFail("expected throw")
        } catch {}

        let calls = await fx.keychain.recordedCalls()
        let addAccounts = calls.compactMap { call -> String? in
            if case let .add(kc, _, _) = call { return kc.account } else { return nil }
        }
        let deleteAccounts = calls.compactMap { call -> String? in
            if case let .delete(kc) = call { return kc.account } else { return nil }
        }
        XCTAssertEqual(addAccounts.count, 2)
        XCTAssertEqual(deleteAccounts, Array(addAccounts.reversed()))
    }
}
