import Foundation
import OSLog

/// `~/Library/LaunchAgents` を走査して `LaunchAgent` 配列を返す。
///
/// - 走査対象は `.plist` のみ
/// - ファイル単位で catch し、パース失敗はログに出して配列から除外（他のファイルは処理を続行する）
/// - FSEvents による変更監視は別コンポーネント（後続タスクで実装）
public struct LaunchAgentsScanner: Sendable {
    public struct ScanResult: Sendable, Equatable {
        public let agents: [LaunchAgent]
        public let failures: [Failure]
    }

    public struct Failure: Sendable, Equatable {
        public let url: URL
        public let message: String
    }

    private let directoryURL: URL

    public init(directoryURL: URL = LaunchAgentsScanner.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    /// デフォルトの走査先: `~/Library/LaunchAgents`
    public static func defaultDirectoryURL() -> URL {
        URL(fileURLWithPath: NSString("~/Library/LaunchAgents").expandingTildeInPath, isDirectory: true)
    }

    /// ディレクトリを走査して結果を返す。ディレクトリが存在しない場合は空の結果。
    public func scan() async -> ScanResult {
        let directory = directoryURL
        return await Task.detached(priority: .utility) {
            Self.performScan(directoryURL: directory)
        }.value
    }

    // MARK: - Private

    private static func performScan(directoryURL: URL) -> ScanResult {
        let manager = FileManager.default
        let logger = Logger(subsystem: "com.uto-usui.tender", category: "LaunchAgentsScanner")

        guard manager.fileExists(atPath: directoryURL.path) else {
            logger.info("LaunchAgents directory does not exist: \(directoryURL.path, privacy: .public)")
            return ScanResult(agents: [], failures: [])
        }

        let contents: [URL]
        do {
            contents = try manager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            logger.error("Failed to list \(directoryURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return ScanResult(agents: [], failures: [])
        }

        var agents: [LaunchAgent] = []
        var failures: [Failure] = []

        for url in contents where url.pathExtension.lowercased() == "plist" {
            do {
                let agent = try PlistParser.parse(contentsOf: url)
                agents.append(agent)
            } catch {
                let message = String(describing: error)
                logger.error("Failed to parse \(url.lastPathComponent, privacy: .public): \(message, privacy: .public)")
                failures.append(Failure(url: url, message: message))
            }
        }

        agents.sort { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        return ScanResult(agents: agents, failures: failures)
    }
}
