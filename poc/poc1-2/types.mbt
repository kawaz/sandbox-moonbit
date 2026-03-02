///|
/// 位置引数の定義
pub(all) struct PositionalDef {
  name : String
  help : String
  choices : Array[String]
} derive(Eq, Show, Debug)

///|
pub fn PositionalDef::new(
  name? : String = "ARG",
  help? : String = "",
  choices? : Array[String] = [],
) -> PositionalDef {
  { name, help, choices }
}

///|
/// 位置引数の受け付け方
pub(all) enum Positional {
  /// 位置引数を許可しない
  Disallowed
  /// 固定数の位置引数
  Fixed(Array[PositionalDef])
  /// 可変長の位置引数
  Variadic(PositionalDef)
} derive(Eq, Show, Debug)

///|
/// グループオプションの値の種類
pub(all) enum GroupKind {
  /// 値なし（--ssl）
  Valueless
  /// 値あり（--output=json）
  WithValue(default~ : String?)
} derive(Eq, Show, Debug)

///|
/// オプションの値の種類
pub(all) enum OptKind {
  /// 値なしフラグ（--verbose）。反転で false にセット
  Flag(default~ : Bool)
  /// 単一値（--format json）。後の指定が上書き
  Single(default~ : String?)
  /// 複数値蓄積（--eval a --eval b）。n>1 で固定長消費（--arg k v）
  Append(defaults~ : Array[String], n~ : Int)
  /// 出現回数カウント（-vvv）。反転で 0 にリセット
  Count(default~ : Int)
  /// 値省略可能オプション（--color, --color=always）。= 形式のみ値受付
  OptionalValue(default~ : String?, implicit~ : String, negated~ : String?)
  /// グループオプション（--ssl で子オプション群を有効化）
  Group(
    group_kind~ : GroupKind,
    opts~ : Array[OptDef],
    positional~ : Positional
  )
} derive(Eq, Show, Debug)

///|
/// フラグ反転パターン
/// Design rationale: 型名は FlagInversion だが、Single（値クリア）や
/// Append（リストリセット）にも適用可能。フラグ反転が最も一般的なため現名称を維持。
pub(all) enum FlagInversion {
  /// --verbose / --no-verbose
  PrefixNo
  /// --enable-cache / --disable-cache
  PrefixEnableDisable
  /// --with-feature / --without-feature
  PrefixWithWithout
} derive(Eq, Show, Debug)

///|
/// help と completion での表示を個別に制御する
pub(all) struct Visibility {
  show_in_help : Bool
  show_in_completion : Bool
} derive(Eq, Show, Debug)

///|
pub fn Visibility::shown() -> Visibility {
  { show_in_help: true, show_in_completion: true }
}

///|
pub fn Visibility::hidden() -> Visibility {
  { show_in_help: false, show_in_completion: false }
}

///|
pub fn Visibility::help_only() -> Visibility {
  { show_in_help: true, show_in_completion: false }
}

///|
pub fn Visibility::completion_only() -> Visibility {
  { show_in_help: false, show_in_completion: true }
}

///|
/// ロングオプション名やサブコマンド名のエイリアス
pub(all) struct AliasEntry {
  name : String
  visibility : Visibility
  /// deprecated メッセージ（None なら非 deprecated）
  deprecated : String?
} derive(Eq, Show, Debug)

///|
pub fn AliasEntry::new(
  name~ : String,
  visibility? : Visibility = Visibility::shown(),
  deprecated? : String? = None,
) -> AliasEntry {
  { name, visibility, deprecated }
}

///|
/// ショートオプション（1文字）に表示制御を付与
pub(all) struct ShortEntry {
  char : Char
  visibility : Visibility
} derive(Eq, Show, Debug)

///|
pub fn ShortEntry::new(
  char~ : Char,
  visibility? : Visibility = Visibility::shown(),
) -> ShortEntry {
  { char, visibility }
}

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

///|
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
  visibility? : Visibility = Visibility::shown(),
) -> OptDef {
  {
    long,
    help,
    kind,
    shorts,
    aliases,
    inversion,
    env,
    choices,
    value_name,
    required,
    visibility,
  }
}

///|
/// 名前解決の方向
pub(all) enum ResolveDirection {
  /// 正方向（--verbose, --enable-cache, --with-ssl）
  Normal
  /// 反転方向（--no-verbose, --disable-cache, --without-ssl）
  Inverted
} derive(Eq, Show, Debug)

///|
/// 名前解決の結果
pub(all) struct ResolveResult {
  /// マッチした OptDef のインデックス（opts 配列内）
  index : Int
  /// 正方向か反転方向か
  direction : ResolveDirection
} derive(Eq, Show, Debug)

///|
/// パースされた値
pub(all) enum ParsedValue {
  /// フラグの真偽値
  FlagValue(Bool)
  /// 単一文字列値（Single, OptionalValue 共用）
  StringValue(String)
  /// 文字列リスト（Append オプション用）
  ListValue(Array[String])
  /// カウント値（Count オプション用）
  CountValue(Int)
  /// グループオプションの値（Group オプション用）
  GroupValue(Array[GroupInstance])
} derive(Eq, Show, Debug)

///|
/// グループオプションの1インスタンス
pub(all) struct GroupInstance {
  /// グループに渡された値（GroupKind::WithValue の場合）
  value : String?
  /// グループ内のパース結果
  result : ParseResult
} derive(Eq, Show, Debug)

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

