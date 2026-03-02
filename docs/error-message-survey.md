# CLI引数パーサ エラーメッセージ設計 調査レポート

調査日: 2026-03-02

---

## 1. clap (Rust) — 最高峰のエラーメッセージ

### 1.1 エラーの種類（ErrorKind: 17種）

| ErrorKind | 説明 |
|---|---|
| `InvalidValue` | 許可リストにない値を指定 |
| `UnknownArgument` | 未定義のフラグ/オプション/引数/サブコマンド |
| `InvalidSubcommand` | サジェスト可能な未知サブコマンド |
| `NoEquals` | `=` 形式が必須のオプションで `=` なし |
| `ValueValidation` | カスタムバリデーション失敗 |
| `TooManyValues` | `num_args` 上限超過 |
| `TooFewValues` | `num_args` 下限未達 |
| `WrongNumberOfValues` | 値の個数不正 |
| `ArgumentConflict` | 排他オプションの同時使用 |
| `MissingRequiredArgument` | 必須引数の欠落 |
| `MissingSubcommand` | 必須サブコマンドの欠落 |
| `InvalidUtf8` | 非UTF8値 |
| `DisplayHelp` | `--help` 要求 |
| `DisplayHelpOnMissingArgumentOrSubcommand` | 引数欠落時のヘルプ表示 |
| `DisplayVersion` | `--version` 要求 |
| `Io` | I/Oエラー |
| `Format` | フォーマットエラー |

### 1.2 エラーメッセージ出力例

```
error: invalid value '23' for '--number <NUMBER>': An even number is expected

For more information, try '--help'.
```

```
error: unexpected argument '--hell' found

  tip: a similar argument exists: '--hello'

Usage: qqq <NAME|--hello <HELLO>|...

For more information, try '--help'.
```

```
error: the argument '--debug' cannot be used with '--no-debug'

Usage: myapp [OPTIONS]

For more information, try '--help'.
```

```
error: the following required arguments were not provided:
    <NAME>

Usage: myapp <NAME> [SUBCOMMAND]

For more information, try '--help'.
```

```
error: unrecognized subcommand 'clone'

  tip: a similar subcommand exists: 'config'

Usage: jj [OPTIONS] <COMMAND>

For more information, try '--help'.
```

```
error: unexpected argument '--optio' found

  tip: a similar argument exists: '--option'

Usage: clap-test --option <opt>...

For more information, try '--help'.
```

### 1.3 メッセージ構造（4層）

```
1. error: {メインメッセージ}           ← 赤太字の "error:" ラベル
2.   tip: {サジェスト/ヒント}          ← 緑の "tip:" ラベル（任意）
3. Usage: {使用法}                     ← Usageセクション
4. For more information, try '--help'. ← フッター
```

### 1.4 色・装飾（Styles: 8カテゴリ）

| カテゴリ | 用途 | デフォルト色 |
|---|---|---|
| `error` | `error:` ラベル | 赤太字 |
| `valid` | サジェスト値、`tip:` | 緑 |
| `invalid` | 問題のある引数/値 | 赤 |
| `literal` | コマンド名、`--help` 等 | 装飾なし or 緑 |
| `placeholder` | `<VALUE>` 等 | 装飾なし or 緑 |
| `header` | セクション見出し | 黄色 |
| `usage` | `Usage:` 見出し | 緑 |
| `context` | `[default: ...]` 等 | 装飾なし |

- `ColorChoice::Auto` / `Always` / `Never` で制御
- anstyle ベースで完全カスタマイズ可能
- `Styles::styled()` で v3 互換カラースキーム

### 1.5 カスタマイズ API

```rust
// カスタムエラー生成
let err = cmd.error(ErrorKind::ValueValidation, "port must be 1-65535");

// コンテキスト情報の追加
err.insert(ContextKind::InvalidArg, ContextValue::String("--port".into()));
err.insert(ContextKind::InvalidValue, ContextValue::String("99999".into()));

// サジェスト追加
err.insert(ContextKind::SuggestedArg, ContextValue::StyledStrs(suggestions));

// フォーマッター切り替え
err.apply::<RichFormatter>();

// TypedValueParser でカスタムバリデーション
// value_parser で型変換時のエラーメッセージ制御
```

- `error-context` feature で構造化コンテキスト（ContextKind + ContextValue）
- `ErrorFormatter` trait で完全カスタムフォーマッター
- `RichFormatter`（デフォルト）と差し替え可能

### 1.6 特に優れている点

