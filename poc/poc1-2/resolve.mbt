///|
/// ロングオプション名を解決する
///
/// 解決順序:
/// 1. long 名との完全一致
/// 2. aliases の name との完全一致
/// 3. 反転パターン名のマッチ（inversion 設定に基づく）
/// 4. いずれにもマッチしない → UnknownOption
pub fn resolve_long(
  opts : Array[OptDef],
  name : String,
) -> ResolveResult raise ParseError {
  // 1. long 名との完全一致
  for i, opt in opts {
    if opt.long == name {
      return { index: i, direction: ResolveDirection::Normal }
    }
  }
  // 2. aliases の name との完全一致
  for i, opt in opts {
    for entry in opt.aliases {
      if entry.name == name {
        return { index: i, direction: ResolveDirection::Normal }
      }
    }
  }
  // 3. 反転パターン名のマッチ
  for i, opt in opts {
    match opt.inversion {
      Some(PrefixNo) =>
        if name == "no-" + opt.long {
          return { index: i, direction: ResolveDirection::Inverted }
        }
      Some(PrefixEnableDisable) =>
        if name == "enable-" + opt.long {
          return { index: i, direction: ResolveDirection::Normal }
        } else if name == "disable-" + opt.long {
          return { index: i, direction: ResolveDirection::Inverted }
        }
      Some(PrefixWithWithout) =>
        if name == "with-" + opt.long {
          return { index: i, direction: ResolveDirection::Normal }
        } else if name == "without-" + opt.long {
          return { index: i, direction: ResolveDirection::Inverted }
        }
      None => ()
    }
  }
  // 4. マッチなし
  raise ParseError::UnknownOption("--" + name)
}

///|
/// ショートオプション文字を解決する
///
/// 全 OptDef の shorts から char 一致を検索する。
/// ショートオプションに反転はないため、常に Normal を返す。
pub fn resolve_short(
  opts : Array[OptDef],
  char : Char,
) -> ResolveResult raise ParseError {
  for i, opt in opts {
    for short in opt.shorts {
      if short.char == char {
        return { index: i, direction: ResolveDirection::Normal }
      }
    }
  }
  raise ParseError::UnknownOption("-" + char.to_string())
}
