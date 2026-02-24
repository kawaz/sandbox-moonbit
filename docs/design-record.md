# Design Record: kawaz/cli — MoonBit CLI 引数パーサ

## 1. 概要

MoonBit でフルスクラッチの CLI 引数パーサライブラリ `kawaz/cli` を設計・実装する。
28 パーサの大規模横断調査（`../main/docs/cli-parser-mega-survey.md`）の知見を踏まえ、理想のパーサを目指す。

### Phase 1 スコープ

- **型設計のみ**: enum / struct / suberror の定義とスナップショットテスト
- パーサ実装・ヘルプ生成は Phase 2 以降

### 設計原則

1. **環境非依存の純粋関数**: パーサコアは `Array[String]` を受け取り `ParseResult` を返す。OS API に依存しない
2. **多段デフォルト**: 設定ファイル → 環境変数 → CLI 引数を `apply_defaults` の畳み込みで表現
3. **型安全な値抽出**: `get_flag` / `get_string` / `get_int` / `get_list` でパース結果にアクセス
4. **表示制御の分離**: help と completion の表示制御を `Visibility` 型で独立管理

---

## 2. アーキテクチャ

### パッケージ構成

```
kawaz/cli/
  lib/          パーサコアロジック（環境非依存）
                Array[String] を受け取る純粋関数
                @env や OS API に一切依存しない
  platform/     @env.args() や extern FFI で引数・環境変数を取得する薄いグルー層
                Phase 2 以降で実装
```

### 依存関係

```
platform/ --> lib/    (platform は lib に依存)
lib/ --> (なし)       (lib は外部依存なし)
```

Design rationale: lib を環境非依存にすることで、テスト容易性と WASM ターゲットでの再利用性を確保する。platform 層は薄いグルーに徹し、ロジックを持たない。

---

## 3. 型設計

### 3.1 OptKind — オプションの値の種類

```moonbit
///|
pub(all) enum OptKind {
  /// 値なしフラグ（--verbose）
  Flag(default~ : Bool)
  /// 単一値（--format json）。複数指定時は後勝ち
  Single(default~ : String?)
  /// 複数値蓄積（--eval a --eval b → ["a", "b"]）
  Append(defaults~ : Array[String], n~ : Int)
  /// カウンタ（-v, -vvv, --verbose → 出現回数）
  Count(default~ : Int)
  /// 値省略可能な単一値（--color, --color=always）
  OptionalValue(default~ : String?, implicit~ : String, negated~ : String?)
} derive(Eq, Show, Debug)
```

Design rationale: デフォルト値を OptKind に内包することで、OptKind と default/defaults の整合性を型レベルで保証する。Flag に String? のデフォルトが設定される等の不整合を構造的に防止。

#### Count — カウンタオプション

OpenSSH の `-v` / `-vvv` パターン。clap の `ArgAction::Count`、Python argparse の `action='count'` と同じ。

- ショートオプションの同一文字連続でカウント（`-vvv` → 3）
- ロングでも使える（`--verbose` → +1）
- 反転フラグ（`Inverted`）で 0 にリセット（`--no-verbose` → 0）
- `LongOptWithValue` の値は無視（`--verbose=3` は `CountValue(1)` として扱う）
- `choices` とは組み合わせ不可（`validate_opts` で `DefinitionError` とする）
- `get_int` と `get_count` の両方で取得可能

#### OptionalValue — 値省略可能オプション

git の `--color` / `--color=always` パターン。

- **先読みなし**: `=` 形式のみ値受付。`--color xxx` は implicit 値を適用 + `xxx` は位置引数
- tokenizer の `LongOpt` / `LongOptWithValue` の区別がこの設計を自然に実現
- 反転フラグ（`Inverted`）は negated 値をセット（`None` なら値を remove）
- ショートオプションとの組み合わせ不可（`validate_opts` で `DefinitionError` とする）
- `choices` バリデーション: `implicit`, `negated`, `default` 全てが `choices` に含まれるかチェック
- `ParsedValue` は既存の `StringValue` を共用

Design rationale: OptionalValue の先読みなし設計は、tokenizer が `--color`（`LongOpt`）と `--color=always`（`LongOptWithValue`）を既に区別しているため、パーサ側で後続トークンの先読みを行う必要がない。これにより実装の複雑さを抑えつつ、git `--color[=when]` と同等のセマンティクスを実現する。

#### Nary — 固定長複数値消費（Append(n~) として統合済み）

当初 `Nary(n~ : Int, defaults~ : Array[Array[String]])` + `TupleListValue(Array[Array[String]])` として別バリアントを検討していたが、`Append(defaults~, n~)` の `n` パラメータとして統合した。`n=1` が通常の Append、`n>1` が固定長複数値消費（jq の `--arg k v` 等）に対応する。`ParseResult::get_chunks()` で n 個ずつのチャンクとして取得可能。

### 3.2 FlagInversion — フラグ反転パターン

```moonbit
///|
/// --no-xxx, --enable-xxx/--disable-xxx, --with-xxx/--without-xxx の 3 パターン
/// Swift ArgumentParser の FlagInversion に相当
pub(all) enum FlagInversion {
  /// --verbose / --no-verbose
  PrefixNo
  /// --enable-color / --disable-color
  PrefixEnableDisable
  /// --with-ssl / --without-ssl
  PrefixWithWithout
} derive(Eq, Show, Debug)
```

Design rationale: `PrefixNo` と `PrefixEnableDisable` は Swift ArgumentParser の `FlagInversion` に対応する。`PrefixWithWithout` は本ライブラリの独自拡張で、`--with-ssl` / `--without-ssl` のような feature toggle パターンに対応する。

Design rationale: 型名は `FlagInversion` だが、`Single`（値クリア）や `Append`（リストリセット）にも適用可能。
`--no-format` で Single オプションの値をクリアし、`--no-eval` で Append のリストをリセットする用途を
意図的にサポートする（DR セクション 4.5.3 参照）。型名を `InversionPattern` 等に変更することも検討したが、
フラグ反転が最も一般的なユースケースであるため現名称を維持する。

反転フラグのセマンティクスはセクション4 apply_defaults を参照。

### 3.3 Visibility — 表示制御

```moonbit
///|
/// help と completion での表示を個別に制御する
pub(all) struct Visibility {
  show_in_help : Bool
  show_in_completion : Bool
} derive(Eq, Show, Debug)
```

```moonbit
///|
/// よく使うプリセット
pub fn Visibility::shown() -> Visibility {
  { show_in_help: true, show_in_completion: true }
}

///|
pub fn Visibility::hidden() -> Visibility {
  { show_in_help: false, show_in_completion: false }
}

///|
/// help にだけ表示（補完候補には出さない）
pub fn Visibility::help_only() -> Visibility {
  { show_in_help: true, show_in_completion: false }
}

///|
/// 補完候補にだけ表示（help には出さない）
pub fn Visibility::completion_only() -> Visibility {
  { show_in_help: false, show_in_completion: true }
}
```

### 3.4 AliasEntry — エイリアス定義

```moonbit
///|
/// ロングオプション名やサブコマンド名のエイリアス
/// deprecated 移行用途などで使う
pub(all) struct AliasEntry {
  name : String
  visibility : Visibility
  /// deprecated メッセージ（None なら非 deprecated）
  deprecated : String?
} derive(Eq, Show, Debug)
```

```moonbit
///|
pub fn AliasEntry::new(
  name~ : String,
  visibility? : Visibility = Visibility::shown(),
  deprecated? : String? = None,
) -> AliasEntry {
  { name, visibility, deprecated }
}
```

### 3.5 ShortEntry — ショートオプション定義

```moonbit
///|
/// ショートオプション（1文字）に表示制御を付与
pub(all) struct ShortEntry {
  char : Char
  visibility : Visibility
} derive(Eq, Show, Debug)
```

```moonbit
///|
pub fn ShortEntry::new(
  char~ : Char,
  visibility? : Visibility = Visibility::shown(),
) -> ShortEntry {
  { char, visibility }
}
```

### 3.6 OptDef — オプション定義

```moonbit
///|
/// 1 つのオプションの完全な定義
pub(all) struct OptDef {
  /// ロングオプション名（"--" プレフィックスなし。例: "verbose"）
  long : String
  /// ヘルプテキスト
  help : String
  /// オプションの種類
  kind : OptKind
  /// ショートオプション（省略可）
  shorts : Array[ShortEntry]
  /// ロング名のエイリアス（省略可）
  aliases : Array[AliasEntry]
  /// フラグ反転パターン（省略可）
  inversion : FlagInversion?
  /// 環境変数名（省略可。例: "MYAPP_VERBOSE"）
  env : String?
  /// 選択肢制約（空なら制約なし）
  choices : Array[String]
  /// ヘルプ表示用の値プレースホルダ（例: "FORMAT", "PATH"）
  value_name : String
  /// 必須フラグ
  required : Bool
  /// ロング名の表示制御
  visibility : Visibility
} derive(Eq, Show, Debug)
```

```moonbit
///|
/// OptDef のコンストラクタ。ラベル付き引数で宣言的に記述する
pub fn OptDef::new(
  long~ : String,
  help~ : String,
  kind~ : OptKind,
  shorts? : Array[ShortEntry] = [],
  aliases? : Array[AliasEntry] = [],
  inversion? : FlagInversion? = None,
  env? : String? = None,
  choices? : Array[String] = [],
  value_name? : String = "VALUE",
  required? : Bool = false,
  visibility? : Visibility = Visibility::shown()
) -> OptDef {
  {
    long, help, kind, shorts, aliases, inversion,
    env, choices, value_name, required, visibility,
  }
}
```

Design rationale: デフォルト値付きのラベル引数には `?` 記法を使用する。MoonBit の `moon fmt` が `param~ : T = default` を `param? : T = default` に正規化するため、フォーマッタの出力に合わせている。必須引数（デフォルト値なし）は `~` 記法のまま。

### 3.7 ParsedValue — パース済みの値

```moonbit
///|
/// パース結果に格納される個々の値
pub(all) enum ParsedValue {
  /// フラグの真偽値
  FlagValue(Bool)
  /// 単一の文字列値（Single, OptionalValue 共用）
  StringValue(String)
  /// 蓄積された文字列リスト
  ListValue(Array[String])
  /// カウンタ値
  CountValue(Int)
} derive(Eq, Show, Debug)
```

### 3.8 ParseResult — パース結果

```moonbit
///|
/// パーサの出力
pub(all) struct ParseResult {
  /// オプション名 → パース済み値のマップ
  values : Map[String, ParsedValue]
  /// 位置引数（オプションでもサブコマンドでもない引数）
  positional : Array[String]
  /// "--" 以降の引数
  rest : Array[String]
  /// Append(n>1) の chunk サイズを記録（get_chunks で使用）
  chunk_sizes : Map[String, Int]
} derive(Eq, Show, Debug)
```

```moonbit
///|
pub fn ParseResult::new() -> ParseResult {
  { values: {}, positional: [], rest: [], chunk_sizes: {} }
}
```

### 3.9 型安全な値抽出メソッド

```moonbit
///|
/// フラグ値を取得。未設定時は false
pub fn ParseResult::get_flag(self : ParseResult, name : String) -> Bool {
  match self.values.get(name) {
    Some(FlagValue(v)) => v
    _ => false
  }
}

///|
/// 文字列値を取得
pub fn ParseResult::get_string(self : ParseResult, name : String) -> String? {
  match self.values.get(name) {
    Some(StringValue(v)) => Some(v)
    _ => None
  }
}

///|
/// Int 値を取得。値が存在しないか Int に変換できない場合は None
/// CountValue(n) も Some(n) として返す
/// Design rationale: Phase 1 では Option で統一。
/// より詳細なエラー区別が必要な場合は Phase 2 で Result 版を追加する
pub fn ParseResult::get_int(self : ParseResult, name : String) -> Int? {
  match self.values.get(name) {
    Some(StringValue(v)) =>
      try {
        Some(@strconv.parse_int(v))
      } catch {
        _ => None
      }
    Some(CountValue(v)) => Some(v)
    _ => None
  }
}

///|
/// リスト値を取得。未設定時は空配列
pub fn ParseResult::get_list(self : ParseResult, name : String) -> Array[String] {
  match self.values.get(name) {
    Some(ListValue(v)) => v
    _ => []
  }
}

///|
/// カウンタ値を取得。未設定時は 0
/// get_int でも取得可能（CountValue(n) → Some(n)）
pub fn ParseResult::get_count(self : ParseResult, name : String) -> Int {
  match self.values.get(name) {
    Some(CountValue(v)) => v
    _ => 0
  }
}

///|
/// Append(n>1) の値を n 個ずつのチャンクに分割して返す
/// n は chunk_sizes から自動参照。n=1 の場合は空配列を返す（get_list を使うこと）
pub fn ParseResult::get_chunks(self : ParseResult, name : String) -> Array[Array[String]]
```