- **did you mean? サジェスト**: Levenshtein 距離ベース。フラグ・オプション・サブコマンドすべてに対応
- **プレフィックスマッチ**: `infer_long_args` で曖昧プレフィックスのエラー検出
- **構造化エラーコンテキスト**: プログラマティックにエラー情報にアクセス可能
- **8種のスタイルカテゴリ**: 視覚的に意味が明確な階層的装飾
- **一貫した4層構造**: error → tip → Usage → footer

---

## 2. bpaf (Rust) — Applicative パーサの明確なエラー

### 2.1 エラーの種類

| 種別 | 説明 |
|---|---|
| 必須オプション欠落 | 期待するオプションが見つからない |
| 予期しない引数 | コンテキストにない引数 |
| 型変換失敗 | 値のパースエラー |
| did you mean? | タイポ検出によるサジェスト |
| 排他違反 | 同時使用不可のオプション |
| 多重指定不可 | 同一オプションの複数指定 |
| ガード失敗 | カスタムバリデーション |
| 値不正 | 期待と異なる値 |

### 2.2 エラーメッセージ出力例

```
Expected --distance ARG, pass --help for usage information
```

```
no such flag: --verbos, did you mean --verbose?
```

```
no such flag: --age12, did you mean --age?
```

```
expected --output=PATH or --output, pass --help for usage information
```

```
expected --name=ARG or --url=ARG, pass --help for usage information
```

```
--name cannot be used at the same time as --url
```

```
--detailed is not expected in this context
```

```
-a is not expected in this context
```

```
argument --no-default-features cannot be used multiple times in this context
```

```
expected --intel, --att, or more, pass --help for usage information
```

```
couldn't parse ten: invalid digit found in string
```

```
expected CRATE, got --detailed. Pass --help for usage information
```

```
expected CRATE, pass --help for usage information
```

```
--llvm cannot be used at the same time as --att
```

```
--name requires an argument NAME
```

```
expected --agree, pass --help for usage information
```

### 2.3 メッセージ構造（1〜2層）

```
{メインメッセージ}[, pass --help for usage information]
```

- clap と比べてシンプル。基本は1行のメッセージ
- Usage セクションの自動表示はない（`--help` への誘導のみ）
- サジェストは "did you mean {候補}?" 形式でインライン

### 2.4 色・装飾

- `bright-color` / `dull-color` オプショナル feature
- デフォルトでは色なし
- 太字・色の使用はフィーチャーフラグで制御

### 2.5 カスタマイズ API

```rust
// guard — カスタムバリデーション
parser.guard(|v| *v <= 10, "Values greater than 10 are only available in the DLC pack!")

// fail — カスタムエラーメッセージ
parser.fail("Custom error message for missing -a")

// parse — 変換+エラー
parser.parse(|s| s.parse::<u32>().map_err(|e| format!("bad number: {e}")))

// catch — エラーリカバリ
parser.catch()  // "value present but invalid" のリカバリ
```

- `ParseFailure` enum: `Stdout(Doc, bool)` / `Completion(String)` / `Stderr(Doc)`
- `exit_code()` + `print_message()` でプログラマティック制御
- テスト用: `run_inner()` で `ParseFailure` を取得して検証

### 2.6 特に優れている点

- **did you mean? サジェスト**: タイポ検出（`--verbos` → `--verbose?`）
- **コンテキスト認識エラー**: "is not expected in this context" — スコープ認識
- **Applicative 合成のエラー**: 排他ブランチの選択肢を列挙（`expected --intel, --att, or more`）
- **positional のフラグ誤検出**: `expected CRATE, got --detailed` — `--` を使うよう誘導
- **排他違反の明示**: `cannot be used at the same time as`
- **必須引数の期待値列挙**: `expected --output=PATH or --output`

---

## 3. Swift ArgumentParser

### 3.1 エラーの種類（ParserError: 16種）

