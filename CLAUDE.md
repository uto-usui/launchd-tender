# CLAUDE.md — launchd-tender

Claude Code などコーディングエージェント向けのプロジェクト指示。

## プロジェクト概要

macOS の launchd ジョブ（`~/Library/LaunchAgents/*.plist`）を GUI で世話する**自分用**アプリ。市場投入は目的ではなく、**自分が気持ちよく使えるか**だけが評価軸。

- Display Name: **Tender**
- Bundle ID: `com.uto-usui.tender`
- リポジトリ名: `launchd-tender`

## ディレクトリ構成

```
launchd-tender/
├── CLAUDE.md                # このファイル
├── DESIGN.md                # UI デザインガイドライン
├── README.md                # プロジェクト概要
├── ai/
│   └── todo/
│       ├── design.md        # 設計メモ v2（技術選定・機能仕様）
│       ├── tasks.md         # 実装 TODO リスト
│       └── reference-launchd-ui.md  # 先行実装の参考
├── Tender/                  # (未作成) Xcode プロジェクト
└── TenderTests/             # (未作成) XCTest
```

## 技術スタック

- Swift (最新)
- SwiftUI + SwiftData
- Xcode 16+
- ターゲット: macOS 15.7.1+（macOS 26+ 推奨）

## 技術的ガードレール（絶対に守る）

1. **`launchctl print` をパースしない**
   - man page で NOT API と明示
   - OS 更新で壊れる
   - 正のデータ源: plist 内容 / `print-disabled` / コマンド exit code / ファイル存在 / 実行可能属性
2. **plist 書き込みは atomic write**
   - tmp file → rename（同一ボリューム）
3. **書き込み前に必ずファイルコピーでバックアップ**
   - `~/Library/Application Support/Tender/backups/<label>/<timestamp>.plist`
4. **SwiftData は versioned schema + migration plan を初期から**設計
5. **SwiftData を source of truth にしない**
   - plist が truth、SwiftData は Intent・メタデータ・キャッシュのみ
6. **Keychain 参照記法は launchd が理解しない**
   - `EnvironmentVariables` はただの文字列
   - Keychain 連携は**ラッパー実行ファイル経由**で実装
7. **次回実行時刻は推定値**
   - UI に「推定」ラベルを明示
8. **TCC / Full Disk Access の要求は最小限**
   - 他ユーザーの plist は読まない

## 参照すべきドキュメント

実装前に必ず読む:

- [UI デザインガイドライン](./DESIGN.md) — レイアウト・カラー・タイポグラフィ
- 設計メモ・TODO・Phase 計画は `ai/todo/` / `docs/plans/`（ローカルのみ、gitignore 済み）

## 開発方針

- LLM 並列実装 OK。1機能1ブランチでもまとめてでも可
- **テストは LaunchctlClient の mock、plist パーサ、次回実行時刻計算の3つのみ必須**
- 段階リリース・MVP 厳密定義は不要（機能揃うまで使わない、という選択も OK）
- **atomic write とバックアップは削らない**（データ破壊が唯一許せない事故）

## コーディング規約

- Swift 標準の命名規則（UpperCamelCase for types, lowerCamelCase for vars/funcs）
- インデント: **4 space**
- `// TODO:` コメントは具体的に。`// TODO` 単独は禁止
- 公開 API には DocC コメント
- `SwiftLint` を初期から入れる（ルールは緩め、徐々に厳しく）

## コミット規約

**Conventional Commits**。例:

- `feat(launchctl): add LaunchctlClient protocol with Process-based impl`
- `fix(plist): handle empty ProgramArguments gracefully`
- `docs(design): add color palette for macOS 26 Liquid Glass`
- `test(scheduler): add unit tests for StartCalendarInterval parsing`
- `chore: initial project scaffolding`

コミットは `/contextual-commit` スキル経由で。WHY と意図を本文に残す。

## やらないこと

- 市場差別化・ポジショニング議論
- 段階リリース計画（自分のペース）
- notarize / 配布戦略（必要になったら後日）
- `/Library/LaunchDaemons` のサポート（将来検討、優先度低）
- 他ユーザーの plist 読み取り

---

ドキュメント間で矛盾があれば、**この CLAUDE.md とローカルの `ai/todo/design.md` を優先**。
