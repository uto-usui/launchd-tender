import SwiftUI
import SwiftData
import TenderCore

/// `StartInterval` / `StartCalendarInterval` を GUI で編集する sheet。
///
/// - 「秒数 / 時刻指定 / 両方なし」の 3 モードを segmented で切り替え
/// - StartInterval はプリセット（1m / 5m / 15m / 30m / 1h / 6h / 12h / 1d）+ 数値入力
/// - StartCalendarInterval は entry の add / remove、各 entry は minute / hour / weekday / day / month の Optional Int
/// - 保存は `SchedulePlistComposer` + `PlistAtomicWriter` + `BackupRecorder`
/// - 反映には再読込が必要（メッセージで案内、自動 reload はしない）
struct ScheduleEditorSheet: View {
    let agent: LaunchAgent
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var mode: Mode = .none
    @State private var interval: Int = 3600
    @State private var entries: [EditableEntry] = []
    @State private var phase: Phase = .editing
    @State private var errorMessage: String?

    enum Mode: String, CaseIterable, Identifiable {
        case interval = "秒数 (StartInterval)"
        case calendar = "時刻指定 (StartCalendarInterval)"
        case none = "スケジュールなし"
        var id: String { rawValue }
    }

    enum Phase: Equatable {
        case editing
        case saving
        case saved
        case failed
    }

    init(agent: LaunchAgent, onDismiss: @escaping () -> Void) {
        self.agent = agent
        self.onDismiss = onDismiss
        _mode = State(initialValue: Self.initialMode(for: agent))
        _interval = State(initialValue: agent.startInterval ?? 3600)
        _entries = State(initialValue: agent.startCalendarInterval.isEmpty
            ? [EditableEntry()]
            : agent.startCalendarInterval.map(EditableEntry.init(from:)))
    }

