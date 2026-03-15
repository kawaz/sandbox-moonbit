# datetime パッケージ設計メモ（進行中）

## 設計決定: Duration 型と内部表現

### 決定事項

1. **Duration は `Ms(Int64) | MsNs(Int64, Int)` の enum**
   - `Ms(Int64)` — ミリ秒精度のみ（大半のCLI用途）
   - `MsNs(Int64, Int)` — ミリ秒 + サブミリ秒ナノ秒（0..999_999）
   - パース時は ns で累積 → `Duration::from_ns(total_ns)` で正規化
   - 例: `1.2ms900us` → `MsNs(2, 100_000)` （2ms + 100μs）

2. **TimeSpec の epoch は ms (Int64)**
   - `@env.now()` (UInt64 ms) と直接互換
   - `Absolute(epoch_ms)` / `Relative(epoch_ms, Duration)`

3. **`now~` パラメータはプラガブル**
   - 型: `() -> Int64`（ミリ秒エポックを返す関数）
   - デフォルト: `@env.now().to_int64()`
   - テスト時: `now=fn() { 1_000_000L }`

4. **サポートするユニット**
   - `w`, `d`, `h`, `m`, `s`, `ms`, `μs`/`us`, `ns`
   - `y`, `month` は非対応（可変長で曖昧）

5. **数値構文の拡張**
   - 小数: `1.5h` → 5400s → `Ms(5_400_000)`
   - アンダースコア区切り: `3_600_000ms` → `Ms(3_600_000)`

### 不採用案とその理由

- **全部ナノ秒 (Go方式)**: シンプルだが `@env.now()` との変換が毎回必要。最大±292年。
- **全部ミリ秒**: シンプルだが μs/ns 精度が完全に失われる。`--since @5ms10us~995us` のような精度保持ができない。
- **enum Nanos/Millis**: 算術演算で毎回 match が必要。複雑すぎる。

### Duration の精度保持の意味

```
--since @5ms10us~995us
```

- since: `Absolute(epoch - 5)` → epoch は ms なので 10μs は消失（仕方ない）
- until side の `995us` → `MsNs(0, 995_000)` として Duration に保持
- re-serialize 時に `995μs` として復元可能

epoch 解決時は ms 精度だが、Duration 自体は sub-ms 精度を保持。
round-trip fidelity のために重要。

### 会話の経緯

1. 最初: 内部表現を秒 (Int64) で実装
2. ユーザー: `1.5h`, `3_600_000ms` のサポートを要望
3. 秒→ms→ns の議論
4. `@env.now()` が ms を返すことが判明
5. ユーザー: Duration を M(ms) と MN(ms, ns) の enum にすべき
6. Go方式(全ns)を提案 → ユーザー: 精度が不要かどうかは関係ない。あり得ることは考えるべき
7. 最終決定: `Ms(Int64) | MsNs(Int64, Int)` の enum。epoch は ms。now はプラガブル。
