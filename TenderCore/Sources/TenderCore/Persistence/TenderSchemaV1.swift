import Foundation
import SwiftData

/// Tender のローカル永続化スキーマ v1。
///
/// - plist は唯一の source of truth。このスキーマは以下だけを保持する:
///   - `Intent`: ユーザーがジョブに与える意味付け（障害切り分けの燃料）
///   - `BackupEntry`: plist 書き込み前に取った自動バックアップのメタデータ
///   - `ExecutionRecord`: launchctl 呼び出しやログファイル更新から得た実行履歴キャッシュ
///
/// 将来のスキーマ変更は `TenderSchemaV2` を定義し、`TenderMigrationPlan` に stage を追加する。
public enum TenderSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [Intent.self, BackupEntry.self, ExecutionRecord.self]
    }

    /// ジョブごとの意味付け。`label` で 1:1 に plist と紐付く。
    @Model
    public final class Intent {
        /// LaunchAgent の `Label` と同じ値。UPSERT キーとして扱う。
        @Attribute(.unique) public var label: String

        /// なぜ存在するか（自由記述）。
        public var why: String

        /// 期待頻度（自由記述: 毎時 / 毎日 / 何曜 etc）。
        public var frequencyExpected: String

        /// 失敗時の影響度。文字列で保持（UI で enum に写す）。
        public var impactOnFailure: String

        /// 依存する秘密情報キー（例: `GH_TOKEN`, `SLACK_BOT_TOKEN`）。
        public var secretsUsed: [String]

        /// 復旧手順（自由記述）。
        public var recoverySteps: String

        public var updatedAt: Date

        public init(
            label: String,
            why: String = "",
            frequencyExpected: String = "",
            impactOnFailure: String = ImpactOnFailure.medium.rawValue,
            secretsUsed: [String] = [],
            recoverySteps: String = "",
            updatedAt: Date = Date()
        ) {
            self.label = label
            self.why = why
            self.frequencyExpected = frequencyExpected
            self.impactOnFailure = impactOnFailure
            self.secretsUsed = secretsUsed
            self.recoverySteps = recoverySteps
            self.updatedAt = updatedAt
        }
    }

    /// plist 書き込み前に取ったバックアップのメタデータ。
    /// 実ファイルは `~/Library/Application Support/Tender/backups/<label>/<timestamp>.plist` に保存する。
    @Model
    public final class BackupEntry {
        public var label: String
        public var timestamp: Date
        public var plistPath: String
        public var reason: String

        public init(
            label: String,
            timestamp: Date,
            plistPath: String,
            reason: String
        ) {
            self.label = label
            self.timestamp = timestamp
            self.plistPath = plistPath
            self.reason = reason
        }
    }

    /// 実行履歴のキャッシュ。
    /// plist が source of truth の原則により、launchd から直接取得できない情報（duration 等）を
    /// Tender が観測できた範囲でのみ保持する。欠落を前提に扱うこと。
    @Model
    public final class ExecutionRecord {
        public var label: String
        public var executedAt: Date
        public var exitCode: Int32
        /// ミリ秒。不明な場合は nil。
        public var durationMs: Int?

        public init(
            label: String,
            executedAt: Date,
            exitCode: Int32,
            durationMs: Int? = nil
        ) {
            self.label = label
            self.executedAt = executedAt
            self.exitCode = exitCode
            self.durationMs = durationMs
        }
    }
}

/// 現行スキーマの `Intent` 型エイリアス。V2 以降は新しい versioned type を指すように更新する。
public typealias Intent = TenderSchemaV1.Intent

/// 現行スキーマの `BackupEntry` 型エイリアス。
public typealias BackupEntry = TenderSchemaV1.BackupEntry

/// 現行スキーマの `ExecutionRecord` 型エイリアス。
public typealias ExecutionRecord = TenderSchemaV1.ExecutionRecord

/// `Intent.impactOnFailure` の表現。SwiftData 側は `String` で永続化し、UI 層でこの enum に写す。
public enum ImpactOnFailure: String, Sendable, CaseIterable, Codable {
    case light
    case medium
    case heavy

    public var localizedLabel: String {
        switch self {
        case .light: "軽"
        case .medium: "中"
        case .heavy: "重"
        }
    }
}
