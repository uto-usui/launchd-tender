import Foundation
import SwiftData

/// Tender の SwiftData マイグレーション計画。
///
/// 現在は V1 のみ。新しいスキーマを追加したら:
/// 1. `TenderSchemaVN` を定義
/// 2. `schemas` の末尾に追加
/// 3. `stages` に `MigrationStage.lightweight(...)` か `.custom(...)` を追加
///
/// migration plan を初期から書く意図は、リリース後にスキーマを変えた際に
/// `fatalError` で既存 store を壊さないこと（CLAUDE.md ガードレール 4）。
public enum TenderMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [TenderSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []  // V1 のみなので stage なし
    }
}
