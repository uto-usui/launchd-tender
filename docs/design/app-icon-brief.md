# App Icon Brief — Tender

Icon Composer 作業者向けの方向性指示書。採用候補 A (新芽 × 聴診器) のレイヤー構造と、
macOS 26 Liquid Glass / 15.7 フォールバックの両方への書き出し方針を残す。

---

## ブランド整合

- **コンセプト**: `quietly watches over your jobs` — 静かな庭師 × 聴診
- **メタファ 3 層**: 庭師 (tender) / 聴診 (auscultation) / 新芽 (sprout)
- **ブランド原則との紐付け**
  - Quiet by default: 光を控えめに、背景は無地 off-white
  - Honest: 新芽と聴診器が実物の比率で描かれる、記号化しすぎない
  - Native: Liquid Glass を素直に採用
  - Density is care: 情報密度は "葉 + Y チューブ + イヤーピース" の 3 要素に限定
  - One signature: ブランド色 Moss Tender は UI accent 側に預け、**アイコンでは systemGreen を主体にする**

---

## 候補 A: 新芽 × 聴診器 (採用)

### レイヤー構造 (下 → 上、5 層)

1. **背景層**
   - Light: off-white `#F4F1EA`
   - Dark: dim moss `#2A302C`
   - 1024pt 正方形。macOS 26 の tinted icon 対応のためアルファ透過の円形マスク前提

2. **下層 (Glass base) — 聴診器のイヤーピース**
   - 2 基を下半分の左右に配置
   - 素材: **Liquid Glass** (`.regular`、refraction 中)
   - 基本色: neutral gray `#B8BCC0` (金属反射)
   - 反射中心に systemTeal `#7FB8B6` を 10% 程度

3. **中層 (Metal tube) — Y 字チューブ**
   - 交差点から上方に立ち上がる
   - 素材: 艶消しの neutral gray、陰影のみ、tint なし
   - Y 字の交差点にやわらかいシャドウ (systemGreen 5% 程度)

4. **上層 (Sprout) — 若葉**
   - チューブの交差点から斜め右上に伸びる
   - 基本色: systemGreen base `#7BB68A`
   - 葉脈: +8% luminance
   - 葉の**外縁だけ** Liquid Glass (translucency 40%) で朝露感
   - 葉は 2 枚、左葉がやや手前

5. **ハイライト層**
   - 左上 45° からの specular highlight
   - 置き場所: 葉先 1 点 + 左イヤーピース 1 点の計 2 点のみ
   - 強度は控えめ (全体の彩度を殺さない)

### Liquid Glass の使用範囲

**最大 2 箇所まで**:
- イヤーピース本体 (Glass base)
- 葉の外縁 (Sprout の縁取りのみ、面全体には当てない)

これ以上増やすと「Liquid Glass が過剰」の印象になるので守る。

### 15.7 フォールバック

- Liquid Glass を**半透明ラスタに焼き込み**、refraction を drop
- イヤーピースは通常の gradient で金属感を出す
- 葉の外縁 Glass は半透明 PNG レイヤーで代替 (opacity 40% 程度)
- それ以外のレイヤーは macOS 26 版と共通

### カラーパレット (ピクセル比率目安)

| 色 | 役割 | 比率 |
|---|---|---|
| systemGreen `#7BB68A` | 若葉 | 30% |
| neutral gray `#B8BCC0` | 聴診器金属 | 45% |
| systemTeal `#7FB8B6` | イヤーピース反射 | 10% |
| off-white `#F4F1EA` | 背景 | 15% |

- **Moss Tender `#5B7F6A` は使わない** — UI accent と役割分離、"One signature" 原則維持
- 朝光は左上斜め 45°、具体的な角度と強度は Icon Composer で最終調整

### Dock 32px シルエット要件

小サイズで識別できる要素は 2 つだけ残す:

- 上 60%: **葉の輪郭**
- 下 40%: **イヤーピース 2 円**

この 2 形状で Tender が識別できる状態を維持。ディテールは 64px 以上でのみ見える前提で描写。

```
    🌱       ← 若葉 (上層 Glass)
    ╱
   ╱
  ┃          ← Y チューブ
 ╱ ╲
(○) (○)     ← イヤーピース (下層 Glass)
```

---

## 不採用候補

### 候補 B: 苔盆栽 × 立てかけ聴診器

> 陶器の鉢に若葉、縁に小さな聴診器が立てかけてある。DESIGN.md 冒頭の "苔盆栽の静けさ" をそのまま絵にした落ち着きトーン案。

**不採用理由**
- 静けさは最強だが **Dock 32px で覚えられにくい**
- 聴診器が 15% 程度しか映らず、launchd 系ツールとして識別されにくい
- 鉢 + 葉のシルエットは他の園芸系アプリ (Plant Parent 等) と混同されやすい

### 候補 C: 世話する手 × 双葉 (記号化)

> 手のひらのシルエット + 双葉。Moss Tender を背景に敷いた記号化案。

**不採用理由**
- **Moss Tender をアイコン背景に敷くと UI accent との均衡が崩れる** — "One signature" を強化する意図は理解できるが、Dock でアプリをアクティブにしたときの強調と背景色が同一になり、視覚的に衝突
- 識別性は最強だが、ブランドメタファ 3 層のうち「聴診」が消え、launchd 管理という機能性が伝わらない
- 手のひらのシルエットはアプリアイコンとして抽象度が高すぎ、macOS の写実寄り Liquid Glass トレンドとも乖離

---

## Icon Composer 作業チェックリスト

- [ ] 1024pt 正方形で制作、円形マスク対応
- [ ] Light / Dark 両バリアント作成
- [ ] macOS 26 向け: Liquid Glass 2 箇所 (イヤーピース / 葉外縁) に限定
- [ ] 15.7 向け: Glass を半透明 PNG に置換したフラット版を別書き出し
- [ ] Dock 32px プレビューで「葉 + 2 円」のシルエットが残るか確認
- [ ] systemGreen / systemTeal / neutral gray / off-white の比率を目視確認
- [ ] Moss Tender (#5B7F6A) が**使われていない**ことを確認 (アプリ側 UI との役割分離)
- [ ] Xcode の Asset Catalog に .icon バンドルで投入、`App Icon` に設定

---

## 参照

- `/Users/usui.y/work/uto/launchd-tender/DESIGN.md` — ブランドコンセプト・アプリアイコン章
- `/Users/usui.y/work/uto/launchd-tender/CLAUDE.md` — プロジェクト原則
- Apple: [Icon Composer — WWDC25](https://developer.apple.com/videos/play/wwdc2025/)
- Apple: [App Icons (macOS 26 design gallery)](https://developer.apple.com/design/new-design-gallery-2026/)
