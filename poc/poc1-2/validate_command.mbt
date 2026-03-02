///|
/// Validates a command definition tree for consistency.
///
/// Checks the command's own opts/global_opts, subcommand name uniqueness,
/// alias conflicts, and recursively validates all subcommands.
pub fn validate_command(cmd : CmdDef) -> Unit raise ParseError {
  validate_command_recursive(cmd, [])
}

///|
fn validate_command_recursive(
  cmd : CmdDef,
  inherited_globals : Array[OptDef],
) -> Unit raise ParseError {
  // 0a. global_opts に Group 禁止
  for opt in cmd.global_opts {
    match opt.kind {
      Group(..) =>
        raise DefinitionError(
          "global opt '--" + opt.long + "': Group option cannot be global",
        )
      _ => ()
    }
  }
  // 0b. subcommands + Group 排他
  if cmd.subcommands.length() > 0 {
    for opt in cmd.opts {
      match opt.kind {
        Group(..) =>
          raise DefinitionError(
            "opt '--" +
            opt.long +
            "': Group option cannot coexist with subcommands",
          )
        _ => ()
      }
    }
  }
  // 1. Validate opts + global_opts + inherited_globals
  let all_opts : Array[OptDef] = []
  for opt in cmd.opts {
    all_opts.push(opt)
  }
  for opt in cmd.global_opts {
    all_opts.push(opt)
  }
  for opt in inherited_globals {
    all_opts.push(opt)
  }
  validate_opts(all_opts)
  // 2-4. Validate subcommand names and aliases
  let subcmd_names : Map[String, Bool] = {}
  for subcmd in cmd.subcommands {
    // 4. Empty subcommand name
    if subcmd.name == "" {
      raise DefinitionError("empty subcommand name")
    }
    // 2. Duplicate subcommand name
    if subcmd_names.contains(subcmd.name) {
      raise DefinitionError("duplicate subcommand: " + subcmd.name)
    }
    subcmd_names[subcmd.name] = true
  }
  // 3. Alias conflicts (with names and other aliases)
  let alias_names : Map[String, Bool] = {}
  for subcmd in cmd.subcommands {
    for alias_entry in subcmd.aliases {
      if subcmd_names.contains(alias_entry.name) ||
        alias_names.contains(alias_entry.name) {
        raise DefinitionError("subcommand alias conflict: " + alias_entry.name)
      }
      alias_names[alias_entry.name] = true
    }
  }
  // 5. Recurse into subcommands with inherited globals
  let next_globals : Array[OptDef] = []
  for opt in cmd.global_opts {
    next_globals.push(opt)
  }
  for opt in inherited_globals {
    next_globals.push(opt)
  }
  for subcmd in cmd.subcommands {
    validate_command_recursive(subcmd, next_globals)
  }
}
