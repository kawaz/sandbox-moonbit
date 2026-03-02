// === find_command 関数テスト ===

// --- ヘルパー ---

///|
fn make_root_cmd(
  opts? : Array[OptDef] = [],
  global_opts? : Array[OptDef] = [],
  subcommands? : Array[CmdDef] = [],
) -> CmdDef {
  CmdDef::new(name="app", opts~, global_opts~, subcommands~)
}

// --- テストケース ---

///|
test "find_command: leaf command (no subcommands)" {
  let cmd = make_root_cmd()
  let (leaf, path, args) = find_command(cmd, ["--verbose", "file.txt"], [])
  inspect(leaf.name, content="app")
  inspect(path, content="[]")
  inspect(
    args,
    content=(
      #|["--verbose", "file.txt"]
    ),
  )
}

///|
test "find_command: single-level subcommand" {
  let cmd = make_root_cmd(subcommands=[CmdDef::new(name="config")])
  let (leaf, path, args) = find_command(cmd, ["config", "--key", "foo"], [])
  inspect(leaf.name, content="config")
  inspect(
    path,
    content=(
      #|["config"]
    ),
  )
  inspect(
    args,
    content=(
      #|["--key", "foo"]
    ),
  )
}

///|
test "find_command: multi-level subcommand" {
  let cmd = make_root_cmd(subcommands=[
    CmdDef::new(name="config", subcommands=[CmdDef::new(name="set")]),
  ])
  let (leaf, path, args) = find_command(
    cmd,
    ["config", "set", "--key", "foo"],
    [],
  )
  inspect(leaf.name, content="set")
  inspect(
    path,
    content=(
      #|["config", "set"]
    ),
  )
  inspect(
    args,
    content=(
      #|["--key", "foo"]
    ),
  )
}

///|
test "find_command: global opt before subcommand" {
  let cmd = make_root_cmd(
    global_opts=[
      OptDef::new(
        long="verbose",
        help="Verbose",
        kind=OptKind::Flag(default=false),
      ),
    ],
    subcommands=[CmdDef::new(name="config")],
  )
  let (leaf, path, args) = find_command(cmd, ["--verbose", "config"], [])
  inspect(leaf.name, content="config")
  inspect(
    path,
    content=(
      #|["config"]
    ),
  )
  inspect(
    args,
    content=(
      #|["--verbose"]
    ),
  )
}

///|
test "find_command: global opt consuming value before subcommand" {
  let cmd = make_root_cmd(
    global_opts=[
      OptDef::new(
        long="format",
        help="Format",
        kind=OptKind::Single(default=None),
      ),
    ],
    subcommands=[CmdDef::new(name="config")],
  )
  let (leaf, path, args) = find_command(cmd, ["--format", "json", "config"], [])
  inspect(leaf.name, content="config")
  inspect(
    path,
    content=(
      #|["config"]
    ),
  )
  inspect(
    args,
    content=(
      #|["--format", "json"]
    ),
  )
}

///|
test "find_command: LongOptWithValue before subcommand" {
  let cmd = make_root_cmd(
    global_opts=[
      OptDef::new(
        long="format",
        help="Format",
        kind=OptKind::Single(default=None),
      ),
    ],
    subcommands=[CmdDef::new(name="config")],
  )
  let (leaf, path, args) = find_command(cmd, ["--format=json", "config"], [])
  inspect(leaf.name, content="config")
  inspect(
    path,
    content=(
      #|["config"]
    ),
  )
  inspect(
    args,
    content=(
      #|["--format=json"]
    ),
  )
}

///|
test "find_command: alias matches canonical name" {
  let cmd = make_root_cmd(subcommands=[
    CmdDef::new(name="config", aliases=[AliasEntry::new(name="cfg")]),
  ])
  let (leaf, path, args) = find_command(cmd, ["cfg"], [])
  inspect(leaf.name, content="config")
  inspect(
    path,
    content=(
      #|["config"]
    ),
  )
  inspect(args, content="[]")
}

///|
test "find_command: double dash stops routing" {
  let cmd = make_root_cmd(subcommands=[CmdDef::new(name="config")])
  let (leaf, path, args) = find_command(cmd, ["--", "config"], [])
  inspect(leaf.name, content="app")
  inspect(path, content="[]")
  inspect(
    args,
    content=(
      #|["--", "config"]
    ),
  )
}

