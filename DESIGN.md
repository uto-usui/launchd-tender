# DESIGN.md — launchd-tender (Tender)

自分用 macOS アプリ Tender のデザイン言語。SwiftUI と最新 macOS を素直に使い、
ブランドは"一点"に宿す。

---

## ブランドコンセプト

> **Tender — quietly watches over your jobs.**
>
> 声高に主張せず、傍らにいる。正確さと優しさを両立する、技術的な庭師。

**メタファ 3 層**
1. **庭師 (tender)** — 世話をする。放置しない
2. **聴診 (auscultation)** — 観察と診断。推定は推定と認める
3. **新芽 (sprout)** — ジョブは生き物。動き続けている

Tender の画面は、朝の園芸店の奥に置かれた苔盆栽の静けさを目指す。
派手ではないが、そこに居る限り手入れが行き届いていることが分かる温度。

---

## ブランド原則 (5)

1. **Quiet by default** — 通知・色・アニメは必要最小限。画面は普段、静か
2. **Honest about uncertainty** — 推定値は "推定" と明示。嘘をつかない
3. **Native, not neutral** — macOS の流儀に従う。中立 ≠ どこの OS でもない、ではない
4. **Density is care** — 情報を整えて見せることが、世話の中身
5. **One signature, not a theme** — ブランド色・アイコン・語り口の 3 点にだけ個を宿す

ドキュメント間で矛盾があれば、この 5 原則を基準に判断する。

---

## OS ターゲット

| OS | 扱い |
|----|------|
| macOS 26+ | メイン。Liquid Glass / SF Symbols 7 / `.glassEffect` / `symbolEffect` 積極利用 |
| macOS 15.7.1〜25.x | フォールバック。`.regularMaterial`、hierarchical SF Symbols |

分岐は `#available(macOS 26, *)`。最小は 15.7.1。

---

## デザイントークン

### Color

**Brand accent は 1 色のみ**。派生・濃淡は `.tint()` と `.opacity()` に委ね、独自パレットを増やさない。
ステータスはシステム semantic color に委ね、ブランド色と明確に役割を分ける。

#### Brand — Moss Tender (Sage/Moss)

| Mode | HEX | OKLCH | HSL | 用途 |
|------|-----|-------|-----|------|
| Light | `#5B7F6A` | `0.553 0.041 150` | `145° 16.5% 42.7%` | Asset `BrandAccent` (Any) |
| Dark  | `#89B59A` | `0.704 0.056 150` | `143° 22.4% 62.4%` | Asset `BrandAccent` (Dark) |

OKLCH は設計段階の明度・色相基準。最終は Asset Catalog の sRGB(/P3) に焼いてコミットする。

**ブランド色の語り口**
> Moss Tender は "尖った緑" ではない。"息をしている緑" だ。
> System Green が「動いている・成功した」と叫ぶ信号色なのに対し、
> Moss Tender はただ "そこに在る" ことを静かに示す。
> launchd ジョブは本来、見えないところで黙々と動く。Tender はその黙々を奪わず、
> 世話する側に寄り添う。だから彩度を落とし、聴診器の金属が帯びる鈍い反射のような緑にした。

**Brand color の適用範囲**（HIG 整合: tint は意味のある場面だけ）
- 選択中のサイドバー行・プライマリアクションボタン（Load / Unload / Kickstart）
- AccentColor として SwiftUI `.tint()` に渡す唯一の値
- **使わない場所**: 状態バッジ、ログのシンタックスハイライト、装飾用グラデーション

#### Status — system semantic color に委任

| 状態 | Color |
|------|-------|
| 有効・正常・成功 | `Color.green` / `systemGreen` |
| 実行中 | `Color.blue` / `systemBlue` |
| 無効・休止 | `Color.gray` / `systemGray` |
| 警告（推定精度が低い / 平文 secret 検出） | `Color.yellow` / `systemYellow` |
| エラー・失敗 | `Color.red` / `systemRed` |

System Green とブランド Moss Tender は**色相 10° 差 / Chroma 1/4 以下**で明確に区別可能。
状態バッジとブランド tint が同画面に並んでも役割は競合しない。

