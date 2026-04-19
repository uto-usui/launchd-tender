import SwiftUI
import SwiftData
import OSLog
import TenderCore

/// ジョブ1つに対応する `Intent` を編集する。
///
/// - 既存があればフィールドを読み込み、なければ空で開始
/// - 保存は SwiftData の UPSERT（`@Attribute(.unique) label`）に委ねる
/// - `secretsUsed` はカンマ区切りの単一 TextField で編集
struct IntentEditorView: View {
    let label: String

    @Environment(\.modelContext) private var modelContext
    @Query private var matches: [Intent]

    @State private var why = ""
    @State private var frequencyExpected = ""
    @State private var impact: ImpactOnFailure = .medium
    @State private var secretsInput = ""
    @State private var recoverySteps = ""

    @State private var savedAt: Date?
    @State private var isDirty = false

    init(label: String) {
        self.label = label
        _matches = Query(filter: #Predicate<Intent> { $0.label == label })
    }

    var body: some View {
        DisclosureGroup("Intent（このジョブは何のために存在するか）") {
            VStack(alignment: .leading, spacing: 12) {
                whyField
                frequencyField
                impactPicker
                secretsField
                recoveryField
                footer
            }
            .padding(.top, Space.sm)
        }
        .onAppear {
            hydrate(from: matches.first)
        }
        .onChange(of: matches.first) { _, new in
            hydrate(from: new)
        }
        .onChange(of: why) { _, _ in isDirty = true }
        .onChange(of: frequencyExpected) { _, _ in isDirty = true }
        .onChange(of: impact) { _, _ in isDirty = true }
        .onChange(of: secretsInput) { _, _ in isDirty = true }
        .onChange(of: recoverySteps) { _, _ in isDirty = true }
    }

    // MARK: - Fields

    private var whyField: some View {
        labeled("なぜ（目的）") {
            TextEditor(text: $why)
                .font(.body)
                .frame(minHeight: 60, maxHeight: 100)
                .scrollContentBackground(.hidden)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
        }
    }

    private var frequencyField: some View {
        labeled("期待頻度") {
            TextField("毎時 / 毎日 / 何曜何時 …", text: $frequencyExpected)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var impactPicker: some View {
        labeled("失敗時の影響") {
            Picker("", selection: $impact) {
                ForEach(ImpactOnFailure.allCases, id: \.self) { level in
                    Text(level.localizedLabel).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var secretsField: some View {
        labeled("依存する secret（カンマ区切り）") {
            TextField("GH_TOKEN, SLACK_BOT_TOKEN …", text: $secretsInput)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
        }
    }

    private var recoveryField: some View {
        labeled("復旧手順") {
            TextEditor(text: $recoverySteps)
                .font(.body)
                .frame(minHeight: 60, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
        }
    }

    private var footer: some View {
        HStack {
            if let savedAt {
                Text("保存済: \(savedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("保存") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(!isDirty)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func hydrate(from intent: Intent?) {
        guard let intent else {
            // 新規。現在のフォーム値はそのまま（ユーザーが入力中の可能性）
            return
        }
        self.why = intent.why
        self.frequencyExpected = intent.frequencyExpected
        self.impact = ImpactOnFailure(rawValue: intent.impactOnFailure) ?? .medium
        self.secretsInput = intent.secretsUsed.joined(separator: ", ")
        self.recoverySteps = intent.recoverySteps
        self.savedAt = intent.updatedAt
        self.isDirty = false
    }

    private func save() {
        let secrets = secretsInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let now = Date()

        if let existing = matches.first {
            existing.why = why
            existing.frequencyExpected = frequencyExpected
            existing.impactOnFailure = impact.rawValue
            existing.secretsUsed = secrets
            existing.recoverySteps = recoverySteps
            existing.updatedAt = now
        } else {
            let intent = Intent(
                label: label,
                why: why,
                frequencyExpected: frequencyExpected,
                impactOnFailure: impact.rawValue,
                secretsUsed: secrets,
                recoverySteps: recoverySteps,
                updatedAt: now
            )
            modelContext.insert(intent)
        }

        do {
            try modelContext.save()
            savedAt = now
            isDirty = false
        } catch {
            // 保存失敗は稀（ローカル SQLite）。失敗したら isDirty を保ったまま状態を戻す。
            // ログ出力のみ、UI は何も出さない（必要なら後からトースト化）。
            let logger = Logger(subsystem: "com.uto-usui.tender", category: "IntentEditorView")
            logger.error("Intent save failed for \(label, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
