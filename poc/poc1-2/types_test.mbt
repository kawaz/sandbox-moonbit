///|
test "OptKind::Flag" {
  inspect(OptKind::Flag(default=false), content="Flag(default=false)")
}

///|
test "OptKind::Single with default" {
  inspect(
    OptKind::Single(default=Some("json")),
    content=(
      #|Single(default=Some("json"))
    ),
  )
}

///|
test "OptKind::Single without default" {
  inspect(OptKind::Single(default=None), content="Single(default=None)")
}

///|
test "OptKind::Append" {
  inspect(
    OptKind::Append(n=1, defaults=["a", "b"]),
    content=(
      #|Append(defaults=["a", "b"], n=1)
    ),
  )
}

///|
test "FlagInversion variants" {
  inspect(FlagInversion::PrefixNo, content="PrefixNo")
  inspect(FlagInversion::PrefixEnableDisable, content="PrefixEnableDisable")
  inspect(FlagInversion::PrefixWithWithout, content="PrefixWithWithout")
}

///|
test "Visibility presets" {
  inspect(
    Visibility::shown(),
    content="{show_in_help: true, show_in_completion: true}",
  )
  inspect(
    Visibility::hidden(),
    content="{show_in_help: false, show_in_completion: false}",
  )
  inspect(
    Visibility::help_only(),
    content="{show_in_help: true, show_in_completion: false}",
  )
  inspect(
    Visibility::completion_only(),
    content="{show_in_help: false, show_in_completion: true}",
  )
}

///|
test "AliasEntry::new defaults" {
  inspect(
    AliasEntry::new(name="old"),
    content=(
      #|{name: "old", visibility: {show_in_help: true, show_in_completion: true}, deprecated: None}
    ),
  )
}

///|
test "AliasEntry::new with deprecated" {
  inspect(
    AliasEntry::new(name="old", deprecated=Some("Use new")),
    content=(
      #|{name: "old", visibility: {show_in_help: true, show_in_completion: true}, deprecated: Some("Use new")}
    ),
  )
}

///|
test "ShortEntry::new defaults" {
  inspect(
    ShortEntry::new(char='v'),
    content="{char: 'v', visibility: {show_in_help: true, show_in_completion: true}}",
  )
}

///|
test "OptDef::new minimal" {
  let opt = OptDef::new(
    long="verbose",
    help="Enable verbose output",
    kind=OptKind::Flag(default=false),
  )
  inspect(opt.long, content="verbose")
  inspect(opt.kind, content="Flag(default=false)")
}

///|
test "ParsedValue variants" {
  inspect(ParsedValue::FlagValue(true), content="FlagValue(true)")
  inspect(
    ParsedValue::StringValue("hello"),
    content=(
      #|StringValue("hello")
    ),
  )
  inspect(
    ParsedValue::ListValue(["a", "b"]),
    content=(
      #|ListValue(["a", "b"])
    ),
  )
}

///|
test "ParseResult::new" {
  let r = ParseResult::new()
  inspect(r.positional, content="[]")
  inspect(r.rest, content="[]")
}

///|
test "ParseResult::get_flag" {
  let r : ParseResult = {
    values: { "verbose": ParsedValue::FlagValue(true) },
    positional: [],
    rest: [],
    chunk_sizes: {},
  }
  inspect(r.get_flag("verbose"), content="true")
  inspect(r.get_flag("missing"), content="false")
}

///|
test "ParseResult::get_string" {
  let r : ParseResult = {
    values: { "format": ParsedValue::StringValue("json") },
    positional: [],
    rest: [],
    chunk_sizes: {},
  }
  inspect(
    r.get_string("format"),
    content=(
      #|Some("json")
    ),
  )
  inspect(r.get_string("missing"), content="None")
}

///|
test "ParseResult::get_int" {
  let r : ParseResult = {
    values: {
      "port": ParsedValue::StringValue("8080"),
      "bad": ParsedValue::StringValue("abc"),
    },
    positional: [],
    rest: [],
    chunk_sizes: {},
  }
  inspect(r.get_int("port"), content="Some(8080)")
  inspect(r.get_int("bad"), content="None")
  inspect(r.get_int("missing"), content="None")
}

