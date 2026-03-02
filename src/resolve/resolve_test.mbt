///|
/// テスト用ヘルパー: テスト用 ErasedNode を簡易作成
fn make_test_node(
  name~ : String,
  kind? : @core.Kind = Option,
  shorts? : Array[@core.ShortEntry] = [],
  aliases? : Array[@core.AliasEntry] = [],
  inversion? : @core.FlagInversion? = None,
) -> @core.ErasedNode {
  let meta : @core.OptMeta = {
    name,
    kind,
    help: "",
    shorts,
    aliases,
    inversion,
    env: None,
    auto_env: None,
    choices: [],
    value_name: "",
    required: false,
    visibility: Visible,
    global: false,
    greedy: false,
  }
  {
    meta,
    arity: 0,
    try_reduce: fn(_action, _seq) { None },
    commit_reduce: fn(_result) {  },
    reset_to_initial: fn(_seq) {  },
    children: fn() { [] },
  }
}

///|
test "resolve: long option exact match" {
  let nodes = [make_test_node(name="port")]
  let result = @resolve.resolve("--port", nodes)
  inspect(
    result,
    content="Resolved(ErasedNode::{meta: {name: \"port\", kind: Option, help: \"\", shorts: [], aliases: [], inversion: None, env: None, auto_env: None, choices: [], value_name: \"\", required: false, visibility: Visible, global: false, greedy: false}, arity: 0}, Value(None))",
  )
}

///|
test "resolve: long option with value" {
  let nodes = [make_test_node(name="port")]
  let result = @resolve.resolve("--port=8080", nodes)
  inspect(
    result,
    content="Resolved(ErasedNode::{meta: {name: \"port\", kind: Option, help: \"\", shorts: [], aliases: [], inversion: None, env: None, auto_env: None, choices: [], value_name: \"\", required: false, visibility: Visible, global: false, greedy: false}, arity: 0}, Value(Some(\"8080\")))",
  )
}

///|
test "resolve: short option" {
  let nodes = [make_test_node(name="port", shorts=[{ char: 'p' }])]
  let result = @resolve.resolve("-p", nodes)
  inspect(
    result,
    content="Resolved(ErasedNode::{meta: {name: \"port\", kind: Option, help: \"\", shorts: [{char: 'p'}], aliases: [], inversion: None, env: None, auto_env: None, choices: [], value_name: \"\", required: false, visibility: Visible, global: false, greedy: false}, arity: 0}, Value(None))",
  )
}

///|
test "resolve: alias match" {
  let nodes = [
    make_test_node(name="output", aliases=[{ name: "out", deprecated: false }]),
  ]
  let result = @resolve.resolve("--out", nodes)
  inspect(
    result,
    content="Resolved(ErasedNode::{meta: {name: \"output\", kind: Option, help: \"\", shorts: [], aliases: [{name: \"out\", deprecated: false}], inversion: None, env: None, auto_env: None, choices: [], value_name: \"\", required: false, visibility: Visible, global: false, greedy: false}, arity: 0}, Value(None))",
  )
}

///|
test "resolve: inversion No pattern" {
  let nodes = [make_test_node(name="verbose", inversion=Some(No))]
  let result = @resolve.resolve("--no-verbose", nodes)
  inspect(
    result,
    content="Resolved(ErasedNode::{meta: {name: \"verbose\", kind: Option, help: \"\", shorts: [], aliases: [], inversion: Some(No), env: None, auto_env: None, choices: [], value_name: \"\", required: false, visibility: Visible, global: false, greedy: false}, arity: 0}, Negate)",
  )
}

///|
test "resolve: inversion EnableDisable enable" {
  let nodes = [make_test_node(name="color", inversion=Some(EnableDisable))]
  let result = @resolve.resolve("--enable-color", nodes)
  inspect(
    result,
    content="Resolved(ErasedNode::{meta: {name: \"color\", kind: Option, help: \"\", shorts: [], aliases: [], inversion: Some(EnableDisable), env: None, auto_env: None, choices: [], value_name: \"\", required: false, visibility: Visible, global: false, greedy: false}, arity: 0}, Value(None))",
  )
}

