import SwiftUI
import TenderCore

/// EnvironmentVariables に検出された秘密情報を警告表示するカード。
///
/// Phase 6 で実装する「Keychain ラッパへ移動」アクションの導線はここに配置される予定。
/// 今は検出結果の可視化に徹する。
struct SecretWarningCard: View {
    let detections: [SecretDetector.DetectedSecret]
    var onMigrate: (() -> Void)? = nil

    var body: some View {
        if detections.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.shield.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.yellow)
                    Text("平文の秘密情報が検出されました")
                        .font(.subheadline).bold()
                    Spacer()
                    if let onMigrate {
                        Button {
                            onMigrate()
                        } label: {
                            Label("Keychain へ移動", systemImage: "lock.shield")
                        }
                        .controlSize(.small)
                    }
                }

                Text("EnvironmentVariables に書かれた値の prefix が既知のトークン形式と一致します。launchd は Keychain 参照記法を理解しないため、ラッパ script 経由で Keychain から読み出す形に移行できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(detections, id: \.key) { detection in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "key.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.yellow)
                            .font(.caption2)
                        Text(detection.key)
                            .font(.body.monospaced().bold())
                            .textSelection(.enabled)
                        Text("→")
                            .foregroundStyle(.secondary)
                        Text(detection.pattern.provider)
                            .font(.caption)
                        Text("(\(detection.pattern.prefix)…)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.yellow.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.yellow.opacity(0.4), lineWidth: 1)
            )
        }
    }
}

#Preview {
    SecretWarningCard(detections: [
        .init(key: "GH_TOKEN", pattern: SecretDetector.defaultPatterns.first { $0.prefix == "ghp_" }!),
        .init(key: "SLACK_TOKEN", pattern: SecretDetector.defaultPatterns.first { $0.prefix == "xoxb-" }!)
    ])
    .padding()
}
