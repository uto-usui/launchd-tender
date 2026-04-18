# DESIGN.md — launchd-tender (Tender)

自分用 macOS アプリの UI デザインガイドライン。SwiftUI で最新 macOS のデザイン言語を素直に使う。

## 原則

1. **macOS ネイティブ第一**: Human Interface Guidelines を最大限尊重する。独自 UI は作らない
2. **気持ちよさ**: 自分用なので、自分が触って楽しいことを最優先
3. **可読性**: ジョブ状態・ログ・plist すべて「見てすぐ分かる」情報設計
4. **静けさ**: 通知・警告は必要な時だけ、普段は静か

## OS ターゲット

| OS | 扱い |
|----|------|
| macOS 26+ | メイン。Liquid Glass / 新 SF Symbols / 新コンポーネント積極利用 |
| macOS 15.7.1〜25.x | フォールバック。通常の material、旧 SF Symbols |

分岐は `#available(macOS 26, *)` で。最小は 15.7.1。

## レイアウト

### メインウィンドウ
- `NavigationSplitView`（初期は2カラム、将来3カラム化可）
  - サイドバー: ジョブ一覧 + 検索
  - 詳細ペイン: 選択ジョブの概要 / アクション / Intent / ログ / plist
- 最小サイズ: **800 × 500 pt**
- タイトルバー: `windowStyle(.hiddenTitleBar)` 検討

### サイドバー
- 幅: 240〜320 pt
- 1アイテム = 2行:
  - 上: 状態インジケータ（● 緑 / 青 / 黄 / 赤 / グレー）+ ラベル（truncate）
  - 下: Intent の1行サマリ（`.secondary` 色）
- 上部に検索フィールド常設

### 詳細ペイン
**タブを使わない。段落スクロール**で以下を順に並べる:
1. ヘッダ（ラベル、状態、次回実行 "推定"、Intent 1行）
2. アクションボタン列（有効/無効、手動実行、リロード、**障害切り分け**）
3. Intent 編集セクション
4. ログ tail（折り畳み可、デフォルト展開）
5. plist raw（折り畳み可、デフォルト閉）
6. 環境変数・パス情報

### 障害切り分けビュー
- `.sheet` で表示、縦スクロール
- セクションごとに色分け:
  - 問題なし: 通常
  - 警告: `.yellow` or systemYellow
  - 致命: `.red` or systemRed

## カラー

- **アクセント**: 当面 `Color.accentColor`（システム既定、後日確定）
- **状態バッジ**:
  - 有効・正常: `.green` / systemGreen
  - 実行中: `.blue` / systemBlue
  - 無効: `.gray` / systemGray
  - 警告: `.yellow` / systemYellow
  - エラー: `.red` / systemRed
- 専用色は作らない。**システムカラー優先**
- Dark / Light 両対応

## タイポグラフィ

| 用途 | フォント / スタイル |
|------|---------------------|
| UI 本文 | SF Pro (`.body`) |
| plist / ログ / コード | **SF Mono** (`.system(.body, design: .monospaced)`) |
| 画面タイトル | `.largeTitle` |
| セクション見出し | `.title2` |
| サブ見出し | `.headline` |
| 補助情報 | `.footnote` + `.secondary` |

## スペーシング

- 基本単位: **8 pt**
- 内部余白: 8 / 12 / 16 / 24
- セクション間: 24〜32
- 境界線は最小限。システムの `Divider` を活用

## アイコン

- **SF Symbols のみ**。独自アイコンは作らない
- バリアント: `.hierarchical` / `.multicolor`（macOS 26 では `.variableColor` も）
- 使用例:
  - ジョブ: `gearshape.2`
  - 有効: `checkmark.circle.fill`
  - 無効: `xmark.circle.fill`
  - 警告: `exclamationmark.triangle.fill`
  - ログ: `doc.text`
  - plist: `curlybraces`
  - 診断: `stethoscope`

## アニメーション

- デフォルトの `.default` を尊重
- 状態変化には `.spring(response: 0.3)` 程度
- 長いアニメーションは避ける（即反応が気持ちいい）

## アクセシビリティ

- VoiceOver: 全アクティブ要素に `accessibilityLabel`
- キーボードショートカット（案）:
  - `⌘F` 検索
  - `⌘R` リロード
  - `⌘E` 有効/無効トグル
  - `⌘K` 手動実行（kickstart）
  - `⌘D` 障害切り分け（diagnose）
- Increase Contrast 設定を尊重

## macOS 26 の新要素（採用方針）

- **Liquid Glass**: サイドバー背景・アクションバーに控えめ採用
- **3D アイコン**: App Icon を Icon Composer で macOS 26 スタイルに
- **新 SF Symbols**: 利用可能なものは積極採用、`#available` でガード

## アプリアイコン

- TBD。Icon Composer で macOS 26 スタイルを主、15.7 向けはフォールバック
- モチーフ案: 種 / 苗木 / 聴診器（世話するメタファ）

## 命名（UI 上）

- Display Name: **Tender**
- ウィンドウタイトル: `Tender` or `Tender — <label>`
- メニュー: macOS 慣習（Tender / File / Edit / View / Window / Help）

## 今決めないこと（TBD）

- 正式アクセントカラー
- アプリアイコン最終デザイン
- メニューバーアイコン（v2 検討）
- ショートカット最終割当