///|
test "ParseResult::get_list" {
  let r : ParseResult = {
    values: { "eval": ParsedValue::ListValue(["1+1", "2+2"]) },
    positional: [],
    rest: [],
    chunk_sizes: {},
  }
  inspect(
    r.get_list("eval"),
    content=(
      #|["1+1", "2+2"]
    ),
  )
  inspect(r.get_list("missing"), content="[]")
}

///|
test "ParseError variants" {
  let e1 : ParseError = ParseError::UnknownOption("--foo")
  inspect(
    e1,
    content=(
      #|UnknownOption("--foo")
    ),
  )
  let e2 : ParseError = ParseError::InvalidChoice(
    option="format",
    value="xml",
    choices=["json", "yaml"],
  )
  inspect(
    e2,
    content=(
      #|InvalidChoice(option="format", value="xml", choices=["json", "yaml"])
    ),
  )
}

///|
test "HelpSection variants" {
  inspect(HelpSection::Commands, content="Commands")
  inspect(HelpSection::Options, content="Options")
  inspect(HelpSection::GlobalOptions, content="GlobalOptions")
  inspect(HelpSection::EnvironmentVariables, content="EnvironmentVariables")
}

///|
test "integration: minimal OptDef" {
  let opt = OptDef::new(
    long="verbose",
    help="Enable verbose output",
    kind=OptKind::Flag(default=false),
  )
  inspect(opt.long, content="verbose")
  inspect(opt.help, content="Enable verbose output")
  inspect(opt.kind, content="Flag(default=false)")
  inspect(opt.shorts.length(), content="0")
  inspect(opt.aliases.length(), content="0")
  inspect(opt.inversion, content="None")
  inspect(opt.env, content="None")
  inspect(opt.required, content="false")
  inspect(
    opt.visibility,
    content="{show_in_help: true, show_in_completion: true}",
  )
}

///|
test "integration: full opts definition" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Enable verbose output",
      kind=OptKind::Flag(default=false),
      inversion=Some(FlagInversion::PrefixNo),
    ),
    OptDef::new(
      long="format",
      help="Output format",
      kind=OptKind::Single(default=Some("json")),
      choices=["json", "yaml", "text"],
      value_name="FORMAT",
      env=Some("MYAPP_FORMAT"),
    ),
    OptDef::new(
      long="eval",
      help="Expression to evaluate (repeatable)",
      kind=OptKind::Append(n=1, defaults=[]),
      value_name="EXPR",
      shorts=[ShortEntry::new(char='e', visibility=Visibility::help_only())],
    ),
    OptDef::new(
      long="config",
      help="Configuration file path",
      kind=OptKind::Single(default=None),
      value_name="PATH",
      env=Some("MYAPP_CONFIG"),
    ),
  ]
  inspect(opts.length(), content="4")

  // verbose
  inspect(opts[0].long, content="verbose")
  inspect(opts[0].inversion, content="Some(PrefixNo)")

  // format
  inspect(
    opts[1].choices,
    content=(
      #|["json", "yaml", "text"]
    ),
  )
  inspect(
    opts[1].env,
    content=(
      #|Some("MYAPP_FORMAT")
    ),
  )

  // eval
  inspect(opts[2].shorts.length(), content="1")
  inspect(opts[2].shorts[0].char, content="e")
  inspect(opts[2].shorts[0].visibility.show_in_completion, content="false")

  // config
  inspect(
    opts[3].env,
    content=(
      #|Some("MYAPP_CONFIG")
    ),
  )
}

///|
test "integration: option with aliases" {
  let opt_output = OptDef::new(
    long="output",
    help="Output file path",
    kind=OptKind::Single(default=None),
    aliases=[
      AliasEntry::new(name="out"),
      AliasEntry::new(
        name="output-file",
        visibility=Visibility::help_only(),
        deprecated=Some("Use --output instead"),
      ),
    ],
    shorts=[ShortEntry::new(char='o')],
  )
  inspect(opt_output.aliases.length(), content="2")
  inspect(opt_output.aliases[0].name, content="out")
  inspect(opt_output.aliases[0].deprecated, content="None")
  inspect(opt_output.aliases[1].name, content="output-file")
  inspect(
    opt_output.aliases[1].deprecated,
    content=(
      #|Some("Use --output instead")
    ),
  )
  inspect(opt_output.aliases[1].visibility.show_in_completion, content="false")
  inspect(opt_output.shorts.length(), content="1")
  inspect(opt_output.shorts[0].char, content="o")
}

