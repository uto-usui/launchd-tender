import XCTest
@testable import TenderCore

final class PlistParserTests: XCTestCase {
    func testParsesMinimalAgent() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.example.minimal</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/echo</string>
                <string>hello</string>
            </array>
        </dict>
        </plist>
        """
        let agent = try PlistParser.parse(Data(xml.utf8))

        XCTAssertEqual(agent.label, "com.example.minimal")
        XCTAssertEqual(agent.programArguments, ["/bin/echo", "hello"])
        XCTAssertFalse(agent.runAtLoad)
        XCTAssertEqual(agent.keepAlive, .disabled)
        XCTAssertNil(agent.startInterval)
        XCTAssertTrue(agent.startCalendarInterval.isEmpty)
    }

    func testParsesStartInterval() throws {
        let xml = plistWrapping("""
            <key>Label</key>
            <string>com.example.interval</string>
            <key>StartInterval</key>
            <integer>3600</integer>
            <key>RunAtLoad</key>
            <true/>
        """)

        let agent = try PlistParser.parse(Data(xml.utf8))

        XCTAssertEqual(agent.startInterval, 3600)
        XCTAssertTrue(agent.runAtLoad)
    }

    func testParsesStartCalendarIntervalSingleDict() throws {
        let xml = plistWrapping("""
            <key>Label</key>
            <string>com.example.daily</string>
            <key>StartCalendarInterval</key>
            <dict>
                <key>Hour</key><integer>8</integer>
                <key>Minute</key><integer>30</integer>
            </dict>
        """)

        let agent = try PlistParser.parse(Data(xml.utf8))

        XCTAssertEqual(agent.startCalendarInterval.count, 1)
        XCTAssertEqual(agent.startCalendarInterval[0].hour, 8)
        XCTAssertEqual(agent.startCalendarInterval[0].minute, 30)
        XCTAssertNil(agent.startCalendarInterval[0].weekday)
    }

    func testParsesStartCalendarIntervalArray() throws {
        let xml = plistWrapping("""
            <key>Label</key>
            <string>com.example.twice-daily</string>
            <key>StartCalendarInterval</key>
            <array>
                <dict>
                    <key>Hour</key><integer>8</integer>
                </dict>
                <dict>
                    <key>Hour</key><integer>17</integer>
                </dict>
            </array>
        """)

        let agent = try PlistParser.parse(Data(xml.utf8))

        XCTAssertEqual(agent.startCalendarInterval.count, 2)
        XCTAssertEqual(agent.startCalendarInterval.map(\.hour), [8, 17])
    }

    func testParsesEnvironmentVariables() throws {
        let xml = plistWrapping("""
            <key>Label</key>
            <string>com.example.env</string>
            <key>EnvironmentVariables</key>
            <dict>
                <key>GH_TOKEN</key><string>ghp_xxxxxxxx</string>
                <key>PATH</key><string>/usr/local/bin:/usr/bin</string>
            </dict>
        """)

        let agent = try PlistParser.parse(Data(xml.utf8))

        XCTAssertEqual(agent.environmentVariables["GH_TOKEN"], "ghp_xxxxxxxx")
        XCTAssertEqual(agent.environmentVariables["PATH"], "/usr/local/bin:/usr/bin")
    }

    func testParsesKeepAliveBool() throws {
        let xml = plistWrapping("""
            <key>Label</key>
            <string>com.example.always</string>
            <key>KeepAlive</key>
            <true/>
        """)

        let agent = try PlistParser.parse(Data(xml.utf8))
        XCTAssertEqual(agent.keepAlive, .always)
    }

    func testParsesKeepAliveConditions() throws {
        let xml = plistWrapping("""
            <key>Label</key>
            <string>com.example.conditional</string>
            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key><false/>
                <key>Crashed</key><true/>
            </dict>
        """)

        let agent = try PlistParser.parse(Data(xml.utf8))
        guard case let .conditions(conds) = agent.keepAlive else {
            return XCTFail("KeepAlive should be .conditions, got \(agent.keepAlive)")
        }
        XCTAssertEqual(conds.successfulExit, false)
        XCTAssertEqual(conds.crashed, true)
    }

    func testEmptyProgramArgumentsDefaultsToEmpty() throws {
        let xml = plistWrapping("""
            <key>Label</key>
            <string>com.example.noargs</string>
        """)

        let agent = try PlistParser.parse(Data(xml.utf8))
        XCTAssertTrue(agent.programArguments.isEmpty)
    }

    func testMissingLabelThrows() {
        let xml = plistWrapping("""
            <key>ProgramArguments</key>
            <array><string>/bin/true</string></array>
        """)

        XCTAssertThrowsError(try PlistParser.parse(Data(xml.utf8))) { error in
            XCTAssertEqual(error as? PlistParser.Error, .missingLabel)
        }
    }

    func testEmptyLabelThrows() {
        let xml = plistWrapping("""
            <key>Label</key>
            <string></string>
        """)

        XCTAssertThrowsError(try PlistParser.parse(Data(xml.utf8))) { error in
            XCTAssertEqual(error as? PlistParser.Error, .missingLabel)
        }
    }

    func testMalformedPlistThrowsInvalidFormat() {
        let data = Data("not a plist".utf8)

        XCTAssertThrowsError(try PlistParser.parse(data)) { error in
            XCTAssertEqual(error as? PlistParser.Error, .invalidFormat)
        }
    }

    func testArrayRootThrowsRootIsNotDictionary() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <array><string>oops</string></array>
        </plist>
        """

