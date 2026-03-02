# PoC1-2: CLI引数パーサ Phase 1-2 実装

## 概要

Reducer 方式（Phase 4）着想前に、引数処理の手順を確認しながら段階的に構築したパーサ実装。
String ベース・OptKind enum 分岐の設計で、Phase 4 では全面的に作り直すが、
399 テストが「この入力にはこう解釈してほしい」というケース集として機能する。

## 設計思想

- **OptKind enum**: Flag / Single / Append / Count / OptionalValue / Group の 6 パターンを明示的に分岐
- **String ベースの ParsedValue**: パース結果は `Map[String, ParsedValue]` に格納
- **手続き的パーサ**: `parse_scope` が while ループでトークンを消費、Group でスコープを再帰
- **多段デフォルト**: `apply_defaults` が opts 配列のコピーを返す純粋関数

### Phase 4 Reducer 方式との違い

| 観点 | Phase 1-2 (本 PoC) | Phase 4 (Reducer) |
|------|--------------------|--------------------|
| 型安全性 | String ベース | `Opt[T]` ジェネリクス |
| パース分岐 | OptKind enum match | reducer クロージャに統一 |
| 値格納 | `Map[String, ParsedValue]` | `Parser.refs: Map[Int, RefV]` |
| 拡張性 | enum に種類追加が必要 | `opt::custom(reducer)` で任意型対応 |

## ファイル構成

| ファイル | 役割 |
|----------|------|
| `types.mbt` | 全型定義 (OptDef, OptKind, ParseResult, CmdDef, Token, ParseError 等) |
| `tokenize.mbt` | `Array[String]` → `Array[Token]` の字句解析 |
| `resolve.mbt` | ロング名/ショート文字 → OptDef の名前解決。`--no-` / `--enable-` / `--disable-` 反転パターン対応 |
| `validate_opts.mbt` | OptDef 配列のバリデーション (重複名・ショート衝突・反転名衝突・choices 整合性・Group 制約) |
| `validate_command.mbt` | CmdDef ツリーの再帰バリデーション (サブコマンド名重複・エイリアス衝突) |
| `parse.mbt` | メインパーサ。スコープ再帰・Group スコープ遷移・finalize (required/choices/defaults) |
| `apply_defaults.mbt` | 設定ファイル/環境変数レイヤの畳み込み。純粋関数 |
| `command.mbt` | サブコマンド解決 + 統合パーサ |
| `integration_test.mbt` | 全コンポーネント連携テスト。Group 3 段ネスト等 |

## テスト結果

399 テスト全パス。主なカバレッジ:

- 全 OptKind の基本動作・エッジケース
- `--no-xxx` / `--enable-xxx` / `--disable-xxx` 反転パターン全種
- Group のスコープ遷移・3 段ネスト・clone 独立性
- サブコマンド解決・エイリアス・曖昧入力
- required / choices / defaults の finalize
- authsock_filter 風の実用的シナリオ
