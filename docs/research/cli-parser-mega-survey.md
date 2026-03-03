# CLI引数パーサライブラリ 大規模横断調査

調査日: 2026-02-24

---

## 1. エグゼクティブサマリー

### 全体の傾向

CLI引数パーサは言語エコシステムごとに設計思想が大きく異なるが、2020年代に入り以下の収束傾向がみられる。

1. **型安全な宣言的API**: derive/デコレータ/struct tag等で型からCLIを生成する手法が主流化。Rust(clap derive)、Go(kong)、Python(typer)、Swift(ArgumentParser)、TypeScript(clipanion)がこの路線。
2. **Applicative/Compose系の台頭**: bpaf(Rust)、optparse-applicative(Haskell)がApplicativeファンクタベースの合成を採用。パーサの型安全な合成と自動ヘルプ生成を両立する。
3. **環境変数統合の標準化**: clap、kong、urfave/cli、click、typer、clipanion等が環境変数フォールバックをファーストクラスでサポート。ヘルプへの表示も広がりつつある。
4. **補完生成の必須化**: bash/zsh/fishへの補完スクリプト生成は成熟したパーサの標準機能となった。
5. **`--no-xxx`反転フラグ**: Click(Python)、kong(Go)、urfave/cli v3(Go)、Swift ArgumentParser、Clipanion(TS)、yargs(JS)が組み込みサポート。clap(Rust)とcobra(Go)は未サポートで手動実装が必要。

### 注目ポイント

- **kong(Go)**: struct tagベースで`negatable:""`による`--no-xxx`自動生成、`env:""`で環境変数、`group:""`でヘルプセクション分け。ユーザーの好みに最も近いGoパーサ。
- **bpaf(Rust)**: Applicative合成で型安全かつ柔軟。環境変数、補完、ヘルプカスタマイズを網羅。clapより軽量でありながら表現力が高い。
- **Swift ArgumentParser**: Apple公式で`FlagInversion`による`--no-xxx`/`--enable-xxx`/`--disable-xxx`を型レベルでサポート。設計の美しさが際立つ。
- **Clipanion(TS)**: 有限状態機械ベースのコマンド解決。`--no-xxx`、環境変数、TypeScript型安全を兼ね備える。
- **cligen(Nim)**: proc signatureからCLIを自動推論。最小コード量で完全なCLIを生成する独自路線。

---

## 2. 言語別 詳細レビュー

### 2.1 Rust

#### clap (derive + builder)

Rustで最も普及したCLIパーサ。derive macroとbuilder APIの二つの入口を持つ。

