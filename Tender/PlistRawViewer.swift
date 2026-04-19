import SwiftUI
import Foundation
import TenderCore

/// plist の raw 内容を SF Mono で表示する read-only ビューア。
///
/// - XML plist はそのまま表示
/// - binary plist は一度デシリアライズ → XML に戻して表示
/// - 読み込み失敗はエラー文言を表示
/// - `FileTailWatcher` でファイル変更に追従、Tender 自身の編集 / 外部 vim からの書き換えどちらも反映
struct PlistRawViewer: View {
    let url: URL

    @State private var content: LoadState = .idle

    var body: some View {
        DisclosureGroup("plist ファイル (raw)") {
            contentView
                .padding(.top, Space.sm)
        }
        .task(id: url) {
            await watchLoop()
        }
    }

    /// 初回読み込み → FSEvents 監視による再読み込みループ。
    /// `.task(id: url)` が cancel されると AsyncStream も終わり watcher.stop が走る。
    private func watchLoop() async {
        content = .loading
        content = await Self.readContent(from: url)

        let stream = AsyncStream<Void> { continuation in
            let watcher = FileTailWatcher(fileURL: url)
            watcher.start { continuation.yield() }
            continuation.onTermination = { _ in watcher.stop() }
        }
        for await _ in stream {
            if Task.isCancelled { break }
            // 書き込み中に一瞬空で読まれるのを避ける debounce
            try? await Task.sleep(for: .milliseconds(150))
            if Task.isCancelled { break }
            content = await Self.readContent(from: url)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch content {
        case .idle, .loading:
            HStack {
                ProgressView().controlSize(.small)
                Text("読み込み中…").foregroundStyle(.secondary).font(.caption)
            }
        case .loaded(let text, let format):
            VStack(alignment: .leading, spacing: 4) {
                Text(format.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    // MARK: - File loading

    enum Format: Equatable {
        case xml
        case binaryToXml

        var label: String {
            switch self {
            case .xml: "XML plist"
            case .binaryToXml: "binary plist (XML に整形)"
            }
        }
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(text: String, format: Format)
        case failed(String)
    }

    private static func readContent(from url: URL) async -> LoadState {
        await Task.detached(priority: .utility) { () -> LoadState in
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                return .failed("ファイル読み込みエラー: \(error.localizedDescription)")
            }

            // bplist マジックバイトで判定
            let magic = data.prefix(6)
            let isBinary = magic.starts(with: Data("bplist".utf8))

            if !isBinary, let text = String(data: data, encoding: .utf8) {
                return .loaded(text: text, format: .xml)
            }

            do {
                let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                let xmlData = try PropertyListSerialization.data(
                    fromPropertyList: plist,
                    format: .xml,
                    options: 0
                )
                guard let text = String(data: xmlData, encoding: .utf8) else {
                    return .failed("XML 変換結果を UTF-8 としてデコードできませんでした")
                }
                return .loaded(text: text, format: .binaryToXml)
            } catch {
                return .failed("plist 変換エラー: \(error.localizedDescription)")
            }
        }.value
    }
}
