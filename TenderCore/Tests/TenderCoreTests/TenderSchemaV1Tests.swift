import XCTest
import SwiftData
@testable import TenderCore

@MainActor
final class TenderSchemaV1Tests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        container = try TenderModelContainer.makeContainer(configuration: .inMemory)
    }

    override func tearDownWithError() throws {
        container = nil
    }

    // MARK: - Intent

    func testInsertAndFetchIntent() throws {
        let intent = TenderSchemaV1.Intent(
            label: "com.example.pull",
            why: "家計データ更新",
            frequencyExpected: "毎日 JST 08:00 / 17:00",
            impactOnFailure: ImpactOnFailure.medium.rawValue,
            secretsUsed: ["MF_ACCESS_TOKEN"],
            recoverySteps: "手動で bin/pull を実行"
        )
        context.insert(intent)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TenderSchemaV1.Intent>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].label, "com.example.pull")
        XCTAssertEqual(fetched[0].why, "家計データ更新")
        XCTAssertEqual(fetched[0].secretsUsed, ["MF_ACCESS_TOKEN"])
    }

    func testIntentLabelUniqueActsAsUpsert() throws {
        // SwiftData の `@Attribute(.unique)` は「例外で拒否」ではなく UPSERT 意味論を持つ。
        // 同じ label で insert すると新レコードが既存を上書きする。
        // この挙動はドキュメント化されており、Tender の保存層は常に upsert 前提で書く。
        let first = TenderSchemaV1.Intent(label: "com.example.dup", why: "初回")
        context.insert(first)
        try context.save()

        let second = TenderSchemaV1.Intent(label: "com.example.dup", why: "上書き")
        context.insert(second)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TenderSchemaV1.Intent>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].why, "上書き")
    }

    func testFetchIntentByLabelPredicate() throws {
        let targetLabel = "com.example.needle"
        context.insert(TenderSchemaV1.Intent(label: "com.example.a"))
        context.insert(TenderSchemaV1.Intent(label: targetLabel, why: "target"))
        context.insert(TenderSchemaV1.Intent(label: "com.example.b"))
        try context.save()

        var descriptor = FetchDescriptor<TenderSchemaV1.Intent>(
            predicate: #Predicate { $0.label == targetLabel }
        )
        descriptor.fetchLimit = 1

        let result = try context.fetch(descriptor)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].why, "target")
    }

    // MARK: - BackupEntry

    func testInsertAndFetchBackupEntry() throws {
        let entry = TenderSchemaV1.BackupEntry(
            label: "com.example.job",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            plistPath: "/tmp/tender-backups/com.example.job/20241114T120000.plist",
            reason: "pre-edit"
        )
        context.insert(entry)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TenderSchemaV1.BackupEntry>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].reason, "pre-edit")
        XCTAssertEqual(fetched[0].plistPath.hasSuffix(".plist"), true)
    }

    func testMultipleBackupsForSameLabel() throws {
        let label = "com.example.many"
        for i in 0..<3 {
            context.insert(TenderSchemaV1.BackupEntry(
                label: label,
                timestamp: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + i * 60)),
                plistPath: "/tmp/\(i).plist",
                reason: "pre-edit \(i)"
            ))
        }
        try context.save()

        let descriptor = FetchDescriptor<TenderSchemaV1.BackupEntry>(
            predicate: #Predicate { $0.label == label },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 3)
        XCTAssertEqual(fetched.map(\.reason), ["pre-edit 0", "pre-edit 1", "pre-edit 2"])
    }

    // MARK: - ExecutionRecord

    func testInsertAndFetchExecutionRecord() throws {
        let now = Date()
        let record = TenderSchemaV1.ExecutionRecord(
            label: "com.example.run",
            executedAt: now,
            exitCode: 0,
            durationMs: 1234
        )
        context.insert(record)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TenderSchemaV1.ExecutionRecord>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].exitCode, 0)
        XCTAssertEqual(fetched[0].durationMs, 1234)
    }

    func testExecutionRecordAllowsMissingDuration() throws {
        let record = TenderSchemaV1.ExecutionRecord(
            label: "com.example.unknown-duration",
            executedAt: Date(),
            exitCode: 1,
            durationMs: nil
        )
        context.insert(record)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TenderSchemaV1.ExecutionRecord>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertNil(fetched[0].durationMs)
        XCTAssertEqual(fetched[0].exitCode, 1)
    }

    // MARK: - Schema identity

    func testSchemaV1VersionIdentifier() {
        XCTAssertEqual(TenderSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(TenderSchemaV1.models.count, 3)
    }

    func testMigrationPlanIncludesV1() {
        XCTAssertTrue(TenderMigrationPlan.schemas.contains(where: { $0 == TenderSchemaV1.self }))
        XCTAssertTrue(TenderMigrationPlan.stages.isEmpty)
    }

    // MARK: - ImpactOnFailure helpers

    func testImpactOnFailureRoundTripsThroughString() {
        for impact in ImpactOnFailure.allCases {
            let intent = TenderSchemaV1.Intent(
                label: "com.example.\(impact.rawValue)",
                impactOnFailure: impact.rawValue
            )
            XCTAssertEqual(ImpactOnFailure(rawValue: intent.impactOnFailure), impact)
        }
    }
}