///|
test "integration: ParseResult with mixed values" {
  let r : ParseResult = {
    values: {
      "verbose": ParsedValue::FlagValue(true),
      "format": ParsedValue::StringValue("yaml"),
      "eval": ParsedValue::ListValue(["1+1", "2+2"]),
    },
    positional: ["input.txt"],
    rest: ["extra"],
    chunk_sizes: {},
  }
  inspect(r.get_flag("verbose"), content="true")
  inspect(
    r.get_string("format"),
    content=(
      #|Some("yaml")
    ),
  )
  inspect(
    r.get_list("eval"),
    content=(
      #|["1+1", "2+2"]
    ),
  )
  inspect(
    r.positional,
    content=(
      #|["input.txt"]
    ),
  )
  inspect(
    r.rest,
    content=(
      #|["extra"]
    ),
  )
}

///|
test "integration: ParseError as suberror" {
  // ParseError が Error として使えることを確認
  fn fail_parse() -> Unit raise ParseError {
    raise ParseError::MissingRequired("format")
  }

  let result : Result[Unit, Error] = try? fail_parse()
  inspect(result is Err(_), content="true")
}

///|
test "OptKind::Flag default true" {
  inspect(OptKind::Flag(default=true), content="Flag(default=true)")
}

///|
test "ParsedValue::FlagValue false" {
  inspect(ParsedValue::FlagValue(false), content="FlagValue(false)")
}

///|
test "OptKind::Append empty defaults" {
  inspect(
    OptKind::Append(n=1, defaults=[]),
    content=(
      #|Append(defaults=[], n=1)
    ),
  )
}

///|
test "ParseError::MissingValue" {
  let e : ParseError = ParseError::MissingValue("--format")
  inspect(
    e,
    content=(
      #|MissingValue("--format")
    ),
  )
}

///|
test "ParseError::MissingRequired" {
  let e : ParseError = ParseError::MissingRequired("--config")
  inspect(
    e,
    content=(
      #|MissingRequired("--config")
    ),
  )
}

///|
test "ParseError::HelpRequested" {
  let e : ParseError = ParseError::HelpRequested
  inspect(e, content="HelpRequested")
}

///|
test "ParseResult accessor type mismatch" {
  let r : ParseResult = {
    values: {
      "flag": ParsedValue::FlagValue(true),
      "str": ParsedValue::StringValue("hello"),
      "list": ParsedValue::ListValue(["a", "b"]),
    },
    positional: [],
    rest: [],
    chunk_sizes: {},
  }
  // get_flag on non-flag values
  inspect(r.get_flag("str"), content="false")
  inspect(r.get_flag("list"), content="false")

  // get_string on non-string values
  inspect(r.get_string("flag"), content="None")
  inspect(r.get_string("list"), content="None")

  // get_int on non-string values
  inspect(r.get_int("flag"), content="None")
  inspect(r.get_int("list"), content="None")

  // get_list on non-list values
  inspect(r.get_list("flag"), content="[]")
  inspect(r.get_list("str"), content="[]")
}

///|
test "Token variants" {
  inspect(
    Token::LongOpt("verbose"),
    content=(
      #|LongOpt("verbose")
    ),
  )
  inspect(
    Token::LongOptWithValue("format", "json"),
    content=(
      #|LongOptWithValue("format", "json")
    ),
  )
  inspect(
    Token::ShortOpts("abc"),
    content=(
      #|ShortOpts("abc")
    ),
  )
  inspect(
    Token::Positional("file.txt"),
    content=(
      #|Positional("file.txt")
    ),
  )
  inspect(Token::DoubleDash, content="DoubleDash")
}

// === Count / OptionalValue / CountValue テスト ===

///|
test "OptKind::Count" {
  inspect(OptKind::Count(default=0), content="Count(default=0)")
  inspect(OptKind::Count(default=3), content="Count(default=3)")
}

