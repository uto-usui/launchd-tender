import XCTest
@testable import TenderCore

final class KeychainDetachTests: XCTestCase {
    private let service = "com.uto-usui.tender"
    private let wrapperDir = URL(fileURLWithPath: "/tmp/wrappers")

    // MARK: - Plan

    func testPlanForManagedAgent() throws {
        let agent = managedAgent()
        let plan = try KeychainDetachPlan.make(
            agent: agent, wrapperDirectory: wrapperDir,
            keychainService: service, deleteKeychainEntries: false
        )
        XCTAssertEqual(plan.restoredProgramArguments, ["/usr/bin/poller", "--once"])
        XCTAssertEqual(plan.wrapperURL.path, "/tmp/wrappers/com.example.job.sh")
        XCTAssertEqual(plan.keychainAccountsToDelete.count, 1)
        XCTAssertEqual(plan.keychainAccountsToDelete[0].account, "com.example.job.GH_TOKEN")
        XCTAssertFalse(plan.deleteKeychainEntries)
    }

    func testPlanRejectsUnmanagedAgent() {
        let agent = LaunchAgent(
            label: "j", programArguments: ["/bin/true"],
            sourcePath: URL(fileURLWithPath: "/tmp/j.plist"),
            tenderManaged: false
        )
        XCTAssertThrowsError(try KeychainDetachPlan.make(
            agent: agent, wrapperDirectory: wrapperDir,
            keychainService: service, deleteKeychainEntries: false
        )) { error in
            XCTAssertEqual(error as? KeychainDetachPlan.MakeError, .notManaged)
        }
    }

    func testPlanRejectsMissingOriginalArgs() {
        let agent = LaunchAgent(
            label: "j", programArguments: ["/bin/bash", "/x.sh"],
            sourcePath: URL(fileURLWithPath: "/tmp/j.plist"),
            tenderManaged: true,
            tenderWrappedEnvs: ["X"],
            tenderOriginalProgramArguments: []
        )
        XCTAssertThrowsError(try KeychainDetachPlan.make(
            agent: agent, wrapperDirectory: wrapperDir,
            keychainService: service, deleteKeychainEntries: false
        )) { error in
            XCTAssertEqual(error as? KeychainDetachPlan.MakeError, .missingOriginalProgramArguments)
        }
    }

    // MARK: - Composer

    func testDetachComposerRestoresProgramArgumentsAndRemovesMetaKeys() throws {
        let originalDict: [String: Any] = [
            "Label": "com.example.job",
            "ProgramArguments": ["/bin/bash", "/tmp/wrappers/com.example.job.sh"],
            "TenderManaged": true,
            "TenderWrappedEnvs": ["GH_TOKEN"],
            "TenderOriginalProgramArguments": ["/usr/bin/poller", "--once"],
            "RunAtLoad": true
        ]
        let original = try PropertyListSerialization.data(
            fromPropertyList: originalDict, format: .xml, options: 0
        )
        let plan = try KeychainDetachPlan.make(
            agent: managedAgent(), wrapperDirectory: wrapperDir,
            keychainService: service, deleteKeychainEntries: false
        )

        let newData = try DetachPlistComposer.compose(originalData: original, plan: plan)
        let dict = try PropertyListSerialization.propertyList(from: newData, options: [], format: nil) as! [String: Any]

        XCTAssertEqual(dict["ProgramArguments"] as? [String], ["/usr/bin/poller", "--once"])
        XCTAssertNil(dict["TenderManaged"])
        XCTAssertNil(dict["TenderWrappedEnvs"])
        XCTAssertNil(dict["TenderOriginalProgramArguments"])
        XCTAssertEqual(dict["RunAtLoad"] as? Bool, true)
    }

    // MARK: - Service