        XCTAssertThrowsError(try PlistParser.parse(Data(xml.utf8))) { error in
            XCTAssertEqual(error as? PlistParser.Error, .rootIsNotDictionary)
        }
    }

    func testBinaryPlistIsAccepted() throws {
        let dict: [String: Any] = [
            "Label": "com.example.binary",
            "StartInterval": 60,
            "RunAtLoad": true
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)

        let agent = try PlistParser.parse(data)

        XCTAssertEqual(agent.label, "com.example.binary")
        XCTAssertEqual(agent.startInterval, 60)
        XCTAssertTrue(agent.runAtLoad)
    }

    func testParsesFromFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("tender-test-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let xml = plistWrapping("""
            <key>Label</key>
            <string>com.example.fromfile</string>
        """)
        try Data(xml.utf8).write(to: fileURL)

        let agent = try PlistParser.parse(contentsOf: fileURL)

        XCTAssertEqual(agent.label, "com.example.fromfile")
        XCTAssertEqual(agent.sourcePath, fileURL)
    }

    // MARK: - Tender meta keys

    func testParsesTenderMetaKeys() throws {
        let xml = plistWrapping("""
            <key>Label</key>
            <string>com.example.managed</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/bash</string>
                <string>/path/to/wrapper.sh</string>
            </array>
            <key>TenderManaged</key><true/>
            <key>TenderWrappedEnvs</key>
            <array>
                <string>GH_TOKEN</string>
                <string>SLACK_TOKEN</string>
            </array>
            <key>TenderOriginalProgramArguments</key>
            <array>
                <string>/usr/local/bin/poller</string>
                <string>--once</string>
            </array>
        """)
        let agent = try PlistParser.parse(Data(xml.utf8))

        XCTAssertTrue(agent.tenderManaged)
        XCTAssertEqual(agent.tenderWrappedEnvs, ["GH_TOKEN", "SLACK_TOKEN"])
        XCTAssertEqual(agent.tenderOriginalProgramArguments, ["/usr/local/bin/poller", "--once"])
    }

    func testMissingTenderMetaKeysDefaultsToUnmanaged() throws {
        let xml = plistWrapping("""
            <key>Label</key><string>com.example.plain</string>
            <key>ProgramArguments</key><array><string>/bin/true</string></array>
        """)
        let agent = try PlistParser.parse(Data(xml.utf8))

        XCTAssertFalse(agent.tenderManaged)
        XCTAssertTrue(agent.tenderWrappedEnvs.isEmpty)
        XCTAssertTrue(agent.tenderOriginalProgramArguments.isEmpty)
    }

    // MARK: - Helpers

    private func plistWrapping(_ body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \(body)
        </dict>
        </plist>
        """
    }
}