///|
test "OptKind::OptionalValue" {
  inspect(
    OptKind::OptionalValue(default=None, implicit="auto", negated=Some("never")),
    content=(
      #|OptionalValue(default=None, implicit="auto", negated=Some("never"))
    ),
  )
  inspect(
    OptKind::OptionalValue(default=Some("auto"), implicit="auto", negated=None),
    content=(
      #|OptionalValue(default=Some("auto"), implicit="auto", negated=None)
    ),
  )
}

///|
test "ParsedValue::CountValue" {
  inspect(ParsedValue::CountValue(0), content="CountValue(0)")
  inspect(ParsedValue::CountValue(3), content="CountValue(3)")
}

///|
test "ParseResult::get_count" {
  let r : ParseResult = {
    values: { "verbose": ParsedValue::CountValue(3) },
    positional: [],
    rest: [],
    chunk_sizes: {},
  }
  inspect(r.get_count("verbose"), content="3")
  inspect(r.get_count("missing"), content="0")
}

///|
test "ParseResult::get_int with CountValue" {
  let r : ParseResult = {
    values: { "verbose": ParsedValue::CountValue(5) },
    positional: [],
    rest: [],
    chunk_sizes: {},
  }
  inspect(r.get_int("verbose"), content="Some(5)")
}

///|
test "ParseResult accessor type mismatch with CountValue" {
  let r : ParseResult = {
    values: { "count": ParsedValue::CountValue(2) },
    positional: [],
    rest: [],
    chunk_sizes: {},
  }
  // get_flag on CountValue
  inspect(r.get_flag("count"), content="false")
  // get_string on CountValue
  inspect(r.get_string("count"), content="None")
  // get_list on CountValue
  inspect(r.get_list("count"), content="[]")
}

// === get_chunks テスト ===

///|
test "get_chunks n=2" {
  let r : ParseResult = {
    values: { "arg": ParsedValue::ListValue(["k1", "v1", "k2", "v2"]) },
    positional: [],
    rest: [],
    chunk_sizes: { "arg": 2 },
  }
  inspect(
    r.get_chunks("arg"),
    content=(
      #|[["k1", "v1"], ["k2", "v2"]]
    ),
  )
}

///|
test "get_chunks empty" {
  let r : ParseResult = {
    values: {},
    positional: [],
    rest: [],
    chunk_sizes: { "arg": 2 },
  }
  inspect(r.get_chunks("arg"), content="[]")
}

///|
test "get_chunks n=1 returns empty" {
  let r : ParseResult = {
    values: { "eval": ParsedValue::ListValue(["a", "b"]) },
    positional: [],
    rest: [],
    chunk_sizes: { "eval": 1 },
  }
  // n=1 の場合は get_chunks は空を返す（get_list を使う）
  inspect(r.get_chunks("eval"), content="[]")
}

///|
test "get_chunks no chunk_sizes returns empty" {
  let r : ParseResult = {
    values: { "eval": ParsedValue::ListValue(["a", "b"]) },
    positional: [],
    rest: [],
    chunk_sizes: {},
  }
  // chunk_sizes に未登録の場合も空を返す
  inspect(r.get_chunks("eval"), content="[]")
}

///|
test "get_chunks n=3" {
  let r : ParseResult = {
    values: { "arg": ParsedValue::ListValue(["a", "b", "c", "d", "e", "f"]) },
    positional: [],
    rest: [],
    chunk_sizes: { "arg": 3 },
  }
  inspect(
    r.get_chunks("arg"),
    content=(
      #|[["a", "b", "c"], ["d", "e", "f"]]
    ),
  )
}

///|
test "get_chunks incomplete trailing chunk dropped" {
  let r : ParseResult = {
    values: { "arg": ParsedValue::ListValue(["a", "b", "c"]) },
    positional: [],
    rest: [],
    chunk_sizes: { "arg": 2 },
  }
  // n=2, length=3 → 1 chunk of 2, trailing "c" is dropped
  inspect(
    r.get_chunks("arg"),
    content=(
      #|[["a", "b"]]
    ),
  )
}

