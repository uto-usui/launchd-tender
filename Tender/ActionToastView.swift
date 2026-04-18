import SwiftUI

/// `AgentActionResult` を表示するバナー。成功は緑、失敗は赤で、X ボタンで dismiss。
struct ActionToastView: View {
    let result: AgentActionResult
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(result.isSuccess ? .green : .red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.subheadline).bold()
                Text(result.label)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if case let .failure(_, _, exitCode, stderr) = result {
                    if exitCode != -1 {
                        Text("exit code: \(exitCode)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(stderr)
                            .font(.caption.monospaced())
                            .foregroundStyle(.red.opacity(0.85))
                            .textSelection(.enabled)
                            .lineLimit(4)
                    }
                }
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("閉じる")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(result.isSuccess ? Color.green.opacity(0.4) : Color.red.opacity(0.4), lineWidth: 1)
        )
        .frame(maxWidth: 480)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var headline: String {
        if result.isSuccess {
            return "\(result.kind.verb) 完了"
        } else {
            return "\(result.kind.verb) 失敗"
        }
    }
}

#Preview("success") {
    ActionToastView(
        result: .success(label: "***REDACTED***", kind: .kickstart),
        onDismiss: {}
    )
    .padding()
}

#Preview("failure") {
    ActionToastView(
        result: .failure(
            label: "com.example.broken",
            kind: .enable,
            exitCode: 3,
            stderr: "Operation not permitted\nCheck gui/503/com.example.broken\n"
        ),
        onDismiss: {}
    )
    .padding()
}
