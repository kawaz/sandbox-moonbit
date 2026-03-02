///| ブラックボックステスト — combinators パッケージの公開 API テスト

// ============================================================
// 1. flag の生成テスト
// ============================================================

///|
test "flag: meta has kind=Option, arity=0" {
  let parser = @core.Parser::new()
  let (_opt, erased) = @combinators.flag(parser, name="verbose")
  inspect(erased.meta.kind, content="Option")
  inspect(erased.arity, content="0")
  inspect(erased.meta.name, content="verbose")
  inspect(erased.meta.required, content="false")
  inspect(erased.meta.greedy, content="false")
  inspect(erased.meta.value_name, content="")
}

// ============================================================
// 2. string_opt の生成テスト
// ============================================================

///|
test "string_opt: meta has kind=Option, arity=1" {
  let parser = @core.Parser::new()
  let (_opt, erased) = @combinators.string_opt(parser, name="output")
  inspect(erased.meta.kind, content="Option")
  inspect(erased.arity, content="1")
  inspect(erased.meta.name, content="output")
  inspect(erased.meta.value_name, content="VALUE")
}

///|
test "string_opt: custom value_name and choices" {
  let parser = @core.Parser::new()
  let (_opt, erased) = @combinators.string_opt(
    parser,
    name="format",
    value_name="FMT",
    choices=["json", "yaml", "toml"],
  )
  inspect(erased.meta.value_name, content="FMT")
  inspect(erased.meta.choices.length(), content="3")
}

// ============================================================
// 3. int_opt の生成テスト
// ============================================================

///|
test "int_opt: meta has kind=Option, arity=1" {
  let parser = @core.Parser::new()
  let (_opt, erased) = @combinators.int_opt(parser, name="count")
  inspect(erased.meta.kind, content="Option")
  inspect(erased.arity, content="1")
  inspect(erased.meta.name, content="count")
  inspect(erased.meta.value_name, content="INT")
}

// ============================================================
// 4. positional の生成テスト
// ============================================================

///|
test "positional: meta has kind=Positional" {
  let parser = @core.Parser::new()
  let (_opt, erased) = @combinators.positional(parser, name="file")
  inspect(erased.meta.kind, content="Positional")
  inspect(erased.arity, content="1")
  inspect(erased.meta.name, content="file")
  inspect(erased.meta.value_name, content="file")
  inspect(erased.meta.global, content="false")
}

// ============================================================
// 5. flag の reducer テスト — Value(None) -> true, Negate -> false
// ============================================================

///|
test "flag: reducer Value(None) -> true" {
  let parser = @core.Parser::new()
  let (opt, _erased) = @combinators.flag(parser, name="verbose")
  let ctx : @core.ReduceCtx[Bool] = { current: false, action: Value(None) }
  inspect((opt.reducer)(ctx), content="Some(true)")
}

///|
test "flag: reducer Negate -> false" {
  let parser = @core.Parser::new()
  let (opt, _erased) = @combinators.flag(parser, name="verbose")
  let ctx : @core.ReduceCtx[Bool] = { current: true, action: Negate }
  inspect((opt.reducer)(ctx), content="Some(false)")
}

///|
test "flag: reducer Value(Some(_)) -> None (no match)" {
  let parser = @core.Parser::new()
  let (opt, _erased) = @combinators.flag(parser, name="verbose")
  let ctx : @core.ReduceCtx[Bool] = {
    current: false,
    action: Value(Some("unexpected")),
  }
  inspect((opt.reducer)(ctx), content="None")
}

// ============================================================
// 6. string_opt の reducer テスト
// ============================================================

///|
test "string_opt: reducer Value(Some(s)) -> Some(s)" {
  let parser = @core.Parser::new()
  let (opt, _erased) = @combinators.string_opt(parser, name="output")
  let ctx : @core.ReduceCtx[String?] = {
    current: None,
    action: Value(Some("hello")),
  }
  inspect((opt.reducer)(ctx), content="Some(Some(\"hello\"))")
}

///|
test "string_opt: reducer Negate -> None" {
  let parser = @core.Parser::new()
  let (opt, _erased) = @combinators.string_opt(parser, name="output")
  let ctx : @core.ReduceCtx[String?] = { current: Some("old"), action: Negate }
  inspect((opt.reducer)(ctx), content="Some(None)")
}

///|
test "string_opt: reducer Value(None) -> None (no match)" {
  let parser = @core.Parser::new()
  let (opt, _erased) = @combinators.string_opt(parser, name="output")
  let ctx : @core.ReduceCtx[String?] = { current: None, action: Value(None) }
  inspect((opt.reducer)(ctx), content="None")
}

// ============================================================
// 7. int_opt の reducer テスト
// ============================================================

///|
test "int_opt: reducer Value(Some(\"42\")) -> Some(42)" {
  let parser = @core.Parser::new()
  let (opt, _erased) = @combinators.int_opt(parser, name="count")
  let ctx : @core.ReduceCtx[Int?] = { current: None, action: Value(Some("42")) }
  inspect((opt.reducer)(ctx), content="Some(Some(42))")
}

///|
test "int_opt: reducer Value(Some(\"abc\")) -> ParseError" {
  let parser = @core.Parser::new()
  let (opt, _erased) = @combinators.int_opt(parser, name="count")
  let ctx : @core.ReduceCtx[Int?] = {
    current: None,
    action: Value(Some("abc")),
  }
  let result : Result[Int??, @core.ParseError] = Ok((opt.reducer)(ctx)) catch {
    e => Err(e)
  }
  inspect(
    result,
    content="Err(InvalidValue(name=\"count\", value=\"abc\", reason=\"not a valid integer\"))",
  )
}

