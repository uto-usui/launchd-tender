# launchd-tender

自分用の launchd GUI マネージャー。macOS ネイティブ（Swift + SwiftUI）。

## コンセプト

> **「launchd ジョブを世話する道具」**

`~/Library/LaunchAgents/*.plist` を気持ちよく眺めて、状態を把握して、安全に操作するためのアプリ。**自分の道具**として作る。市場投入は目的ではない。

## Display Name

- アプリ名: **Tender**
- Bundle ID: `com.uto-usui.tender`
- リポジトリ / ディレクトリ名: `launchd-tender`（GitHub 検索性のため）

## 要件

- macOS 15.7.1 以上（**macOS 26+ 推奨**、Liquid Glass 等の新 UI を積極採用）
- Xcode 16 以上
- Swift 最新

## 現在の状態

計画中。Xcode プロジェクト未作成。

## ドキュメント

- [設計メモ v2](./ai/todo/design.md) — 技術選定・ガードレール・タスクリスト・検討事項
- [参考: azu/launchd-ui](./ai/todo/reference-launchd-ui.md) — 先行実装（Tauri + React 版）の紹介記事

## スコープ

- **対象**: `~/Library/LaunchAgents/*.plist` のみ
- **対象外**: `/Library/LaunchAgents` / `/Library/LaunchDaemons` / `/System/...`（将来検討）

## 技術的ガードレール（抜粋、詳細は設計メモ）

1. `launchctl print` のパースを主データ源にしない（man page で NOT API 明示）
2. plist 書き込みは atomic write（tmp file → rename）
3. 書き込み前にファイルコピーでバックアップ
4. SwiftData は versioned schema + migration plan を初期から
5. Keychain 参照は launchd が理解しないので、ラッパー実行ファイル経由で実装
6. 次回実行時刻は推定値（UI に明示）

## ドッグフード対象

- `***REDACTED***` — 毎日 JST 8:00 / 17:00 に git pull
- `***REDACTED***` — 1時間おき（GHトークン平文問題あり → Keychain 連携の実証ケース）
