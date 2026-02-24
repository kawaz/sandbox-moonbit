// === Phase 2 統合テスト ===
// 現実的な CLI アプリケーションのシナリオを再現し、
// 全コンポーネント (tokenize, resolve, validate_opts, parse, apply_defaults) の
// 連携動作を確認する。

// --- 共通オプション定義 ---

///|
/// 実用的な CLI アプリケーションを模したオプション定義セット
fn make_integration_opts() -> Array[OptDef] {
  [
    // --verbose (Flag, default=false, inversion=PrefixNo)
    OptDef::new(
      long="verbose",
      help="Enable verbose output",
      kind=OptKind::Flag(default=false),
      inversion=Some(FlagInversion::PrefixNo),
    ),
    // --format (Single, default=Some("json"), choices=["json","yaml","text"], value_name="FORMAT")
    OptDef::new(
      long="format",
      help="Output format",
      kind=OptKind::Single(default=Some("json")),
      choices=["json", "yaml", "text"],
      value_name="FORMAT",
    ),
    // --eval / -e (Append, defaults=[], value_name="EXPR")
    OptDef::new(
      long="eval",
      help="Evaluate expression",
      kind=OptKind::Append(n=1, defaults=[]),
      shorts=[ShortEntry::new(char='e')],
      value_name="EXPR",
    ),
    // --config (Single, default=None, env=Some("MYAPP_CONFIG"), value_name="PATH")
    OptDef::new(
      long="config",
      help="Configuration file path",
      kind=OptKind::Single(default=None),
      env=Some("MYAPP_CONFIG"),
      value_name="PATH",
    ),
    // --output / -o (Single, default=None, aliases=["out", "output-file"(deprecated)])
    OptDef::new(
      long="output",
      help="Output file",
      kind=OptKind::Single(default=None),
      shorts=[ShortEntry::new(char='o')],
      aliases=[
        AliasEntry::new(name="out"),
        AliasEntry::new(
          name="output-file",
          deprecated=Some("Use --output instead"),
        ),
      ],
    ),
  ]
}

// --- テストシナリオ ---

///|
test "integration: typical CLI usage" {
  let opts = make_integration_opts()
  let result = parse(opts, [
    "--format", "yaml", "--eval", "1+1", "--eval", "2+2", "input.txt", "--", "extra",
  ])
  // format は yaml に指定
  inspect(
    result.get_string("format"),
    content=(
      #|Some("yaml")
    ),
  )
  // eval は 2 つ蓄積
  inspect(
    result.get_list("eval"),
    content=(
      #|["1+1", "2+2"]
    ),
  )
  // positional は input.txt
  inspect(
    result.positional,
    content=(
      #|["input.txt"]
    ),
  )
  // rest は -- 以降
  inspect(
    result.rest,
    content=(
      #|["extra"]
    ),
  )
  // verbose はデフォルト false
  inspect(result.get_flag("verbose"), content="false")
  // config はデフォルト None
  inspect(result.get_string("config"), content="None")
  // output はデフォルト None
  inspect(result.get_string("output"), content="None")
}

///|
test "integration: short options" {
  let opts = make_integration_opts()
  let result = parse(opts, ["-e", "expr1", "-o", "out.txt", "file.txt"])
  // eval はショート -e で蓄積
  inspect(
    result.get_list("eval"),
    content=(
      #|["expr1"]
    ),
  )
  // output はショート -o で指定
  inspect(
    result.get_string("output"),
    content=(
      #|Some("out.txt")
    ),
  )
  // positional
  inspect(
    result.positional,
    content=(
      #|["file.txt"]
    ),
  )
}

///|
test "integration: flag inversion (last wins)" {
  let opts = make_integration_opts()
  // --verbose 後に --no-verbose → 後勝ちで false
  let result = parse(opts, ["--verbose", "--no-verbose"])
  inspect(result.get_flag("verbose"), content="false")
}

///|
test "integration: flag inversion (inverted then normal)" {
  let opts = make_integration_opts()
  // --no-verbose 後に --verbose → 後勝ちで true
  let result = parse(opts, ["--no-verbose", "--verbose"])
  inspect(result.get_flag("verbose"), content="true")
}

///|
test "integration: alias resolution" {
  let opts = make_integration_opts()
  // --out は output のエイリアス
  let result = parse(opts, ["--out", "result.txt"])
  inspect(
    result.get_string("output"),
    content=(
      #|Some("result.txt")
    ),
  )
}

///|
test "integration: deprecated alias resolution" {
  let opts = make_integration_opts()
  // --output-file は deprecated エイリアスだが動作する
  let result = parse(opts, ["--output-file", "old.txt"])
  inspect(
    result.get_string("output"),
    content=(
      #|Some("old.txt")
    ),
  )
}

