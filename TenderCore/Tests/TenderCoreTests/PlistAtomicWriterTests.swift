import XCTest
@testable import TenderCore

final class PlistAtomicWriterTests: XCTestCase {
    private var tempDir: URL!
    private var backupsRoot: URL!
    private var agentsDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tender-writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        backupsRoot = tempDir.appendingPathComponent("backups", isDirectory: true)
        agentsDir = tempDir.appendingPathComponent("LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - 1. 新規書き込み

    func testWritesNewFileWithoutBackup() throws {
        let writer = PlistAtomicWriter(backupsRootURL: backupsRoot)
        let dest = agentsDir.appendingPathComponent("com.example.new.plist")
        let payload = Data("hello".utf8)

        let record = try writer.write(
            payload,
            to: dest,
            label: "com.example.new",
            reason: "initial write"
        )

        XCTAssertNil(record, "新規作成時は BackupRecord は nil")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertEqual(try Data(contentsOf: dest), payload)

        // バックアップルート自体が作られていないこと（新規なら触る必要なし）
        let backupSubdir = backupsRoot.appendingPathComponent("com.example.new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupSubdir.path))
    }

    // MARK: - 2. 上書き + バックアップ

    func testOverwritesExistingAndCreatesBackup() throws {
        let writer = PlistAtomicWriter(backupsRootURL: backupsRoot)
        let dest = agentsDir.appendingPathComponent("com.example.overwrite.plist")
        let original = Data("original content".utf8)
        let updated = Data("updated content".utf8)
        try original.write(to: dest)

        let record = try writer.write(
            updated,
            to: dest,
            label: "com.example.overwrite",
            reason: "raw editor save"
        )

        let unwrapped = try XCTUnwrap(record)
        XCTAssertEqual(unwrapped.label, "com.example.overwrite")
        XCTAssertEqual(unwrapped.reason, "raw editor save")
        XCTAssertTrue(FileManager.default.fileExists(atPath: unwrapped.plistPath.path))
        XCTAssertEqual(try Data(contentsOf: unwrapped.plistPath), original,
                       "バックアップは書き込み前の内容と一致すべき")
        XCTAssertEqual(try Data(contentsOf: dest), updated,
                       "destination は新しい内容で上書きされる")
    }

    // MARK: - 3. バックアップファイル名フォーマット

    func testBackupFilenameFormatUsesInjectedClock() throws {
        // 2026-04-19 13:45:07 (ローカル TZ として固定)
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 19
        components.hour = 13
        components.minute = 45
        components.second = 7
        let fixed = Calendar.current.date(from: components)!

        let writer = PlistAtomicWriter(backupsRootURL: backupsRoot, clock: { fixed })
        let dest = agentsDir.appendingPathComponent("com.example.fmt.plist")
        try Data("v1".utf8).write(to: dest)

        let record = try XCTUnwrap(try writer.write(
            Data("v2".utf8),
            to: dest,
            label: "com.example.fmt",
            reason: "timestamp check"
        ))

        XCTAssertEqual(record.plistPath.lastPathComponent, "20260419-134507.plist")
        XCTAssertEqual(record.timestamp, fixed)
    }

    // MARK: - 4. バックアップディレクトリ自動生成

    func testBackupSubdirectoryIsCreatedOnFirstOverwrite() throws {
        let writer = PlistAtomicWriter(backupsRootURL: backupsRoot)
        let dest = agentsDir.appendingPathComponent("com.example.autodir.plist")
        try Data("v1".utf8).write(to: dest)

        XCTAssertFalse(FileManager.default.fileExists(atPath: backupsRoot.path))

        _ = try writer.write(
            Data("v2".utf8),
            to: dest,
            label: "com.example.autodir",
            reason: "first overwrite"
        )

        let labelDir = backupsRoot.appendingPathComponent("com.example.autodir")
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: labelDir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    // MARK: - 5. 複数回上書き

    func testMultipleOverwritesProduceMultipleBackups() throws {
        // 同一ラベルで 3 回上書き、異なるタイムスタンプで 3 ファイルが並ぶことを確認
        let times: [Date] = [
            makeDate(year: 2026, month: 1, day: 1, hour: 0, minute: 0, second: 0),
            makeDate(year: 2026, month: 1, day: 1, hour: 0, minute: 0, second: 1),
            makeDate(year: 2026, month: 1, day: 1, hour: 0, minute: 0, second: 2)
        ]
        let counter = SequentialClock(values: times)
        let writer = PlistAtomicWriter(backupsRootURL: backupsRoot, clock: { counter.next() })

        let dest = agentsDir.appendingPathComponent("com.example.multi.plist")
        try Data("v0".utf8).write(to: dest)

        for i in 1...3 {
            let rec = try writer.write(
                Data("v\(i)".utf8),
                to: dest,
                label: "com.example.multi",
                reason: "revision \(i)"
            )
            XCTAssertNotNil(rec)
        }

        let labelDir = backupsRoot.appendingPathComponent("com.example.multi")
        let entries = try FileManager.default.contentsOfDirectory(atPath: labelDir.path).sorted()
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries, [
            "20260101-000000.plist",
            "20260101-000001.plist",
            "20260101-000002.plist"
        ])
    }

    // MARK: - 6. 親ディレクトリ未作成で throw

    func testThrowsWhenParentDirectoryMissing() {
        let writer = PlistAtomicWriter(backupsRootURL: backupsRoot)
        let missingParent = tempDir.appendingPathComponent("does-not-exist", isDirectory: true)
        let dest = missingParent.appendingPathComponent("agent.plist")

        XCTAssertThrowsError(try writer.write(
            Data("x".utf8),
            to: dest,
            label: "com.example.missing",
            reason: "should fail"
        )) { error in
            guard case let PlistAtomicWriter.WriteError.sourceDirectoryMissing(url) = error else {
                return XCTFail("Expected sourceDirectoryMissing, got \(error)")
            }
            XCTAssertEqual(url.standardizedFileURL, missingParent.standardizedFileURL)
        }
    }

    // MARK: - 7. data の内容が destination に反映される（read-back）

    func testDataIsWrittenByteForByte() throws {
        let writer = PlistAtomicWriter(backupsRootURL: backupsRoot)
        let dest = agentsDir.appendingPathComponent("com.example.readback.plist")
        let payload = Data((0..<1024).map { UInt8($0 % 256) })

        _ = try writer.write(payload, to: dest, label: "com.example.readback", reason: "read-back")

        XCTAssertEqual(try Data(contentsOf: dest), payload)
    }

    // MARK: - 8. tmp ファイル残骸がない

    func testNoTempFileResidueAfterSuccess() throws {
        let writer = PlistAtomicWriter(backupsRootURL: backupsRoot)
        let dest = agentsDir.appendingPathComponent("com.example.notmp.plist")
        try Data("v0".utf8).write(to: dest)

        _ = try writer.write(
            Data("v1".utf8),
            to: dest,
            label: "com.example.notmp",
            reason: "no residue"
        )

        let entries = try FileManager.default.contentsOfDirectory(atPath: agentsDir.path)
        let leftover = entries.filter { $0.hasPrefix(".tender-write-") }
        XCTAssertTrue(leftover.isEmpty, "tmp ファイルが残っている: \(leftover)")
    }

    // MARK: - 9. 異なる label でバックアップが分離される

    func testDifferentLabelsCreateSeparateSubdirs() throws {
        let writer = PlistAtomicWriter(backupsRootURL: backupsRoot)
        let destA = agentsDir.appendingPathComponent("a.plist")
        let destB = agentsDir.appendingPathComponent("b.plist")
        try Data("a0".utf8).write(to: destA)
        try Data("b0".utf8).write(to: destB)

        _ = try writer.write(Data("a1".utf8), to: destA, label: "com.example.a", reason: "r")
        _ = try writer.write(Data("b1".utf8), to: destB, label: "com.example.b", reason: "r")

        let subdirs = try FileManager.default.contentsOfDirectory(atPath: backupsRoot.path).sorted()
        XCTAssertEqual(subdirs, ["com.example.a", "com.example.b"])
    }

    // MARK: - 10. binary plist / XML 問わず扱える

    func testHandlesBinaryPlist() throws {
        let writer = PlistAtomicWriter(backupsRootURL: backupsRoot)
        let dest = agentsDir.appendingPathComponent("com.example.binary.plist")
        let dict: [String: Any] = ["Label": "com.example.binary", "StartInterval": 60]
        let binary = try PropertyListSerialization.data(
            fromPropertyList: dict,
            format: .binary,
            options: 0
        )

        _ = try writer.write(binary, to: dest, label: "com.example.binary", reason: "binary")

        let readback = try Data(contentsOf: dest)
        XCTAssertEqual(readback, binary)
        let parsed = try PlistParser.parse(readback)
        XCTAssertEqual(parsed.label, "com.example.binary")
        XCTAssertEqual(parsed.startInterval, 60)
    }

    func testHandlesXmlPlist() throws {
        let writer = PlistAtomicWriter(backupsRootURL: backupsRoot)
        let dest = agentsDir.appendingPathComponent("com.example.xml.plist")
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.example.xml</string>
        </dict>
        </plist>
        """
        let payload = Data(xml.utf8)

        _ = try writer.write(payload, to: dest, label: "com.example.xml", reason: "xml")

        XCTAssertEqual(try Data(contentsOf: dest), payload)
        XCTAssertEqual(try PlistParser.parse(payload).label, "com.example.xml")
    }

    // MARK: - Helpers

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int
    ) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        c.minute = minute
        c.second = second
        return Calendar.current.date(from: c)!
    }
}

/// Sendable な Date シーケンスを順に返すテスト用クロック。
/// Swift 6 の `@Sendable` クロージャで `var` キャプチャできないための代替。
private final class SequentialClock: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Date]

    init(values: [Date]) {
        self.values = values
    }

    func next() -> Date {
        lock.lock()
        defer { lock.unlock() }
        precondition(!values.isEmpty, "SequentialClock exhausted")
        return values.removeFirst()
    }
}
