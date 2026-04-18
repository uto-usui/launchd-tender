import SwiftUI

/// Keychain ラッパ管理下の LaunchAgent を示すバッジ。
struct TenderManagedBadge: View {
    var body: some View {
        Label("Keychain 管理済", systemImage: "lock.shield.fill")
            .labelStyle(.titleAndIcon)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(.purple.opacity(0.12))
            )
            .overlay(
                Capsule().strokeBorder(.purple.opacity(0.4), lineWidth: 0.5)
            )
            .foregroundStyle(.purple)
            .help("ProgramArguments は wrapper script 経由で Keychain から値を読み出している")
    }
}

#Preview {
    TenderManagedBadge()
        .padding()
}
