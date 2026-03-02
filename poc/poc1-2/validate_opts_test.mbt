///|
test "validate_opts: valid opts pass" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Enable verbose output",
      kind=OptKind::Flag(default=false),
      shorts=[ShortEntry::new(char='v')],
    ),
    OptDef::new(
      long="format",
      help="Output format",
      kind=OptKind::Single(default=Some("json")),
      choices=["json", "yaml", "text"],
    ),
    OptDef::new(
      long="output",
      help="Output file",
      kind=OptKind::Single(default=None),
      aliases=[AliasEntry::new(name="out")],
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(result, content="Ok(())")
}

///|
test "validate_opts: empty long name" {
  let opts : Array[OptDef] = [
    OptDef::new(long="", help="Bad option", kind=OptKind::Flag(default=false)),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("empty long name"))
    ),
  )
}

///|
test "validate_opts: duplicate long name" {
  let opts : Array[OptDef] = [
    OptDef::new(long="verbose", help="First", kind=OptKind::Flag(default=false)),
    OptDef::new(
      long="verbose",
      help="Second",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("duplicate long: verbose"))
    ),
  )
}

///|
test "validate_opts: duplicate short char" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="First",
      kind=OptKind::Flag(default=false),
      shorts=[ShortEntry::new(char='v')],
    ),
    OptDef::new(
      long="version",
      help="Second",
      kind=OptKind::Flag(default=false),
      shorts=[ShortEntry::new(char='v')],
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("duplicate short: v"))
    ),
  )
}

///|
test "validate_opts: alias conflicts with long name" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
    ),
    OptDef::new(long="debug", help="Debug", kind=OptKind::Flag(default=false), aliases=[
      AliasEntry::new(name="verbose"),
    ]),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("alias conflict: verbose"))
    ),
  )
}

///|
test "validate_opts: alias conflicts with another alias" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="output",
      help="Output",
      kind=OptKind::Single(default=None),
      aliases=[AliasEntry::new(name="out")],
    ),
    OptDef::new(
      long="outfile",
      help="Output file",
      kind=OptKind::Single(default=None),
      aliases=[AliasEntry::new(name="out")],
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("alias conflict: out"))
    ),
  )
}

///|
test "validate_opts: inversion PrefixNo conflict" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="color",
      help="Enable color",
      kind=OptKind::Flag(default=true),
      inversion=Some(FlagInversion::PrefixNo),
    ),
    OptDef::new(
      long="no-color",
      help="Disable color",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("inversion conflict: no-color"))
    ),
  )
}

///|
test "validate_opts: inversion PrefixEnableDisable conflict" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="feature",
      help="Feature flag",
      kind=OptKind::Flag(default=false),
      inversion=Some(FlagInversion::PrefixEnableDisable),
    ),
    OptDef::new(
      long="enable-feature",
      help="Enable feature",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("inversion conflict: enable-feature"))
    ),
  )
}

///|
test "validate_opts: inversion PrefixWithWithout conflict" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="deps",
      help="Dependencies",
      kind=OptKind::Flag(default=true),
      inversion=Some(FlagInversion::PrefixWithWithout),
    ),
    OptDef::new(
      long="without-deps",
      help="Without deps",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("inversion conflict: without-deps"))
    ),
  )
}

///|
test "validate_opts: choices with default outside choices" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="format",
      help="Output format",
      kind=OptKind::Single(default=Some("xml")),
      choices=["json", "yaml", "text"],
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("default value \"xml\" not in choices for --format"))
    ),
  )
}

///|
test "validate_opts: choices with default None passes" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="format",
      help="Output format",
      kind=OptKind::Single(default=None),
      choices=["json", "yaml", "text"],
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(result, content="Ok(())")
}

///|
test "validate_opts: choices with default inside choices passes" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="format",
      help="Output format",
      kind=OptKind::Single(default=Some("json")),
      choices=["json", "yaml", "text"],
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(result, content="Ok(())")
}

///|
test "validate_opts: invalid short char dash" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
      shorts=[ShortEntry::new(char='-')],
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("invalid short option: -"))
    ),
  )
}

///|
test "validate_opts: invalid short char equals" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
      shorts=[ShortEntry::new(char='=')],
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("invalid short option: ="))
    ),
  )
}

///|
test "validate_opts: invalid short char space" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
      shorts=[ShortEntry::new(char=' ')],
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("invalid short option:  "))
    ),
  )
}

///|
test "validate_opts: valid short chars alphanumeric" {
  let opts : Array[OptDef] = [
    OptDef::new(long="aaa", help="A", kind=OptKind::Flag(default=false), shorts=[
      ShortEntry::new(char='a'),
    ]),
    OptDef::new(long="bbb", help="B", kind=OptKind::Flag(default=false), shorts=[
      ShortEntry::new(char='Z'),
    ]),
    OptDef::new(long="ccc", help="C", kind=OptKind::Flag(default=false), shorts=[
      ShortEntry::new(char='9'),
    ]),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(result, content="Ok(())")
}

///|
test "validate_opts: accumulate defaults with choices valid" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="level",
      help="Log level",
      kind=OptKind::Append(n=1, defaults=["info", "warn"]),
      choices=["debug", "info", "warn", "error"],
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(result, content="Ok(())")
}