///|
test "integration: apply_defaults + parse pipeline" {
  let opts = make_integration_opts()
  // layer 1: config defaults (--format yaml, --verbose)
  let config_layer = apply_defaults(opts, ["--format", "yaml", "--verbose"])
  // layer 2: env defaults (--format json) — json が yaml を上書き
  let env_layer = apply_defaults(config_layer, ["--format", "json"])
  // layer 3: CLI args (--no-verbose, input.txt) — verbose を反転
  let result = parse(env_layer, ["--no-verbose", "input.txt"])
  // format は env_layer の json がデフォルトになり、CLI で指定されていないのでそのまま
  inspect(
    result.get_string("format"),
    content=(
      #|Some("json")
    ),
  )
  // verbose は CLI で --no-verbose を指定したので false
  inspect(result.get_flag("verbose"), content="false")
  // positional
  inspect(
    result.positional,
    content=(
      #|["input.txt"]
    ),
  )
}

///|
test "integration: accumulate with defaults pipeline" {
  let opts = make_integration_opts()
  // defaults に ["--eval", "default-expr"] を apply_defaults
  let with_defaults = apply_defaults(opts, ["--eval", "default-expr"])
  // CLI で追加の --eval "extra" を parse
  let result = parse(with_defaults, ["--eval", "extra"])
  // CLI で明示指定したため、デフォルトは適用されず CLI の値のみ
  // (parse は explicitly_set を追跡し、デフォルト上書きしない)
  inspect(
    result.get_list("eval"),
    content=(
      #|["extra"]
    ),
  )
}

///|
test "integration: accumulate defaults applied when not specified on CLI" {
  let opts = make_integration_opts()
  // defaults に ["--eval", "default-expr"] を apply_defaults
  let with_defaults = apply_defaults(opts, ["--eval", "default-expr"])
  // CLI で eval を指定しない → デフォルトが適用される
  let result = parse(with_defaults, ["--verbose"])
  inspect(
    result.get_list("eval"),
    content=(
      #|["default-expr"]
    ),
  )
}

///|
test "integration: accumulate reset via apply_defaults" {
  // eval に PrefixNo 反転を追加したオプション定義
  let opts : Array[OptDef] = [
    OptDef::new(
      long="eval",
      help="Evaluate expression",
      kind=OptKind::Append(n=1, defaults=[]),
      shorts=[ShortEntry::new(char='e')],
      inversion=Some(FlagInversion::PrefixNo),
      value_name="EXPR",
    ),
  ]
  // defaults に old を追加
  let with_old = apply_defaults(opts, ["--eval", "old"])
  inspect(
    with_old[0].kind,
    content=(
      #|Append(defaults=["old"], n=1)
    ),
  )
  // --no-eval でリセットし、--eval new で新しい値を追加
  let reset_and_new = apply_defaults(with_old, ["--no-eval", "--eval", "new"])
  inspect(
    reset_and_new[0].kind,
    content=(
      #|Append(defaults=["new"], n=1)
    ),
  )
  // parse で CLI 引数なし → デフォルトの ["new"] が適用される
  let result = parse(reset_and_new, [])
  inspect(
    result.get_list("eval"),
    content=(
      #|["new"]
    ),
  )
}

///|
test "integration: --help detection" {
  let opts = make_integration_opts()
  // --help は opts に定義されていないため HelpRequested が発生
  let result : Result[ParseResult, Error] = try? parse(opts, ["--help"])
  inspect(
    result,
    content=(
      #|Err(HelpRequested)
    ),
  )
}

///|
test "integration: --help among other args" {
  let opts = make_integration_opts()
  // 他の引数と混在していても --help で HelpRequested
  let result : Result[ParseResult, Error] = try? parse(opts, [
    "--verbose", "--help", "--format", "yaml",
  ])
  inspect(
    result,
    content=(
      #|Err(HelpRequested)
    ),
  )
}

///|
test "integration: error on unknown option" {
  let opts = make_integration_opts()
  let result : Result[ParseResult, Error] = try? parse(opts, ["--unknown"])
  inspect(
    result,
    content=(
      #|Err(UnknownOption("--unknown"))
    ),
  )
}

///|
test "integration: error on unknown short option" {
  let opts = make_integration_opts()
  let result : Result[ParseResult, Error] = try? parse(opts, ["-x"])
  inspect(
    result,
    content=(
      #|Err(UnknownOption("-x"))
    ),
  )
}

///|
test "integration: required option missing" {
  // required=true のオプションを追加
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Enable verbose output",
      kind=OptKind::Flag(default=false),
    ),
    OptDef::new(
      long="target",
      help="Deployment target",
      kind=OptKind::Single(default=None),
      required=true,
    ),
  ]
  let result : Result[ParseResult, Error] = try? parse(opts, ["--verbose"])
  inspect(
    result,
    content=(
      #|Err(MissingRequired("--target"))
    ),
  )
}

