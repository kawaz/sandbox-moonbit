# CLI引数パーサ ヘルプ出力フォーマット比較調査

調査日: 2026-03-02

---

## 総括

### ベストプラクティスの抽出

各パーサを横断して確認された共通的なベストプラクティスは以下の通り。

1. **セクション分割**: Usage / Commands (or Subcommands) / Arguments / Options がほぼ全パーサで採用。セクションヘッダは視覚的区別が重要
2. **Usage 行**: 常に最上部。コマンドパスと引数の概要を1行で示す
3. **デフォルト値表示**: 大半のパーサがオプションの横に `[default: 8080]` 形式で表示
4. **隠しオプション**: 通常ヘルプから除外し、`--help-all` や `--help-hidden` で別途表示する二段階方式が最善
5. **ターミナル幅対応**: 自動検出 + フォールバック幅（80 or 120）が標準
6. **カスタムセクション**: Examples / Environment Variables を独立セクションとして追加できる機構が重要
7. **補完連携**: ヘルプ定義と補完定義が単一ソースから生成される設計が理想

### パーサ別 強み・弱み一覧

| パーサ | 言語 | 強み | 弱み |
|--------|------|------|------|
| clap | Rust | テンプレート方式で完全カスタマイズ可。カスタムヘッダ/セクション/環境変数表示。NO_COLOR対応 | テンプレート構文がやや独自。`--no-xxx` 未対応 |
| bpaf | Rust | header/footer、group_help でセクション追加。markdown/manpage 生成 | セクション構成が固定的。カスタムセクション追加の自由度が低い |
| Swift ArgumentParser | Swift | 最も洗練されたデフォルト出力。`--help-hidden` 二段階方式。カスタムセクションタイトル | Go/Rust/JS エコシステムと隔離。カラー出力は控えめ |
| cobra | Go | Go テンプレートで完全カスタマイズ。Flags/Global Flags の自動分離。コマンドグループ対応 | テンプレートが冗長。環境変数セクション非対応 |
| Clipanion | TS | 装飾的なセクションヘッダ（`━━━`）。カテゴリ分類。Markdown 記法対応 | カスタマイズポイントが少ない。ヘルプ構成の変更が困難 |
| click | Python | シンプルで読みやすい。epilog。rich-click で高度なスタイリング。`--no-xxx` 対応 | デフォルトではセクション分けが最小限。環境変数セクション手動 |
| yargs | Node.js | group() でセクション自由配置。epilog/example/usage。deprecated 表示 | デフォルトのフォーマットが粗い。カラー非対応 |
| oclif | Node.js | helpGroup でフラググループ化。GLOBAL FLAGS 自動分離。フレームワークとして統合的 | 環境変数ヘルプ非表示（要望中）。カスタマイズは Help クラス継承が必要 |

---

## 統一サンプル仕様

以下の仕様で各パーサのヘルプ出力例を作成する。

- アプリ名: `myapp`
- 説明: "A sample application"
- サブコマンド: `serve`, `config`
- グローバルオプション: `--verbose` (flag), `--config <path>` (ファイルパス)
- `serve` のオプション: `--port <number>` (デフォルト 8080), `--host <addr>`, `--ssl` (flag), `--ssl-cert <path>` (requires --ssl)
- `config` のサブコマンド: `config get`, `config set`

---

## 1. clap (Rust)

### 1.1 デフォルトヘルプ出力サンプル

**トップレベル (`myapp --help`)**:
```
A sample application

Usage: myapp [OPTIONS] <COMMAND>

Commands:
  serve   Start the server
  config  Manage configuration
  help    Print this message or the help of the given subcommand(s)

Options:
      --verbose          Enable verbose output
      --config <PATH>    Path to config file
  -h, --help             Print help
  -V, --version          Print version
```

**サブコマンド (`myapp serve --help`)**:
```
Start the server

Usage: myapp serve [OPTIONS]

Options:
      --port <PORT>          Port to listen on [default: 8080]
      --host <ADDR>          Host address to bind
      --ssl                  Enable SSL
      --ssl-cert <PATH>      Path to SSL certificate (requires --ssl)
  -h, --help                 Print help
```

**ネストサブコマンド (`myapp config --help`)**:
```
Manage configuration

Usage: myapp config <COMMAND>

Commands:
  get   Get a configuration value
  set   Set a configuration value
  help  Print this message or the help of the given subcommand(s)

Options:
  -h, --help  Print help
```

### 1.2 セクション構成

デフォルトテンプレート:
```
{before-help}{about-with-newline}
{usage-heading} {usage}

{all-args}{after-help}
```

`{all-args}` は内部で以下の順序に展開される:
1. **説明** (about)
2. **Usage** 行
3. **Commands** (サブコマンド一覧) — `subcommand_help_heading()` でヘッダ名変更可
4. **Arguments** (位置引数)
5. **Options** (オプション・フラグ) — `help_heading()` / `next_help_heading()` でグループ分け可