///|
test "validate_opts: accumulate defaults with choices invalid" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="level",
      help="Log level",
      kind=OptKind::Append(n=1, defaults=["info", "trace"]),
      choices=["debug", "info", "warn", "error"],
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("default value \"trace\" not in choices for --level"))
    ),
  )
}

///|
test "validate_opts: accumulate empty defaults with choices passes" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="level",
      help="Log level",
      kind=OptKind::Append(n=1, defaults=[]),
      choices=["debug", "info", "warn", "error"],
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(result, content="Ok(())")
}

///|
test "validate_opts: long name with invalid chars" {
  let opts = [
    OptDef::new(long="Format", help="h", kind=OptKind::Flag(default=false)),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("long name contains invalid character: Format"))
    ),
  )
}

///|
test "validate_opts: long name with hyphen at start" {
  let opts = [
    OptDef::new(long="-format", help="h", kind=OptKind::Flag(default=false)),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("long name starts or ends with hyphen: -format"))
    ),
  )
}

///|
test "validate_opts: alias with invalid chars" {
  let opts = [
    OptDef::new(long="format", help="h", kind=OptKind::Flag(default=false), aliases=[
      AliasEntry::new(name="Format!"),
    ]),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("alias name contains invalid character: Format!"))
    ),
  )
}

///|
test "validate_opts: valid long names" {
  let opts = [
    OptDef::new(
      long="output-format",
      help="h",
      kind=OptKind::Flag(default=false),
    ),
    OptDef::new(long="port", help="h", kind=OptKind::Single(default=None)),
    OptDef::new(long="v2", help="h", kind=OptKind::Flag(default=false)),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(result, content="Ok(())")
}

// === OptionalValue + short 禁止 ===

///|
test "validate_opts: OptionalValue with short raises DefinitionError" {
  let opts = [
    OptDef::new(
      long="color",
      help="Color",
      kind=OptKind::OptionalValue(default=None, implicit="auto", negated=None),
      shorts=[ShortEntry::new(char='c')],
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("OptionalValue cannot have short options: --color"))
    ),
  )
}

///|
test "validate_opts: OptionalValue without short passes" {
  let opts = [
    OptDef::new(
      long="color",
      help="Color",
      kind=OptKind::OptionalValue(
        default=None,
        implicit="auto",
        negated=Some("never"),
      ),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(result, content="Ok(())")
}

// === Count + choices 禁止 ===

///|
test "validate_opts: Count with choices raises DefinitionError" {
  let opts = [
    OptDef::new(
      long="verbose",
      help="Verbosity",
      kind=OptKind::Count(default=0),
      choices=["0", "1", "2"],
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("Count cannot have choices: --verbose"))
    ),
  )
}

///|
test "validate_opts: Count without choices passes" {
  let opts = [
    OptDef::new(
      long="verbose",
      help="Verbosity",
      kind=OptKind::Count(default=0),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(result, content="Ok(())")
}

// === OptionalValue + choices バリデーション ===

///|
test "validate_opts: OptionalValue choices implicit not in choices" {
  let opts = [
    OptDef::new(
      long="color",
      help="Color",
      kind=OptKind::OptionalValue(
        default=None,
        implicit="auto",
        negated=Some("never"),
      ),
      choices=["always", "never"],
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("implicit value \"auto\" not in choices for --color"))
    ),
  )
}

///|
test "validate_opts: OptionalValue choices negated not in choices" {
  let opts = [
    OptDef::new(
      long="color",
      help="Color",
      kind=OptKind::OptionalValue(
        default=None,
        implicit="auto",
        negated=Some("never"),
      ),
      choices=["auto", "always"],
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("negated value \"never\" not in choices for --color"))
    ),
  )
}

///|
test "validate_opts: OptionalValue choices default not in choices" {
  let opts = [
    OptDef::new(
      long="color",
      help="Color",
      kind=OptKind::OptionalValue(
        default=Some("invalid"),
        implicit="auto",
        negated=Some("never"),
      ),
      choices=["auto", "always", "never"],
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("default value \"invalid\" not in choices for --color"))
    ),
  )
}

///|
test "validate_opts: OptionalValue choices all valid passes" {
  let opts = [
    OptDef::new(
      long="color",
      help="Color",
      kind=OptKind::OptionalValue(
        default=Some("auto"),
        implicit="auto",
        negated=Some("never"),
      ),
      choices=["auto", "always", "never"],
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(result, content="Ok(())")
}

// === Append n バリデーション ===

///|
test "validate_opts: Append n=0 raises DefinitionError" {
  let opts = [
    OptDef::new(long="arg", help="Arg", kind=OptKind::Append(n=0, defaults=[])),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("n must be >= 1 for --arg"))
    ),
  )
}