### 3.10 ParseError — パースエラー

```moonbit
///|
pub(all) suberror ParseError {
  /// 未知のオプション（例: --unknown）
  UnknownOption(String)
  /// 値が必要なオプションに値がない（例: --format で値が続かない）
  MissingValue(String)
  /// 必須オプションが指定されていない
  MissingRequired(String)
  /// choices 制約に合致しない値
  InvalidChoice(option~ : String, value~ : String, choices~ : Array[String])
  /// --help が指定された
  /// Design rationale: 正常系だがパース中断を強制するため
  /// エラー型で表現する（cobra/clap と同じアプローチ）
  HelpRequested
  /// OptDef 定義のバリデーションエラー（開発者のミス）
  DefinitionError(String)
} derive(Show)
```

### 3.11 HelpSection — ヘルプセクション種別

```moonbit
///|
/// --help 出力のセクション分け
pub(all) enum HelpSection {
  /// サブコマンド一覧
  Commands
  /// ローカルオプション
  Options
  /// グローバルオプション（親から継承）
  GlobalOptions
  /// 環境変数
  EnvironmentVariables
} derive(Eq, Show, Debug)
```

---

## 4. apply_defaults 設計

### シグネチャ

```moonbit
///|
/// 引数レイヤを OptDef のデフォルト値に吸収する
/// 未知オプションは無視（デフォルト層ではエラーにしない）
/// 位置引数と "--" 以降は無視
pub fn apply_defaults(
  opts : Array[OptDef],
  args : Array[String]
) -> Array[OptDef]
```

### セマンティクス

| OptKind | 正方向の動作 | 反転方向の動作 |
|---|---|---|
| Flag | OptKind 内の `default` を該当値に上書き | OptKind 内の `default` を反転値に上書き |
| Single | OptKind 内の `default` を指定値に上書き | OptKind 内の `default` を `None` にクリア |
| Append(n=1) | OptKind 内の `defaults` に値を追加 | OptKind 内の `defaults` を `[]` にリセット |
| Append(n>1) | n 個全て揃った場合のみ `defaults` に反映（部分消費は破棄、defaults 変更なし） | OptKind 内の `defaults` を `[]` にリセット |
| Count | OptKind 内の `default` を +1 | OptKind 内の `default` を 0 にリセット |
| OptionalValue | `LongOptWithValue` → `default` を指定値に上書き、`LongOpt` → `default` を `implicit` に上書き | OptKind 内の `default` を `negated` に上書き（`None` なら `None` にクリア） |

### 使用例: 多段畳み込み

```moonbit
// 設定ファイルの引数 → 環境変数の引数 → CLI 引数の 3 段階
let config_args : Array[String] = ["--format", "yaml", "--verbose"]
let env_args : Array[String] = ["--format", "json"]
let cli_args : Array[String] = ["--no-verbose", "input.txt"]

// apply_defaults で設定ファイル → 環境変数を畳み込み
let reduced_opts = apply_defaults(apply_defaults(opts, config_args), env_args)

// 最終パースは CLI 引数で実行（Phase 2 で実装）
let result = parse(reduced_opts, cli_args)
// result: format="json"（env で上書き）, verbose=false（CLI で反転）, positional=["input.txt"]
```

### Append + 反転フラグの例

```bash
# デフォルト: --fields id,name（設定ファイル由来）
# CLI引数: フィールドをリセットして created_at のみに
myapp --no-fields --fields created_at
# → パース結果: fields = ["created_at"]

# CLI引数: フィールドに追加
myapp --fields created_at
# → パース結果: fields = ["id", "name", "created_at"]
```

### 不変条件

- **恒等性**: `apply_defaults(opts, []) == opts`（空引数では何も変化しない）
- **純粋関数**: 入力の opts を変更せず、新しい `Array[OptDef]` を返す
- **未知オプション無視**: デフォルト層なので知らないオプションはスキップ
- **位置引数無視**: `--` 以前の非オプション引数、`--` 以降すべてを無視
- **環境変数の安全な変換**: 環境変数値は `["--key", value]` ペアとして変換し、シェル分割しない。`MYAPP_FORMAT="--verbose"` は `["--format", "--verbose"]`（format の値が文字列 "--verbose"）として扱う

Design rationale: `apply_defaults` は値のバリデーションを行わない。`--verbose=banana` のような Flag への不正な
= 形式は無視される（方向のみ適用）。これは設定ファイルやデフォルト層で不正値が含まれていても、最終的な
`parse` でのバリデーションに委ねるという設計判断による。`apply_defaults` はあくまでデフォルト値の書き換えに
特化した純粋関数であり、エラーを raise しない（未知オプションも無視する）。

### parse と apply_defaults の Append セマンティクス差異

- `apply_defaults`: 既存の defaults に値を**追加**する（stacking semantics）
- `parse`: CLI で明示指定された Append オプションは、defaults を**完全に置換**する（replace semantics）

Design rationale: clap / cobra と同様のアプローチ。CLI で明示的に `--eval new` を指定した場合、ユーザーの意図は「new を使う」であり「デフォルトに追加する」ではない。デフォルトに追加したい場合は `apply_defaults` の層で行う。

---

## 4.5 パーサ実装設計（Phase 2）

Phase 2 ではパーサコアを実装する。CmdDef（サブコマンド）および platform/ 層は Phase 2.5 に先送りし、まず単一コマンドの引数パーサを完成させる。

### 4.5.1 Token — 字句解析の中間表現

```moonbit
///|
pub(all) enum Token {
  /// --verbose
  LongOpt(String)
  /// --format=json
  LongOptWithValue(String, String)
  /// -abc （複数文字を文字列で保持）
  ShortOpts(String)
  /// 位置引数
  Positional(String)
  /// --
  DoubleDash
} derive(Eq, Show, Debug)
```

Design rationale: `-abc` を個々の `ShortOpt(Char)` に分割せず `ShortOpts(String)` で保持する。分割は parse 段階で OptDef を参照して行う（`-o file` のように最後の短オプションが値を取る場合の判定に OptDef 情報が必要なため）。

### 4.5.2 tokenize 関数

```moonbit
///|
pub fn tokenize(args : Array[String]) -> Array[Token]
```

変換ルール:

| 入力パターン | 出力 Token | 備考 |
|---|---|---|
| `--` | `DoubleDash` | 以降の全引数は `Positional` |
| `--key=value` | `LongOptWithValue(key, value)` | `=` の前がキー、後が値 |
| `--key` | `LongOpt(key)` | `--` プレフィックスを除去 |
| `-abc` | `ShortOpts("abc")` | `-` プレフィックスを除去、2文字以上 |
| `-` | `Positional("-")` | 単独ハイフンは位置引数（stdin 慣習） |
| その他 | `Positional(value)` | そのまま |

`DoubleDash` 以降の全引数は無条件で `Positional` に変換する。

### 4.5.3 parse 関数

```moonbit
///|
pub fn parse(
  opts : Array[OptDef],
  args : Array[String],
) -> ParseResult raise ParseError
```

処理フロー:

1. `tokenize(args)` で字句解析
2. トークン列を順に処理:
   - `LongOpt(name)`: OptDef から名前解決（エイリアス・反転パターン含む）。Flag なら `FlagValue` を設定、Single なら次のトークンを値として消費、Append なら値を蓄積、Count なら既存値 +1、OptionalValue なら `implicit` 値で `StringValue` を設定
   - `LongOptWithValue(name, value)`: 名前解決後、値を設定。Flag に `=value` が指定された場合、`"true"` / `"false"` のみ許容し、それ以外は `InvalidChoice` とする。Count に `=value` が指定された場合、値は無視して `CountValue(1)` として扱う。OptionalValue に `=value` が指定された場合、その値で `StringValue` を設定
   - `ShortOpts(chars)`: 1文字ずつ処理。最後の文字が Single/Append 型なら残りの文字列または後続トークンを値として消費。Count 型の文字が連続する場合はその文字数をカウント（`-vvv` → `CountValue(3)`）
   - `Positional(value)`: `positional` に追加
   - `DoubleDash`: 以降の全トークンを `rest` に追加
3. `--no-xxx` 反転処理: `--no-verbose` を検出したら、`inversion=Some(PrefixNo)` の OptDef を探して `FlagValue(false)` を設定
4. `--enable-xxx`/`--disable-xxx`、`--with-xxx`/`--without-xxx` も同様に処理（正方向は `FlagValue(true)`、負方向は `FlagValue(false)`）
5. required チェック: 必須オプションが未設定なら `MissingRequired`
6. choices チェック: 値が `choices` に含まれないなら `InvalidChoice`
7. `--help` 検出: `HelpRequested` を raise
8. デフォルト値適用: `OptKind` 内の default/defaults を明示指定されていないオプションに適用

Design rationale: `required=true` + `inversion` の組み合わせ — `--no-format` で Single オプションの値をクリアしても、
`explicitly_set` に記録されるため required チェックは通過する。これは「ユーザーが明示的にオプションを操作した」
ことを required の充足条件とする設計判断。値の存在自体を保証したい場合は、呼び出し元で `get_string` の戻り値を
確認する必要がある。将来的に `required` の意味を厳密化する場合は別のバリデーションオプションを追加する。

短オプション結合の展開例:

```
-abc  （a=Flag, b=Flag, c=Flag）
→ FlagValue(true), FlagValue(true), FlagValue(true)

-abc  （a=Flag, b=Flag, c=Single）
→ FlagValue(true), FlagValue(true), 次トークンを c の値に

-abcVALUE  （a=Flag, b=Flag, c=Single）
→ FlagValue(true), FlagValue(true), c の値 = "VALUE"

-vvv  （v=Count）
→ CountValue(3)

-avvb  （a=Flag, v=Count, b=Flag）
→ FlagValue(true), CountValue(2), FlagValue(true)
```

### Single/Append/Count/OptionalValue の反転処理

- `--no-format` (Single + PrefixNo): 値を未設定にクリアする。次トークンを値として消費しない
- `--no-eval` (Append + PrefixNo): リストを空にリセットする
- `--no-verbose` (Count + PrefixNo): カウンタを 0 にリセットする（`CountValue(0)`）
- `--no-color` (OptionalValue + PrefixNo): `negated` 値を `StringValue` として設定する。`negated` が `None` なら値を remove する

### 4.5.4 apply_defaults 関数

セクション4の設計をそのまま実装する。追加の設計判断:

- 反転フラグ（`--no-xxx` 等）の処理も apply_defaults 内で行う
- 内部で `tokenize` を使用し、トークン列から OptDef のデフォルト値を更新
- 未知オプション・位置引数は無視（セクション4の不変条件に従う）

```moonbit
///|
/// セクション4のシグネチャ再掲。実装はセクション4のセマンティクスに従う
pub fn apply_defaults(
  opts : Array[OptDef],
  args : Array[String],
) -> Array[OptDef]
```

### 4.5.5 validate_opts 関数

```moonbit
///|
pub fn validate_opts(opts : Array[OptDef]) -> Unit raise ParseError
```

検証項目:

| 検証 | エラー |
|---|---|
| 空の `long` 名 | `DefinitionError("empty long name")` |
| `long` 名の重複 | `DefinitionError("duplicate long: {name}")` |
| `short` 文字の重複 | `DefinitionError("duplicate short: {char}")` |
| エイリアス名が他の `long` 名やエイリアスと衝突 | `DefinitionError("alias conflict: {name}")` |
| 反転生成名（`no-xxx`, `enable-xxx` 等）が他のオプション名と衝突 | `DefinitionError("inversion conflict: {name}")` |
| `choices` 設定時にデフォルト値が `choices` に含まれない | `InvalidChoice(...)` |
| `short` 文字が英数字でない | `DefinitionError("invalid short option: {char}")` |
| Append defaults が choices に含まれない | `InvalidChoice(...)` |
| Count + `choices` の組み合わせ | `DefinitionError("Count option cannot have choices: {name}")` |
| OptionalValue + `shorts` の組み合わせ | `DefinitionError("OptionalValue option cannot have short options: {name}")` |
| OptionalValue + `choices` 時に `implicit` が `choices` に含まれない | `InvalidChoice(...)` |
| OptionalValue + `choices` 時に `negated`（Some）が `choices` に含まれない | `InvalidChoice(...)` |
| OptionalValue + `choices` 時に `default`（Some）が `choices` に含まれない | `InvalidChoice(...)` |