| ParserError case | 説明 |
|---|---|
| `helpRequested` | ヘルプ表示要求 |
| `versionRequested` | バージョン表示要求 |
| `dumpHelpRequested` | 構造化ヘルプダンプ |
| `completionScriptRequested` | 補完スクリプト生成 |
| `completionScriptCustomResponse` | カスタム補完応答 |
| `unsupportedShell` | 未対応シェル |
| `notImplemented` | 未実装 |
| `invalidState` | 内部状態不正 |
| `unknownOption` | 未知のオプション |
| `invalidOption` | 不正なオプション形式 |
| `nonAlphanumericShortOption` | 非英数字のショートオプション |
| `missingValueForOption` | オプションの値欠落 |
| `unexpectedValueForOption` | 予期しないオプション値 |
| `unexpectedExtraValues` | 余分な値 |
| `duplicateExclusiveValues` | 排他値の重複 |
| `noValue` | 値なし |
| `unableToParseValue` | 値のパース失敗 |
| `missingSubcommand` | サブコマンド欠落 |
| `userValidationError` | ユーザーバリデーション |
| `noArguments` | 引数なし |
| `missingValueOrUnknownCompositeOption` | 値欠落 or 複合オプション不明 |

### 3.2 エラーメッセージ出力例

```
Error: Unknown option '--inner'
Usage: cli [<context>] <subcommand>
See 'cli --help' for more information.
```

```
Error: Missing expected argument '<phrase>'
Help:  <phrase>  The phrase to repeat.
Usage: repeat [--count <count>] [--include-counter] <phrase>
See 'repeat --help' for more information.
```

```
Error: Missing value for '--count <count>'
Help:  --count <count>  The number of times to repeat 'phrase'.
Usage: repeat <phrase> [--count <count>]
See 'repeat --help' for more information.
```

```
Error: The value 'ZZZ' is invalid for '<high-value>'
```

```
Error: '<high-value>' must be at least 1.
```

```
Error: Unexpected argument '--indx'
Did you mean '--index'?
```

```
Error: 'string' must contain at least 3 characters.
```

```
Error: The file doesn't exist.
```

### 3.3 メッセージ構造（3〜4層）

```
Error: {メインメッセージ}           ← "Error:" プレフィックス
Help:  {関連オプションのヘルプ}      ← 任意。該当引数のヘルプテキスト
Usage: {使用法}                     ← Usage行
See '{cmd} --help' for more information.  ← フッター
```

### 3.4 色・装飾

- **色なし**: Swift ArgumentParser はデフォルトで色付きエラーを出力しない
- プレーンテキスト出力
- 構造的な "Error:" / "Help:" / "Usage:" ラベルで視覚的に区別

### 3.5 カスタマイズ API

```swift
// ValidationError — カスタムバリデーション
func validate() throws {
    guard count > 0, count <= 5 else {
        throw ValidationError("count must be higher than 0, up to 5")
    }
}

// ExitCode — サイレント終了
throw ExitCode.failure

// CleanExit — メッセージ付き正常終了
throw CleanExit.message("Done!")

// カスタムエラー型
// CustomStringConvertible or LocalizedError に準拠
struct MyError: Error, CustomStringConvertible {
    var description: String { "custom message" }
}

// main() のオーバーライドで完全制御
static func main() {
    do { ... } catch { /* カスタムフォーマット */ }
}
```

### 3.6 特に優れている点

- **Help: 行の追加**: 問題の引数に対応するヘルプテキストをエラーにインライン表示。他のパーサにない独自機能
- **did you mean? サジェスト**: near-miss 検出（GSoC プロジェクトで実装）
- **型レベルバリデーション**: `ExpressibleByArgument` 準拠で型レベルのバリデーション
- **プラットフォーム対応終了コード**: Unix の `EX_USAGE` / Windows の `ERROR_BAD_ARGUMENTS`
- **MessageInfo ディスパッチ**: エラー種別に応じて構造化されたメッセージ生成

---

## 4. cobra + pflag (Go)

### 4.1 エラーの種類

| 種別 | 発生源 |
|---|---|
| 未知コマンド | cobra |
| 未知フラグ（long） | pflag |
| 未知フラグ（short） | pflag |
| フラグ構文不正 | pflag |
| フラグ値欠落 | pflag |
| 必須フラグ未設定 | cobra |
| 引数数不正 | cobra（`Args` バリデータ） |
| 値パース失敗 | pflag |

### 4.2 エラーメッセージ出力例

```
Error: unknown command "srever" for "hugo"

Did you mean this?
        server

Run 'hugo --help' for usage.
```

```
Error: unknown command "remove" for "kubectl"

Did you mean this?
        delete

Run 'kubectl help' for usage.
```

```
Error: unknown flag: --invalid
```

```
Error: unknown shorthand flag: 't' in -test.v=true
```

```
Error: flag needs an argument: --config
```

```
Error: required flag(s) "flagname" not set
```

```
Error: bad flag syntax: ---foo
```

```
Error: accepts 2 arg(s), received 3
```