///|
test "integration: required option provided" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="target",
      help="Deployment target",
      kind=OptKind::Single(default=None),
      required=true,
    ),
  ]
  let result = parse(opts, ["--target", "production"])
  inspect(
    result.get_string("target"),
    content=(
      #|Some("production")
    ),
  )
}

///|
test "integration: invalid choice error" {
  let opts = make_integration_opts()
  let result : Result[ParseResult, Error] = try? parse(opts, ["--format", "xml"])
  inspect(
    result,
    content=(
      #|Err(InvalidChoice(option="format", value="xml", choices=["json", "yaml", "text"]))
    ),
  )
}

///|
test "integration: --key=value form with all types" {
  let opts = make_integration_opts()
  let result = parse(opts, ["--format=text", "--eval=expr1", "--output=out.txt"])
  inspect(
    result.get_string("format"),
    content=(
      #|Some("text")
    ),
  )
  inspect(
    result.get_list("eval"),
    content=(
      #|["expr1"]
    ),
  )
  inspect(
    result.get_string("output"),
    content=(
      #|Some("out.txt")
    ),
  )
}

///|
test "integration: options after positional args" {
  let opts = make_integration_opts()
  // MoonBit パーサはオプション位置自由
  let result = parse(opts, [
    "input.txt", "--format", "yaml", "other.txt", "--verbose",
  ])
  inspect(
    result.positional,
    content=(
      #|["input.txt", "other.txt"]
    ),
  )
  inspect(
    result.get_string("format"),
    content=(
      #|Some("yaml")
    ),
  )
  inspect(result.get_flag("verbose"), content="true")
}

///|
test "integration: empty args uses all defaults" {
  let opts = make_integration_opts()
  let result = parse(opts, [])
  // verbose: default false
  inspect(result.get_flag("verbose"), content="false")
  // format: default "json"
  inspect(
    result.get_string("format"),
    content=(
      #|Some("json")
    ),
  )
  // eval: default []
  inspect(result.get_list("eval"), content="[]")
  // config: default None
  inspect(result.get_string("config"), content="None")
  // output: default None
  inspect(result.get_string("output"), content="None")
  // positional: empty
  inspect(result.positional, content="[]")
  // rest: empty
  inspect(result.rest, content="[]")
}

///|
test "integration: complex multi-layer defaults pipeline" {
  let opts = make_integration_opts()
  // Layer 1: 設定ファイルレイヤ — format=yaml, verbose=true
  let layer1 = apply_defaults(opts, ["--format", "yaml", "--verbose"])
  // Layer 1 の結果を検証
  inspect(layer1[0].kind, content="Flag(default=true)")
  inspect(layer1[1].kind, content="Single(default=Some(\"yaml\"))")
  // Layer 2: 環境変数レイヤ — format=text（yaml を上書き）
  let layer2 = apply_defaults(layer1, ["--format", "text"])
  inspect(layer2[1].kind, content="Single(default=Some(\"text\"))")
  // verbose は layer1 の true がそのまま
  inspect(layer2[0].kind, content="Flag(default=true)")
  // Layer 3: CLI — --no-verbose で反転、format は指定なし（text がデフォルト）
  let result = parse(layer2, ["--no-verbose", "--output", "final.txt"])
  inspect(result.get_flag("verbose"), content="false")
  inspect(
    result.get_string("format"),
    content=(
      #|Some("text")
    ),
  )
  inspect(
    result.get_string("output"),
    content=(
      #|Some("final.txt")
    ),
  )
}

///|
test "integration: double dash stops option parsing" {
  let opts = make_integration_opts()
  let result = parse(opts, [
    "--verbose", "pos1", "--", "--format", "yaml", "--unknown", "pos2",
  ])
  inspect(result.get_flag("verbose"), content="true")
  inspect(
    result.positional,
    content=(
      #|["pos1"]
    ),
  )
  // -- 以降は rest に入り、オプションとしてパースされない
  inspect(
    result.rest,
    content=(
      #|["--format", "yaml", "--unknown", "pos2"]
    ),
  )
  // format は CLI で指定されていないのでデフォルト
  inspect(
    result.get_string("format"),
    content=(
      #|Some("json")
    ),
  )
}

///|
test "integration: missing value error for single option" {
  let opts = make_integration_opts()
  // --format の後に値がない（--verbose が次に来る）
  let result : Result[ParseResult, Error] = try? parse(opts, [
    "--format", "--verbose",
  ])
  // --verbose がフォーマットの値として消費される
  // (tokenize は全てをトークン化するだけで、値の判定は parse が行う)
  // → format="--verbose" になり choices チェックで失敗
  inspect(
    result,
    content=(
      #|Err(InvalidChoice(option="format", value="--verbose", choices=["json", "yaml", "text"]))
    ),
  )
}

