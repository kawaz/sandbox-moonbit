///|
/// サブコマンド名またはエイリアスでマッチする CmdDef を返す
fn matches_subcommand(name : String, subcommands : Array[CmdDef]) -> CmdDef? {
  for sub in subcommands {
    if sub.name == name {
      return Some(sub)
    }
    for entry in sub.aliases {
      if entry.name == name {
        return Some(sub)
      }
    }
  }
  None
}

///|
/// ShortOpts 文字列を走査し、値消費で追加スキップすべきトークン数を返す
///
/// parse.mbt と同じロジック: 先頭から1文字ずつ走査。
/// 値を取る文字（Single/Append）で残り文字列がなければ次トークン消費（+1）、
/// 残りがあれば内包（+0）。未知の文字はスキップなし（0）。
fn compute_short_opts_skip(
  chars : String,
  opts : Array[OptDef],
) -> Int raise ParseError {
  let mut skip = 0
  let mut j = 0
  while j < chars.length() {
    let ch = match chars.get_char(j) {
      None => break
      Some(c) => c
    }
    // resolve_short は未知文字で ParseError::UnknownOption を raise する
    let resolved = resolve_short(opts, ch)
    let opt = opts[resolved.index]
    match opt.kind {
      Flag(_) | Count(_) => j += 1
      Single(_) => {
        let remaining_start = j + 1
        if remaining_start < chars.length() {
          // 残り文字列に値が内包 → 追加トークン消費なし
          // この文字で ShortOpts の走査は終了
          break
        } else {
          // 次トークンを値として消費
          skip += 1
          j += 1
        }
      }
      Append(n~, ..) => {
        let remaining_start = j + 1
        if remaining_start < chars.length() {
          // 残り文字列が1つ目の値、残り n-1 個が次トークン
          skip += n - 1
          break
        } else {
          // n 個のトークンを値として消費
          skip += n
          j += 1
        }
      }
      // OptionalValue は ShortOpts では使用禁止（validate_opts でブロック済み）
      OptionalValue(..) => j += 1
      Group(..) => ()
    }
  }
  skip
}

///|
/// トークン列を走査し、最初のサブコマンド候補 Positional のインデックスを返す
fn scan_for_subcommand(
  tokens : Array[Token],
  effective_opts : Array[OptDef],
  subcommands : Array[CmdDef],
) -> Int? raise ParseError {
  let has_help_opt = effective_opts.iter().any(fn(opt) { opt.long == "help" })
  let has_version_opt = effective_opts
    .iter()
    .any(fn(opt) { opt.long == "version" })
  let mut i = 0
  while i < tokens.length() {
    match tokens[i] {
      LongOpt(name) =>
        // --help / --version はユーザー定義がなければ特殊処理（resolve_long を呼ばず、値も消費しない）
        // parse で特殊処理されるため、ここではスキップのみ
        if (name == "help" && not(has_help_opt)) ||
          (name == "version" && not(has_version_opt)) {
          () // i += 1 はループ末尾で行われる
        } else {
          let resolved = resolve_long(effective_opts, name)
          let opt = effective_opts[resolved.index]
          // Normal 方向で値を消費する kind → 次トークンをスキップ
          if resolved.direction == ResolveDirection::Normal {
            match opt.kind {
              Single(_) => i += 1
              Append(n~, ..) => i += n // n 個のトークンをスキップ
              _ => ()
            }
          }
          // Inverted 方向は値を消費しない
        }
      LongOptWithValue(name, _) =>
        // --help=xxx / --version=xxx もユーザー定義がなければ特殊処理（スキップのみ）
        if (name == "help" && not(has_help_opt)) ||
          (name == "version" && not(has_version_opt)) {
          ()
        } else {
          // resolve して存在確認のみ。値はトークン内に含まれるので追加スキップ不要
          let _ = resolve_long(effective_opts, name)
        }
      ShortOpts(chars) => {
        let skip = compute_short_opts_skip(chars, effective_opts)
        i += skip
      }
      Positional(name) =>
        if not(matches_subcommand(name, subcommands) is None) {
          return Some(i)
        } else if subcommands.length() > 0 {
          // Design rationale: サブコマンドが定義されたコマンドでは、位置引数を受け付けない。
          // 最初の Positional トークンはサブコマンド名として解釈され、マッチしなければ
          // UnknownCommand となる。これは cobra 等の主要フレームワークと同じ設計。
          // 位置引数とサブコマンドの曖昧さを排除し、typo を早期検出するため。
          raise ParseError::UnknownCommand(name)
        } else {
          return None
        }
      DoubleDash => return None
    }
    i += 1
  }
  None
}

