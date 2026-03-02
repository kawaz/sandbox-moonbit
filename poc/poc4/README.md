# PoC4: Parser struct + getter 方式 検証レポート

## 概要

Phase 4 大統一設計の新方式「Parser struct + getter」を PoC 検証した。
前回 PoC3（`wip-resultmap-poc/src/poc3`）の方式A（Ref[T] クロージャキャプチャ）を発展させ、以下の改善を加えた。

### 前回 PoC3 との差分

| 観点 | PoC3 (方式A) | PoC4 (今回) |
|------|-------------|-------------|
| ID カウンタ | グローバル `id_counter` | Parser ローカル `mut seq` |
| 値の所有権 | `Opt[T].slots: Map[Int, Ref[T]]` | `Parser.refs: Map[Int, RefV]` に集約 |
| Opt[T] の構造 | slots フィールドあり | getter/setter クロージャのみ |
| グループ | なし | `clone_map` + `RefV::Group(Array[ErasedRef])` |
| テスト分離 | グローバル状態で汚染リスク | Parser インスタンスごとに独立 |

## 検証シナリオと結果

### シナリオ1: 基本 — Parser + Opt + getter で型安全取得 ✅

- `Parser::new()` → `p.int()`, `p.flag()`, `p.str()` で `Opt[T]` を生成
- `p.get(opt)` で型安全に `T` を返す（ダウンキャスト不使用）
- getter クロージャが `Ref[T]` をキャプチャし、`Opt[T]` 自体は値を保持しない

テスト:
- 初期値の取得（Int, Bool, String）
- setter → getter ラウンドトリップ
- 複数 Opt の独立性

### シナリオ2: グループ — clone + clone_map + Array refs ✅

- `register_group([opt_ids])` で雛形登録 → `RefV::Group(Array[ErasedRef])`
- `clone_group(template_id)` で `ErasedRef.clone_ref()` による独立コピー作成
- `clone_map[clone_id] = template_id` で追跡
- 各 clone の `ErasedRef` が独立した `Ref[T]` を持ち、互いに干渉しない

テスト:
- 2つの clone に異なる値を設定
- `reduce_erased` 経由での型消去書き込みが各 clone で独立

### シナリオ3: テスト分離 — 別 Parser インスタンスの独立性 ✅

- `Parser::new()` ごとに `seq = 0` から開始
- 別インスタンスの Opt は同じ ID を持ちうるが、別の `Ref[T]` をキャプチャ
- グローバル状態なし → テスト順序依存なし

テスト:
- `p1.int()` と `p2.int()` が両方 `id=0`（独立 ID 空間）
- 値の書き込みが互いに影響しない

### シナリオ4: ErasedRef — reduce_erased 相当の型消去書き込み ✅

- `Parser.refs[opt.id]` から `ErasedRef` を取得
- `reduce_erased(ReduceAction)` で型を知らずに書き込み
- `p.get(opt)` で型安全に読み出し — **同じ `Ref[T]` を共有**
- `Negate` で初期値にリセット
- `reset()` で初期値に復元
- reducer が `None` を返す → `reduce_erased` が `false` を返す（マッチ失敗）

テスト:
- Int の `reduce_erased(Value(Some("3000")))` → `p.get(port) = 3000`
- Flag の `reduce_erased(Value(None))` → `p.get(verbose) = true`
- `reduce_erased(Negate)` → 初期値に戻る
- Flag に `Value(Some("string"))` → `false`（マッチ失敗）
- `reset()` → 初期値に戻る

## 成功基準の達成

| 基準 | 結果 |
|------|------|
| 4シナリオ全て moon test パス | ✅ 11テスト全パス |
| ダウンキャスト不使用 | ✅ `as`/`downcast`/enum Value ラッパーなし |
| Opt[T] に slots/Ref フィールドなし | ✅ `id`, `name`, `getter`, `setter` のみ |
| Parser ローカル seq でテスト間独立 | ✅ グローバルカウンタなし |

## アーキテクチャ図

```
Parser
├── seq: Int (ローカル ID カウンタ)
├── refs: Map[Int, RefV]
│   ├── 0 → Single(ErasedRef) ←── Ref[Int] をキャプチャ ──┐
│   ├── 1 → Single(ErasedRef) ←── Ref[Bool] をキャプチャ ─┤
│   ├── 2 → Group([ErasedRef, ErasedRef])  (template)     │
│   ├── 3 → Group([ErasedRef, ErasedRef])  (clone0)       │
│   └── 4 → Group([ErasedRef, ErasedRef])  (clone1)       │
├── clone_map: {3→2, 4→2}                                 │
│                                                          │
Opt[Int]  ←── getter クロージャが同じ Ref[Int] をキャプチャ ┘
├── id: 0
├── name: "port"
├── getter: (instance_id) -> Int   // Ref[Int].val を返す
└── setter: (instance_id, Int)     // Ref[Int].val に書く

ErasedRef (型消去ビュー)
├── reduce_erased: (ReduceAction) -> Bool  // 同じ Ref[T] に書く
├── reset: () -> Unit                      // 初期値に戻す
└── clone_ref: () -> ErasedRef             // 独立コピー生成
```

**核心**: `Opt[T].getter` と `ErasedRef.reduce_erased` が**同じ `Ref[T]`** をキャプチャしている。
- 型消去ビュー（ErasedRef）: パーサが型を知らずに書き込む
- 型ありビュー（Opt[T].getter）: ユーザーが型安全に読み出す
- ダウンキャストは一切不要

## 課題・今後の検討

1. **Opt[T].getter の instance_id 設計**: 現在は `-1` で直属値、`>= 0` でグループ clone を想定しているが、グループの getter 経由での型安全な読み出しは未実装（ErasedRef 経由のみ）
2. **clone_ref の再帰**: PoC では 1段のみ。ネストグループは未対応
3. **GC**: ErasedRef が Parser より長生きした場合の Ref[T] 残存（MoonBit の GC が回収するため実害なし）
4. **reducer のエラー**: 本設計では `raise ParseError` だが PoC では簡略化して `T?` で代替
