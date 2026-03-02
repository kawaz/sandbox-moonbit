# DR-008: ReduceCtx 統一 + フックアーキテクチャ

日付: 2026-03-02

## 概要

reducer シグネチャを `(ReduceCtx[T]) -> T?!ParseError` に統一し、パースライフサイクルを6フェーズのフックパイプラインとして設計。exclusive/dependent 等の制約機能はフックの上の薄いラッパーとして実装する方針を決定した。

## 決定事項

1. ReduceCtx[T] 1引数方式の採用（reducer シグネチャ統一）
2. パースライフサイクル 6フェーズのフックアーキテクチャ
3. Visibility enum 4段階（Visible / Advanced / Deprecated / Hidden）
4. auto-env の `Bool?` 方式（None=inherit, Some(true)=on, Some(false)=off）
5. Mutual Exclusion / Dependent Options を制約フックとして実装
6. Output フェーズの3段階カスタマイズ
7. 複数値パラメータは常に Array（ターゲット別ラッパーで DX 最適化）
8. CompletionCandidate 構造体（value, description?, group?, style?）
9. ユーザー定義エイリアス機能は不要と判断

## 背景・動機

Phase 4 設計の進行に伴い、以下の課題が浮上した:

- reducer に ParseContext を渡す必要が生じ、引数が3つに膨張
- exclusive/dependent オプション等の制約をどこで検証するかが未定
- ヘルプ・補完のカスタマイズ粒度が未定義
- これらを場当たり的に追加すると、消費ループ内の分岐が肥大化する懸念

フックアーキテクチャにより、コアのパイプラインは固定のまま機能追加をフック登録で完結させる方針とした。

## 検討した代替案

### ReduceCtx 以外の方式

| 方式 | 不採用理由 |
|---|---|
| 3引数 `(T, ReduceAction, ParseContext)` | 引数追加のたびにシグネチャ変更。後方互換性が破壊される |
| Optional ctx（ラベル付きオプション引数） | MoonBit 言語制約により不可（後述） |
| 2種の API（custom / custom_with_ctx） | API が分散し、どちらを使うべきか迷う |
| enum ラッパー `Simple(() -> T) \| WithCtx((Ctx) -> T)` | 利用側が毎回 enum で包む必要があり冗長 |

### Visibility を Bool 2つ（help 表示 / 補完表示）

ショートヘルプ / 補完での表示を独立制御する案。利用側が煩雑で、組み合わせの漏れが出やすい。4段階 enum なら意図が明確で、ヘルプ・補完の表示ルールを enum 値から一意に決定できる。

### auto-env を専用 enum（AutoEnv { Inherit | On | Off }）

ユーザーから「true/false じゃないのがわかりにくい」と指摘。`Bool?` なら MoonBit の型システムに自然に整合し、None が inherit を表す慣用的パターン。

### 制約を OptMeta の requires フィールドとして実装

OptMeta が肥大化し、カスタム制約に対応できない。制約は「何でもあり得る」ため、一般化されたフック機構の上に exclusive/dependent を便利関数として載せる方が拡張性が高い。

### ユーザー定義エイリアス（git alias 的機能）

シェルコマンド実行はパーサの責務外（セキュリティリスク）。引数展開だけなら既存の aliases フィールドに追加すれば済む。パーサの新機能としては不要。

## 決定の詳細

### 1. ReduceCtx[T] 1引数方式

```moonbit
(ReduceCtx[T]) -> T?!ParseError
```

ReduceCtx[T] は現在の値、ReduceAction、ParseContext を全て保持する構造体。将来 `ahead()` 等のメソッドを追加してもシグネチャは変わらない。

経緯: 2引数 → ParseContext 追加で3引数 → 「`_ctx` 書くのも面倒、optional にしたい」→ MoonBit 制約で不可 → 「後方互換性を考えると ctx に全部入れるべき」→ ReduceCtx[T] に決定。

### 2. パースライフサイクル 6フェーズ

```
PreProcess → Resolve → Reduce → Validate → Finalize → Output
```

- **PreProcess**: 引数の前処理（`--foo=bar` の分割等）
- **Resolve**: トークンをどの Opt にマッチさせるか決定
- **Reduce**: マッチした Opt の reducer を実行し値を生成
- **Validate**: exclusive/dependent 等の制約検証
- **Finalize**: デフォルト値の適用、未設定チェック
- **Output**: ヘルプ・補完・バージョン等の出力生成

