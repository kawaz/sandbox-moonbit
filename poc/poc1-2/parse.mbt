///|
/// スコープ単位のパース処理
///
/// tokens[start..] を scope_opts に基づいてパースし、
/// (result, explicitly_set, 次のインデックス) を返す。
/// DoubleDash に遭遇した場合は即座にリターンし、以降の処理は呼び出し元に委ねる。
fn parse_scope(
  tokens : Array[Token],
  start : Int,
  scope_opts : Array[OptDef],
  own_opts_count : Int,
  positional_spec : Positional,
  context : String,
  initial_result? : ParseResult,
  initial_explicitly_set? : Map[String, Bool],
) -> (ParseResult, Map[String, Bool], Int) raise ParseError {
  let has_help_opt = scope_opts.iter().any(fn(opt) { opt.long == "help" })
  let has_version_opt = scope_opts.iter().any(fn(opt) { opt.long == "version" })
  let result = initial_result.unwrap_or(ParseResult::new())
  let explicitly_set : Map[String, Bool] = initial_explicitly_set.unwrap_or({})
  // Group の explicitly_set 管理用
  // キー1: opt.long, キー2: value (WithValue のインスタンス値), 値: そのインスタンスの explicitly_set
  let group_explicitly_sets : Map[String, Map[String, Map[String, Bool]]] = {}
  let mut i = start
  // デフォルトグループの即時初期化
  // scope_opts[0..own_opts_count] で WithValue(default=Some(v)) の Group を検索
  for k = 0; k < own_opts_count; k = k + 1 {
    let opt = scope_opts[k]
    match opt.kind {
      Group(
        group_kind=WithValue(default=Some(default_val)),
        opts=group_opts,
        positional=group_positional
      ) => {
        // 子スコープの scope_opts = group.opts + parent scope_opts
        let child_scope_opts = group_opts.copy()
        child_scope_opts.append(scope_opts.copy())
        let child_context = if context == "" {
          "--" + opt.long + " " + default_val
        } else {
          context + " / --" + opt.long + " " + default_val
        }
        let (child_result, child_es, next_i) = parse_scope(
          tokens,
          i,
          child_scope_opts,
          group_opts.length(),
          group_positional,
          child_context,
        )
        // デフォルトインスタンスを GroupValue に追加
        update_group_value(result, opt.long, Some(default_val), child_result)
        explicitly_set[opt.long] = true
        // explicitly_set を保存
        save_group_explicitly_set(
          group_explicitly_sets,
          opt.long,
          default_val,
          child_es,
        )
        // 子スコープがトークンを消費した分だけ進める
        i = next_i
        // Design rationale: validate でデフォルトグループは同レベルに1つまでに制限されている
        // ため、最初の1つを見つけたら即座に break する
        break
      }
      _ => ()
    }
  }
  while i < tokens.length() {
    match tokens[i] {
      LongOpt(name) => {
        // --help 特殊処理: opts に help 未定義なら HelpRequested
        if name == "help" && not(has_help_opt) {
          raise HelpRequested
        }
        // --version 特殊処理: opts に version 未定義なら VersionRequested
        if name == "version" && not(has_version_opt) {
          raise VersionRequested
        }
        let resolved = resolve_long(scope_opts, name)
        let opt = scope_opts[resolved.index]
        match opt.kind {
          Flag(_) => {
            let value = match resolved.direction {
              Normal => true
              Inverted => false
            }
            result.values[opt.long] = FlagValue(value)
            explicitly_set[opt.long] = true
          }
          Single(_) =>
            if resolved.direction == ResolveDirection::Inverted {
              // --no-format: 値をクリア（未設定扱い）
              result.values.remove(opt.long)
              explicitly_set[opt.long] = true
            } else {
              i += 1
              if i >= tokens.length() {
                raise MissingValue("--" + opt.long)
              }
              result.values[opt.long] = StringValue(
                extract_token_value(tokens[i]),
              )
              explicitly_set[opt.long] = true
            }
          Append(n~, ..) => {
            if resolved.direction == ResolveDirection::Inverted {
              // --no-eval: リストをリセット
              result.values[opt.long] = ListValue([])
              explicitly_set[opt.long] = true
            } else {
              // n 個のトークンを消費
              for _ in 0..<n {
                i += 1
                if i >= tokens.length() {
                  raise MissingValue("--" + opt.long)
                }
                let value = extract_token_value(tokens[i])
                accumulate_value(result, opt.long, value)
              }
              explicitly_set[opt.long] = true
            }
            result.chunk_sizes[opt.long] = n
          }
          Count(_) => {
            let new_val = if resolved.direction == Normal {
              match result.values.get(opt.long) {
                Some(CountValue(n)) => n + 1
                _ => 1
              }
            } else {
              0
            }
            result.values[opt.long] = CountValue(new_val)
            explicitly_set[opt.long] = true
          }
          OptionalValue(implicit~, negated~, ..) =>
            if resolved.direction == Inverted {
              match negated {
                Some(v) => result.values[opt.long] = StringValue(v)
                None => result.values.remove(opt.long)
              }
              explicitly_set[opt.long] = true
            } else {
              result.values[opt.long] = StringValue(implicit)
              explicitly_set[opt.long] = true
            }
          Group(group_kind~, opts=group_opts, positional=group_positional) => {
            // Case A: 親由来の Group（index >= own_opts_count）→ スコープ終了
            if resolved.index >= own_opts_count {
              // 方向に関係なくトークンを消費せずに返す
              finalize_scope(
                result, scope_opts, own_opts_count, explicitly_set, positional_spec,
                context,
              )
              return (result, explicitly_set, i)
            }
            // 自スコープの Group（index < own_opts_count）
            if resolved.direction == ResolveDirection::Inverted {
              // --no-xxx: GroupValue をクリア（空配列にリセット）
              result.values[opt.long] = GroupValue([])
              explicitly_set[opt.long] = true
            } else {
              // Case B: 自スコープの Group → 子スコープ開始
              explicitly_set[opt.long] = true
              match group_kind {
                WithValue(_) => {
                  // 次のトークンから値を取得
                  i += 1
                  if i >= tokens.length() {
                    raise MissingValue("--" + opt.long)
                  }
                  let group_value = extract_token_value(tokens[i])
                  i += 1
                  // 子スコープの scope_opts = group.opts + parent scope_opts
                  let child_scope_opts = group_opts.copy()
                  child_scope_opts.append(scope_opts.copy())
                  let child_context = if context == "" {
                    "--" + opt.long + " " + group_value
                  } else {
                    context + " / --" + opt.long + " " + group_value
                  }
                  // 既存インスタンスを lookup してマージか新規か判定
                  let (child_initial_result, child_initial_es) = lookup_group_instance(
                    result,
                    opt.long,
                    group_value,
                    group_explicitly_sets,
                  )
                  let (child_result, child_es, next_i) = parse_scope(
                    tokens,
                    i,
                    child_scope_opts,
                    group_opts.length(),
                    group_positional,
                    child_context,
                    initial_result?=child_initial_result,
                    initial_explicitly_set?=child_initial_es,
                  )
                  update_group_value(
                    result,
                    opt.long,
                    Some(group_value),
                    child_result,
                  )
                  // explicitly_set を保存
                  save_group_explicitly_set(
                    group_explicitly_sets,
                    opt.long,
                    group_value,
                    child_es,
                  )
                  // Design rationale: ループ末尾の i += 1 を考慮して next_i - 1 に設定
                  i = next_i - 1
                }
                Valueless => {
                  // 常に新規 GroupInstance
                  i += 1
                  let child_scope_opts = group_opts.copy()
                  child_scope_opts.append(scope_opts.copy())
                  let child_context = if context == "" {
                    "--" + opt.long
                  } else {
                    context + " / --" + opt.long
                  }
                  let (child_result, _child_es, next_i) = parse_scope(
                    tokens,
                    i,
                    child_scope_opts,
                    group_opts.length(),
                    group_positional,
                    child_context,
                  )
                  // 新規追加
                  append_group_instance(result, opt.long, None, child_result)
                  // Design rationale: ループ末尾の i += 1 を考慮して next_i - 1 に設定
                  i = next_i - 1
                }
              }
            }
          }
        }
      }
      LongOptWithValue(name, value) => {
        // --help=... も特殊処理
        if name == "help" && not(has_help_opt) {
          raise HelpRequested
        }
        // --version=... も特殊処理
        if name == "version" && not(has_version_opt) {
          raise VersionRequested
        }
        let resolved = resolve_long(scope_opts, name)
        let opt = scope_opts[resolved.index]
        match opt.kind {
          Flag(_) => {
            let bool_val = if value == "true" {
              true
            } else if value == "false" {
              false
            } else {
              raise InvalidChoice(option=opt.long, value~, choices=[
                "true", "false",
              ])
            }
            let final_val = match resolved.direction {
              Normal => bool_val
              Inverted => not(bool_val)
            }
            result.values[opt.long] = FlagValue(final_val)
            explicitly_set[opt.long] = true
          }
          Single(_) =>
            if resolved.direction == ResolveDirection::Inverted {
              result.values.remove(opt.long)
              explicitly_set[opt.long] = true
            } else {
              result.values[opt.long] = StringValue(value)
              explicitly_set[opt.long] = true
            }
          Append(n~, ..) => {
            if resolved.direction == ResolveDirection::Inverted {
              // --no-eval=... : リストをリセット（値は無視）
              result.values[opt.long] = ListValue([])
              explicitly_set[opt.long] = true
            } else if n > 1 {
              // = 形式で n>1 は値が足りない
              raise MissingValue("--" + opt.long)
            } else {
              accumulate_value(result, opt.long, value)
              explicitly_set[opt.long] = true
            }
            result.chunk_sizes[opt.long] = n
          }
          Count(_) => {
            // --verbose=N は Count に対しては値を無視し、通常の increment/reset
            let new_val = if resolved.direction == Normal {
              match result.values.get(opt.long) {
                Some(CountValue(n)) => n + 1
                _ => 1
              }
            } else {
              0
            }
            result.values[opt.long] = CountValue(new_val)
            explicitly_set[opt.long] = true
          }
          OptionalValue(negated~, ..) =>
            if resolved.direction == Inverted {
              // --no-color=xxx は値を無視して negated 適用
              match negated {
                Some(v) => result.values[opt.long] = StringValue(v)
                None => result.values.remove(opt.long)
              }
              explicitly_set[opt.long] = true
            } else {
              result.values[opt.long] = StringValue(value)
              explicitly_set[opt.long] = true
            }
          Group(group_kind~, opts=group_opts, positional=group_positional) => {
            // Case A: 親由来の Group → スコープ終了
            if resolved.index >= own_opts_count {
              finalize_scope(
                result, scope_opts, own_opts_count, explicitly_set, positional_spec,
                context,
              )
              return (result, explicitly_set, i)
            }
            // 自スコープの Group
            if resolved.direction == ResolveDirection::Inverted {
              // --no-xxx=value: GroupValue をクリア（値は無視）
              result.values[opt.long] = GroupValue([])
              explicitly_set[opt.long] = true
            } else {
              explicitly_set[opt.long] = true
              match group_kind {
                WithValue(_) => {
                  // = の後の値を Group の value として使い、子スコープ開始
                  let group_value = value
                  i += 1
                  let child_scope_opts = group_opts.copy()
                  child_scope_opts.append(scope_opts.copy())
                  let child_context = if context == "" {
                    "--" + opt.long + " " + group_value
                  } else {
                    context + " / --" + opt.long + " " + group_value
                  }
                  let (child_initial_result, child_initial_es) = lookup_group_instance(
                    result,
                    opt.long,
                    group_value,
                    group_explicitly_sets,
                  )
                  let (child_result, child_es, next_i) = parse_scope(
                    tokens,
                    i,
                    child_scope_opts,
                    group_opts.length(),
                    group_positional,
                    child_context,
                    initial_result?=child_initial_result,
                    initial_explicitly_set?=child_initial_es,
                  )
                  update_group_value(
                    result,
                    opt.long,
                    Some(group_value),
                    child_result,
                  )
                  save_group_explicitly_set(
                    group_explicitly_sets,
                    opt.long,
                    group_value,
                    child_es,
                  )
                  // Design rationale: ループ末尾の i += 1 を考慮して next_i - 1 に設定
                  i = next_i - 1
                }
                Valueless =>
                  // Valueless + =value: エラー（UnexpectedValue 相当）
                  // Flag に =value で非 bool を渡した場合と同様のエラー
                  raise InvalidChoice(option=opt.long, value~, choices=[
                    "(no value expected)",
                  ])
              }
            }
          }
        }
      }
      ShortOpts(chars) => {
        // Design rationale: ShortOpts 内ではスコープ開始もスコープ終了も発火しない。
        // 全文字の処理が完了した後に、Group のスコープが次のトークンから開く。
        // pending_groups に遅延スコープ開始情報を蓄積し、ループ完了後に処理する。
        let pending_groups : Array[(OptDef, String?)] = [] // (opt, group_value)
        let mut j = 0
        while j < chars.length() {
          // Design rationale: short オプション文字は validate_opts で ASCII英数字のみに制限済み。
          // get_char はキャラクタインデックスを取るが、ASCII のみなのでバイトインデックスと一致する。
          let ch = match chars.get_char(j) {
            None => break
            Some(c) => c
          }
          let resolved = resolve_short(scope_opts, ch)
          let opt = scope_opts[resolved.index]
          match opt.kind {
            Flag(_) => {
              let value = match resolved.direction {
                Normal => true
                Inverted => false
              }
              result.values[opt.long] = FlagValue(value)
              explicitly_set[opt.long] = true
              j += 1
            }
            Single(_) => {
              let remaining_start = j + 1
              if remaining_start < chars.length() {
                let value = chars.unsafe_substring(
                  start=remaining_start,
                  end=chars.length(),
                )
                result.values[opt.long] = StringValue(value)
                explicitly_set[opt.long] = true
                j = chars.length()
              } else {
                i += 1
                if i >= tokens.length() {
                  raise MissingValue("-" + ch.to_string())
                }
                result.values[opt.long] = StringValue(
                  extract_token_value(tokens[i]),
                )
                explicitly_set[opt.long] = true
                j += 1
              }
            }
            Append(n~, ..) => {
              let remaining_start = j + 1
              let mut consumed = 0
              if remaining_start < chars.length() {
                let value = chars.unsafe_substring(
                  start=remaining_start,
                  end=chars.length(),
                )
                accumulate_value(result, opt.long, value)
                consumed = 1
                j = chars.length()
              } else {
                j += 1
              }
              // 残り n - consumed 個を次のトークンから消費
              for _ in 0..<(n - consumed) {
                i += 1
                if i >= tokens.length() {
                  raise MissingValue("-" + ch.to_string())
                }
                accumulate_value(
                  result,
                  opt.long,
                  extract_token_value(tokens[i]),
                )
              }
              explicitly_set[opt.long] = true
              result.chunk_sizes[opt.long] = n
            }
            Count(_) => {
              // 同一文字が連続する分だけカウント（-vvv → 3）
              let mut count = 1
              while j + count < chars.length() {
                match chars.get_char(j + count) {
                  Some(c2) => if c2 == ch { count += 1 } else { break }
                  _ => break
                }
              }
              let new_val = if resolved.direction == Normal {
                match result.values.get(opt.long) {
                  Some(CountValue(n)) => n + count
                  _ => count
                }
              } else {
                0
              }
              result.values[opt.long] = CountValue(new_val)
              explicitly_set[opt.long] = true
              j += count
            }
            // Design rationale: OptionalValue はショートオプションで使用禁止
            // validate_opts で事前にブロックされるため、ここには到達しない。
            // 防御的コードとして panic する。
            OptionalValue(..) =>
              raise DefinitionError(
                "OptionalValue cannot be used with short option: -" +
                ch.to_string(),
              )
            Group(group_kind~, ..) => {
              // Design rationale: ShortOpts 内ではスコープ遷移しない。
              // Group 情報を pending_groups に蓄積し、ShortOpts 完了後にスコープ開始する。
              explicitly_set[opt.long] = true
              match group_kind {
                WithValue(_) => {
                  // Single と同様: 残り文字列を値として消費、なければ次トークン
                  let remaining_start = j + 1
                  if remaining_start < chars.length() {
                    let group_value = chars.unsafe_substring(
                      start=remaining_start,
                      end=chars.length(),
                    )
                    pending_groups.push((opt, Some(group_value)))
                    j = chars.length()
                  } else {
                    i += 1
                    if i >= tokens.length() {
                      raise MissingValue("-" + ch.to_string())
                    }
                    let group_value = extract_token_value(tokens[i])
                    pending_groups.push((opt, Some(group_value)))
                    j += 1
                  }
                }
                Valueless => {
                  // Flag と同様: ただ記録して次の文字へ
                  pending_groups.push((opt, None))
                  j += 1
                }
              }
            }
          }
        }
        // ShortOpts 処理完了後: pending_groups のスコープを順次開始
        for pending in pending_groups {
          let (opt, group_value) = pending
          match opt.kind {
            Group(group_kind~, opts=group_opts, positional=group_positional) =>
              match group_kind {
                WithValue(_) => {
                  let gv = group_value.unwrap()
                  i += 1
                  let child_scope_opts = group_opts.copy()
                  child_scope_opts.append(scope_opts.copy())
                  let child_context = if context == "" {
                    "--" + opt.long + " " + gv
                  } else {
                    context + " / --" + opt.long + " " + gv
                  }
                  let (child_initial_result, child_initial_es) = lookup_group_instance(
                    result,
                    opt.long,
                    gv,
                    group_explicitly_sets,
                  )
                  let (child_result, child_es, next_i) = parse_scope(
                    tokens,
                    i,
                    child_scope_opts,
                    group_opts.length(),
                    group_positional,
                    child_context,
                    initial_result?=child_initial_result,
                    initial_explicitly_set?=child_initial_es,
                  )
                  update_group_value(result, opt.long, Some(gv), child_result)
                  save_group_explicitly_set(
                    group_explicitly_sets,
                    opt.long,
                    gv,
                    child_es,
                  )
                  // Design rationale: ループ末尾の i += 1 を考慮して next_i - 1 に設定
                  i = next_i - 1
                }
                Valueless => {
                  i += 1
                  let child_scope_opts = group_opts.copy()
                  child_scope_opts.append(scope_opts.copy())
                  let child_context = if context == "" {
                    "--" + opt.long
                  } else {
                    context + " / --" + opt.long
                  }
                  let (child_result, _child_es, next_i) = parse_scope(
                    tokens,
                    i,
                    child_scope_opts,
                    group_opts.length(),
                    group_positional,
                    child_context,
                  )
                  append_group_instance(result, opt.long, None, child_result)
                  // Design rationale: ループ末尾の i += 1 を考慮して next_i - 1 に設定
                  i = next_i - 1
                }
              }
            _ => () // unreachable
          }
        }
      }
      Positional(val) =>
        match positional_spec {
          Disallowed => raise UnexpectedPositional(context~, value=val)
          Fixed(defs) => {
            let consumed = result.positional.length()
            if consumed >= defs.length() {
              raise TooManyPositional(
                context~,
                expected=defs.length(),
                actual=consumed + 1,
              )
            }
            let def = defs[consumed]
            if def.choices.length() > 0 && not(def.choices.contains(val)) {
              raise InvalidChoice(
                option="positional '" + def.name + "'",
                value=val,
                choices=def.choices,
              )
            }
            result.positional.push(val)
          }
          Variadic(def) => {
            if def.choices.length() > 0 && not(def.choices.contains(val)) {
              raise InvalidChoice(
                option="positional '" + def.name + "'",
                value=val,
                choices=def.choices,
              )
            }
            result.positional.push(val)
          }
        }
      DoubleDash => {
        // DoubleDash 以降の処理は呼び出し元に委ねる
        // DoubleDash の位置を返す（呼び出し元が DoubleDash を検知して巻き戻す）
        finalize_scope(
          result, scope_opts, own_opts_count, explicitly_set, positional_spec, context,
        )
        return (result, explicitly_set, i)
      }
    }
    i += 1
  }
  // スコープ終了: required/choices/defaults チェック
  finalize_scope(
    result, scope_opts, own_opts_count, explicitly_set, positional_spec, context,
  )
  (result, explicitly_set, tokens.length())
}

