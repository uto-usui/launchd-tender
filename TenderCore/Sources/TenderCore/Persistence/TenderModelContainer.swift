import Foundation
import SwiftData

/// Tender 用 `ModelContainer` の生成ヘルパ。
///
/// アプリ本体は `TenderModelContainer.makeContainer()` を呼んで得たコンテナを
/// SwiftUI の `.modelContainer(_:)` に渡す。テストは `.inMemory` で副作用を閉じ込める。
public enum TenderModelContainer {
    public enum Configuration {
        case onDisk(URL? = nil)
        case inMemory
    }

    /// Tender のコンテナを生成する。
    ///
    /// - Parameter configuration: 永続化先。`.onDisk(nil)` で SwiftData デフォルトパス。
    public static func makeContainer(
        configuration: Configuration = .onDisk()
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: TenderSchemaV1.self)

        let modelConfiguration: ModelConfiguration
        switch configuration {
        case .onDisk(let url):
            if let url {
                modelConfiguration = ModelConfiguration(
                    schema: schema,
                    url: url
                )
            } else {
                modelConfiguration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false
                )
            }
        case .inMemory:
            modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )
        }

        return try ModelContainer(
            for: schema,
            migrationPlan: TenderMigrationPlan.self,
            configurations: modelConfiguration
        )
    }
}
