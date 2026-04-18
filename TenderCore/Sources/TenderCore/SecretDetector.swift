import Foundation

/// EnvironmentVariables の値から既知の秘密情報 prefix を検出する。
///
/// 目的は完全網羅ではなく、「明らかに平文で書くべきでないトークン」を警告すること。
/// false negative（検知漏れ）より false positive（過剰警告）の方がタチが悪いので、
/// プロバイダ公式の prefix 形式のみを採用する（ヒューリスティック検出はしない）。
public enum SecretDetector {
    /// 既知の秘密 prefix 定義。
    public struct Pattern: Sendable, Equatable {
        public let provider: String
        public let prefix: String
        public let description: String

        public init(provider: String, prefix: String, description: String) {
            self.provider = provider
            self.prefix = prefix
            self.description = description
        }
    }

    /// 検出結果。
    public struct DetectedSecret: Sendable, Equatable {
        /// EnvironmentVariables のキー名（例: `GH_TOKEN`）
        public let key: String
        /// マッチしたパターン
        public let pattern: Pattern

        public init(key: String, pattern: Pattern) {
            self.key = key
            self.pattern = pattern
        }
    }

    /// Tender がデフォルトで使う既知パターン。
    public static let defaultPatterns: [Pattern] = [
        Pattern(provider: "GitHub", prefix: "ghp_", description: "GitHub Personal Access Token (classic)"),
        Pattern(provider: "GitHub", prefix: "gho_", description: "GitHub OAuth access token"),
        Pattern(provider: "GitHub", prefix: "ghu_", description: "GitHub user-to-server token"),
        Pattern(provider: "GitHub", prefix: "ghs_", description: "GitHub server-to-server token"),
        Pattern(provider: "GitHub", prefix: "ghr_", description: "GitHub refresh token"),
        Pattern(provider: "GitHub", prefix: "github_pat_", description: "GitHub fine-grained PAT"),
        Pattern(provider: "OpenAI / Anthropic", prefix: "sk-", description: "OpenAI / Anthropic 等の secret key"),
        Pattern(provider: "Slack", prefix: "xoxb-", description: "Slack bot user OAuth token"),
        Pattern(provider: "Slack", prefix: "xoxp-", description: "Slack user OAuth token"),
        Pattern(provider: "Slack", prefix: "xoxa-", description: "Slack user token (legacy)"),
        Pattern(provider: "Slack", prefix: "xoxs-", description: "Slack session token"),
        Pattern(provider: "AWS", prefix: "AKIA", description: "AWS access key id"),
        Pattern(provider: "AWS", prefix: "ASIA", description: "AWS temporary access key id"),
        Pattern(provider: "SendGrid", prefix: "SG.", description: "SendGrid API key"),
        Pattern(provider: "Stripe", prefix: "sk_live_", description: "Stripe live secret key"),
        Pattern(provider: "Stripe", prefix: "sk_test_", description: "Stripe test secret key"),
        Pattern(provider: "Stripe", prefix: "rk_live_", description: "Stripe live restricted key"),
        Pattern(provider: "Google", prefix: "AIza", description: "Google API key")
    ]

    /// `LaunchAgent` の EnvironmentVariables を走査する。
    public static func detect(
        in agent: LaunchAgent,
        patterns: [Pattern] = defaultPatterns
    ) -> [DetectedSecret] {
        detect(in: agent.environmentVariables, patterns: patterns)
    }

    /// 任意の dict を走査する（テスト用途）。
    public static func detect(
        in environmentVariables: [String: String],
        patterns: [Pattern] = defaultPatterns
    ) -> [DetectedSecret] {
        var results: [DetectedSecret] = []
        for (key, value) in environmentVariables {
            for pattern in patterns where value.hasPrefix(pattern.prefix) {
                results.append(DetectedSecret(key: key, pattern: pattern))
                break  // 同じ値に複数 prefix がマッチしたら最初のものだけ報告
            }
        }
        // 決定的に並べる（テスト・UI 双方で安定）
        results.sort { $0.key < $1.key }
        return results
    }
}