グローバルオプションとローカルオプションは**デフォルトでは同一の Options セクション**に混在する。分離するには `help_heading("Global Options")` を明示的に指定する必要がある。

環境変数は `env` feature 有効時に各オプション説明の横に `[env: VAR_NAME=]` 形式で表示されるが、独立セクションとしては出力されない。

### 1.3 カスタマイズ機能

- **テンプレート方式**: `help_template()` で完全にレイアウト変更可。テンプレート変数: `{name}`, `{version}`, `{author}`, `{about}`, `{usage}`, `{all-args}`, `{options}`, `{positionals}`, `{subcommands}`, `{before-help}`, `{after-help}`, `{tab}`
- **カスタムセクション**: `next_help_heading("Environment Variables")` でオプションを任意のセクションに分類
- **before/after help**: `before_help()` / `after_help()` でヘルプ前後にテキスト追加（Examples 等）
- **ヘルプハンドラ上書き**: `override_help()` で完全にカスタムテキストに置換
- **表示順**: `display_order()` でオプション/サブコマンドの表示順制御

### 1.4 表示制御

- **隠しオプション/サブコマンド**: `hide(true)` で非表示。`--help-all` 的な機能は組み込みなし（カスタム実装が必要）
- **deprecated**: `deprecated` feature flag でサポート。オプトインで警告表示
- **カラー/ANSI**: anstream ベース。`NO_COLOR` 環境変数、`CLICOLOR`、`CLICOLOR_FORCE` 対応。自動 TTY 検出
- **ターミナル幅**: `wrap_help` feature で自動検出。デフォルトフォールバックは 120 文字

### 1.5 特徴的な機能

- **排他グループ**: `ArgGroup` で `--json | --csv` のような排他を定義。ヘルプに `[required]` 表示
- **required 表現**: `<REQUIRED>` (山括弧)、`[OPTIONAL]` (角括弧)
- **デフォルト値**: `[default: 8080]` 形式で表示
- **環境変数**: `[env: PORT=]` 形式で各オプションに表示
- **補完連携**: `clap_complete` でヘルプ定義から補完スクリプト生成 (bash/zsh/fish/PowerShell/elvish)
- **エイリアス**: `visible_alias()` / `visible_short_alias()` でヘルプに表示されるエイリアスを定義

### 1.6 階層表示

- トップレベル: Commands + (グローバル) Options
- サブコマンド: そのコマンドの Options のみ。グローバルオプションは `help_heading` を使わない限り**表示されない**
- ネストサブコマンド: 親のオプションは表示されない

---

## 2. bpaf (Rust)

### 2.1 デフォルトヘルプ出力サンプル

**トップレベル (`myapp --help`)**:
```
A sample application

Usage: myapp [--verbose] [--config=PATH] COMMAND ...

Available options:
        --verbose    Enable verbose output
        --config=PATH  Path to config file
    -h, --help       Prints help information

Available commands:
    serve            Start the server
    config           Manage configuration
```

**サブコマンド (`myapp serve --help`)**:
```
Start the server

Usage: myapp serve [--port=PORT] [--host=ADDR] [--ssl] [--ssl-cert=PATH]

Available options:
        --port=PORT       Port to listen on (default: 8080)
        --host=ADDR       Host address to bind
        --ssl             Enable SSL
        --ssl-cert=PATH   Path to SSL certificate
    -h, --help            Prints help information
```

### 2.2 セクション構成

1. **説明** (descr) — 1-2 行の概要
2. **Usage** 行 — 自動生成またはカスタム
3. **ヘッダ** (header) — Usage とオプション一覧の間
4. **Available positional items** — 位置引数（ヘルプテキストがある場合のみ表示）
5. **Available options** — 名前付きオプション・フラグ
6. **Available commands** — サブコマンド一覧
7. **フッタ** (footer) — 末尾

### 2.3 カスタマイズ機能

- **ヘッダ/フッタ**: `header()` / `footer()` メソッドで Usage 後・末尾にテキスト追加
- **グループヘルプ**: `group_help()` で複数パーサに共通の説明を追加（独立セクション風）
- **カスタム Usage**: `custom_usage()` / `with_usage()` で Usage 行をオーバーライド
- **テンプレート方式**: なし（構造は固定）
- **完全カスタム**: なし（フォーマットは内部管理）
- **多形式出力**: `render_markdown()`, `render_html()`, `render_manpage()` で markdown/HTML/manpage 生成

### 2.4 表示制御

- **隠しオプション**: `hide()` で非表示、`hide_usage()` で Usage 行からのみ除外
- **deprecated**: 組み込みサポートなし
- **カラー**: `bright-color` / `dull-color` feature フラグで制御
- **ターミナル幅**: デフォルト最大幅 100 文字。設定可能

### 2.5 特徴的な機能