///|
test "integration: missing value at end of args" {
  let opts = make_integration_opts()
  // --output が最後で値がない
  let result : Result[ParseResult, Error] = try? parse(opts, ["--output"])
  inspect(
    result,
    content=(
      #|Err(MissingValue("--output"))
    ),
  )
}

///|
test "integration: apply_defaults preserves original opts (purity)" {
  let opts = make_integration_opts()
  let _modified = apply_defaults(opts, [
    "--verbose", "--format", "yaml", "--eval", "test",
  ])
  // 元の opts は変更されていない
  inspect(opts[0].kind, content="Flag(default=false)")
  inspect(opts[1].kind, content="Single(default=Some(\"json\"))")
  inspect(
    opts[2].kind,
    content=(
      #|Append(defaults=[], n=1)
    ),
  )
}

// --- W6, W7: 追加テスト ---

///|
test "integration: PrefixEnableDisable" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="cache",
      help="Enable caching",
      kind=OptKind::Flag(default=true),
      inversion=Some(FlagInversion::PrefixEnableDisable),
    ),
  ]
  // --disable-cache で false
  let result1 = parse(opts, ["--disable-cache"])
  inspect(result1.get_flag("cache"), content="false")
  // --enable-cache で true
  let result2 = parse(opts, ["--enable-cache"])
  inspect(result2.get_flag("cache"), content="true")
  // --disable-cache 後に --enable-cache → 後勝ちで true
  let result3 = parse(opts, ["--disable-cache", "--enable-cache"])
  inspect(result3.get_flag("cache"), content="true")
}

///|
test "integration: PrefixWithWithout" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="ssl",
      help="SSL support",
      kind=OptKind::Flag(default=true),
      inversion=Some(FlagInversion::PrefixWithWithout),
    ),
  ]
  // --without-ssl で false
  let result1 = parse(opts, ["--without-ssl"])
  inspect(result1.get_flag("ssl"), content="false")
  // --with-ssl で true
  let result2 = parse(opts, ["--with-ssl"])
  inspect(result2.get_flag("ssl"), content="true")
  // --with-ssl 後に --without-ssl → 後勝ちで false
  let result3 = parse(opts, ["--with-ssl", "--without-ssl"])
  inspect(result3.get_flag("ssl"), content="false")
}

///|
test "integration: -- after --" {
  let opts : Array[OptDef] = []
  let result = parse(opts, ["--", "--"])
  inspect(result.positional, content="[]")
  inspect(
    result.rest,
    content=(
      #|["--"]
    ),
  )
}

// === サブコマンド統合テスト ===

///|
test "integration: subcmd - 3段ネスト + グローバルOpt" {
  // app --verbose remote add origin
  // verbose はルートの global_opts、remote > add と2段ネスト
  let cmd = CmdDef::new(
    name="app",
    global_opts=[
      OptDef::new(
        long="verbose",
        help="Verbose output",
        kind=OptKind::Flag(default=false),
      ),
    ],
    subcommands=[
      CmdDef::new(name="remote", subcommands=[
        CmdDef::new(name="add", help_on_empty=false, opts=[
          OptDef::new(
            long="name",
            help="Remote name",
            kind=OptKind::Single(default=None),
          ),
        ]),
      ]),
    ],
  )
  let cr = parse_command(cmd, ["--verbose", "remote", "add", "--name", "origin"])
  inspect(
    cr.command,
    content=(
      #|["remote", "add"]
    ),
  )
  inspect(cr.result.get_flag("verbose"), content="true")
  inspect(
    cr.result.get_string("name"),
    content=(
      #|Some("origin")
    ),
  )
}

///|
test "integration: subcmd - apply_defaults + parse_command" {
  // 設定ファイル由来のデフォルトを apply_defaults で畳み込んでから parse_command
  let cmd = CmdDef::new(
    name="app",
    global_opts=[
      OptDef::new(
        long="verbose",
        help="Verbose output",
        kind=OptKind::Flag(default=false),
        inversion=Some(FlagInversion::PrefixNo),
      ),
    ],
    subcommands=[
      CmdDef::new(name="build", help_on_empty=false, opts=[
        OptDef::new(
          long="target",
          help="Build target",
          kind=OptKind::Single(default=Some("debug")),
        ),
      ]),
    ],
  )
  // 設定ファイルレイヤ: target=release をデフォルトに
  let config_layer = apply_defaults(cmd.subcommands[0].opts, [
    "--target", "release",
  ])
  // config_layer のデフォルトが更新されていることを確認
  inspect(config_layer[0].kind, content="Single(default=Some(\"release\"))")
  // 更新されたオプション定義で CmdDef を再構築
  let cmd2 = CmdDef::new(name="app", global_opts=cmd.global_opts, subcommands=[
    CmdDef::new(name="build", help_on_empty=false, opts=config_layer),
  ])
  // CLI: target を指定しない → release がデフォルト適用
  let cr = parse_command(cmd2, ["build", "--verbose"])
  inspect(
    cr.command,
    content=(
      #|["build"]
    ),
  )
  inspect(cr.result.get_flag("verbose"), content="true")
  inspect(
    cr.result.get_string("target"),
    content=(
      #|Some("release")
    ),
  )
}

