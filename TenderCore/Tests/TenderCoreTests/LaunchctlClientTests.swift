import XCTest
@testable import TenderCore

final class LaunchctlClientTests: XCTestCase {
    // MARK: - MockLaunchctlClient

    func testEnableRecordsCallAndReturnsResult() async throws {
        let mock = MockLaunchctlClient()
        await mock.enqueueSuccess(stdout: "ok")

        let result = try await mock.enable(label: "com.example.foo")

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "ok")
        XCTAssertTrue(result.isSuccess)
        let calls = await mock.recordedCalls()
        XCTAssertEqual(calls, [.enable("com.example.foo")])
    }

    func testDisableRecordsCallAndReturnsResult() async throws {
        let mock = MockLaunchctlClient()
        await mock.enqueueSuccess()

        let result = try await mock.disable(label: "com.example.bar")

        XCTAssertTrue(result.isSuccess)
        let calls = await mock.recordedCalls()
        XCTAssertEqual(calls, [.disable("com.example.bar")])
    }

    func testKickstartWithKillRecordsOption() async throws {
        let mock = MockLaunchctlClient()
        await mock.enqueueSuccess()

        _ = try await mock.kickstart(label: "com.example.baz", options: KickstartOptions(kill: true))

        let calls = await mock.recordedCalls()
        XCTAssertEqual(calls, [.kickstart("com.example.baz", KickstartOptions(kill: true))])
    }

    func testKickstartDefaultHasKillFalse() async throws {
        let mock = MockLaunchctlClient()
        await mock.enqueueSuccess()

        _ = try await mock.kickstart(label: "com.example.qux", options: .default)

        // KickstartOptions.default は kill=false であることを明示的に検証する。
        XCTAssertEqual(KickstartOptions.default.kill, false)
        let calls = await mock.recordedCalls()
        XCTAssertEqual(calls, [.kickstart("com.example.qux", KickstartOptions(kill: false))])
    }

    func testBootstrapPassesURLToCall() async throws {
        let mock = MockLaunchctlClient()
        await mock.enqueueSuccess()
        let url = URL(fileURLWithPath: "/Users/tender/Library/LaunchAgents/com.example.foo.plist")

        _ = try await mock.bootstrap(plistPath: url)

        let calls = await mock.recordedCalls()
        XCTAssertEqual(calls, [.bootstrap(url)])
    }

    func testBootoutPassesLabelToCall() async throws {
        let mock = MockLaunchctlClient()
        await mock.enqueueSuccess()

        _ = try await mock.bootout(label: "com.example.boot")

        let calls = await mock.recordedCalls()
        XCTAssertEqual(calls, [.bootout("com.example.boot")])
    }

    func testPrintDisabledReturnsEnqueuedLabels() async throws {
        let mock = MockLaunchctlClient()
        let expectedLabels: Set<String> = ["com.example.foo", "com.example.bar"]
        await mock.enqueuePrintDisabled(labels: expectedLabels)

        let result = try await mock.printDisabled()

        XCTAssertEqual(result.disabledLabels, expectedLabels)
        let calls = await mock.recordedCalls()
        XCTAssertEqual(calls, [.printDisabled])
    }

    func testEnqueueErrorIsThrown() async {
        let mock = MockLaunchctlClient()
        let failure = LaunchctlResult(exitCode: 5, stdout: "", stderr: "nope")
        await mock.enqueueError(.commandFailed(failure))

        do {
            _ = try await mock.enable(label: "com.example.err")
            XCTFail("Expected LaunchctlError.commandFailed to be thrown")
        } catch let error as LaunchctlError {
            XCTAssertEqual(error, .commandFailed(failure))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFIFOOrderingAcrossMultipleCalls() async throws {
        // 複数の enqueue が順序通りに消費されることを確認する。
        let mock = MockLaunchctlClient()
        await mock.enqueueSuccess(stdout: "first")
        await mock.enqueueSuccess(stdout: "second")

        let r1 = try await mock.enable(label: "com.example.a")
        let r2 = try await mock.disable(label: "com.example.b")

        XCTAssertEqual(r1.stdout, "first")
        XCTAssertEqual(r2.stdout, "second")
    }

    // MARK: - LaunchctlResult

    func testIsSuccessTrueOnExitZero() {
        let result = LaunchctlResult(exitCode: 0, stdout: "", stderr: "")
        XCTAssertTrue(result.isSuccess)
    }

    func testIsSuccessFalseOnNonZero() {
        XCTAssertFalse(LaunchctlResult(exitCode: 1, stdout: "", stderr: "").isSuccess)
        XCTAssertFalse(LaunchctlResult(exitCode: -1, stdout: "", stderr: "").isSuccess)
        XCTAssertFalse(LaunchctlResult(exitCode: 127, stdout: "", stderr: "").isSuccess)
    }

    // MARK: - ProcessLaunchctlClient argv 生成（実 launchctl は呼ばない）

    func testBuildArgumentsForEnable() {
        let args = ProcessLaunchctlClient.buildArguments(
            for: .enable(label: "com.example.foo"),
            uid: 501
        )
        XCTAssertEqual(args, ["enable", "gui/501/com.example.foo"])
    }

    func testBuildArgumentsForDisable() {
        let args = ProcessLaunchctlClient.buildArguments(
            for: .disable(label: "com.example.foo"),
            uid: 501
        )
        XCTAssertEqual(args, ["disable", "gui/501/com.example.foo"])
    }

    func testBuildArgumentsForKickstartWithoutKill() {
        let args = ProcessLaunchctlClient.buildArguments(
            for: .kickstart(label: "com.example.foo", options: .default),
            uid: 501
        )
        XCTAssertEqual(args, ["kickstart", "gui/501/com.example.foo"])
    }

    func testBuildArgumentsForKickstartWithKill() {
        let args = ProcessLaunchctlClient.buildArguments(
            for: .kickstart(label: "com.example.foo", options: KickstartOptions(kill: true)),
            uid: 501
        )
        XCTAssertEqual(args, ["kickstart", "-k", "gui/501/com.example.foo"])
    }

    func testBuildArgumentsForBootstrap() {
        let url = URL(fileURLWithPath: "/Users/tender/Library/LaunchAgents/com.example.foo.plist")
        let args = ProcessLaunchctlClient.buildArguments(
            for: .bootstrap(plistPath: url),
            uid: 501
        )
        XCTAssertEqual(args, ["bootstrap", "gui/501", "/Users/tender/Library/LaunchAgents/com.example.foo.plist"])
    }

    func testBuildArgumentsForBootout() {
        let args = ProcessLaunchctlClient.buildArguments(
            for: .bootout(label: "com.example.foo"),
            uid: 501
        )
        XCTAssertEqual(args, ["bootout", "gui/501/com.example.foo"])
    }

    func testBuildArgumentsForPrintDisabled() {
        let args = ProcessLaunchctlClient.buildArguments(
            for: .printDisabled,
            uid: 501
        )
        XCTAssertEqual(args, ["print-disabled", "gui/501"])
    }

    func testBuildArgumentsUsesDifferentUID() {
        // uid が domain 文字列へ埋め込まれることを uid 0 (root) ケースで確認。
        let args = ProcessLaunchctlClient.buildArguments(
            for: .enable(label: "com.example.foo"),
            uid: 0
        )
        XCTAssertEqual(args, ["enable", "gui/0/com.example.foo"])
    }

    // MARK: - print-disabled パーサ

    func testParsePrintDisabledExtractsDisabledLabels() {
        let text = """
        disabled services = {
        \t"com.example.foo" => disabled
        \t"com.example.bar" => enabled
        \t"com.example.baz" => disabled
        }
        """
        let labels = ProcessLaunchctlClient.parsePrintDisabled(text)
        XCTAssertEqual(labels, ["com.example.foo", "com.example.baz"])
    }

    func testParsePrintDisabledIgnoresEnabled() {
        let text = """
        disabled services = {
        \t"com.example.only-enabled" => enabled
        }
        """
        let labels = ProcessLaunchctlClient.parsePrintDisabled(text)
        XCTAssertTrue(labels.isEmpty)
    }

    func testParsePrintDisabledHandlesWhitespaceVariations() {
        // 前後の空白やタブにぶれがあっても拾えること。
        let text = #""com.example.a"    =>    disabled"#
        let labels = ProcessLaunchctlClient.parsePrintDisabled(text)
        XCTAssertEqual(labels, ["com.example.a"])
    }

    func testParsePrintDisabledReturnsEmptyOnGarbage() {
        // 形式が壊れていても例外は投げず、空 Set を返す。
        let labels = ProcessLaunchctlClient.parsePrintDisabled("totally broken output")
        XCTAssertTrue(labels.isEmpty)
    }
}