Design rationale: バリデーションエラーは `DefinitionError` で表現する。開発者のミスであることを明示し、ユーザー入力起因のエラーと区別する。choices 不整合は `InvalidChoice` を再利用し、メッセージで区別する。

### 4.5.6 名前解決

オプション名の解決順序（`LongOpt` / `LongOptWithValue` のキーに対して）:

1. `long` 名との完全一致
2. `aliases` の `name` との完全一致
3. 反転パターン名のマッチ:
   - `PrefixNo`: `no-{long}` → 反転
   - `PrefixEnableDisable`: `enable-{long}` → 正方向、`disable-{long}` → 反転
   - `PrefixWithWithout`: `with-{long}` → 正方向、`without-{long}` → 反転
4. いずれにもマッチしない → `UnknownOption`

ショートオプションの解決:

1. 全 OptDef の `shorts` から `char` 一致を検索
2. マッチしない → `UnknownOption`

### 4.5.7 実装優先順

```
1. tokenize        — 単純な字句解析。他に依存なし
   ↓
2. validate_opts   — OptDef のバリデーション。parse 前に呼ぶ
   ↓
3. parse           — コア実装。tokenize + 名前解決 + 値設定 + チェック
   ↓
4. apply_defaults  — parse のサブセット。parse 完成後に実装
```

各関数は独立してテスト可能。TDD で 1 → 4 の順に実装・テストを進める。

---

## 5. ユーザー API 使用例

### 最小のオプション定義

```moonbit
let opt = OptDef::new(
  long="verbose",
  help="Enable verbose output",
  kind=Flag(default=false),
)
```

### 基本的なオプション定義

```moonbit
let opts : Array[OptDef] = [
  OptDef::new(
    long="verbose",
    help="Enable verbose output",
    kind=Flag(default=false),
    inversion=Some(PrefixNo),
  ),
  OptDef::new(
    long="format",
    help="Output format",
    kind=Single(default=Some("json")),
    choices=["json", "yaml", "text"],
    value_name="FORMAT",
    env=Some("MYAPP_FORMAT"),
  ),
  OptDef::new(
    long="eval",
    help="Expression to evaluate (repeatable)",
    kind=Append(defaults=[]),
    value_name="EXPR",
    shorts=[ShortEntry::new(char='e', visibility=Visibility::help_only())],
  ),
  OptDef::new(
    long="config",
    help="Configuration file path",
    kind=Single(default=None),
    value_name="PATH",
    env=Some("MYAPP_CONFIG"),
  ),
]
```

### カウンタオプション

```moonbit
let opt_verbose = OptDef::new(
  long="verbose",
  help="Increase verbosity level",
  kind=Count(default=0),
  shorts=[ShortEntry::new(char='v')],
  inversion=Some(PrefixNo),
)
// -v → CountValue(1), -vvv → CountValue(3), --verbose --verbose → CountValue(2)
// --no-verbose → CountValue(0)
```

### 値省略可能オプション

```moonbit
let opt_color = OptDef::new(
  long="color",
  help="Control color output",
  kind=OptionalValue(default=None, implicit="always", negated=Some("never")),
  choices=["always", "auto", "never"],
  inversion=Some(PrefixNo),
)
// --color → StringValue("always")（implicit 値）
// --color=auto → StringValue("auto")
// --no-color → StringValue("never")（negated 値）
// --color xxx → StringValue("always") + xxx は位置引数
```

### エイリアス付きオプション

```moonbit
let opt_output = OptDef::new(
  long="output",
  help="Output file path",
  kind=Single(default=None),
  aliases=[
    AliasEntry::new(name="out"),
    // deprecated: help には出すが補完には出さない
    AliasEntry::new(name="output-file", visibility=Visibility::help_only(), deprecated=Some("Use --output instead")),
  ],
  shorts=[ShortEntry::new(char='o')],
)
```

### パース結果の利用（Phase 2 で parse 実装後）

```moonbit
fn run() -> Unit raise ParseError {
  let result = parse(opts, ["--format", "yaml", "--eval", "1+1", "--eval", "2+2", "input.txt", "--", "extra"])

  let verbose = result.get_flag("verbose")       // false
  let format = result.get_string("format")        // Some("yaml")
  let evals = result.get_list("eval")             // ["1+1", "2+2"]
  let positional = result.positional               // ["input.txt"]
  let rest = result.rest                           // ["extra"]
  // ...
}

fn run_with_count() -> Unit raise ParseError {
  let result = parse(opts, ["-vvv", "--color", "input.txt"])

  let verbosity = result.get_count("verbose")    // 3
  let verbosity2 = result.get_int("verbose")     // Some(3)（get_int でも取得可能）
  let color = result.get_string("color")          // Some("always")（implicit 値）
  // ...
}
```

---

## 6. --help 出力例

※ Phase 1 ではサブコマンド・グローバルオプションの区分は未実装。以下は Phase 2 以降の完成イメージ。

```
myapp 1.0.0 - Description of the application

Usage: myapp [OPTIONS] [ARGS...]

Options:
  --verbose              Enable verbose output
  --no-verbose           Disable verbose output
  --format <FORMAT>      Output format [possible: json, yaml, text] [default: json]
  --eval, -e <EXPR>      Expression to evaluate (repeatable)

Global Options:
  --config <PATH>        Configuration file path [env: MYAPP_CONFIG]
  --help                 Show this help message

Environment Variables:
  MYAPP_FORMAT           Output format (overridden by --format)
  MYAPP_CONFIG           Configuration file path (overridden by --config)
```

セクション構成:

1. **Options** — そのコマンド固有のオプション
2. **Global Options** — 親コマンドから継承されたオプション（Phase 2 のサブコマンド実装後に活用）
3. **Environment Variables** — `env` 属性が設定されたオプションの一覧

---

## 7. Phase 2 以降への拡張ポイント

### Phase 2: パーサコア実装

詳細設計はセクション 4.5 を参照。

- `tokenize(args)` の実装（字句解析）
- `validate_opts(opts)` の実装（OptDef 定義のバリデーション）
- `parse(opts, args)` の実装（`Array[OptDef]` + `Array[String]` → `ParseResult raise ParseError`）
- `apply_defaults(opts, args)` の実装（多段デフォルトの畳み込み）
- 短オプションの結合（`-abc` = `-a -b -c`）のサポート
- `--no-xxx` / `--enable-xxx` / `--disable-xxx` / `--with-xxx` / `--without-xxx` 反転処理
- `--key=value` の分割処理

### Phase 2.5: サブコマンド対応（実装済み）

Phase 2 のパーサコアを土台に、サブコマンドルーティングとグローバルオプション継承を実装した。

#### 設計原則

- **parse result return**: `parse_command` は `CommandResult` を返す。コマンドパスとパース結果を一体化し、呼び出し元でのディスパッチを容易にする
- **グローバルオプション前後配置**: サブコマンド名の前後どちらにもグローバルオプションを置ける（cobra の PersistentFlags 方式）
- **help_on_empty で required エラー防止**: サブコマンド名も引数もない状態を parse に渡すと required エラーになるため、parse の前で `HelpRequested` を raise する

#### CmdDef 型

```moonbit
pub(all) struct CmdDef {
  /// コマンド名
  name : String
  /// コマンドの説明
  description : String
  /// バージョン文字列
  version : String
  /// コマンド固有のオプション定義
  opts : Array[OptDef]
  /// グローバルオプション定義（このコマンドで定義し、子孫に継承される）
  global_opts : Array[OptDef]
  /// サブコマンド定義（無制限ネスト）
  subcommands : Array[CmdDef]
  /// コマンド名のエイリアス
  aliases : Array[AliasEntry]
  /// 引数なし実行時に help を表示するか（デフォルト: true）
  help_on_empty : Bool
}
```

各フィールドの説明:

| フィールド | 説明 |
|---|---|
| `name` | コマンド名。サブコマンドルーティングのマッチ対象 |
| `description` | ヘルプ表示用の説明文 |
| `version` | `--version` で表示するバージョン文字列 |
| `opts` | このコマンド固有のオプション。子には継承されない |
| `global_opts` | このコマンドで定義するグローバルオプション。子孫全てで有効（cobra PersistentFlags 相当） |
| `subcommands` | 子サブコマンドの配列。子もさらに `subcommands` を持てるため無制限ネスト |
| `aliases` | コマンド名のエイリアス（`AliasEntry` で deprecated 移行にも対応） |
| `help_on_empty` | `true` の場合、引数なし実行時に `HelpRequested` を raise |

#### CommandResult 型

```moonbit
pub(all) struct CommandResult {
  /// 解決されたコマンドパス（例: ["remote", "add"]）
  command : Array[String]
  /// パース結果（リーフコマンドの effective_opts でパースした結果）
  result : ParseResult
}
```

`command` はルートコマンドの名前を含まず、サブコマンドパスのみを保持する。サブコマンドなしの場合は空配列。

#### ルーティングアルゴリズム

`parse_command` → `find_command` → `scan_for_subcommand` の 3 段階で処理する。

##### parse_command（エントリポイント）

1. `validate_command(cmd)` でコマンド定義ツリー全体を検証
2. ルートの `help_on_empty` チェック（引数が空なら `HelpRequested`）
3. `find_command` でサブコマンド解決
4. リーフの `help_on_empty` チェック（ルートと異なるリーフの場合のみ）
5. effective_opts 構築（leaf の `opts` + `global_opts` + 全祖先の `global_opts`）
6. `parse(effective_opts, parse_args)` で引数パース
7. `CommandResult` として返却

##### find_command（再帰的サブコマンド解決）

```
find_command(cmd, args, inherited_globals) -> (leaf_cmd, command_path, parse_args)
```

1. `cmd.subcommands` が空ならリーフとして即返却
2. `effective_opts` = `cmd.opts` + `cmd.global_opts` + `inherited_globals` を構築
3. `tokenize(args)` で字句解析
4. `scan_for_subcommand` でサブコマンド候補の位置を特定
5. サブコマンドが見つからなければ `cmd` 自体がリーフ
6. 見つかれば、その位置の引数を除去して子に再帰
7. 再帰時に `cmd.global_opts` + `inherited_globals` を子の `inherited_globals` として渡す

##### scan_for_subcommand（トークン走査）

```
scan_for_subcommand(tokens, effective_opts, subcommands) -> Int?
```

トークン列を先頭から走査し、最初のサブコマンド候補 `Positional` のインデックスを返す。

- `LongOpt` / `LongOptWithValue` / `ShortOpts`: `resolve_long` / `resolve_short` で名前解決し、値消費分をスキップ
- `Positional`: サブコマンド名とマッチすればそのインデックスを返す
- `DoubleDash`: 走査を終了（`None` を返す）

オプションの値消費を正確にスキップすることで、`--format json config set` のような引数列で `json` をサブコマンドと誤認しない。

#### グローバルオプション継承

全祖先の `global_opts` がリーフコマンドで有効になる仕組み:

```
root.global_opts → child.global_opts → grandchild.global_opts
         ↓                 ↓                    ↓
      リーフの effective_opts に全て含まれる
```

- `find_command` の再帰で、各階層の `global_opts` が `inherited_globals` として子に渡される
- `parse_command` の effective_opts 構築時に、ルートから leaf の親まで全ての `global_opts` を収集
- 最終的な `parse` には leaf の `opts` + leaf の `global_opts` + 全祖先の `global_opts` が渡される

#### Design rationale

