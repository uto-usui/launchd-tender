import XCTest
@testable import TenderCore

final class KeychainMigrationPlanTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 0)
    private let wrapperDir = URL(fileURLWithPath: "/tmp/wrappers")
    private let service = "com.uto-usui.tender"

    private func makeAgent(
        env: [String: String] = ["GH_TOKEN": "ghp_xxx", "SENTRY_DSN": "https://example"],
        argv: [String] = ["/usr/bin/poller", "--once"]
    ) -> LaunchAgent {
        LaunchAgent(
            label: "com.example.job",
            programArguments: argv,
            environmentVariables: env,
            sourcePath: URL(fileURLWithPath: "/tmp/com.example.job.plist")
        )
    }

    func testPlanForSingleEnv() throws {
        let plan = try KeychainMigrationPlan.make(
            agent: makeAgent(), selectedEnvs: ["GH_TOKEN"],
            wrapperDirectory: wrapperDir, keychainService: service, now: epoch
        )

        XCTAssertEqual(plan.wrapperURL.path, "/tmp/wrappers/com.example.job.sh")
        XCTAssertEqual(plan.keychainWrites, [
            .init(service: service, account: "com.example.job.GH_TOKEN", password: "ghp_xxx")
        ])
        XCTAssertEqual(plan.newProgramArguments, ["/bin/bash", "/tmp/wrappers/com.example.job.sh"])
        // 選択されていない SENTRY_DSN は残る
        XCTAssertEqual(plan.newEnvironmentVariables, ["SENTRY_DSN": "https://example"])
    }

    func testPlanMetaKeysRecordOriginal() throws {
        let plan = try KeychainMigrationPlan.make(
            agent: makeAgent(), selectedEnvs: ["GH_TOKEN"],
            wrapperDirectory: wrapperDir, keychainService: service, now: epoch
        )
        XCTAssertTrue(plan.metaKeys.tenderManaged)
        XCTAssertEqual(plan.metaKeys.tenderWrappedEnvs, ["GH_TOKEN"])
        XCTAssertEqual(plan.metaKeys.tenderOriginalProgramArguments, ["/usr/bin/poller", "--once"])
    }

    func testPlanMetaKeysAsDictionary() throws {
        let plan = try KeychainMigrationPlan.make(
            agent: makeAgent(), selectedEnvs: ["GH_TOKEN"],
            wrapperDirectory: wrapperDir, keychainService: service, now: epoch
        )
        let dict = plan.metaKeys.asDictionary
        XCTAssertEqual(dict["TenderManaged"] as? Bool, true)
        XCTAssertEqual(dict["TenderWrappedEnvs"] as? [String], ["GH_TOKEN"])
        XCTAssertEqual(dict["TenderOriginalProgramArguments"] as? [String], ["/usr/bin/poller", "--once"])
    }

    func testPlanForMultipleEnvs() throws {
        let plan = try KeychainMigrationPlan.make(
            agent: makeAgent(env: ["A": "a-val", "B": "b-val"]),
            selectedEnvs: ["A", "B"],
            wrapperDirectory: wrapperDir, keychainService: service, now: epoch
        )
        XCTAssertEqual(plan.keychainWrites.count, 2)
        XCTAssertTrue(plan.keychainWrites.contains(.init(service: service, account: "com.example.job.A", password: "a-val")))
        XCTAssertTrue(plan.keychainWrites.contains(.init(service: service, account: "com.example.job.B", password: "b-val")))
        XCTAssertTrue(plan.newEnvironmentVariables.isEmpty)
    }

    func testWrapperScriptEmbedsExpectedLines() throws {
        let plan = try KeychainMigrationPlan.make(
            agent: makeAgent(), selectedEnvs: ["GH_TOKEN"],
            wrapperDirectory: wrapperDir, keychainService: service, now: epoch
        )
        XCTAssertTrue(plan.wrapperScript.contains(
            "export GH_TOKEN=\"$(security find-generic-password -s 'com.uto-usui.tender' -a 'com.example.job.GH_TOKEN' -w)\""
        ))
        XCTAssertTrue(plan.wrapperScript.contains("exec '/usr/bin/poller' '--once'"))
    }

    func testEmptySelectionThrows() {
        XCTAssertThrowsError(try KeychainMigrationPlan.make(
            agent: makeAgent(), selectedEnvs: [],
            wrapperDirectory: wrapperDir, keychainService: service, now: epoch
        )) { error in
            XCTAssertEqual(error as? KeychainMigrationPlan.MakeError, .emptySelection)
        }
    }

    func testUnknownEnvKeyThrows() {
        XCTAssertThrowsError(try KeychainMigrationPlan.make(
            agent: makeAgent(), selectedEnvs: ["MISSING"],
            wrapperDirectory: wrapperDir, keychainService: service, now: epoch
        )) { error in
            XCTAssertEqual(error as? KeychainMigrationPlan.MakeError, .unknownEnvKey("MISSING"))
        }
    }

    func testMissingSourcePathThrows() {
        let agent = LaunchAgent(
            label: "j", programArguments: ["/bin/true"],
            environmentVariables: ["X": "y"], sourcePath: nil
        )
        XCTAssertThrowsError(try KeychainMigrationPlan.make(
            agent: agent, selectedEnvs: ["X"],
            wrapperDirectory: wrapperDir, keychainService: service, now: epoch
        )) { error in
            XCTAssertEqual(error as? KeychainMigrationPlan.MakeError, .missingSourcePath)
        }
    }

    func testEmptyProgramArgumentsThrows() {
        let agent = LaunchAgent(
            label: "j", programArguments: [],
            environmentVariables: ["X": "y"],
            sourcePath: URL(fileURLWithPath: "/tmp/j.plist")
        )
        XCTAssertThrowsError(try KeychainMigrationPlan.make(
            agent: agent, selectedEnvs: ["X"],
            wrapperDirectory: wrapperDir, keychainService: service, now: epoch
        )) { error in
            XCTAssertEqual(error as? KeychainMigrationPlan.MakeError, .emptyProgramArguments)
        }
    }
}
