import Foundation
import Observation
import OSLog
import TenderCore

/// サイドバー用の observable state。
///
/// - `reload()` が scan と `print-disabled` を並行取得し、UI に反映
/// - `LaunchctlClient` は注入可能（本番は `ProcessLaunchctlClient`）。失敗しても scan 結果は残す
/// - `enable` / `disable` / `kickstart` は実行後に `print-disabled` を再取得する
@MainActor
@Observable
final class LaunchAgentsStore {
    private(set) var agents: [LaunchAgent] = []
    private(set) var failures: [LaunchAgentsScanner.Failure] = []
    private(set) var disabledLabels: Set<String> = []
    private(set) var isLoading = false
    private(set) var runningAction: AgentActionKind?
    private(set) var lastActionResult: AgentActionResult?

    private let scanner: LaunchAgentsScanner
    private let launchctl: any LaunchctlClient
    private let logger = Logger(subsystem: "com.uto-usui.tender", category: "LaunchAgentsStore")

    init(
        scanner: LaunchAgentsScanner = LaunchAgentsScanner(),
        launchctl: any LaunchctlClient = ProcessLaunchctlClient()
    ) {
        self.scanner = scanner
        self.launchctl = launchctl
    }

    // MARK: - Loading

    func reload() async {
        isLoading = true
        defer { isLoading = false }

        async let scanTask = scanner.scan()
        async let disabledTask = fetchDisabledLabels()

        let scanResult = await scanTask
        let disabled = await disabledTask

        self.agents = scanResult.agents
        self.failures = scanResult.failures
        if let disabled {
            self.disabledLabels = disabled
        }
    }

    func status(for agent: LaunchAgent) -> AgentStatus {
        AgentStatusEvaluator.evaluate(agent: agent, disabledLabels: disabledLabels)
    }

    func dismissActionResult() {
        lastActionResult = nil
    }

    // MARK: - Actions

    func enable(_ agent: LaunchAgent) async {
        await performAction(label: agent.label, kind: .enable) {
            try await self.launchctl.enable(label: agent.label)
        }
    }

    func disable(_ agent: LaunchAgent) async {
        await performAction(label: agent.label, kind: .disable) {
            try await self.launchctl.disable(label: agent.label)
        }
    }

    func kickstart(_ agent: LaunchAgent, kill: Bool = false) async {
        let kind: AgentActionKind = kill ? .kickstartKill : .kickstart
        await performAction(label: agent.label, kind: kind) {
            try await self.launchctl.kickstart(label: agent.label, options: .init(kill: kill))
        }
    }

    // MARK: - Private

    private func performAction(
        label: String,
        kind: AgentActionKind,
        _ op: @escaping () async throws -> LaunchctlResult
    ) async {
        runningAction = kind
        defer { runningAction = nil }

        do {
            let result = try await op()
            if result.isSuccess {
                lastActionResult = .success(label: label, kind: kind)
            } else {
                lastActionResult = .failure(
                    label: label,
                    kind: kind,
                    exitCode: result.exitCode,
                    stderr: result.stderr
                )
            }
        } catch {
            logger.error("\(kind.verb) failed for \(label, privacy: .public): \(String(describing: error), privacy: .public)")
            lastActionResult = .failure(
                label: label,
                kind: kind,
                exitCode: -1,
                stderr: String(describing: error)
            )
        }

        // disabled 集合は enable / disable 後に変化する。kickstart でも念のため同期
        if let disabled = await fetchDisabledLabels() {
            self.disabledLabels = disabled
        }
    }

    private func fetchDisabledLabels() async -> Set<String>? {
        do {
            let result = try await launchctl.printDisabled()
            return result.disabledLabels
        } catch {
            logger.error("print-disabled failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