#### Surface — material 優先

- macOS 26: `.glassEffect(...)` と `GlassEffectContainer` を使う
- macOS 25.x 以下: `.regularMaterial` / `.thickMaterial` / `.thinMaterial`
- **二重ブラー禁止**: Liquid Glass が自動適用される `Toolbar` / `Sidebar` / `Inspector` では、
  カスタム `.regularMaterial` を**削除**する（AppKit/SwiftUI 同方針）

#### Foreground — 絶対に独自色で塗らない

本文・ラベルは `.primary` / `.secondary` / `.tertiary` のみ。ダーク対応は system が担う。

---

### Typography

Apple が提供する semantic scale をそのまま使う。**独自スケールを追加しない。**

| Token | Style |
|-------|-------|
| 画面タイトル | `.largeTitle` |
| セクション見出し | `.title2` |
| サブ見出し | `.headline` |
| 本文 | `.body` |
| 副情報 | `.callout` / `.subheadline` |
| 補助情報 | `.footnote` + `.secondary` |
| キャプション | `.caption` / `.caption2` |
| plist・ログ・code | `.system(.body, design: .monospaced)` — SF Mono |

Dynamic Type に従う。フォントサイズを pt 直指定しない。

---

### Spacing

4 pt サブグリッド、8 pt 主グリッド。6 token に固定し、これ以上増やさない。

```swift
enum Space {
    static let xs:  CGFloat =  4   // icon padding
    static let sm:  CGFloat =  8   // inline 要素間
    static let md:  CGFloat = 12   // form row 内
    static let lg:  CGFloat = 16   // カード内部余白
    static let xl:  CGFloat = 24   // セクション間
    static let xxl: CGFloat = 32   // 段落スクロールの節目
}
```

境界線より**余白で区切る**。`Divider` はセクション境界の最後の手段。

---

### Radius

角丸も 3 段階に留める。

```swift
enum Radius {
    static let sm: CGFloat =  6   // ボタン・バッジ
    static let md: CGFloat = 10   // カード・シート内セクション
    static let lg: CGFloat = 16   // sheet / inspector の外縁
}
```

影は使わない。macOS 26 では Liquid Glass が深度を担う。
macOS 25 以下は material の境界線に任せる。

---

### Motion

```swift
.spring(response: 0.3, dampingFraction: 0.85)   // 状態変化（running ↔ idle）
.easeOut(duration: 0.15)                         // hover / tap
```

**装飾アニメは作らない**。即反応が気持ちいい。Reduce Motion 設定を尊重。

---

## マテリアル運用（Liquid Glass）

### macOS 26+

- `Toolbar` / `Sidebar` / `Inspector` は**自動で Liquid Glass**。カスタム背景を書かない
- 群としてガラスを効かせる場面: `GlassEffectContainer { ... }`
- 単発カスタム要素: `.glassEffect()` を控えめに。本文密度を下げる盛り方はしない

### macOS 25.x 以下

- `NavigationSplitView` のサイドバー背景: system 任せ（独自 material を上書きしない）
- カスタムパネルが必要な場合のみ `.regularMaterial`

### 共通

- tint は**プライマリ要素**（primary action ボタン、選択状態）にのみ乗せる
- Liquid Glass に乗せる tint は system が色相・明度を自動調整する。
  開発者は "基準色" を渡すだけ。固定彩度・固定明度の指定はしない

---

## アイコン

### 原則

- **SF Symbols のみ**。独自アイコンは作らない（App Icon を除く）
- Rendering mode は用途で使い分ける（下表）
- メタファ（`leaf` / `stethoscope` / `bandage`）は**4 箇所のみ**に集中投下、
  他は中立な `folder` / `calendar` / `curlybraces` で地を作る（メタファ:中立 ≒ 1:4）

### Rendering mode の使い分け