///|
test "find_command: unknown command raises UnknownCommand" {
  let cmd = make_root_cmd(subcommands=[CmdDef::new(name="config")])
  let result : Result[(CmdDef, Array[String], Array[String]), Error] = try? find_command(
    cmd,
    ["unknown"],
    [],
  )
  inspect(
    result,
    content=(
      #|Err(UnknownCommand("unknown"))
    ),
  )
}

///|
test "find_command: unknown option raises UnknownOption" {
  let cmd = make_root_cmd(subcommands=[CmdDef::new(name="config")])
  let result : Result[(CmdDef, Array[String], Array[String]), Error] = try? find_command(
    cmd,
    ["--unknown-opt", "config"],
    [],
  )
  inspect(
    result,
    content=(
      #|Err(UnknownOption("--unknown-opt"))
    ),
  )
}

///|
test "find_command: positional arg raises UnknownCommand when subcommands exist" {
  // サブコマンドが定義されたコマンドでは、位置引数は UnknownCommand になる
  let cmd = make_root_cmd(subcommands=[CmdDef::new(name="config")])
  let result : Result[(CmdDef, Array[String], Array[String]), Error] = try? find_command(
    cmd,
    ["file.txt"],
    [],
  )
  inspect(
    result,
    content=(
      #|Err(UnknownCommand("file.txt"))
    ),
  )
}

///|
test "find_command: inverted direction does not consume value" {
  let cmd = make_root_cmd(
    global_opts=[
      OptDef::new(
        long="format",
        help="Format",
        kind=OptKind::Single(default=Some("json")),
        inversion=Some(FlagInversion::PrefixNo),
      ),
    ],
    subcommands=[CmdDef::new(name="config")],
  )
  let (leaf, path, args) = find_command(cmd, ["--no-format", "config"], [])
  inspect(leaf.name, content="config")
  inspect(
    path,
    content=(
      #|["config"]
    ),
  )
  inspect(
    args,
    content=(
      #|["--no-format"]
    ),
  )
}

// === parse_command 関数テスト ===

///|
test "parse_command: simple command (no subcommands)" {
  let cmd = CmdDef::new(name="app", help_on_empty=false, opts=[
    OptDef::new(
      long="output",
      help="Output file",
      kind=OptKind::Single(default=None),
    ),
  ])
  let cr = parse_command(cmd, ["--output", "out.txt"])
  inspect(cr.command, content="[]")
  inspect(
    cr.result.get_string("output"),
    content=(
      #|Some("out.txt")
    ),
  )
}

///|
test "parse_command: subcommand with options" {
  let cmd = CmdDef::new(name="app", subcommands=[
    CmdDef::new(name="config", help_on_empty=false, opts=[
      OptDef::new(long="key", help="Key", kind=OptKind::Single(default=None)),
    ]),
  ])
  let cr = parse_command(cmd, ["config", "--key", "foo"])
  inspect(
    cr.command,
    content=(
      #|["config"]
    ),
  )
  inspect(
    cr.result.get_string("key"),
    content=(
      #|Some("foo")
    ),
  )
}

///|
test "parse_command: global opt before subcommand" {
  let cmd = CmdDef::new(
    name="app",
    global_opts=[
      OptDef::new(
        long="verbose",
        help="Verbose",
        kind=OptKind::Flag(default=false),
      ),
    ],
    subcommands=[
      CmdDef::new(name="config", help_on_empty=false, opts=[
        OptDef::new(long="key", help="Key", kind=OptKind::Single(default=None)),
      ]),
    ],
  )
  let cr = parse_command(cmd, ["--verbose", "config", "--key", "foo"])
  inspect(
    cr.command,
    content=(
      #|["config"]
    ),
  )
  inspect(cr.result.get_flag("verbose"), content="true")
  inspect(
    cr.result.get_string("key"),
    content=(
      #|Some("foo")
    ),
  )
}

///|
test "parse_command: global opt after subcommand" {
  let cmd = CmdDef::new(
    name="app",
    global_opts=[
      OptDef::new(
        long="verbose",
        help="Verbose",
        kind=OptKind::Flag(default=false),
      ),
    ],
    subcommands=[
      CmdDef::new(name="config", help_on_empty=false, opts=[
        OptDef::new(long="key", help="Key", kind=OptKind::Single(default=None)),
      ]),
    ],
  )
  let cr = parse_command(cmd, ["config", "--verbose", "--key", "foo"])
  inspect(
    cr.command,
    content=(
      #|["config"]
    ),
  )
  inspect(cr.result.get_flag("verbose"), content="true")
  inspect(
    cr.result.get_string("key"),
    content=(
      #|Some("foo")
    ),
  )
}