- **env 連携**: `env("VAR")` で環境変数フォールバック。ヘルプに環境変数名を表示可能
- **フォールバック表示**: `display_fallback()` / `debug_fallback()` でデフォルト値をヘルプに表示
- **補完連携**: `autocomplete` feature でヘルプ定義から補完生成 (bash/zsh/fish/elvish)
- **多形式ドキュメント生成**: manpage, markdown, HTML

### 2.6 階層表示

- トップレベル: Available options + Available commands
- サブコマンド: そのコマンドの Available options のみ
- グローバルオプションはサブコマンドヘルプに**表示されない**（bpaf はグローバル/ローカルの区分を持たない。構造で表現する）

---

## 3. Swift Argument Parser

### 3.1 デフォルトヘルプ出力サンプル

**トップレベル (`myapp --help`)**:
```
OVERVIEW: A sample application

USAGE: myapp <subcommand>

OPTIONS:
  --verbose               Enable verbose output
  --config <path>         Path to config file
  -h, --help              Show help information.

SUBCOMMANDS:
  serve                   Start the server
  config                  Manage configuration

  See 'myapp help <subcommand>' for detailed help.
```

**サブコマンド (`myapp serve --help`)**:
```
OVERVIEW: Start the server

USAGE: myapp serve [--port <port>] [--host <addr>] [--ssl] [--ssl-cert <path>]

OPTIONS:
  --port <port>           Port to listen on (default: 8080)
  --host <addr>           Host address to bind
  --ssl                   Enable SSL
  --ssl-cert <path>       Path to SSL certificate (requires --ssl)
  -h, --help              Show help information.
```

**ネストサブコマンド (`myapp config --help`)**:
```
OVERVIEW: Manage configuration

USAGE: myapp config <subcommand>

OPTIONS:
  -h, --help              Show help information.

SUBCOMMANDS:
  get                     Get a configuration value
  set                     Set a configuration value

  See 'myapp config help <subcommand>' for detailed help.
```

### 3.2 セクション構成

`HelpGenerator.generateSections()` による順序:
1. **OVERVIEW** — abstract + discussion
2. **USAGE** — コマンド構文
3. **ARGUMENTS** — 位置引数
4. **カスタムタイトルセクション** — `@OptionGroup(title: "Build Options")` 等
5. **OPTIONS** — フラグ・オプション
6. **SUBCOMMANDS** — サブコマンド一覧
7. **グループ化サブコマンド** — `[GroupName] Subcommands` 形式

フォーマット定数:
- インデント: 2 スペース
- ラベル列幅: 26 文字

### 3.3 カスタマイズ機能

- **カスタムセクション**: `@OptionGroup(title: "Server Options")` でオプションをグループ化し独立セクション表示
- **ヘルプ名制御**: `CommandConfiguration(helpNames: .shortAndLong)` でヘルプフラグ名変更
- **テンプレート方式**: なし（構造は固定だがセクション追加は柔軟）
- **完全カスタム**: `HelpCommand` をオーバーライドして独自ヘルプ生成可能
- **多形式出力**: terminal text, JSON dump, manpage, DocC reference

### 3.4 表示制御

- **隠しオプション**: `visibility: .hidden` で通常ヘルプから除外、`--help-hidden` で表示。`visibility: .private` で完全非表示
- **deprecated**: `@available(*, deprecated)` で廃止マーク可
- **カラー**: 控えめ（基本的にプレーンテキスト）
- **ターミナル幅**: 自動検出し折り返し対応

### 3.5 特徴的な機能

- **二段階ヘルプ**: `--help` (通常) / `--help-hidden` (すべて表示) の二段階方式が組み込み
- **FlagInversion**: `@Flag(inversion: .prefixedNo)` で `--ssl` / `--no-ssl` を自動生成。ヘルプにも両方表示
- **デフォルト値**: `(default: 8080)` 形式で表示
- **補完連携**: ヘルプ定義から bash/zsh/fish 補完生成
- **OptionGroup**: 関連オプションを構造体にまとめて独自セクションタイトルで表示

### 3.6 階層表示

- トップレベル: OPTIONS (グローバル) + SUBCOMMANDS
- サブコマンド: そのコマンドの OPTIONS のみ。親のグローバルオプションは**表示されない**
- ネストサブコマンド: 同様に自身の OPTIONS + SUBCOMMANDS のみ
- フッタに `See 'myapp help <subcommand>'` メッセージ

---

## 4. cobra (Go)

### 4.1 デフォルトヘルプ出力サンプル

**トップレベル (`myapp --help`)**:
```
A sample application

Usage:
  myapp [command]

Available Commands:
  serve       Start the server
  config      Manage configuration
  help        Help about any command

Flags:
      --verbose        Enable verbose output
      --config string  Path to config file
  -h, --help           help for myapp

Global Flags:
  (なし - トップレベルなので Flags に統合)

Use "myapp [command] --help" for more information about a command.
```

