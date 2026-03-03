# CLI パーサ リザルト取得・構造化出力 API 調査

調査日: 2026-03-02
目的: Phase 4 CLI パーサ設計における「パース結果をユーザーがどう取り出すか」の API 設計材料

---

## 1. clap (Rust)

### 1.1 パース結果の取得方法

**derive 方式**: `#[derive(Parser)]` で構造体に直接マッピング。完全に型安全。

```rust
#[derive(Parser)]
struct Cli {
    #[arg(long)]
    port: u16,
    #[arg(long)]
    verbose: bool,
}

let cli = Cli::parse();
println!("{}", cli.port);  // u16 として直接アクセス
```

**builder 方式**: `ArgMatches` から `get_one::<T>("name")` で取得。ジェネリクスで型指定。

```rust
let matches = Command::new("app")
    .arg(Arg::new("port").long("port").value_parser(clap::value_parser!(u16)))
    .get_matches();

let port: &u16 = matches.get_one("port").unwrap();
```

derive は構造体フィールド直接アクセス（コンパイル時型安全）、builder は `get_one::<T>` で実行時に型指定（型不一致は panic）。

### 1.2 デフォルト値

- derive: `#[arg(default_value = "8080")]` または Rust 構造体のフィールドデフォルト
- builder: `Arg::default_value("8080")`
- デフォルトは文字列で指定し、value_parser で型変換される

### 1.3 指定 vs デフォルト区別

**`ValueSource` enum** で明確に区別可能:

```rust
pub enum ValueSource {
    DefaultValue,   // Arg::default_value 由来
    EnvVariable,    // Arg::env 由来
    CommandLine,    // ユーザーが明示的に指定
    // non_exhaustive
}

// 使い方
let source = matches.value_source("port"); // Option<ValueSource>
```

`value_source()` メソッドは `ArgMatches` に対して呼び出し、引数名を指定して値のソースを取得する。derive 方式でも `ArgMatches` を取得すれば利用可能。

### 1.4 構造化出力

ArgMatches 自体にシリアライズ機能はない。内部が `AnyValue` のため型情報が失われている。

パターン:
- derive 構造体に `#[derive(Serialize)]` を追加し、serde で JSON/YAML 等にシリアライズ
- `clap-serde-derive` クレートで clap + serde を統合
- 構造化出力は clap の責務外。ユーザー側で実装

### 1.5 繰り返しの結果取得

```rust
// derive
#[arg(long)]
tags: Vec<String>,  // --tags a --tags b → vec!["a", "b"]

// builder
let tags: Vec<&String> = matches.get_many("tags").unwrap().collect();
```

`get_many::<T>` がイテレータを返し、`.collect()` で Vec に変換。

### 1.6 サブコマンドのディスパッチ

**derive**: enum + `#[derive(Subcommand)]` → `match` 分岐

```rust
#[derive(Subcommand)]
enum Commands {
    Serve { port: u16 },
    Deploy { target: String },
}

match &cli.command {
    Commands::Serve { port } => { /* ... */ }
    Commands::Deploy { target } => { /* ... */ }
}
```

**builder**: `matches.subcommand()` → `Option<(&str, &ArgMatches)>` を `match`

```rust
match matches.subcommand() {
    Some(("serve", sub_m)) => { /* sub_m.get_one(...) */ }
    Some(("deploy", sub_m)) => { /* ... */ }
    _ => unreachable!(),
}
```

### 1.7 設定ファイル/環境変数/CLI の統合

- 環境変数: `#[arg(env = "PORT")]` で env feature 有効化時にサポート
- 設定ファイル: clap 単体では非サポート。`clap-serde-derive`, `clap_conf`, `twelf` 等の外部クレートで統合
- 優先順位: CLI > 環境変数 > デフォルト（clap 組み込み）。設定ファイルは外部クレート依存

---

## 2. bpaf (Rust)

### 2.1 パース結果の取得方法

**Applicative スタイル**: パーサの合成結果が直接 Rust 構造体になる。型安全。

```rust
// combinatoric
let port = long("port").argument::<u16>("PORT");
let verbose = long("verbose").switch();
let parser = construct!(Config { port, verbose });
let config: Config = parser.to_options().run();  // Config として直接取得
```

