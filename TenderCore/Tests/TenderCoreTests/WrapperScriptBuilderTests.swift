import XCTest
@testable import TenderCore

final class WrapperScriptBuilderTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 0)

    func testHeaderIncludesLabelAndSource() {
        let script = WrapperScriptBuilder.build(
            label: "com.example.job", envKeys: [],
            programArguments: ["/bin/true"],
            keychainService: "com.uto-usui.tender",
            generatedAt: epoch,
            sourcePlistPath: "/tmp/x.plist"
        )
        XCTAssertTrue(script.hasPrefix("#!/bin/bash\n"))
        XCTAssertTrue(script.contains("# Tender-managed wrapper for com.example.job"))
        XCTAssertTrue(script.contains("# Source plist: /tmp/x.plist"))
        XCTAssertTrue(script.contains("set -euo pipefail"))
    }

    func testSingleEnvKeyEmitsSecurityExport() {
        let script = WrapperScriptBuilder.build(
            label: "com.example.job", envKeys: ["GH_TOKEN"],
            programArguments: ["/usr/local/bin/poller", "--once"],
            keychainService: "com.uto-usui.tender",
            generatedAt: epoch,
            sourcePlistPath: "/tmp/x.plist"
        )
        XCTAssertTrue(
            script.contains(
                "export GH_TOKEN=\"$(security find-generic-password -s 'com.uto-usui.tender' -a 'com.example.job.GH_TOKEN' -w)\""
            )
        )
    }

    func testMultipleEnvKeysPreserveOrder() {
        let script = WrapperScriptBuilder.build(
            label: "job", envKeys: ["A", "B", "C"],
            programArguments: ["/bin/true"],
            keychainService: "s",
            generatedAt: epoch,
            sourcePlistPath: "/x"
        )
        let aIdx = script.range(of: "export A=")!.lowerBound
        let bIdx = script.range(of: "export B=")!.lowerBound
        let cIdx = script.range(of: "export C=")!.lowerBound
        XCTAssertLessThan(aIdx, bIdx)
        XCTAssertLessThan(bIdx, cIdx)
    }

    func testNoEnvKeysEmitsComment() {
        let script = WrapperScriptBuilder.build(
            label: "job", envKeys: [],
            programArguments: ["/bin/true"],
            keychainService: "s",
            generatedAt: epoch,
            sourcePlistPath: "/x"
        )
        XCTAssertTrue(script.contains("# (no Keychain-backed env vars)"))
    }

    func testExecUsesSingleQuotedArgv() {
        let script = WrapperScriptBuilder.build(
            label: "job", envKeys: [],
            programArguments: ["/usr/local/bin/poller", "--once", "--flag=x"],
            keychainService: "s",
            generatedAt: epoch,
            sourcePlistPath: "/x"
        )
        XCTAssertTrue(script.contains("exec '/usr/local/bin/poller' '--once' '--flag=x'"))
    }

    func testShellEscapeHandlesSingleQuote() {
        XCTAssertEqual(WrapperScriptBuilder.shellSingleQuote("it's ok"), "'it'\"'\"'s ok'")
    }

    func testShellEscapeHandlesDollarBacktickNewline() {
        // 単引用符内は全て literal 扱い — 置換は ' だけで十分
        XCTAssertEqual(WrapperScriptBuilder.shellSingleQuote("$HOME"), "'$HOME'")
        XCTAssertEqual(WrapperScriptBuilder.shellSingleQuote("`echo x`"), "'`echo x`'")
        XCTAssertEqual(WrapperScriptBuilder.shellSingleQuote("a\nb"), "'a\nb'")
    }

    func testArgvWithSingleQuoteEscapesInExec() {
        let script = WrapperScriptBuilder.build(
            label: "job", envKeys: [],
            programArguments: ["/bin/echo", "it's"],
            keychainService: "s",
            generatedAt: epoch,
            sourcePlistPath: "/x"
        )
        XCTAssertTrue(script.contains("'it'\"'\"'s'"))
    }

    func testBuildOrThrowRejectsEmptyArgv() {
        XCTAssertThrowsError(try WrapperScriptBuilder.buildOrThrow(
            label: "j", envKeys: [], programArguments: [],
            keychainService: "s", generatedAt: epoch, sourcePlistPath: "/x"
        )) { error in
            XCTAssertEqual(error as? WrapperScriptBuilder.BuilderError, .emptyProgramArguments)
        }
    }

    func testEndsWithNewline() {
        let script = WrapperScriptBuilder.build(
            label: "j", envKeys: [],
            programArguments: ["/bin/true"],
            keychainService: "s", generatedAt: epoch, sourcePlistPath: "/x"
        )
        XCTAssertTrue(script.hasSuffix("\n"))
    }
}
