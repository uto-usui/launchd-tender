import XCTest
@testable import TenderCore

final class SecretDetectorTests: XCTestCase {
    func testDetectsGitHubClassicPAT() {
        let result = SecretDetector.detect(in: ["GH_TOKEN": "ghp_abcdefghijklmnopqrstuvwxyz0123456789"])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].key, "GH_TOKEN")
        XCTAssertEqual(result[0].pattern.prefix, "ghp_")
    }

    func testDetectsGitHubFineGrainedPAT() {
        let result = SecretDetector.detect(in: ["GH_PAT": "github_pat_xxxxx"])
        XCTAssertEqual(result.first?.pattern.prefix, "github_pat_")
    }

    func testDetectsSlackBotToken() {
        let result = SecretDetector.detect(in: ["SLACK_BOT_TOKEN": "xoxb-1234567890-abcdefghij"])
        XCTAssertEqual(result.first?.pattern.provider, "Slack")
    }

    func testDetectsAWSAccessKey() {
        let result = SecretDetector.detect(in: ["AWS_ACCESS_KEY_ID": "AKIAIOSFODNN7EXAMPLE"])
        XCTAssertEqual(result.first?.pattern.prefix, "AKIA")
    }

    func testDetectsOpenAISecret() {
        let result = SecretDetector.detect(in: ["OPENAI_API_KEY": "sk-proj-abc123"])
        XCTAssertEqual(result.first?.pattern.prefix, "sk-")
    }

    func testReturnsMultipleHitsSortedByKey() {
        let env = [
            "SLACK_TOKEN": "xoxb-1-2-3",
            "AWS_KEY": "AKIASOMETHING",
            "GH_TOKEN": "ghp_xxx",
            "PATH": "/usr/local/bin"  // non-secret, ignored
        ]
        let result = SecretDetector.detect(in: env)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map(\.key), ["AWS_KEY", "GH_TOKEN", "SLACK_TOKEN"])
    }

    func testIgnoresValuesWithoutKnownPrefix() {
        let env = [
            "SOMETHING": "plain_string",
            "NUMERIC": "12345",
            "LOOKS_LIKE_TOKEN_BUT_NOT": "xyz_ghp_fake"  // prefix が先頭でないので検出しない
        ]
        XCTAssertTrue(SecretDetector.detect(in: env).isEmpty)
    }

    func testEmptyEnvironmentReturnsEmpty() {
        XCTAssertTrue(SecretDetector.detect(in: [:]).isEmpty)
    }

    func testWorksOnLaunchAgent() {
        let agent = LaunchAgent(
            label: "com.example.needs-gh",
            environmentVariables: ["GH_TOKEN": "ghp_needs_move_to_keychain"]
        )
        let result = SecretDetector.detect(in: agent)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].key, "GH_TOKEN")
    }

    func testCustomPatternsOverrideDefaults() {
        let custom = [SecretDetector.Pattern(provider: "ACME", prefix: "acme_", description: "ACME test")]
        let result = SecretDetector.detect(
            in: ["X": "acme_match", "Y": "ghp_not_matched_with_custom_only"],
            patterns: custom
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].pattern.provider, "ACME")
    }

    func testFirstMatchWinsWhenMultiplePrefixes() {
        // 同じ値に対しては1つだけ報告（誤検出の増幅を防ぐ）
        let custom = [
            SecretDetector.Pattern(provider: "A", prefix: "sk-", description: "a"),
            SecretDetector.Pattern(provider: "B", prefix: "sk-l", description: "b")
        ]
        let result = SecretDetector.detect(
            in: ["K": "sk-live-something"],
            patterns: custom
        )
        XCTAssertEqual(result.count, 1)
    }
}