///|
test "resolve: inversion EnableDisable disable" {
  let nodes = [make_test_node(name="color", inversion=Some(EnableDisable))]
  let result = @resolve.resolve("--disable-color", nodes)
  inspect(
    result,
    content="Resolved(ErasedNode::{meta: {name: \"color\", kind: Option, help: \"\", shorts: [], aliases: [], inversion: Some(EnableDisable), env: None, auto_env: None, choices: [], value_name: \"\", required: false, visibility: Visible, global: false, greedy: false}, arity: 0}, Negate)",
  )
}

///|
test "resolve: prefix match unique" {
  let nodes = [make_test_node(name="port"), make_test_node(name="verbose")]
  let result = @resolve.resolve("--por", nodes)
  inspect(
    result,
    content="Resolved(ErasedNode::{meta: {name: \"port\", kind: Option, help: \"\", shorts: [], aliases: [], inversion: None, env: None, auto_env: None, choices: [], value_name: \"\", required: false, visibility: Visible, global: false, greedy: false}, arity: 0}, Value(None))",
  )
}

///|
test "resolve: prefix match ambiguous" {
  let nodes = [make_test_node(name="port"), make_test_node(name="poll")]
  let result : String = try {
    let _ = @resolve.resolve("--po", nodes)
    "no error"
  } catch {
    @core.ParseError::AmbiguousOption(input~, candidates~) =>
      "AmbiguousOption(input=" +
      input +
      ", candidates=" +
      candidates.to_string() +
      ")"
    e => "unexpected: " + e.to_string()
  }
  inspect(
    result,
    content="AmbiguousOption(input=po, candidates=[\"port\", \"poll\"])",
  )
}

///|
test "resolve: command match" {
  let nodes = [make_test_node(name="serve", kind=Command)]
  let result = @resolve.resolve("serve", nodes)
  inspect(
    result,
    content="Resolved(ErasedNode::{meta: {name: \"serve\", kind: Command, help: \"\", shorts: [], aliases: [], inversion: None, env: None, auto_env: None, choices: [], value_name: \"\", required: false, visibility: Visible, global: false, greedy: false}, arity: 0}, Value(None))",
  )
}

///|
test "resolve: unresolved" {
  let nodes = [make_test_node(name="port")]
  let result = @resolve.resolve("--unknown", nodes)
  inspect(result, content="Unresolved")
}

///|
test "resolve: bare double dash" {
  let nodes = [make_test_node(name="port")]
  let result = @resolve.resolve("--", nodes)
  inspect(result, content="Unresolved")
}

///|
test "resolve: inversion Custom pattern" {
  let nodes = [
    make_test_node(name="foo", inversion=Some(Custom("with", "without"))),
  ]
  let result_with = @resolve.resolve("--with-foo", nodes)
  inspect(
    result_with,
    content="Resolved(ErasedNode::{meta: {name: \"foo\", kind: Option, help: \"\", shorts: [], aliases: [], inversion: Some(Custom(\"with\", \"without\")), env: None, auto_env: None, choices: [], value_name: \"\", required: false, visibility: Visible, global: false, greedy: false}, arity: 0}, Value(None))",
  )
  let result_without = @resolve.resolve("--without-foo", nodes)
  inspect(
    result_without,
    content="Resolved(ErasedNode::{meta: {name: \"foo\", kind: Option, help: \"\", shorts: [], aliases: [], inversion: Some(Custom(\"with\", \"without\")), env: None, auto_env: None, choices: [], value_name: \"\", required: false, visibility: Visible, global: false, greedy: false}, arity: 0}, Negate)",
  )
}

///|
test "resolve: deprecated alias also resolves" {
  let nodes = [
    make_test_node(name="output", aliases=[{ name: "out", deprecated: true }]),
  ]
  let result = @resolve.resolve("--out", nodes)
  inspect(
    result,
    content="Resolved(ErasedNode::{meta: {name: \"output\", kind: Option, help: \"\", shorts: [], aliases: [{name: \"out\", deprecated: true}], inversion: None, env: None, auto_env: None, choices: [], value_name: \"\", required: false, visibility: Visible, global: false, greedy: false}, arity: 0}, Value(None))",
  )
}