**derive 方式**: clap 同様に `#[derive(Bpaf)]` で構造体定義も可能。

結果は常に型付き構造体/enum として返る。`HashMap` や辞書アクセスの段階がない。

### 2.2 デフォルト値

```rust
let port = long("port").argument::<u16>("PORT")
    .fallback(8080);  // デフォルト値

// 動的デフォルト
let port = long("port").argument::<u16>("PORT")
    .fallback_with(|| Ok(default_port()));
```

- `fallback(val)`: 固定デフォルト
- `fallback_with(fn)`: 動的デフォルト（関数/クロージャ）
- `display_fallback` / `debug_fallback`: ヘルプにデフォルト値を表示

### 2.3 指定 vs デフォルト区別

**直接的なサポートなし**。ただし型レベルで区別可能:

```rust
// Option<T> にして、None = 未指定、Some(v) = 指定
let port = long("port").argument::<u16>("PORT").optional();  // Option<u16>

// fallback + optional の組み合わせで擬似的に区別
// ただし ValueSource のような明示的 enum はない
```

bpaf は applicative の純粋性を重視しており、「パース結果」と「メタ情報」を分離する設計。結果は T そのものであり、ソース情報は付随しない。

### 2.4 構造化出力

パーサが直接 Rust 構造体を返すため、構造体に `#[derive(Serialize)]` を付ければ serde で任意フォーマットにシリアライズ可能。bpaf 側で特別な機能は不要。

### 2.5 繰り返しの結果取得

```rust
// many: 0個以上を Vec に収集
let tags = long("tag").argument::<String>("TAG").many();  // Vec<String>

// some: 1個以上を Vec に収集（0個はエラー）
let tags = long("tag").argument::<String>("TAG").some("at least one tag");

// collect: カスタムコレクションに収集
let tags = long("tag").argument::<String>("TAG").collect::<BTreeSet<_>>();
```

### 2.6 サブコマンドのディスパッチ

enum の各 variant が `#[bpaf(command("name"))]` で対応。結果は enum なので `match` で分岐。

```rust
#[derive(Debug, Clone, Bpaf)]
enum Action {
    #[bpaf(command("serve"))]
    Serve { port: u16 },
    #[bpaf(command("deploy"))]
    Deploy { target: String },
}

match action {
    Action::Serve { port } => { /* ... */ }
    Action::Deploy { target } => { /* ... */ }
}
```

サブコマンドのネストも自然に対応（enum 内に enum）。

### 2.7 設定ファイル/環境変数/CLI の統合

- 環境変数: `env("PORT")` でサポート
- 設定ファイル: bpaf 単体では非サポート。ユーザー側で `fallback_with` を使って実装可能
- 優先順位: CLI > 環境変数 > fallback（bpaf 組み込み）

---

## 3. cobra + viper (Go)

### 3.1 パース結果の取得方法

**cobra**: `cmd.Flags().GetString("name")` 等の型別 getter で取得。構造体マッピングなし。

```go
var port int
cmd.Flags().IntVar(&port, "port", 8080, "listen port")
// または
port, _ := cmd.Flags().GetInt("port")
```

**viper**: `viper.GetString("key")` 等の型別 getter。設定ファイル、環境変数、フラグを統合して単一 API で取得。

```go
viper.BindPFlag("port", cmd.Flags().Lookup("port"))
port := viper.GetInt("port")
```

型安全性は弱い。getter の型指定を間違えるとゼロ値が返る（コンパイルエラーにならない）。

### 3.2 デフォルト値

- cobra: `Flags().IntVar(&port, "port", 8080, "...")` の第3引数
- viper: `viper.SetDefault("port", 8080)`
- 両方設定した場合は viper の優先順位で解決

### 3.3 指定 vs デフォルト区別

**`cmd.Flags().Changed("name")` で明確に区別可能**:

```go
if cmd.Flags().Changed("port") {
    // ユーザーが明示的に --port を指定した
    port, _ := cmd.Flags().GetInt("port")
    fmt.Printf("Port explicitly set to %d\n", port)
} else {
    // デフォルト値が使われた
    fmt.Println("Using default port")
}
```

