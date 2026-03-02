///| ブラックボックステスト — parse パッケージの公開 API テスト

// ============================================================
// 1. flag 基本: ["--verbose"] -> verbose=true
// ============================================================

///|
test "parse: flag basic" {
  let parser = @core.Parser::new()
  let (verbose_opt, verbose_node) = @combinators.flag(parser, name="verbose")
  let root = @combinators.opts([@core.Opts::Node(verbose_node)])
  @parse.parse(["--verbose"], root)
  inspect((verbose_opt.getter)(0), content="true")
}

// ============================================================
// 2. flag 未指定: [] -> verbose=false (initial)
// ============================================================

///|
test "parse: flag not specified" {
  let parser = @core.Parser::new()
  let (verbose_opt, verbose_node) = @combinators.flag(parser, name="verbose")
  let root = @combinators.opts([@core.Opts::Node(verbose_node)])
  @parse.parse([], root)
  inspect((verbose_opt.getter)(0), content="false")
}

// ============================================================
// 3. string_opt 基本: ["--name", "hello"] -> name=Some("hello")
// ============================================================

///|
test "parse: string_opt basic" {
  let parser = @core.Parser::new()
  let (name_opt, name_node) = @combinators.string_opt(parser, name="name")
  let root = @combinators.opts([@core.Opts::Node(name_node)])
  @parse.parse(["--name", "hello"], root)
  inspect((name_opt.getter)(0), content="Some(\"hello\")")
}

// ============================================================
// 4. string_opt with =: ["--name=hello"] -> name=Some("hello")
// ============================================================

///|
test "parse: string_opt with equals" {
  let parser = @core.Parser::new()
  let (name_opt, name_node) = @combinators.string_opt(parser, name="name")
  let root = @combinators.opts([@core.Opts::Node(name_node)])
  @parse.parse(["--name=hello"], root)
  inspect((name_opt.getter)(0), content="Some(\"hello\")")
}

// ============================================================
// 5. int_opt 基本: ["--port", "8080"] -> port=Some(8080)
// ============================================================

///|
test "parse: int_opt basic" {
  let parser = @core.Parser::new()
  let (port_opt, port_node) = @combinators.int_opt(parser, name="port")
  let root = @combinators.opts([@core.Opts::Node(port_node)])
  @parse.parse(["--port", "8080"], root)
  inspect((port_opt.getter)(0), content="Some(8080)")
}

// ============================================================
// 6. int_opt 不正値: ["--port", "abc"] -> ParseError::InvalidValue
// ============================================================

///|
test "parse: int_opt invalid value" {
  let parser = @core.Parser::new()
  let (_port_opt, port_node) = @combinators.int_opt(parser, name="port")
  let root = @combinators.opts([@core.Opts::Node(port_node)])
  let result : Result[Unit, @core.ParseError] = Ok(
    @parse.parse(["--port", "abc"], root),
  ) catch {
    e => Err(e)
  }
  inspect(
    result,
    content="Err(InvalidValue(name=\"port\", value=\"abc\", reason=\"not a valid integer\"))",
  )
}

// ============================================================
// 7. positional 基本: ["file.txt"] -> pos=Some("file.txt")
// ============================================================

///|
test "parse: positional basic" {
  let parser = @core.Parser::new()
  let (pos_opt, pos_node) = @combinators.positional(parser, name="file")
  let root = @combinators.opts([@core.Opts::Node(pos_node)])
  @parse.parse(["file.txt"], root)
  inspect((pos_opt.getter)(0), content="Some(\"file.txt\")")
}

// ============================================================
// 8. 複合: ["--verbose", "--port", "8080", "file.txt"]
// ============================================================

///|
test "parse: combined options and positional" {
  let parser = @core.Parser::new()
  let (verbose_opt, verbose_node) = @combinators.flag(parser, name="verbose")
  let (port_opt, port_node) = @combinators.int_opt(parser, name="port")
  let (pos_opt, pos_node) = @combinators.positional(parser, name="file")
  let root = @combinators.opts([
    @core.Opts::Node(verbose_node),
    @core.Opts::Node(port_node),
    @core.Opts::Node(pos_node),
  ])
  @parse.parse(["--verbose", "--port", "8080", "file.txt"], root)
  inspect((verbose_opt.getter)(0), content="true")
  inspect((port_opt.getter)(0), content="Some(8080)")
  inspect((pos_opt.getter)(0), content="Some(\"file.txt\")")
}

// ============================================================
// 9. -- セパレータ: ["--", "--verbose"] -> verbose=false, pos=Some("--verbose")
// ============================================================

///|
test "parse: double dash separator" {
  let parser = @core.Parser::new()
  let (verbose_opt, verbose_node) = @combinators.flag(parser, name="verbose")
  let (pos_opt, pos_node) = @combinators.positional(parser, name="file")
  let root = @combinators.opts([
    @core.Opts::Node(verbose_node),
    @core.Opts::Node(pos_node),
  ])
  @parse.parse(["--", "--verbose"], root)
  inspect((verbose_opt.getter)(0), content="false")
  inspect((pos_opt.getter)(0), content="Some(\"--verbose\")")
}

// ============================================================
// 10. 未知オプション: ["--unknown"] -> ParseError::UnknownOption
// ============================================================

///|
test "parse: unknown option" {
  let parser = @core.Parser::new()
  let (_verbose_opt, verbose_node) = @combinators.flag(parser, name="verbose")
  let root = @combinators.opts([@core.Opts::Node(verbose_node)])
  let result : Result[Unit, @core.ParseError] = Ok(
    @parse.parse(["--unknown"], root),
  ) catch {
    e => Err(e)
  }
  inspect(result, content="Err(UnknownOption(\"--unknown\"))")
}

// ============================================================
// 11. 値不足: ["--port"] -> ParseError::MissingValue
// ============================================================

///|
test "parse: missing value" {
  let parser = @core.Parser::new()
  let (_port_opt, port_node) = @combinators.int_opt(parser, name="port")
  let root = @combinators.opts([@core.Opts::Node(port_node)])
  let result : Result[Unit, @core.ParseError] = Ok(
    @parse.parse(["--port"], root),
  ) catch {
    e => Err(e)
  }
  inspect(result, content="Err(MissingValue(\"port\"))")
}
