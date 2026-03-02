///|
/// テスト用のオプション定義を構築するヘルパー
fn make_test_opts() -> Array[OptDef] {
  [
    // index 0: verbose (PrefixNo)
    OptDef::new(
      long="verbose",
      help="Enable verbose output",
      kind=OptKind::Flag(default=false),
      shorts=[ShortEntry::new(char='v')],
      inversion=Some(FlagInversion::PrefixNo),
    ),
    // index 1: cache (PrefixEnableDisable)
    OptDef::new(
      long="cache",
      help="Enable cache",
      kind=OptKind::Flag(default=true),
      inversion=Some(FlagInversion::PrefixEnableDisable),
    ),
    // index 2: ssl (PrefixWithWithout)
    OptDef::new(
      long="ssl",
      help="Use SSL",
      kind=OptKind::Flag(default=false),
      inversion=Some(FlagInversion::PrefixWithWithout),
    ),
    // index 3: output (aliases あり, shorts あり)
    OptDef::new(
      long="output",
      help="Output file",
      kind=OptKind::Single(default=None),
      aliases=[AliasEntry::new(name="out"), AliasEntry::new(name="output-file")],
      shorts=[ShortEntry::new(char='o')],
    ),
    // index 4: format (inversion なし)
    OptDef::new(
      long="format",
      help="Output format",
      kind=OptKind::Single(default=Some("json")),
    ),
  ]
}

// === resolve_long テスト ===

///|
test "resolve_long: long 名完全一致" {
  let opts = make_test_opts()
  let result = resolve_long(opts, "verbose")
  inspect(result.index, content="0")
  inspect(result.direction, content="Normal")
}

///|
test "resolve_long: エイリアス一致" {
  let opts = make_test_opts()
  let result = resolve_long(opts, "out")
  inspect(result.index, content="3")
  inspect(result.direction, content="Normal")
}

///|
test "resolve_long: エイリアス一致 (output-file)" {
  let opts = make_test_opts()
  let result = resolve_long(opts, "output-file")
  inspect(result.index, content="3")
  inspect(result.direction, content="Normal")
}

///|
test "resolve_long: PrefixNo 反転 (no-verbose)" {
  let opts = make_test_opts()
  let result = resolve_long(opts, "no-verbose")
  inspect(result.index, content="0")
  inspect(result.direction, content="Inverted")
}

///|
test "resolve_long: PrefixEnableDisable 正方向 (enable-cache)" {
  let opts = make_test_opts()
  let result = resolve_long(opts, "enable-cache")
  inspect(result.index, content="1")
  inspect(result.direction, content="Normal")
}

///|
test "resolve_long: PrefixEnableDisable 反転 (disable-cache)" {
  let opts = make_test_opts()
  let result = resolve_long(opts, "disable-cache")
  inspect(result.index, content="1")
  inspect(result.direction, content="Inverted")
}

///|
test "resolve_long: PrefixWithWithout 正方向 (with-ssl)" {
  let opts = make_test_opts()
  let result = resolve_long(opts, "with-ssl")
  inspect(result.index, content="2")
  inspect(result.direction, content="Normal")
}

///|
test "resolve_long: PrefixWithWithout 反転 (without-ssl)" {
  let opts = make_test_opts()
  let result = resolve_long(opts, "without-ssl")
  inspect(result.index, content="2")
  inspect(result.direction, content="Inverted")
}

///|
test "resolve_long: マッチなし → UnknownOption" {
  let opts = make_test_opts()
  let result : Result[ResolveResult, Error] = try? resolve_long(
    opts, "nonexistent",
  )
  inspect(
    result,
    content=(
      #|Err(UnknownOption("--nonexistent"))
    ),
  )
}

///|
test "resolve_long: inversion なしのオプションに no- プレフィックスを付けてもマッチしない" {
  let opts = make_test_opts()
  let result : Result[ResolveResult, Error] = try? resolve_long(
    opts, "no-format",
  )
  inspect(
    result,
    content=(
      #|Err(UnknownOption("--no-format"))
    ),
  )
}

// === resolve_short テスト ===

///|
test "resolve_short: 一致" {
  let opts = make_test_opts()
  let result = resolve_short(opts, 'v')
  inspect(result.index, content="0")
  inspect(result.direction, content="Normal")
}

///|
test "resolve_short: 別のショートオプション一致" {
  let opts = make_test_opts()
  let result = resolve_short(opts, 'o')
  inspect(result.index, content="3")
  inspect(result.direction, content="Normal")
}

///|
test "resolve_short: マッチなし → UnknownOption" {
  let opts = make_test_opts()
  let result : Result[ResolveResult, Error] = try? resolve_short(opts, 'x')
  inspect(
    result,
    content=(
      #|Err(UnknownOption("-x"))
    ),
  )
}
