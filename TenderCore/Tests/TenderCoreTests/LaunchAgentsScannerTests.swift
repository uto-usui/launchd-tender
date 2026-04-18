import XCTest
@testable import TenderCore

final class LaunchAgentsScannerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tender-scanner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testReturnsEmptyForNonexistentDirectory() async {
        let scanner = LaunchAgentsScanner(directoryURL: tempDir.appendingPathComponent("does-not-exist"))
        let result = await scanner.scan()
        XCTAssertTrue(result.agents.isEmpty)
        XCTAssertTrue(result.failures.isEmpty)
    }

    func testScansValidPlists() async throws {
        try writePlist("a.plist", label: "com.example.a")
        try writePlist("b.plist", label: "com.example.b")

        let result = await LaunchAgentsScanner(directoryURL: tempDir).scan()

        XCTAssertEqual(result.agents.map(\.label), ["com.example.a", "com.example.b"])
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.agents[0].sourcePath?.lastPathComponent, "a.plist")
    }

    func testSortsAgentsByLabel() async throws {
        try writePlist("z.plist", label: "com.example.z")
        try writePlist("a.plist", label: "com.example.a")
        try writePlist("m.plist", label: "com.example.m")

        let result = await LaunchAgentsScanner(directoryURL: tempDir).scan()
        XCTAssertEqual(result.agents.map(\.label), ["com.example.a", "com.example.m", "com.example.z"])
    }

    func testSkipsNonPlistFiles() async throws {
        try writePlist("agent.plist", label: "com.example.a")
        try "readme".data(using: .utf8)!.write(to: tempDir.appendingPathComponent("README.txt"))

        let result = await LaunchAgentsScanner(directoryURL: tempDir).scan()

        XCTAssertEqual(result.agents.count, 1)
        XCTAssertTrue(result.failures.isEmpty)
    }

    func testRecordsFailureForMalformedPlist() async throws {
        try writePlist("good.plist", label: "com.example.good")
        try "garbage".data(using: .utf8)!.write(to: tempDir.appendingPathComponent("broken.plist"))

        let result = await LaunchAgentsScanner(directoryURL: tempDir).scan()

        XCTAssertEqual(result.agents.map(\.label), ["com.example.good"])
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures[0].url.lastPathComponent, "broken.plist")
    }

    // MARK: - Helpers

    private func writePlist(_ filename: String, label: String) throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
        </dict>
        </plist>
        """
        try Data(xml.utf8).write(to: tempDir.appendingPathComponent(filename))
    }
}
