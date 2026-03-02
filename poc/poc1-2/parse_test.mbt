// === parse 関数テスト ===

// --- 基本テスト ---

///|
test "parse: empty args with defaults" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose output",
      kind=OptKind::Flag(default=false),
    ),
    OptDef::new(
      long="format",
      help="Output format",
      kind=OptKind::Single(default=Some("json")),
    ),
    OptDef::new(
      long="eval",
      help="Expressions",
      kind=OptKind::Append(n=1, defaults=["default-expr"]),
    ),
  ]
  let result = parse(opts, [])
  inspect(result.get_flag("verbose"), content="false")
  inspect(
    result.get_string("format"),
    content=(
      #|Some("json")
    ),
  )
  inspect(
    result.get_list("eval"),
    content=(
      #|["default-expr"]
    ),
  )
  inspect(result.positional, content="[]")
  inspect(result.rest, content="[]")
}

///|
test "parse: long flag" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let result = parse(opts, ["--verbose"])
  inspect(result.get_flag("verbose"), content="true")
}

///|
test "parse: long single with separate value" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="format",
      help="Format",
      kind=OptKind::Single(default=None),
    ),
  ]
  let result = parse(opts, ["--format", "yaml"])
  inspect(
    result.get_string("format"),
    content=(
      #|Some("yaml")
    ),
  )
}

///|
test "parse: long option --key=value form" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="format",
      help="Format",
      kind=OptKind::Single(default=None),
    ),
  ]
  let result = parse(opts, ["--format=yaml"])
  inspect(
    result.get_string("format"),
    content=(
      #|Some("yaml")
    ),
  )
}

///|
test "parse: long accumulate" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="eval",
      help="Eval",
      kind=OptKind::Append(n=1, defaults=[]),
    ),
  ]
  let result = parse(opts, ["--eval", "1+1", "--eval", "2+2"])
  inspect(
    result.get_list("eval"),
    content=(
      #|["1+1", "2+2"]
    ),
  )
}

///|
test "parse: positional only" {
  let opts : Array[OptDef] = []
  let result = parse(opts, ["file1.txt", "file2.txt"])
  inspect(
    result.positional,
    content=(
      #|["file1.txt", "file2.txt"]
    ),
  )
  inspect(result.rest, content="[]")
}

///|
test "parse: double dash separator" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let result = parse(opts, ["--verbose", "--", "--not-an-option", "file.txt"])
  inspect(result.get_flag("verbose"), content="true")
  inspect(result.positional, content="[]")
  inspect(
    result.rest,
    content=(
      #|["--not-an-option", "file.txt"]
    ),
  )
}

// --- 反転テスト ---

///|
test "parse: PrefixNo inversion --no-verbose" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=true),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = parse(opts, ["--no-verbose"])
  inspect(result.get_flag("verbose"), content="false")
}

///|
test "parse: PrefixEnableDisable --disable-cache" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="cache",
      help="Cache",
      kind=OptKind::Flag(default=true),
      inversion=Some(FlagInversion::PrefixEnableDisable),
    ),
  ]
  let result = parse(opts, ["--disable-cache"])
  inspect(result.get_flag("cache"), content="false")
}

///|
test "parse: PrefixEnableDisable --enable-cache" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="cache",
      help="Cache",
      kind=OptKind::Flag(default=false),
      inversion=Some(FlagInversion::PrefixEnableDisable),
    ),
  ]
  let result = parse(opts, ["--enable-cache"])
  inspect(result.get_flag("cache"), content="true")
}

// --- ショートオプション ---

///|
test "parse: short flag -v" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
      shorts=[ShortEntry::new(char='v')],
    ),
  ]
  let result = parse(opts, ["-v"])
  inspect(result.get_flag("verbose"), content="true")
}

///|
test "parse: short combined flags -abc" {
  let opts : Array[OptDef] = [
    OptDef::new(long="aaa", help="A", kind=OptKind::Flag(default=false), shorts=[
      ShortEntry::new(char='a'),
    ]),
    OptDef::new(long="bbb", help="B", kind=OptKind::Flag(default=false), shorts=[
      ShortEntry::new(char='b'),
    ]),
    OptDef::new(long="ccc", help="C", kind=OptKind::Flag(default=false), shorts=[
      ShortEntry::new(char='c'),
    ]),
  ]
  let result = parse(opts, ["-abc"])
  inspect(result.get_flag("aaa"), content="true")
  inspect(result.get_flag("bbb"), content="true")
  inspect(result.get_flag("ccc"), content="true")
}

///|
test "parse: short single -f value" {
  let opts : Array[OptDef] = [
    OptDef::new(long="file", help="File", kind=OptKind::Single(default=None), shorts=[
      ShortEntry::new(char='f'),
    ]),
  ]
  let result = parse(opts, ["-f", "output.txt"])
  inspect(
    result.get_string("file"),
    content=(
      #|Some("output.txt")
    ),
  )
}

///|
test "parse: short combined -abcVALUE (a,b=Flag, c=Single)" {
  let opts : Array[OptDef] = [
    OptDef::new(long="aaa", help="A", kind=OptKind::Flag(default=false), shorts=[
      ShortEntry::new(char='a'),
    ]),
    OptDef::new(long="bbb", help="B", kind=OptKind::Flag(default=false), shorts=[
      ShortEntry::new(char='b'),
    ]),
    OptDef::new(long="file", help="File", kind=OptKind::Single(default=None), shorts=[
      ShortEntry::new(char='c'),
    ]),
  ]
  let result = parse(opts, ["-abcVALUE"])
  inspect(result.get_flag("aaa"), content="true")
  inspect(result.get_flag("bbb"), content="true")
  inspect(
    result.get_string("file"),
    content=(
      #|Some("VALUE")
    ),
  )
}

// --- デフォルト値 ---

///|
test "parse: default flag value applied" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=true),
    ),
  ]
  let result = parse(opts, [])
  inspect(result.get_flag("verbose"), content="true")
}

///|
test "parse: default single Some applied" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="format",
      help="Format",
      kind=OptKind::Single(default=Some("json")),
    ),
  ]
  let result = parse(opts, [])
  inspect(
    result.get_string("format"),
    content=(
      #|Some("json")
    ),
  )
}

///|
test "parse: default accumulate applied" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="eval",
      help="Eval",
      kind=OptKind::Append(n=1, defaults=["a"]),
    ),
  ]
  let result = parse(opts, [])
  inspect(
    result.get_list("eval"),
    content=(
      #|["a"]
    ),
  )
}