`Changed()` は pflag パッケージの機能。cobra が pflag を使うため自動的に利用可能。

viper 側にはソース区別の API がない。ただし `viper.IsSet("key")` で「何らかのソースで値が設定されたか」は確認可能。

### 3.4 構造化出力

- cobra 単体: なし
- viper: `viper.AllSettings()` で `map[string]interface{}` を取得可能。JSON/YAML にシリアライズできる
- `viper.WriteConfig()` で設定ファイルへの書き出しもサポート
- 実質的に viper が構造化出力を担当

```go
settings := viper.AllSettings()
jsonBytes, _ := json.MarshalIndent(settings, "", "  ")
```

### 3.5 繰り返しの結果取得

```go
// StringSlice フラグ
var tags []string
cmd.Flags().StringSliceVar(&tags, "tags", nil, "tags")
// --tags a,b --tags c → ["a", "b", "c"]

// StringArray フラグ（コンマ分割なし）
cmd.Flags().StringArrayVar(&tags, "tags", nil, "tags")
// --tags a --tags b → ["a", "b"]
```

cobra/pflag は `StringSlice` と `StringArray` を区別する。viper 側では `viper.GetStringSlice("tags")` で取得。

### 3.6 サブコマンドのディスパッチ

RunE コールバック方式。サブコマンドごとに `Run` / `RunE` 関数を定義。

```go
var serveCmd = &cobra.Command{
    Use:   "serve",
    Short: "Start server",
    RunE: func(cmd *cobra.Command, args []string) error {
        port, _ := cmd.Flags().GetInt("port")
        return startServer(port)
    },
}
rootCmd.AddCommand(serveCmd)
```

型安全なディスパッチ（enum match）ではなく、命令的なコールバック登録。結果は `error` のみ返せる。

### 3.7 設定ファイル/環境変数/CLI の統合

**viper の優先順位**（最も特徴的な部分）:

```
1. overrides (viper.Set)
2. flags (BindPFlag)
3. env variables (BindEnv / AutomaticEnv)
4. config file
5. key/value store (etcd/consul)
6. defaults (SetDefault)
```

6段階の優先順位が明確に定義され、透過的に解決される。CLI ツールで最も成熟した設定統合。

---

## 4. Swift ArgumentParser

### 4.1 パース結果の取得方法

**プロパティラッパー**で構造体フィールドに直接マッピング。完全に型安全。

```swift
struct Serve: ParsableCommand {
    @Option var port: Int = 8080
    @Flag var verbose: Bool = false
    @Argument var file: String

    func run() throws {
        print("Port: \(port)")  // 直接アクセス
    }
}
```

- `@Option`: `--name value` 形式
- `@Flag`: `--name` 形式（bool）
- `@Argument`: 位置引数

構造体そのものがパース結果。`run()` メソッド内で `self.port` のように直接アクセス。

### 4.2 デフォルト値

Swift の標準的なプロパティ初期化構文で指定:

```swift
@Option var port: Int = 8080       // デフォルト値あり
@Option var host: String?          // Optional → nil がデフォルト → 非必須
@Option var name: String           // デフォルト値なし → 必須
```

### 4.3 指定 vs デフォルト区別

**直接的なサポートなし**。

区別のワークアラウンド:
- `Optional` にして `nil` チェック: `@Option var port: Int?` → `nil` なら未指定
- ただし「ユーザーがデフォルトと同じ値を明示指定した」場合は区別不可
- 内部の `InputOrigin` に情報はあるが public API ではない

Swift ArgumentParser は「型が結果」の思想が強く、メタ情報（ソース等）を結果に付随させない設計。

### 4.4 構造化出力

構造体が `Codable` に準拠していれば JSONEncoder 等でシリアライズ可能。ただし `@Option` 等のプロパティラッパーがあるため、カスタムの Codable 実装が必要になる場合がある。

ArgumentParser 自体に構造化出力機能はない。

### 4.5 繰り返しの結果取得

```swift
@Option var tags: [String] = []    // --tags a --tags b → ["a", "b"]
```

配列型のプロパティは自動的に繰り返しオプションとして扱われる。

### 4.6 サブコマンドのディスパッチ

enum + `ParsableCommand` 継承。各サブコマンドが独自の `run()` を持つ。