### 4.3 メッセージ構造（2〜3層）

```
Error: {メインメッセージ}               ← "Error:" プレフィックス
[Did you mean this?]                    ← サジェスト（コマンドのみ）
        {候補}                          ← インデント付き候補
[Run '{cmd} --help' for usage.]         ← フッター
```

- サブコマンドの typo 時のみ "Did you mean this?" を表示
- フラグの typo にはサジェスト**なし**（pflag の制約）
- エラー後に自動で Usage を表示（`SilenceUsage` で制御可能）

### 4.4 色・装飾

- **色なし**: cobra/pflag はデフォルトで色付き出力なし
- プレーンテキスト
- "Error:" プレフィックスのみ

### 4.5 カスタマイズ API

```go
// SetFlagErrorFunc — フラグパースエラーのカスタムハンドラ
rootCmd.SetFlagErrorFunc(func(cmd *cobra.Command, err error) error {
    return fmt.Errorf("flag error: %w", err)
})

// SilenceErrors — 自動エラー出力の抑制
rootCmd.SilenceErrors = true

// SilenceUsage — エラー時のUsage自動表示の抑制
rootCmd.SilenceUsage = true

// SuggestionsMinimumDistance — Levenshtein距離閾値
rootCmd.SuggestionsMinimumDistance = 2

// SuggestFor — 手動サジェスト定義
deleteCmd.SuggestFor = []string{"remove", "rm"}

// DisableSuggestions — サジェスト無効化
rootCmd.DisableSuggestions = true

// RunE — エラー型の戻り値
cmd.RunE = func(cmd *cobra.Command, args []string) error {
    return fmt.Errorf("port must be 1-65535")
}
```

### 4.6 特に優れている点

- **コマンドサジェスト**: Levenshtein 距離ベース（閾値カスタマイズ可能）
- **SuggestFor**: 距離に関係なく手動でサジェスト候補を定義可能
- **柔軟なエラーフック**: `SetFlagErrorFunc` でフラグエラーの完全カスタマイズ
- **段階的な制御**: `SilenceErrors` / `SilenceUsage` で出力制御
- **Args バリデータ**: `cobra.ExactArgs(n)`, `cobra.MinimumNArgs(n)` 等のプリセット

---

## 5. Clipanion (TypeScript)

### 5.1 エラーの種類

| エラークラス | 説明 |
|---|---|
| `UsageError` | ユーザー入力起因のエラー。スタックトレース非表示 |
| `UnknownSyntaxError` | コマンドが見つからない。候補をサジェスト |
| `AmbiguousSyntaxError` | 複数コマンドにマッチ。候補を列挙 |

### 5.2 エラーメッセージ出力例

```
UnknownSyntaxError: Command not found; did you mean one of:

  0. mytool -h
  1. mytool -v
  2. mytool each [-x,--exclude #0]
```

```
AmbiguousSyntaxError: Cannot find which to pick amongst the following alternatives:

  0. mytool install [--json] [--exact] ...
  1. mytool install [--tilde] [--save-dev] ...
```

```
UsageError: Invalid option value for --port: expected a number

Usage: mytool serve [--port #0]
```

### 5.3 メッセージ構造

```
{ErrorName}: {メインメッセージ}        ← エラークラス名がプレフィックス
[候補リスト（番号付き）]               ← "did you mean" の候補（番号付き）
[Usage: {使用法}]                     ← UsageError の場合
```

- `UsageError` はメッセージ + Usage 行のみ（スタックトレースなし）
- 通常の `Error` はスタックトレース付き
- 候補は FSM ベースで構造的に検出

### 5.4 色・装飾

- **色なし**: Clipanion 自体は色付き出力をしない
- エラークラス名（`UsageError:`, `UnknownSyntaxError:`）が識別子
- Yarn (Berry) での利用時は Yarn 側が色付け

### 5.5 カスタマイズ API

```typescript
// UsageError — スタックトレース非表示
throw new UsageError("Invalid port number");

// catch メソッドオーバーライド
class MyCommand extends Command {
    async catch(error: any): Promise<void> {
        // カスタムエラーハンドリング
    }
}

// ErrorWithMeta インターフェース
interface ErrorWithMeta extends Error {
    readonly clipanion: ErrorMeta;  // {type: 'none'} | {type: 'usage'}
}
```

- `ErrorMeta.type = 'usage'` → スタックトレース非表示、Usage 行表示
- `ErrorMeta.type = 'none'` → スタックトレース表示
- 戻り値 `1` → Clipanion は何も表示しない（自前出力用）

