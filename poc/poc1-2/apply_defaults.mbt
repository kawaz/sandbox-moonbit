///|
/// 引数レイヤを OptDef のデフォルト値に吸収する。
/// 入力の opts を変更せず、新しい Array[OptDef] を返す純粋関数。
///
/// Design rationale: validate_opts を呼ばず、未知オプションも無視する。
/// 設定ファイルや環境変数等のデフォルト層では、未知オプションの存在は
/// エラーではなく単なるスキップ対象とするため。
///
/// | OptKind     | 正方向の動作                    | 反転方向の動作                    |
/// |-------------|-------------------------------|--------------------------------|
/// | Flag        | default を該当値に上書き          | default を反転値に上書き            |
/// | Single      | default を指定値に上書き          | default を None にクリア           |
/// | Append  | defaults に値を追加             | defaults を [] にリセット          |
pub fn apply_defaults(
  opts : Array[OptDef],
  args : Array[String],
) -> Array[OptDef] {
  // opts をコピー（各 OptDef を新しい struct として複製）
  let result_opts : Array[OptDef] = opts.map(fn(opt) { copy_opt_def(opt) })
  let tokens = tokenize(args)
  let mut i = 0
  while i < tokens.length() {
    let token = tokens[i]
    match token {
      LongOpt(name) => {
        let resolved = try? resolve_long(result_opts, name)
        match resolved {
          Ok(r) => {
            let opt = result_opts[r.index]
            match opt.kind {
              Flag(_) =>
                update_opt_kind(result_opts, r.index, apply_flag(r.direction))
              Single(_) =>
                // 次のトークンから値を取得
                if r.direction == ResolveDirection::Inverted {
                  update_opt_kind(
                    result_opts,
                    r.index,
                    OptKind::Single(default=None),
                  )
                } else {
                  // 次のトークンを値として消費
                  let value = consume_next_value(tokens, i)
                  match value {
                    Some(v) => {
                      i = i + 1 // 値トークンを消費
                      update_opt_kind(
                        result_opts,
                        r.index,
                        OptKind::Single(default=Some(v)),
                      )
                    }
                    None => () // 値がなければ無視
                  }
                }
              Append(defaults~, n~) =>
                if r.direction == ResolveDirection::Inverted {
                  update_opt_kind(
                    result_opts,
                    r.index,
                    OptKind::Append(defaults=[], n~),
                  )
                } else {
                  // n 個の値を一時的に収集
                  let collected : Array[String] = []
                  let mut consumed = 0
                  for _ in 0..<n {
                    let value = consume_next_value(tokens, i + consumed)
                    match value {
                      Some(v) => {
                        collected.push(v)
                        consumed += 1
                      }
                      None => break
                    }
                  }
                  // n 個全て揃った場合のみ defaults に反映
                  if collected.length() == n {
                    let new_defaults = defaults.copy()
                    for v in collected {
                      new_defaults.push(v)
                    }
                    i = i + consumed
                    update_opt_kind(
                      result_opts,
                      r.index,
                      OptKind::Append(defaults=new_defaults, n~),
                    )
                  }
                  // 部分消費は破棄（defaults 変更なし）
                }
              Count(default=current) =>
                if r.direction == ResolveDirection::Inverted {
                  update_opt_kind(
                    result_opts,
                    r.index,
                    OptKind::Count(default=0),
                  )
                } else {
                  update_opt_kind(
                    result_opts,
                    r.index,
                    OptKind::Count(default=current + 1),
                  )
                }
              OptionalValue(implicit~, negated~, ..) =>
                if r.direction == ResolveDirection::Inverted {
                  match negated {
                    Some(v) =>
                      update_opt_kind(
                        result_opts,
                        r.index,
                        OptKind::OptionalValue(
                          default=Some(v),
                          implicit~,
                          negated~,
                        ),
                      )
                    None =>
                      update_opt_kind(
                        result_opts,
                        r.index,
                        OptKind::OptionalValue(
                          default=None,
                          implicit~,
                          negated~,
                        ),
                      )
                  }
                } else {
                  update_opt_kind(
                    result_opts,
                    r.index,
                    OptKind::OptionalValue(
                      default=Some(implicit),
                      implicit~,
                      negated~,
                    ),
                  )
                }
              Group(group_kind~, opts~, positional~) =>
                match group_kind {
                  WithValue(..) =>
                    if r.direction == ResolveDirection::Inverted {
                      update_opt_kind(
                        result_opts,
                        r.index,
                        OptKind::Group(
                          group_kind=GroupKind::WithValue(default=None),
                          opts~,
                          positional~,
                        ),
                      )
                    } else {
                      // 次のトークンを値として消費
                      let value = consume_next_value(tokens, i)
                      match value {
                        Some(v) => {
                          i = i + 1
                          update_opt_kind(
                            result_opts,
                            r.index,
                            OptKind::Group(
                              group_kind=GroupKind::WithValue(default=Some(v)),
                              opts~,
                              positional~,
                            ),
                          )
                        }
                        None => () // 値がなければ無視
                      }
                    }
                  Valueless => () // デフォルト値の概念がない
                }
            }
          }
          Err(_) => () // 未知オプション → 無視
        }
      }
      LongOptWithValue(name, value) => {
        let resolved = try? resolve_long(result_opts, name)
        match resolved {
          Ok(r) => {
            let opt = result_opts[r.index]
            match opt.kind {
              Flag(_) =>
                // = 形式の Flag は値を無視し、方向に従う
                update_opt_kind(result_opts, r.index, apply_flag(r.direction))
              Single(_) =>
                if r.direction == ResolveDirection::Inverted {
                  update_opt_kind(
                    result_opts,
                    r.index,
                    OptKind::Single(default=None),
                  )
                } else {
                  update_opt_kind(
                    result_opts,
                    r.index,
                    OptKind::Single(default=Some(value)),
                  )
                }
              Append(defaults~, n~) =>
                if r.direction == ResolveDirection::Inverted {
                  update_opt_kind(
                    result_opts,
                    r.index,
                    OptKind::Append(defaults=[], n~),
                  )
                } else if n > 1 {
                  // = 形式では値が1つしか取れないので n>1 は無視
                  ()
                } else {
                  let new_defaults = defaults.copy()
                  new_defaults.push(value)
                  update_opt_kind(
                    result_opts,
                    r.index,
                    OptKind::Append(defaults=new_defaults, n~),
                  )
                }
              Count(default=current) =>
                // --verbose=N は = 形式でも値を無視し、方向に従う
                if r.direction == ResolveDirection::Inverted {
                  update_opt_kind(
                    result_opts,
                    r.index,
                    OptKind::Count(default=0),
                  )
                } else {
                  update_opt_kind(
                    result_opts,
                    r.index,
                    OptKind::Count(default=current + 1),
                  )
                }
              OptionalValue(implicit~, negated~, ..) =>
                if r.direction == ResolveDirection::Inverted {
                  // --no-color=xxx は値を無視して negated 適用
                  match negated {
                    Some(v) =>
                      update_opt_kind(
                        result_opts,
                        r.index,
                        OptKind::OptionalValue(
                          default=Some(v),
                          implicit~,
                          negated~,
                        ),
                      )
                    None =>
                      update_opt_kind(
                        result_opts,
                        r.index,
                        OptKind::OptionalValue(
                          default=None,
                          implicit~,
                          negated~,
                        ),
                      )
                  }
                } else {
                  update_opt_kind(
                    result_opts,
                    r.index,
                    OptKind::OptionalValue(
                      default=Some(value),
                      implicit~,
                      negated~,
                    ),
                  )
                }
              Group(group_kind~, opts~, positional~) =>
                match group_kind {
                  WithValue(..) =>
                    if r.direction == ResolveDirection::Inverted {
                      update_opt_kind(
                        result_opts,
                        r.index,
                        OptKind::Group(
                          group_kind=GroupKind::WithValue(default=None),
                          opts~,
                          positional~,
                        ),
                      )
                    } else {
                      update_opt_kind(
                        result_opts,
                        r.index,
                        OptKind::Group(
                          group_kind=GroupKind::WithValue(default=Some(value)),
                          opts~,
                          positional~,
                        ),
                      )
                    }
                  Valueless => () // デフォルト値の概念がない
                }
            }
          }
          Err(_) => ()
        }
      }
      ShortOpts(chars) => {
        let mut j = 0
        while j < chars.length() {
          // Design rationale: apply_defaults は validate_opts を呼ばないため、
          // マルチバイト文字を含む短オプション文字列が来る可能性がある。
          // chars.length() は UTF-16 コード単位数、get_char はキャラクタインデックスなので
          // 不一致が起こりうる。None の場合はループを終了する。
          let char = match chars.get_char(j) {
            None => break
            Some(c) => c
          }
          let resolved = try? resolve_short(result_opts, char)
          match resolved {
            Ok(r) => {
              let opt = result_opts[r.index]
              match opt.kind {
                Flag(_) => {
                  update_opt_kind(result_opts, r.index, apply_flag(r.direction))
                  j += 1
                }
                Single(_) => {
                  let remaining_start = j + 1
                  if remaining_start < chars.length() {
                    // 残り文字列を値として使用 (-fVALUE)
                    let value = chars.unsafe_substring(
                      start=remaining_start,
                      end=chars.length(),
                    )
                    update_opt_kind(
                      result_opts,
                      r.index,
                      OptKind::Single(default=Some(value)),
                    )
                    j = chars.length()
                  } else {
                    // 次のトークンを消費
                    let value = consume_next_value(tokens, i)
                    match value {
                      Some(v) => {
                        i = i + 1
                        update_opt_kind(
                          result_opts,
                          r.index,
                          OptKind::Single(default=Some(v)),
                        )
                      }
                      None => ()
                    }
                    j += 1
                  }
                }
                Append(defaults~, n~) => {
                  let remaining_start = j + 1
                  // n 個の値を一時的に収集
                  let collected : Array[String] = []
                  let mut tokens_consumed = 0
                  // 残り文字列があれば1つ目の値として使用
                  if remaining_start < chars.length() {
                    let value = chars.unsafe_substring(
                      start=remaining_start,
                      end=chars.length(),
                    )
                    collected.push(value)
                    j = chars.length()
                  } else {
                    j += 1
                  }
                  // 残り n - collected.length() 個を次のトークンから消費
                  for _ in 0..<(n - collected.length()) {
                    let value = consume_next_value(tokens, i + tokens_consumed)
                    match value {
                      Some(v) => {
                        collected.push(v)
                        tokens_consumed += 1
                      }
                      None => break
                    }
                  }
                  // n 個全て揃った場合のみ defaults に反映
                  if collected.length() == n {
                    let new_defaults = defaults.copy()
                    for v in collected {
                      new_defaults.push(v)
                    }
                    i = i + tokens_consumed
                    update_opt_kind(
                      result_opts,
                      r.index,
                      OptKind::Append(defaults=new_defaults, n~),
                    )
                  }
                  // 部分消費は破棄（defaults 変更なし）
                }
                Count(default=current) => {
                  // 同一文字が連続する分だけカウント
                  let mut count = 1
                  while j + count < chars.length() {
                    match chars.get_char(j + count) {
                      Some(c2) => if c2 == char { count += 1 } else { break }
                      _ => break
                    }
                  }
                  let new_val = if r.direction == ResolveDirection::Inverted {
                    0
                  } else {
                    current + count
                  }
                  update_opt_kind(
                    result_opts,
                    r.index,
                    OptKind::Count(default=new_val),
                  )
                  j += count
                }
                // Design rationale: OptionalValue はショートオプションで使用禁止。
                // apply_defaults は validate_opts を呼ばないため到達しうるが、無視する。
                OptionalValue(..) => j += 1
                Group(..) => j += 1
              }
            }
            Err(_) => j += 1 // 未知の場合スキップ
          }
        }
      }
      Positional(_) => () // 無視
      DoubleDash => () // DoubleDash 以降は tokenize で Positional になるため、ここでは無視
    }
    i = i + 1
  }
  result_opts
}