| 用途 | Mode | 理由 |
|------|------|------|
| 状態（確定: 正常 / 無効 / エラー） | `.hierarchical` + systemXxx tint | 色でカテゴリ、濃淡で焦点 |
| 状態（進行中: running / waiting） | `.variableColor` | 生命兆候の脈動、"推定"の揺らぎ |
| 警告の例外強調（平文 secret, bandage 系） | `.multicolor` | 色コードを変えて視線を引く |
| アクションボタン | `.hierarchical` | ツールバーの色数を抑える |
| セクション見出し | `.hierarchical` | 情報設計の地 |

### インベントリ（第一候補のみ記載）

#### 状態
| 用途 | Symbol | Mode |
|------|--------|------|
| 有効・正常稼働 | `leaf.fill` | `.hierarchical` + systemGreen |
| 待機中 | `hourglass` | `.variableColor` |
| 実行中 | `waveform.path.ecg` | `.variableColor` + systemBlue |
| 無効（休止） | `pause.circle.fill` | `.hierarchical` + systemGray |
| エラー・失敗 | `exclamationmark.octagon.fill` | `.hierarchical` + systemRed |
| 警告 | `exclamationmark.triangle.fill` | `.hierarchical` + systemYellow |
| 不明 | `questionmark.circle` | `.hierarchical` |

`.fill` の有無で "確定" と "推定・未確定" を視覚的に分ける。

#### アクション
| 用途 | Symbol |
|------|--------|
| リロード / bootstrap | `arrow.trianglehead.2.clockwise` |
| 有効⇄無効トグル | `power.circle` |
| 手動実行 (kickstart) | `play.circle.fill` |
| Finder で開く | `folder` |
| 外部エディタで開く | `square.and.pencil` |
| 障害切り分け (diagnose) | `stethoscope` ← **ブランド核** |
| バックアップ履歴 | `clock.arrow.trianglehead.counterclockwise.rotate.90` |

#### セクション見出し
| 用途 | Symbol |
|------|--------|
| ジョブ一覧（サイドバー） | `leaf.circle` ← **ブランド核** |
| Intent 編集 | `text.bubble` |
| 実行ログ | `text.alignleft` |
| plist raw | `curlybraces` |
| 環境変数 | `key.horizontal` |
| 次回実行スケジュール | `calendar.badge.clock` |
| バックアップ | `clock.arrow.trianglehead.counterclockwise.rotate.90` |
| 診断 | `stethoscope.circle` ← **ブランド核** |

### Keychain 統合（Phase 6 以降の UI 要素）

ブランドメタファからは外し、中立の shield / key 族で表現する。

| 用途 | Symbol | Mode |
|------|--------|------|
| Keychain 管理済みバッジ | `lock.shield.fill` | `.hierarchical` + systemGray |
| Keychain 移行アクション | `lock.shield` | `.hierarchical` |
| Keychain 解除アクション | `lock.open` | `.hierarchical` |
| Keychain エントリ（key/value 一覧） | `key.fill` | `.hierarchical` + `.secondary` |
| 平文 secret 検出の警告 | `exclamationmark.shield.fill` | `.hierarchical` + systemYellow |
| 移行成功表示 | `checkmark.seal.fill` | `.hierarchical` + systemGreen |

### UI primitive（地のシンボル）

| 用途 | Symbol |
|------|--------|
| 閉じる（トースト・シート） | `xmark.circle.fill` |
| 追加 | `plus.circle.fill` |
| 削除 | `minus.circle.fill` |
| 空状態 | `tray` |

### メタファの配置（絶対に増やさない 4 箇所）

1. **サイドバールート見出し** = `leaf.circle`（入り口が庭）
2. **正常稼働バッジ** = `leaf.fill`（健やかな成長）
3. **診断起動ボタン** = `stethoscope`（聴診の核）
4. **実行中アニメーション** = `waveform.path.ecg` + `.variableColor`（心拍）

これ以外は中立シンボルで地を作る。Keychain セクションはブランドメタファを使わず、
"安全装置"のニュアンスを shield で表す。

### Symbol Effect（macOS 26）

- ジョブ起動／停止遷移: `.symbolEffect(.drawOn)` / `.drawOff`（SF Symbols 7）
- 進行中の "命の脈動": `.symbolEffect(.variableColor.iterative)` を waveform.path.ecg, hourglass に
- 状態が置換されるとき: Magic Replace（enclosure matching）で自然に入れ替える