### 5.6 特に優れている点

- **FSM ベースの構造的エラー検出**: コマンドパスの有限状態機械で曖昧さを静的に検出
- **番号付き候補リスト**: 複数候補を番号付きで整理表示
- **UnknownSyntax vs Ambiguous の区別**: 「見つからない」と「曖昧」を明確に分離
- **ErrorMeta によるスタックトレース制御**: ユーザーエラーでスタックトレースを自動抑制
- **whileRunning() コンテキスト**: 実行中のコマンドを `while running {input}` で表示

---

## 6. 横断比較

### 6.1 エラー種別 × パーサ対応表

| エラー種別 | clap | bpaf | Swift AP | cobra | Clipanion |
|---|---|---|---|---|---|
| 未知オプション | `UnknownArgument` | "not expected in this context" | `unknownOption` | "unknown flag" | `UnknownSyntaxError` |
| 値不正/型不正 | `InvalidValue` | "couldn't parse" | `unableToParseValue` | pflag parse error | `UsageError` |
| 必須欠落 | `MissingRequiredArgument` | "expected X, pass --help" | `noValue` / missing | "required flag not set" | (型レベル) |
| サブコマンド欠落 | `MissingSubcommand` | (--help誘導) | `missingSubcommand` | (help表示) | `UnknownSyntaxError` |
| 排他違反 | `ArgumentConflict` | "cannot be used at the same time" | `duplicateExclusiveValues` | (手動) | `AmbiguousSyntaxError` |
| 値個数不正 | `TooMany/FewValues` | (Applicative) | `unexpectedExtraValues` | "accepts N args" | (型レベル) |
| **did you mean?** | **対応** | **対応** | **対応** | **コマンドのみ** | **FSM候補** |
| 曖昧プレフィックス | `infer_long_args` | (未対応) | (未対応) | (未対応) | FSM自動 |

### 6.2 メッセージ構造比較

| パーサ | ラベル | サジェスト | Usage表示 | フッター |
|---|---|---|---|---|
| clap | `error:` (赤) | `tip:` (緑) | Usage行 | `For more information, try '--help'.` |
| bpaf | (なし) | `did you mean X?` | なし | `pass --help for usage information` |
| Swift AP | `Error:` | `Did you mean 'X'?` | Usage行 | `See 'cmd --help' for more information.` |
| cobra | `Error:` | `Did you mean this?` | 自動Usage | `Run 'cmd --help' for usage.` |
| Clipanion | `ErrorName:` | 番号付き候補 | Usage行 | なし |

### 6.3 色・装飾比較

| パーサ | 色付き | カスタマイズ |
|---|---|---|
| clap | 8カテゴリのセマンティック着色 | anstyle で完全カスタマイズ |
| bpaf | オプショナル feature | bright-color / dull-color |
| Swift AP | なし | — |
| cobra | なし | — |
| Clipanion | なし | — |

### 6.4 エラーカスタマイズ API 比較

| パーサ | 構造化エラー | カスタムバリデーション | フォーマッターカスタマイズ |
|---|---|---|---|
| clap | ContextKind/ContextValue | value_parser, cmd.error() | ErrorFormatter trait |
| bpaf | ParseFailure enum | guard(), fail(), parse() | print_message() |
| Swift AP | ParserError enum (内部) | validate(), ValidationError | main() override |
| cobra | error interface | RunE, Args validators | SetFlagErrorFunc |
| Clipanion | ErrorWithMeta interface | catch() override | ErrorMeta type |

---

## 7. Phase 4 設計に取り入れるべきポイント

### 7.1 必須: エラーメッセージの構造化（clap 方式）

**4層構造を採用**:

```
error: {メインメッセージ}               ← 赤太字
  tip: {サジェスト/ヒント}              ← 緑（任意）
Usage: {使用法}                         ← Usageセクション
For more information, try '--help'.     ← フッター
```

理由: clap の4層構造は情報密度と可読性のバランスが最も良い。bpaf の1行は情報不足、cobra の自動 Usage 全表示は冗長。

### 7.2 必須: did you mean? サジェスト

- Levenshtein 距離ベースのタイポ検出（オプション名・サブコマンド名の両方）
- bpaf の `no such flag: --verbos, did you mean --verbose?` 形式がインラインで分かりやすい
- clap の `tip: a similar argument exists: '--verbose'` も良い
- cobra はフラグのサジェストがない（pflag の制約）ので、パーサ自作なら両方サポート