///|
/// OptDef をコピーする（struct は参照型のためフィールド展開で複製）
fn copy_opt_def(opt : OptDef) -> OptDef {
  {
    long: opt.long,
    help: opt.help,
    kind: copy_opt_kind(opt.kind),
    shorts: opt.shorts.copy(),
    aliases: opt.aliases.copy(),
    inversion: opt.inversion,
    env: opt.env,
    choices: opt.choices.copy(),
    value_name: opt.value_name,
    required: opt.required,
    visibility: opt.visibility,
  }
}

///|
/// OptKind をコピーする（Append の Array を deep copy）
fn copy_opt_kind(kind : OptKind) -> OptKind {
  match kind {
    Flag(default~) => Flag(default~)
    Single(default~) => Single(default~)
    Append(defaults~, n~) => Append(defaults=defaults.copy(), n~)
    Count(default~) => Count(default~)
    OptionalValue(default~, implicit~, negated~) =>
      OptionalValue(default~, implicit~, negated~)
    Group(group_kind~, opts~, positional~) => {
      let copied_opts = opts.map(fn(o) { { ..o, kind: copy_opt_kind(o.kind) } })
      let copied_positional = match positional {
        Disallowed => Disallowed
        Fixed(defs) =>
          Fixed(defs.map(fn(d) { { ..d, choices: d.choices.copy() } }))
        Variadic(def) => Variadic({ ..def, choices: def.choices.copy() })
      }
      let copied_group_kind = match group_kind {
        Valueless => Valueless
        WithValue(default~) => WithValue(default~)
      }
      Group(
        group_kind=copied_group_kind,
        opts=copied_opts,
        positional=copied_positional,
      )
    }
  }
}

///|
/// Flag の方向に応じた OptKind を返す
fn apply_flag(direction : ResolveDirection) -> OptKind {
  match direction {
    Normal => OptKind::Flag(default=true)
    Inverted => OptKind::Flag(default=false)
  }
}

///|
/// result_opts の指定インデックスの OptDef の kind を更新する
fn update_opt_kind(
  result_opts : Array[OptDef],
  index : Int,
  new_kind : OptKind,
) -> Unit {
  let opt = result_opts[index]
  result_opts[index] = {
    long: opt.long,
    help: opt.help,
    kind: new_kind,
    shorts: opt.shorts,
    aliases: opt.aliases,
    inversion: opt.inversion,
    env: opt.env,
    choices: opt.choices,
    value_name: opt.value_name,
    required: opt.required,
    visibility: opt.visibility,
  }
}

///|
/// 次のトークンを値として返す（全トークンタイプを受容）
fn consume_next_value(tokens : Array[Token], current_index : Int) -> String? {
  let next = current_index + 1
  if next < tokens.length() {
    Some(extract_token_value(tokens[next]))
  } else {
    None
  }
}
