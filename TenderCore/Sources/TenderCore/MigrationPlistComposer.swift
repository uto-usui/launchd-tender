import Foundation

/// 既存 plist Data に `KeychainMigrationPlan` を適用し、新しい plist Data を返す。
///
/// - `PropertyListSerialization` で dict に展開 → 差分更新 → XML で再 serialize
/// - 未知キー（Tender が扱わないキー）は保持される — plist が truth である原則を崩さない
/// - 出力は必ず XML（人間可読、diff しやすい）
public enum MigrationPlistComposer {
    public enum ComposeError: Error, Equatable, Sendable {
        case rootIsNotDictionary
        case invalidFormat
    }

    public static func compose(
        originalData: Data,
        plan: KeychainMigrationPlan
    ) throws -> Data {
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(
                from: originalData, options: .mutableContainersAndLeaves, format: nil
            )
        } catch {
            throw ComposeError.invalidFormat
        }
        guard var dict = plist as? [String: Any] else {
            throw ComposeError.rootIsNotDictionary
        }

        dict["ProgramArguments"] = plan.newProgramArguments

        if plan.newEnvironmentVariables.isEmpty {
            dict.removeValue(forKey: "EnvironmentVariables")
        } else {
            dict["EnvironmentVariables"] = plan.newEnvironmentVariables
        }

        // meta key マージ
        for (key, value) in plan.metaKeys.asDictionary {
            dict[key] = value
        }

        return try PropertyListSerialization.data(
            fromPropertyList: dict, format: .xml, options: 0
        )
    }
}