- **help_on_empty を parse の前でチェック**: サブコマンドが期待されるコマンドに引数なしで実行すると、`parse` が required オプションのエラーを返す。ユーザーの意図はヘルプ表示であるため、parse の前に `HelpRequested` を raise する
- **--version は --help と同じトークン消費ルール内で処理**: `parse` 関数内の `LongOpt`/`LongOptWithValue` 処理の冒頭で、`opts` に `version` が未定義なら `VersionRequested` を raise する。`--help` と同じ位置で同じパターンの処理を行うことで、一貫性を保つ
- **子固有オプションをサブコマンド名の前に置けない**: `scan_for_subcommand` は `effective_opts`（親の `opts` + `global_opts` + `inherited_globals`）で名前解決する。子の `opts` は含まれないため、`myapp --child-opt subcmd` は `UnknownOption` になる。これは cobra と同じ制約であり、パーサの複雑さとユーザーの混乱を防ぐ意図的な設計
- **UnknownCommand はサブコマンドが定義されているコマンドでのみ発火**: `scan_for_subcommand` 内で、`Positional` がどのサブコマンドにもマッチせず、かつ `subcommands` が空でない場合に `UnknownCommand` を raise する。サブコマンドが未定義のリーフでは `Positional` は位置引数として扱われる

#### validate_command

コマンド定義ツリーの再帰的検証。`parse_command` の冒頭で呼び出される。

検証項目:

| 検証 | エラー |
|---|---|
| 各ノードの `opts` + `global_opts` + `inherited_globals` の整合性 | `validate_opts` に委譲 |
| サブコマンド名が空 | `DefinitionError("empty subcommand name")` |
| サブコマンド名の重複 | `DefinitionError("duplicate subcommand: {name}")` |
| サブコマンドエイリアスが他の名前・エイリアスと衝突 | `DefinitionError("subcommand alias conflict: {name}")` |

再帰時に `inherited_globals` を蓄積して渡すことで、祖先の `global_opts` と子の `opts` の名前衝突も検出する。

#### platform/ 層

`@env.args()` からの引数取得グルー。Phase 2.5 のスコープだが未実装（Phase 3 以降で着手予定）。

### Phase 3: オプショングループ

サブコマンドに近い「暗黙的スコープベースのグルーピング」機構。`--upstream u1 --socket s1 a b --socket s2 d --upstream u2 --socket s3` のように、オプション出現でスコープが開閉し、ネストした構造をパースする。

#### 新規型

##### PositionalDef — 位置引数の定義

```moonbit
///|
pub(all) struct PositionalDef {
  /// ヘルプ用プレースホルダ（"FILE", "SRC", "DST"）
  name : String
  /// 説明
  help : String
  /// 選択肢制約（空なら制約なし）
  choices : Array[String]
} derive(Eq, Show, Debug)
```

##### Positional — 位置引数の受付仕様

```moonbit
///|
pub(all) enum Positional {
  /// 位置引数を受け付けない
  Disallowed
  /// 固定個数。各位置に個別の定義
  Fixed(Array[PositionalDef])
  /// 可変長。全て同じ定義
  Variadic(PositionalDef)
} derive(Eq, Show, Debug)
```

CmdDef と Group の両方で使用する。CmdDef にも `positional_spec : Positional` フィールドを追加:

```moonbit
///|
// CmdDef に追加
positional_spec : Positional  // デフォルト: Variadic(PositionalDef::new(name="ARG", help=""))
```

既存の動作（位置引数を自由に受け付ける）との後方互換性を維持するため `Variadic` がデフォルト。

##### GroupInstance — グループインスタンス

```moonbit
///|
pub(all) struct GroupInstance {
  /// 値ありグループの値（"u1"）。値なしグループは None
  value : String?
  /// グループ内のパース結果
  result : ParseResult
} derive(Eq, Show, Debug)
```

Design rationale: GroupInstance → ParseResult → ParsedValue::GroupValue → GroupInstance の相互再帰型が存在する。MoonBit の derive(Eq, Show, Debug) は相互再帰型を正しく処理可能という前提で設計しているが、実装時に確認が必要。深いネストでのスタックオーバーフローは実用上問題にならない想定（グループのネストは3-4段が上限）。

##### GroupKind — グループの値受付種別

```moonbit
///|
pub(all) enum GroupKind {
  /// 値なしグループ（`--rule` のように値を取らない）
  Valueless
  /// 値ありグループ（`--upstream u1` のように値を取る）
  WithValue(default~ : String?)
} derive(Eq, Show, Debug)
```

##### OptKind::Group — グループオプション

```moonbit
///|
// OptKind に追加
Group(
  /// グループの値受付種別
  group_kind~ : GroupKind,
  /// グループ内のオプション定義
  opts~ : Array[OptDef],
  /// 位置引数の受付仕様
  positional~ : Positional,
)
```

##### ParsedValue::GroupValue

```moonbit
///|
// ParsedValue に追加
GroupValue(Array[GroupInstance])
```

#### 値ありグループ vs 値なしグループ

| | 値ありグループ | 値なしグループ |
|---|---|---|
| 例 | `--upstream u1` | `--rule` |
| インスタンス識別 | value がキー | キーなし |
| 同名再出現 | 同 value → マージ / 異 value → 新規 | 常に新規追加（append） |
| データモデル | dict 的（value で lookup + merge） | array 的（素直に append） |
| default | デフォルトインスタンスが暗黙的に開く | 構造的に不可能（GroupKind::Valueless） |
| env | デフォルト値のソース | 設計上不採用 |
| choices | グループ値の選択肢制約 | 設計上不採用 |
| value_name | ヘルプ表示用 | 設計上不採用 |

#### スコープルール

1. **グループ開始**: Group オプション出現でスコープが開く
2. **グループ閉じ**: 同レベル以上の Group オプション出現でスコープが閉じる
3. **`--`**: 全グループ閉じ。以降は root の rest
4. **opts の解決順序**: グループ内 → 親にフォールバック（サブコマンドの global_opts 継承と同じ）。子グループと親で同名オプションが存在する場合、子が親をシャドーイングする（意図的な設計）
   Design rationale: フォールバック解決された親オプションの値は子スコープの ParseResult に格納され、親スコープには伝播しない。したがって、親レベルの `required=true` オプションは親レベル（グループスコープの外）で明示的に指定する必要がある。子スコープ内でフォールバック経由で設定しても親の required チェックは満たされない。これはサブコマンドの global_opts と同じ挙動である
5. **positional の処理**: `Disallowed` → 位置引数出現で `UnexpectedPositional` エラー。`Fixed(defs)` → `defs.length()` 個を消費、超過は `TooManyPositional`、スコープ閉じ時に不足は `TooFewPositional`。`Variadic(def)` → 0 個以上を `positional` 配列に追加。位置引数消費時に `PositionalDef.choices` が非空であれば即座に choices チェックを行い、不一致時は `InvalidChoice` エラーを raise する
6. **`--help` / `--version`**: グループスコープ内でも通常通り `HelpRequested` / `VersionRequested` を raise。グループ固有のヘルプ概念は導入しない
7. **required + help_on_empty**: `help_on_empty` は `parse` の前にチェック（Phase 2.5 と同じ）。Group の `required=true` は「GroupValue が空配列でない」を要求。デフォルトグループ存在時は暗黙インスタンスにより通常満たされるが、`--no-xxx` でクリアされた場合は required 未充足でエラーとなる

Design rationale: 同レベルのグループ出現でスコープを閉じる設計は、暗黙的な区切りとしてユーザーに「次のグループが始まった」ことを自然に伝える。明示的な閉じタグ（`--end-upstream` 等）は冗長であり、CLIの慣習にも合わない。

Design rationale: 同名オプションのシャドーイングを意図的に許可する。子グループが親と同名のオプションを定義した場合、`scope_opts` の先頭走査により子の定義が優先される。これはサブコマンドの `global_opts` + `opts` で同名オプションが許容されている既存設計と一貫する。validate では禁止しない。

#### デフォルトグループ

値ありグループに `default` が設定されている場合、パーサはパース開始時点でデフォルトインスタンスのスコープが開いている状態からスタートする。

```
定義: --upstream は Group(group_kind=WithValue(default=Some("SSH_AUTH_SOCK")))
      --socket は upstream 内の Group

入力: --socket s1 a b --socket s2 c

暗黙的に: [--upstream SSH_AUTH_SOCK] --socket s1 a b --socket s2 c

結果:
upstream: GroupValue([
  { value: Some("SSH_AUTH_SOCK"), result: {
      socket: [
        { value: Some("s1"), positional: ["a", "b"] },
        { value: Some("s2"), positional: ["c"] },
      ]
  }}
])
```

明示的にデフォルト値と同じ値を指定した場合はマージされる。

Design rationale: デフォルトグループにより、最も一般的なケース（単一 upstream で socket だけ指定）を最も簡潔に書ける。authsock_filter のユースケースで `--upstream` を毎回指定する冗長さを排除する。

即時初期化の手順: 親の `parse_scope` ループ開始前に、`scope_opts[0..own_opts_count]`（自スコープの opts のみ）で `WithValue(default=Some(v))` を持つ Group を検索する。親レベルの Group のデフォルト初期化は親スコープの責務であり、子スコープでは行わない。見つかった場合、その Group に対して子スコープの `parse_scope` を呼び出す（`initial_result=None`, `initial_explicitly_set=None`, value=v）。子の `parse_scope` がトークンを消費し、親由来の Group（`resolved.index >= own_opts_count`）マッチまたは DoubleDash またはトークン終端で返る。戻り値の `(child_result, child_explicitly_set, next_i)` から GroupInstance を作成し、親のループは `next_i` からトークン処理を開始する。つまり、デフォルトグループは最初のトークンから即座にスコープを開き、最初の親由来 Group マッチまで全トークンを子スコープ内で処理する。子オプションが一つも使われなくても、デフォルトインスタンスは結果に含まれる。

#### 値ありグループのマージ

同じ値の Group インスタンスが複数回出現した場合、既存インスタンスのスコープを再開してマージする。

```
入力: --upstream u1 --socket s1 a --upstream u2 --socket s2 --upstream u1 --socket s3 b

結果:
upstream: GroupValue([
  { value: Some("u1"), result: {
      socket: [
        { value: Some("s1"), positional: ["a"] },
        { value: Some("s3"), positional: ["b"] },  ← マージ
      ]
  }},
  { value: Some("u2"), result: { socket: [{ value: Some("s2"), positional: [] }] } },
])
```

マージ時の挙動は通常のパースと同じ:
- Single: 後勝ち
- Append: 追加
- Flag: 後勝ち
- Count: 加算（既存の CountValue に加算）
- Group（子）: 同じルールで再帰的にマージ
- positional (Variadic): 追加
- positional (Fixed): マージ再開時は**遅延発火の完全置換**。マージ再開時は `initial_result.positional` をコピーして初期状態とする。リセット発火前はこのコピーがそのまま維持される。最初の位置引数が消費された時点でコピーをクリアし、0 から N 個を再消費する。位置引数が1つも消費されなければ前回の値を維持する（リセットは発火しない）。N 個未満のまま再度スコープが閉じた場合、リセットが発火済みならエラー、未発火なら前回の値が残っているためエラーにしない。DoubleDash 中断時もこの同じルールに従う（リセット発火済みなら `TooFewPositional`、未発火なら前回の値を維持）。Fixed の値は `ParseResult.positional` フィールドに格納される（`GroupInstance.result.positional`）
  - 例: `Fixed([SRC, DST])` で初回 `a b`、マージ再開時 `c d` → 結果は `["c", "d"]`（`["a", "b"]` は破棄）
  - 例: `Fixed([SRC, DST])` で初回 `a b`、マージ再開時に位置引数なし → 結果は `["a", "b"]`（前回の値を維持）

##### Fixed positional の状態遷移

| 状態 | 条件 | 結果 |
|------|------|------|
| 初回: N 個消費 | N 個全て消費 | 正常。positional = [v1, ..., vN] |
| 初回: N 個未満消費 | 1 個以上 N 個未満で<br>スコープ閉じ | `TooFewPositional` エラー |
| 初回: 0 個消費 | 位置引数なしで<br>スコープ閉じ | `TooFewPositional` エラー（Fixed は必ず N 個必要） |
| マージ再開: 0 個消費 | 位置引数なしで<br>スコープ閉じ | リセット未発火。前回の値を維持。エラーなし |
| マージ再開: N 個消費 | リセット発火、N 個全て消費 | 正常。positional = [w1, ..., wN]（完全置換） |
| マージ再開: N 個未満消費 | リセット発火、1 個以上 N 個未満で<br>スコープ閉じ | `TooFewPositional` エラー |
| DoubleDash 中断(初回) | Fixed 消費途中で `--` | `TooFewPositional` エラー |
| DoubleDash 中断(マージ再開) | リセット未発火で `--` | 前回の値を維持。エラーなし |
| DoubleDash 中断(マージ再開) | リセット発火済みで `--` | `TooFewPositional` エラー |