///|
pub fn ParseResult::new() -> ParseResult {
  { values: {}, positional: [], rest: [], chunk_sizes: {} }
}

///|
pub fn ParseResult::get_flag(self : ParseResult, name : String) -> Bool {
  match self.values.get(name) {
    Some(FlagValue(v)) => v
    _ => false
  }
}

///|
pub fn ParseResult::get_string(self : ParseResult, name : String) -> String? {
  match self.values.get(name) {
    Some(StringValue(v)) => Some(v)
    _ => None
  }
}

///|
pub fn ParseResult::get_int(self : ParseResult, name : String) -> Int? {
  match self.values.get(name) {
    Some(StringValue(v)) => Some(@strconv.parse_int(v)) catch { _ => None }
    Some(CountValue(v)) => Some(v)
    _ => None
  }
}

///|
pub fn ParseResult::get_count(self : ParseResult, name : String) -> Int {
  match self.values.get(name) {
    Some(CountValue(v)) => v
    _ => 0
  }
}

///|
pub fn ParseResult::get_list(
  self : ParseResult,
  name : String,
) -> Array[String] {
  match self.values.get(name) {
    Some(ListValue(v)) => v
    _ => []
  }
}

///|
/// Append(n>1) の値を n 個ずつのチャンクに分割して返す
/// n=1 の場合は空配列を返す（get_list を使うこと）
/// n は parse 時に chunk_sizes に記録された値を自動参照する
pub fn ParseResult::get_chunks(
  self : ParseResult,
  name : String,
) -> Array[Array[String]] {
  let n = match self.chunk_sizes.get(name) {
    Some(n) => n
    None => 1
  }
  if n <= 1 {
    return []
  }
  let list = self.get_list(name)
  if list.length() == 0 {
    return []
  }
  let result : Array[Array[String]] = []
  let mut i = 0
  while i + n <= list.length() {
    let chunk : Array[String] = []
    for j in 0..<n {
      chunk.push(list[i + j])
    }
    result.push(chunk)
    i += n
  }
  result
}

///|
/// Group オプションの値を取得する
pub fn ParseResult::get_group(
  self : ParseResult,
  name : String,
) -> Array[GroupInstance]? {
  match self.values.get(name) {
    Some(GroupValue(v)) => Some(v)
    _ => None
  }
}

///|
/// パースエラー
pub(all) suberror ParseError {
  /// 未知のオプション
  UnknownOption(String)
  /// 値が不足
  MissingValue(String)
  /// 必須オプション未指定
  MissingRequired(String)
  /// 値が選択肢に含まれない
  InvalidChoice(option~ : String, value~ : String, choices~ : Array[String])
  /// --help 指定（正常系だがパース中断のためエラー型で表現）
  HelpRequested
  /// オプション定義のバリデーションエラー（開発者エラー）
  DefinitionError(String)
  /// 未知のサブコマンド
  UnknownCommand(String)
  /// --version 指定（正常系だがパース中断のためエラー型で表現）
  VersionRequested
  /// 位置引数が多すぎる
  TooManyPositional(context~ : String, expected~ : Int, actual~ : Int)
  /// 位置引数が少なすぎる
  TooFewPositional(context~ : String, expected~ : Int, actual~ : Int)
  /// 位置引数が許可されていない
  UnexpectedPositional(context~ : String, value~ : String)
} derive(Show)

///|
/// サブコマンド定義（トップレベルコマンドも含む）
pub(all) struct CmdDef {
  /// コマンド名
  name : String
  /// コマンドの説明
  description : String
  /// バージョン文字列
  version : String
  /// コマンド固有のオプション定義
  opts : Array[OptDef]
  /// グローバルオプション定義（親から継承）
  global_opts : Array[OptDef]
  /// サブコマンド定義
  subcommands : Array[CmdDef]
  /// コマンド名のエイリアス
  aliases : Array[AliasEntry]
  /// 引数なし実行時に help を表示するか
  help_on_empty : Bool
  /// 位置引数の受け付け方
  positional_spec : Positional
} derive(Show, Debug)

///|
pub fn CmdDef::new(
  name~ : String,
  description? : String = "",
  version? : String = "",
  opts? : Array[OptDef] = [],
  global_opts? : Array[OptDef] = [],
  subcommands? : Array[CmdDef] = [],
  aliases? : Array[AliasEntry] = [],
  help_on_empty? : Bool = true,
  positional_spec? : Positional = Positional::Variadic(PositionalDef::new()),
) -> CmdDef {
  {
    name,
    description,
    version,
    opts,
    global_opts,
    subcommands,
    aliases,
    help_on_empty,
    positional_spec,
  }
}

///|
/// サブコマンド解決済みのパース結果
pub(all) struct CommandResult {
  /// 解決されたコマンドパス（例: ["git", "remote", "add"]）
  command : Array[String]
  /// パース結果
  result : ParseResult
} derive(Eq, Show, Debug)

///|
pub fn CommandResult::new(
  command? : Array[String] = [],
  result? : ParseResult = ParseResult::new(),
) -> CommandResult {
  { command, result }
}

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

///|
/// トークン化の中間表現
pub(all) enum Token {
  /// --verbose
  LongOpt(String)
  /// --format=json
  LongOptWithValue(String, String)
  /// -abc（短オプション群）
  ShortOpts(String)
  /// 位置引数
  Positional(String)
  /// -- セパレータ
  DoubleDash
} derive(Eq, Show, Debug)