**サブコマンド (`myapp serve --help`)**:
```
Start the server

Usage:
  myapp serve [flags]

Flags:
      --port int       Port to listen on (default 8080)
      --host string    Host address to bind
      --ssl            Enable SSL
      --ssl-cert string  Path to SSL certificate
  -h, --help           help for serve

Global Flags:
      --verbose        Enable verbose output
      --config string  Path to config file
```

**ネストサブコマンド (`myapp config --help`)**:
```
Manage configuration

Usage:
  myapp config [command]

Available Commands:
  get         Get a configuration value
  set         Set a configuration value

Flags:
  -h, --help  help for config

Global Flags:
      --verbose        Enable verbose output
      --config string  Path to config file

Use "myapp config [command] --help" for more information about a command.
```

### 4.2 セクション構成

デフォルト Usage テンプレートの順序:
1. **Usage** — `myapp [command]` or `myapp serve [flags]`
2. **Aliases** — エイリアスがある場合のみ
3. **Examples** — `Example` フィールドが設定されている場合のみ
4. **Available Commands** — サブコマンド一覧。`AddGroup()` でグループ化可
5. **Flags** — そのコマンドのローカルフラグ
6. **Global Flags** — 親から継承されたフラグ（`PersistentFlags`）
7. **Additional help topics** — ヘルプトピック
8. **フッタ** — `Use "myapp [command] --help" for more information about a command.`

**最大の特徴**: Flags と Global Flags が**自動分離**される。`PersistentFlags()` で定義したフラグは子コマンドで自動的に Global Flags セクションに表示される。

### 4.3 カスタマイズ機能

- **Go テンプレート方式**: `SetHelpTemplate()` / `SetUsageTemplate()` で完全カスタマイズ。Go の `text/template` 構文
- **テンプレート変数**: `.UseLine`, `.CommandPath`, `.Short`, `.Long`, `.Example`, `.HasAvailableSubCommands`, `.Commands`, `.LocalFlags.FlagUsages`, `.InheritedFlags.FlagUsages`, `.Groups` 等
- **コマンドグループ**: `AddGroup(&cobra.Group{ID: "manage", Title: "Management Commands"})` でサブコマンドをグループ化
- **カスタムヘルプ関数**: `SetHelpFunc()` で完全に独自のヘルプ出力関数を設定可
- **カスタムセクション**: テンプレートに任意のセクションを追加可能

### 4.4 表示制御

- **隠しコマンド/フラグ**: `Hidden: true` で非表示。`IsAvailableCommand()` でフィルタ
- **deprecated**: `Deprecated` フィールドに文字列を設定。ヘルプには表示されず、使用時に警告
- **カラー**: デフォルトでカラーなし。glamour 等のライブラリと組み合わせてリッチ表示可
- **ターミナル幅**: テンプレートベースのため自動折り返しはなし（手動対応）

### 4.5 特徴的な機能

- **Flags / Global Flags 自動分離**: Persistent flags は自動的に Global Flags セクションに分離表示。**これは cobra の最大の強み**
- **エイリアス**: `Aliases` フィールドでサブコマンドのエイリアスを定義。ヘルプに Aliases セクション表示
- **補完連携**: 組み込みの補完生成 (bash/zsh/fish/PowerShell)
- **man page 生成**: cobra/doc パッケージで manpage 生成
- **環境変数**: 組み込みサポートなし（viper との連携で実現するが、ヘルプには表示されない）

### 4.6 階層表示

- トップレベル: Available Commands + Flags (全フラグが Flags に表示)
- サブコマンド: Flags (ローカル) + **Global Flags (親の Persistent)** — 自動分離
- ネストサブコマンド: Available Commands + Flags + Global Flags
- フッタに `Use "myapp config [command] --help"` メッセージ

---

## 5. Clipanion (TypeScript)

### 5.1 デフォルトヘルプ出力サンプル

**トップレベル (`myapp --help`)**:
```
myapp - A sample application

━━━ General commands ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  myapp serve                       Start the server
  myapp config get                  Get a configuration value
  myapp config set                  Set a configuration value

You can also print more details about any of these commands by calling them
with the `-h,--help` flag right after the command name.
```

**サブコマンド (`myapp serve -h`)**:
```
━━━ Usage ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

$ myapp serve [--port #0] [--host #0] [--ssl] [--ssl-cert #0]

━━━ Details ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Start the HTTP server with the specified configuration.

The **--ssl** flag enables HTTPS mode. When using SSL, you must also
provide a certificate path via **--ssl-cert**.

━━━ Examples ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Start on default port
  $ myapp serve

Start on custom port with SSL
  $ myapp serve --port 3000 --ssl --ssl-cert ./cert.pem
```

### 5.2 セクション構成

**全体ヘルプ**:
1. **ヘッダ** — アプリ名 + バージョン
2. **カテゴリ別コマンド一覧** — `category` 指定でグループ化。未指定は "General commands"
3. **フッタ** — `-h,--help` 案内

