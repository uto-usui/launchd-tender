import SwiftUI

/// Keychain ラッパ管理下の LaunchAgent を示すバッジ。
struct TenderManagedBadge: View {
    var body: some View {
        Label("Keychain 管理済", systemImage: "lock.shield.fill")
            .labelStyle(.titleAndIcon)
            .font(.caption)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(.gray.opacity(0.12))
            )
            .overlay(
                Capsule().strokeBorder(.gray.opacity(0.4), lineWidth: 0.5)
            )
            .foregroundStyle(.secondary)
            .help("ProgramArguments は wrapper script 経由で Keychain から値を読み出している")
    }
}

#Preview {
    TenderManagedBadge()
        .padding()
}
