import XCTest
@testable import TenderCore

final class AgentStatusEvaluatorTests: XCTestCase {
    func testDisabledLabelShortCircuits() {
        let agent = makeAgent(
            label: "com.example.off",
            programArguments: ["/missing/bin"]  // 実行ファイルが無くても disabled が優先する
        )
        let status = AgentStatusEvaluator.evaluate(
            agent: agent,
            disabledLabels: ["com.example.off"],
            fileExists: { _ in false },
            isExecutable: { _ in false }
        )
        XCTAssertEqual(status, .disabled)
    }

    func testEnabledWhenExecutableIsReadyAndNotDisabled() {
        let agent = makeAgent(
            label: "com.example.on",
            programArguments: ["/usr/bin/env"]
        )
        let status = AgentStatusEvaluator.evaluate(
            agent: agent,
            disabledLabels: [],
            fileExists: { $0 == "/usr/bin/env" },
            isExecutable: { $0 == "/usr/bin/env" }
        )
        XCTAssertEqual(status, .enabled)
    }

    func testMissingExecutableReportsPath() {
        let agent = makeAgent(
            label: "com.example.missing",
            programArguments: ["/opt/homebrew/bin/ghost"]
        )
        let status = AgentStatusEvaluator.evaluate(
            agent: agent,
            disabledLabels: [],
            fileExists: { _ in false },
            isExecutable: { _ in false }
        )
        XCTAssertEqual(status, .missingExecutable(path: "/opt/homebrew/bin/ghost"))
    }

    func testPresentButNotExecutable() {
        let agent = makeAgent(
            label: "com.example.chmod",
            programArguments: ["/opt/script.sh"]
        )
        let status = AgentStatusEvaluator.evaluate(
            agent: agent,
            disabledLabels: [],
            fileExists: { _ in true },
            isExecutable: { _ in false }
        )
        XCTAssertEqual(status, .notExecutable(path: "/opt/script.sh"))
    }

    func testNoProgramArgumentsFallsThrough() {
        let agent = makeAgent(
            label: "com.example.empty",
            programArguments: [],
            program: nil
        )
        let status = AgentStatusEvaluator.evaluate(
            agent: agent,
            disabledLabels: [],
            fileExists: { _ in true },
            isExecutable: { _ in true }
        )
        XCTAssertEqual(status, .noProgramArguments)
    }

    func testProgramFallbackWhenProgramArgumentsEmpty() {
        let agent = makeAgent(
            label: "com.example.programonly",
            programArguments: [],
            program: "/bin/sleep"
        )
        let status = AgentStatusEvaluator.evaluate(
            agent: agent,
            disabledLabels: [],
            fileExists: { $0 == "/bin/sleep" },
            isExecutable: { $0 == "/bin/sleep" }
        )
        XCTAssertEqual(status, .enabled)
    }

    func testEmptyFirstArgumentTreatedAsNoProgramArguments() {
        let agent = makeAgent(
            label: "com.example.empty-first",
            programArguments: [""],
            program: nil
        )
        let status = AgentStatusEvaluator.evaluate(
            agent: agent,
            disabledLabels: [],
            fileExists: { _ in true },
            isExecutable: { _ in true }
        )
        XCTAssertEqual(status, .noProgramArguments)
    }

    func testResolveExecutablePathPrefersProgramArguments() {
        let agent = makeAgent(
            label: "com.example.both",
            programArguments: ["/first"],
            program: "/second"
        )
        XCTAssertEqual(AgentStatusEvaluator.resolveExecutablePath(agent: agent), "/first")
    }

    // MARK: - Helpers

    private func makeAgent(
        label: String,
        programArguments: [String] = [],
        program: String? = nil
    ) -> LaunchAgent {
        LaunchAgent(
            label: label,
            programArguments: programArguments,
            program: program
        )
    }
}