///|
test "integration: subcmd - グローバルOpt が全レベルに散らばる" {
  // ルートに --verbose、config に --format、set にはなし → set で全部使える
  let cmd = CmdDef::new(
    name="app",
    global_opts=[
      OptDef::new(
        long="verbose",
        help="Verbose output",
        kind=OptKind::Flag(default=false),
      ),
    ],
    subcommands=[
      CmdDef::new(
        name="config",
        global_opts=[
          OptDef::new(
            long="format",
            help="Output format",
            kind=OptKind::Single(default=Some("text")),
          ),
        ],
        subcommands=[
          CmdDef::new(name="set", help_on_empty=false, opts=[
            OptDef::new(
              long="key",
              help="Config key",
              kind=OptKind::Single(default=None),
            ),
          ]),
        ],
      ),
    ],
  )
  let cr = parse_command(cmd, [
    "config", "set", "--key", "name", "--verbose", "--format", "json",
  ])
  inspect(
    cr.command,
    content=(
      #|["config", "set"]
    ),
  )
  inspect(
    cr.result.get_string("key"),
    content=(
      #|Some("name")
    ),
  )
  inspect(cr.result.get_flag("verbose"), content="true")
  inspect(
    cr.result.get_string("format"),
    content=(
      #|Some("json")
    ),
  )
}

///|
test "integration: subcmd - Append オプション + サブコマンド" {
  // ["--eval", "a", "run", "--eval", "b"] で eval が global_opts の Append
  let cmd = CmdDef::new(
    name="app",
    global_opts=[
      OptDef::new(
        long="eval",
        help="Evaluate expression",
        kind=OptKind::Append(n=1, defaults=[]),
        shorts=[ShortEntry::new(char='e')],
      ),
    ],
    subcommands=[CmdDef::new(name="run", help_on_empty=false)],
  )
  let cr = parse_command(cmd, ["--eval", "a", "run", "--eval", "b"])
  inspect(
    cr.command,
    content=(
      #|["run"]
    ),
  )
  inspect(
    cr.result.get_list("eval"),
    content=(
      #|["a", "b"]
    ),
  )
}

///|
test "integration: subcmd - Count オプション + サブコマンド" {
  // ["-vvv", "deploy"] で v が global_opts の Count
  let cmd = CmdDef::new(
    name="app",
    global_opts=[
      OptDef::new(
        long="verbose",
        help="Verbosity level",
        kind=OptKind::Count(default=0),
        shorts=[ShortEntry::new(char='v')],
      ),
    ],
    subcommands=[CmdDef::new(name="deploy", help_on_empty=false)],
  )
  let cr = parse_command(cmd, ["-vvv", "deploy"])
  inspect(
    cr.command,
    content=(
      #|["deploy"]
    ),
  )
  inspect(cr.result.get_count("verbose"), content="3")
}

///|
test "integration: subcmd - OptionalValue + サブコマンド" {
  // ["--color", "build"] で color が global_opts の OptionalValue
  // --color は = 形式なしなので implicit 値 "always" が使われる
  // "build" はサブコマンドとして解決される
  let cmd = CmdDef::new(
    name="app",
    global_opts=[
      OptDef::new(
        long="color",
        help="Color output",
        kind=OptKind::OptionalValue(
          default=None,
          implicit="always",
          negated=Some("never"),
        ),
        inversion=Some(FlagInversion::PrefixNo),
      ),
    ],
    subcommands=[CmdDef::new(name="build", help_on_empty=false)],
  )
  let cr = parse_command(cmd, ["--color", "build"])
  inspect(
    cr.command,
    content=(
      #|["build"]
    ),
  )
  // --color は値なし形式なので implicit="always" が適用
  inspect(
    cr.result.get_string("color"),
    content=(
      #|Some("always")
    ),
  )
}