///|
test "parse: default single None not in values" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="config",
      help="Config",
      kind=OptKind::Single(default=None),
    ),
  ]
  let result = parse(opts, [])
  inspect(result.values.contains("config"), content="false")
}

///|
test "parse: default accumulate empty array applied" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="eval",
      help="Eval",
      kind=OptKind::Append(n=1, defaults=[]),
    ),
  ]
  let result = parse(opts, [])
  inspect(result.get_list("eval"), content="[]")
  inspect(result.values.contains("eval"), content="true")
}

// --- エラーケース ---

///|
test "parse: unknown option" {
  let opts : Array[OptDef] = []
  let result : Result[ParseResult, Error] = try? parse(opts, ["--unknown"])
  inspect(
    result,
    content=(
      #|Err(UnknownOption("--unknown"))
    ),
  )
}

///|
test "parse: missing value for single" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="format",
      help="Format",
      kind=OptKind::Single(default=None),
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(opts, ["--format"])
  inspect(
    result,
    content=(
      #|Err(MissingValue("--format"))
    ),
  )
}

///|
test "parse: missing required" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="output",
      help="Output",
      kind=OptKind::Single(default=None),
      required=true,
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(opts, [])
  inspect(
    result,
    content=(
      #|Err(MissingRequired("--output"))
    ),
  )
}

///|
test "parse: invalid choice" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="format",
      help="Format",
      kind=OptKind::Single(default=None),
      choices=["json", "yaml"],
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(opts, ["--format", "xml"])
  inspect(
    result,
    content=(
      #|Err(InvalidChoice(option="format", value="xml", choices=["json", "yaml"]))
    ),
  )
}

///|
test "parse: --help raises HelpRequested" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(opts, ["--help"])
  inspect(
    result,
    content=(
      #|Err(HelpRequested)
    ),
  )
}

///|
test "parse: --help with custom help opt is normal option" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="help",
      help="Show help",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let result = parse(opts, ["--help"])
  inspect(result.get_flag("help"), content="true")
}

// --- 統合テスト ---

///|
test "parse: mixed args integration" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
      shorts=[ShortEntry::new(char='v')],
      inversion=Some(FlagInversion::PrefixNo),
    ),
    OptDef::new(
      long="format",
      help="Format",
      kind=OptKind::Single(default=Some("json")),
      choices=["json", "yaml", "text"],
    ),
    OptDef::new(
      long="eval",
      help="Eval",
      kind=OptKind::Append(n=1, defaults=[]),
      shorts=[ShortEntry::new(char='e')],
    ),
    OptDef::new(
      long="output",
      help="Output",
      kind=OptKind::Single(default=None),
      shorts=[ShortEntry::new(char='o')],
    ),
  ]
  let result = parse(opts, [
    "-v", "--format=yaml", "-e", "1+1", "--eval", "2+2", "input.txt", "--", "extra1",
    "extra2",
  ])
  inspect(result.get_flag("verbose"), content="true")
  inspect(
    result.get_string("format"),
    content=(
      #|Some("yaml")
    ),
  )
  inspect(
    result.get_list("eval"),
    content=(
      #|["1+1", "2+2"]
    ),
  )
  inspect(result.get_string("output"), content="None")
  inspect(
    result.positional,
    content=(
      #|["input.txt"]
    ),
  )
  inspect(
    result.rest,
    content=(
      #|["extra1", "extra2"]
    ),
  )
}

///|
test "parse: LongOptWithValue for flag (--verbose=true)" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let result = parse(opts, ["--verbose=true"])
  inspect(result.get_flag("verbose"), content="true")
}

///|
test "parse: LongOptWithValue for flag (--verbose=false)" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let result = parse(opts, ["--verbose=false"])
  inspect(result.get_flag("verbose"), content="false")
}

///|
test "parse: accumulate with --key=value form" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="eval",
      help="Eval",
      kind=OptKind::Append(n=1, defaults=[]),
    ),
  ]
  let result = parse(opts, ["--eval=first", "--eval=second"])
  inspect(
    result.get_list("eval"),
    content=(
      #|["first", "second"]
    ),
  )
}

///|
test "parse: short accumulate consumes next token" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="eval",
      help="Eval",
      kind=OptKind::Append(n=1, defaults=[]),
      shorts=[ShortEntry::new(char='e')],
    ),
  ]
  let result = parse(opts, ["-e", "expr1", "-e", "expr2"])
  inspect(
    result.get_list("eval"),
    content=(
      #|["expr1", "expr2"]
    ),
  )
}

///|
test "parse: missing value for short single" {
  let opts : Array[OptDef] = [
    OptDef::new(long="file", help="File", kind=OptKind::Single(default=None), shorts=[
      ShortEntry::new(char='f'),
    ]),
  ]
  let result : Result[ParseResult, Error] = try? parse(opts, ["-f"])
  inspect(
    result,
    content=(
      #|Err(MissingValue("-f"))
    ),
  )
}

///|
test "parse: required option satisfied" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="output",
      help="Output",
      kind=OptKind::Single(default=None),
      required=true,
    ),
  ]
  let result = parse(opts, ["--output", "out.txt"])
  inspect(
    result.get_string("output"),
    content=(
      #|Some("out.txt")
    ),
  )
}

///|
test "parse: choices valid value passes" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="format",
      help="Format",
      kind=OptKind::Single(default=None),
      choices=["json", "yaml"],
    ),
  ]
  let result = parse(opts, ["--format", "json"])
  inspect(
    result.get_string("format"),
    content=(
      #|Some("json")
    ),
  )
}

// --- Flag=非bool値エラー (#84 W1) ---

///|
test "parse: --verbose=banana raises InvalidChoice" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(opts, [
    "--verbose=banana",
  ])
  inspect(
    result,
    content=(
      #|Err(InvalidChoice(option="verbose", value="banana", choices=["true", "false"]))
    ),
  )
}

// --- Single+Inverted (#84 W3) ---

///|
test "parse: --no-format (Single+Inverted) clears value" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="format",
      help="Format",
      kind=OptKind::Single(default=Some("json")),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = parse(opts, ["--no-format"])
  // --no-format は値をクリアするので、デフォルトも適用されない
  inspect(result.values.contains("format"), content="false")
  inspect(result.get_string("format"), content="None")
}