パーサのコアはこのパイプラインを駆動するだけ。exclusive() 等は内部で Validate フェーズにフックを登録する薄いラッパー。

### 3. Visibility enum 4段階

| 値 | ヘルプ（通常） | ヘルプ（--help-all） | 補完 |
|---|---|---|---|
| Visible | 表示 | 表示 | 候補に出る |
| Advanced | 非表示 | 表示 | 候補に出る |
| Deprecated | 非表示 | 表示（deprecated マーク） | 候補に出る（警告付き） |
| Hidden | 非表示 | 非表示 | 候補に出ない |

### 4. auto-env の Bool? 方式

```moonbit
auto_env : Bool?  // None=inherit(親の設定を継承), Some(true)=on, Some(false)=off
```

サブコマンドで inherit すれば、トップレベルで on/off を切り替えるだけで全体に反映される。

### 5. 制約フック + 便利関数

```
exclusive(opt_a, opt_b)       // 内部で Validate フックを登録
dependent(opt_a, requires=opt_b)  // 同上
```

ヘルプ・補完への情報公開は `help_hint` で行う。制約ロジックとヘルプ表示を分離。

requires の値条件は2口:
- 簡易: 文字列一致（`requires=("format", "json")`）
- カスタム述語: `(T) -> Bool`

### 6. Output フェーズの3段階カスタマイズ

| レベル | 内容 | 用途 |
|---|---|---|
| Level 0 | 自動生成（デフォルト） | 通常利用 |
| Level 1 | 部分フック（insertBefore/insertAfter/transform） | セクション追加、候補リスト動的生成 |
| Level 2 | 全面差し替え | 行全体の書き換え等 |

補完では候補リストの動的生成（Level 1）が最も需要が高い。

### 7. 複数値パラメータは常に Array

MoonBit に暗黙変換やオーバーロードがないため、`string | Array[String]` のような union 型は表現できない。enum ラッパーはかえって冗長。Array 統一が最もシンプル。

TS ターゲットでは `string | string[]` を受けて内部で Array に正規化するラッパーを提供。

### 8. CompletionCandidate 構造体

```moonbit
struct CompletionCandidate {
  value : String
  description : String?    // zsh/fish で候補横に表示
  group : String?          // グループ分け
  style : String?          // deprecated 警告等のスタイル
}
```

### 9. ユーザー定義エイリアス不要

git alias 的な機能を検討したが:
- シェルコマンド実行 → セキュリティリスク、パーサの責務外
- 引数展開のみ → 既存の aliases フィールドへの追加で十分
- パーサに新たな仕組みは不要

## MoonBit 言語制約の発見

PoC 検証で判明した制約:

- **クロージャにラベル付き引数・オプション引数は使えない** — 関数型の引数に `label~` や `?` を付ける構文が存在しない
- **関数型にラベルを表現する構文がない** — `(A, label~ : B) -> C` はパースエラー
- **ラベル付き関数は first-class ではない** — 変数に束縛不可、高階関数の引数に渡せない
- **オプション引数は内部的に `T?` に変換される** — ただしラベル情報は型システムに乗らない
- **ラベル付き/オプション引数が有効なのはトップレベル関数の直接呼び出し時のみ**

この制約により「reducer の ctx をオプション引数にする」案が不可となり、ReduceCtx[T] 1引数方式の採用に至った。検証コードは一時的なパッケージで実施し、削除済み。

## 影響範囲

- **phase4-design.md**: reducer シグネチャが ReduceCtx[T] 1引数に確定
- **OptMeta**: visibility フィールド追加、auto_env を Bool? に変更
- **Parser**: フックレジストリの追加（フェーズごとのフック配列）
- **exclusive/dependent API**: Parser レベルの便利関数として実装（OptMeta には入れない）
- **補完システム**: CompletionCandidate 構造体の導入
- **ヘルプシステム**: Visibility に基づく表示制御、Output フェーズの3段階カスタマイズ

## 参考資料

- `docs/error-message-survey.md` — 5パーサのエラーメッセージ調査
- `docs/result-api-survey.md` — 7パーサのリザルト取得API調査
- `docs/help-format-survey.md` — 8パーサのヘルプ出力フォーマット調査
- `docs/phase4-design.md` — 設計書本体
- DR-007 (`docs/archives/007-phase4-opts-enum-resultmap-design.md`) — 前回の設計決定（Opts enum + ResultMap）
