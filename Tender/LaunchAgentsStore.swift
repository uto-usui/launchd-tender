import Foundation
import Observation
import TenderCore

/// サイドバー用の observable state。Scanner の結果を保持する。
@MainActor
@Observable
final class LaunchAgentsStore {
    private(set) var agents: [LaunchAgent] = []
    private(set) var failures: [LaunchAgentsScanner.Failure] = []
    private(set) var isLoading = false

    private let scanner: LaunchAgentsScanner

    init(scanner: LaunchAgentsScanner = LaunchAgentsScanner()) {
        self.scanner = scanner
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        let result = await scanner.scan()
        self.agents = result.agents
        self.failures = result.failures
    }
}
