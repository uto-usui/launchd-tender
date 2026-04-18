import Foundation
import Observation
import OSLog
import TenderCore

/// サイドバー用の observable state。
///
/// - `reload()` が scan と `print-disabled` を並行取得し、UI に反映
/// - `LaunchctlClient` は注入可能（本番は `ProcessLaunchctlClient`）。失敗しても scan 結果は残す
@MainActor
@Observable
final class LaunchAgentsStore {
    private(set) var agents: [LaunchAgent] = []
    private(set) var failures: [LaunchAgentsScanner.Failure] = []
    private(set) var disabledLabels: Set<String> = []
    private(set) var isLoading = false

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

    func reload() async {
        isLoading = true
        defer { isLoading = false }

        // Scanner と print-disabled は独立して取れる。並行して await
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

    // MARK: - Private

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