///|
/// CLI引数をパースして ParseResult を返す
///
/// 処理フロー:
/// 1. validate_opts でバリデーション
/// 2. tokenize で字句解析
/// 3. parse_scope でトークン列を処理
/// 4. DoubleDash 以降の rest 収集
pub fn parse(
  opts : Array[OptDef],
  args : Array[String],
  positional_spec? : Positional = Variadic(PositionalDef::new()),
) -> ParseResult raise ParseError {
  validate_opts(opts)
  let tokens = tokenize(args)
  let (result, _explicitly_set, end_index) = parse_scope(
    tokens,
    0,
    opts,
    opts.length(),
    positional_spec,
    "",
  )
  // DoubleDash 以降の rest 収集
  // Design rationale: parse_scope は DoubleDash の位置で返す。
  // DoubleDash の次のトークンから rest に追加する。
  if end_index < tokens.length() && tokens[end_index] == DoubleDash {
    for j = end_index + 1; j < tokens.length(); j = j + 1 {
      match tokens[j] {
        Positional(val) => result.rest.push(val)
        _ => ()
      }
    }
  }
  result
}

///|
/// トークンからテキスト値を取り出すヘルパー
/// Design rationale: 全トークンタイプを値として受容する（greedy consumption）。
/// --format --verbose の場合、--verbose は format の値 "--verbose" になる。
/// --format -- の場合、DoubleDash は値 "--" になる。
/// これは clap/argparse 等の主要パーサと同じ挙動。
fn extract_token_value(token : Token) -> String {
  match token {
    Positional(v) => v
    LongOpt(v) => "--" + v
    LongOptWithValue(k, v) => "--" + k + "=" + v
    ShortOpts(v) => "-" + v
    DoubleDash => "--"
  }
}