///|
test "parse_command: multi-level nesting with global opts" {
  let cmd = CmdDef::new(
    name="app",
    global_opts=[
      OptDef::new(
        long="verbose",
        help="Verbose",
        kind=OptKind::Flag(default=false),
      ),
    ],
    subcommands=[
      CmdDef::new(
        name="config",
        global_opts=[
          OptDef::new(
            long="format",
            help="Format",
            kind=OptKind::Single(default=Some("text")),
          ),
        ],
        subcommands=[
          CmdDef::new(name="set", help_on_empty=false, opts=[
            OptDef::new(
              long="key",
              help="Key",
              kind=OptKind::Single(default=None),
            ),
          ]),
        ],
      ),
    ],
  )
  let cr = parse_command(cmd, ["config", "set", "--key", "foo", "--verbose"])
  inspect(
    cr.command,
    content=(
      #|["config", "set"]
    ),
  )
  inspect(
    cr.result.get_string("key"),
    content=(
      #|Some("foo")
    ),
  )
  inspect(cr.result.get_flag("verbose"), content="true")
  // format はデフォルト値
  inspect(
    cr.result.get_string("format"),
    content=(
      #|Some("text")
    ),
  )
}

///|
test "parse_command: help_on_empty root" {
  let cmd = CmdDef::new(name="app", help_on_empty=true)
  let result : Result[CommandResult, Error] = try? parse_command(cmd, [])
  inspect(result, content="Err(HelpRequested)")
}

///|
test "parse_command: help_on_empty subcommand" {
  let cmd = CmdDef::new(name="app", subcommands=[
    CmdDef::new(name="config", help_on_empty=true),
  ])
  let result : Result[CommandResult, Error] = try? parse_command(cmd, ["config"])
  inspect(result, content="Err(HelpRequested)")
}

///|
test "parse_command: help_on_empty=false allows empty args" {
  let cmd = CmdDef::new(name="app", help_on_empty=false)
  let cr = parse_command(cmd, [])
  inspect(cr.command, content="[]")
  inspect(cr.result.positional, content="[]")
}

///|
test "parse_command: --help raises HelpRequested" {
  let cmd = CmdDef::new(name="app", help_on_empty=false)
  let result : Result[CommandResult, Error] = try? parse_command(cmd, ["--help"])
  inspect(result, content="Err(HelpRequested)")
}

///|
test "parse_command: --version raises VersionRequested" {
  let cmd = CmdDef::new(name="app", help_on_empty=false, version="1.0.0")
  let result : Result[CommandResult, Error] = try? parse_command(cmd, [
    "--version",
  ])
  inspect(result, content="Err(VersionRequested)")
}

///|
test "find_command: Append(n=2) long opt before subcommand skips n tokens" {
  let cmd = make_root_cmd(
    global_opts=[
      OptDef::new(
        long="arg",
        help="Key-value pair",
        kind=OptKind::Append(defaults=[], n=2),
      ),
    ],
    subcommands=[CmdDef::new(name="config")],
  )
  let (leaf, path, args) = find_command(cmd, ["--arg", "k", "v", "config"], [])
  inspect(leaf.name, content="config")
  inspect(
    path,
    content=(
      #|["config"]
    ),
  )
  inspect(
    args,
    content=(
      #|["--arg", "k", "v"]
    ),
  )
}

///|
test "find_command: Append(n=2) short opt before subcommand skips n tokens" {
  let cmd = make_root_cmd(
    global_opts=[
      OptDef::new(
        long="arg",
        help="Key-value pair",
        kind=OptKind::Append(defaults=[], n=2),
        shorts=[ShortEntry::new(char='a')],
      ),
    ],
    subcommands=[CmdDef::new(name="config")],
  )
  let (leaf, path, args) = find_command(cmd, ["-a", "k", "v", "config"], [])
  inspect(leaf.name, content="config")
  inspect(
    path,
    content=(
      #|["config"]
    ),
  )
  inspect(
    args,
    content=(
      #|["-a", "k", "v"]
    ),
  )
}

