import XCTest
import SwiftData
@testable import TenderCore

@MainActor
final class BackupRecorderTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        container = try TenderModelContainer.makeContainer(configuration: .inMemory)
    }

    override func tearDownWithError() throws {
        container = nil
    }

    func testRecordSingleBackupInsertsEntry() throws {
        let recorder = BackupRecorder(context: context)
        let record = PlistAtomicWriter.BackupRecord(
            label: "com.example.job",
            timestamp: Date(timeIntervalSince1970: 1_000_000),
            plistPath: URL(fileURLWithPath: "/tmp/backup/com.example.job/20260419-120000.plist"),
            reason: "keychain-migration"
        )
        try recorder.record(record)

        let fetched = try context.fetch(FetchDescriptor<BackupEntry>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].label, "com.example.job")
        XCTAssertEqual(fetched[0].reason, "keychain-migration")
        XCTAssertEqual(fetched[0].plistPath, "/tmp/backup/com.example.job/20260419-120000.plist")
    }

    func testRecordArrayIgnoresNil() throws {
        let recorder = BackupRecorder(context: context)
        let record = PlistAtomicWriter.BackupRecord(
            label: "l", timestamp: Date(), plistPath: URL(fileURLWithPath: "/x"),
            reason: "r"
        )
        try recorder.record([nil, record, nil])

        let fetched = try context.fetch(FetchDescriptor<BackupEntry>())
        XCTAssertEqual(fetched.count, 1)
    }

    func testMultipleRecordsAccumulate() throws {
        let recorder = BackupRecorder(context: context)
        try recorder.record(PlistAtomicWriter.BackupRecord(
            label: "l1", timestamp: Date(), plistPath: URL(fileURLWithPath: "/a"), reason: "r1"
        ))
        try recorder.record(PlistAtomicWriter.BackupRecord(
            label: "l2", timestamp: Date(), plistPath: URL(fileURLWithPath: "/b"), reason: "r2"
        ))

        let fetched = try context.fetch(FetchDescriptor<BackupEntry>(sortBy: [SortDescriptor(\.label)]))
        XCTAssertEqual(fetched.map(\.label), ["l1", "l2"])
    }
}
