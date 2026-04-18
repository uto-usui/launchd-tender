import Foundation
import SwiftData

/// `PlistAtomicWriter` が返す `BackupRecord` を SwiftData の `BackupEntry` として永続化する。
///
/// - `PlistAtomicWriter` は書き換え前のファイルコピーを取るが SwiftData には触らない（Sendable 制約）
/// - 呼び出し側（MainActor 上）が write 成功後にこの recorder で insert する
/// - 失敗時は throw — 呼び出し側はバックアップ漏れをログに残すか無視するかを選ぶ
@MainActor
public struct BackupRecorder {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// `BackupRecord` を `BackupEntry` として insert + save する。
    public func record(_ record: PlistAtomicWriter.BackupRecord) throws {
        let entry = BackupEntry(
            label: record.label,
            timestamp: record.timestamp,
            plistPath: record.plistPath.path,
            reason: record.reason
        )
        context.insert(entry)
        try context.save()
    }

    /// 複数のレコードを一括で insert + save する（`PlistAtomicWriter.BackupRecord?` の配列想定）。
    /// nil は読み飛ばす。
    public func record(_ records: [PlistAtomicWriter.BackupRecord?]) throws {
        for r in records {
            if let r {
                let entry = BackupEntry(
                    label: r.label, timestamp: r.timestamp,
                    plistPath: r.plistPath.path, reason: r.reason
                )
                context.insert(entry)
            }
        }
        try context.save()
    }
}