**コマンドヘルプ**:
1. **Usage** — コマンド構文（`━━━` 装飾付きヘッダ）
2. **Options** — オプション一覧（定義がある場合）
3. **Details** — 長い説明文（Markdown 対応）
4. **Examples** — 説明 + コマンド例のペア

### 5.3 カスタマイズ機能

- **Usage 定義**: `static usage = Command.Usage({ category, description, details, examples })` で宣言的定義
- **カテゴリ分類**: `category` でコマンドをグループ化
- **Markdown 対応**: details に `**bold**` や `` `code` `` を使用可。自動改行・インデント
- **テンプレート方式**: なし
- **完全カスタム**: 困難（`Cli.usage()` の内部ロジックに依存）

### 5.4 表示制御

- **隠しコマンド**: description を設定しないことで全体ヘルプから除外
- **deprecated**: 組み込みサポートなし
- **カラー/ANSI**: Rich format (ANSI エスケープ) と Text format (プレーンテキスト) を自動切り替え。ヘッダにグラデーション装飾
- **ターミナル幅**: 80 文字幅でラップ（固定）

### 5.5 特徴的な機能

- **装飾的ヘッダ**: `━━━ Usage ━━━━━━━` 形式の視覚的に目立つセクション区切り
- **Markdown 記法**: 詳細説明でインライン Markdown が使える
- **FSM ベースのコマンド解決**: 有限状態機械でコマンドを解決。類似コマンドのサジェスト
- **補完連携**: 組み込みなし（外部ツール依存）
- **フラットなコマンド一覧**: ネストしたサブコマンドもトップレベルのヘルプに `myapp config get` のようにフルパスで表示

### 5.6 階層表示

- トップレベル: カテゴリ別のフルパスコマンド一覧（`myapp serve`, `myapp config get`, `myapp config set`）
- サブコマンド: Usage + Details + Examples（個別コマンドの詳細表示）
- グローバルオプションの概念が薄い（各コマンドが独立）

---

## 6. click (Python)

### 6.1 デフォルトヘルプ出力サンプル

**トップレベル (`myapp --help`)**:
```
Usage: myapp [OPTIONS] COMMAND [ARGS]...

  A sample application

Options:
  --verbose          Enable verbose output
  --config PATH      Path to config file
  --help             Show this message and exit.

Commands:
  serve   Start the server
  config  Manage configuration
```

**サブコマンド (`myapp serve --help`)**:
```
Usage: myapp serve [OPTIONS]

  Start the server

Options:
  --port INTEGER     Port to listen on  [default: 8080]
  --host TEXT        Host address to bind
  --ssl              Enable SSL
  --ssl-cert PATH    Path to SSL certificate
  --help             Show this message and exit.
```

**ネストサブコマンド (`myapp config --help`)**:
```
Usage: myapp config [OPTIONS] COMMAND [ARGS]...

  Manage configuration

Options:
  --help  Show this message and exit.

Commands:
  get  Get a configuration value
  set  Set a configuration value
```

### 6.2 セクション構成

`format_help()` の内部順序:
1. **Usage** 行
2. **説明** — docstring から自動生成
3. **Options** — オプション一覧（`write_dl()` で定義リスト形式）
4. **Commands** — サブコマンド一覧（Group の場合のみ）
5. **Epilog** — 末尾テキスト

### 6.3 カスタマイズ機能

- **epilog**: `@click.command(epilog="...")` で末尾テキスト追加
- **HelpFormatter サブクラス**: `format_help()`, `format_usage()`, `write_dl()` 等をオーバーライド
- **rich-click**: `import rich_click as click` に置換するだけで Rich ベースの高度なスタイリング。100 以上のテーマ
- **Cloup**: Click 拡張ライブラリ。オプションのグループ化、カスタムセクション追加
- **テンプレート方式**: なし（メソッドオーバーライド方式）

### 6.4 表示制御

- **隠しオプション**: `hidden=True` で非表示
- **deprecated**: `deprecated=True` で廃止マーク
- **カラー**: ANSI エスケープコード対応。`NO_COLOR` 環境変数非対応（rich-click 使用時は対応）
- **ターミナル幅**: デフォルト最大 80 文字。`max_width` パラメータで変更可。自動検出あり
- **`--no-xxx`**: `--flag/--no-flag` 形式を組み込みサポート

### 6.5 特徴的な機能

- **`--flag/--no-flag`**: `click.option('--ssl/--no-ssl')` でブール反転フラグを簡単に定義
- **デフォルト値**: `[default: 8080]` 形式。`show_default=True` で有効化
- **環境変数**: `envvar="PORT"` で設定。`show_envvar=True` で表示
- **メタ変数**: `metavar="PORT"` でプレースホルダ名をカスタマイズ
- **テキストエスケープ**: `\b` で折り返し防止（コード例用）、`\f` で help テキスト切り捨て
- **補完連携**: `click-completion` / `click-autocomplete` パッケージで補完生成

