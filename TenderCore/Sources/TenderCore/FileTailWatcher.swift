import Foundation
import OSLog

/// 単一ファイルの mtime / 追記 / 削除 / rename を `DispatchSource` で監視する軽量 watcher。
///
/// `LaunchAgentsWatcher` はディレクトリを監視するが、こちらはログファイルや plist
/// など「1 ファイルの追記」を拾うためのもの。実装は同型だが用途と呼び方を分ける。
///
/// `@unchecked Sendable` の理由は `LaunchAgentsWatcher` と同じ — `source` / `fd` の
/// 生存を `start` / `stop` と stateQueue で直列化している。
public final class FileTailWatcher: @unchecked Sendable {
    public typealias EventHandler = @Sendable () -> Void

    private let fileURL: URL
    private let logger = Logger(subsystem: "com.uto-usui.tender", category: "FileTailWatcher")
    private let stateQueue = DispatchQueue(label: "com.uto-usui.tender.file-tail.state")
    private let eventQueue = DispatchQueue.global(qos: .utility)
    private var source: (any DispatchSourceFileSystemObject)?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    deinit {
        if let source = source {
            source.cancel()
        }
        source = nil
    }

    /// 監視を開始する。ファイルが存在しない / 開けない場合はログを出して no-op。
    public func start(onChange: @escaping EventHandler) {
        stateQueue.sync { [self] in
            guard source == nil else { return }
            let path = self.fileURL.path
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else {
                let err = String(cString: strerror(errno))
                logger.debug("open(\(path, privacy: .public), O_EVTONLY) failed: \(err, privacy: .public)")
                return
            }

            let newSource = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .delete, .rename],
                queue: eventQueue
            )
            newSource.setEventHandler { onChange() }
            newSource.setCancelHandler { close(fd) }
            newSource.resume()
            source = newSource
        }
    }

    public func stop() {
        stateQueue.sync {
            guard let current = source else { return }
            current.cancel()
            source = nil
        }
    }
}