```swift
struct App: ParsableCommand {
    static var configuration = CommandConfiguration(
        subcommands: [Serve.self, Deploy.self]
    )
}

struct Serve: ParsableCommand {
    @Option var port: Int = 8080
    func run() throws { /* ... */ }
}
```

ディスパッチは自動。`App.main()` がサブコマンドの `run()` を直接呼び出す。明示的な match 分岐が不要。

### 4.7 設定ファイル/環境変数/CLI の統合

- 環境変数: 組み込みサポートなし（`transform` クロージャ内で `ProcessInfo.processInfo.environment` を手動参照する方式）
- 設定ファイル: 非サポート
- CLI 引数のみに特化した設計

---

## 5. oclif (TypeScript)

### 5.1 パース結果の取得方法

`this.parse()` メソッドが `{ flags, args }` オブジェクトを返す。TypeScript の型推論で型安全。

```typescript
import { Command, Flags, Args } from '@oclif/core'

export default class Serve extends Command {
    static flags = {
        port: Flags.integer({ default: 8080 }),
        verbose: Flags.boolean({ default: false }),
    }

    static args = {
        file: Args.string({ required: true }),
    }

    async run() {
        const { flags, args } = await this.parse(Serve)
        console.log(flags.port)  // number 型として推論
        console.log(args.file)   // string 型として推論
    }
}
```

`Interfaces.InferredFlags<typeof Serve.flags>` で型を推論。static プロパティから型情報を取得。

### 5.2 デフォルト値

```typescript
static flags = {
    port: Flags.integer({ default: 8080 }),
    name: Flags.string({ default: async () => computeDefault() }),  // 動的デフォルト
}
```

デフォルトは固定値または非同期関数で指定可能。

### 5.3 指定 vs デフォルト区別

**直接的なサポートなし**。`this.parse()` の結果にソース情報は含まれない。

ワークアラウンド:
- デフォルトを `undefined` にして `flags.port === undefined` で区別
- `process.argv` を直接チェック

### 5.4 構造化出力

**`--json` フラグの組み込みサポート**:

```typescript
export default class MyCommand extends Command {
    static enableJsonFlag = true

    async run() {
        const result = { port: 8080, status: 'running' }
        return result  // --json 付きなら JSON 出力
    }
}
```

`enableJsonFlag = true` で `--json` フラグが自動追加される。`run()` の戻り値が JSON としてシリアライズされる。oclif の独自機能。

### 5.5 繰り返しの結果取得

```typescript
static flags = {
    tags: Flags.string({ multiple: true }),  // string[]
}
```

`multiple: true` で配列として取得。

### 5.6 サブコマンドのディスパッチ

ディレクトリ構造ベースの自動ディスパッチ:

```
src/commands/
  serve.ts       → mycli serve
  deploy/
    index.ts     → mycli deploy
    staging.ts   → mycli deploy staging
```

ファイルシステムがコマンドツリーを定義。明示的なディスパッチコードは不要。

### 5.7 設定ファイル/環境変数/CLI の統合

- 環境変数: `Flags.string({ env: 'PORT' })` でサポート
- 設定ファイル: 非サポート（ユーザー側で実装）
- 優先順位: CLI > 環境変数 > デフォルト

---

## 6. click (Python)

### 6.1 パース結果の取得方法

**コールバック関数のパラメータとして注入**。デコレータが関数引数に値を渡す。

```python
@click.command()
@click.option('--port', type=int, default=8080)
@click.option('--verbose', is_flag=True)
@click.argument('file')
def serve(port, verbose, file):
    print(f"Port: {port}")  # int として受け取る
```

型はデコレータの `type` 引数で指定。Python の動的型付けのため、コンパイル時の型安全性はないが、パース時に型変換・バリデーションが実行される。

### 6.2 デフォルト値

```python
@click.option('--port', type=int, default=8080)
@click.option('--name', default=lambda: get_default_name())  # callable
```

`default` は固定値または callable。callable の場合は呼び出し時に評価。

### 6.3 指定 vs デフォルト区別

**`ParameterSource` enum で明確に区別可能**:

```python
class ParameterSource(enum.Enum):
    COMMANDLINE = ...     # CLI で明示指定
    ENVIRONMENT = ...     # 環境変数由来
    DEFAULT = ...         # default 値
    DEFAULT_MAP = ...     # Context.default_map 由来
    PROMPT = ...          # プロンプト入力

# 使い方
@click.command()
@click.option('--port', type=int, default=8080)
@click.pass_context
def serve(ctx, port):
    source = ctx.get_parameter_source('port')
    if source == click.core.ParameterSource.COMMANDLINE:
        print("Port was explicitly set")
```

Click の `ParameterSource` は clap の `ValueSource` と同等。5段階のソース区別が可能。

### 6.4 構造化出力

Click 自体に構造化出力機能はない。ユーザー側で `json.dumps()` 等を使用。

ただし `Context.params` で全パラメータを `dict` として取得可能:

```python
@click.pass_context
def cmd(ctx):
    params = ctx.params  # {'port': 8080, 'verbose': False}
    json.dumps(params)   # JSON 化可能
```

### 6.5 繰り返しの結果取得

```python
# multiple=True: 繰り返しオプション → tuple
@click.option('--tag', '-t', multiple=True)
def cmd(tag):  # tag = ('a', 'b', 'c')

# nargs=N: 固定個数の値 → tuple
@click.option('--point', nargs=2, type=float)
def cmd(point):  # point = (1.0, 2.0)
```

結果は常に tuple。list ではない。

### 6.6 サブコマンドのディスパッチ

`@click.group()` + `@cli.command()` でコールバック登録。自動ディスパッチ。

```python
@click.group()
def cli():
    pass

@cli.command()
@click.option('--port', type=int, default=8080)
def serve(port):
    print(f"Serving on {port}")

@cli.command()
@click.option('--target')
def deploy(target):
    print(f"Deploying to {target}")
```

各コマンドが独自のコールバック関数を持つ。match 分岐ではなくコールバック登録方式。

### 6.7 設定ファイル/環境変数/CLI の統合

- 環境変数: `@click.option('--port', envvar='PORT')` でサポート。ヘルプにも表示
- 設定ファイル: `Context.default_map` で設定ファイルからの値を統合可能
- 優先順位: CLI > 環境変数 > default_map > default

```python
@click.command()
@click.pass_context
def cmd(ctx):
    # 設定ファイルから読んだ値を default_map に設定
    ctx.default_map = load_config()
```

---

## 7. yargs (Node.js)

### 7.1 パース結果の取得方法

**argv オブジェクト**（プレーンな JS オブジェクト）で取得。辞書アクセス。

```javascript
const argv = yargs(process.argv.slice(2))
    .option('port', { type: 'number', default: 8080 })
    .option('verbose', { type: 'boolean', default: false })
    .parseSync()

console.log(argv.port)     // number
console.log(argv.verbose)  // boolean
console.log(argv._)        // positional args (array)
console.log(argv.$0)       // script name
```

TypeScript では `yargs` が型推論を提供するが、基本的には動的な JS オブジェクト。

### 7.2 デフォルト値

```javascript
yargs.option('port', {
    type: 'number',
    default: 8080,
    defaultDescription: 'HTTP=80, HTTPS=443',  // ヘルプ表示用（実値とは別）
})
```

`defaultDescription` はヘルプ表示を動的デフォルトに合わせるための機能。実際のデフォルト値とは独立。

### 7.3 指定 vs デフォルト区別

