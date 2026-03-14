# MoonBit 日時パッケージ既存調査

調査日: 2026-03-14

## 概要

MoonBit 標準ライブラリ (moonbitlang/core) には日時パッケージは存在しない。
`@env.now() -> UInt64` で Unix ミリ秒が取れるのみ。

コミュニティ・公式実験に6つのパッケージが存在する。

## パッケージ一覧

### 1. moonbitlang/x (time)

- **種別**: 公式実験パッケージ
- **最終更新**: 2026-03-10（月次プロモーション継続中）
- **バージョン**: v0.4.41
- **Stars**: 53

**型**: Duration, PlainDate, PlainTime, PlainDateTime, ZonedDateTime, Zone, ZoneOffset, Period, Weekday（9型）

**特徴**:
- Pure MoonBit（FFI なし）→ 全ターゲット（JS/WASM/Native）で動作
- ISO 8601 完全準拠（パース・フォーマット両対応）
- TZif2 バイナリ形式でのタイムゾーン読み込み対応（DST 自動切り替え）
- java.time 風の命名（PlainDate/PlainTime/PlainDateTime）
- 100+ テストケース、ブラックボックス + ホワイトボックス
- `from_string()` → `Result[T, String]` でエラーハンドリング
- 演算子オーバーロード (`op_add` 等)

**制限**:
- カスタムフォーマッタなし（ISO 8601 のみ）
- ロケール非対応
- システム時刻取得は外部 FFI/WASI に依存（ライブラリ自体は pure）

---

### 2. iceBear67/time

- **種別**: コミュニティ
- **最終更新**: 2025-10-26（3コミット）
- **バージョン**: v0.1.2
- **Stars**: 0

**型**: Instant, Duration, Period, LocalDate, LocalTime, LocalDateTime, ZoneId, ZonedDateTime（8型）+ DateTimeFormatter

**特徴**:
- java.time API に最も忠実な設計
- 265 個の公開 API（最大規模）
- DateTimeFormatter によるカスタムパターンフォーマット対応
  - `yyyy-MM-dd`, `HH:mm:ss`, 12時間制 `hh`, ナノ秒 `nnnnnnnnn` 等
- ZoneId にプリセット18種（UTC, JST, EST, PST, CET 等）
- `to_human_readable()` → "1 year, 2 months, and 15 days"
- JS/Native 完全対応（C FFI で POSIX + Windows 両対応）
- `Instant::now()`, `LocalDate::now()` 等の現在時刻取得
- ゼロ外部依存

**制限**:
- WASM はスタブ実装（FFI が 0 を返す）
- パーサは ISO 形式の限定的なサブセットのみ
- DST 自動調整非対応（オフセット値で管理）
- 初期段階（3コミット、star なし）

---

### 3. Asterless/MoonPtime

- **種別**: コミュニティ
- **最終更新**: 2025-11-12
- **バージョン**: v0.1.2
- **Stars**: 0

**型**: Ptime, Span（2型のみ）

**特徴**:
- OCaml ptime に着想。最小主義設計
- ピコ秒精度（Int64 x 2 = 16バイト）
- RFC 3339 フォーマット出力
- `of_ymd_hms()` で日付時刻から構築
- Pure MoonBit、外部依存なし
- 演算: add_span, sub_span, diff, compare

**制限**:
- タイムゾーン非対応（設計上の判断）
- RFC 3339 パースなし（出力のみ）
- カスタムフォーマットなし
- 2型のみで機能は限定的

---

### 4. SupremeHuaji/ptime

- **種別**: コミュニティ
- **最終更新**: 2025-09-26
- **バージョン**: v0.1.0
- **Stars**: 0

**型**: PTime, Span, DateComponents

**特徴**:
- ピコ秒精度
- RFC 3339 双方向対応（パース + 生成）
- 多様な出力形式: HTTP date, JSON timestamp, SQL datetime, カスタムパターン (`%Y-%m-%d %H:%M:%S`)
- `humanize_span()` → "1 hour ago" の相対時間表示
- 負のタイムスタンプ対応（1970年以前）

**制限**:
- 4コミット、初期段階
- ドキュメント最小限

---

### 5. suiyunonghen/datetime

- **種別**: コミュニティ
- **最終更新**: 2025-03-28
- **バージョン**: v0.1.6（6バージョン公開、最も進んだ版管理）
- **Stars**: 1