### 7.3 必須: コンテキスト認識エラー

bpaf の **"is not expected in this context"** パターンは Phase 4 の OC/P モードと相性が良い:

- OC モードで Positional として期待される場所にフラグが来た → `expected CRATE, got --detailed`
- P モードでマッチしないオプション → `--xyz is not expected in this context`
- サブコマンドのスコープ外オプション → コンテキスト付きエラー

### 7.4 必須: Swift AP の Help: 行（独自拡張）

Swift ArgumentParser の **Help: 行**は他のパーサにない独自機能で、Phase 4 に取り入れる価値が高い:

```
error: missing value for '--count <count>'
  help: --count <count>  The number of times to repeat 'phrase'.
Usage: repeat <phrase> [--count <count>]
For more information, try '--help'.
```

問題の引数のヘルプテキストをインライン表示することで、`--help` を実行せずに修正できる。

### 7.5 推奨: セマンティックスタイリング

clap の8カテゴリをベースに、MoonBit のターゲット（native/js/wasm）に応じた出力制御:

| カテゴリ | 用途 |
|---|---|
| `error` | エラーラベル（赤太字） |
| `valid` | サジェスト/正しい値（緑） |
| `invalid` | 問題のある値/引数（赤） |
| `literal` | コマンド名・フラグ名 |
| `hint` | tip/help ラベル（緑） |

- native target: ANSI エスケープコード
- js/wasm target: なし or ブラウザコンソール

### 7.6 推奨: 排他違反の明示（bpaf 方式）

Phase 4 の `or(...)` 排他選択に対応:

```
error: --json cannot be used at the same time as --yaml

Usage: myapp [--json | --yaml] <file>
For more information, try '--help'.
```

### 7.7 推奨: Applicative 合成のエラー列挙（bpaf 方式）

Phase 4 の reducer 3値（None/Some/ParseError）と相性が良い:

```
error: expected --intel, --att, or --llvm, pass --help for usage information
```

複数の候補がすべて None（マッチしない）を返した場合、期待される選択肢を列挙。

### 7.8 検討: FSM ベースの曖昧さ検出（Clipanion 方式）

Phase 4 の消費ループ Step 9-10 の曖昧さエラーに応用:

```
error: ambiguous argument 'deploy'

  Cannot determine which to pick:
    0. myapp deploy [--force] <target>
    1. myapp deploy [--rollback] <version>

For more information, try '--help'.
```

### 7.9 検討: ErrorMeta によるスタックトレース制御（Clipanion 方式）

ParseError にメタデータを持たせ、パーサエラー（ユーザー起因）と内部エラー（バグ）を区別:

```moonbit
pub(all) enum ParseError {
  Usage(String, ~context: ErrorContext)    // ユーザー起因。スタックトレース非表示
  Internal(String)                         // 内部エラー。スタックトレース表示
}
```

### 7.10 Phase 4 エラー種別の設計案

Phase 4 の reducer ベース設計に対応したエラー種別:

| エラー種別 | 発生タイミング | メッセージ例 |
|---|---|---|
| `UnknownOption` | 名前解決 | `no such flag: --verbos, did you mean --verbose?` |
| `UnexpectedArgument` | OC→Pモード遷移後 | `--xyz is not expected in this context` |
| `MissingRequired` | validate | `the following required arguments were not provided: --port` |
| `InvalidValue` | reducer raise | `invalid value 'abc' for '--port <PORT>': expected integer` |
| `ArgumentConflict` | validate | `--json cannot be used at the same time as --yaml` |
| `AmbiguousMatch` | 消費ループ Step 9-10 | `ambiguous argument: multiple commands match` |
| `MissingValue` | 消費ループ | `--port requires a value` |
| `TooManyValues` | 消費ループ | `unexpected value 'extra' for '--flag'` |
| `MissingSubcommand` | validate | `a subcommand is required` |
| `PositionalAsFlag` | 消費ループ | `expected FILE, got --verbose. Use '--' separator` |
| `MultipleUse` | validate | `--output cannot be used multiple times` |

### 7.11 実装優先度

1. **Phase 4 初期**: 基本エラー（UnknownOption, MissingRequired, InvalidValue, MissingValue）+ 1行メッセージ
2. **Phase 4 中期**: 4層構造 + did you mean? サジェスト + Help: 行
3. **Phase 4 後期**: セマンティックスタイリング + FSM 曖昧さ検出 + エラーカスタマイズ API