///|
/// サブコマンドを再帰的に解決し、リーフコマンド・コマンドパス・パース用引数を返す
///
/// 返り値: (leaf_cmd, command_path, parse_args)
/// - leaf_cmd: 最終的に選択されたコマンド定義
/// - command_path: ルートからリーフまでのサブコマンド名リスト（例: ["config", "set"]）
/// - parse_args: サブコマンド名を除去した引数列（オプションパース用）
/// Design rationale: parse_command 経由での使用を想定。直接呼び出しは非推奨だが、
/// テストでの直接検証のために pub を維持。将来 internal visibility が導入されたら変更する。
pub fn find_command(
  cmd : CmdDef,
  args : Array[String],
  inherited_globals : Array[OptDef],
) -> (CmdDef, Array[String], Array[String]) raise ParseError {
  // サブコマンドが未定義のリーフコマンドならルーティング不要
  if cmd.subcommands.length() == 0 {
    return (cmd, [], args)
  }
  // 1. effective_opts = cmd.opts + cmd.global_opts + inherited_globals
  let effective_opts : Array[OptDef] = []
  for opt in cmd.opts {
    effective_opts.push(opt)
  }
  for opt in cmd.global_opts {
    effective_opts.push(opt)
  }
  for opt in inherited_globals {
    effective_opts.push(opt)
  }
  // 2. tokenize
  let tokens = tokenize(args)
  // 3. scan_for_subcommand
  let subcmd_idx = scan_for_subcommand(tokens, effective_opts, cmd.subcommands)
  match subcmd_idx {
    None => (cmd, [], args)
    Some(idx) => {
      // サブコマンド名をマッチして CmdDef を取得
      let subcmd_name = match tokens[idx] {
        Positional(name) => name
        _ =>
          abort(
            "unreachable: scan_for_subcommand returned non-Positional index",
          )
      }
      let matched_cmd = match matches_subcommand(subcmd_name, cmd.subcommands) {
        Some(c) => c
        None =>
          abort(
            "unreachable: scan_for_subcommand confirmed match but matches_subcommand returned None",
          )
      }
      // args から subcmd_idx 位置の要素を除去
      // tokenize は args の各エントリを1つの Token に変換するので、インデックスは1:1対応
      let new_args : Array[String] = []
      for j, arg in args {
        if j != idx {
          new_args.push(arg)
        }
      }
      // 再帰: 子の global_opts に親の effective_opts を渡す（opts + global_opts + inherited）
      let child_inherited : Array[OptDef] = []
      for opt in cmd.global_opts {
        child_inherited.push(opt)
      }
      for opt in inherited_globals {
        child_inherited.push(opt)
      }
      let (leaf, child_path, parse_args) = find_command(
        matched_cmd, new_args, child_inherited,
      )
      // 不変条件: command_path は常に正規名（CmdDef.name）で構築される。
      // エイリアス経由でマッチしても matched_cmd.name を使うため、
      // 呼び出し側は正規名のみを前提にできる。
      let path : Array[String] = [matched_cmd.name]
      for p in child_path {
        path.push(p)
      }
      (leaf, path, parse_args)
    }
  }
}

///|
/// CLI引数をサブコマンド解決 + パースして CommandResult を返す
///
/// 処理フロー:
/// 1. validate_command(cmd) でコマンド定義ツリーを検証
/// 2. help_on_empty チェック（ルート）
/// 3. find_command でサブコマンド解決
/// 4. help_on_empty チェック（リーフ、ルートと異なる場合）
/// 5. effective_opts 構築（leaf の opts + global_opts + 全祖先の global_opts）
/// 6. parse で引数パース
/// 7. CommandResult として返却
pub fn parse_command(
  cmd : CmdDef,
  args : Array[String],
) -> CommandResult raise ParseError {
  // 1. validate
  validate_command(cmd)
  // 2. help_on_empty チェック（ルート）
  if args.length() == 0 && cmd.help_on_empty {
    raise HelpRequested
  }
  // 3. find_command
  let (leaf_cmd, command_path, parse_args) = find_command(cmd, args, [])
  // 4. help_on_empty チェック（リーフ、ルートと異なる場合のみ）
  if parse_args.length() == 0 &&
    leaf_cmd.help_on_empty &&
    command_path.length() > 0 {
    raise HelpRequested
  }
  // 5. effective_opts 構築
  let effective_opts : Array[OptDef] = []
  // leaf の opts
  for opt in leaf_cmd.opts {
    effective_opts.push(opt)
  }
  // leaf の global_opts
  for opt in leaf_cmd.global_opts {
    effective_opts.push(opt)
  }
  // 全祖先の global_opts を収集
  // ルートの global_opts も含める必要がある
  let inherited = if command_path.length() > 0 {
    // ルートから leaf の親までの global_opts を収集
    let globals : Array[OptDef] = []
    for opt in cmd.global_opts {
      globals.push(opt)
    }
    // path に沿って中間ノードの global_opts も収集
    // 不変条件: command_path は正規名のみで構成されるため、sub.name との比較で安全にマッチする
    let mut current = cmd
    for i in 0..<(command_path.length() - 1) {
      let name = command_path[i]
      let mut found : CmdDef? = None
      for sub in current.subcommands {
        if sub.name == name {
          found = Some(sub)
          break
        }
      }
      match found {
        Some(sub) => {
          for opt in sub.global_opts {
            globals.push(opt)
          }
          current = sub
        }
        None =>
          abort(
            "unreachable: command_path contains unknown subcommand name: " +
            name,
          )
      }
    }
    globals
  } else {
    []
  }
  for opt in inherited {
    effective_opts.push(opt)
  }
  // 6. parse（positional_spec をリーフコマンドから渡す）
  let result = parse(
    effective_opts,
    parse_args,
    positional_spec=leaf_cmd.positional_spec,
  )
  // 7. return
  CommandResult::new(command=command_path, result~)
}