///|
test "int_opt: reducer Negate -> Some(None)" {
  let parser = @core.Parser::new()
  let (opt, _erased) = @combinators.int_opt(parser, name="count")
  let ctx : @core.ReduceCtx[Int?] = { current: Some(10), action: Negate }
  inspect((opt.reducer)(ctx), content="Some(None)")
}

///|
test "int_opt: reducer Value(None) -> None (no match)" {
  let parser = @core.Parser::new()
  let (opt, _erased) = @combinators.int_opt(parser, name="count")
  let ctx : @core.ReduceCtx[Int?] = { current: None, action: Value(None) }
  inspect((opt.reducer)(ctx), content="None")
}

///|
test "int_opt: reducer Value(Some(\"-7\")) -> Some(-7)" {
  let parser = @core.Parser::new()
  let (opt, _erased) = @combinators.int_opt(parser, name="count")
  let ctx : @core.ReduceCtx[Int?] = { current: None, action: Value(Some("-7")) }
  inspect((opt.reducer)(ctx), content="Some(Some(-7))")
}

// ============================================================
// 8. opts ヘルパーのテスト
// ============================================================

///|
test "opts: wraps Array[Opts] into Opts::Array" {
  let parser = @core.Parser::new()
  let (_opt1, erased1) = @combinators.flag(parser, name="verbose")
  let (_opt2, erased2) = @combinators.string_opt(parser, name="output")
  let result = @combinators.opts([
    @core.Opts::Node(erased1),
    @core.Opts::Node(erased2),
  ])
  match result {
    Array(arr) => inspect(arr.length(), content="2")
    _ => assert_true(false)
  }
}

///|
test "opts: empty array" {
  let result = @combinators.opts([])
  match result {
    Array(arr) => inspect(arr.length(), content="0")
    _ => assert_true(false)
  }
}

// ============================================================
// 9. try_reduce / commit_reduce の統合テスト
// ============================================================

///|
test "flag: try_reduce + commit_reduce updates getter value" {
  let parser = @core.Parser::new()
  let (opt, erased) = @combinators.flag(parser, name="verbose")
  // 初期値は false
  inspect((opt.getter)(0), content="false")
  // try_reduce で Value(None) を渡す → Some(ReduceResult)
  let result = (erased.try_reduce)(@core.ReduceAction::Value(None), 0)
  assert_true(result is Some(_))
  // まだ commit していないので getter は false
  inspect((opt.getter)(0), content="false")
  // commit する
  match result {
    Some(rr) => (erased.commit_reduce)(rr)
    None => ()
  }
  // commit 後は true
  inspect((opt.getter)(0), content="true")
}

///|
test "string_opt: try_reduce + commit_reduce updates getter value" {
  let parser = @core.Parser::new()
  let (opt, erased) = @combinators.string_opt(parser, name="output")
  // 初期値は None
  inspect((opt.getter)(0), content="None")
  // try_reduce で Value(Some("test.txt")) を渡す
  let result = (erased.try_reduce)(
    @core.ReduceAction::Value(Some("test.txt")),
    0,
  )
  assert_true(result is Some(_))
  match result {
    Some(rr) => (erased.commit_reduce)(rr)
    None => ()
  }
  inspect((opt.getter)(0), content="Some(\"test.txt\")")
}

///|
test "int_opt: try_reduce + commit_reduce updates getter value" {
  let parser = @core.Parser::new()
  let (opt, erased) = @combinators.int_opt(parser, name="count")
  inspect((opt.getter)(0), content="None")
  let result = (erased.try_reduce)(@core.ReduceAction::Value(Some("42")), 0)
  assert_true(result is Some(_))
  match result {
    Some(rr) => (erased.commit_reduce)(rr)
    None => ()
  }
  inspect((opt.getter)(0), content="Some(42)")
}

///|
test "flag: reset_to_initial restores initial value" {
  let parser = @core.Parser::new()
  let (opt, erased) = @combinators.flag(parser, name="verbose")
  // set to true
  let result = (erased.try_reduce)(@core.ReduceAction::Value(None), 0)
  match result {
    Some(rr) => (erased.commit_reduce)(rr)
    None => ()
  }
  inspect((opt.getter)(0), content="true")
  // reset
  (erased.reset_to_initial)(0)
  inspect((opt.getter)(0), content="false")
}

///|
test "flag: try_reduce returns None for Value(Some(_))" {
  let parser = @core.Parser::new()
  let (_opt, erased) = @combinators.flag(parser, name="verbose")
  let result = (erased.try_reduce)(
    @core.ReduceAction::Value(Some("unexpected")),
    0,
  )
  assert_true(result is None)
}

// ============================================================
// 10. Parser への refs 登録テスト
// ============================================================

///|
test "combinators register refs in parser" {
  let parser = @core.Parser::new()
  let _ = @combinators.flag(parser, name="verbose")
  let _ = @combinators.string_opt(parser, name="output")
  let _ = @combinators.int_opt(parser, name="count")
  let _ = @combinators.positional(parser, name="file")
  inspect(parser.refs.length(), content="4")
}

// ============================================================
// 11. ID の一意性テスト
// ============================================================

///|
test "each combinator gets unique id" {
  let parser = @core.Parser::new()
  let (opt1, _) = @combinators.flag(parser, name="a")
  let (opt2, _) = @combinators.string_opt(parser, name="b")
  let (opt3, _) = @combinators.int_opt(parser, name="c")
  let (opt4, _) = @combinators.positional(parser, name="d")
  assert_true(opt1.id != opt2.id)
  assert_true(opt2.id != opt3.id)
  assert_true(opt3.id != opt4.id)
}
