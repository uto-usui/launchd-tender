import Foundation

/// plist の `ProgramArguments` を Keychain から値を読み出すラッパー script に置き換えるためのビルダ。
///
/// 生成 script:
/// ```bash
/// #!/bin/bash
/// # Tender-managed wrapper for <label>
/// # Generated: <ISO8601 timestamp>
/// # Source plist: <path>
/// set -euo pipefail
///
/// export GH_TOKEN="$(security find-generic-password -s 'com.uto-usui.tender' -a 'job.GH_TOKEN' -w)"
///
/// exec '/usr/local/bin/poller' '--once'
/// ```
///
/// - `exec` で置換するため PID / signal が透過し、launchctl の `kill -k` が wrapper を介さず届く
/// - 引数は POSIX 単引用符包囲でエスケープ（`'` は `'"'"'` に置換）
/// - env キーは `[A-Za-z_][A-Za-z0-9_]*` 想定だが、builder 自体は素通しする（UI 側で事前にバリデーション）
public enum WrapperScriptBuilder {
    public enum BuilderError: Error, Equatable, Sendable {
        case emptyProgramArguments
    }

    /// 検証あり版。`programArguments` が空ならエラー。
    public static func buildOrThrow(
        label: String,
        envKeys: [String],
        programArguments: [String],
        keychainService: String,
        generatedAt: Date,
        sourcePlistPath: String
    ) throws -> String {
        guard !programArguments.isEmpty else {
            throw BuilderError.emptyProgramArguments
        }
        return build(
            label: label,
            envKeys: envKeys,
            programArguments: programArguments,
            keychainService: keychainService,
            generatedAt: generatedAt,
            sourcePlistPath: sourcePlistPath
        )
    }

    /// 検証なし版。空 argv でも組み立てるが生成物は無意味（テスト用途）。
    public static func build(
        label: String,
        envKeys: [String],
        programArguments: [String],
        keychainService: String,
        generatedAt: Date,
        sourcePlistPath: String
    ) -> String {
        var lines: [String] = []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        lines.append("#!/bin/bash")
        lines.append("# Tender-managed wrapper for \(label)")
        lines.append("# Generated: \(formatter.string(from: generatedAt))")
        lines.append("# Source plist: \(sourcePlistPath)")
        lines.append("set -euo pipefail")
        lines.append("")

        if envKeys.isEmpty {
            lines.append("# (no Keychain-backed env vars)")
        } else {
            for key in envKeys {
                let account = "\(label).\(key)"
                let escapedService = shellSingleQuote(keychainService)
                let escapedAccount = shellSingleQuote(account)
                lines.append(
                    "export \(key)=\"$(security find-generic-password -s \(escapedService) -a \(escapedAccount) -w)\""
                )
            }
        }

        lines.append("")
        let escapedArgv = programArguments.map(shellSingleQuote).joined(separator: " ")
        lines.append("exec \(escapedArgv)")
        lines.append("") // trailing newline

        return lines.joined(separator: "\n")
    }

    /// POSIX shell 単引用符エスケープ。
    /// - 引用符内の `'` を `'"'"'` に置換し、全体を `'...'` で包む。
    /// - 空白 / `$` / `` ` `` / `\` / 改行 / `"` は全て単引用符内で無力化される。
    package static func shellSingleQuote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }

}