`TooFewPositional` の具体的な値: `expected = defs.length()`, `actual = 消費済みの位置引数数`。初回で 0 個消費の場合は `expected = defs.length()`, `actual = 0`。

「リセット発火」の判定は `parse_scope` 内のローカル変数 `positional_reset_fired : Bool` で管理する。初期値は `false`。マージ再開時に最初の位置引数を消費した時点で `true` に設定し、`initial_result.positional` をクリアする。

##### マージのフロー

```
parse_scope 内で Group オプション出現時:
  1. group_kind に応じて値を取得（WithValue: 次トークンまたは =value / Valueless: なし）
  2. Valueless の場合: 新規 GroupInstance を作成
  3. WithValue の場合:
     a. value で既存 GroupInstance を lookup（O(N) 線形走査）
     b. 見つかった場合: 既存の result を initial_result、既存の explicitly_set を initial_explicitly_set として parse_scope を再帰呼び出し（マージ再開後に指定しなかったオプションのデフォルト値が汚染されることを防ぐ）。explicitly_set 状態は `initial_explicitly_set` パラメータとして渡し、`parse_scope` の戻り値として返す。ParseResult のフィールドではないため、derive(Eq, Show, Debug) に影響しない
     c. 見つからなかった場合: initial_result=None, initial_explicitly_set=None で parse_scope を再帰呼び出し
  4. 戻り値の (ParseResult, explicitly_set, Int) から GroupInstance.result にセット/更新。explicitly_set は GroupInstance と共に保持する
```

##### explicitly_set の保持戦略

`explicitly_set` は `parse_scope` の呼び出し元がグループインスタンスと共に管理する。

- **WithValue グループ**: `parse_scope` の呼び出し元は `Map[String, Map[String, Bool]]` を保持する。キーはグループ値（value）、値はそのインスタンスの `explicitly_set`。マージ再開時に value で lookup し、既存の `explicitly_set` を `initial_explicitly_set` として渡す
- **Valueless グループ**: マージが発生しない（常に新規追加）ため、`explicitly_set` の引き継ぎは不要。`initial_explicitly_set` は常に `None` で呼ばれる

Design rationale: `explicitly_set` を `GroupInstance` のフィールドに含めない理由は、`GroupInstance` が `derive(Eq, Show, Debug)` を持ち、テストでの `inspect` やアサーションに使用されるため。内部状態をユーザー向け型に含めると、テストの期待値に explicitly_set のエントリが含まれ、テストが脆くなる。

#### inversion（`--no-xxx`）

`--no-xxx` は**そのスコープ内で解決された**当該オプション名に対応する GroupValue の配列全体を空にクリアする（全インスタンス破棄）。子グループのインスタンスも親と共に消滅する（ツリーごと破棄）。親由来の Group（`index >= own_opts_count`）に対する `--no-xxx` は子スコープでは処理されず、スコープ終了を発火して親に戻る。親スコープ内で inversion が処理される。

```
入力: --upstream u1 --socket s1 a --no-socket --socket s2 b --upstream u2 --socket s3

結果:
upstream: GroupValue([
  { value: Some("u1"), result: {
      socket: [
        // s1 は --no-socket でリセットされた
        { value: Some("s2"), positional: ["b"] },
      ]
  }},
  { value: Some("u2"), result: { socket: [{ value: Some("s3"), positional: [] }] } },
])
```

inversion はそのスコープ内のみに影響する。u2 の socket は u1 内の `--no-socket` に影響されない。

親グループの inversion 例:

```
入力: --upstream u1 --socket s1 a --upstream u2 --socket s2 b --no-upstream --upstream u3 --socket s3

結果:
upstream: GroupValue([
  // u1, u2 は --no-upstream でツリーごと破棄された（子 socket も消滅）
  { value: Some("u3"), result: { socket: [{ value: Some("s3"), positional: [] }] } },
])
```

##### デフォルトグループの inversion

`--no-upstream` でデフォルトインスタンスも含めてクリアされる。クリア後、デフォルトインスタンスは再生成しない。子オプション（`--socket` 等）は親にフォールバック解決を試みるが、親にも定義がなければ `UnknownOption` となる。再度 `--upstream` を明示すれば新しいスコープが開く。

デフォルトグループの子スコープ内で `--no-upstream` が出現した場合: `--upstream` は親由来 Group（`index >= own_opts_count`）なのでスコープ終了が発火し、デフォルトグループの子スコープが閉じる。親スコープに戻り、親が `--no-upstream` を処理して GroupValue をクリアする。クリア後の動作は上記の通り（デフォルトインスタンスは再生成しない、子オプションは `UnknownOption`）。

#### help 表示

罫線（`│`）でグループのネストを視覚的に表現する。

```
Options:
  --verbose               Verbose output
  --upstream HOST         Upstream server [default: SSH_AUTH_SOCK]
                          (--socket can be used without explicit --upstream)
  │ --socket PATH         Socket path
  │ │ <FINGERPRINT>...    Allowed key fingerprints
  │ --timeout VALUE       Per-upstream timeout
  --format VALUE          Output format
```

`Variadic` の位置引数は `...` 付き、`Fixed` は個別に表示:
```
  --mapping VALUE         Field mapping
  │ <SRC>                 Source field
  │ <DST>                 Destination field
```

Design rationale: 罫線 `│` (U+2502) は East Asian Width: Ambiguous であり、CJK 環境の一部ターミナルで2セル幅になる可能性がある。ASCII フォールバック (`|`) オプションの実装は Phase 4（ヘルプ生成）で対処する。Phase 3 のパーサ設計自体には影響しない。

#### OptDef フィールドと Group の関係

| フィールド | 値ありGroup | 値なしGroup |
|-----------|------------|------------|
| long/help | 有効 | 有効 |
| shorts | 有効 | 有効 |
| aliases | 有効 | 有効 |
| inversion | そのスコープ内の GroupValue をリセット | 同左 |
| env | デフォルト値のソース（下記参照） | 無効（validate で禁止） |
| choices | グループ値の選択肢制約 | 無効（validate で禁止） |
| value_name | ヘルプ表示用 | 無効（validate で禁止） |
| required | 1つ以上のインスタンス必須 | 同左 |
| visibility | 有効 | 有効 |

#### validate ルール（Group 固有）

| 検証 | エラー | 実装場所 |
|------|--------|----------|
| `global_opts` に Group を含む | `DefinitionError` | `validate_command` |
| サブコマンドを持つ CmdDef の `opts` に Group を含む | `DefinitionError` | `validate_command` |
| 同レベルに `WithValue(default=Some(_))` の Group が複数存在 | `DefinitionError` | `validate_opts`（配列全体走査） |
| Group 内の opts に `help` / `version` 名を含む | `DefinitionError` | `validate_opts`（再帰適用時） |
| Group 内の opts | `validate_opts` を再帰適用 | `validate_opts` |
| Valueless + `env` が `Some` | `DefinitionError` | `validate_opts` |
| Valueless + `choices` が非空 | `DefinitionError` | `validate_opts` |
| Valueless + `value_name` がデフォルト以外 | `DefinitionError` | `validate_opts` |

`validate_command_recursive` 内で `cmd.subcommands.length() > 0 && cmd.opts に Group が含まれる` をチェックする。同様に `cmd.global_opts に Group が含まれる` もチェックする。これらは `validate_opts` には委譲しない（`validate_opts` は opts 配列を受け取るだけで CmdDef の構造を知らないため）。`validate_opts` の責務は Group 内 opts の再帰的バリデーションと、同レベルのデフォルトグループ重複チェックに限定される。

Design rationale: Group のスコープ内トークンは可変長であり、`scan_for_subcommand` がサブコマンド名を探すためにスキップすべきトークン数を静的に決定できない。サブコマンドと Group は排他的に使用する制約とする。`global_opts` に Group を含めないルールと合わせて、CmdDef レベルでのサブコマンド探索はグループを意識する必要がない。

#### パース方式

既存の `parse` を内部関数 `parse_scope` にリファクタリングし、再帰呼び出しでグループを処理する。

##### parse_scope（内部関数）

```
parse_scope(tokens, start, scope_opts, own_opts_count, positional_spec, context, initial_result?, initial_explicitly_set?)
  -> (ParseResult, Map[String, Bool], Int) raise ParseError
```

| パラメータ | 説明 |
|-----------|------|
| `tokens` | tokenize 済みトークン列（全体を共有） |
| `start` | 処理開始インデックス |
| `scope_opts` | このスコープで有効なフラット opts（Group 内 opts + 親 opts を結合。Group 内 opts を先頭に置くことで自然にフォールバック解決を実現。名前解決は先頭優先: `resolve_long` / `resolve_short` は配列の先頭から走査して最初にマッチしたものを返す） |
| `own_opts_count` | `scope_opts` の先頭何個が自スコープの opts か。required/choices チェックはこの範囲のみに適用。**スコープ終了判定にも使用**: `resolved.index >= own_opts_count` の Group オプションが出現した場合、方向（Normal/Inverted）に関係なくスコープ終了を発火する |
| `positional_spec` | このスコープの位置引数受付仕様（`Positional` 型） |
| `context` | エラーメッセージ用のグループパス文字列。ルートでは `""`、子スコープでは親の context に `" / --group_name value"` を結合して渡す |
| `initial_result?` | マージ時に既存 ParseResult を引き継ぐためのパラメータ |
| `initial_explicitly_set?` | マージ時に既存の explicitly_set 状態を引き継ぐためのパラメータ。None なら空マップで初期化 |

戻り値:
- `ParseResult`: このスコープのパース結果
- `Map[String, Bool]`: このスコープの explicitly_set 状態
- `Int`: 次に処理すべきトークンインデックス（呼び出し元がここから処理を継続）

既存の `parse(opts, args)` はこの関数のラッパーとなる:
```
pub fn parse(opts, args, positional_spec?) -> ParseResult raise ParseError:
  tokens = tokenize(args)
  let ps = positional_spec.or(Variadic(PositionalDef::new(name="ARG", help="")))
  (result, _, end_i) = parse_scope(tokens, 0, opts, opts.length(), ps, "", None, None)
  //                                      own_opts_count = opts.length() = scope_opts.length()
  //                                      全ての Group は index < own_opts_count なのでスコープ終了しない
  if end_i < tokens.length() && tokens[end_i] == DoubleDash:
    result.rest = tokens[end_i+1..] から Positional 値を収集
  // Design rationale: `--` 以降のトークンは `positional_spec` の制約を受けず、無条件に `rest` に格納する。
  // これは Phase 2 の既存動作と一致する。`Positional::Disallowed` のスコープでも `-- foo bar` は
  // `rest = ["foo", "bar"]` となり、`UnexpectedPositional` にはならない。
  // `rest` は「パーサが解釈しない残余引数」であり、子プロセスへの透過的な引数渡し等に使用されることを想定している。
  // required/choices チェック
  return result
```

##### extract_groups（ヘルパー関数）

```
extract_groups(opts) -> Array[OptDef]:
  opts.filter(fn(o) { match o.kind { Group(..) => true; _ => false } })
```

opts 配列から `OptKind::Group` であるエントリを抽出する。`validate_opts` でのグループ関連バリデーション（同レベルのデフォルトグループ重複チェック等）に使用する。

Design rationale: スコープ終了判定は `own_opts_count` によるインデックスベース判定に移行したため、`extract_groups` はスコープ制御には使用しない。

Design rationale: `parse` をリファクタリングして `parse_scope` を導入することで、グループのスコープ再帰と既存のトークン消費ロジックを共有する。トークン列全体を共有しインデックスで管理することで、コピーのオーバーヘッドを避ける。スコープ終了判定は `own_opts_count` によるインデックスベース方式を採用。resolve 結果のインデックスが `own_opts_count` 以上なら親由来の Group であり、スコープ終了を発火する。この方式は参照同一性や名前ベースの containment チェックが不要で、シャドーイング（同名 Group が子に定義されたケース）でも正しく動作する。

##### Group オプション遭遇時の処理フロー

