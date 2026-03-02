///| ブラックボックステスト — core パッケージの公開 API テスト

// ============================================================
// 1. Parser::new() と next_id() のテスト
// ============================================================

///|
test "Parser::new creates parser with seq 0" {
  let p = @core.Parser::new()
  inspect(p.seq, content="0")
}

///|
test "Parser::next_id increments and returns id" {
  let p = @core.Parser::new()
  let id1 = p.next_id()
  let id2 = p.next_id()
  let id3 = p.next_id()
  inspect(id1, content="1")
  inspect(id2, content="2")
  inspect(id3, content="3")
}

///|
test "Parser::next_id independent between parsers" {
  let p1 = @core.Parser::new()
  let p2 = @core.Parser::new()
  let a = p1.next_id()
  let b = p2.next_id()
  // 各 Parser は独立した seq を持つ
  inspect(a, content="1")
  inspect(b, content="1")
}

// ============================================================
// 2. InitialValue::get のテスト
// ============================================================

///|
test "InitialValue::get with Val" {
  let iv : @core.InitialValue[Int] = Val(42)
  inspect(iv.get(), content="42")
}

///|
test "InitialValue::get with Thunk" {
  let iv : @core.InitialValue[String] = Thunk(fn() { "hello" })
  inspect(iv.get(), content="hello")
}

///|
test "InitialValue::get Thunk is called each time" {
  let counter : Ref[Int] = { val: 0 }
  let iv : @core.InitialValue[Int] = Thunk(fn() {
    counter.val = counter.val + 1
    counter.val
  })
  inspect(iv.get(), content="1")
  inspect(iv.get(), content="2")
  inspect(iv.get(), content="3")
}

// ============================================================
// 3. Opt[T] の Hash/Eq テスト（id ベース）
// ============================================================

///|
test "Opt Hash/Eq is id-based" {
  let meta = make_test_meta("test")
  let opt1 : @core.Opt[Int] = {
    id: 1,
    initial: Val(0),
    reducer: fn(ctx) { Some(ctx.current) },
    meta,
    getter: fn(_) { 0 },
  }
  let opt2 : @core.Opt[Int] = {
    id: 1,
    initial: Val(99),
    reducer: fn(ctx) { Some(ctx.current) },
    meta,
    getter: fn(_) { 99 },
  }
  let opt3 : @core.Opt[Int] = {
    id: 2,
    initial: Val(0),
    reducer: fn(ctx) { Some(ctx.current) },
    meta,
    getter: fn(_) { 0 },
  }
  // 同じ id なら等しい（他のフィールドが違っても）
  assert_true(opt1 == opt2)
  // 違う id なら等しくない
  assert_true(opt1 != opt3)
}

///|
test "Opt can be used as Map key" {
  let meta = make_test_meta("test")
  let opt1 : @core.Opt[Int] = {
    id: 10,
    initial: Val(0),
    reducer: fn(ctx) { Some(ctx.current) },
    meta,
    getter: fn(_) { 0 },
  }
  let opt2 : @core.Opt[Int] = {
    id: 20,
    initial: Val(0),
    reducer: fn(ctx) { Some(ctx.current) },
    meta,
    getter: fn(_) { 0 },
  }
  let m : Map[@core.Opt[Int], String] = Map::new()
  m.set(opt1, "first")
  m.set(opt2, "second")
  inspect(m.get(opt1), content="Some(\"first\")")
  inspect(m.get(opt2), content="Some(\"second\")")
}

// ============================================================
// 4. OptMeta の生成テスト
// ============================================================

///|
test "OptMeta creation" {
  let meta = make_test_meta("verbose")
  inspect(meta.name, content="verbose")
  inspect(meta.kind, content="Option")
  inspect(meta.required, content="false")
  inspect(meta.global, content="false")
  inspect(meta.greedy, content="false")
  inspect(meta.visibility, content="Visible")
}

///|
test "OptMeta with shorts and aliases" {
  let meta : @core.OptMeta = {
    name: "output",
    kind: Option,
    help: "Output file",
    shorts: [{ char: 'o' }],
    aliases: [
      { name: "out", deprecated: false },
      { name: "dest", deprecated: true },
    ],
    inversion: None,
    env: Some("OUTPUT_FILE"),
    auto_env: None,
    choices: [],
    value_name: "FILE",
    required: true,
    visibility: Visible,
    global: false,
    greedy: false,
  }
  inspect(meta.shorts.length(), content="1")
  inspect(meta.shorts[0].char, content="o")
  inspect(meta.aliases.length(), content="2")
  inspect(meta.aliases[1].deprecated, content="true")
  inspect(meta.env, content="Some(\"OUTPUT_FILE\")")
  inspect(meta.value_name, content="FILE")
  inspect(meta.required, content="true")
}

// ============================================================
// 5. ReduceAction の Eq テスト
// ============================================================

///|
test "ReduceAction Eq - Value variants" {
  let a1 : @core.ReduceAction = Value(Some("hello"))
  let a2 : @core.ReduceAction = Value(Some("hello"))
  let a3 : @core.ReduceAction = Value(Some("world"))
  let a4 : @core.ReduceAction = Value(None)
  assert_true(a1 == a2)
  assert_true(a1 != a3)
  assert_true(a1 != a4)
}

///|
test "ReduceAction Eq - Negate" {
  let n1 : @core.ReduceAction = Negate
  let n2 : @core.ReduceAction = Negate
  let v1 : @core.ReduceAction = Value(None)
  assert_true(n1 == n2)
  assert_true(n1 != v1)
}

// ============================================================
// 補助関数
// ============================================================

///|
fn make_test_meta(name : String) -> @core.OptMeta {
  {
    name,
    kind: Option,
    help: "",
    shorts: [],
    aliases: [],
    inversion: None,
    env: None,
    auto_env: None,
    choices: [],
    value_name: "VALUE",
    required: false,
    visibility: Visible,
    global: false,
    greedy: false,
  }
}