**型**: DateTime (Double型), TimeZone, SystemDate, SystemTime, SystemDateTime

**特徴**:
- 内部表現が Double（1899-12-30 基準の日数 + 時刻を小数部に）
- タイムゾーン変換対応
- Unix タイムスタンプ変換
- ISO 8601 パース（タイムゾーン付き）
- 複数の貢献者による協調開発
- ミリ秒精度

**制限**:
- Double 表現による精度限界
- 1899-12-30 基準は Delphi/Excel 由来で独特
- ナノ秒以上の精度不可

---

### 6. MINGtoMING/datetime

- **種別**: コミュニティ
- **最終更新**: 2025-03-24
- **バージョン**: v0.1.0
- **Stars**: 1

**型**: Datetime, Date, Time, Offset

**特徴**:
- TOML 形式の日時パース/文字列化に特化
- ナノ秒精度
- 部分日時表現（日付のみ、時刻のみ）
- バリデーション重視

**制限**:
- 2コミット、事実上停止
- TOML 専用で汎用性低い

---

## 比較表

| 項目 | moonbitlang/x | iceBear67/time | Asterless/MoonPtime | SupremeHuaji/ptime | suiyunonghen/datetime | MINGtoMING/datetime |
|---|---|---|---|---|---|---|
| **設計思想** | java.time (Plain*) | java.time (Local*) | OCaml ptime | OCaml ptime 風 | Delphi/独自 | TOML 特化 |
| **型の数** | 9 | 8 + Formatter | 2 | 3 | 5 | 4 |
| **精度** | ナノ秒 | ナノ秒 | ピコ秒 | ピコ秒 | ミリ秒 | ナノ秒 |
| **TZ対応** | TZif2+DST | オフセット+プリセット | なし | なし | オフセット | オフセット |
| **ISO 8601 パース** | ○ | △（限定的） | × | ○ | ○ | ○（TOML向け） |
| **RFC 3339** | △（基本形） | ○ | 出力のみ | ○（双方向） | × | × |
| **カスタムフォーマット** | × | ○ | × | ○ (`%Y-%m-%d`) | × | × |
| **現在時刻取得** | ×（pure） | ○（FFI） | × | ○ | × | × |
| **全ターゲット** | ○ | △（WASMスタブ） | ○ | 不明 | ○ | 不明 |
| **FFI** | なし | C (POSIX+Win) | なし | なし | なし | なし |
| **外部依存** | なし | なし | なし | なし | なし | なし |
| **テスト** | 100+ | 975行 | あり | あり | あり | あり |
| **活発度** | ◎（月次更新） | △（初期） | △（初期） | △（初期） | ○（6版） | ×（停止） |
| **成熟度** | 実用段階 | プロト→実用 | PoC | PoC | 実用初期 | PoC |

## 評価

### Tier 1: 実用候補
- **moonbitlang/x (time)**: 公式、最も活発、Pure MoonBit、ISO 8601 完全対応。標準になる可能性が最も高い
- **iceBear67/time**: API 最大規模、Formatter あり。ただし初期段階で WASM 制限あり

### Tier 2: 特化型
- **SupremeHuaji/ptime**: カスタムフォーマット + humanize が強み。RFC 3339 双方向
- **suiyunonghen/datetime**: 最も多くバージョンを重ねた。タイムゾーン変換あり

### Tier 3: 限定的
- **Asterless/MoonPtime**: 最小主義で美しいが機能が限定的
- **MINGtoMING/datetime**: TOML 専用、事実上停止

## 我々のライブラリとの関係

我々の目的は**広大な日時ライブラリの構築ではない**。

CLI ツールの `--since` / `--until` で使う柔軟な日時指定パーサが欲しい:
- Duration 形式: `"5m"`, `"1h"`, `"2d"`, `"1h30m"` → 秒数
- 日付文字列: `"2024-01-01"` → Unix epoch seconds
- 日時文字列: `"2024-01-01T12:00:00"` → Unix epoch seconds
- 相対指定: `"yesterday"`, `"today"` 等も将来的にあり得る

既存パッケージはいずれもこの「CLI 日時指定パーサ」というニッチをカバーしていない。
moonbitlang/x の PlainDate/PlainDateTime のパースは近いが、Duration 形式（`5m`, `1h30m`）のパースは存在しない。

→ **自作の価値あり**。内部で moonbitlang/x の ISO 8601 パースを参考にしつつ、CLI 向けの柔軟なパーサとして設計する。