```
parse_scope 内でトークンを resolve した結果:

  A. Group オプションで resolved.index >= own_opts_count（親由来の Group）
    → スコープ終了（方向に関係なく、トークンを消費せずに返す）
    Design rationale: 子スコープの ParseResult には親 Group の GroupValue が存在しないため、
    子スコープ内での inversion 処理は意味をなさない。トークンを消費せずに返すことで、
    親スコープが Normal（子スコープ再開）か Inverted（GroupValue クリア）かを適切に判断できる。

  B. Group オプションで resolved.index < own_opts_count（自スコープの Group）
    → 子スコープ開始:
      1. group_kind に応じて値を取得（WithValue: 次トークンまたは =value / Valueless: なし）
      2. Valueless の場合: 新規 GroupInstance を作成
      3. WithValue の場合:
         a. value で既存 GroupInstance を lookup
         b. 見つかった場合: 既存の result を initial_result、既存の explicitly_set を initial_explicitly_set として渡す（マージ）
         c. 見つからなかった場合: initial_result=None, initial_explicitly_set=None（新規）
      4. child_opts = group.opts + scope_opts（Group 内 opts を先頭に結合。フォールバック解決された親オプションの値は子スコープの ParseResult に格納される）
      5. child_context = if context == "" { "--" + opt.long + (value があれば " " + value) } else { context + " / --" + opt.long + (value があれば " " + value) }
         (child_result, child_explicitly_set, next_i) = parse_scope(tokens, i, child_opts, group.opts.length(), group.positional, child_context, initial_result, initial_explicitly_set)
      6. GroupInstance { value, result: child_result } を GroupValue に追加/更新。child_explicitly_set も GroupInstance と共に保持する
      7. i = next_i で処理続行

  C. 非 Group オプション
    → 通常の parse 処理
```

Design rationale: フォールバック解決された親オプションの値が子スコープの ParseResult に格納される設計は意図的である。これはサブコマンドの `global_opts` が `CommandResult.result`（サブコマンドの ParseResult）に格納される動作と一致する。親スコープの ParseResult を汚染しないことで、各スコープの結果が自己完結する。

##### スコープ終了条件

`parse_scope` は以下の条件でループを抜ける:
- トークン列の終端に到達
- `DoubleDash` に遭遇 → `DoubleDash` 以降のトークンをパースせず、戻り値のインデックスを `DoubleDash` 位置に設定して返す。DoubleDash 遭遇時もスコープ終了と同じルールに従う: Fixed positional のリセットが発火済み（位置引数を1つ以上消費済み）なら N 個揃っているかチェックし、不足なら `TooFewPositional`。リセット未発火なら前回の値を維持しエラーにしない。呼び出し元も同じインデックスを受け取り、`DoubleDash` を検知して再帰を巻き戻す。最終的にルートの `parse` が `DoubleDash` 以降を `rest` に格納する（下記「DoubleDash 巻き戻しプロトコル」参照）
- 現在のトークンが **Group オプション**であり、`resolve_long` または `resolve_short` の結果の `index >= own_opts_count`（親由来の Group）でマッチした場合 → 方向（Normal/Inverted）に関係なくトークンを消費せずに返す。自スコープの Group（`index < own_opts_count`）ではスコープ終了は発火しない

##### DoubleDash 巻き戻しプロトコル

`parse_scope` が `DoubleDash` に遭遇した場合、以降のトークンを処理せず、戻り値のインデックスを `DoubleDash` の位置に設定して返す。呼び出し元の `parse_scope` は戻り値のインデックスが `DoubleDash` を指していることを検知し、子スコープの結果を保存した後、自身も同じインデックスで返す。この巻き戻しがルートまで伝播する。

```
ルート parse:
  (result, _, end_i) = parse_scope(tokens, 0, ...)
  if end_i < tokens.length() && tokens[end_i] == DoubleDash:
    result.rest = tokens[end_i+1..] から Positional 値を収集
```

Design rationale: `DoubleDash` を特殊な戻り値（例: `ScopeExit` enum）で表現する方法も検討したが、インデックスベースの方がシンプルで十分。`parse_scope` は常に「次に処理すべきインデックス」を返すため、それが `DoubleDash` 位置なら呼び出し元が判断できる。

DoubleDash による早期リターン前に、そのスコープの required/choices チェック（`scope_opts[0..own_opts_count]` に対して）を実行する。これにより、グループスコープ内の必須オプション未指定が DoubleDash で見逃されることを防ぐ。

##### 動作検証（own_opts_count による正しいスコープ制御）

以下の定義を前提とする:
- ルート opts: `[--verbose (Flag), --upstream (Group)]`
- upstream opts: `[--socket (Group), --timeout (Single)]`
- socket opts: `[--fingerprint (Single)]`

```
ルート parse_scope:
  scope_opts = [--verbose, --upstream]
  own_opts_count = 2 (= scope_opts.length())
  → --upstream: index=1, < 2 → 自スコープの Group → Case B（子スコープ開始）✓

upstream の parse_scope:
  scope_opts = [--socket, --timeout, --verbose, --upstream]
  own_opts_count = 2 (upstream.opts = [--socket, --timeout])
  → --socket: index=0, < 2 → 自スコープの Group → Case B（子スコープ開始）✓
  → --upstream: index=3, >= 2 → 親由来の Group → Case A（スコープ終了）✓
  → --no-upstream: index=3, >= 2 → 親由来の Group（Inverted） → Case A（スコープ終了）✓
  → --verbose: index=2, >= 2 → 親由来だが非 Group → Case C（通常処理）✓

socket の parse_scope:
  scope_opts = [--fingerprint, --socket, --timeout, --verbose, --upstream]
  own_opts_count = 1 (socket.opts = [--fingerprint])
  → --fingerprint: index=0, < 1 → 非 Group → Case C（通常処理）✓
  → --socket: index=1, >= 1 → 親由来の Group → Case A（スコープ終了）✓
  → --upstream: index=4, >= 1 → 親由来の Group → Case A（スコープ終了）✓

シャドーイング例:
  ルートに --timeout (Single) と --upstream (Group)
  upstream.opts に --timeout (Group, 親をシャドーイング) と --socket (Group)

  upstream の parse_scope:
    scope_opts = [--timeout(Group/child), --socket, --timeout(Single/parent), --upstream]
    own_opts_count = 2
    → --timeout: resolve は index=0（先頭優先）, < 2 → 自スコープの Group → Case B ✓
    → --socket: index=1, < 2 → 自スコープの Group → Case B ✓

  socket の parse_scope:
    scope_opts = [socket.opts..., --timeout(Group/child), --socket, --timeout(Single/parent), --upstream]
    own_opts_count = socket.opts.length()
    → --timeout: resolve は index=socket.opts.length()（子のGroup版）, >= own_opts_count → Case A ✓
```

旧設計（`exit_groups` 方式）では、containment 判定に名前ベースを使うとシャドーイング時に誤発火し、参照ベースを使うと判定基準が言語仕様に依存する問題があった。`own_opts_count` によるインデックスベース判定はこれらの問題を根本的に解消する。

##### LongOptWithValue 形式のグループ

`--upstream=u1` (`LongOptWithValue`) は `--upstream u1` (`LongOpt` + 次トークン) と等価に処理する。`GroupKind::Valueless` のグループに `=value` 形式が使われた場合は、Flag への `=value` と同様にエラーとする。

##### Group + ショートオプション

- `GroupKind::WithValue`: ShortOpts 処理は Single と同様（残り文字列を値として消費、なければ次トークン）。その後スコープが開く
- `GroupKind::Valueless`: Flag と同様に扱い、スコープが開く

結合された短オプション列 `-gab`（g=Valueless Group, a,b=非Group）の場合、ShortOpts トークン全体が現在のスコープで処理される。g のフラグ処理完了後、残り文字 `a`, `b` も同じスコープで処理される。その後、次のトークンから g のグループスコープが開く。つまり ShortOpts 内では途中でのスコープ遷移は発生しない。

ShortOpts 内ではスコープ開始もスコープ終了も発火しない。全文字の処理が完了した後に、Group のスコープが次のトークンから開く。したがって、`-gab` で `g` が Valueless Group の場合、`a`, `b` は現在の（親）スコープの opts で解決される。`a`, `b` が g のグループ内にしか定義されていない場合は `UnknownOption` になる。また、親由来 Group のショートオプションが ShortOpts 結合内に現れた場合も、スコープ終了は発火せず、通常処理（フラグトグル等）として扱われる。

##### Group + `--help` / `--version`

グループスコープ内での `--help` / `--version` は、既存の parse の特殊処理と同じく `HelpRequested` / `VersionRequested` を raise する。グループ固有のヘルプという概念は導入しない。Group 内の opts に `help` / `version` という名前の OptDef を定義することは validate で禁止する（validate ルール参照）。

##### required/choices チェックと Group

- Group 内のオプションの required/choices チェックは `parse_scope` 内で独立して行われる。チェック対象は `scope_opts[0..own_opts_count]`（= `group.opts` 相当）のみであり、`scope_opts` に含まれる親の opts に対しては行わない（親の opts の required/choices は親スコープの責務）。（注意: 親由来オプションがフォールバック解決されて子スコープの ParseResult に値が格納されても、親スコープの required チェックには反映されない。スコープルール 4 の Design rationale 参照）
- 親 parse の required チェックでは、Group オプション自体の `required`（GroupValue が空配列でないこと）のみをチェック
- デフォルトグループが存在する場合、暗黙インスタンスが生成されるため required は通常満たされる。ただし `--no-xxx` によるクリアでデフォルトインスタンスも含めて破棄された場合は、GroupValue が空配列となり required 未充足でエラーとなる

Design rationale: 既存の required チェック（Phase 2）は `explicitly_set` マップ基準で「ユーザーが明示的にオプションを操作したか」を判定する。Group の required は異なる基準（インスタンス数 > 0）を採用する。これは Group がコンテナであり、その存在自体が意味を持つため。Group 内の子オプションの required は従来通り `explicitly_set` 基準で判定される。
- Group 値の choices チェック: `GroupKind::WithValue` + `choices` 設定時、各 GroupInstance の value が choices に含まれるかを `parse_scope` 内で即座にチェック。choices チェックも Group 内の opts に対してのみ行う

#### ParseError 追加バリアント

```moonbit
///|
// ParseError に追加
/// 位置引数が多すぎる
TooManyPositional(context~ : String, expected~ : Int, actual~ : Int)
/// 位置引数が不足
TooFewPositional(context~ : String, expected~ : Int, actual~ : Int)
/// 位置引数を受け付けないコンテキストに位置引数が渡された
UnexpectedPositional(context~ : String, value~ : String)
```

`context` にはグループパス（例: `"--upstream u1 / --socket s1"`）を含め、ネスト内のどこでエラーが起きたかをユーザーに伝える。

#### アクセサ

```moonbit
///|
pub fn ParseResult::get_group(self : ParseResult, name : String) -> Array[GroupInstance]
```

GroupInstance の `result` は `ParseResult` なので、既存のアクセサ（`get_flag`, `get_string`, `get_list`, `get_group` 等）をそのまま再帰的に使用できる。グループが未指定の場合は空配列を返す（`get_list` が `[]` を返すのと同じ慣例）。`WithValue(default=Some(v))` の場合、明示的な指定がなくてもデフォルトインスタンスが結果に含まれる。

#### apply_defaults との相互作用

| OptKind | 正方向の動作 | 反転方向の動作 |
|---|---|---|
| Group(WithValue) | Group 定義の `default` を指定値に上書き | Group 定義の `default` を `None` にクリア（デフォルトインスタンス無効化） |
| Group(Valueless) | 無視（値なし） | 無視 |

- `apply_defaults` は Group オプションのデフォルト値（`GroupKind::WithValue` の `default`）のみを更新する
- Group の `env` は `apply_defaults` で解決される。`apply_defaults` は `GroupKind::WithValue` の `default` 値を環境変数の値で上書きする。これにより、環境変数でデフォルトグループのインスタンス値を設定できる。Group 内の子オプションの `env` は Phase 2 と同じく `apply_defaults` で個別に解決される
- Group 内の子オプションのデフォルト値は `apply_defaults` の対象外。子オプションのデフォルトは OptDef 内に直接定義する
- グループ構造を含む引数列（`["--upstream", "u1", "--socket", "s1"]`）を `apply_defaults` に渡した場合、`--upstream` の default 値のみが `u1` に上書きされ、`--socket` 以降は未知オプションとして無視される