///|
test "validate_opts: Append defaults not divisible by n" {
  let opts = [
    OptDef::new(
      long="arg",
      help="Arg",
      kind=OptKind::Append(n=2, defaults=["k1", "v1", "k2"]),
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("defaults length must be divisible by n for --arg"))
    ),
  )
}

///|
test "validate_opts: Append n=2 defaults valid" {
  let opts = [
    OptDef::new(
      long="arg",
      help="Arg",
      kind=OptKind::Append(n=2, defaults=["k1", "v1"]),
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(result, content="Ok(())")
}

///|
test "validate_opts: Append n=2 empty defaults valid" {
  let opts = [
    OptDef::new(long="arg", help="Arg", kind=OptKind::Append(n=2, defaults=[])),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(result, content="Ok(())")
}

// === W8: 追加テスト ===

///|
test "validate_opts: trailing hyphen" {
  let opts = [
    OptDef::new(
      long="format-",
      help="Bad name",
      kind=OptKind::Single(default=None),
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("long name starts or ends with hyphen: format-"))
    ),
  )
}

///|
test "validate_opts: Append n=-1" {
  let opts = [
    OptDef::new(long="arg", help="Arg", kind=OptKind::Append(n=-1, defaults=[])),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("n must be >= 1 for --arg"))
    ),
  )
}

// === Group バリデーション ===

///|
test "validate_opts: Valueless Group with env raises DefinitionError" {
  let opts = [
    OptDef::new(
      long="ssl",
      help="Enable SSL",
      kind=OptKind::Group(
        group_kind=GroupKind::Valueless,
        opts=[
          OptDef::new(
            long="cert",
            help="Certificate",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
      env=Some("SSL"),
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("opt '--ssl': Valueless Group cannot have env"))
    ),
  )
}

///|
test "validate_opts: Valueless Group with choices raises DefinitionError" {
  let opts = [
    OptDef::new(
      long="ssl",
      help="Enable SSL",
      kind=OptKind::Group(
        group_kind=GroupKind::Valueless,
        opts=[
          OptDef::new(
            long="cert",
            help="Certificate",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
      choices=["a", "b"],
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("opt '--ssl': Valueless Group cannot have choices"))
    ),
  )
}

///|
test "validate_opts: Valueless Group with value_name raises DefinitionError" {
  let opts = [
    OptDef::new(
      long="ssl",
      help="Enable SSL",
      kind=OptKind::Group(
        group_kind=GroupKind::Valueless,
        opts=[
          OptDef::new(
            long="cert",
            help="Certificate",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
      value_name="TYPE",
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("opt '--ssl': Valueless Group cannot have value_name"))
    ),
  )
}

///|
test "validate_opts: Group inner opts recursive validation" {
  let opts = [
    OptDef::new(
      long="ssl",
      help="Enable SSL",
      kind=OptKind::Group(
        group_kind=GroupKind::Valueless,
        opts=[
          OptDef::new(
            long="format",
            help="Format",
            kind=OptKind::Single(default=Some("xml")),
            choices=["json", "yaml"],
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("default value \"xml\" not in choices for --format"))
    ),
  )
}

///|
test "validate_opts: Group inner opts with help raises DefinitionError" {
  let opts = [
    OptDef::new(
      long="ssl",
      help="Enable SSL",
      kind=OptKind::Group(
        group_kind=GroupKind::Valueless,
        opts=[
          OptDef::new(
            long="help",
            help="Show help",
            kind=OptKind::Flag(default=false),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("opt '--ssl': Group cannot contain 'help' option"))
    ),
  )
}

///|
test "validate_opts: Group inner opts with version raises DefinitionError" {
  let opts = [
    OptDef::new(
      long="ssl",
      help="Enable SSL",
      kind=OptKind::Group(
        group_kind=GroupKind::Valueless,
        opts=[
          OptDef::new(
            long="version",
            help="Show version",
            kind=OptKind::Flag(default=false),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("opt '--ssl': Group cannot contain 'version' option"))
    ),
  )
}

///|
test "validate_opts: duplicate WithValue default Group raises DefinitionError" {
  let opts = [
    OptDef::new(
      long="ssl",
      help="Enable SSL",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=Some("tls1.2")),
        opts=[],
        positional=Positional::Disallowed,
      ),
    ),
    OptDef::new(
      long="proxy",
      help="Enable proxy",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=Some("http")),
        opts=[],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("opt '--proxy': duplicate WithValue(default=Some) Group (conflicts with '--ssl')"))
    ),
  )
}

///|
test "validate_opts: valid Group definition passes" {
  let opts = [
    OptDef::new(
      long="ssl",
      help="Enable SSL",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=None),
        opts=[
          OptDef::new(
            long="cert",
            help="Certificate",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result : Result[Unit, Error] = try? validate_opts(opts)
  inspect(result, content="Ok(())")
}