///|
test "integration: subcmd - FlagInversion + サブコマンド" {
  // ["--no-verbose", "deploy"] で verbose が反転
  let cmd = CmdDef::new(
    name="app",
    global_opts=[
      OptDef::new(
        long="verbose",
        help="Verbose output",
        kind=OptKind::Flag(default=true),
        inversion=Some(FlagInversion::PrefixNo),
      ),
    ],
    subcommands=[CmdDef::new(name="deploy", help_on_empty=false)],
  )
  let cr = parse_command(cmd, ["--no-verbose", "deploy"])
  inspect(
    cr.command,
    content=(
      #|["deploy"]
    ),
  )
  inspect(cr.result.get_flag("verbose"), content="false")
}

///|
test "integration: subcmd - エイリアス + 多段ネスト" {
  // git のようなコマンド体系: co = checkout, ci = commit
  let cmd = CmdDef::new(
    name="git",
    global_opts=[
      OptDef::new(
        long="verbose",
        help="Verbose output",
        kind=OptKind::Flag(default=false),
      ),
    ],
    subcommands=[
      CmdDef::new(
        name="checkout",
        aliases=[AliasEntry::new(name="co")],
        help_on_empty=false,
        opts=[
          OptDef::new(
            long="branch",
            help="Branch name",
            kind=OptKind::Single(default=None),
            shorts=[ShortEntry::new(char='b')],
          ),
        ],
      ),
      CmdDef::new(name="remote", aliases=[AliasEntry::new(name="rm")], subcommands=[
        CmdDef::new(
          name="add",
          aliases=[AliasEntry::new(name="a")],
          help_on_empty=false,
          opts=[
            OptDef::new(
              long="url",
              help="Remote URL",
              kind=OptKind::Single(default=None),
            ),
          ],
        ),
      ]),
    ],
  )
  // エイリアス co でサブコマンド解決
  let cr1 = parse_command(cmd, ["co", "--branch", "main"])
  inspect(
    cr1.command,
    content=(
      #|["checkout"]
    ),
  )
  inspect(
    cr1.result.get_string("branch"),
    content=(
      #|Some("main")
    ),
  )
  // 多段ネスト + エイリアス: rm a = remote add
  let cr2 = parse_command(cmd, [
    "--verbose", "rm", "a", "--url", "https://example.com",
  ])
  inspect(
    cr2.command,
    content=(
      #|["remote", "add"]
    ),
  )
  inspect(cr2.result.get_flag("verbose"), content="true")
  inspect(
    cr2.result.get_string("url"),
    content=(
      #|Some("https://example.com")
    ),
  )
}

///|
test "integration: subcmd - -- 以降はサブコマンドにならない" {
  // ["build", "--", "extra"] → rest に "extra"
  let cmd = CmdDef::new(name="app", subcommands=[
    CmdDef::new(name="build", help_on_empty=false, opts=[
      OptDef::new(
        long="target",
        help="Build target",
        kind=OptKind::Single(default=Some("debug")),
      ),
    ]),
  ])
  let cr = parse_command(cmd, [
    "build", "--target", "release", "--", "extra1", "extra2",
  ])
  inspect(
    cr.command,
    content=(
      #|["build"]
    ),
  )
  inspect(
    cr.result.get_string("target"),
    content=(
      #|Some("release")
    ),
  )
  inspect(
    cr.result.rest,
    content=(
      #|["extra1", "extra2"]
    ),
  )
}

///|
test "integration: subcmd - positional + サブコマンド" {
  // ["deploy", "production"] で production は positional
  let cmd = CmdDef::new(name="app", subcommands=[
    CmdDef::new(name="deploy", help_on_empty=false, opts=[
      OptDef::new(
        long="force",
        help="Force deploy",
        kind=OptKind::Flag(default=false),
      ),
    ]),
  ])
  let cr = parse_command(cmd, ["deploy", "--force", "production"])
  inspect(
    cr.command,
    content=(
      #|["deploy"]
    ),
  )
  inspect(cr.result.get_flag("force"), content="true")
  inspect(
    cr.result.positional,
    content=(
      #|["production"]
    ),
  )
}

// === Phase 3 統合テスト ===
// Group オプション (OptKind::Group) の複合的なシナリオを検証する。

// --- 共通定義: authsock_filter ---

///|
/// authsock_filter 風のオプション定義
/// --verbose: Flag
/// --upstream HOST: Group(WithValue, opts=[--socket, --timeout], positional=Variadic)
fn make_authsock_filter_opts() -> Array[OptDef] {
  [
    OptDef::new(
      long="verbose",
      help="Verbose output",
      kind=OptKind::Flag(default=false),
      inversion=Some(FlagInversion::PrefixNo),
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
          OptDef::new(
            long="timeout",
            help="Timeout in seconds",
            kind=OptKind::Single(default=Some("30")),
          ),
        ],
        positional=Positional::Variadic(PositionalDef::new(name="FINGERPRINT")),
      ),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
}

// --- 統合テスト 1: authsock_filter フルシナリオ ---