    func testServiceRestoresPlistAndDeletesWrapperButKeepsKeychainByDefault() async throws {
        let fx = try await makeFixture(deleteKeychain: false)
        defer { tearDownFixture(fx) }

        let receipt = try await fx.detachService.execute(plan: fx.plan)

        XCTAssertNotNil(receipt.backup)
        XCTAssertTrue(receipt.wrapperDeleted)
        XCTAssertTrue(receipt.keychainAccountsDeleted.isEmpty)

        // plist が戻っている
        let restoredData = try Data(contentsOf: fx.plistURL)
        let dict = try PropertyListSerialization.propertyList(from: restoredData, options: [], format: nil) as! [String: Any]
        XCTAssertEqual(dict["ProgramArguments"] as? [String], ["/usr/bin/poller", "--once"])
        XCTAssertNil(dict["TenderManaged"])
    }

    func testServiceDeletesKeychainWhenFlagSet() async throws {
        let fx = try await makeFixture(deleteKeychain: true)
        defer { tearDownFixture(fx) }
        await fx.keychain.enqueueDeleteSuccess()

        let receipt = try await fx.detachService.execute(plan: fx.plan)

        XCTAssertEqual(receipt.keychainAccountsDeleted.count, 1)
        XCTAssertEqual(receipt.keychainAccountsDeleted[0].account, "com.example.job.GH_TOKEN")
    }

    // MARK: - Fixture

    private struct Fixture {
        let tmpRoot: URL
        let plistURL: URL
        let wrapperURL: URL
        let keychain: MockKeychainClient
        let detachService: KeychainDetachService
        let plan: KeychainDetachPlan
    }

    private func managedAgent(plistPath: String = "/tmp/com.example.job.plist") -> LaunchAgent {
        LaunchAgent(
            label: "com.example.job",
            programArguments: ["/bin/bash", "/tmp/wrappers/com.example.job.sh"],
            sourcePath: URL(fileURLWithPath: plistPath),
            tenderManaged: true,
            tenderWrappedEnvs: ["GH_TOKEN"],
            tenderOriginalProgramArguments: ["/usr/bin/poller", "--once"]
        )
    }

    private func makeFixture(deleteKeychain: Bool) async throws -> Fixture {
        let tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("tender-detach-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)

        let plistURL = tmpRoot.appendingPathComponent("com.example.job.plist")
        let wrapperDir = tmpRoot.appendingPathComponent("wrappers", isDirectory: true)
        try FileManager.default.createDirectory(at: wrapperDir, withIntermediateDirectories: true)
        let wrapperURL = wrapperDir.appendingPathComponent("com.example.job.sh")
        try "#!/bin/bash\nexec /usr/bin/poller --once\n".write(to: wrapperURL, atomically: true, encoding: .utf8)

        let agent = managedAgent(plistPath: plistURL.path)
        // wrapper が既に存在する状態の plist を書く
        let dict: [String: Any] = [
            "Label": agent.label,
            "ProgramArguments": ["/bin/bash", wrapperURL.path],
            "TenderManaged": true,
            "TenderWrappedEnvs": ["GH_TOKEN"],
            "TenderOriginalProgramArguments": ["/usr/bin/poller", "--once"],
            "RunAtLoad": true
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: plistURL)

        let plan = try KeychainDetachPlan.make(
            agent: agent, wrapperDirectory: wrapperDir,
            keychainService: service, deleteKeychainEntries: deleteKeychain
        )

        let keychain = MockKeychainClient()
        let plistWriter = PlistAtomicWriter(
            backupsRootURL: tmpRoot.appendingPathComponent("backups", isDirectory: true),
            clock: { Date(timeIntervalSince1970: 1_000_000_000) }
        )
        let fileWriter = FileSystemWrapperFileWriter()
        let detachService = KeychainDetachService(
            keychain: keychain, plistWriter: plistWriter, fileWriter: fileWriter
        )

        return Fixture(
            tmpRoot: tmpRoot, plistURL: plistURL, wrapperURL: wrapperURL,
            keychain: keychain, detachService: detachService, plan: plan
        )
    }

    private func tearDownFixture(_ fx: Fixture) {
        try? FileManager.default.removeItem(at: fx.tmpRoot)
    }
}