///|
test "find_command: Append(n=2) short opt with inline value before subcommand" {
  let cmd = make_root_cmd(
    global_opts=[
      OptDef::new(
        long="arg",
        help="Key-value pair",
        kind=OptKind::Append(defaults=[], n=2),
        shorts=[ShortEntry::new(char='a')],
      ),
    ],
    subcommands=[CmdDef::new(name="config")],
  )
  // -ak は inline で "k" が1つ目の値、"v" が次トークンで2つ目の値
  let (leaf, path, args) = find_command(cmd, ["-ak", "v", "config"], [])
  inspect(leaf.name, content="config")
  inspect(
    path,
    content=(
      #|["config"]
    ),
  )
  inspect(
    args,
    content=(
      #|["-ak", "v"]
    ),
  )
}

///|
test "parse_command: global + local options combined" {
  let cmd = CmdDef::new(
    name="app",
    global_opts=[
      OptDef::new(
        long="debug",
        help="Debug mode",
        kind=OptKind::Flag(default=false),
      ),
      OptDef::new(
        long="log-level",
        help="Log level",
        kind=OptKind::Single(default=Some("info")),
      ),
    ],
    subcommands=[
      CmdDef::new(name="serve", help_on_empty=false, opts=[
        OptDef::new(
          long="port",
          help="Port",
          kind=OptKind::Single(default=Some("8080")),
        ),
      ]),
    ],
  )
  let cr = parse_command(cmd, [
    "serve", "--port", "3000", "--debug", "--log-level", "warn",
  ])
  inspect(
    cr.command,
    content=(
      #|["serve"]
    ),
  )
  inspect(
    cr.result.get_string("port"),
    content=(
      #|Some("3000")
    ),
  )
  inspect(cr.result.get_flag("debug"), content="true")
  inspect(
    cr.result.get_string("log-level"),
    content=(
      #|Some("warn")
    ),
  )
}

///|
test "find_command: --help before subcommand does not raise UnknownOption" {
  let cmd = make_root_cmd(subcommands=[CmdDef::new(name="config")])
  // --help は opts に定義されていないが、scan_for_subcommand で UnknownOption にならない
  let (leaf, path, _args) = find_command(cmd, ["--help", "config"], [])
  // --help はスキップされ、config がサブコマンドとして認識される
  inspect(leaf.name, content="config")
  inspect(
    path,
    content=(
      #|["config"]
    ),
  )
}

///|
test "find_command: --version before subcommand does not raise UnknownOption" {
  let cmd = make_root_cmd(subcommands=[CmdDef::new(name="config")])
  let (leaf, path, _args) = find_command(cmd, ["--version", "config"], [])
  inspect(leaf.name, content="config")
  inspect(
    path,
    content=(
      #|["config"]
    ),
  )
}

///|
test "parse_command: subcommand with --help raises HelpRequested" {
  let cmd = CmdDef::new(name="app", subcommands=[
    CmdDef::new(name="config", help_on_empty=false, opts=[
      OptDef::new(long="key", help="Key", kind=OptKind::Single(default=None)),
    ]),
  ])
  let result : Result[CommandResult, Error] = try? parse_command(cmd, [
    "config", "--help",
  ])
  inspect(result, content="Err(HelpRequested)")
}

///|
test "parse_command: --help before subcommand raises HelpRequested" {
  let cmd = CmdDef::new(name="app", subcommands=[
    CmdDef::new(name="config", help_on_empty=false),
  ])
  // --help がサブコマンドより前にあっても、parse で HelpRequested になる
  let result : Result[CommandResult, Error] = try? parse_command(cmd, [
    "--help", "config",
  ])
  inspect(result, content="Err(HelpRequested)")
}

// === Step 9: positional_spec 接続テスト ===

///|
test "parse_command: leaf positional_spec Fixed is passed to parse" {
  // CmdDef に positional_spec=Fixed を設定し、parse_command で正しく検証されることを確認
  let cmd = CmdDef::new(
    name="app",
    positional_spec=Positional::Fixed([
      PositionalDef::new(name="SRC"),
      PositionalDef::new(name="DST"),
    ]),
    help_on_empty=false,
  )
  // 正常: 2 個の位置引数
  let result = parse_command(cmd, ["src.txt", "dst.txt"])
  inspect(
    result.result.positional,
    content=(
      #|["src.txt", "dst.txt"]
    ),
  )
  // 異常: 3 個 → TooManyPositional
  let err_result : Result[CommandResult, Error] = try? parse_command(cmd, [
    "a", "b", "c",
  ])
  inspect(
    err_result,
    content=(
      #|Err(TooManyPositional(context="", expected=2, actual=3))
    ),
  )
}