- **サブコマンド**: `#[derive(Subcommand)]`で無制限ネスト対応。`Command::subcommand_help_heading`でヘルプ表示もカスタマイズ可能。
- **ヘルプ生成**: `help_heading`属性でセクション分け可能。デフォルトはARGS/OPTIONS/SUBCOMMANDS。カスタムセクション追加も可能だが、グローバルオプションと環境変数のセクションは手動設定が必要。
- **オプション定義**: `#[arg(long, short)]`でロング/ショート。`required`、`default_value`等の属性が豊富。
- **boolフラグ**: `--no-xxx`自動生成は**未サポート**。`overrides_with`を使った手動ワークアラウンドが必要（[Issue #815](https://github.com/clap-rs/clap/issues/815)は未解決）。
- **`--`セパレータ**: 対応。`last(true)`や`trailing_var_arg(true)`で制御。
- **引数位置の自由度**: interspersed optionsをサポート。位置引数とオプションを混在可能。
- **環境変数**: `env` featureを有効化し`#[arg(env = "VAR")]`で指定。ヘルプに環境変数名も表示される。
- **completion生成**: `clap_complete`クレートでbash/zsh/fish/PowerShell/elvish対応。
- **型安全性**: derive macroで構造体に直接パース。強い型安全。
- **バリデーション**: `value_parser`、`PossibleValue`、カスタムバリデータ。
- **エラーメッセージ**: カラー出力、サジェスト機能（did you mean?）、カスタマイズ可能。
- **APIスタイル**: derive（宣言的） + builder（命令的）のハイブリッド。

**強み**: 機能網羅性、エコシステムの大きさ、ドキュメント充実。
**弱み**: コンパイル時間が長い、`--no-xxx`未サポート、機能フラグが多く設定が複雑。

#### argh (Google)

Fuchsia CLIツール仕様準拠のderive-basedパーサ。コードサイズ最適化を重視。

- **サブコマンド**: enum + `#[argh(subcommand)]`で対応。再帰的ネスト可能。
- **ヘルプ生成**: 基本的なヘルプのみ。セクション分けカスタマイズは限定的。
- **boolフラグ**: `#[argh(switch)]`。`--no-xxx`サポートなし。
- **`--`セパレータ**: 対応。
- **環境変数**: **未サポート**。
- **completion生成**: **未サポート**。
- **型安全性**: derive macroで型安全。
- **APIスタイル**: derive only。

**強み**: バイナリサイズ最小、シンプルなAPI。
**弱み**: 機能が少ない。環境変数・補完・`--no-xxx`すべて非対応。

#### pico-args

ゼロ依存のミニマルパーサ。

- **サブコマンド**: **未サポート**。フラグとオプションと自由引数のみ。
- **ヘルプ生成**: **未サポート**。手動記述が必要。
- **boolフラグ**: 基本的なフラグのみ。反転なし。
- **`--`セパレータ**: 対応。
- **環境変数**: **未サポート**。
- **completion生成**: **未サポート**。
- **型安全性**: `FromStr`トレイトによる変換。
- **APIスタイル**: imperative（ストリーミング）。

**強み**: コンパイル速度、バイナリサイズ、コードの単純さ。
**弱み**: 本格的なCLIには不向き。

#### lexopt

ペダンティックに正確な低レベルレキサー。

- **サブコマンド**: パーサではなくレキサーなので、アプリケーション側で実装。
- **ヘルプ生成**: **未サポート**。
- **boolフラグ**: 手動実装。
- **`--`セパレータ**: 正確に対応。
- **環境変数**: **未サポート**。
- **completion生成**: **未サポート**。
- **型安全性**: `OsString`ベース。明示的な変換が必要。
- **APIスタイル**: imperative（イテレータ）。

**強み**: 正確性、ゼロ依存、OsString対応（不正エンコーディング耐性）。
**弱み**: すべて手動実装。CLIフレームワークの基盤として使う用途。

#### bpaf

Applicativeインターフェースのコマンドラインパーサ。

- **サブコマンド**: `command()`で定義。無制限ネスト。
- **ヘルプ生成**: doc commentからの自動生成。セクション分けはグルーピング可能。
- **オプション定義**: `short`/`long`/`env`を連鎖して定義。
- **boolフラグ**: `flag`/`switch`で定義。`--no-xxx`はnamed argを2つ定義して合成する形。
- **`--`セパレータ**: 対応。
- **引数位置の自由度**: Applicativeなのでパーサ定義順序と入力順序は独立。
- **環境変数**: `env("VAR")`でファーストクラスサポート。
- **completion生成**: bash/zsh/fish/elvish対応（動的補完）。
- **型安全性**: Applicativeファンクタベースで非常に強い型安全。
- **バリデーション**: `guard`、`parse`で変換・検証。
- **APIスタイル**: combinatoric（合成的） + derive（宣言的）のハイブリッド。

**強み**: 合成的で表現力が高い、コンパイル時間が短い（clapより大幅に短い）、環境変数・補完対応。
**弱み**: Applicativeの概念に馴染みがないと学習コストが高い。

---

### 2.2 Go

#### cobra + pflag

Go最大のCLIフレームワーク。Kubernetes、Hugo、GitHub CLIなどが採用。

- **サブコマンド**: 無制限ネスト。`AddCommand`で追加。
- **ヘルプ生成**: 自動生成。カスタムテンプレートで全面的にカスタマイズ可能。サブコマンド一覧、フラグ、継承フラグのセクション分け。
- **boolフラグ**: `--flag=true/false`形式のみ。**`--no-xxx`プレフィックスは未サポート**（[Issue #958](https://github.com/spf13/cobra/issues/958)は未解決）。
- **`--`セパレータ**: pflagが対応。
- **引数位置の自由度**: GNUスタイルでinterspersed。
- **環境変数**: cobra単体では未サポート。**viper**との連携で環境変数・設定ファイルを統合。ヘルプへの環境変数表示は手動。
- **completion生成**: bash/zsh/fish/PowerShell対応。動的補完もサポート。
- **型安全性**: pflagの型付きフラグ。構造体へのバインドは手動。
- **バリデーション**: `Args`フィールド(`ExactArgs`, `MinimumNArgs`等)、`RunE`でエラー返却。
- **エラーメッセージ**: サジェスト機能（did you mean?）。
- **APIスタイル**: imperative / builder。
- **Persistent Flags**: 親コマンドから子コマンドへフラグを継承する仕組み（グローバルオプション相当）。

**強み**: エコシステム最大、ドキュメント豊富、補完が優秀、Persistent Flagsでグローバルオプション。
**弱み**: `--no-xxx`未サポート、環境変数はviper依存、struct tagベースではなくコード量が多い。

#### urfave/cli (v3)

宣言的でシンプルなGoのCLIパッケージ。

- **サブコマンド**: ネスト対応。`Commands`フィールドで定義。
- **ヘルプ生成**: 自動生成。テンプレートカスタマイズ可能。カテゴリによるグルーピング。
- **boolフラグ**: v3で`BoolWithInverseFlag`追加。`--no-xxx`を自動生成。InversePrefixでカスタマイズも可能。
- **`--`セパレータ**: 対応。
- **環境変数**: フラグ定義に`Sources`で環境変数を指定。ヘルプに表示される。
- **completion生成**: bash対応（`BashComplete`フック）。zsh/fishは限定的。
- **型安全性**: 各型のフラグ構造体で型付き。
- **APIスタイル**: declarative（構造体リテラル）。

**強み**: シンプルなAPI、`--no-xxx`サポート(v3)、環境変数のヘルプ表示。
**弱み**: cobraと比べエコシステムが小さい、補完がbash中心。

#### kong

struct tagベースの宣言的パーサ。

- **サブコマンド**: `cmd:""`タグで無制限ネスト。
- **ヘルプ生成**: `group:""`タグでセクション分け。カスタムHelpPrinterも指定可能。
- **boolフラグ**: `negatable:""`で**`--no-xxx`を自動生成**。`negatable:"X"`でカスタム反転名も可能。
- **`--`セパレータ**: 対応。
- **引数位置の自由度**: interspersed。
- **環境変数**: `env:"VAR"`タグ。ヘルプに表示。
- **completion生成**: `kongplete`/`king`パッケージでbash/zsh対応。
- **型安全性**: struct定義から直接パース。非常に型安全。
- **バリデーション**: `enum:"a,b,c"`、`required:""`、カスタムバリデータ。
- **エラーメッセージ**: カスタマイズ可能。
- **APIスタイル**: declarative（struct tag）。
- **追加機能**: `xor:`（排他）、`and:`（依存）、`embed:""`（埋め込み）、`prefix:""`（ネスト）。

**強み**: struct tagだけで完結する宣言的API、`--no-xxx`組み込み、環境変数対応、グルーピング。ユーザーの好みに最も適合するGoパーサ。
**弱み**: cobraほどのエコシステムはない。

#### ff (flags-first)

Go標準の`flag.FlagSet`を拡張するミニマルなパッケージ。

- **サブコマンド**: `ffcli.Command`でネスト対応。
- **ヘルプ生成**: 基本的な自動生成。カスタマイズは限定的。
- **boolフラグ**: Go標準のflagに準拠。`--no-xxx`未サポート。
- **`--`セパレータ**: 対応。
- **環境変数**: ファーストクラスサポート。設定ファイル（JSON、.env等）も統合。優先順位: CLI > 環境変数 > 設定ファイル > デフォルト。
- **completion生成**: **未サポート**（外部実装を推奨）。
- **型安全性**: Go標準flag準拠。
- **APIスタイル**: flags-first（フラグ中心の設定哲学）。

**強み**: 軽量、Go標準flagとの互換性、環境変数・設定ファイル統合。
**弱み**: 機能が最小限、補完なし。

---

### 2.3 Python

#### click

デコレータベースの成熟したCLIフレームワーク。

- **サブコマンド**: `@click.group()`で無制限ネスト。`add_command()`やデコレータで追加。
- **ヘルプ生成**: 自動生成。セクション分けはデフォルト（Options、Commands）。カスタマイズ可能。
- **boolフラグ**: **`--flag/--no-flag`をファーストクラスサポート**。`@click.option('--verbose/--no-verbose')`で定義。
- **`--`セパレータ**: 対応。
- **引数位置の自由度**: デフォルトはinterspersed。`allow_interspersed_args=False`で無効化も可能。
- **環境変数**: `envvar="VAR"`で指定。ヘルプに表示可能（`show_envvar=True`）。
- **completion生成**: `click.shell_completion`モジュールでbash/zsh/fish対応。
- **型安全性**: Pythonの型変換（`type=int`等）。静的型安全ではない。
- **バリデーション**: `type=click.Choice([...])`、`callback`でカスタム検証。
- **エラーメッセージ**: ユーザーフレンドリー。カスタマイズ可能。
- **APIスタイル**: declarative（デコレータ）。

**強み**: Pythonで最も成熟、`--no-xxx`ネイティブ、環境変数対応、補完対応。
**弱み**: 型ヒントベースではない（typerが解決）。

#### typer

click上に構築された、型ヒントベースのCLIフレームワーク。

- **サブコマンド**: `app.add_typer()`で無制限ネスト。
- **ヘルプ生成**: 自動生成。clickベースのカスタマイズが可能。
- **boolフラグ**: **`--flag/--no-flag`を自動生成**。bool型のデフォルト値に基づいて適切な形式を生成。
- **`--`セパレータ**: 対応（click由来）。
- **環境変数**: `envvar="VAR"`で指定。
- **completion生成**: bash/zsh/fish/PowerShell対応。`--install-completion`で自動インストール。
- **型安全性**: Python型ヒントから推論。エディタ補完が効く。
- **バリデーション**: 型ヒントベースの自動バリデーション + Annotatedでカスタム。
- **APIスタイル**: declarative（型ヒント + デコレータ）。

**強み**: 最小コードで機能豊富なCLI。型ヒントから自動推論。clickの全機能を継承。
**弱み**: click依存、起動が若干遅い。

#### argparse（標準ライブラリ）

Pythonの標準ライブラリ。

- **サブコマンド**: `add_subparsers()`で対応。ネストは可能だが**公式にはサポート外**で不安定。
- **ヘルプ生成**: 自動生成。フォーマッタでカスタマイズ可能。
- **boolフラグ**: `store_true`/`store_false`アクション。`--no-xxx`は手動定義。
- **`--`セパレータ**: 対応。
- **引数位置の自由度**: **制限あり**。オプションはサブコマンド名の前に置く必要がある。
- **環境変数**: **未サポート**（手動実装、ConfigArgParseで拡張可能）。
- **completion生成**: **未サポート**（argcompleteで拡張可能）。
- **型安全性**: `type=`で変換指定。静的型安全ではない。
- **APIスタイル**: imperative / builder。

**強み**: 標準ライブラリ、追加依存なし。
**弱み**: ネストしたサブコマンドが不安定、環境変数・補完が外部依存、引数位置制約。

#### fire (Google)

任意のPythonオブジェクトからCLIを自動生成。

- **サブコマンド**: クラスのメソッド = サブコマンド。ネスト可能。
- **ヘルプ生成**: docstringから自動生成。カスタマイズは限定的。
- **boolフラグ**: `--flag`/`--noflag`形式で自動サポート（`--no-flag`ではなく`--noflag`）。
- **`--`セパレータ**: 対応。Fireでは`--`の後はPythonの式として解釈される。
- **環境変数**: **未サポート**。
- **completion生成**: Fireが補完スクリプトを生成可能。
- **型安全性**: Python関数シグネチャから推論。実行時型チェック。
- **APIスタイル**: magic / auto-generate。

**強み**: ゼロコードでCLI生成、プロトタイピングに最適。
**弱み**: 本格CLIには不向き、カスタマイズ性が低い、`--noflag`形式が非標準。

---

### 2.4 Node.js / TypeScript

#### commander.js

Node.jsで最も普及したCLIフレームワーク。

- **サブコマンド**: `.command()`/`.addCommand()`で無制限ネスト。
- **ヘルプ生成**: 自動生成。カスタムヘルプテキスト追加可能。
- **boolフラグ**: `--no-xxx`で**自動的にfalse設定**。`--no-`プレフィックスを検出して自動処理。
- **`--`セパレータ**: 対応。`enablePositionalOptions()`と`passThroughOptions()`で制御。
- **環境変数**: `.env("VAR")`で指定。CLIオプション > 環境変数 > デフォルトの優先順位。
- **completion生成**: **組み込みなし**（外部パッケージで対応）。
- **型安全性**: TypeScript型定義あり。パース結果は`opts()`で取得。
- **バリデーション**: `.choices()`、カスタムパーサ関数。
- **APIスタイル**: builder（メソッドチェーン）。

**強み**: 最も普及、`--no-xxx`自動、環境変数対応。
**弱み**: 補完生成なし、TypeScript型安全が弱い。

#### yargs

宣言的で豊富な機能を持つパーサ。

- **サブコマンド**: `.command()`でネスト対応。
- **ヘルプ生成**: 自動生成。グルーピング可能。
- **boolフラグ**: **`--no-xxx`をネイティブサポート**。`boolean-negation`パーサ設定で制御。
- **`--`セパレータ**: 対応。`'--'`以降を配列で取得可能。
- **環境変数**: `.env(prefix)`で一括バインド。接頭辞ベースの自動マッピング。
- **completion生成**: bash/zsh対応。`.completion()`で有効化。動的補完もサポート。**補完時に`--no-xxx`も考慮**。
- **型安全性**: TypeScript型定義あり。`.strict()`で未知オプションを拒否。
- **バリデーション**: `.check()`、`.choices()`、`.implies()`、`.conflicts()`。
- **APIスタイル**: declarative（メソッドチェーン）。

**強み**: 機能豊富、`--no-xxx`対応、補完生成、環境変数対応。
**弱み**: バンドルサイズが大きい。

#### gunshi (kazupon)

モダンなJavaScript CLIライブラリ。Node.js/Deno/Bunのユニバーサルランタイム対応。

- **サブコマンド**: オブジェクトスタイルとlazy loadingで対応。コンテキスト共有。
- **ヘルプ生成**: プラグ可能なレンダラでカスタマイズ。i18n対応。
- **boolフラグ**: 基本的なフラグ対応。`--no-xxx`は調査時点で明示的なドキュメントなし。
- **`--`セパレータ**: args-tokensによるパース。
- **環境変数**: プラグインシステムで対応可能。
- **completion生成**: `@gunshi/plugin-completion`プラグインでbash対応。動的補完。
- **型安全性**: TypeScript型パラメータによる包括的な型安全。compile-time safety。
- **バリデーション**: カスタムバリデーション。
- **APIスタイル**: declarative + plugin-based。

**強み**: ユニバーサルランタイム、プラグインシステム、i18n、TypeScript型安全。
**弱み**: 比較的新しく、エコシステムが発展途上。

#### clipanion (Yarn製)

有限状態機械ベースのTypeScript CLIフレームワーク。

- **サブコマンド**: コマンドパスで定義。無制限ネスト（例: `yarn workspaces list`）。
- **ヘルプ生成**: 自動生成。カスタマイズ可能。
- **boolフラグ**: **`--no-xxx`をネイティブサポート**。カウンタオプションでは`--no-verbose`でリセット。
- **`--`セパレータ**: 対応。**`--`なしの透過的プロキシもサポート**。
- **環境変数**: `env`プロパティで指定。明示的オプションが優先。
- **completion生成**: 限定的。
- **型安全性**: TypeScriptのクラスベースで型安全。Typanion連携でバリデーション強化。
- **バリデーション**: Typanionライブラリとの統合。
- **APIスタイル**: class-based / declarative。

**強み**: FSMベースの高速コマンド解決、`--no-xxx`・環境変数対応、`--`なしプロキシ。
**弱み**: ランタイム依存なし（メリットでもある）、補完が限定的。

#### citty (UnJS / Nuxt)

UnJSエコシステムのエレガントなCLIビルダー。

- **サブコマンド**: `defineCommand`でサブコマンド定義。
- **ヘルプ生成**: 自動生成。usageレンダリング。
- **boolフラグ**: 基本的な対応。`--no-xxx`の明示的サポートは不明。
- **`--`セパレータ**: 対応（推定）。
- **環境変数**: 明示的なドキュメントなし。
- **completion生成**: **未サポート**（Issue #130で議論中）。
- **型安全性**: TypeScript `defineCommand`型ヘルパーで型安全。
- **APIスタイル**: declarative。

**強み**: 軽量、UnJS/Nuxtエコシステムとの親和性。
**弱み**: 機能が少ない、補完なし、ドキュメントが未成熟。

#### oclif (Salesforce)

プラグインアーキテクチャのCLIフレームワーク。

- **サブコマンド**: コロン区切り（`app:deploy`）またはスペース区切りの多段コマンド。
- **ヘルプ生成**: 自動生成。ヘルプクラスでカスタマイズ。Markdownドキュメント生成。
- **boolフラグ**: `Flags.boolean()`。`--no-xxx`は明示的サポートなし。`allowNo`オプションで制御可能。
- **`--`セパレータ**: 対応。
- **環境変数**: `env:"VAR"`で指定。ヘルプへの表示は[Issue #181](https://github.com/oclif/oclif/issues/181)で要望中。
- **completion生成**: 組み込みautocomplete。bash/zsh/fish対応のプラグインあり。
- **型安全性**: TypeScriptクラスベースで型安全。
- **バリデーション**: `dependsOn`、`exclusive`、`exactlyOne`等のフラグ間関係定義。
- **APIスタイル**: class-based / framework。
- **プラグインシステム**: oclif最大の特徴。CLIを分割・拡張可能。

**強み**: プラグインアーキテクチャ、エンタープライズレベル、フラグ間関係定義。
**弱み**: 重量級、学習コストが高い。

---

### 2.5 Swift

#### swift-argument-parser (Apple公式)

SwiftのプロパティラッパーとProtocolで型安全なCLI定義。

- **サブコマンド**: `ParsableCommand`プロトコルで無制限ネスト。`CommandConfiguration`でサブコマンドをセクション分け可能。エイリアスもサポート。
- **ヘルプ生成**: 高品質な自動生成。`CommandConfiguration`でセクション分けされたサブコマンド表示。`@Flag`/`@Option`/`@Argument`の各ヘルプ文字列。
- **boolフラグ**: **`FlagInversion`による3種類のネイティブサポート**:
  - `.prefixedNo`: `--render`/`--no-render`
  - `.prefixedEnableDisable`: `--enable-cache`/`--disable-cache`
  - Optional `Bool?`でnil/true/falseの3状態。
- **`--`セパレータ**: 対応。
- **引数位置の自由度**: interspersed。
- **環境変数**: **未サポート**（[Issue #4](https://github.com/apple/swift-argument-parser/issues/4)で要望中）。`ProcessInfo.processInfo.environment`で手動対応。
- **completion生成**: `--generate-completion-script`でbash/zsh/fish対応。カスタム補完（`.file()`, `.directory()`等）。
- **型安全性**: Swiftの型システムで非常に強い型安全。
- **バリデーション**: `validate()`メソッドでカスタム検証。`@Option`の`transform:`で変換。
- **エラーメッセージ**: 高品質。`ValidationError`でカスタムエラー。
- **APIスタイル**: declarative（プロパティラッパー + Protocol）。

**強み**: `FlagInversion`の設計が最も優れている（3パターン対応）、型安全性、補完生成。Apple公式。
**弱み**: 環境変数未サポート、Swiftエコシステム限定。

---

### 2.6 Zig

#### zig-clap (Hejsil)

clap-rsにインスパイアされたZig用パーサ。

- **サブコマンド**: サポート。
- **ヘルプ生成**: ヘルプ文字列のパースと生成が可能。
- **boolフラグ**: ショートフラグのチェーン（`-abc`）対応。
- **`--`セパレータ**: 対応（推定）。
- **環境変数**: 不明。
- **completion生成**: 不明。
- **型安全性**: Zigのcomptime型システムを活用。
- **APIスタイル**: 宣言的（ヘルプ文字列ベース）。

#### yazap (prajwalch)

clap-rsインスパイアのZig用パーサ。

- **サブコマンド**: ネストしたサブコマンド対応。
- **ヘルプ生成**: 自動生成。
- **boolフラグ**: ブール短縮オプションのチェーン対応。
- **`--`セパレータ**: 対応。
- **環境変数**: 不明。
- **completion生成**: 不明（ドキュメントサイトが停止中）。
- **型安全性**: Zigの型システム活用。
- **APIスタイル**: builder。

**Zigの総評**: Zigのパーサエコシステムは発展途上。zig-clapとyazapが主要候補だが、Rust/Goレベルの成熟度には達していない。

---

### 2.7 OCaml

#### cmdliner

OCamlの標準的CLIパーサ。宣言的定義とman page生成。

- **サブコマンド**: `Term.eval_choice`で複数コマンド。
- **ヘルプ生成**: **UNIX man page自動生成**。セクション分けはmanページの慣例に従う。
- **boolフラグ**: `Arg.flag`で基本フラグ。`--no-flag`は`const not`を適用して手動実装。
- **`--`セパレータ**: 対応。POSIX/GNU慣例準拠。
- **環境変数**: `env`パラメータで環境変数を指定可能。値が未指定時にフォールバック。
- **completion生成**: bash/zsh対応の補完スクリプト。
- **型安全性**: OCamlの型システムで型安全。
- **APIスタイル**: declarative / combinator。

**強み**: man page自動生成、POSIX/GNU準拠、環境変数対応。
**弱み**: OCamlエコシステム限定、ドキュメントが少ない。

#### Core.Command (Jane Street)

Jane Streetの産業用Core ライブラリのCLIモジュール。

- **サブコマンド**: 対応。複数ユーティリティの統合をサポート。
- **ヘルプ生成**: 自動生成。
- **boolフラグ**: `no_arg`フラグ対応。
- **`--`セパレータ**: 対応。
- **環境変数**: 不明。
- **completion生成**: bash auto-completion対応。
- **型安全性**: OCamlの型システム + Applicative。
- **APIスタイル**: applicative / combinator。

**強み**: 産業レベルの信頼性、Async対応、auto-completion。
**弱み**: Jane Street Coreへの依存が大きい。

---

### 2.8 その他の言語

#### Nim: cligen

proc signatureからCLIを自動推論する独自アプローチ。

- **サブコマンド**: `dispatchMulti`でgitスタイルのサブコマンド。
- **ヘルプ生成**: 自動生成。スタイル非感知識別子（`--dry-run`と`--dryRun`が同一視）。
- **boolフラグ**: Nimのbool型で自動。
- **環境変数**: `mergeCfgEnv`で`$CMD`環境変数と設定ファイルを統合。`$NO_COLOR`対応。
- **completion生成**: bash(`_longopt`)、zsh(`_gnu_generic`)と互換。
- **型安全性**: Nimの型システムで推論。
- **APIスタイル**: magic / reflection。

**強み**: 最小コード（`dispatch`の1行）、あいまいプレフィックスマッチ、環境変数・設定ファイル統合。
**弱み**: Nimエコシステム限定。

#### Nim: docopt.nim

ドキュメントからCLIを逆生成。

- **APIスタイル**: documentation-driven。使い方テキストを書くとパーサが生成される。
- **サブコマンド**: 使い方テキスト内で定義可能。
- **completion生成**: 限定的。

#### Haskell: optparse-applicative

Applicativeファンクタベースのパーサ。bpaf(Rust)の思想的源流。

- **サブコマンド**: `subparser`/`hsubparser`で対応。独立したサブパーサとして動作。
- **ヘルプ生成**: 自動生成。包括的なヘルプ画面。
- **boolフラグ**: `switch`で定義。`--no-xxx`は手動実装。
- **`--`セパレータ**: 対応。
- **環境変数**: 直接的なサポートは限定的。
- **completion生成**: **bash/zsh/fish対応**。`--bash-completion-script`等の隠しオプションで自動拡張。
- **型安全性**: Haskellの型システムで最高レベルの型安全。
- **APIスタイル**: applicative / combinator。

**強み**: 型安全性の極致、合成的な設計、自動prefix disambiguation。
**弱み**: Haskellの学習コスト、環境変数サポートが弱い。

#### Elixir: OptionParser

Elixir標準ライブラリのシンプルなパーサ。

- **サブコマンド**: **未サポート**。アプリケーション側で実装。
- **ヘルプ生成**: **未サポート**。手動記述。
- **boolフラグ**: `--no-xxx`による反転を**ネイティブサポート**。
- **`--`セパレータ**: 対応。`parse_head/2`で`--`前後を分離。
- **環境変数**: **未サポート**。
- **completion生成**: **未サポート**。
- **型安全性**: `:string`、`:boolean`、`:integer`、`:float`、`:count`の型指定。
- **制約**: スイッチにアンダースコア不可、引数は0または1個のみ。
- **APIスタイル**: functional / imperative。

**強み**: `--no-xxx`ネイティブ。
**弱み**: 機能が最小限。サブコマンド・ヘルプ・補完すべてなし。

---

## 3. 機能比較マトリクス

凡例: `+++` = 最高 / `++` = 良好 / `+` = 基本対応 / `-` = 未対応 / `~` = 手動/外部

### Rust

| 機能 | clap | argh | pico-args | lexopt | bpaf |
|------|------|------|-----------|--------|------|
| サブコマンドネスト | +++無制限 | ++無制限 | - | ~手動 | +++無制限 |
| ヘルプセクション分け | ++heading | + | - | - | ++group |
| ロング/ショート | +++両方 | ++両方 | ++両方 | ++両方 | +++両方 |
| `--no-xxx` | ~手動 | - | - | ~手動 | ~手動 |
| `--`セパレータ | +++ | ++ | ++ | +++ | ++ |
| 引数位置自由 | +++ | ++ | ++ | +++ | +++ |
| 環境変数 | +++env | - | - | - | +++env |
| completion生成 | +++5シェル | - | - | - | +++4シェル |
| 型安全性 | +++derive | ++derive | +FromStr | +OsStr | +++applicative |
| バリデーション | +++ | + | + | ~手動 | ++ |
| エラーメッセージ | +++suggest | + | + | - | ++ |
| APIスタイル | derive+builder | derive | imperative | imperative | compose+derive |

### Go

| 機能 | cobra+pflag | urfave/cli v3 | kong | ff |
|------|-------------|---------------|------|-----|
| サブコマンドネスト | +++無制限 | ++ネスト | +++無制限 | ++ネスト |
| ヘルプセクション分け | ++template | ++category | ++group | + |
| ロング/ショート | +++両方 | ++両方 | ++short tag | ++Go flag |
| `--no-xxx` | - | +++BoolInverse | +++negatable | - |
| `--`セパレータ | +++ | ++ | ++ | ++ |
| 引数位置自由 | +++ | ++ | ++ | ++ |
| 環境変数 | ~viper | +++Sources | +++env tag | +++native |
| completion生成 | +++4シェル | +bash | ++external | - |
| 型安全性 | +pflag | +typed flag | +++struct | +Go flag |
| バリデーション | ++Args | ++ | ++enum/xor | + |
| エラーメッセージ | +++suggest | ++ | ++ | + |
| APIスタイル | imperative | declarative | struct tag | flags-first |

### Python

| 機能 | click | typer | argparse | fire |
|------|-------|-------|----------|------|
| サブコマンドネスト | +++無制限 | +++無制限 | +不安定 | ++auto |
| ヘルプセクション分け | ++ | ++ | + | + |
| ロング/ショート | +++両方 | +++両方 | ++両方 | ~auto |
| `--no-xxx` | +++native | +++auto | ~手動 | +--noflag |
| `--`セパレータ | ++ | ++ | ++ | ++ |
| 引数位置自由 | +++intersp | +++intersp | -制約あり | ++ |
| 環境変数 | +++envvar | +++envvar | ~手動 | - |
| completion生成 | ++3シェル | +++4シェル | ~argcomplete | + |
| 型安全性 | +runtime | ++type hint | +runtime | +runtime |
| バリデーション | ++Choice/cb | +++Annotated | ++type/choice | +auto |
| エラーメッセージ | ++ | ++ | + | + |
| APIスタイル | decorator | type hint | builder | magic |

### Node.js / TypeScript

| 機能 | commander | yargs | gunshi | clipanion | citty | oclif |
|------|-----------|-------|--------|-----------|-------|-------|
| サブコマンドネスト | +++無制限 | ++ネスト | ++lazy | +++FSM | ++基本 | +++colon |
| ヘルプセクション分け | ++ | ++group | +++i18n | ++ | + | ++ |
| ロング/ショート | +++両方 | +++両方 | ++両方 | +++両方 | ++両方 | +++両方 |
| `--no-xxx` | +++auto | +++native | ? | +++native | ? | ~allowNo |
| `--`セパレータ | +++ | +++ | ++ | +++proxy | ++ | ++ |
| 引数位置自由 | ++ | ++ | ++ | +++ | ++ | ++ |
| 環境変数 | +++env | +++prefix | ~plugin | +++env | ? | ++env |
| completion生成 | - | ++bash/zsh | ++plugin | ~ | - | ++plugin |
| 型安全性 | +TS defs | +TS defs | +++TS param | +++TS class | ++defineCmd | ++TS class |
| バリデーション | ++choices | +++rich | ++ | +++Typanion | + | +++relations |
| エラーメッセージ | ++ | ++ | ++ | ++ | + | ++ |
| APIスタイル | builder | declarative | declarative | class-based | declarative | framework |

### その他の言語

| 機能 | Swift AP | zig-clap | yazap | cmdliner | Core.Cmd | cligen | optparse-app | OptionParser |
|------|----------|----------|-------|----------|----------|--------|-------------|--------------|
| サブコマンド | +++無制限 | ++対応 | ++ネスト | ++choice | ++対応 | ++multi | ++sub | - |
| ヘルプ生成 | +++ | ++ | ++ | +++man | ++ | +++auto | +++ | - |
| `--no-xxx` | +++3種 | - | - | ~手動 | ~ | ~ | ~手動 | +++native |
| `--`セパレータ | ++ | ++ | ++ | +++ | ++ | ++ | ++ | ++ |
| 環境変数 | - | ? | ? | ++env | ? | ++merge | ~ | - |
| completion | +++3シェル | ? | ? | ++bash/zsh | ++bash | +compat | +++3シェル | - |
| 型安全性 | +++ | ++ | ++ | ++ | ++ | ++auto | +++ | + |
| APIスタイル | prop.wrap | decl | builder | combinator | applicative | magic | applicative | functional |

---

## 4. ユーザー好みとの適合度ランキング

評価基準（各10点満点、合計100点）:
1. サブコマンドネスト（無制限）: 10
2. 引数なし→`--help`表示: 10
3. ヘルプのセクション分け（サブコマンド/オプション/グローバル/環境変数）: 10
4. ロングオプション基本、ショートは明示追加: 10
5. `--no-xxx` boolフラグ反転: 10
6. オプション位置自由 + `--`セパレータ: 10
7. completion出力機能: 10
8. サブコマンドごとのオプション + グローバルオプション共存: 10
9. 環境変数連携 + ヘルプ表示: 10
10. 型安全性・バリデーション: 10

### Tier 1: 非常に高い適合度 (80+)

| 順位 | パーサ | 言語 | スコア | 備考 |
|------|--------|------|--------|------|
| 1 | **kong** | Go | 92 | struct tagで完結。`--no-xxx`、環境変数、グルーピング、型安全すべて対応。補完は外部だが対応可能。 |
| 2 | **clap** | Rust | 88 | 最も機能が豊富。`--no-xxx`が自動でない点で-2、しかし他はほぼ満点。 |
| 3 | **typer** | Python | 87 | 型ヒントから自動推論で`--no-xxx`自動、補完4シェル、環境変数対応。Pythonの制約のみ。 |
| 4 | **bpaf** | Rust | 86 | Applicative合成で表現力最高。環境変数・補完対応。`--no-xxx`は手動合成。 |
| 5 | **click** | Python | 85 | `--no-xxx`ネイティブ、環境変数、補完。型ヒントではない点で-2。 |
| 6 | **swift-argument-parser** | Swift | 84 | `FlagInversion`が最も美しい設計。環境変数未対応が唯一の弱点。 |
| 7 | **urfave/cli v3** | Go | 82 | `BoolWithInverseFlag`、環境変数Sources。補完がbash中心。 |

### Tier 2: 高い適合度 (65-79)

| 順位 | パーサ | 言語 | スコア | 備考 |
|------|--------|------|--------|------|
| 8 | **clipanion** | TS | 78 | FSMベース、`--no-xxx`、環境変数。補完が限定的。 |
| 9 | **yargs** | JS | 76 | `--no-xxx`、補完（動的）、環境変数。TypeScript型安全がやや弱い。 |
| 10 | **cobra** | Go | 75 | エコシステム最大だが`--no-xxx`未対応。Persistent Flagsでグローバルオプション。環境変数はviper依存。 |
| 11 | **commander.js** | JS | 72 | `--no-xxx`自動、環境変数。補完未搭載。 |
| 12 | **cmdliner** | OCaml | 70 | man page生成、環境変数、POSIX準拠。`--no-xxx`手動。 |
| 13 | **optparse-applicative** | Haskell | 68 | Applicative設計の元祖。補完3シェル。環境変数・`--no-xxx`が弱い。 |
| 14 | **oclif** | TS | 67 | プラグインアーキテクチャ。重量級だが機能豊富。`--no-xxx`が弱い。 |
| 15 | **cligen** | Nim | 65 | 最小コード。環境変数統合。補完は外部ツール互換。 |

### Tier 3: 中程度の適合度 (50-64)

| 順位 | パーサ | 言語 | スコア | 備考 |
|------|--------|------|--------|------|
| 16 | **gunshi** | JS | 62 | モダンだが発展途上。プラグインで拡張可能。 |
| 17 | **ff** | Go | 58 | flags-first哲学。環境変数は優秀だが補完なし。 |
| 18 | **Core.Command** | OCaml | 56 | Jane Street品質。エコシステム依存大。 |
| 19 | **argparse** | Python | 52 | 標準だが制約多い。ネスト不安定、引数位置制約。 |

### Tier 4: 低い適合度 (<50)

| 順位 | パーサ | 言語 | スコア | 備考 |
|------|--------|------|--------|------|
| 20 | **argh** | Rust | 40 | コードサイズ最適化特化。環境変数・補完・`--no-xxx`すべてなし。 |
| 21 | **fire** | Python | 38 | プロトタイプ向け。`--noflag`形式が非標準。 |
| 22 | **citty** | TS | 35 | 機能不足。補完なし。 |
| 23 | **yazap** | Zig | 33 | 発展途上。 |
| 24 | **zig-clap** | Zig | 32 | 発展途上。 |
| 25 | **OptionParser** | Elixir | 28 | `--no-xxx`のみ優秀。他は最小限。 |
| 26 | **docopt.nim** | Nim | 25 | ドキュメント駆動。制約が多い。 |
| 27 | **pico-args** | Rust | 20 | ミニマル特化。CLIフレームワークではない。 |
| 28 | **lexopt** | Rust | 15 | レキサー。フレームワークの基盤部品。 |

---

## 5. 発見・アイデア

ユーザーが考えていなかった可能性のある良い設計パターンを以下にまとめる。

### 5.1 Swift ArgumentParserの`FlagInversion`3パターン

```
--render / --no-render        (prefixedNo)
--enable-cache / --disable-cache  (prefixedEnableDisable)
```

さらにOptional Boolで`nil`/`true`/`false`の3状態を表現できる。これにより「ユーザーが明示的に指定したか」を区別可能。MoonBitで自作する際、この3パターンを型レベルで提供することは強力。

### 5.2 Clipanionの有限状態機械(FSM)ベースコマンド解決

コマンドツリーをFSMにコンパイルすることで、入力文字列を高速に解決する。これにより:
- コマンドの曖昧さを静的に検出
- `--`なしの透過的プロキシ（Yarnの`yarn add react`のように、`add`がサブコマンドかパッケージ名かをFSMで解決）

### 5.3 kongの`xor`/`and`タグによるフラグ間制約

```go
type CLI struct {
    JSON bool `xor:"output"`
    YAML bool `xor:"output"`
    Text bool `xor:"output"`
}
```

排他的オプション（`--json | --yaml | --text`）や依存オプション（`--username`と`--password`は同時指定必須）を宣言的に定義可能。oclif も `exactlyOne`、`dependsOn`等で類似機能を提供。

### 5.4 bpafのApplicative合成の利点

Applicativeは以下を保証する:
- パーサの定義順序と入力順序が独立（引数位置の自由度が構造的に保証される）
- すべてのパーサの構造が事前に分かるため、ヘルプと補完を自動生成可能
- monadicと異なり、先の引数の値によって後のパーサが変わることがないため、静的解析が可能

### 5.5 cligenの「あいまいプレフィックスマッチ」

```
--dry-run も --dry も --d も（一意であれば）受け付ける
```

補完がなくても長いオプション名を短く入力可能。加えてスタイル非感知（`--dryRun` = `--dry-run` = `--dry_run`）。

### 5.6 cobraの「Persistent Flags」パターン

親コマンドで定義したフラグが全ての子・孫コマンドに継承される。これはグローバルオプションの実装として非常に直感的。

### 5.7 yargsの環境変数プレフィックス自動バインド

```js
.env('MYAPP')  // MYAPP_VERBOSE -> --verbose に自動マッピング
```

個別に`env:"VAR"`を書かなくても、命名規約で環境変数を一括バインド。

### 5.8 oclif/Clipanionのフラグ間関係定義

```
dependsOn: ['username']  // --password は --username がある時のみ有効
exclusive: ['json']       // --yaml と --json は排他的
exactlyOne: ['json', 'yaml', 'text']  // このうち1つだけ必須
```

### 5.9 gunshiのi18n対応ヘルプ

CLIのヘルプメッセージとバリデーションエラーを多言語化する仕組み。グローバルツールには有用。

### 5.10 Clipanionの`--`なし透過的プロキシ

通常は`--`の後に渡す引数を、`--`なしで透過的に下位コマンドに渡せる。ラッパーCLIの実装に便利。

---

## 6. フルスクラッチ設計への示唆（MoonBitで自作する際に取り入れるべき要素）

### 6.1 設計原則

1. **宣言的API**: MoonBitのstruct/enumから`derive`相当のマクロまたはコード生成でCLIを定義。kong(Go)やclap derive(Rust)のアプローチ。
2. **Applicative合成**: bpaf/optparse-applicativeの合成パターン。パーサを小さな部品から合成し、引数順序の自由度とヘルプ・補完の自動生成を構造的に保証。
3. **型安全**: パース結果は直接MoonBitの型にマッピング。`Result`型でエラーハンドリング。

### 6.2 必須機能

| 機能 | 推奨設計 | 参考元 |
|------|----------|--------|
| サブコマンド | 無制限ネスト、enum/struct定義 | clap, kong |
| `--no-xxx`反転 | `FlagInversion`型で3パターン | Swift ArgumentParser |
| 環境変数 | `env`属性 + ヘルプ表示 + プレフィックス自動バインド | kong + yargs |
| completion生成 | bash/zsh/fish対応、動的補完 | clap_complete, cobra |
| ヘルプセクション分け | サブコマンド / ローカルオプション / グローバルオプション / 環境変数の4セクション | カスタム設計 |
| グローバルオプション | Persistent Flags相当、親から子への継承 | cobra |
| `--`セパレータ | `trailing_var_arg`相当 | clap |
| フラグ間制約 | `xor`(排他)、`and`(依存)、`exactly_one` | kong, oclif |
| 引数なし→`--help` | デフォルト挙動 | カスタム設計 |
| エラーメッセージ | サジェスト(did you mean?)、カラー出力 | cobra, clap |

### 6.3 差別化ポイント（既存にない設計）

1. **環境変数のヘルプ統合セクション**: 多くのパーサは環境変数をオプションの説明に埋め込むが、専用セクション「ENVIRONMENT VARIABLES」として一覧表示するパーサは少ない。
2. **`FlagInversion`の拡張**: Swift APの3パターンに加え、`--with-xxx`/`--without-xxx`パターンも追加。
3. **グローバルオプションの明示的セクション**: ヘルプ出力で「Global Options」セクションを自動分離。
4. **Applicative + derive ハイブリッド**: bpafのように合成APIとderiveマクロの両方を提供。
5. **コンパイル時FSM生成**: Clipanionのように、コマンドツリーをコンパイル時にFSMに変換し、実行時のパースを高速化。
6. **プレフィックスマッチ**: cligenのあいまいマッチを型安全に実装。一意でない場合はコンパイルエラー。
7. **i18n対応ヘルプ**: gunshiのように多言語対応をオプションで提供。

### 6.4 理想的な`--help`出力イメージ

```
myapp 1.0.0 - Description of the application

Usage: myapp [OPTIONS] <COMMAND>

Commands:
  serve     Start the server
  deploy    Deploy to production
  config    Manage configuration

Options:
  --verbose          Enable verbose output
  --format <FORMAT>  Output format [possible: json, yaml, text] [default: json]

Global Options:
  --config <PATH>    Configuration file path [env: MYAPP_CONFIG]
  --no-color         Disable colored output
  --help             Show this help message

Environment Variables:
  MYAPP_CONFIG       Configuration file path (overridden by --config)
  MYAPP_LOG_LEVEL    Log level [possible: debug, info, warn, error]
  MYAPP_NO_COLOR     Disable colored output (overridden by --no-color)
```

### 6.5 実装優先度

1. **Phase 1**: オプション定義（long/short/env）、型安全パース、`--help`生成
2. **Phase 2**: サブコマンド（無制限ネスト）、グローバルオプション、`--no-xxx`反転
3. **Phase 3**: completion生成（bash/zsh/fish）、フラグ間制約
4. **Phase 4**: FSM最適化、i18n、プレフィックスマッチ

---

## 参考リンク

### Rust
- [clap - GitHub](https://github.com/clap-rs/clap)
- [argh - GitHub](https://github.com/google/argh)
- [pico-args - GitHub](https://github.com/RazrFalcon/pico-args)
- [lexopt - GitHub](https://github.com/blyxxyz/lexopt)
- [bpaf - GitHub](https://github.com/pacak/bpaf)

### Go
- [cobra - GitHub](https://github.com/spf13/cobra)
- [urfave/cli - GitHub](https://github.com/urfave/cli)
- [kong - GitHub](https://github.com/alecthomas/kong)
- [ff - GitHub](https://github.com/peterbourgon/ff)

### Python
- [click - Documentation](https://click.palletsprojects.com/)
- [typer - Documentation](https://typer.tiangolo.com/)
- [argparse - Documentation](https://docs.python.org/3/library/argparse.html)
- [fire - GitHub](https://github.com/google/python-fire)

### Node.js / TypeScript
- [commander.js - GitHub](https://github.com/tj/commander.js)
- [yargs - Documentation](https://yargs.js.org/)
- [gunshi - Documentation](https://gunshi.dev/)
- [clipanion - GitHub](https://github.com/arcanis/clipanion)
- [citty - GitHub](https://github.com/unjs/citty)
- [oclif - Documentation](https://oclif.io/)

### Swift
- [swift-argument-parser - GitHub](https://github.com/apple/swift-argument-parser)

### Zig
- [zig-clap - GitHub](https://github.com/Hejsil/zig-clap)
- [yazap - GitHub](https://github.com/prajwalch/yazap)

### OCaml
- [cmdliner - GitHub](https://github.com/dbuenzli/cmdliner)
- [Core.Command - Jane Street](https://ocaml.janestreet.com/ocaml-core/v0.12/doc/)

### Haskell
- [optparse-applicative - Hackage](https://hackage.haskell.org/package/optparse-applicative)

### Nim
- [cligen - GitHub](https://github.com/c-blake/cligen)
- [docopt.nim - GitHub](https://github.com/docopt/docopt.nim)

### Elixir
- [OptionParser - Documentation](https://hexdocs.pm/elixir/OptionParser.html)