///|
/// Append 型の値を蓄積するヘルパー
fn accumulate_value(
  result : ParseResult,
  long : String,
  value : String,
) -> Unit {
  match result.values.get(long) {
    Some(ListValue(list)) => list.push(value)
    _ => result.values[long] = ListValue([value])
  }
}

///|
/// スコープ終了時の required/choices チェック + デフォルト値適用 + positional 不足チェック
fn finalize_scope(
  result : ParseResult,
  scope_opts : Array[OptDef],
  own_opts_count : Int,
  explicitly_set : Map[String, Bool],
  positional_spec : Positional,
  context : String,
) -> Unit raise ParseError {
  let own_opts = scope_opts[0:own_opts_count]
  // required チェック（自スコープの opts のみ）
  for opt in own_opts {
    if opt.required && not(explicitly_set.contains(opt.long)) {
      raise MissingRequired("--" + opt.long)
    }
  }
  // choices チェック（自スコープの opts のみ）
  for opt in own_opts {
    if opt.choices.length() > 0 {
      match result.values.get(opt.long) {
        Some(StringValue(value)) =>
          if not(opt.choices.contains(value)) {
            raise InvalidChoice(option=opt.long, value~, choices=opt.choices)
          }
        Some(ListValue(values)) =>
          for value in values {
            if not(opt.choices.contains(value)) {
              raise InvalidChoice(option=opt.long, value~, choices=opt.choices)
            }
          }
        _ => ()
      }
    }
  }
  // デフォルト値適用（自スコープの opts のみ）
  for opt in own_opts {
    if not(explicitly_set.contains(opt.long)) {
      match opt.kind {
        Flag(default=v) => result.values[opt.long] = FlagValue(v)
        Single(default=Some(v)) => result.values[opt.long] = StringValue(v)
        Single(default=None) => ()
        Append(defaults=arr, n~) => {
          result.values[opt.long] = ListValue(arr.copy())
          result.chunk_sizes[opt.long] = n
        }
        Count(default=v) => result.values[opt.long] = CountValue(v)
        OptionalValue(default=Some(v), ..) =>
          result.values[opt.long] = StringValue(v)
        OptionalValue(default=None, ..) => ()
        Group(..) =>
          // Group のデフォルト値: 明示的に使われなければ空 GroupValue
          result.values[opt.long] = GroupValue([])
      }
    }
  }
  // Fixed positional の不足チェック
  match positional_spec {
    Fixed(defs) =>
      if result.positional.length() < defs.length() {
        raise TooFewPositional(
          context~,
          expected=defs.length(),
          actual=result.positional.length(),
        )
      }
    _ => ()
  }
}