///|
test "integration: authsock_filter full scenario" {
  let opts = make_authsock_filter_opts()
  // --verbose --upstream u1 --socket s1 a b --upstream u2 --socket s2 c
  let result = parse(opts, [
    "--verbose", "--upstream", "u1", "--socket", "s1", "a", "b", "--upstream", "u2",
    "--socket", "s2", "c",
  ])
  // --verbose は true
  inspect(result.get_flag("verbose"), content="true")
  // upstream は GroupValue で 2 インスタンス
  let groups = result.get_group("upstream")
  inspect(not(groups is None), content="true")
  let instances = groups.unwrap()
  inspect(instances.length(), content="2")
  // u1: socket=s1, timeout=30(default), positional=["a", "b"]
  let u1 = instances[0]
  inspect(u1.value, content="Some(\"u1\")")
  inspect(
    u1.result.get_string("socket"),
    content=(
      #|Some("s1")
    ),
  )
  inspect(
    u1.result.get_string("timeout"),
    content=(
      #|Some("30")
    ),
  )
  inspect(
    u1.result.positional,
    content=(
      #|["a", "b"]
    ),
  )
  // u2: socket=s2, timeout=30(default), positional=["c"]
  let u2 = instances[1]
  inspect(u2.value, content="Some(\"u2\")")
  inspect(
    u2.result.get_string("socket"),
    content=(
      #|Some("s2")
    ),
  )
  inspect(
    u2.result.get_string("timeout"),
    content=(
      #|Some("30")
    ),
  )
  inspect(
    u2.result.positional,
    content=(
      #|["c"]
    ),
  )
}

// --- 統合テスト 2: 3段ネストシナリオ ---

///|
test "integration: 3-level nested Group" {
  // --server HOST > --database DB > --table TABLE (Single)
  //   server: Group(WithValue), opts に database: Group(WithValue), opts に table: Single
  let opts : Array[OptDef] = [
    OptDef::new(
      long="server",
      help="Server host",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=None),
        opts=[
          OptDef::new(
            long="database",
            help="Database name",
            kind=OptKind::Group(
              group_kind=GroupKind::WithValue(default=None),
              opts=[
                OptDef::new(
                  long="table",
                  help="Table name",
                  kind=OptKind::Single(default=None),
                ),
              ],
              positional=Positional::Disallowed,
            ),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  // --server s1 --database db1 --table t1 --database db2 --table t2 --server s2 --database db3 --table t3
  let result = parse(opts, [
    "--server", "s1", "--database", "db1", "--table", "t1", "--database", "db2",
    "--table", "t2", "--server", "s2", "--database", "db3", "--table", "t3",
  ])
  let servers = result.get_group("server").unwrap()
  inspect(servers.length(), content="2")
  // s1: database=[db1(table=t1), db2(table=t2)]
  let s1 = servers[0]
  inspect(s1.value, content="Some(\"s1\")")
  let s1_dbs = s1.result.get_group("database").unwrap()
  inspect(s1_dbs.length(), content="2")
  inspect(s1_dbs[0].value, content="Some(\"db1\")")
  inspect(
    s1_dbs[0].result.get_string("table"),
    content=(
      #|Some("t1")
    ),
  )
  inspect(s1_dbs[1].value, content="Some(\"db2\")")
  inspect(
    s1_dbs[1].result.get_string("table"),
    content=(
      #|Some("t2")
    ),
  )
  // s2: database=[db3(table=t3)]
  let s2 = servers[1]
  inspect(s2.value, content="Some(\"s2\")")
  let s2_dbs = s2.result.get_group("database").unwrap()
  inspect(s2_dbs.length(), content="1")
  inspect(s2_dbs[0].value, content="Some(\"db3\")")
  inspect(
    s2_dbs[0].result.get_string("table"),
    content=(
      #|Some("t3")
    ),
  )
}

// --- 統合テスト 3: Group + apply_defaults パイプライン ---

///|
test "integration: Group + apply_defaults pipeline" {
  let opts = make_authsock_filter_opts()
  // apply_defaults で upstream のデフォルト値を設定
  let with_defaults = apply_defaults(opts, ["--upstream", "default-host"])
  // デフォルト値が GroupKind::WithValue(default=Some("default-host")) に変更されたことを確認
  match with_defaults[1].kind {
    Group(group_kind=WithValue(default=d), ..) =>
      inspect(
        d,
        content=(
          #|Some("default-host")
        ),
      )
    _ => inspect("unexpected kind", content="")
  }
  // parse: --socket を指定するが --upstream は指定しない → デフォルト host が使われる
  let result = parse(with_defaults, ["--socket", "s1", "fp1"])
  let groups = result.get_group("upstream").unwrap()
  inspect(
    groups.length(),
    content=(
      #|1
    ),
  )
  let inst = groups[0]
  inspect(
    inst.value,
    content=(
      #|Some("default-host")
    ),
  )
  inspect(
    inst.result.get_string("socket"),
    content=(
      #|Some("s1")
    ),
  )
  inspect(
    inst.result.positional,
    content=(
      #|["fp1"]
    ),
  )
}

// --- 統合テスト 4: Group + --help で HelpRequested ---

///|
test "integration: Group --help at root level" {
  let opts = make_authsock_filter_opts()
  let result : Result[ParseResult, Error] = try? parse(opts, ["--help"])
  inspect(
    result,
    content=(
      #|Err(HelpRequested)
    ),
  )
}

///|
test "integration: Group --help inside child scope" {
  let opts = make_authsock_filter_opts()
  // --upstream u1 --help (子スコープ内の --help)
  let result : Result[ParseResult, Error] = try? parse(opts, [
    "--upstream", "u1", "--help",
  ])
  inspect(
    result,
    content=(
      #|Err(HelpRequested)
    ),
  )
}

// --- 統合テスト 5: Group required チェック ---

///|
test "integration: Group required option missing inside group" {
  // upstream 内の socket を required にする
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
            required=true,
          ),
        ],
        positional=Positional::Variadic(PositionalDef::new()),
      ),
    ),
  ]
  // --upstream u1 で --socket を渡さない → MissingRequired
  let result : Result[ParseResult, Error] = try? parse(opts, [
    "--upstream", "u1",
  ])
  inspect(
    result,
    content=(
      #|Err(MissingRequired("--socket"))
    ),
  )
}

