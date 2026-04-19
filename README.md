# launchd-tender

自分用の launchd GUI マネージャー。macOS ネイティブ（Swift 6 + SwiftUI + SwiftData）。

## コンセプト

> **「launchd ジョブを世話する道具」**

`~/Library/LaunchAgents/*.plist` を気持ちよく眺めて、状態を把握して、安全に操作するためのアプリ。**自分の道具**として作る。市場投入は目的ではない。

## Display Name

- アプリ名: **Tender**
- Bundle ID: `com.uto-usui.tender`
- リポジトリ / ディレクトリ名: `launchd-tender`

## 要件

- macOS 15.7.1 以上（**macOS 26+ 推奨**）
- Xcode 16 以上、Swift 6.0
- `xcodegen`（プロジェクト生成。`.xcodeproj` は gitignore）

## セットアップ

```bash
# 初回のみ
brew install xcodegen
xcodegen generate        # project.yml から Tender.xcodeproj を生成

# ビルド
xcodebuild -project Tender.xcodeproj -scheme Tender build

# テスト（TenderCore、176 ケース）
cd TenderCore && swift test
```

Xcode で開くなら `open Tender.xcodeproj`。

## 機能（現状）

### 観察
- `~/Library/LaunchAgents/*.plist` 自動スキャン + `DispatchSource` による変更監視（追加 / 削除 / rename で自動リロード）
- サイドバー: ジョブ一覧、状態バッジ（有効 / 無効 / 実行ファイル欠落 / 実行権限なし）、Intent の one-liner、次回実行推定
- 詳細ペイン: label / sourcePath / ProgramArguments / StartInterval / StartCalendarInterval（人間可読）/ EnvironmentVariables / plist raw viewer（XML 化、折り畳み）

### 操作
- enable / disable / kickstart / kickstart -k（再起動）/ bootout → bootstrap（再読込）
- 実行中はボタンを無効化、結果はトーストで表示（成功 3 秒自動消滅、失敗は手動 dismiss で stderr / exit code 可視化）

### 意味付け（Intent）
- ジョブごとに「なぜ存在するか / 期待頻度 / 失敗時影響 / 依存秘密 / 復旧手順」を SwiftData に保存
- `@Attribute(.unique) label` で UPSERT、サイドバーは why を one-liner に畳んで表示

### 診断（障害切り分けシート）
- 1 画面集約: label / 状態 / 実行ファイル存在 / PATH・WorkingDirectory・env / StandardOut・ErrorPath の末尾 40 行（FSEvents リアルタイム更新、エラー行 red）
- **Unified Log**: `log show --predicate 'process == "<basename>"' --last 1h --style ndjson` を呼び、error/fault 行を色分け
- 秘密情報検出: 既知 prefix（`ghp_` / `github_pat_` / `sk-` / `xoxb-` / `AKIA` / `SG.` / `AIza` ほか）にマッチする値を警告
- Intent の復旧手順をその場で表示、TCC / Full Disk Access の注意喚起

### Keychain ラッパ移行（Phase 6）
launchd は Keychain 参照記法を理解しないため、**ラッパー script 経由**で実現する。

- 検出した平文 env に「Keychain へ移動」ボタン
- プレビュー 2 段階（plist 差分 / 生成 wrapper タブ）で実行前に確認
- 逆順 rollback: Keychain 書き込み → wrapper script → plist atomic 書き換えの順、どこで失敗しても元に戻る
- 管理下の plist は `TenderManaged: true` / `TenderWrappedEnvs` / `TenderOriginalProgramArguments` meta key で自己識別
- 「Keychain 解除」で元に戻せる（Keychain エントリは既定で残す、再移行時の再入力を省くため）

### バックアップ / 復元
- plist 書き換え前は常に `~/Library/Application Support/Tender/backups/<label>/<timestamp>.plist` に atomic コピー
- SwiftData `BackupEntry` として履歴保存
- 「バックアップ履歴」sheet: 一覧 + 内容プレビュー + confirmationDialog 経由で復元（復元前も自動バックアップ）

## アーキテクチャ

```
Tender/                     # SwiftUI アプリターゲット
TenderCore/                 # ローカル Swift Package（テスト可能なドメインロジック）
  ├── LaunchAgent           # plist を映したスナップショット型
  ├── PlistParser           # PropertyListSerialization ラッパ（XML / binary 両対応）
  ├── LaunchctlClient       # launchctl 操作の抽象（Process 実装 + Mock）
  ├── KeychainClient        # /usr/bin/security 抽象（Process 実装 + Mock）
  ├── UnifiedLogClient      # /usr/bin/log show + ndjson パーサ
  ├── KeychainMigration*    # plan / composer / service / detach（逆順 rollback）
  ├── PlistAtomicWriter     # 書き換え前コピー + atomic replace
  ├── BackupRecorder        # PlistAtomicWriter の Record を SwiftData に永続化
  ├── FileTailWatcher       # 単一ファイル監視（DispatchSource）
  └── TenderSchemaV1        # SwiftData VersionedSchema
```

テストは `TenderCore/Tests/TenderCoreTests/` にまとめる（176 ケース、0 failure）。

## ドキュメント

- [CLAUDE.md](./CLAUDE.md) — エージェント向けプロジェクト指示・ガードレール
- [DESIGN.md](./DESIGN.md) — UI デザインガイドライン
- [設計メモ v2](./ai/todo/design.md) — 技術選定・機能仕様・議論の経緯
- [タスクリスト](./ai/todo/tasks.md) — Phase 1〜7 の実装状況
- [docs/plans/](./docs/plans/) — Phase ごとの design doc / implementation plan
- [参考: azu/launchd-ui](./ai/todo/reference-launchd-ui.md) — 先行実装（Tauri + React 版）

## スコープ

- **対象**: `~/Library/LaunchAgents/*.plist` のみ
- **対象外**: `/Library/LaunchAgents` / `/Library/LaunchDaemons` / `/System/...`（将来検討）

## 技術的ガードレール（抜粋、詳細は CLAUDE.md / 設計メモ）

1. `launchctl print` のパースを主データ源にしない（man page で NOT API 明示）
2. plist 書き込みは atomic write（tmp file → rename）
3. 書き込み前にファイルコピーでバックアップ（例外なし）
4. SwiftData は versioned schema + migration plan を初期から
5. Keychain 参照は launchd が理解しないので、ラッパー実行ファイル経由で実装
6. 次回実行時刻は推定値（UI に「推定」ラベル）
7. TCC / Full Disk Access の要求は最小限（他ユーザーの plist は読まない）