///|
/// WithValue Group の既存インスタンスを lookup する
/// 見つかった場合は (result, explicitly_set) のペアを返す
fn lookup_group_instance(
  result : ParseResult,
  long : String,
  value : String,
  group_explicitly_sets : Map[String, Map[String, Map[String, Bool]]],
) -> (ParseResult?, Map[String, Bool]?) {
  match result.values.get(long) {
    Some(GroupValue(instances)) =>
      for instance in instances {
        match instance.value {
          Some(v) =>
            if v == value {
              // 既存インスタンスを見つけた → マージ
              let es = match group_explicitly_sets.get(long) {
                Some(by_value) =>
                  match by_value.get(value) {
                    Some(es) => Some(es)
                    None => None
                  }
                None => None
              }
              return (Some(instance.result), es)
            }
          None => ()
        }
      }
    _ => ()
  }
  (None, None)
}

///|
/// WithValue Group の GroupValue に追加/更新する
fn update_group_value(
  result : ParseResult,
  long : String,
  value : String?,
  child_result : ParseResult,
) -> Unit {
  match result.values.get(long) {
    Some(GroupValue(instances)) => {
      // 既存の同じ value のインスタンスを探して更新
      for i, instance in instances {
        if instance.value == value {
          instances[i] = { value, result: child_result }
          return
        }
      }
      // 見つからなかった → 新規追加
      instances.push({ value, result: child_result })
    }
    _ =>
      // まだ GroupValue が存在しない → 新規作成
      result.values[long] = GroupValue([{ value, result: child_result }])
  }
}

///|
/// Valueless Group のインスタンスを常に新規追加する
fn append_group_instance(
  result : ParseResult,
  long : String,
  value : String?,
  child_result : ParseResult,
) -> Unit {
  match result.values.get(long) {
    Some(GroupValue(instances)) =>
      instances.push({ value, result: child_result })
    _ => result.values[long] = GroupValue([{ value, result: child_result }])
  }
}

///|
/// Group の explicitly_set を保存する
fn save_group_explicitly_set(
  group_explicitly_sets : Map[String, Map[String, Map[String, Bool]]],
  long : String,
  value : String,
  es : Map[String, Bool],
) -> Unit {
  match group_explicitly_sets.get(long) {
    Some(by_value) => by_value[value] = es
    None => {
      let by_value : Map[String, Map[String, Bool]] = {}
      by_value[value] = es
      group_explicitly_sets[long] = by_value
    }
  }
}
