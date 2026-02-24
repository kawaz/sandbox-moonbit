///|
test "validate_command: valid command with subcommands passes" {
  let cmd = CmdDef::new(
    name="app",
    opts=[
      OptDef::new(
        long="output",
        help="Output file",
        kind=OptKind::Single(default=None),
      ),
    ],
    global_opts=[
      OptDef::new(
        long="verbose",
        help="Verbose output",
        kind=OptKind::Flag(default=false),
      ),
    ],
    subcommands=[
      CmdDef::new(
        name="build",
        opts=[
          OptDef::new(
            long="target",
            help="Build target",
            kind=OptKind::Single(default=None),
          ),
        ],
        aliases=[AliasEntry::new(name="b")],
      ),
      CmdDef::new(
        name="test",
        opts=[
          OptDef::new(
            long="filter",
            help="Test filter",
            kind=OptKind::Single(default=None),
          ),
        ],
        aliases=[AliasEntry::new(name="t")],
      ),
    ],
  )
  let result : Result[Unit, Error] = try? validate_command(cmd)
  inspect(result, content="Ok(())")
}

///|
test "validate_command: duplicate subcommand name" {
  let cmd = CmdDef::new(name="app", subcommands=[
    CmdDef::new(name="build"),
    CmdDef::new(name="build"),
  ])
  let result : Result[Unit, Error] = try? validate_command(cmd)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("duplicate subcommand: build"))
    ),
  )
}

///|
test "validate_command: subcommand alias conflicts with another subcommand name" {
  let cmd = CmdDef::new(name="app", subcommands=[
    CmdDef::new(name="build", aliases=[AliasEntry::new(name="b")]),
    CmdDef::new(name="b"),
  ])
  let result : Result[Unit, Error] = try? validate_command(cmd)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("subcommand alias conflict: b"))
    ),
  )
}

///|
test "validate_command: subcommand alias conflicts with another alias" {
  let cmd = CmdDef::new(name="app", subcommands=[
    CmdDef::new(name="build", aliases=[AliasEntry::new(name="x")]),
    CmdDef::new(name="test", aliases=[AliasEntry::new(name="x")]),
  ])
  let result : Result[Unit, Error] = try? validate_command(cmd)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("subcommand alias conflict: x"))
    ),
  )
}

///|
test "validate_command: empty subcommand name" {
  let cmd = CmdDef::new(name="app", subcommands=[CmdDef::new(name="")])
  let result : Result[Unit, Error] = try? validate_command(cmd)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("empty subcommand name"))
    ),
  )
}

///|
test "validate_command: child opts conflict with parent global_opts" {
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
      CmdDef::new(name="build", opts=[
        OptDef::new(
          long="verbose",
          help="Build verbose",
          kind=OptKind::Flag(default=false),
        ),
      ]),
    ],
  )
  let result : Result[Unit, Error] = try? validate_command(cmd)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("duplicate long: verbose"))
    ),
  )
}

///|
test "validate_command: grandchild validation (recursive)" {
  let cmd = CmdDef::new(name="app", subcommands=[
    CmdDef::new(name="remote", subcommands=[
      CmdDef::new(name="add"),
      CmdDef::new(name="add"),
    ]),
  ])
  let result : Result[Unit, Error] = try? validate_command(cmd)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("duplicate subcommand: add"))
    ),
  )
}

///|
test "validate_command: global_opts conflict between parent levels" {
  let cmd = CmdDef::new(
    name="app",
    global_opts=[
      OptDef::new(
        long="debug",
        help="Debug mode",
        kind=OptKind::Flag(default=false),
      ),
    ],
    subcommands=[
      CmdDef::new(name="sub", global_opts=[
        OptDef::new(
          long="debug",
          help="Sub debug",
          kind=OptKind::Flag(default=false),
        ),
      ]),
    ],
  )
  let result : Result[Unit, Error] = try? validate_command(cmd)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("duplicate long: debug"))
    ),
  )
}

///|
test "validate_command: duplicate long in opts" {
  // 同じコマンドの opts 内で long 名が重複
  let cmd = CmdDef::new(name="app", opts=[
    OptDef::new(
      long="output",
      help="Output 1",
      kind=OptKind::Single(default=None),
    ),
    OptDef::new(
      long="output",
      help="Output 2",
      kind=OptKind::Single(default=None),
    ),
  ])
  let result : Result[Unit, Error] = try? validate_command(cmd)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("duplicate long: output"))
    ),
  )
}

///|
test "validate_command: alias reverse collision (name shadows later alias)" {
  // "b" が先に名前として登録され、別 opt の alias "b" と衝突
  let cmd = CmdDef::new(name="app", opts=[
    OptDef::new(long="b", help="Option b", kind=OptKind::Flag(default=false)),
    OptDef::new(
      long="build",
      help="Build option",
      kind=OptKind::Flag(default=false),
      aliases=[AliasEntry::new(name="b")],
    ),
  ])
  let result : Result[Unit, Error] = try? validate_command(cmd)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("alias conflict: b"))
    ),
  )
}

///|
test "validate_command: opts and global_opts duplicate" {
  // opts と global_opts の間で long 名が重複
  let cmd = CmdDef::new(
    name="app",
    opts=[
      OptDef::new(
        long="format",
        help="Format (local)",
        kind=OptKind::Single(default=None),
      ),
    ],
    global_opts=[
      OptDef::new(
        long="format",
        help="Format (global)",
        kind=OptKind::Single(default=None),
      ),
    ],
  )
  let result : Result[Unit, Error] = try? validate_command(cmd)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("duplicate long: format"))
    ),
  )
}

// === Group + command バリデーション ===

///|
test "validate_command: global_opts with Group raises DefinitionError" {
  let cmd = CmdDef::new(name="app", global_opts=[
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
    ),
  ])
  let result : Result[Unit, Error] = try? validate_command(cmd)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("global opt '--ssl': Group option cannot be global"))
    ),
  )
}

///|
test "validate_command: subcommands with Group raises DefinitionError" {
  let cmd = CmdDef::new(
    name="app",
    opts=[
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
      ),
    ],
    subcommands=[CmdDef::new(name="build")],
  )
  let result : Result[Unit, Error] = try? validate_command(cmd)
  inspect(
    result,
    content=(
      #|Err(DefinitionError("opt '--ssl': Group option cannot coexist with subcommands"))
    ),
  )
}

///|
test "validate_command: no subcommands with Group passes" {
  let cmd = CmdDef::new(name="app", opts=[
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
    ),
  ])
  let result : Result[Unit, Error] = try? validate_command(cmd)
  inspect(result, content="Ok(())")
}

///|
test "validate_command: global_opts with non-Group passes" {
  let cmd = CmdDef::new(
    name="app",
    global_opts=[
      OptDef::new(
        long="verbose",
        help="Verbose",
        kind=OptKind::Flag(default=false),
      ),
    ],
    subcommands=[CmdDef::new(name="build")],
  )
  let result : Result[Unit, Error] = try? validate_command(cmd)
  inspect(result, content="Ok(())")
}