// === CmdDef テスト ===

///|
test "CmdDef::new defaults" {
  let cmd = CmdDef::new(name="myapp")
  inspect(cmd.name, content="myapp")
  inspect(cmd.description, content="")
  inspect(cmd.version, content="")
  inspect(cmd.opts.length(), content="0")
  inspect(cmd.global_opts.length(), content="0")
  inspect(cmd.subcommands.length(), content="0")
  inspect(cmd.aliases.length(), content="0")
  inspect(cmd.help_on_empty, content="true")
}

///|
test "CmdDef::new with all fields" {
  let cmd = CmdDef::new(
    name="myapp",
    description="My awesome app",
    version="1.0.0",
    opts=[
      OptDef::new(
        long="verbose",
        help="Enable verbose output",
        kind=OptKind::Flag(default=false),
      ),
    ],
    global_opts=[
      OptDef::new(
        long="config",
        help="Config file",
        kind=OptKind::Single(default=None),
      ),
    ],
    aliases=[AliasEntry::new(name="app")],
    help_on_empty=false,
  )
  inspect(cmd.name, content="myapp")
  inspect(cmd.description, content="My awesome app")
  inspect(cmd.version, content="1.0.0")
  inspect(cmd.opts.length(), content="1")
  inspect(cmd.opts[0].long, content="verbose")
  inspect(cmd.global_opts.length(), content="1")
  inspect(cmd.global_opts[0].long, content="config")
  inspect(cmd.aliases.length(), content="1")
  inspect(cmd.aliases[0].name, content="app")
  inspect(cmd.help_on_empty, content="false")
}

///|
test "CmdDef nested subcommands" {
  let cmd = CmdDef::new(name="git", description="Version control", subcommands=[
    CmdDef::new(name="remote", description="Manage remotes", subcommands=[
      CmdDef::new(name="add", description="Add a remote"),
      CmdDef::new(name="remove", description="Remove a remote"),
    ]),
    CmdDef::new(name="commit", description="Create a commit"),
  ])
  inspect(cmd.name, content="git")
  inspect(cmd.subcommands.length(), content="2")
  inspect(cmd.subcommands[0].name, content="remote")
  inspect(cmd.subcommands[0].subcommands.length(), content="2")
  inspect(cmd.subcommands[0].subcommands[0].name, content="add")
  inspect(cmd.subcommands[0].subcommands[0].description, content="Add a remote")
  inspect(cmd.subcommands[0].subcommands[1].name, content="remove")
  inspect(cmd.subcommands[1].name, content="commit")
}

// === CommandResult テスト ===

///|
test "CommandResult::new defaults" {
  let cr = CommandResult::new()
  inspect(cr.command, content="[]")
  inspect(cr.result.positional, content="[]")
  inspect(cr.result.rest, content="[]")
}

///|
test "CommandResult::new with values" {
  let r : ParseResult = {
    values: { "verbose": ParsedValue::FlagValue(true) },
    positional: ["file.txt"],
    rest: [],
    chunk_sizes: {},
  }
  let cr = CommandResult::new(command=["git", "commit"], result=r)
  inspect(
    cr.command,
    content=(
      #|["git", "commit"]
    ),
  )
  inspect(cr.result.get_flag("verbose"), content="true")
  inspect(
    cr.result.positional,
    content=(
      #|["file.txt"]
    ),
  )
}

///|
test "CommandResult inspect" {
  let cr = CommandResult::new(command=["myapp", "sub"])
  inspect(
    cr,
    content=(
      #|{command: ["myapp", "sub"], result: {values: {}, positional: [], rest: [], chunk_sizes: {}}}
    ),
  )
}

// === ParseError 新バリアント テスト ===

///|
test "ParseError::UnknownCommand" {
  let e : ParseError = ParseError::UnknownCommand("frobnicate")
  inspect(
    e,
    content=(
      #|UnknownCommand("frobnicate")
    ),
  )
}

///|
test "ParseError::VersionRequested" {
  let e : ParseError = ParseError::VersionRequested
  inspect(e, content="VersionRequested")
}

