import SwiftUI
import SwiftData
import TenderCore

@main
struct TenderApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            self.modelContainer = try TenderModelContainer.makeContainer()
        } catch {
            // 永続化が初期化できないとアプリとして機能しない（Intent / バックアップ記録が保存できない）。
            // 自分用ツールなので fatalError で落として原因を調べる運用。
            fatalError("Failed to initialize Tender's SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 720, minHeight: 480)
        }
        .modelContainer(modelContainer)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