装飾効果の重ね掛けはしない。1 要素 1 エフェクト。

---

## レイアウト

### メインウィンドウ

- `NavigationSplitView`（2 カラム、将来 3 カラム拡張余地）
  - **サイドバー**: ジョブ一覧 + 検索
  - **詳細ペイン**: 選択ジョブの概要 → アクション → Intent → ログ → plist
- 最小サイズ: **800 × 500 pt**
- `windowStyle(.hiddenTitleBar)` で Liquid Glass の伸びやかさを活かす（macOS 26）

### サイドバー

- 幅: 240〜320 pt
- 1 アイテム = 2 行
  - 上: 状態シンボル + ラベル（truncate）
  - 下: Intent 1 行サマリ（`.secondary`）
- 上部に検索フィールド常設

### 詳細ペイン

**タブを使わない。段落スクロール**で下記を順に並べる:

1. ヘッダ（ラベル / 状態 / 次回実行 "推定" / Intent 1 行）
2. アクションボタン列（有効/無効 / 手動実行 / リロード / 障害切り分け）
3. Intent 編集セクション
4. ログ tail（折り畳み可、デフォルト展開）
5. plist raw（折り畳み可、デフォルト閉）
6. 環境変数・パス情報

### 障害切り分けビュー

- `.sheet` 表示、縦スクロール
- セクションごとに systemYellow / systemRed で色分け。**ブランド tint は使わない**
- `bandage.fill` の `.multicolor` を "要対応" ヘッダに限定使用

---

## アクセシビリティ

- VoiceOver: 全アクティブ要素に `accessibilityLabel`
- **Reduce Motion**: `symbolEffect` と `.spring` の両方を条件付きで無効化
- **Increase Contrast**: システム設定を尊重、独自コントラスト加工はしない
- キーボードショートカット（案）
  - `⌘F` 検索
  - `⌘R` リロード
  - `⌘E` 有効/無効トグル
  - `⌘K` 手動実行 (kickstart)
  - `⌘D` 障害切り分け (diagnose)

---

## アプリアイコン

Icon Composer で macOS 26 スタイル、15.7 向けフォールバック別書き出し。

- 主モチーフ: **若い新芽が聴診器のチューブに巻きついている** 構図
  - 下層: ガラスのイヤーピース（Liquid Glass の半透明）
  - 上層: 半透明の若葉（新芽 = `leaf` の葉脈から抽出）
  - 光: 朝のハイライト、正面斜め上から
- カラー: systemGreen（若葉） + systemTeal（ガラス反射） + neutral gray（金属）
- Dock 視認性のため `clock` / `gearshape` / `doc` 系は**入れない**

---

## 命名（UI 上）

- Display Name: **Tender**
- ウィンドウタイトル: `Tender` or `Tender — <label>`
- ブランド色アセット名: `BrandAccent`（Moss Tender）
- メニュー: macOS 慣習（Tender / File / Edit / View / Window / Help）

---

## 今決めないこと (TBD)

- メニューバーアイコン（v2 検討）
- キーボードショートカット最終割当（上記は案）
- App Icon 最終デザイン（Icon Composer 実作業で詰める）
- 平文 secret 検出 UI の具体レイアウト

---

## 参照

- [Meet Liquid Glass — WWDC25 Session 219](https://developer.apple.com/videos/play/wwdc2025/219/)
- [Build an AppKit app with the new design — WWDC25 Session 310](https://developer.apple.com/videos/play/wwdc2025/310/)
- [Build a SwiftUI app with the new design — WWDC25 Session 323](https://developer.apple.com/videos/play/wwdc2025/323/)
- [What's new in SF Symbols 7 — WWDC25 Session 337](https://developer.apple.com/videos/play/wwdc2025/337/)
- [New design gallery 2026 — Apple Developer](https://developer.apple.com/design/new-design-gallery-2026/)

---

ドキュメント間で矛盾があれば、この DESIGN.md と `CLAUDE.md`、`ai/todo/design.md` を優先。
