///|
/// Validates an array of option definitions for consistency.
///
/// Checks for:
/// 1. Empty long names
/// 2. Duplicate long names
/// 3. Duplicate short characters
/// 4. Alias conflicts with long names or other aliases
/// 5. Inversion name conflicts (no-xxx, enable-xxx/disable-xxx, with-xxx/without-xxx)
/// 6. Default value not in choices
pub fn validate_opts(opts : Array[OptDef]) -> Unit raise ParseError {
  // Pre-loop check: duplicate WithValue(default=Some) Group prohibition
  let mut first_with_value_default : String? = None
  for opt in opts {
    match opt.kind {
      Group(group_kind=WithValue(default=Some(_)), ..) =>
        match first_with_value_default {
          Some(first_long) =>
            raise DefinitionError(
              "opt '--" +
              opt.long +
              "': duplicate WithValue(default=Some) Group (conflicts with '--" +
              first_long +
              "')",
            )
          None => first_with_value_default = Some(opt.long)
        }
      _ => ()
    }
  }
  let long_names : Map[String, Bool] = {}
  let short_chars : Map[Char, Bool] = {}
  // all_names tracks the source of each registered name for conflict reporting
  // Values: "long", "alias", "inversion"
  let all_names : Map[String, String] = {}
  for opt in opts {
    // 1. Empty long name
    if opt.long == "" {
      raise DefinitionError("empty long name")
    }
    // 1.5. Long name character validation
    fn validate_long_name(
      name : String,
      label : String,
    ) -> Unit raise ParseError {
      // 先頭・末尾ハイフンチェック
      if name.has_prefix("-") || name.has_suffix("-") {
        raise DefinitionError(label + " starts or ends with hyphen: " + name)
      }
      for i in 0..<name.length() {
        let c = match name.get_char(i) {
          // Design rationale: name.length() は UTF-16 コード単位数、get_char はキャラクタインデックス。
          // マルチバイト文字を含む名前では不一致が起きるため None でループを終了する。
          // この時点で既にASCII以外の文字を含むことが確定するため、エラーを raise する。
          None =>
            raise DefinitionError(
              label + " contains invalid character: " + name,
            )
          Some(c) => c
        }
        if not(c >= 'a' && c <= 'z') && not(c >= '0' && c <= '9') && c != '-' {
          raise DefinitionError(label + " contains invalid character: " + name)
        }
      }
    }

    validate_long_name(opt.long, "long name")
    // 2. Duplicate long name
    if long_names.contains(opt.long) {
      raise DefinitionError("duplicate long: " + opt.long)
    }
    long_names[opt.long] = true
    // Check all_names for conflicts with aliases or inversion names
    match all_names.get(opt.long) {
      Some("inversion") =>
        raise DefinitionError("inversion conflict: " + opt.long)
      Some("alias") => raise DefinitionError("alias conflict: " + opt.long)
      Some(_) => raise DefinitionError("duplicate long: " + opt.long)
      None => ()
    }
    all_names[opt.long] = "long"
    // 3. Short character validation and duplicate check
    for short_entry in opt.shorts {
      let c = short_entry.char
      if not(c >= 'a' && c <= 'z') &&
        not(c >= 'A' && c <= 'Z') &&
        not(c >= '0' && c <= '9') {
        raise DefinitionError("invalid short option: " + c.to_string())
      }
      if short_chars.contains(c) {
        raise DefinitionError("duplicate short: " + c.to_string())
      }
      short_chars[c] = true
    }
    // 4. Alias conflicts
    for alias_entry in opt.aliases {
      validate_long_name(alias_entry.name, "alias name")
      if all_names.contains(alias_entry.name) {
        raise DefinitionError("alias conflict: " + alias_entry.name)
      }
      all_names[alias_entry.name] = "alias"
    }
    // 5. Inversion name conflicts
    fn check_inversion(
      all_names : Map[String, String],
      name : String,
    ) -> Unit raise ParseError {
      if all_names.contains(name) {
        raise DefinitionError("inversion conflict: " + name)
      }
      all_names[name] = "inversion"
    }

    match opt.inversion {
      Some(PrefixNo) => check_inversion(all_names, "no-" + opt.long)
      Some(PrefixEnableDisable) => {
        check_inversion(all_names, "enable-" + opt.long)
        check_inversion(all_names, "disable-" + opt.long)
      }
      Some(PrefixWithWithout) => {
        check_inversion(all_names, "with-" + opt.long)
        check_inversion(all_names, "without-" + opt.long)
      }
      None => ()
    }
    // 6. OptionalValue + short は禁止
    match opt.kind {
      OptionalValue(..) =>
        if opt.shorts.length() > 0 {
          raise DefinitionError(
            "OptionalValue cannot have short options: --" + opt.long,
          )
        }
      _ => ()
    }
    // 7. Count + choices は禁止
    match opt.kind {
      Count(_) =>
        if opt.choices.length() > 0 {
          raise DefinitionError("Count cannot have choices: --" + opt.long)
        }
      _ => ()
    }
    // 8. Append: n >= 1 and defaults.length() % n == 0
    match opt.kind {
      Append(n~, defaults~) => {
        if n < 1 {
          raise DefinitionError("n must be >= 1 for --" + opt.long)
        }
        if defaults.length() % n != 0 {
          raise DefinitionError(
            "defaults length must be divisible by n for --" + opt.long,
          )
        }
      }
      _ => ()
    }
    // 9. Choices validation: check default is in choices
    if opt.choices.length() > 0 {
      match opt.kind {
        Single(default=Some(default_val)) =>
          if not(opt.choices.contains(default_val)) {
            raise DefinitionError(
              "default value \"" +
              default_val +
              "\" not in choices for --" +
              opt.long,
            )
          }
        Append(defaults~, ..) =>
          for default_val in defaults {
            if not(opt.choices.contains(default_val)) {
              raise DefinitionError(
                "default value \"" +
                default_val +
                "\" not in choices for --" +
                opt.long,
              )
            }
          }
        OptionalValue(default~, implicit~, negated~) => {
          fn check_choice(
            val : String,
            label : String,
            opt_long : String,
            choices : Array[String],
          ) -> Unit raise ParseError {
            if not(choices.contains(val)) {
              raise DefinitionError(
                label +
                " value \"" +
                val +
                "\" not in choices for --" +
                opt_long,
              )
            }
          }

          // implicit must be in choices
          check_choice(implicit, "implicit", opt.long, opt.choices)
          // negated must be in choices (if set)
          match negated {
            Some(v) => check_choice(v, "negated", opt.long, opt.choices)
            None => ()
          }
          // default must be in choices (if set)
          match default {
            Some(v) => check_choice(v, "default", opt.long, opt.choices)
            None => ()
          }
        }
        _ => ()
      }
    }
    // 10. Group validation
    match opt.kind {
      Group(group_kind~, opts=inner_opts, ..) => {
        // 10a. Valueless Group + env 禁止
        match group_kind {
          Valueless => {
            match opt.env {
              Some(_) =>
                raise DefinitionError(
                  "opt '--" + opt.long + "': Valueless Group cannot have env",
                )
              None => ()
            }
            // 10b. Valueless Group + choices 禁止
            if opt.choices.length() > 0 {
              raise DefinitionError(
                "opt '--" + opt.long + "': Valueless Group cannot have choices",
              )
            }
            // 10c. Valueless Group + value_name 禁止
            if opt.value_name != "VALUE" {
              raise DefinitionError(
                "opt '--" +
                opt.long +
                "': Valueless Group cannot have value_name",
              )
            }
          }
          _ => ()
        }
        // 10d. Group 内に help/version 名禁止
        for inner_opt in inner_opts {
          if inner_opt.long == "help" {
            raise DefinitionError(
              "opt '--" + opt.long + "': Group cannot contain 'help' option",
            )
          }
          if inner_opt.long == "version" {
            raise DefinitionError(
              "opt '--" + opt.long + "': Group cannot contain 'version' option",
            )
          }
        }
        // 10e. Group 内 opts の再帰バリデーション
        validate_opts(inner_opts)
      }
      _ => ()
    }
  }
}