**公式サポートなし**。[Issue #513](https://github.com/yargs/yargs/issues/513) で議論されたが未実装。

ワークアラウンド:
- `process.argv` を直接チェック
- デフォルトを `undefined` にして `argv.port === undefined` で区別
- sentinel 値を使用

```javascript
// ワークアラウンド例
const isExplicit = process.argv.includes('--port')
```

### 7.4 構造化出力

argv オブジェクトが JS のプレーンオブジェクトなので `JSON.stringify` で即座に JSON 化可能。

```javascript
const argv = yargs(args).option('port', { ... }).parseSync()
console.log(JSON.stringify(argv, null, 2))
// { "port": 8080, "verbose": false, "_": [], "$0": "app" }
```

内部メタデータ（`_`, `$0`）も含まれる。ケバブケースのオプションは `camel-case-expansion` でキャメルケースプロパティも自動生成される。

### 7.5 繰り返しの結果取得

```javascript
yargs.option('tag', {
    type: 'string',
    array: true,  // --tag a --tag b → ['a', 'b']
})
```

`array: true` で配列として取得。

### 7.6 サブコマンドのディスパッチ

**handler コールバック方式**:

```javascript
yargs
    .command('serve', 'Start server', (yargs) => {
        yargs.option('port', { type: 'number', default: 8080 })
    }, (argv) => {
        console.log(`Serving on ${argv.port}`)
    })
    .command('deploy', 'Deploy app', {}, (argv) => { /* ... */ })
    .parse()
```

- `builder` 関数でサブコマンド固有のオプションを定義
- `handler` 関数でサブコマンドのロジックを実行
- ディレクトリベースのコマンド発見もサポート（oclif と同様）

### 7.7 設定ファイル/環境変数/CLI の統合

- 環境変数: `envPrefix` で一括指定、または `option` ごとに未サポート（手動実装）
- 設定ファイル: `yargs.config()` でサポート。JSON ファイルから読み込み
- 優先順位: CLI > config > default（ただし明確な統合フレームワークはない）

---

## 比較サマリー

### 指定 vs デフォルト区別

| パーサ | 区別可能? | 方法 | ソース種別 |
|--------|-----------|------|-----------|
| **clap** | **可能** | `value_source()` → `ValueSource` enum | Default, Env, CommandLine |
| **bpaf** | **不可** | `Option<T>` で擬似的に | - |
| **cobra** | **可能** | `Flags().Changed("name")` → bool | 2値（変更あり/なし） |
| **Swift AP** | **不可** | `Optional` で擬似的に | - |
| **oclif** | **不可** | `undefined` チェックのワークアラウンド | - |
| **click** | **可能** | `get_parameter_source()` → `ParameterSource` enum | CommandLine, Env, Default, DefaultMap, Prompt |
| **yargs** | **不可** | `process.argv` 直接チェック | - |

**明確にサポートしているのは clap, cobra, click の3つ**。特に clap と click は enum でソースの種類まで区別できる。

### 構造化出力

| パーサ | 構造化出力 | 方法 |
|--------|-----------|------|
| **clap** | 間接的 | derive 構造体 + serde |
| **bpaf** | 間接的 | 結果構造体 + serde |
| **cobra+viper** | **直接** | `viper.AllSettings()` → `map[string]any` |
| **Swift AP** | 間接的 | Codable 準拠 |
| **oclif** | **直接** | `enableJsonFlag` で `--json` 自動追加 |
| **click** | 間接的 | `ctx.params` → dict |
| **yargs** | 暗黙的 | argv が JS オブジェクト → `JSON.stringify` |

### サブコマンドディスパッチ方式

| パーサ | 方式 | パターン |
|--------|------|---------|
| **clap** | enum match | 構造的分岐 |
| **bpaf** | enum match | 構造的分岐 |
| **cobra** | callback | `RunE` 関数登録 |
| **Swift AP** | 自動 dispatch | 各構造体の `run()` 直接呼び出し |
| **oclif** | ファイル構造 | ディレクトリ = コマンドツリー |
| **click** | callback | デコレータでコマンド登録 |
| **yargs** | callback | `handler` 関数登録 |

---

## Phase 4 設計に取り入れるべきポイント

### 1. ValueSource enum の導入（clap / click 方式）

現在の `result.get(opt)` は T を直接返すが、**値のソース情報** を取得する API が必要。

```moonbit
///| 値のソース
pub(all) enum ValueSource {
    Initial          // 初期値のまま（ユーザー未指定）
    Default(String)  // defaults ソースから（ソース名付き）
    Environment      // 環境変数から
    CommandLine      // CLI で明示指定
} derive(Eq, Show, Debug)

// API
result.get(port)          // T — 値そのもの
result.source(port)       // ValueSource — 値のソース
result.is_explicit(port)  // Bool — CommandLine かどうかのショートカット
```

**clap と click の共通項**: 3段階以上のソース区別が有用。特に設定ファイル統合時に「CLI > env > config > default」の優先順位でどのソースが勝ったかを知りたい。

**cobra の Changed()**: bool のみで簡潔だが、env/config の区別ができない。Phase 4 では enum 方式を採用すべき。

**実装への影響**: ResultMap / Opt[T] の slots に値と一緒にソース情報を保持。reducer が ReduceAction を処理する際に CommandLine ソースを記録。defaults マージ時に各ソースの識別子を記録。

### 2. 構造化出力のアプローチ

Phase 4 設計では「バリデーションはユーザー側に委ねる」思想。構造化出力も同様:

**推奨方式**:
- `result.to_entries()` → `Array[(String, String, ValueSource)]` (name, value_string, source) で全パース結果をシンプルに列挙
- JSON シリアライズはユーザー側で実装（MoonBit の `@json` パッケージ）
- パーサ側は「結果の列挙」まで。フォーマットは責務外

**oclif の `--json` パターン**: パーサの責務を超えるため不採用。ただし `result.to_json()` ヘルパーを便利関数として提供するのはあり。

### 3. 繰り返し結果の統一

全パーサで Array/Vec 型が標準。Phase 4 の `Append` reducer も `Array[T]` を返す設計で統一されている。問題なし。

### 4. サブコマンドディスパッチ: callback vs match

MoonBit にはリフレクションも derive マクロもないため:
- **enum match 方式** (clap/bpaf): ユーザー定義 enum への自動マッピングが困難
- **callback 方式** (cobra/click/yargs): `cmd("serve", handler_fn)` でコールバック登録 → MoonBit で自然に実現可能
- **現在の設計** `result.command()` → `ErasedNode?` は中間的。ユーザーが名前で分岐する必要がある

**推奨**: callback 方式をプライマリにしつつ、`result.command()` で手動分岐も可能にする二段構えが望ましい。

```moonbit
// callback 方式（推奨）
let serve = cmd("serve", opts([port, host]), fn(result) {
    let p = result.get(port)
    start_server(p)
})

// 手動分岐方式（フォールバック）
let result = parse(args, app)
match result.command() {
    Some(node) if node.meta.name == "serve" => { ... }
    Some(node) if node.meta.name == "deploy" => { ... }
    _ => show_help()
}
```

### 5. defaults 統合の優先順位モデル（viper 参考）

現在の Phase 4 設計「各ソースごとに独立 ResultMap → 後勝ちマージ」は viper のモデルと本質的に同じ。

viper の6段階を参考に Phase 4 の優先順位:

```
1. CLI 引数              (CommandLine)
2. 環境変数              (Environment)
3. 設定ファイル          (Default("config"))
4. initial 値            (Initial)
```

各段階で独立に parse → 後勝ちマージ。ValueSource を記録することで「どのソースが勝ったか」をユーザーが確認可能。

### 6. Optional[T] vs ValueSource の使い分け

bpaf / Swift AP の「Optional で区別」パターンは MoonBit でも自然に使える:

```moonbit
let port = opt::int(name="port")           // Int（required、未指定はエラー）
let host = opt::str_opt(name="host")       // String?（optional、未指定は None）
```

ただし ValueSource があれば:
- `port` のデフォルト 8080 が initial 由来か CLI 指定かを区別可能
- 設定ファイル統合時に「どのソースからの値か」を透過的に追跡可能

**両方提供** が望ましい。`get(opt)` で値、`source(opt)` でソース。

---

## 参考リンク

- [clap ValueSource](https://docs.rs/clap/latest/clap/parser/enum.ValueSource.html)
- [clap derive tutorial](https://docs.rs/clap/latest/clap/_derive/_tutorial/index.html)
- [bpaf documentation](https://docs.rs/bpaf/latest/bpaf/)
- [cobra Flags().Changed()](https://cobra.dev/docs/how-to-guides/working-with-flags/)
- [viper priority order](https://github.com/spf13/viper)
- [Swift ArgumentParser](https://github.com/apple/swift-argument-parser)
- [oclif flags](https://oclif.io/docs/flags/)
- [click ParameterSource](https://click.palletsprojects.com/en/stable/api/)
- [yargs Issue #513](https://github.com/yargs/yargs/issues/513)
- [clap-serde-derive](https://crates.io/crates/clap-serde-derive)