///|
test "parse: --no-eval (Append+Inverted) resets list" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="eval",
      help="Eval",
      kind=OptKind::Append(n=1, defaults=["default-expr"]),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = parse(opts, ["--eval", "first", "--no-eval"])
  // --no-eval でリストがリセットされ、明示設定扱いなのでデフォルトも適用されない
  inspect(result.get_list("eval"), content="[]")
}

///|
test "parse: --no-format does not consume next token" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="format",
      help="Format",
      kind=OptKind::Single(default=Some("json")),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = parse(opts, ["--no-format", "file.txt"])
  // --no-format は次のトークンを消費しない → file.txt は positional
  inspect(result.get_string("format"), content="None")
  inspect(
    result.positional,
    content=(
      #|["file.txt"]
    ),
  )
}

// --- C5: 追加テスト ---

///|
test "parse: --help=value raises HelpRequested" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(opts, ["--help=yes"])
  inspect(
    result,
    content=(
      #|Err(HelpRequested)
    ),
  )
}

///|
test "parse: -eEXPR (Append short combined)" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="eval",
      help="Eval",
      kind=OptKind::Append(n=1, defaults=[]),
      shorts=[ShortEntry::new(char='e')],
    ),
  ]
  let result = parse(opts, ["-eEXPR"])
  inspect(
    result.get_list("eval"),
    content=(
      #|["EXPR"]
    ),
  )
}

///|
test "parse: Append MissingValue at end" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="eval",
      help="Eval",
      kind=OptKind::Append(n=1, defaults=[]),
      shorts=[ShortEntry::new(char='e')],
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(opts, ["-e"])
  inspect(
    result,
    content=(
      #|Err(MissingValue("-e"))
    ),
  )
}

///|
test "parse: Single last wins" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="format",
      help="Format",
      kind=OptKind::Single(default=None),
    ),
  ]
  let result = parse(opts, ["--format", "json", "--format", "yaml"])
  inspect(
    result.get_string("format"),
    content=(
      #|Some("yaml")
    ),
  )
}

///|
test "parse: empty string argument" {
  let opts : Array[OptDef] = []
  let result = parse(opts, [""])
  inspect(
    result.positional,
    content=(
      #|[""]
    ),
  )
}

///|
test "parse: -- only" {
  let opts : Array[OptDef] = []
  let result = parse(opts, ["--"])
  inspect(result.positional, content="[]")
  inspect(result.rest, content="[]")
}