///|
test "ParseError::UnknownCommand as suberror" {
  fn fail_cmd() -> Unit raise ParseError {
    raise ParseError::UnknownCommand("bad")
  }

  let result : Result[Unit, Error] = try? fail_cmd()
  inspect(result is Err(_), content="true")
}

///|
test "ParseError::VersionRequested as suberror" {
  fn fail_version() -> Unit raise ParseError {
    raise ParseError::VersionRequested
  }

  let result : Result[Unit, Error] = try? fail_version()
  inspect(result is Err(_), content="true")
}

// === Phase 3 Step 1: 新規型テスト ===

///|
test "PositionalDef::new defaults" {
  let pd = PositionalDef::new()
  inspect(pd.name, content="ARG")
  inspect(pd.help, content="")
  inspect(pd.choices, content="[]")
}

///|
test "PositionalDef::new with values" {
  let pd = PositionalDef::new(name="FILE", help="Input file", choices=[
    "a.txt", "b.txt",
  ])
  inspect(pd.name, content="FILE")
  inspect(pd.help, content="Input file")
  inspect(
    pd.choices,
    content=(
      #|["a.txt", "b.txt"]
    ),
  )
}

///|
test "Positional variants" {
  inspect(Positional::Disallowed, content="Disallowed")
  let fixed = Positional::Fixed([
    PositionalDef::new(name="SRC"),
    PositionalDef::new(name="DST"),
  ])
  inspect(
    fixed,
    content=(
      #|Fixed([{name: "SRC", help: "", choices: []}, {name: "DST", help: "", choices: []}])
    ),
  )
  let variadic = Positional::Variadic(PositionalDef::new(name="FILE"))
  inspect(
    variadic,
    content=(
      #|Variadic({name: "FILE", help: "", choices: []})
    ),
  )
}

///|
test "GroupKind variants" {
  inspect(GroupKind::Valueless, content="Valueless")
  inspect(GroupKind::WithValue(default=None), content="WithValue(default=None)")
  inspect(
    GroupKind::WithValue(default=Some("json")),
    content=(
      #|WithValue(default=Some("json"))
    ),
  )
}

///|
test "GroupInstance construction and mutual recursion" {
  // GroupInstance が ParseResult を含み、ParsedValue::GroupValue が GroupInstance を含む
  // 相互再帰型の構築テスト
  let inner_result : ParseResult = {
    values: { "verbose": FlagValue(true) },
    positional: [],
    rest: [],
    chunk_sizes: {},
  }
  let gi : GroupInstance = { value: Some("json"), result: inner_result }
  inspect(
    gi.value,
    content=(
      #|Some("json")
    ),
  )
  inspect(gi.result.get_flag("verbose"), content="true")
}

///|
test "GroupInstance with None value" {
  let gi : GroupInstance = { value: None, result: ParseResult::new() }
  inspect(gi.value, content="None")
}

///|
test "OptKind::Group construction" {
  let group_opt = OptKind::Group(
    group_kind=GroupKind::Valueless,
    opts=[
      OptDef::new(
        long="verbose",
        help="Verbose",
        kind=OptKind::Flag(default=false),
      ),
    ],
    positional=Positional::Disallowed,
  )
  inspect(
    group_opt,
    content=(
      #|Group(group_kind=Valueless, opts=[{long: "verbose", help: "Verbose", kind: Flag(default=false), shorts: [], aliases: [], inversion: None, env: None, choices: [], value_name: "VALUE", required: false, visibility: {show_in_help: true, show_in_completion: true}}], positional=Disallowed)
    ),
  )
}

///|
test "ParsedValue::GroupValue construction" {
  let inner_result : ParseResult = {
    values: { "flag": FlagValue(true) },
    positional: [],
    rest: [],
    chunk_sizes: {},
  }
  let gv = ParsedValue::GroupValue([{ value: None, result: inner_result }])
  inspect(
    gv,
    content=(
      #|GroupValue([{value: None, result: {values: {"flag": FlagValue(true)}, positional: [], rest: [], chunk_sizes: {}}}])
    ),
  )
}

///|
test "ParseError::TooManyPositional" {
  let e : ParseError = ParseError::TooManyPositional(
    context="myapp",
    expected=2,
    actual=3,
  )
  inspect(
    e,
    content=(
      #|TooManyPositional(context="myapp", expected=2, actual=3)
    ),
  )
}