### 6.6 階層表示

- トップレベル: Options (グローバル含む) + Commands
- サブコマンド: そのコマンドの Options のみ。**グローバルオプションは表示されない**
- ネストサブコマンド: 自身の Options + Commands

---

## 7. yargs (Node.js)

### 7.1 デフォルトヘルプ出力サンプル

**トップレベル (`myapp --help`)**:
```
myapp - A sample application

Usage: myapp <command> [options]

Commands:
  myapp serve   Start the server
  myapp config  Manage configuration

Options:
      --verbose  Enable verbose output                         [boolean]
      --config   Path to config file                            [string]
  -h, --help     Show help                                     [boolean]
  -v, --version  Show version number                           [boolean]

Examples:
  myapp serve --port 3000  Start server on port 3000

For more information, visit https://example.com
```

**サブコマンド (`myapp serve --help`)**:
```
myapp serve

Start the server

Options:
      --port      Port to listen on               [number] [default: 8080]
      --host      Host address to bind                            [string]
      --ssl       Enable SSL                                     [boolean]
      --ssl-cert  Path to SSL certificate                         [string]
  -h, --help      Show help                                      [boolean]
```

### 7.2 セクション構成

1. **Usage** 行 — `usage()` で設定
2. **Commands** — サブコマンド一覧
3. **Positionals** — 位置引数（ある場合）
4. **Options** — オプション一覧（`group()` でカスタムグループ化可）
5. **Examples** — `example()` で追加
6. **Epilog** — `epilog()` で末尾テキスト

### 7.3 カスタマイズ機能

- **group()**: `yargs.group(['port', 'host'], 'Server Options:')` でオプションをグループ化
- **usage()**: Usage 行のカスタマイズ。`$0` がスクリプト名に置換
- **example()**: 使用例の追加
- **epilog()**: 末尾メッセージ
- **scriptName()**: スクリプト名の変更
- **テンプレート方式**: なし
- **完全カスタム**: なし

### 7.4 表示制御

- **隠しオプション/コマンド**: `hidden: true` で非表示。`--show-hidden` オプションで表示可
- **deprecated**: `deprecated: true` で `[deprecated]` 表示。deprecated メッセージも設定可
- **カラー**: 組み込みカラーなし（プレーンテキスト）
- **ターミナル幅**: `wrap(yargs.terminalWidth())` で自動検出。デフォルトは `Math.min(80, windowWidth)`

### 7.5 特徴的な機能

- **型タグ表示**: `[boolean]`, `[number]`, `[string]`, `[array]` 等の型を右端に表示
- **デフォルト値**: `[default: 8080]` 形式で表示
- **required 表現**: `[required]` タグ
- **choices**: `[choices: "json", "csv", "yaml"]` で選択肢表示
- **deprecated 表示**: `[deprecated]` タグ。非推奨メッセージも設定可
- **`--show-hidden`**: 隠しオプションを表示する専用フラグ
- **coerce**: 値の変換関数
- **補完連携**: `completion()` で bash/zsh 補完スクリプト生成。カスタム補完関数サポート

### 7.6 階層表示

- トップレベル: Commands + Options (グローバル含む)
- サブコマンド: そのコマンドの Options のみ。グローバルオプションは**表示されない**（明示的にグループに追加しない限り）
- `group()` で手動構成すれば "Global Options" セクションを作成可能

---

## 8. oclif (Node.js)

### 8.1 デフォルトヘルプ出力サンプル

**トップレベル (`myapp --help`)**:
```
A sample application

VERSION
  myapp/1.0.0

USAGE
  $ myapp COMMAND

COMMANDS
  config  Manage configuration
  help    Display help for myapp
  serve   Start the server
```

**サブコマンド (`myapp serve --help`)**:
```
Start the server

USAGE
  $ myapp serve [--port <value>] [--host <value>] [--ssl] [--ssl-cert <value>]

FLAGS
  --host=<value>      Host address to bind
  --port=<value>      Port to listen on [default: 8080]
  --ssl               Enable SSL
  --ssl-cert=<value>  Path to SSL certificate

GLOBAL FLAGS
  --config=<value>  Path to config file
  --verbose         Enable verbose output

DESCRIPTION
  Start the server

EXAMPLES
  $ myapp serve --port 3000

  $ myapp serve --ssl --ssl-cert ./cert.pem
```

**ネストサブコマンド (`myapp config --help`)**:
```
Manage configuration

USAGE
  $ myapp config COMMAND

COMMANDS
  config get  Get a configuration value
  config set  Set a configuration value
```

### 8.2 セクション構成

`showCommandHelp` の順序:
1. **DESCRIPTION** or summary (短い説明)
2. **VERSION** — トップレベルのみ
3. **USAGE** — コマンド構文
4. **ARGUMENTS** — 位置引数
5. **FLAGS** — コマンドのローカルフラグ
6. **GLOBAL FLAGS** — グローバルフラグ（自動分離）
7. **DESCRIPTION** — 長い説明文
8. **EXAMPLES** — 使用例
9. **COMMANDS** — サブコマンド/トピック一覧