///|
test "parse: --no-format then --format yaml (Single clear then set)" {
  let opts = [
    OptDef::new(
      long="format",
      help="format",
      kind=OptKind::Single(default=Some("json")),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let r = parse(opts, ["--no-format", "--format", "yaml"])
  inspect(
    r.get_string("format"),
    content=(
      #|Some("yaml")
    ),
  )
}

///|
test "parse: --no-format=ignored (LongOptWithValue + Single + Inverted)" {
  let opts = [
    OptDef::new(
      long="format",
      help="format",
      kind=OptKind::Single(default=Some("json")),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let r = parse(opts, ["--no-format=ignored"])
  inspect(r.get_string("format"), content="None")
}

///|
test "parse: --no-eval=ignored (LongOptWithValue + Append + Inverted)" {
  let opts = [
    OptDef::new(
      long="eval",
      help="eval",
      kind=OptKind::Append(n=1, defaults=["a"]),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let r = parse(opts, ["--eval", "b", "--no-eval=whatever"])
  inspect(r.get_list("eval"), content="[]")
}

///|
test "parse: --no-verbose=true (LongOptWithValue + Flag + Inverted)" {
  let opts = [
    OptDef::new(
      long="verbose",
      help="verbose",
      kind=OptKind::Flag(default=false),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let r = parse(opts, ["--no-verbose=true"])
  inspect(r.get_flag("verbose"), content="false")
}

///|
test "parse: --no-verbose=false (LongOptWithValue + Flag + Inverted)" {
  let opts = [
    OptDef::new(
      long="verbose",
      help="verbose",
      kind=OptKind::Flag(default=false),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let r = parse(opts, ["--no-verbose=false"])
  inspect(r.get_flag("verbose"), content="true")
}

///|
test "parse: short option MissingValue shows short form" {
  let opts = [
    OptDef::new(
      long="format",
      help="format",
      kind=OptKind::Single(default=None),
      shorts=[ShortEntry::new(char='f')],
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(opts, ["-f"])
  inspect(
    result,
    content=(
      #|Err(MissingValue("-f"))
    ),
  )
}

// === Count テスト ===

///|
test "parse Count: --verbose" {
  let opts = [
    OptDef::new(
      long="verbose",
      help="Verbosity",
      kind=OptKind::Count(default=0),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = parse(opts, ["--verbose"])
  inspect(result.get_count("verbose"), content="1")
}

///|
test "parse Count: -v" {
  let opts = [
    OptDef::new(
      long="verbose",
      help="Verbosity",
      kind=OptKind::Count(default=0),
      shorts=[ShortEntry::new(char='v')],
    ),
  ]
  let result = parse(opts, ["-v"])
  inspect(result.get_count("verbose"), content="1")
}

///|
test "parse Count: -vvv" {
  let opts = [
    OptDef::new(
      long="verbose",
      help="Verbosity",
      kind=OptKind::Count(default=0),
      shorts=[ShortEntry::new(char='v')],
    ),
  ]
  let result = parse(opts, ["-vvv"])
  inspect(result.get_count("verbose"), content="3")
}

///|
test "parse Count: -v -v --verbose" {
  let opts = [
    OptDef::new(
      long="verbose",
      help="Verbosity",
      kind=OptKind::Count(default=0),
      shorts=[ShortEntry::new(char='v')],
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = parse(opts, ["-v", "-v", "--verbose"])
  inspect(result.get_count("verbose"), content="3")
}

///|
test "parse Count: --no-verbose resets" {
  let opts = [
    OptDef::new(
      long="verbose",
      help="Verbosity",
      kind=OptKind::Count(default=0),
      shorts=[ShortEntry::new(char='v')],
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = parse(opts, ["-vvv", "--no-verbose"])
  inspect(result.get_count("verbose"), content="0")
}

///|
test "parse Count: --no-verbose -vv" {
  let opts = [
    OptDef::new(
      long="verbose",
      help="Verbosity",
      kind=OptKind::Count(default=0),
      shorts=[ShortEntry::new(char='v')],
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = parse(opts, ["--no-verbose", "-vv"])
  inspect(result.get_count("verbose"), content="2")
}

///|
test "parse Count: default" {
  let opts = [
    OptDef::new(
      long="verbose",
      help="Verbosity",
      kind=OptKind::Count(default=0),
    ),
  ]
  let result = parse(opts, [])
  inspect(result.get_count("verbose"), content="0")
}

///|
test "parse Count: -vxv mixed short" {
  let opts = [
    OptDef::new(
      long="verbose",
      help="Verbosity",
      kind=OptKind::Count(default=0),
      shorts=[ShortEntry::new(char='v')],
    ),
    OptDef::new(long="xxx", help="X flag", kind=OptKind::Flag(default=false), shorts=[
      ShortEntry::new(char='x'),
    ]),
  ]
  let result = parse(opts, ["-vxv"])
  // v=1 (first v), x=true, v=1 more → v=2
  inspect(result.get_count("verbose"), content="2")
  inspect(result.get_flag("xxx"), content="true")
}

///|
test "parse Count: LongOptWithValue --verbose=ignored" {
  let opts = [
    OptDef::new(
      long="verbose",
      help="Verbosity",
      kind=OptKind::Count(default=0),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = parse(opts, ["--verbose=3"])
  // Count ignores the value in = form, just increments
  inspect(result.get_count("verbose"), content="1")
}

///|
test "parse Count: non-zero default" {
  let opts = [
    OptDef::new(
      long="verbose",
      help="Verbosity",
      kind=OptKind::Count(default=2),
    ),
  ]
  let result = parse(opts, [])
  inspect(result.get_count("verbose"), content="2")
}

// === OptionalValue テスト ===

///|
test "parse OptionalValue: --color" {
  let opts = [
    OptDef::new(
      long="color",
      help="Color output",
      kind=OptKind::OptionalValue(
        default=None,
        implicit="auto",
        negated=Some("never"),
      ),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = parse(opts, ["--color"])
  inspect(
    result.get_string("color"),
    content=(
      #|Some("auto")
    ),
  )
}

///|
test "parse OptionalValue: --color=always" {
  let opts = [
    OptDef::new(
      long="color",
      help="Color output",
      kind=OptKind::OptionalValue(
        default=None,
        implicit="auto",
        negated=Some("never"),
      ),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = parse(opts, ["--color=always"])
  inspect(
    result.get_string("color"),
    content=(
      #|Some("always")
    ),
  )
}

///|
test "parse OptionalValue: --color xxx (no lookahead)" {
  let opts = [
    OptDef::new(
      long="color",
      help="Color output",
      kind=OptKind::OptionalValue(
        default=None,
        implicit="auto",
        negated=Some("never"),
      ),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = parse(opts, ["--color", "xxx"])
  // xxx is NOT consumed as value, it becomes positional
  inspect(
    result.get_string("color"),
    content=(
      #|Some("auto")
    ),
  )
  inspect(
    result.positional,
    content=(
      #|["xxx"]
    ),
  )
}

///|
test "parse OptionalValue: --no-color" {
  let opts = [
    OptDef::new(
      long="color",
      help="Color output",
      kind=OptKind::OptionalValue(
        default=None,
        implicit="auto",
        negated=Some("never"),
      ),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = parse(opts, ["--no-color"])
  inspect(
    result.get_string("color"),
    content=(
      #|Some("never")
    ),
  )
}

///|
test "parse OptionalValue: --no-color with negated=None removes" {
  let opts = [
    OptDef::new(
      long="color",
      help="Color output",
      kind=OptKind::OptionalValue(
        default=Some("auto"),
        implicit="auto",
        negated=None,
      ),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = parse(opts, ["--no-color"])
  // negated=None means remove from values
  inspect(result.values.contains("color"), content="false")
  inspect(result.get_string("color"), content="None")
}

///|
test "parse OptionalValue: --no-color=xxx ignores value" {
  let opts = [
    OptDef::new(
      long="color",
      help="Color output",
      kind=OptKind::OptionalValue(
        default=None,
        implicit="auto",
        negated=Some("never"),
      ),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = parse(opts, ["--no-color=xxx"])
  // negated applied, value ignored
  inspect(
    result.get_string("color"),
    content=(
      #|Some("never")
    ),
  )
}

///|
test "parse OptionalValue: default Some" {
  let opts = [
    OptDef::new(
      long="color",
      help="Color output",
      kind=OptKind::OptionalValue(
        default=Some("auto"),
        implicit="auto",
        negated=Some("never"),
      ),
    ),
  ]
  let result = parse(opts, [])
  inspect(
    result.get_string("color"),
    content=(
      #|Some("auto")
    ),
  )
}

///|
test "parse OptionalValue: default None" {
  let opts = [
    OptDef::new(
      long="color",
      help="Color output",
      kind=OptKind::OptionalValue(
        default=None,
        implicit="auto",
        negated=Some("never"),
      ),
    ),
  ]
  let result = parse(opts, [])
  inspect(result.values.contains("color"), content="false")
}

///|
test "parse OptionalValue: choices validation passes" {
  let opts = [
    OptDef::new(
      long="color",
      help="Color output",
      kind=OptKind::OptionalValue(
        default=None,
        implicit="auto",
        negated=Some("never"),
      ),
      choices=["auto", "always", "never"],
    ),
  ]
  let result = parse(opts, ["--color=always"])
  inspect(
    result.get_string("color"),
    content=(
      #|Some("always")
    ),
  )
}

///|
test "parse OptionalValue: choices validation fails" {
  let opts = [
    OptDef::new(
      long="color",
      help="Color output",
      kind=OptKind::OptionalValue(
        default=None,
        implicit="auto",
        negated=Some("never"),
      ),
      choices=["auto", "always", "never"],
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(opts, ["--color=invalid"])
  inspect(
    result,
    content=(
      #|Err(InvalidChoice(option="color", value="invalid", choices=["auto", "always", "never"]))
    ),
  )
}

///|
test "parse OptionalValue: no short allowed" {
  let opts = [
    OptDef::new(
      long="color",
      help="Color output",
      kind=OptKind::OptionalValue(default=None, implicit="auto", negated=None),
      shorts=[ShortEntry::new(char='c')],
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(opts, ["--color"])
  inspect(
    result,
    content=(
      #|Err(DefinitionError("OptionalValue cannot have short options: --color"))
    ),
  )
}

// === Append n=2 テスト ===

///|
test "parse Append n=2: --arg k v" {
  let opts = [
    OptDef::new(
      long="arg",
      help="Key-value pair",
      kind=OptKind::Append(n=2, defaults=[]),
    ),
  ]
  let result = parse(opts, ["--arg", "k", "v"])
  inspect(
    result.get_list("arg"),
    content=(
      #|["k", "v"]
    ),
  )
}

///|
test "parse Append n=2: --arg k1 v1 --arg k2 v2" {
  let opts = [
    OptDef::new(
      long="arg",
      help="Key-value pair",
      kind=OptKind::Append(n=2, defaults=[]),
    ),
  ]
  let result = parse(opts, ["--arg", "k1", "v1", "--arg", "k2", "v2"])
  inspect(
    result.get_list("arg"),
    content=(
      #|["k1", "v1", "k2", "v2"]
    ),
  )
}

///|
test "parse Append n=2: --arg k (missing v)" {
  let opts = [
    OptDef::new(
      long="arg",
      help="Key-value pair",
      kind=OptKind::Append(n=2, defaults=[]),
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(opts, ["--arg", "k"])
  inspect(
    result,
    content=(
      #|Err(MissingValue("--arg"))
    ),
  )
}

///|
test "parse Append n=2: --arg=k (= form)" {
  let opts = [
    OptDef::new(
      long="arg",
      help="Key-value pair",
      kind=OptKind::Append(n=2, defaults=[]),
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(opts, ["--arg=k"])
  inspect(
    result,
    content=(
      #|Err(MissingValue("--arg"))
    ),
  )
}

///|
test "parse Append n=2: --no-arg resets" {
  let opts = [
    OptDef::new(
      long="arg",
      help="Key-value pair",
      kind=OptKind::Append(n=2, defaults=[]),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = parse(opts, ["--arg", "k", "v", "--no-arg"])
  inspect(result.get_list("arg"), content="[]")
}

///|
test "parse Append n=2: -a k v (short)" {
  let opts = [
    OptDef::new(
      long="arg",
      help="Key-value pair",
      kind=OptKind::Append(n=2, defaults=[]),
      shorts=[ShortEntry::new(char='a')],
    ),
  ]
  let result = parse(opts, ["-a", "k", "v"])
  inspect(
    result.get_list("arg"),
    content=(
      #|["k", "v"]
    ),
  )
}

///|
test "parse Append n=2: -ak v (short with remaining)" {
  let opts = [
    OptDef::new(
      long="arg",
      help="Key-value pair",
      kind=OptKind::Append(n=2, defaults=[]),
      shorts=[ShortEntry::new(char='a')],
    ),
  ]
  let result = parse(opts, ["-ak", "v"])
  inspect(
    result.get_list("arg"),
    content=(
      #|["k", "v"]
    ),
  )
}

///|
test "parse Append n=3: --arg a b c" {
  let opts = [
    OptDef::new(
      long="arg",
      help="Triple",
      kind=OptKind::Append(n=3, defaults=[]),
    ),
  ]
  let result = parse(opts, ["--arg", "a", "b", "c"])
  inspect(
    result.get_list("arg"),
    content=(
      #|["a", "b", "c"]
    ),
  )
}

///|
test "parse Append n=2: short missing second value" {
  let opts = [
    OptDef::new(
      long="arg",
      help="Key-value pair",
      kind=OptKind::Append(n=2, defaults=[]),
      shorts=[ShortEntry::new(char='a')],
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(opts, ["-a", "k"])
  inspect(
    result,
    content=(
      #|Err(MissingValue("-a"))
    ),
  )
}

///|
test "parse Append n=2: defaults applied" {
  let opts = [
    OptDef::new(
      long="arg",
      help="Key-value pair",
      kind=OptKind::Append(n=2, defaults=["dk", "dv"]),
    ),
  ]
  let result = parse(opts, [])
  inspect(
    result.get_list("arg"),
    content=(
      #|["dk", "dv"]
    ),
  )
}

// === W8: 追加テスト ===

///|
test "parse: --format -- consumes DoubleDash as value" {
  let opts = [
    OptDef::new(
      long="format",
      help="Format",
      kind=OptKind::Single(default=None),
    ),
  ]
  let result = parse(opts, ["--format", "--"])
  inspect(
    result.get_string("format"),
    content=(
      #|Some("--")
    ),
  )
}

// === --version 特殊処理テスト ===

///|
test "parse: --version raises VersionRequested" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(opts, ["--version"])
  inspect(
    result,
    content=(
      #|Err(VersionRequested)
    ),
  )
}

///|
test "parse: --version with custom version opt is normal option" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="version",
      help="Show version",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let result = parse(opts, ["--version"])
  inspect(result.get_flag("version"), content="true")
}

///|
test "parse: --format --version consumes --version as value for Single" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="format",
      help="Format",
      kind=OptKind::Single(default=None),
    ),
  ]
  let result = parse(opts, ["--format", "--version"])
  inspect(
    result.get_string("format"),
    content=(
      #|Some("--version")
    ),
  )
}

///|
test "parse: -- --version is Positional (not VersionRequested)" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let result = parse(opts, ["--", "--version"])
  inspect(
    result.rest,
    content=(
      #|["--version"]
    ),
  )
}

///|
test "parse: -V in ShortOpts does not trigger VersionRequested" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
      shorts=[ShortEntry::new(char='V')],
    ),
  ]
  let result = parse(opts, ["-V"])
  inspect(result.get_flag("verbose"), content="true")
}

///|
test "parse: --version=value raises VersionRequested" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(opts, ["--version=1.0"])
  inspect(
    result,
    content=(
      #|Err(VersionRequested)
    ),
  )
}

///|
test "parse: Append choices validation" {
  let opts = [
    OptDef::new(
      long="eval",
      help="Eval",
      kind=OptKind::Append(n=1, defaults=[]),
      choices=["valid1", "valid2"],
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(opts, [
    "--eval", "valid1", "--eval", "invalid",
  ])
  inspect(
    result,
    content=(
      #|Err(InvalidChoice(option="eval", value="invalid", choices=["valid1", "valid2"]))
    ),
  )
}

// === Group パーステスト (Step 4b) ===

///|
test "parse Group: WithValue basic" {
  // --upstream u1 --socket s1 → GroupValue([{value: Some("u1"), result: {socket: "s1"}}])
  let opts : Array[OptDef] = [
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=None),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket path",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result = parse(opts, ["--upstream", "u1", "--socket", "s1"])
  let groups = result.get_group("upstream")
  inspect(
    groups,
    content=(
      #|Some([{value: Some("u1"), result: {values: {"socket": StringValue("s1")}, positional: [], rest: [], chunk_sizes: {}}}])
    ),
  )
}

///|
test "parse Group: WithValue multiple instances" {
  // --upstream u1 --socket s1 --upstream u2 --socket s2 → 2 instances
  let opts : Array[OptDef] = [
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=None),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket path",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result = parse(opts, [
    "--upstream", "u1", "--socket", "s1", "--upstream", "u2", "--socket", "s2",
  ])
  let groups = result.get_group("upstream")
  inspect(
    groups,
    content=(
      #|Some([{value: Some("u1"), result: {values: {"socket": StringValue("s1")}, positional: [], rest: [], chunk_sizes: {}}}, {value: Some("u2"), result: {values: {"socket": StringValue("s2")}, positional: [], rest: [], chunk_sizes: {}}}])
    ),
  )
}

///|
test "parse Group: WithValue merge same value" {
  // --upstream u1 --socket s1 --upstream u1 --socket s2 → merge (socket last wins)
  let opts : Array[OptDef] = [
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=None),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket path",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result = parse(opts, [
    "--upstream", "u1", "--socket", "s1", "--upstream", "u1", "--socket", "s2",
  ])
  let groups = result.get_group("upstream")
  inspect(
    groups,
    content=(
      #|Some([{value: Some("u1"), result: {values: {"socket": StringValue("s2")}, positional: [], rest: [], chunk_sizes: {}}}])
    ),
  )
}

///|
test "parse Group: Valueless basic" {
  // --rule --target x → GroupValue([{value: None, result: {target: "x"}}])
  let opts : Array[OptDef] = [
    OptDef::new(
      long="rule",
      help="Rule",
      kind=OptKind::Group(
        group_kind=GroupKind::Valueless,
        opts=[
          OptDef::new(
            long="target",
            help="Target",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result = parse(opts, ["--rule", "--target", "x"])
  let groups = result.get_group("rule")
  inspect(
    groups,
    content=(
      #|Some([{value: None, result: {values: {"target": StringValue("x")}, positional: [], rest: [], chunk_sizes: {}}}])
    ),
  )
}

///|
test "parse Group: Valueless multiple instances" {
  // --rule --target x --rule --target y → 2 instances (always append)
  let opts : Array[OptDef] = [
    OptDef::new(
      long="rule",
      help="Rule",
      kind=OptKind::Group(
        group_kind=GroupKind::Valueless,
        opts=[
          OptDef::new(
            long="target",
            help="Target",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result = parse(opts, [
    "--rule", "--target", "x", "--rule", "--target", "y",
  ])
  let groups = result.get_group("rule")
  inspect(
    groups,
    content=(
      #|Some([{value: None, result: {values: {"target": StringValue("x")}, positional: [], rest: [], chunk_sizes: {}}}, {value: None, result: {values: {"target": StringValue("y")}, positional: [], rest: [], chunk_sizes: {}}}])
    ),
  )
}

///|
test "parse Group: Disallowed positional in child scope raises error" {
  // Step 5: Disallowed + 位置引数 → UnexpectedPositional
  let opts : Array[OptDef] = [
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=None),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket path",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(opts, [
    "--upstream", "u1", "arg1",
  ])
  inspect(
    result,
    content=(
      #|Err(UnexpectedPositional(context="--upstream u1", value="arg1"))
    ),
  )
}

///|
test "parse Group: with parent option" {
  // --verbose --upstream u1 --socket s1 --verbose → verbose は親 opt
  // 子スコープ内の --verbose はフォールバックで子の result に入る
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose output",
      kind=OptKind::Flag(default=false),
    ),
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=None),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket path",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result = parse(opts, ["--verbose", "--upstream", "u1", "--socket", "s1"])
  // 親スコープの verbose
  inspect(
    result.get_flag("verbose"),
    content=(
      #|true
    ),
  )
  let groups = result.get_group("upstream")
  inspect(
    groups,
    content=(
      #|Some([{value: Some("u1"), result: {values: {"socket": StringValue("s1")}, positional: [], rest: [], chunk_sizes: {}}}])
    ),
  )
}

///|
test "parse Group: --no-xxx clears GroupValue" {
  // --upstream u1 --socket s1 --no-upstream → GroupValue cleared
  let opts : Array[OptDef] = [
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=None),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket path",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = parse(opts, [
    "--upstream", "u1", "--socket", "s1", "--no-upstream",
  ])
  let groups = result.get_group("upstream")
  inspect(
    groups,
    content=(
      #|Some([])
    ),
  )
}

///|
test "parse Group: --upstream=u1 form (LongOptWithValue)" {
  // --upstream=u1 --socket s1 → WithValue with =value
  let opts : Array[OptDef] = [
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=None),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket path",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result = parse(opts, ["--upstream=u1", "--socket", "s1"])
  let groups = result.get_group("upstream")
  inspect(
    groups,
    content=(
      #|Some([{value: Some("u1"), result: {values: {"socket": StringValue("s1")}, positional: [], rest: [], chunk_sizes: {}}}])
    ),
  )
}

///|
test "parse Group: empty group (no child opts used)" {
  // --upstream u1 → GroupValue with empty child result
  let opts : Array[OptDef] = [
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=None),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket path",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result = parse(opts, ["--upstream", "u1"])
  let groups = result.get_group("upstream")
  inspect(
    groups,
    content=(
      #|Some([{value: Some("u1"), result: {values: {}, positional: [], rest: [], chunk_sizes: {}}}])
    ),
  )
}

// === Step 5: Positional Spec テスト ===

///|
test "parse Positional: Disallowed raises UnexpectedPositional" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(
    opts,
    ["arg1"],
    positional_spec=Positional::Disallowed,
  )
  inspect(
    result,
    content=(
      #|Err(UnexpectedPositional(context="", value="arg1"))
    ),
  )
}

///|
test "parse Positional: Fixed 2 args normal" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let result = parse(
    opts,
    ["src.txt", "dst.txt"],
    positional_spec=Positional::Fixed([
      PositionalDef::new(name="SRC"),
      PositionalDef::new(name="DST"),
    ]),
  )
  inspect(
    result.positional,
    content=(
      #|["src.txt", "dst.txt"]
    ),
  )
}

///|
test "parse Positional: Fixed 2 args but 3 given raises TooManyPositional" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(
    opts,
    ["a", "b", "c"],
    positional_spec=Positional::Fixed([
      PositionalDef::new(name="SRC"),
      PositionalDef::new(name="DST"),
    ]),
  )
  inspect(
    result,
    content=(
      #|Err(TooManyPositional(context="", expected=2, actual=3))
    ),
  )
}

///|
test "parse Positional: Fixed 2 args but 1 given raises TooFewPositional" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(
    opts,
    ["a"],
    positional_spec=Positional::Fixed([
      PositionalDef::new(name="SRC"),
      PositionalDef::new(name="DST"),
    ]),
  )
  inspect(
    result,
    content=(
      #|Err(TooFewPositional(context="", expected=2, actual=1))
    ),
  )
}

///|
test "parse Positional: Fixed with choices valid" {
  let opts : Array[OptDef] = []
  let result = parse(
    opts,
    ["json"],
    positional_spec=Positional::Fixed([
      PositionalDef::new(name="FORMAT", choices=["json", "yaml", "toml"]),
    ]),
  )
  inspect(
    result.positional,
    content=(
      #|["json"]
    ),
  )
}

///|
test "parse Positional: Fixed with choices invalid raises InvalidChoice" {
  let opts : Array[OptDef] = []
  let result : Result[ParseResult, Error] = try? parse(
    opts,
    ["xml"],
    positional_spec=Positional::Fixed([
      PositionalDef::new(name="FORMAT", choices=["json", "yaml", "toml"]),
    ]),
  )
  inspect(
    result,
    content=(
      #|Err(InvalidChoice(option="positional 'FORMAT'", value="xml", choices=["json", "yaml", "toml"]))
    ),
  )
}

///|
test "parse Positional: Variadic with choices invalid raises InvalidChoice" {
  let opts : Array[OptDef] = []
  let result : Result[ParseResult, Error] = try? parse(
    opts,
    ["good", "bad"],
    positional_spec=Positional::Variadic(
      PositionalDef::new(name="ITEM", choices=["good", "ok"]),
    ),
  )
  inspect(
    result,
    content=(
      #|Err(InvalidChoice(option="positional 'ITEM'", value="bad", choices=["good", "ok"]))
    ),
  )
}

///|
test "parse Positional: Variadic 0 args is ok" {
  let opts : Array[OptDef] = []
  let result = parse(
    opts,
    [],
    positional_spec=Positional::Variadic(PositionalDef::new(name="FILE")),
  )
  inspect(result.positional, content="[]")
}

///|
test "parse Positional: Variadic multiple args" {
  let opts : Array[OptDef] = []
  let result = parse(
    opts,
    ["a", "b", "c"],
    positional_spec=Positional::Variadic(PositionalDef::new(name="FILE")),
  )
  inspect(
    result.positional,
    content=(
      #|["a", "b", "c"]
    ),
  )
}

// === Step 6: デフォルトグループ初期化テスト ===

///|
test "parse Group: default group without child opts" {
  // WithValue(default=Some("default_val")) + 子オプションなし → デフォルトインスタンスが作られる
  let opts : Array[OptDef] = [
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=Some("SSH_AUTH_SOCK")),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket path",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result = parse(opts, [])
  let groups = result.get_group("upstream")
  inspect(
    groups,
    content=(
      #|Some([{value: Some("SSH_AUTH_SOCK"), result: {values: {}, positional: [], rest: [], chunk_sizes: {}}}])
    ),
  )
}

///|
test "parse Group: default group merged with explicit same value" {
  // WithValue(default=Some("default_val")) + 明示的に同じ value → マージ
  let opts : Array[OptDef] = [
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=Some("SSH_AUTH_SOCK")),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket path",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result = parse(opts, ["--upstream", "SSH_AUTH_SOCK", "--socket", "s1"])
  let groups = result.get_group("upstream")
  inspect(
    groups,
    content=(
      #|Some([{value: Some("SSH_AUTH_SOCK"), result: {values: {"socket": StringValue("s1")}, positional: [], rest: [], chunk_sizes: {}}}])
    ),
  )
}

///|
test "parse Group: default group with different explicit value" {
  // WithValue(default=Some("default_val")) + 異なる value → 2インスタンス
  let opts : Array[OptDef] = [
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=Some("SSH_AUTH_SOCK")),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket path",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result = parse(opts, ["--upstream", "other", "--socket", "s1"])
  let groups = result.get_group("upstream")
  inspect(
    groups,
    content=(
      #|Some([{value: Some("SSH_AUTH_SOCK"), result: {values: {}, positional: [], rest: [], chunk_sizes: {}}}, {value: Some("other"), result: {values: {"socket": StringValue("s1")}, positional: [], rest: [], chunk_sizes: {}}}])
    ),
  )
}

///|
test "parse Group: default group child opts used without explicit upstream" {
  // デフォルトグループの子オプションを --upstream なしで使用
  let opts : Array[OptDef] = [
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=Some("SSH_AUTH_SOCK")),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket path",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result = parse(opts, ["--socket", "s1"])
  let groups = result.get_group("upstream")
  inspect(
    groups,
    content=(
      #|Some([{value: Some("SSH_AUTH_SOCK"), result: {values: {"socket": StringValue("s1")}, positional: [], rest: [], chunk_sizes: {}}}])
    ),
  )
}

///|
test "parse Group: WithValue(default=None) no default instance" {
  // WithValue(default=None) → デフォルトインスタンスなし
  let opts : Array[OptDef] = [
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=None),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket path",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result = parse(opts, [])
  let groups = result.get_group("upstream")
  inspect(
    groups,
    content=(
      #|Some([])
    ),
  )
}

// === Step 7: Group inversion テスト ===

///|
test "parse Group inversion: --no-xxx then --xxx value creates new instance" {
  // --upstream u1 --socket s1 --no-upstream --upstream u2 --socket s2
  // → u1 はクリアされ、u2 が新規に作られる
  let opts : Array[OptDef] = [
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=None),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket path",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = parse(opts, [
    "--upstream", "u1", "--socket", "s1", "--no-upstream", "--upstream", "u2", "--socket",
    "s2",
  ])
  let groups = result.get_group("upstream")
  inspect(
    groups,
    content=(
      #|Some([{value: Some("u2"), result: {values: {"socket": StringValue("s2")}, positional: [], rest: [], chunk_sizes: {}}}])
    ),
  )
}

///|
test "parse Group inversion: default group + --no-xxx clears and does not regenerate" {
  // WithValue(default=Some("SSH_AUTH_SOCK")) + --no-upstream → クリアされ再生成されない
  let opts : Array[OptDef] = [
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=Some("SSH_AUTH_SOCK")),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket path",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = parse(opts, ["--no-upstream"])
  let groups = result.get_group("upstream")
  inspect(
    groups,
    content=(
      #|Some([])
    ),
  )
}

///|
test "parse Group inversion: parent --no-xxx triggers scope exit from child" {
  // 子スコープ内で --no-upstream → 親由来の Group なのでスコープ終了 → 親で --no-upstream 処理
  let opts : Array[OptDef] = [
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=Some("SSH_AUTH_SOCK")),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket path",
            kind=OptKind::Group(
              group_kind=GroupKind::WithValue(default=None),
              opts=[
                OptDef::new(
                  long="fingerprint",
                  help="Fingerprint",
                  kind=OptKind::Single(default=None),
                ),
              ],
              positional=Positional::Variadic(PositionalDef::new()),
            ),
          ),
        ],
        positional=Positional::Disallowed,
      ),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  // --socket s1 --fingerprint f1 --no-upstream → 子(socket)スコープ → 親(upstream)のスコープ終了 → 親で inversion
  let result = parse(opts, [
    "--socket", "s1", "--fingerprint", "f1", "--no-upstream",
  ])
  let groups = result.get_group("upstream")
  inspect(
    groups,
    content=(
      #|Some([])
    ),
  )
}

///|
test "parse Group inversion: default group + --no-xxx then --xxx recreates" {
  // デフォルトグループ + --no-upstream + --upstream u1 --socket s1 → 再作成される
  let opts : Array[OptDef] = [
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=Some("SSH_AUTH_SOCK")),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket path",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = parse(opts, [
    "--no-upstream", "--upstream", "u1", "--socket", "s1",
  ])
  let groups = result.get_group("upstream")
  inspect(
    groups,
    content=(
      #|Some([{value: Some("u1"), result: {values: {"socket": StringValue("s1")}, positional: [], rest: [], chunk_sizes: {}}}])
    ),
  )
}

// === Step 8: Group + LongOptWithValue / ShortOpts テスト ===

///|
test "parse Group LongOptWithValue: --upstream=u1 --socket s1" {
  // =value 形式で子スコープ開始（既存テストと異なるテスト名で重複確認）
  let opts : Array[OptDef] = [
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=None),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket path",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result = parse(opts, ["--upstream=u1", "--socket", "s1"])
  let groups = result.get_group("upstream")
  inspect(
    groups,
    content=(
      #|Some([{value: Some("u1"), result: {values: {"socket": StringValue("s1")}, positional: [], rest: [], chunk_sizes: {}}}])
    ),
  )
}

///|
test "parse Group LongOptWithValue: Valueless + =value raises error" {
  // Valueless Group に =value を渡すとエラー
  let opts : Array[OptDef] = [
    OptDef::new(
      long="rule",
      help="Rule",
      kind=OptKind::Group(
        group_kind=GroupKind::Valueless,
        opts=[
          OptDef::new(
            long="pattern",
            help="Pattern",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(opts, ["--rule=foo"])
  inspect(
    result,
    content=(
      #|Err(InvalidChoice(option="rule", value="foo", choices=["(no value expected)"]))
    ),
  )
}

///|
test "parse Group ShortOpts: WithValue consumes remaining as value" {
  // -uu1 → 残り文字列 "u1" を値として消費、その後子スコープ
  let opts : Array[OptDef] = [
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=None),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket path",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
      shorts=[ShortEntry::new(char='u')],
    ),
  ]
  let result = parse(opts, ["-uu1", "--socket", "s1"])
  let groups = result.get_group("upstream")
  inspect(
    groups,
    content=(
      #|Some([{value: Some("u1"), result: {values: {"socket": StringValue("s1")}, positional: [], rest: [], chunk_sizes: {}}}])
    ),
  )
}

///|
test "parse Group ShortOpts: Valueless opens child scope after ShortOpts" {
  // -g --pattern foo → ショートオプション -g で Valueless Group、ShortOpts完了後に子スコープ開始
  let opts : Array[OptDef] = [
    OptDef::new(
      long="rule",
      help="Rule",
      kind=OptKind::Group(
        group_kind=GroupKind::Valueless,
        opts=[
          OptDef::new(
            long="pattern",
            help="Pattern",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
      shorts=[ShortEntry::new(char='g')],
    ),
  ]
  let result = parse(opts, ["-g", "--pattern", "foo"])
  let groups = result.get_group("rule")
  inspect(
    groups,
    content=(
      #|Some([{value: None, result: {values: {"pattern": StringValue("foo")}, positional: [], rest: [], chunk_sizes: {}}}])
    ),
  )
}

///|
test "parse Group LongOptWithValue: --upstream=u1 --upstream=u2 multiple instances" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=None),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket path",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result = parse(opts, [
    "--upstream=u1", "--socket", "s1", "--upstream=u2", "--socket", "s2",
  ])
  let groups = result.get_group("upstream")
  inspect(
    groups,
    content=(
      #|Some([{value: Some("u1"), result: {values: {"socket": StringValue("s1")}, positional: [], rest: [], chunk_sizes: {}}}, {value: Some("u2"), result: {values: {"socket": StringValue("s2")}, positional: [], rest: [], chunk_sizes: {}}}])
    ),
  )
}

///|
test "parse Group LongOptWithValue: --no-upstream --upstream=u1 clears then recreates" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=None),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket path",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = parse(opts, [
    "--upstream", "old", "--socket", "sold", "--no-upstream", "--upstream=u1", "--socket",
    "s1",
  ])
  let groups = result.get_group("upstream")
  inspect(
    groups,
    content=(
      #|Some([{value: Some("u1"), result: {values: {"socket": StringValue("s1")}, positional: [], rest: [], chunk_sizes: {}}}])
    ),
  )
}
