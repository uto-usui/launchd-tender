import Foundation

/// `KeychainDetachPlan` を既存 plist Data に適用し、管理前の状態に戻す。
///
/// - ProgramArguments を `TenderOriginalProgramArguments` の値で復元
/// - Tender 管理 meta key 3 つを削除
/// - EnvironmentVariables は触らない（migration 時に削除されている env は戻らない — Keychain 側に値があるので別途手動復元する）
public enum DetachPlistComposer {
    public enum ComposeError: Error, Equatable, Sendable {
        case rootIsNotDictionary
        case invalidFormat
    }

    public static func compose(
        originalData: Data,
        plan: KeychainDetachPlan
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

        dict["ProgramArguments"] = plan.restoredProgramArguments
        dict.removeValue(forKey: "TenderManaged")
        dict.removeValue(forKey: "TenderWrappedEnvs")
        dict.removeValue(forKey: "TenderOriginalProgramArguments")

        return try PropertyListSerialization.data(
            fromPropertyList: dict, format: .xml, options: 0
        )
    }
}
