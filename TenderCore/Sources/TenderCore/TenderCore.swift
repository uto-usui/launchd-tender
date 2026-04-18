/// Tender のドメインロジック層。
///
/// このモジュールは UI 非依存のビジネスロジックを集約する:
/// - `LaunchAgent` モデル
/// - `PlistParser`
/// - `LaunchAgentsScanner`
/// - `LaunchctlClient`
/// - 次回実行時刻計算
///
/// いずれも task #4 以降で追加される。
public enum TenderCore {
    public static let version = "0.1.0"
}