    private static func initialMode(for agent: LaunchAgent) -> Mode {
        if agent.startInterval != nil { return .interval }
        if !agent.startCalendarInterval.isEmpty { return .calendar }
        return .none
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            Picker("モード", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(phase != .editing)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch mode {
                    case .interval:
                        intervalSection
                    case .calendar:
                        calendarSection
                    case .none:
                        Text("このジョブは RunAtLoad / WatchPaths など別のトリガに委ねます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    previewSection

                    if let errorMessage {
                        Text(errorMessage).font(.callout).foregroundStyle(.red)
                    }
                    if phase == .saved {
                        Label("保存しました。launchctl bootout → bootstrap で再読込してください。", systemImage: "checkmark.seal.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                }
            }

            Divider()
            footer
        }
        .padding(20)
        .frame(minWidth: 620, idealWidth: 720, minHeight: 520, idealHeight: 620)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("スケジュール編集")
                .font(.title3).bold()
            Text(agent.label)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var intervalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("秒数")
                    .font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                Text(humanInterval(interval))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(intervalPresets, id: \.seconds) { preset in
                    Button(preset.label) { interval = preset.seconds }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            HStack {
                TextField("秒", value: $interval, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Stepper("", value: $interval, in: 1...86400 * 7, step: 60)
                    .labelsHidden()
            }
        }
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("時刻エントリ (\(entries.count))")
                    .font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                Button {
                    entries.append(EditableEntry())
                } label: {
                    Label("追加", systemImage: "plus")
                }
                .controlSize(.small)
                .disabled(phase != .editing)
            }
            ForEach($entries) { $entry in
                EntryEditor(entry: $entry) {
                    entries.removeAll { $0.id == entry.id }
                }
                .disabled(phase != .editing)
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("プレビュー")
                .font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
            Text(previewText)
                .font(.body.monospaced())
                .textSelection(.enabled)
        }
    }

    private var footer: some View {
        HStack {
            if phase == .saving {
                ProgressView().controlSize(.small)
                Text("保存中…").foregroundStyle(.secondary)
            }
            Spacer()
            Button("閉じる") { onDismiss() }
            Button {
                Task { await save() }
            } label: {
                Text(phase == .saved ? "完了" : "保存")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(phase != .editing || agent.sourcePath == nil)
        }
    }

    // MARK: - Derived values

    private var previewText: String {
        switch mode {
        case .interval:
            return "\(interval) 秒ごと (\(humanInterval(interval)))"
        case .calendar:
            let resolved = entries.compactMap(\.asStartCalendarEntry)
            if resolved.isEmpty { return "(空)" }
            return StartCalendarFormatter.format(resolved).joined(separator: " / ")
        case .none:
            return "スケジュールなし"
        }
    }

    private var intervalPresets: [(label: String, seconds: Int)] {
        [
            ("1m", 60), ("5m", 300), ("15m", 900), ("30m", 1800),
            ("1h", 3600), ("6h", 21600), ("12h", 43200), ("1d", 86400)
        ]
    }

    private func humanInterval(_ seconds: Int) -> String {
        if seconds % 86400 == 0 { return "\(seconds / 86400) 日" }
        if seconds % 3600 == 0 { return "\(seconds / 3600) 時間" }
        if seconds % 60 == 0 { return "\(seconds / 60) 分" }
        return "\(seconds) 秒"
    }

    // MARK: - Save

    private func save() async {
        guard let sourceURL = agent.sourcePath else { return }
        phase = .saving
        errorMessage = nil

        let (intervalToSave, entriesToSave): (Int?, [StartCalendarEntry])
        switch mode {
        case .interval:
            intervalToSave = interval
            entriesToSave = []
        case .calendar:
            intervalToSave = nil
            entriesToSave = entries.compactMap(\.asStartCalendarEntry)
        case .none:
            intervalToSave = nil
            entriesToSave = []
        }

        do {
            let originalData = try Data(contentsOf: sourceURL)
            let newData = try SchedulePlistComposer.compose(
                originalData: originalData,
                startInterval: intervalToSave,
                startCalendarInterval: entriesToSave
            )
            let backupsRoot = try PlistAtomicWriter.defaultBackupsRootURL()
            let writer = PlistAtomicWriter(backupsRootURL: backupsRoot)
            let backup = try writer.write(
                newData, to: sourceURL,
                label: agent.label, reason: "schedule-edit"
            )
            if let backup {
                try BackupRecorder(context: modelContext).record(backup)
            }
            phase = .saved
        } catch {
            phase = .failed
            errorMessage = String(describing: error)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(0))
                if phase == .failed { phase = .editing }
            }
        }
    }
}

// MARK: - EditableEntry

/// UI バインド用の可変エントリ。各フィールドは "(任意)" を nil、値入力時は Int で保持する。
private struct EditableEntry: Identifiable, Hashable {
    let id = UUID()
    var minute: Int?
    var hour: Int?
    var day: Int?
    var weekday: Int?
    var month: Int?

    init() {}

    init(from entry: StartCalendarEntry) {
        self.minute = entry.minute
        self.hour = entry.hour
        self.day = entry.day
        self.weekday = entry.weekday
        self.month = entry.month
    }

    var asStartCalendarEntry: StartCalendarEntry? {
        // 全フィールド nil の entry は launchd から見ると「任意時刻」で意味がないので保存対象外。
        if minute == nil && hour == nil && day == nil && weekday == nil && month == nil {
            return nil
        }
        return StartCalendarEntry(minute: minute, hour: hour, day: day, weekday: weekday, month: month)
    }
}

// MARK: - EntryEditor

private struct EntryEditor: View {
    @Binding var entry: EditableEntry
    let onRemove: () -> Void

    private let weekdayLabels = [
        "(任意)", "日曜", "月曜", "火曜", "水曜", "木曜", "金曜", "土曜"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(StartCalendarFormatter.format(entry.asStartCalendarEntry ?? StartCalendarEntry()))
                    .font(.body.monospaced().bold())
                Spacer()
                Button(role: .destructive) { onRemove() } label: {
                    Image(systemName: "minus.circle")
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
            }
            HStack(spacing: 10) {
                numericField(label: "Minute", range: 0...59, value: $entry.minute)
                numericField(label: "Hour", range: 0...23, value: $entry.hour)
                numericField(label: "Day", range: 1...31, value: $entry.day)
                weekdayField()
                numericField(label: "Month", range: 1...12, value: $entry.month)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06))
        )
    }

    private func numericField(label: String, range: ClosedRange<Int>, value: Binding<Int?>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                TextField("—", value: value, format: .number.precision(.integerLength(range.lowerBound < 10 && range.upperBound < 10 ? 1 : 2)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 52)
                Button {
                    value.wrappedValue = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("クリア（任意扱い）")
            }
        }
    }

    private func weekdayField() -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Weekday").font(.caption2).foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { entry.weekday ?? 0 },
                set: { entry.weekday = $0 == 0 ? nil : $0 }
            )) {
                ForEach(0..<weekdayLabels.count, id: \.self) { idx in
                    Text(weekdayLabels[idx]).tag(idx)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 96)
        }
    }
}
