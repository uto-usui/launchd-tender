import Foundation
import OSLog

/// `~/Library/LaunchAgents` 配下の変更を監視し、コールバックを呼ぶ。
///
/// - 実装は `DispatchSource.makeFileSystemObjectSource(fileDescriptor:eventMask:queue:)`
///   を使った軽量なディレクトリ監視。FSEventStream は過剰なので使わない
/// - 監視対象はディレクトリそのもの。`.write / .delete / .rename` を拾うと中身の
///   追加・削除・名前変更も検知できる（ディレクトリに対するイベントは中身の変化で発火する）
/// - watcher は `stop()` されるまで生存。`deinit` で自動停止
/// - イベントは debounce しない。呼び出し元で必要ならまとめて扱う
/// - コールバックは utility QoS の global queue で呼ばれる。UI 反映は呼び出し側で
///   `@MainActor` に戻すこと
///
/// `@unchecked Sendable` の理由: `DispatchSource` と file descriptor の寿命を
/// `start()` / `stop()` で手動管理している。`source` への書き込みは internal queue
/// 経由で直列化し、イベントハンドラからは `self` を参照しない（強参照サイクル回避も兼ねる）
/// ため、外形的には Sendable として安全に扱える。
public final class LaunchAgentsWatcher: @unchecked Sendable {
    /// 変更検知時に呼ばれるハンドラ。
    public typealias EventHandler = @Sendable () -> Void

    private let directoryURL: URL
    private let logger = Logger(subsystem: "com.uto-usui.tender", category: "LaunchAgentsWatcher")

    /// `source` / `fileDescriptor` の生存管理を直列化するための queue。
    private let stateQueue = DispatchQueue(label: "com.uto-usui.tender.watcher.state")

    /// イベント配信用の queue。
    private let eventQueue = DispatchQueue.global(qos: .utility)

    /// 現在アクティブな DispatchSource。stop 済み / 未開始の間は nil。
    private var source: (any DispatchSourceFileSystemObject)?

    /// 監視対象 URL を指定して初期化する。
    /// - Parameter directoryURL: 監視するディレクトリ。デフォルトは `~/Library/LaunchAgents`
    public init(directoryURL: URL = LaunchAgentsScanner.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    deinit {
        // deinit からは stateQueue.sync を呼ばず、直接キャンセルする
        // （他スレッドが同時アクセスしないのは deinit の前提）
        if let source = source {
            source.cancel()
        }
        source = nil
    }

    /// 監視を開始する。すでに開始済みの場合は no-op。
    ///
    /// ディレクトリが開けない場合（`ENOENT` など）はログを出して黙って戻る。
    /// クラッシュせず、Store 側は手動 reload に委ねる。
    ///
    /// - Parameter onChange: 変更検知時に呼ばれるハンドラ。background queue で呼ばれる。
    public func start(onChange: @escaping EventHandler) {
        stateQueue.sync {
            guard source == nil else {
                logger.debug("start() called but watcher is already running")
                return
            }

            let path = directoryURL.path
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else {
                let err = String(cString: strerror(errno))
                logger.error("open(\(path, privacy: .public), O_EVTONLY) failed: \(err, privacy: .public)")
                return
            }

            let newSource = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename],
                queue: eventQueue
            )

            // イベントハンドラは self を捕捉しない（強参照サイクル回避）。
            // ユーザー提供のクロージャのみを呼ぶ。
            newSource.setEventHandler {
                onChange()
            }

            // キャンセル時に fd を閉じる。これにより二重 close は起きない
            // （キャンセルは一度しか走らない）。
            newSource.setCancelHandler {
                close(fd)
            }

            newSource.resume()
            source = newSource
            logger.debug("started watching \(path, privacy: .public)")
        }
    }

    /// 監視を停止する。未開始 / 既に停止済みの場合は no-op。
    public func stop() {
        stateQueue.sync {
            guard let current = source else { return }
            current.cancel()
            source = nil
        }
    }
}