// --- 統合テスト 6: Group choices チェック ---

///|
test "integration: Group choices validation inside group" {
  // upstream 内の socket に choices 制約を設定
  let opts : Array[OptDef] = [
    OptDef::new(
      long="upstream",
      help="Upstream server",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=None),
        opts=[
          OptDef::new(
            long="socket",
            help="Socket type",
            kind=OptKind::Single(default=None),
            choices=["unix", "tcp"],
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  // --upstream u1 --socket invalid → InvalidChoice
  let result : Result[ParseResult, Error] = try? parse(opts, [
    "--upstream", "u1", "--socket", "invalid",
  ])
  inspect(
    result,
    content=(
      #|Err(InvalidChoice(option="socket", value="invalid", choices=["unix", "tcp"]))
    ),
  )
}

// --- 統合テスト 7: Group + DoubleDash ---

///|
test "integration: Group + DoubleDash" {
  let opts = make_authsock_filter_opts()
  // --upstream u1 --socket s1 -- rest1 rest2
  let result = parse(opts, [
    "--upstream", "u1", "--socket", "s1", "--", "rest1", "rest2",
  ])
  // upstream u1 の socket=s1 が設定される
  let groups = result.get_group("upstream").unwrap()
  inspect(
    groups.length(),
    content=(
      #|1
    ),
  )
  let u1 = groups[0]
  inspect(
    u1.result.get_string("socket"),
    content=(
      #|Some("s1")
    ),
  )
  // DoubleDash 後は rest に入る
  inspect(
    result.rest,
    content=(
      #|["rest1", "rest2"]
    ),
  )
  // 子スコープの positional は空
  inspect(
    u1.result.positional,
    content=(
      #|[]
    ),
  )
}

// --- 統合テスト 8: Group + 複雑なマージ ---

///|
test "integration: Group complex merge" {
  let opts = make_authsock_filter_opts()
  // --upstream u1 --socket s1 --upstream u2 --socket s2 --upstream u1 --timeout 60
  // u1 が2回出現: socket=s1(1回目), timeout=60(2回目のマージ)
  let result = parse(opts, [
    "--upstream", "u1", "--socket", "s1", "--upstream", "u2", "--socket", "s2", "--upstream",
    "u1", "--timeout", "60",
  ])
  let groups = result.get_group("upstream").unwrap()
  inspect(
    groups.length(),
    content=(
      #|2
    ),
  )
  // u1: socket=s1, timeout=60
  let u1 = groups[0]
  inspect(
    u1.value,
    content=(
      #|Some("u1")
    ),
  )
  inspect(
    u1.result.get_string("socket"),
    content=(
      #|Some("s1")
    ),
  )
  inspect(
    u1.result.get_string("timeout"),
    content=(
      #|Some("60")
    ),
  )
  // u2: socket=s2, timeout=30(default)
  let u2 = groups[1]
  inspect(
    u2.value,
    content=(
      #|Some("u2")
    ),
  )
  inspect(
    u2.result.get_string("socket"),
    content=(
      #|Some("s2")
    ),
  )
  inspect(
    u2.result.get_string("timeout"),
    content=(
      #|Some("30")
    ),
  )
}
