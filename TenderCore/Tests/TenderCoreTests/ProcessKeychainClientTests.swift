import XCTest
@testable import TenderCore

final class ProcessKeychainClientTests: XCTestCase {
    func testAddArgumentsWithoutOverwrite() {
        let args = ProcessKeychainClient.buildAddArguments(
            service: "com.uto-usui.tender", account: "job.GH_TOKEN",
            password: "ghp_xxx", overwrite: false
        )
        XCTAssertEqual(args, [
            "add-generic-password", "-s", "com.uto-usui.tender", "-a", "job.GH_TOKEN",
            "-w", "ghp_xxx"
        ])
    }

    func testAddArgumentsWithOverwriteAppendsDashU() {
        let args = ProcessKeychainClient.buildAddArguments(
            service: "s", account: "a", password: "p", overwrite: true
        )
        XCTAssertEqual(args.last, "-U")
        XCTAssertTrue(args.contains("add-generic-password"))
    }

    func testFindArgumentsHasDashW() {
        let args = ProcessKeychainClient.buildFindArguments(service: "s", account: "a")
        XCTAssertEqual(args, ["find-generic-password", "-s", "s", "-a", "a", "-w"])
    }

    func testDeleteArguments() {
        let args = ProcessKeychainClient.buildDeleteArguments(service: "s", account: "a")
        XCTAssertEqual(args, ["delete-generic-password", "-s", "s", "-a", "a"])
    }

    func testPasswordWithSpacesIsPassedAsSingleArgument() {
        let args = ProcessKeychainClient.buildAddArguments(
            service: "s", account: "a", password: "has space and $dollar", overwrite: false
        )
        // Process は argv で渡すので shell 解釈されない — 単一要素として保持される
        XCTAssertEqual(args[6], "has space and $dollar")
    }
}
