# DR-010: 先食い最長一致 Reducer モデルとマルチペルソナレビュー修正

日付: 2026-03-03

## 概要

arity フィールドと resolve フェーズの廃止を起点に「先食い最長一致 + resolve は Reducer」モデルへ設計を進化させ、4ペルソナ並列レビューで致命的問題を洗い出して修正した。

## 経緯

### Phase 1: arity への疑問から先食い最長一致へ

1. **arity の用途調査** — resolve_value, expand_short_combined, ヘルプ生成の3箇所で使用。reducer を呼ぶ前の引数文法レベルのメタデータに過ぎない
2. **TryReduceResult 3状態の提案** — Accept / NeedValue / Reject の3状態を検討 → NeedValue は serial で対応可能なため不要と判断
3. **先食い最長一致への飛躍** — 値を取る系は行き止まりまで先食い。候補同士の比較で先食い最長が1つならその opt が消費
4. **「resolve は Reducer」の洞察** — 名前解決自体が、opt をたくさん持っていてマッチする opt を探す Reducer。resolve という独立フェーズは不要

### Phase 2: マルチペルソナレビュー

「先食い最長一致 + resolve 廃止」の新設計に対して4ペルソナで並列レビューを実施:

- ペルソナ1（パーサ理論）
- ペルソナ2（API 設計 / DX）
- ペルソナ3（MoonBit 実装者）
- ペルソナ4（エッジケース破壊者）

#### 致命的問題と解決

1. **try_reduce の raise ParseError と投機実行の矛盾** — 全4ペルソナが指摘。消費ループは全候補に投機的に try_reduce を呼ぶため、非採用候補のエラーで全体が落ちてはいけない
   - 解決: try_reduce から raise 除去。内部で try? → catch → Reject
2. **完全一致 vs プレフィックスマッチの優先度未定義** — ペルソナ4が指摘
   - 解決案として MatchQuality (Exact / Prefix) を検討 → **不採用**（後述）
3. **`--` の force_positional シグナル欠如** — 消費ループ側の状態変数で対応

#### 追加修正

- ResultMap + Opt.slots の二重記述 → Parser.refs + getter に一本化
- P モード短縮オプション展開フロー明記
- ReduceCtx.get のセマンティクス: stale read（投機実行中の get は直前のスナップショットを返す）

## 決定事項

### Phase 1 由来

1. **arity フィールド廃止** — 実用上 arity は 0 か 1。reducer 自体が消費量を決定する
2. **resolve フェーズ廃止** — 各ノードの try_reduce に統合。名前解決自体が Reducer
3. **try_reduce が args[pos..] を直接受け取る**
4. **TryReduceResult = Accept(consumed, result) | Reject**
5. **スコープ Reducer = 子ノード群の先食い最長一致を選ぶ**
6. **短縮オプション展開はスコープ Reducer の責務**
7. **パイプラインは5フェーズに**: PreProcess → Reduce → Validate → Finalize → Output

### Phase 2（レビュー修正）由来

8. **try_reduce は raise しない** — 内部で catch → Reject
9. **force_positional は消費ループ側の状態変数**
10. **Opt[T] は getter 方式に統一** — slots 廃止、Parser.refs + getter に一本化
11. **P モードでも短縮オプション展開を適用**
12. **ctx.get() は stale read**

## 不採用案

### NeedValue(Int) — TryReduceResult の第3状態

serial で対応可能。実用上 arity は 0 か 1 であり、「あと N 個必要」という状態を返す複雑さに見合わない。

### resolve を独立フェーズとして残す

各ノードの try_reduce に内包した方が統一的。名前解決もマッチ判定の一部であり、分離する理由がない。

### MatchQuality (Exact / Prefix) — 完全一致の優先

消費ループの先食い最長一致で consumed の数で十分に区別できるため、追加の品質指標は不要。完全一致は自然にプレフィックスマッチより多くの文字を消費するか、候補が1つに絞られる。

### Opt.slots による結果保持

Parser.refs + getter/setter クロージャに一本化。slots は ResultMap との二重管理になり、整合性の維持が困難。

## 付録: チャットログ要約

### Phase 1 — 先食い最長一致モデルの発見

- **User**: 「arity て何に使ってるの？」
  - AI: 3箇所で使用（resolve_value, expand_short_combined, ヘルプ生成）。reducer を呼ぶ前のメタデータ
- **User**: 「reducer の戻り値として T, Bool を返す？」
  - AI: 3状態の TryReduceResult が最小解 → Accept / NeedValue / Reject
- **User**: 「値を取る系は行き止まりまで先食いして良い」
  - → 先食い最長一致モデルへの飛躍
- **User**: 「名前解決自体が Reducer。resolve って概念自体がいらない」
  - → resolve フェーズ廃止の決定

### Phase 2 — マルチペルソナレビュー

- **User**: 「複数のペルソナで検討してみて」
  - → 4ペルソナ（パーサ理論 / API 設計 / MoonBit 実装 / エッジケース）で並列レビュー
- **全4ペルソナ**: try_reduce + raise の矛盾を指摘 → raise 除去、内部 catch → Reject
- **ペルソナ4**: 完全一致 vs プレフィックスの優先度問題を指摘 → MatchQuality 検討後、consumed 数で十分と判断し不採用
