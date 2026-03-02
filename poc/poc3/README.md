# PoC3: 型消去→型復元 — 2方式比較

## 概要

MoonBit では trait object からのダウンキャストが原理的に不可能（ランタイムリフレクション非サポート）。
ダウンキャストに頼らず型消去→型復元を実現する方式を2つ実装し、比較検証した。

## 方式A: Ref[T] クロージャキャプチャ（採用）

`SlotA[T]` が `Map[Int, Ref[T]]` を保持し、Store の ID をキーに各 Store ごとの独立した `Ref[T]` を管理。Store 自体は値を持たない。

```
SlotA[T] { id, default_value, slots: Map[Int, Ref[T]] }
StoreA   { id, clone_fns: Map[Int, (Int, Int) -> Unit] }
```

- `store.get(slot)` → `slot.slots[store.id].val` で直接 T を返す
- ダウンキャスト不要、エンコード不要（ゼロコスト）
- clone: クロージャレジストリ経由で新 Store ID に対応する独立 Ref を作成

## 方式B: enum Value ラッパー（不採用）

閉じた型集合を enum で定義し、Store が `Map[Int, Value]` で値を保持。`SlotB[T]` が `wrap`/`unwrap` クロージャで変換を閉じ込める。

```
enum Value { VInt(Int), VBool(Bool), VStr(String) }
SlotB[T]  { id, default_value, wrap: (T) -> Value, unwrap: (Value) -> T }
StoreB    { data: Map[Int, Value] }
```

- `store.get(slot)` → `slot.unwrap(data[slot.id])`
- clone: Map コピーのみ（シンプル）

## 比較

| 観点 | 方式A (Ref[T]) | 方式B (enum Value) |
|------|---------------|-------------------|
| 型の開閉 | **開**（任意 T 対応） | **閉**（enum 列挙のみ） |
| エンコード | なし（ゼロコスト） | wrap/unwrap（パターンマッチ） |
| 値の所有権 | Slot 側に分散 | Store 側に集約 |
| clone | クロージャレジストリ | Map コピー |
| 型安全性 | 静的保証 | unwrap ミスは runtime abort |

## 結論: 方式A 採用

`opt::custom(my_reducer)` でユーザーが任意の T としてパースできる開放性が設計の根幹。enum で型を閉じる方式B ではこの要件を満たせない。

方式A のデメリット（値の所有権逆転、GC 依存）は CLI パーサの用途では問題にならない。

## テスト結果

4テスト全パス:
- `poc3a: type erasure with Ref[T] capture - basics` — 異なる型の Slot 生成・取得・上書き・デフォルト値
- `poc3a: store clone produces independent copy` — clone 後の独立性
- `poc3b: type erasure with enum Value - basics` — 方式B の基本動作
- `poc3b: store clone produces independent copy` — 方式B の clone 独立性