### 8.3 カスタマイズ機能

- **Help クラス継承**: `extends Help` で `formatCommand()`, `formatRoot()`, `formatCommands()`, `formatTopic()` をオーバーライド
- **helpGroup**: `Flags.string({ helpGroup: 'Server Options' })` でフラグをグループ化
- **static properties**: `summary`, `description`, `examples`, `usage`, `hidden` で宣言的定義
- **テンプレート方式**: なし（メソッドオーバーライド方式）
- **例のフォーマット**: `<%= config.bin %>` がバイナリ名に、`<%= command.id %>` がコマンド名に置換

### 8.4 表示制御

- **隠しコマンド/フラグ**: `hidden: true` で非表示
- **deprecated**: `deprecated: true` または `deprecated: { message, version }` でフラグ/コマンドの廃止マーク
- **deprecateAliases**: エイリアス使用時に非推奨警告
- **カラー**: ヘルプ出力のカラーカスタマイズ対応
- **ターミナル幅**: 自動検出対応

### 8.5 特徴的な機能

- **FLAGS / GLOBAL FLAGS 自動分離**: cobra と同様、グローバルフラグは自動的に GLOBAL FLAGS セクションに分離
- **helpGroup**: フラグを任意のグループに分類して独立セクション表示
- **env**: `Flags.string({ env: 'PORT' })` で環境変数フォールバック。**ただしヘルプには環境変数名が表示されない**（feature request 中）
- **トピック**: サブコマンドの上位概念としてトピックを定義し、コマンドのツリー構造を表現
- **補完連携**: プラグイン方式で補完生成（開発中）

### 8.6 階層表示

- トップレベル: COMMANDS のみ（FLAGS はルートには表示しないのがデフォルト）
- サブコマンド: FLAGS + GLOBAL FLAGS + DESCRIPTION + EXAMPLES
- ネストサブコマンド: COMMANDS 一覧
- **GLOBAL FLAGS がサブコマンドのヘルプに自動表示される**のは cobra と共通の強み

---

## 比較まとめ

### セクション構成比較

| セクション | clap | bpaf | Swift AP | cobra | Clipanion | click | yargs | oclif |
|------------|------|------|----------|-------|-----------|-------|-------|-------|
| Usage | o | o | o | o | o | o | o | o |
| Description | o | o | OVERVIEW | Long/Short | Details | docstring | - | DESCRIPTION |
| Arguments | o | o | ARGUMENTS | - | - | - | Positionals | ARGUMENTS |
| Options/Flags | Options | Available options | OPTIONS | Flags | (Usage内) | Options | Options | FLAGS |
| Global Options | 手動 | - | - | **自動** | - | - | 手動 | **自動** |
| Subcommands | Commands | Available commands | SUBCOMMANDS | Available Commands | コマンド一覧 | Commands | Commands | COMMANDS |
| Examples | before/after | footer | - | Examples | Examples | epilog | Examples | EXAMPLES |
| Env Variables | 各行内 | 各行内 | - | - | - | 各行内 | - | - |
| フッタ | after_help | footer | help案内 | help案内 | help案内 | epilog | epilog | - |

### Global Options の表示方式比較

| パーサ | グローバルオプションのサブコマンド表示 | 実装方式 |
|--------|---------------------------------------|----------|
| clap | 表示されない（手動で help_heading 設定が必要） | 明示的 |
| bpaf | 表示されない | 構造的に分離 |
| Swift AP | 表示されない | 構造的に分離 |
| cobra | **自動表示** (Global Flags セクション) | PersistentFlags |
| Clipanion | グローバルの概念が薄い | 各コマンド独立 |
| click | 表示されない | Context 経由 |
| yargs | 表示されない（group で手動可） | 手動 |
| oclif | **自動表示** (GLOBAL FLAGS セクション) | 自動継承 |

### カスタマイズ方式比較

| パーサ | テンプレート | メソッド上書き | セクション追加 | 完全カスタム |
|--------|-------------|---------------|---------------|-------------|
| clap | **独自テンプレート** | - | help_heading | override_help |
| bpaf | - | - | group_help | - |
| Swift AP | - | HelpCommand 上書き | @OptionGroup(title:) | o |
| cobra | **Go テンプレート** | SetHelpFunc | テンプレート内 | o |
| Clipanion | - | - | category | - |
| click | - | **HelpFormatter 継承** | Cloup で可能 | o |
| yargs | - | - | group() | - |
| oclif | - | **Help クラス継承** | helpGroup | o |

---

## 我々のパーサへの推奨事項

`cli-design-preferences.md` の好みと各パーサの調査結果を踏まえた推奨:

### 1. セクション構成

好み（サブコマンド一覧 -> オプション -> グローバルオプション -> 環境変数）を実現するため、以下の順序を推奨:

```
Description (1行の概要)

Usage: myapp <command> [options]

Commands:
  serve   Start the server
  config  Manage configuration

Options:
  --port <number>    Port to listen on  [default: 8080]
  --host <addr>      Host address to bind

Global Options:
  --verbose          Enable verbose output
  --config <path>    Path to config file

Environment Variables:
  MYAPP_VERBOSE      Same as --verbose
  MYAPP_CONFIG       Same as --config
```

**根拠**:
- Commands -> Options -> Global Options の順は cobra/oclif の Flags/Global Flags 自動分離に近いが、独立セクションとして明確に分離
- Environment Variables を独立セクションにするのは click/clap の各行内表示より発見しやすい
- Description は Swift AP の OVERVIEW 的な位置に配置

### 2. Global Options のサブコマンド表示

cobra/oclif 方式を採用し、サブコマンドのヘルプに Global Options セクションを**自動表示**する。大半のパーサがこれを怠っており、ユーザーが「このオプションはサブコマンドでも使えるのか？」を確認するためにトップレベルのヘルプに戻る必要がある。

### 3. 隠しオプション

Swift AP の二段階方式を採用:
- `--help`: 通常のヘルプ表示（隠しオプション除外）
- `--help-all`: すべてのオプション表示（隠し・deprecated 含む）

### 4. ターミナル幅・カラー

- ターミナル幅自動検出 + フォールバック 80 文字
- `NO_COLOR` 環境変数対応（[no-color.org](https://no-color.org/) 標準）
- TTY 検出による自動カラー切り替え

### 5. デフォルト値・型情報の表示

clap と yargs のハイブリッド:
```
--port <number>    Port to listen on  [default: 8080]
```
- デフォルト値: `[default: 8080]` 形式
- 型情報: `<number>`, `<path>`, `<addr>` 等のメタ変数で表現（yargs の `[number]` タグよりメタ変数の方が読みやすい）

### 6. 環境変数表示

独立セクション方式を推奨（大半のパーサが未対応で差別化要因）:
```
Environment Variables:
  MYAPP_PORT      Same as --port  [default: 8080]
  MYAPP_CONFIG    Same as --config
```

加えて、各オプション行にも `[env: MYAPP_PORT]` を表示する clap 方式の併用も検討。

### 7. 引数なし実行

好み通り、引数なし実行時は `--help` と同等の表示を行う。これは全パーサで設定可能だが、デフォルトでこの動作をするパーサは少ない（cobra は `RunE` 未設定時にヘルプ表示）。

### 8. テンプレート方式の検討

clap の独自テンプレートと cobra の Go テンプレートはどちらも強力だが、**デフォルトの構成が十分に良ければテンプレートは不要**。我々のパーサではデフォルトのセクション構成を十分に練り上げた上で、以下のカスタマイズポイントを提供する:
- ヘッダ/フッタテキスト（before_help / after_help）
- カスタムセクション追加（help_heading 相当）
- ヘルプハンドラの完全オーバーライド

### 9. 補完連携

ヘルプ定義と補完定義は同一ソースから生成する設計とする。オプション名、メタ変数、choices、サブコマンド名はすべてヘルプと補完で共有。

### 10. ショートオプション

好みに従い、デフォルトではショートオプションを付与しない。ユーザーが明示的に指定した場合のみヘルプに表示:
```
Options:
      --port <number>     Port to listen on  [default: 8080]
  -h, --help              Show help
```
`-h` のように明示指定されたもののみ左カラムに表示。clap/cobra の `-h, --help` デフォルト付与は行わない。

---

## 参考資料

- [clap - docs.rs](https://docs.rs/clap/latest/clap/)
- [clap - GitHub](https://github.com/clap-rs/clap)
- [bpaf - docs.rs](https://docs.rs/bpaf/latest/bpaf/)
- [bpaf - GitHub](https://github.com/pacak/bpaf)
- [Swift Argument Parser - GitHub](https://github.com/apple/swift-argument-parser)
- [Swift Argument Parser - Documentation](https://apple.github.io/swift-argument-parser/documentation/argumentparser/)
- [Swift Argument Parser Announcement](https://www.swift.org/blog/argument-parser/)
- [cobra - GitHub](https://github.com/spf13/cobra)
- [cobra - Documentation](https://cobra.dev/)
- [Clipanion - GitHub](https://github.com/arcanis/clipanion)
- [Clipanion Help Command](http://mael.dev/clipanion/docs/help/)
- [Click - Documentation](https://click.palletsprojects.com/)
- [rich-click - GitHub](https://github.com/ewels/rich-click)
- [yargs - Documentation](https://yargs.js.org/)
- [yargs - GitHub](https://github.com/yargs/yargs)
- [oclif - Documentation](https://oclif.io/)
- [oclif Help Classes](https://oclif.io/docs/help_classes/)
- [oclif - GitHub](https://github.com/oclif/oclif)