Design rationale: `apply_defaults` はオプション定義のデフォルト値を書き換える純粋関数であり、グループのスコープパースを行わない。グループの完全なパースは `parse` / `parse_scope` の責務とする。

##### `copy_opt_kind` の Group 対応

`apply_defaults` の内部で使用する `copy_opt_kind` は、Group バリアントでは `opts` 配列の deep copy が必要。各子 OptDef の `kind` も再帰的に `copy_opt_kind` を適用する。

```
copy_opt_kind(Group(group_kind~, opts~, positional~)):
  copied_opts = opts.map(fn(o) { { ..o, kind: copy_opt_kind(o.kind) } })
  copied_positional = match positional {
    Fixed(defs) => Fixed(defs.map(fn(d) { { ..d, choices: d.choices.copy() } }))
    Variadic(def) => Variadic({ ..def, choices: def.choices.copy() })
    Disallowed => Disallowed
  }
  Group(group_kind~, opts=copied_opts, positional=copied_positional)
```

Design rationale: `apply_defaults` は OptDef 配列を変異させるため、Group 内の opts も独立コピーが必要。コピーしないと複数回の `apply_defaults` 呼び出しで子オプションのデフォルト値が汚染される。

### Phase 4: ヘルプ生成 + completion

- `--help` セクション分けヘルプテキスト生成
- bash / zsh / fish 補完スクリプト生成
- サブコマンド一覧セクション
- `Visibility` によるヘルプ / 補完の出し分け

### Phase 5: 高度な機能

- ~~`Nary`~~ → `Append(n~)` として統合済み（セクション 3.1 参照）。~~`TupleListValue`~~ → `ParseResult::get_chunks` で実現済み（セクション 3.9 参照）
- フラグ間制約: `xor`（排他）, `and`（依存）, `exactly_one`
- あいまいプレフィックスマッチ（`--dry` → `--dry-run`、一意の場合のみ）
- did you mean? サジェスト（編集距離ベース）
- FSM ベースコマンド解決（静的な曖昧さ検出）
- 環境変数プレフィックス自動バインド（`MYAPP_` → 全オプション）
- i18n サポート

### 拡張時の型設計への影響

- ~~`CmdDef` 型の追加~~ → Phase 2.5 で実装済み（セクション 7 Phase 2.5 参照）
- ~~`ParseResult` に `commands : Array[String]` フィールドを追加~~ → `CommandResult` 型の `command` フィールドとして Phase 2.5 で実装済み
- ~~`ParseError` に `UnknownCommand(String)` バリアントを追加~~ → Phase 2.5 で実装済み
- ~~`ParseError` に `VersionRequested` バリアントを追加~~ → Phase 2.5 で実装済み（`--help` と同じ設計思想で `parse` 内で処理）
- `ParsedValue` に値の出所（`Source` enum: `Default | Explicit | Inherited`）を付与する拡張を検討中。これにより「ユーザーが明示的にフラグを指定したか」と「デフォルト値が活きているだけか」を区別可能にする
- ~~`ParsedValue` に `TupleListValue` を追加~~ → `Append(n~)` + `get_chunks` で実現済み
- Phase 3 で `OptKind` に `Group` バリアント、`ParsedValue` に `GroupValue` バリアントを追加
- Phase 3 で `PositionalDef`, `Positional`, `GroupKind`, `GroupInstance` 型を新規追加
- Phase 3 で `CmdDef` に `positional_spec : Positional` フィールドを追加
- Phase 3 で `ParseResult::get_group` アクセサを追加
- Phase 3 で `ParseError` に `TooManyPositional`, `TooFewPositional`, `UnexpectedPositional` バリアントを追加

---

## 8. 不採用の設計とその理由

### Applicative 合成（bpaf / optparse-applicative 方式）

bpaf や optparse-applicative が採用する Applicative ファンクタベースの合成パターン。パーサの型安全な合成と引数順序の構造的自由度保証に優れる。

**不採用理由**: MoonBit には Higher-Kinded Types（HKT）がなく、Applicative ファンクタを型レベルで表現できない。ランタイムで同等の合成は可能だが、型安全性の恩恵が薄れるため、データ指向（`Array[OptDef]`）のシンプルなアプローチを採用した。

### derive マクロベースの定義（clap derive / kong struct tag 方式）

struct にアノテーションを付けてコンパイル時にパーサを生成する方式。

**現状**: MoonBit には derive マクロのカスタム定義機構がない（`derive(Eq, Show)` 等の組み込みのみ）。ただし以下の仕組みを組み合わせた外部コード生成方式は技術的に実現可能:

- **ユーザー定義 attribute**: `#cli.opt(long="verbose", help="...")` 等のアノテーションを struct に付与可能（コンパイラは無視、外部ツールがソースをパースして利用）
- **`pre-build`**: `moon.pkg` の `pre-build` フィールドで `moon build/check/test` 前に任意コマンドを実行可能。コードジェネレータを組み込める

将来のアイデアとして、`Array[OptDef]` ベースの API から型安全な struct + アクセサを生成するツールを `pre-build` で実行する構成が考えられる。現時点ではランタイム API を優先する。

### 値の型パラメータ化（`OptDef[T]`）

各オプションにジェネリック型を持たせて型安全にする方式。

**不採用理由**: 異なる型の `OptDef[T]` を 1 つの `Array` に入れられない（MoonBit には existential types がない）。Trait object 相当の仕組みでラップする方法もあるが、複雑さに見合わない。代わりに `ParsedValue` enum で値を包み、`get_flag` / `get_string` 等の型安全アクセサで抽出する方式を採用した。

### オプション値の即時パース（parse 時に Int / Bool 等に変換）

パース時に文字列から各型への変換を行う方式。

**不採用理由**: `apply_defaults` で多段畳み込みを行う設計では、`OptKind` 内のデフォルト値（`Flag(default~)`, `Single(default~)`, `Append(defaults~)`）を文字列/Bool のまま保持する方が単純。型変換は最終的な `get_int` 等のアクセサ呼び出し時に行う。変換エラーもアクセサ側で `None` を返すことで一貫したエラーハンドリングが可能。

### `--key=value` を独立した型で表現

`=` 区切りの引数形式を専用のバリアントで表現する方式。

**不採用理由**: `--key=value` は `--key value` と同義であり、パーサの字句解析段階で分割すれば十分。型レベルで区別する必要がない。Phase 2 のパーサ実装で `=` を含む引数を検出して分割する処理を入れる。

---

## Phase 4: API 再設計 — コンビネータ + Reducer パターン

### 9. 背景・動機

Phase 1-3 は PoC（概念実証）として要件の実現可能性を検証した。OptKind enum ベースの設計は要件検証には十分だったが、以下の課題が浮上した:

- ParsedValue が全て String ベース（Flag/Count 以外）で、ユーザーが結果取得時に型変換を行う必要がある
- "Parse, don't validate" の原則に反する二度手間が発生している
- OptKind の各バリアントが独立しており、合成や拡張に制約がある

Phase 4 では、コンビネータ合成と Reducer パターンを軸に API を再設計する方向性を模索する。

---

### 10. 型付きアクセサ Opt[T] の導出

#### 10.1 heterogeneous container 問題

ParsedValue にジェネリクスを適用する最初の発想（`ParsedValue[T]`）は、`Map[String, ParsedValue[???]]` で異なる `T` を混在できないという問題に直面する。MoonBit には mapped types、マクロ、trait object、Any 型がなく、型レベルでの自動導出は不可能。

#### 10.2 Opt[T] — 型付きアクセサ（レンズ）

解決策として、`Opt[T]` を「値を保持しない型付きアクセサ」として設計する方向性が見えた:

- 内部の `ParseResult` は String ベースのまま維持する
- `Opt[T]` は取り出し時に parser を適用して `T` に変換する
- `Opt[T]` 自体は immutable で値を保持しない — 定義情報と変換ロジックのみ

```moonbit
// Opt[T] は値を保持しない。定義情報 + 変換関数のみ
struct Opt[T] {
  initial : T
  reducer : (T, String?) -> T  // raise ParseError
  // + メタ情報
}

// 使用時: ParseResult から型付きで取り出す
let port : Int = result.get(port_opt)
let verbose : Bool = result.get(verbose_opt)
```

Design rationale: 内部を String ベースに保つことで、apply_defaults の多段畳み込み等の既存設計と整合性を維持しつつ、ユーザー向け API では型安全なアクセスを提供する二層構造となる。MoonBit の型システム制約下で heterogeneous container 問題を回避する現実的なアプローチ。

---

### 11. コンビネータ合成による OptKind の置換

OptKind enum を廃止し、プリミティブ + コンビネータで合成する設計が可能であることが見えた。

#### 11.1 プリミティブ

```moonbit
// 基本型
opt::int(long="port")              // Opt[Int]
opt::string(long="name")           // Opt[String]
opt::bool(long="verbose")          // Opt[Bool]
opt::path(long="config")           // Opt[Path]
opt::regex(long="pattern")         // Opt[Regex]

// カスタム型
opt::custom(parser=(s) -> MyType::parse(s))  // Opt[MyType]
```

#### 11.2 合成コンビネータ

```moonbit
// 蓄積
opt::append(opt::string)           // Opt[Array[String]]

// 固定長複数値
opt::tuple(opt::string, opt::int)  // Opt[(String, Int)]
opt::append(opt::tuple(opt::int, opt::int, opt::int))
                                   // Opt[Array[(Int, Int, Int)]]

// 選択（先頭トークンで区別）
opt::or(rgb, css_color_string)     // Opt[Color]
```

#### 11.3 tuple の内部表現

~~内部的には tuple2（cons cell / HList 相当）のみで任意長を表現する:~~

~~`1個: tuple(int, nil)` / `2個: tuple(int, tuple(string, nil))` / `3個: tuple(int, tuple(int, tuple(int, nil)))`~~

**→ 左畳み込みに変更:**

内部的には `tuple(pre, cur)` の 2 引数のみで任意長を表現する:

```
1個: tuple(tuple(none, o1))                         -- tuple(none, o) で single 相当
2個: tuple(tuple(none, o1), o2)
3個: tuple(tuple(tuple(none, o1), o2), o3)
```

Design rationale: 右畳み込み（cons cell）から左畳み込みに変更した理由:
- パースはトークンを左から右に消費する
- 左畳み込みなら消費順と構造が一致し、パース中に逐次的に結果を積み上げられる
- 右畳み込みだと末端まで展開してから戻る形になり不自然

これにより内部表現は `tuple(pre, cur)` の 2 引数だけで任意長を表現。`tuple(none, o)` で single も統一。

ユーザー API は `tuple2` / `tuple3` / `tuple4` / `tuple5` を提供し、平坦な型 `(A, B, C)` を返す。内部 1 種類 + 表面 N 種類の責務分離。

#### 11.4 or コンビネータ

`or(rgb, css_color_string)` は複数パーサの試行。値を受けるオプションの数が固定であるという制約のもとで、先頭トークンでの部分マッチングに曖昧さがなければ許容される方向。

---

### 12. 核心: Reducer パターンによる OptKind 完全統一

parser のシグネチャを `(pre: T, cur: String?) -> T` にすることで、全 OptKind が統一的に表現できることがわかった。

```moonbit
struct Opt[T] {
  initial : T
  reducer : (T, String?) -> T  // raise ParseError
  // + メタ情報 (long, short, env, help, required, inversion, visibility, completion_hint, ...)
}
```

#### 12.1 各 OptKind の Reducer 表現

| 現 OptKind | initial | reducer | cur の役割 |
|------------|---------|---------|-----------|
| Flag | `false` | `(_, None) -> true` | None（値なし） |
| Count | `0` | `(n, None) -> n + 1` | None（値なし） |
| Single(Int) | `None` | `(_, Some(s)) -> Some(parse_int(s))` | Some（次トークン） |
| Append(String) | `[]` | `(arr, Some(s)) -> [...arr, s]` | Some（次トークン） |
| OptionalValue | `None` | 値あり: `(_, Some(s)) -> Some(s)`, 値なし: `(_, None) -> Some(implicit)` | Some or None |

`cur: String?` で値を取らない Flag/Count（`None`）と値を取る Single/Append（`Some`）を統一的に扱える。

#### 12.2 プリミティブは custom の特殊化

`opt::int` は `opt::custom(parse_int)` のシンタックスシュガーとなる。全ての組み込み parser は `custom` の特殊化であり、特別扱いする必要がない。

