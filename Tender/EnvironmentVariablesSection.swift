import SwiftUI
import TenderCore

/// 環境変数セクション。平文 secret 検出がある場合は見出しに黄色バッジ、
/// 検出行には inline で警告アイコンと yellow.opacity(0.06) 帯を載せる。
///
/// DESIGN.md の "Density is care" / "Honest about uncertainty" に沿った表現:
/// - "見るべき場所は 1 つ" (独立カードを作らない)
/// - "推定" を見出しバッジに明示
struct EnvironmentVariablesSection: View {
    let agent: LaunchAgent
    let detections: [SecretDetector.DetectedSecret]
    var onMigrate: (() -> Void)? = nil

    private var detectedKeys: Set<String> { Set(detections.map(\.key)) }

    var body: some View {
        if agent.environmentVariables.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Space.sm) {
                header
                ForEach(agent.environmentVariables.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    row(key: key, value: value, isDetected: detectedKeys.contains(key))
                }
                if !detections.isEmpty {
                    Text("prefix 一致による推定です。誤検知の場合はこのセクションを無視できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            Text("EnvironmentVariables")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if !detections.isEmpty {
                Label("\(detections.count) 件 推定", systemImage: "exclamationmark.shield.fill")
                    .labelStyle(.titleAndIcon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }
            Spacer()
            if !detections.isEmpty, let onMigrate {
                Button {
                    onMigrate()
                } label: {
                    Label("Keychain へ", systemImage: "lock.shield")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func row(key: String, value: String, isDetected: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            if isDetected {
                Image(systemName: "exclamationmark.shield.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.yellow)
                    .font(.caption2)
            } else {
                // 列位置を揃えるためのスペーサ
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.caption2)
                    .opacity(0)
            }
            Text(key).font(.body.monospaced().bold())
            Text("=").foregroundStyle(.secondary)
            Text(value).font(.body.monospaced()).textSelection(.enabled)
        }
        .padding(.horizontal, Space.xs)
        .padding(.vertical, 2)
        .background(
            isDetected
                ? RoundedRectangle(cornerRadius: Radius.sm).fill(.yellow.opacity(0.06))
                : nil
        )
    }
}
