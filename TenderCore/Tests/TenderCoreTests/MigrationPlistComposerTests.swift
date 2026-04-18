import XCTest
@testable import TenderCore

final class MigrationPlistComposerTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 0)
    private let wrapperDir = URL(fileURLWithPath: "/tmp/wrappers")
    private let service = "com.uto-usui.tender"

    private func makePlan(envKeysToMigrate: [String] = ["GH_TOKEN"]) throws -> KeychainMigrationPlan {
        let agent = LaunchAgent(
            label: "com.example.job",
            programArguments: ["/usr/bin/poller", "--once"],
            environmentVariables: ["GH_TOKEN": "ghp_xxx", "SENTRY_DSN": "https://e"],
            sourcePath: URL(fileURLWithPath: "/tmp/com.example.job.plist")
        )
        return try KeychainMigrationPlan.make(
            agent: agent, selectedEnvs: envKeysToMigrate,
            wrapperDirectory: wrapperDir, keychainService: service, now: epoch
        )
    }

    private func makeOriginalPlist(
        programArguments: [String] = ["/usr/bin/poller", "--once"],
        env: [String: String] = ["GH_TOKEN": "ghp_xxx", "SENTRY_DSN": "https://e"],
        extraKeys: [String: Any] = [:]
    ) throws -> Data {
        var dict: [String: Any] = [
            "Label": "com.example.job",
            "ProgramArguments": programArguments,
            "EnvironmentVariables": env,
            "RunAtLoad": true,
            "StandardOutPath": "/tmp/poller.out.log"
        ]
        for (k, v) in extraKeys { dict[k] = v }
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    func testComposeReplacesProgramArgumentsAndDropsMigratedEnv() throws {
        let original = try makeOriginalPlist()
        let plan = try makePlan()

        let newData = try MigrationPlistComposer.compose(originalData: original, plan: plan)
        let dict = try PropertyListSerialization.propertyList(from: newData, options: [], format: nil) as! [String: Any]

        XCTAssertEqual(dict["ProgramArguments"] as? [String], ["/bin/bash", "/tmp/wrappers/com.example.job.sh"])
        XCTAssertEqual(dict["EnvironmentVariables"] as? [String: String], ["SENTRY_DSN": "https://e"])
    }

    func testComposeAddsMetaKeys() throws {
        let original = try makeOriginalPlist()
        let plan = try makePlan()

        let newData = try MigrationPlistComposer.compose(originalData: original, plan: plan)
        let dict = try PropertyListSerialization.propertyList(from: newData, options: [], format: nil) as! [String: Any]

        XCTAssertEqual(dict["TenderManaged"] as? Bool, true)
        XCTAssertEqual(dict["TenderWrappedEnvs"] as? [String], ["GH_TOKEN"])
        XCTAssertEqual(dict["TenderOriginalProgramArguments"] as? [String], ["/usr/bin/poller", "--once"])
    }

    func testComposePreservesUntouchedKeys() throws {
        let original = try makeOriginalPlist(extraKeys: [
            "StartInterval": 3600,
            "WatchPaths": ["/tmp/watch"]
        ])
        let plan = try makePlan()
        let newData = try MigrationPlistComposer.compose(originalData: original, plan: plan)
        let dict = try PropertyListSerialization.propertyList(from: newData, options: [], format: nil) as! [String: Any]

        XCTAssertEqual(dict["Label"] as? String, "com.example.job")
        XCTAssertEqual(dict["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(dict["StandardOutPath"] as? String, "/tmp/poller.out.log")
        XCTAssertEqual(dict["StartInterval"] as? Int, 3600)
        XCTAssertEqual(dict["WatchPaths"] as? [String], ["/tmp/watch"])
    }

    func testComposeRemovesEnvironmentVariablesKeyWhenAllMigrated() throws {
        let agent = LaunchAgent(
            label: "com.example.job",
            programArguments: ["/usr/bin/poller"],
            environmentVariables: ["GH_TOKEN": "x"],
            sourcePath: URL(fileURLWithPath: "/tmp/j.plist")
        )
        let plan = try KeychainMigrationPlan.make(
            agent: agent, selectedEnvs: ["GH_TOKEN"],
            wrapperDirectory: wrapperDir, keychainService: service, now: epoch
        )
        let original = try makeOriginalPlist(
            programArguments: ["/usr/bin/poller"], env: ["GH_TOKEN": "x"]
        )
        let newData = try MigrationPlistComposer.compose(originalData: original, plan: plan)
        let dict = try PropertyListSerialization.propertyList(from: newData, options: [], format: nil) as! [String: Any]

        XCTAssertNil(dict["EnvironmentVariables"])
    }

    func testComposeOutputIsXML() throws {
        let original = try makeOriginalPlist()
        let plan = try makePlan()
        let newData = try MigrationPlistComposer.compose(originalData: original, plan: plan)
        let prefix = String(data: newData.prefix(40), encoding: .utf8) ?? ""
        XCTAssertTrue(prefix.contains("<?xml"), "expected XML prefix, got: \(prefix)")
    }

    func testComposeThrowsOnInvalidData() throws {
        let plan = try makePlan()
        XCTAssertThrowsError(try MigrationPlistComposer.compose(
            originalData: Data("not a plist".utf8), plan: plan
        )) { error in
            XCTAssertEqual(error as? MigrationPlistComposer.ComposeError, .invalidFormat)
        }
    }

    func testComposeThrowsWhenRootIsNotDict() throws {
        let plan = try makePlan()
        let arrayPlist = try PropertyListSerialization.data(
            fromPropertyList: ["not", "a", "dict"] as [String],
            format: .xml, options: 0
        )
        XCTAssertThrowsError(try MigrationPlistComposer.compose(
            originalData: arrayPlist, plan: plan
        )) { error in
            XCTAssertEqual(error as? MigrationPlistComposer.ComposeError, .rootIsNotDictionary)
        }
    }
}