Design rationale: reducer パターンは畳み込み（fold）の一般化であり、Phase 1-3 の apply_defaults と同じ思想を個々のオプション値レベルに適用したもの。全 OptKind を単一のインターフェースで表現できるため、パーサコアの分岐が消え、新しい値パターンの追加がコンビネータの追加だけで完結する。

---

### 13. 各言語ライブラリの型変換方式調査

#### 13.1 比較表

| ライブラリ | 型変換方式 | バリデーション | 補完候補 |
|-----------|-----------|-------------|---------|
| clap (Rust) | ValueParser trait | value_parser! マクロ | ValueHint enum |
| bpaf (Rust) | FromStr + .parse() コンビネータ | .guard(fn, msg) | .complete() |
| cobra (Go) | 型別メソッド IntVar/StringVar | Args バリデータ関数 | ValidArgsFunction コールバック |
| kong (Go) | struct タグ + MapperFunc | enum タグ | Completer interface |
| click (Python) | ParamType クラス (INT/FLOAT/Path/Choice) | callback 引数 | shell_complete() メソッド |
| swift-argument-parser | ExpressibleByArgument protocol | transform クロージャ | CompletionKind enum |
| yargs (JS) | .number()/.boolean() | .check() コールバック | completion コマンド |
| optparse-applicative (Haskell) | ReadM monad | ReadM 内で検証 | bashCompleter/completeWith |

#### 13.2 設計パターン分類

- **パターン A（型システム）**: clap, swift-argument-parser, typer — trait / protocol / 型アノテーションで変換を駆動
- **パターン B（コールバック/関数）**: click, yargs, cobra — 関数やコールバックで明示的に変換
- **パターン C（文字列+後処理）**: argparse, commander — パース結果は文字列、ユーザーが後で変換
- **パターン D（コンビネータ）**: bpaf, optparse-applicative — パーサ自体を合成・変換する

本設計は **A+D のハイブリッド**（trait で型変換 + コンビネータで合成 + reducer で統一）の方向性。MoonBit の trait を型変換の拡張ポイントとし、コンビネータで合成、reducer で全パターンを統一する。

---

### 14. メタ情報の分離

#### 14.1 reducer で表現できるもの

- 型変換（String → T）
- choices バリデーション
- or（複数パーサの試行）
- tuple（固定長複数値）

#### 14.2 reducer 外のメタ情報

以下は reducer のロジックではなく、パーサの振る舞いや表示に関わる定義情報として `Opt[T]` のフィールドに残る:

- `long`, `short`, `aliases` — 名前解決
- `env` — 環境変数フォールバック
- `required` — 必須制約
- `inversion` — `--no-xxx` 等の反転フラグ生成
- `help`, `visibility` — ヘルプ/補完での表示制御
- `completion_hint` — 補完候補の種別（File / Dir / Custom 等）
- `value_name` — ヘルプ表示用のプレースホルダ（例: "PORT", "PATH"）

---

### 15. MoonBit 型システムの制約と設計判断

#### 15.1 調査結果

| 機能 | MoonBit での状況 |
|-----|----------------|
| ジェネリクス | あり（HKT なし） |
| trait | あり（associated types なし） |
| derive | あり（カスタム derive 不可） |
| マクロ | なし |
| mapped types / conditional types | なし |
| trait object / Any | なし |
| heterogeneous collections | 不可 |

#### 15.2 制約から導かれる設計方針

「定義 struct から結果 struct を自動導出」は不可能。したがって:

- **外部表現**: `Opt[T]` 型付きアクセサでユーザーに型安全なインターフェースを提供
- **内部表現**: `OptDef`（型消去済み）→ `CmdDef` → `parse()` → `ParseResult`（String ベース）
- **接続**: `Opt[T].get(result)` で reducer を適用し `T` を返す

この二層構造が MoonBit の型システム制約下での現実的な落としどころとなる。

---

### 16. 設計の全体像

```
[ユーザー API]
  opt::int, opt::string, opt::bool, opt::path, opt::custom
  opt::append, opt::tuple2/3/4/5, opt::or
  opt::flag, opt::count
  Opt[T] { initial, reducer, meta }

[メタ情報]
  long, short, aliases, env, required, inversion
  help, visibility, value_name, completion_hint

[内部表現]
  OptDef (型消去済み) → CmdDef → parse() → ParseResult (String ベース)

[取り出し]
  Opt[T].get(result) → reducer 適用 → T
```

Design rationale: ユーザーは `Opt[T]` を通じて型安全な定義と取得を行い、内部では型消去された `OptDef` / `ParseResult` でパーサコアのロジックを単純に保つ。Phase 1-3 の `ParsedValue` enum + `get_flag` / `get_string` アクセサの延長線上にあるが、型変換の責務を定義側（`Opt[T]` の `reducer`）に移すことで、アクセサの型ごとの分岐を不要にする。

---

### 17. 未解決課題

1. **Group のコンビネータ表現** → **解決** — Group は子スコープ + positional を持つ特殊なオプション。reducer パターンにどう統合するか検討が必要

   **回答:** コンビネータ合成 + append + メタフラグで表現できる:

   ```
   namedGroup("upstream",
     path("path", required=true),
     int("timeout"),
     namedGroup("socket",
       path("path", required=true),
       rest("filters", string)
     )
   )
   ```

   - `namedGroup` は実質的に `append` の特殊化
   - グループ化は meta 側に group フラグを持てば表現可能
   - append の中身がコンビネータ合成 Opt で表現可能なら、名前付き (namedGroup) と名前なし (append) の区別も reducer で統一的に表現できる可能性がある

   namedGroup の挙動:
   - 出現するたびに新しいスコープを開く
   - 値あり (WithValue 相当): `namedGroup("upstream", ...)` → `--upstream u1` で "u1" をキーにスコープ開始
   - 値なし (Valueless 相当): namedGroup の名前だけでスコープ開始
   - 子要素は合成 Opt で定義、スコープ内でパースされる
   - 同じ値のインスタンスが再出現したらマージ（reducer の pre に前回結果が渡される）

2. **inversion の reducer 統合** → **解決** — `--no-xxx` 時に reducer に何を渡すか。`pre` をリセットして `initial` に戻す方式、別の reducer を呼ぶ方式、あるいは reducer の第3引数として `inverted: Bool` を渡す方式が考えられる

   **回答:** reducer の pre を initial にリセットするだけ。

   `--no-upstream` が出現したら:
   1. 該当 Opt の値を `initial` に戻す
   2. reducer は呼ばない（値消費なし）

   これは inversion 用の特別な処理ではなく、「pre を initial にリセット」という汎用操作。メタ情報として `inversion: FlagInversion?` を持ち、`--no-xxx` トークンを検出したら initial リセットを発動する。

3. **tuple の or での曖昧さ判定** → **解決** — 先頭トークンだけで判定可能かの静的チェックアルゴリズム。曖昧な場合のエラー報告も含む

   **回答:** 貪欲マッチ + 段階的絞り込みアルゴリズム:

   各 or 候補を 1 トークン目から順に試行する:

   1. 全候補 NG → パースエラー（引数が足りないか要件に合う引数ではない）
   2. 1 個だけ OK、他 NG → OK（確定）
   3. 2 個以上 OK → n+1 個目の opt で絞り込み:
      - 全候補の n+1 個目の opt が全て無し → パースエラー（曖昧です）
      - tuple の最後まで OK が 1 つだけ → OK（確定）
      - tuple の最後まで OK が複数 → パースエラー（曖昧です）

   つまり各トークンを消費するたびに候補を絞り込み、一意に確定するか最後まで曖昧なままかを判定する。

4. **completion hint の設計** → **方式確定、詳細設計は後日** — ValueHint enum 的なものと custom コールバックの統合。reducer からは補完候補を導出できないため、メタ情報として明示的に指定する必要がある

   **方式決定:**
   - 静的ソース出力（bash/zsh/fish スクリプト生成）は採用しない
   - **自己コマンドのセルフ呼び出しによる動的ヒント方式を確定**
     - コマンド自身が `--completion` 等の隠しオプションで呼ばれた際に、現在のカーソル位置と入力済みトークンを受け取り、補完候補を動的に返す
     - shell の completion 設定はコマンド自身を呼び出す薄いラッパーのみ
   - 詳細設計（プロトコル、出力形式、shell 連携の具体）は後日

5. **ヘルプ生成** → **未解決** — reducer パターンからヘルプテキストをどう生成するか。型名、可能な値、デフォルト値の表示には reducer 外のメタ情報が必要

6. **PoC（Phase 1-3）からの移行パス** → **解決: 全削除 + 完全作り直し** — 既存の OptKind ベース実装をどう段階的にリプレースするか。Opt[T] ラッパーを被せて段階的に移行する方式が有力

   **回答:** 移行不要。Phase 1-3 の PoC 実装は全削除して完全作り直し。

   方針:
   - PoC コードは `jj split` でコミット切り出し、bookmark またはタグで残しておく（しばらく振り返れるように）
   - 新設計はゼロから実装
   - まだ誰も使っていない PoC なので捨てて構わない
   - PoC は無駄ではなく、新設計の礎として役立った

   **テストケースは漏れなく再利用する:**
   - 要件定義の具現化であるテストケース集こそが宝物
   - 詳細なエッジケースを網羅したテストケースがあるからこそ、大きな設計判断（全削除＋作り直し）ができる
   - テストケースの期待値は新 API に合わせて書き換えるが、テストしている「要件・エッジケース」自体は全て引き継ぐ

---

### 18. 大統一: Command / Option / Positional の Reducer 統一

Phase 4 の議論の中で、reducer パターンがオプションだけでなく、サブコマンドと位置パラメータまで統一的に表現できる可能性が見えた。

#### 洞察

サブコマンド、オプション、位置パラメータは全て「トークンを消費して結果を積み上げる」という同じ構造を持つ:

| 種別 | マッチ条件 | long の意味 | reducer |
|------|----------|-----------|---------|
| Command | 名前でマッチ | サブコマンド名 (`serve`) | 子スコープの結果を返す |
| Option | `--long` でマッチ | オプション名 (`port`) | 値を変換・蓄積 |
| Positional | 位置でマッチ | プレースホルダ名 (`FILE`) | 値を変換・蓄積 |

meta に `kind: Command | Option | Positional` を持たせれば、全てを同じ reducer パターンで定義できる。

#### long フィールドの文脈依存的な意味

`long` フィールドは kind によって意味が変わる:
- `Option`: `--long` のオプション名 → コマンドラインで `--port 8080` と指定
- `Positional`: プレースホルダ名 → ヘルプ表示で `<FILE>` と表示
- `Command`: サブコマンド名 → コマンドラインで `serve` と指定

#### 位置パラメータとオプション引数のプレースホルダ統一

RGB の例:
```
--color int("R") int("G") int("B")
```
ヘルプ表示: `--color <R> <G> <B>`

ここで `"R"`, `"G"`, `"B"` は位置パラメータのプレースホルダ名。オプションの引数（tuple で合成された子要素）も位置パラメータと同じパターンで表現される。

つまり `int("R")` は:
- kind: Positional
- long: "R"（プレースホルダ名）
- reducer: `(_, Some(s)) -> parse_int(s)`

#### 設計の全体像（更新）

```
Opt[T] {
  initial : T
  reducer : (T, String?) -> T raise ParseError
  meta : Meta {
    kind : Kind          // Command | Option | Positional
    long : String        // 名前 or プレースホルダ
    short : ...          // Option のみ
    env : ...            // Option のみ
    help : String
    ...
  }
}
```

全ての定義が Opt[T] の合成で表現される:
- `opt::command("serve", children=[...])` → Command 種別の Opt
- `opt::int(long="port")` → Option 種別の Opt
- `opt::positional("FILE", opt::path)` → Positional 種別の Opt
- `opt::tuple(int("R"), int("G"), int("B"))` → 内部的に Positional の合成

これにより CmdDef / OptDef / PositionalDef の3つの型が Opt[T] の1つに統一される可能性がある。

#### 注意

この大統一はまだ構想段階。実装上の課題:
- Command の reducer は子スコープ全体を処理する必要があり、単純な `(T, String?) -> T` に収まるか要検討
- パーサのトークン消費ロジックが kind によって異なる（Option は `--` プレフィックスでマッチ、Command は名前でマッチ、Positional は位置でマッチ）
- ヘルプ生成時の kind による表示分け
