import XCTest
@testable import TenderCore

final class SchedulePlistComposerTests: XCTestCase {
    private func plist(_ dict: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    private func parse(_ data: Data) throws -> [String: Any] {
        try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: Any]
    }

    func testSetStartInterval() throws {
        let original = try plist([
            "Label": "com.example.job",
            "ProgramArguments": ["/bin/true"]
        ])
        let newData = try SchedulePlistComposer.compose(
            originalData: original, startInterval: 3600, startCalendarInterval: []
        )
        let dict = try parse(newData)
        XCTAssertEqual(dict["StartInterval"] as? Int, 3600)
        XCTAssertNil(dict["StartCalendarInterval"])
        XCTAssertEqual(dict["Label"] as? String, "com.example.job")
    }

    func testRemoveStartIntervalWhenNil() throws {
        let original = try plist([
            "Label": "com.example.job",
            "StartInterval": 60
        ])
        let newData = try SchedulePlistComposer.compose(
            originalData: original, startInterval: nil, startCalendarInterval: []
        )
        let dict = try parse(newData)
        XCTAssertNil(dict["StartInterval"])
    }

    func testSingleCalendarEntryEmittedAsDict() throws {
        let original = try plist([
            "Label": "com.example.job",
            "ProgramArguments": ["/bin/true"]
        ])
        let newData = try SchedulePlistComposer.compose(
            originalData: original, startInterval: nil,
            startCalendarInterval: [.init(minute: 0, hour: 8)]
        )
        let dict = try parse(newData)
        let sci = dict["StartCalendarInterval"] as? [String: Any]
        XCTAssertNotNil(sci)
        XCTAssertEqual(sci?["Hour"] as? Int, 8)
        XCTAssertEqual(sci?["Minute"] as? Int, 0)
        XCTAssertNil(sci?["Weekday"])
    }

    func testMultipleCalendarEntriesEmittedAsArray() throws {
        let original = try plist(["Label": "com.example.job"])
        let entries: [StartCalendarEntry] = [
            .init(minute: 0, hour: 8),
            .init(minute: 0, hour: 17)
        ]
        let newData = try SchedulePlistComposer.compose(
            originalData: original, startInterval: nil, startCalendarInterval: entries
        )
        let dict = try parse(newData)
        let sci = dict["StartCalendarInterval"] as? [[String: Any]]
        XCTAssertEqual(sci?.count, 2)
        XCTAssertEqual(sci?[0]["Hour"] as? Int, 8)
        XCTAssertEqual(sci?[1]["Hour"] as? Int, 17)
    }

    func testBothIntervalAndCalendarCanCoexist() throws {
        let original = try plist(["Label": "com.example.job"])
        let newData = try SchedulePlistComposer.compose(
            originalData: original, startInterval: 900,
            startCalendarInterval: [.init(hour: 9)]
        )
        let dict = try parse(newData)
        XCTAssertEqual(dict["StartInterval"] as? Int, 900)
        XCTAssertNotNil(dict["StartCalendarInterval"])
    }

    func testRemoveBothWhenNone() throws {
        let original = try plist([
            "Label": "com.example.job",
            "StartInterval": 60,
            "StartCalendarInterval": ["Hour": 8] as [String: Int]
        ])
        let newData = try SchedulePlistComposer.compose(
            originalData: original, startInterval: nil, startCalendarInterval: []
        )
        let dict = try parse(newData)
        XCTAssertNil(dict["StartInterval"])
        XCTAssertNil(dict["StartCalendarInterval"])
    }

    func testPreservesUnrelatedKeys() throws {
        let original = try plist([
            "Label": "com.example.job",
            "ProgramArguments": ["/usr/local/bin/x", "--flag"],
            "EnvironmentVariables": ["A": "1"],
            "RunAtLoad": true,
            "StartInterval": 60
        ])
        let newData = try SchedulePlistComposer.compose(
            originalData: original, startInterval: 3600,
            startCalendarInterval: []
        )
        let dict = try parse(newData)
        XCTAssertEqual(dict["Label"] as? String, "com.example.job")
        XCTAssertEqual(dict["ProgramArguments"] as? [String], ["/usr/local/bin/x", "--flag"])
        XCTAssertEqual(dict["EnvironmentVariables"] as? [String: String], ["A": "1"])
        XCTAssertEqual(dict["RunAtLoad"] as? Bool, true)
    }

    func testEntryWithNilFieldsOmitsKeys() throws {
        let original = try plist(["Label": "j"])
        let newData = try SchedulePlistComposer.compose(
            originalData: original, startInterval: nil,
            startCalendarInterval: [.init(hour: 12)]
        )
        let dict = try parse(newData)
        let sci = dict["StartCalendarInterval"] as? [String: Any]
        XCTAssertEqual(sci?.keys.sorted(), ["Hour"])
    }

    func testInvalidDataThrows() {
        XCTAssertThrowsError(try SchedulePlistComposer.compose(
            originalData: Data("not plist".utf8),
            startInterval: 60, startCalendarInterval: []
        )) { error in
            XCTAssertEqual(error as? SchedulePlistComposer.ComposeError, .invalidFormat)
        }
    }

    func testRootIsNotDictThrows() throws {
        let array = try PropertyListSerialization.data(
            fromPropertyList: [1, 2, 3] as [Int], format: .xml, options: 0
        )
        XCTAssertThrowsError(try SchedulePlistComposer.compose(
            originalData: array, startInterval: nil, startCalendarInterval: []
        )) { error in
            XCTAssertEqual(error as? SchedulePlistComposer.ComposeError, .rootIsNotDictionary)
        }
    }

    func testOutputIsXML() throws {
        let original = try plist(["Label": "j"])
        let newData = try SchedulePlistComposer.compose(
            originalData: original, startInterval: 60, startCalendarInterval: []
        )
        let prefix = String(data: newData.prefix(40), encoding: .utf8) ?? ""
        XCTAssertTrue(prefix.contains("<?xml"))
    }
}