///|
test "ParseError::TooFewPositional" {
  let e : ParseError = ParseError::TooFewPositional(
    context="myapp",
    expected=2,
    actual=1,
  )
  inspect(
    e,
    content=(
      #|TooFewPositional(context="myapp", expected=2, actual=1)
    ),
  )
}

///|
test "ParseError::UnexpectedPositional" {
  let e : ParseError = ParseError::UnexpectedPositional(
    context="myapp",
    value="extra",
  )
  inspect(
    e,
    content=(
      #|UnexpectedPositional(context="myapp", value="extra")
    ),
  )
}

///|
test "ParseError new variants as suberror" {
  fn fail_too_many() -> Unit raise ParseError {
    raise ParseError::TooManyPositional(context="ctx", expected=1, actual=2)
  }

  fn fail_too_few() -> Unit raise ParseError {
    raise ParseError::TooFewPositional(context="ctx", expected=2, actual=1)
  }

  fn fail_unexpected() -> Unit raise ParseError {
    raise ParseError::UnexpectedPositional(context="ctx", value="x")
  }

  let r1 : Result[Unit, Error] = try? fail_too_many()
  inspect(r1 is Err(_), content="true")
  let r2 : Result[Unit, Error] = try? fail_too_few()
  inspect(r2 is Err(_), content="true")
  let r3 : Result[Unit, Error] = try? fail_unexpected()
  inspect(r3 is Err(_), content="true")
}

///|
test "CmdDef::new positional_spec default" {
  let cmd = CmdDef::new(name="myapp")
  // デフォルトは Variadic(PositionalDef::new())
  inspect(
    cmd.positional_spec,
    content=(
      #|Variadic({name: "ARG", help: "", choices: []})
    ),
  )
}

///|
test "CmdDef::new with positional_spec" {
  let cmd = CmdDef::new(
    name="myapp",
    positional_spec=Positional::Fixed([
      PositionalDef::new(name="SRC"),
      PositionalDef::new(name="DST"),
    ]),
  )
  inspect(
    cmd.positional_spec,
    content=(
      #|Fixed([{name: "SRC", help: "", choices: []}, {name: "DST", help: "", choices: []}])
    ),
  )
}

///|
test "ParseResult::get_group with GroupValue" {
  let inner : ParseResult = {
    values: {},
    positional: [],
    rest: [],
    chunk_sizes: {},
  }
  let gi : GroupInstance = { value: Some("val"), result: inner }
  let r : ParseResult = {
    values: { "my-group": ParsedValue::GroupValue([gi]) },
    positional: [],
    rest: [],
    chunk_sizes: {},
  }
  let groups = r.get_group("my-group")
  inspect(groups is Some(_), content="true")
  match groups {
    Some(arr) => inspect(arr.length(), content="1")
    None => inspect("unreachable", content="")
  }
}

///|
test "ParseResult::get_group with missing key" {
  let r = ParseResult::new()
  inspect(r.get_group("missing"), content="None")
}

///|
test "ParseResult::get_group with non-GroupValue" {
  let r : ParseResult = {
    values: { "flag": ParsedValue::FlagValue(true) },
    positional: [],
    rest: [],
    chunk_sizes: {},
  }
  inspect(r.get_group("flag"), content="None")
}

///|
test "ParseResult accessor type mismatch with GroupValue" {
  let inner : ParseResult = {
    values: {},
    positional: [],
    rest: [],
    chunk_sizes: {},
  }
  let r : ParseResult = {
    values: { "grp": ParsedValue::GroupValue([{ value: None, result: inner }]) },
    positional: [],
    rest: [],
    chunk_sizes: {},
  }
  // get_flag on GroupValue
  inspect(r.get_flag("grp"), content="false")
  // get_string on GroupValue
  inspect(r.get_string("grp"), content="None")
  // get_list on GroupValue
  inspect(r.get_list("grp"), content="[]")
  // get_count on GroupValue
  inspect(r.get_count("grp"), content="0")
  // get_int on GroupValue
  inspect(r.get_int("grp"), content="None")
}
