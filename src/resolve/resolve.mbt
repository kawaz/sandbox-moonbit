///| 名前解決（Resolve フェーズ）
/// ロングオプション・エイリアス・プレフィックス・反転パターンの解決

///|
pub(all) enum ResolveResult {
  Resolved(@core.ErasedNode, @core.ReduceAction)
  Unresolved
}

///|
/// ResolveResult の Show 実装（テスト inspect 用）
pub impl Show for ResolveResult with output(self, logger) {
  match self {
    Resolved(node, action) => {
      logger.write_string("Resolved(")
      logger.write_string("ErasedNode::{meta: ")
      node.meta.output(logger)
      logger.write_string(", arity: ")
      node.arity.output(logger)
      logger.write_string("}, ")
      action.output(logger)
      logger.write_string(")")
    }
    Unresolved => logger.write_string("Unresolved")
  }
}

///|
/// 名前解決のメイン関数
pub fn resolve(
  input : String,
  nodes : Array[@core.ErasedNode],
) -> ResolveResult raise @core.ParseError {
  if input.has_prefix("--") {
    // `--` で始まる: ロングオプション
    let after_dashes = input.unsafe_substring(start=2, end=input.length())
    if after_dashes.is_empty() {
      // `--` のみ → Unresolved
      Unresolved
    } else {
      // `--xxx=yyy` の分解
      let (name, value) = split_long_value(after_dashes)
      // まずロング名で解決（完全一致 → プレフィックスマッチ）
      let result = resolve_long(name, value, nodes)
      match result {
        Resolved(_, _) => result
        Unresolved =>
          // ロング名で解決できなければ反転パターンを試す
          resolve_inversion(name, nodes)
      }
    }
  } else if input.has_prefix("-") && input.char_length() == 2 {
    // `-x` の形式: ショートオプション
    // 2文字目の Char を取得
    match input.get_char(1) {
      Some(ch) => resolve_short(ch, nodes)
      None => Unresolved
    }
  } else {
    // それ以外: サブコマンドマッチ
    resolve_command(input, nodes)
  }
}

///|
/// `--xxx=yyy` の分解。`=` があれば (name, Some(value))、なければ (name, None)
fn split_long_value(s : String) -> (String, String?) {
  match s.find("=") {
    Some(eq_offset) => {
      let name = s.unsafe_substring(start=0, end=eq_offset)
      let value = s.unsafe_substring(start=eq_offset + 1, end=s.length())
      (name, Some(value))
    }
    None => (s, None)
  }
}

///|
/// ロング名解決（完全一致 → エイリアス完全一致 → プレフィックスマッチ）
fn resolve_long(
  name : String,
  value : String?,
  nodes : Array[@core.ErasedNode],
) -> ResolveResult raise @core.ParseError {
  let action : @core.ReduceAction = Value(value)
  // 1. 完全一致
  for node in nodes {
    if node.meta.kind == Option && node.meta.name == name {
      return Resolved(node, action)
    }
  }
  // 2. エイリアス完全一致
  for node in nodes {
    if node.meta.kind == Option {
      for al in node.meta.aliases {
        if al.name == name {
          return Resolved(node, action)
        }
      }
    }
  }
  // 3. プレフィックスマッチ（曖昧でなければ）
  let candidates : Array[(@core.ErasedNode, String)] = []
  for node in nodes {
    if node.meta.kind == Option && node.meta.name.has_prefix(name) {
      candidates.push((node, node.meta.name))
    }
  }
  // エイリアスのプレフィックスマッチもチェック
  for node in nodes {
    if node.meta.kind == Option {
      for al in node.meta.aliases {
        if al.name.has_prefix(name) {
          // 既に候補にあるノードは追加しない
          let already = candidates
            .iter()
            .find_first(fn(pair) { pair.1 == node.meta.name })
          if already is None {
            candidates.push((node, node.meta.name))
          }
        }
      }
    }
  }
  match candidates.length() {
    1 => Resolved(candidates[0].0, action)
    n if n > 1 => {
      let names : Array[String] = []
      for pair in candidates {
        names.push(pair.1)
      }
      raise @core.ParseError::AmbiguousOption(input=name, candidates=names)
    }
    _ => Unresolved
  }
}

///|
/// ショート名解決
fn resolve_short(ch : Char, nodes : Array[@core.ErasedNode]) -> ResolveResult {
  for node in nodes {
    if node.meta.kind == Option {
      for short in node.meta.shorts {
        if short.char == ch {
          return Resolved(node, Value(None))
        }
      }
    }
  }
  Unresolved
}

///|
/// 反転パターン解決
fn resolve_inversion(
  name : String,
  nodes : Array[@core.ErasedNode],
) -> ResolveResult {
  for node in nodes {
    if node.meta.kind != Option {
      continue
    }
    match node.meta.inversion {
      Some(No) =>
        // `--no-xxx` → name="xxx"
        if name.has_prefix("no-") {
          let base = name.unsafe_substring(start=3, end=name.length())
          if base == node.meta.name {
            return Resolved(node, Negate)
          }
        }
      Some(EnableDisable) => {
        // `--enable-xxx` → name="xxx", Value(None)
        if name.has_prefix("enable-") {
          let base = name.unsafe_substring(start=7, end=name.length())
          if base == node.meta.name {
            return Resolved(node, Value(None))
          }
        }
        // `--disable-xxx` → name="xxx", Negate
        if name.has_prefix("disable-") {
          let base = name.unsafe_substring(start=8, end=name.length())
          if base == node.meta.name {
            return Resolved(node, Negate)
          }
        }
      }
      Some(Custom(pos, neg)) => {
        // `--{pos}-xxx` → Value(None)
        let pos_prefix = pos + "-"
        if name.has_prefix(pos_prefix) {
          let base = name.unsafe_substring(
            start=pos_prefix.length(),
            end=name.length(),
          )
          if base == node.meta.name {
            return Resolved(node, Value(None))
          }
        }
        // `--{neg}-xxx` → Negate
        let neg_prefix = neg + "-"
        if name.has_prefix(neg_prefix) {
          let base = name.unsafe_substring(
            start=neg_prefix.length(),
            end=name.length(),
          )
          if base == node.meta.name {
            return Resolved(node, Negate)
          }
        }
      }
      None => ()
    }
  }
  Unresolved
}

///|
/// サブコマンド名解決
fn resolve_command(
  name : String,
  nodes : Array[@core.ErasedNode],
) -> ResolveResult {
  for node in nodes {
    if node.meta.kind == Command && node.meta.name == name {
      return Resolved(node, Value(None))
    }
  }
  Unresolved
}
