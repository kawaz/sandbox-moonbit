///| コンビネータ関数群
/// flag, string_opt, int_opt, positional 等のコンビネータを提供する
///
// Design rationale: MoonBit does not allow defining methods on foreign types,
// so these are standalone functions taking @core.Parser as the first argument
// instead of being Parser methods.

// ============================================================
// 1. flag (Bool)
// ============================================================

///|
pub fn flag(
  parser : @core.Parser,
  name~ : String,
  help? : String = "",
  shorts? : Array[@core.ShortEntry] = [],
  aliases? : Array[@core.AliasEntry] = [],
  inversion? : @core.FlagInversion? = None,
  env? : String? = None,
  auto_env? : Bool? = None,
  visibility? : @core.Visibility = Visible,
  global? : Bool = false,
) -> (@core.Opt[Bool], @core.ErasedNode) {
  let id = parser.next_id()
  let initial : @core.InitialValue[Bool] = Val(false)
  let meta : @core.OptMeta = {
    name,
    kind: Option,
    help,
    shorts,
    aliases,
    inversion,
    env,
    auto_env,
    choices: [],
    value_name: "",
    required: false,
    visibility,
    global,
    greedy: false,
  }
  let reducer : (@core.ReduceCtx[Bool]) -> Bool? raise @core.ParseError = fn(
    ctx,
  ) {
    match ctx.action {
      Value(None) => Some(true)
      Negate => Some(false)
      Value(Some(_)) => None
    }
  }
  let cell : Ref[Bool] = { val: initial.get() }
  let erased_ref = @core.ErasedRef::new()
  parser.refs.set(id, @core.RefV::Value(erased_ref))
  let erased : @core.ErasedNode = {
    meta,
    arity: 0,
    try_reduce: (action, _result_map_id) => {
      let ctx : @core.ReduceCtx[Bool] = { current: cell.val, action }
      match reducer(ctx) {
        Some(new_val) =>
          Some(
            @core.ReduceResult::new(commit=fn() {
              cell.val = new_val
              erased_ref.set_source(@core.ValueSource::CommandLine)
            }),
          )
        None => None
      }
    },
    commit_reduce: fn(result) { result.run() },
    reset_to_initial: fn(_result_map_id) {
      cell.val = initial.get()
      erased_ref.set_source(@core.ValueSource::Initial)
    },
    children: fn() { [] },
  }
  let opt : @core.Opt[Bool] = {
    id,
    initial,
    reducer,
    meta,
    getter: fn(_result_map_id) { cell.val },
  }
  (opt, erased)
}

// ============================================================
// 2. string_opt (String?)
// ============================================================

///|
pub fn string_opt(
  parser : @core.Parser,
  name~ : String,
  help? : String = "",
  shorts? : Array[@core.ShortEntry] = [],
  aliases? : Array[@core.AliasEntry] = [],
  env? : String? = None,
  auto_env? : Bool? = None,
  choices? : Array[String] = [],
  value_name? : String = "VALUE",
  required? : Bool = false,
  visibility? : @core.Visibility = Visible,
  global? : Bool = false,
) -> (@core.Opt[String?], @core.ErasedNode) {
  let id = parser.next_id()
  let initial : @core.InitialValue[String?] = Val(None)
  let meta : @core.OptMeta = {
    name,
    kind: Option,
    help,
    shorts,
    aliases,
    inversion: None,
    env,
    auto_env,
    choices,
    value_name,
    required,
    visibility,
    global,
    greedy: false,
  }
  let reducer : (@core.ReduceCtx[String?]) -> String?? raise @core.ParseError = fn(
    ctx,
  ) {
    match ctx.action {
      Value(Some(s)) => Some(Some(s))
      Negate => Some(None)
      Value(None) => None
    }
  }
  let cell : Ref[String?] = { val: initial.get() }
  let erased_ref = @core.ErasedRef::new()
  parser.refs.set(id, @core.RefV::Value(erased_ref))
  let erased : @core.ErasedNode = {
    meta,
    arity: 1,
    try_reduce: (action, _result_map_id) => {
      let ctx : @core.ReduceCtx[String?] = { current: cell.val, action }
      match reducer(ctx) {
        Some(new_val) =>
          Some(
            @core.ReduceResult::new(commit=fn() {
              cell.val = new_val
              erased_ref.set_source(@core.ValueSource::CommandLine)
            }),
          )
        None => None
      }
    },
    commit_reduce: fn(result) { result.run() },
    reset_to_initial: fn(_result_map_id) {
      cell.val = initial.get()
      erased_ref.set_source(@core.ValueSource::Initial)
    },
    children: fn() { [] },
  }
  let opt : @core.Opt[String?] = {
    id,
    initial,
    reducer,
    meta,
    getter: fn(_result_map_id) { cell.val },
  }
  (opt, erased)
}

// ============================================================
// 3. int_opt (Int?)
// ============================================================

///|
pub fn int_opt(
  parser : @core.Parser,
  name~ : String,
  help? : String = "",
  shorts? : Array[@core.ShortEntry] = [],
  aliases? : Array[@core.AliasEntry] = [],
  env? : String? = None,
  auto_env? : Bool? = None,
  value_name? : String = "INT",
  required? : Bool = false,
  visibility? : @core.Visibility = Visible,
  global? : Bool = false,
) -> (@core.Opt[Int?], @core.ErasedNode) {
  let id = parser.next_id()
  let initial : @core.InitialValue[Int?] = Val(None)
  let meta : @core.OptMeta = {
    name,
    kind: Option,
    help,
    shorts,
    aliases,
    inversion: None,
    env,
    auto_env,
    choices: [],
    value_name,
    required,
    visibility,
    global,
    greedy: false,
  }
  let reducer : (@core.ReduceCtx[Int?]) -> Int?? raise @core.ParseError = ctx => {
    match ctx.action {
      Value(Some(s)) =>
        try {
          let n = @strconv.parse_int(s)
          Some(Some(n))
        } catch {
          @strconv.StrConvError(_) =>
            raise @core.ParseError::InvalidValue(
              name~,
              value=s,
              reason="not a valid integer",
            )
        }
      Negate => Some(None)
      Value(None) => None
    }
  }
  let cell : Ref[Int?] = { val: initial.get() }
  let erased_ref = @core.ErasedRef::new()
  parser.refs.set(id, @core.RefV::Value(erased_ref))
  let erased : @core.ErasedNode = {
    meta,
    arity: 1,
    try_reduce: (action, _result_map_id) => {
      let ctx : @core.ReduceCtx[Int?] = { current: cell.val, action }
      match reducer(ctx) {
        Some(new_val) =>
          Some(
            @core.ReduceResult::new(commit=fn() {
              cell.val = new_val
              erased_ref.set_source(@core.ValueSource::CommandLine)
            }),
          )
        None => None
      }
    },
    commit_reduce: fn(result) { result.run() },
    reset_to_initial: fn(_result_map_id) {
      cell.val = initial.get()
      erased_ref.set_source(@core.ValueSource::Initial)
    },
    children: fn() { [] },
  }
  let opt : @core.Opt[Int?] = {
    id,
    initial,
    reducer,
    meta,
    getter: fn(_result_map_id) { cell.val },
  }
  (opt, erased)
}

// ============================================================
// 4. positional (String?)
// ============================================================

///|
pub fn positional(
  parser : @core.Parser,
  name~ : String,
  help? : String = "",
  required? : Bool = false,
  visibility? : @core.Visibility = Visible,
) -> (@core.Opt[String?], @core.ErasedNode) {
  let id = parser.next_id()
  let initial : @core.InitialValue[String?] = Val(None)
  let meta : @core.OptMeta = {
    name,
    kind: Positional,
    help,
    shorts: [],
    aliases: [],
    inversion: None,
    env: None,
    auto_env: None,
    choices: [],
    value_name: name,
    required,
    visibility,
    global: false,
    greedy: false,
  }
  let reducer : (@core.ReduceCtx[String?]) -> String?? raise @core.ParseError = fn(
    ctx,
  ) {
    match ctx.action {
      Value(Some(s)) => Some(Some(s))
      _ => Some(None)
    }
  }
  let cell : Ref[String?] = { val: initial.get() }
  let erased_ref = @core.ErasedRef::new()
  parser.refs.set(id, @core.RefV::Value(erased_ref))
  let erased : @core.ErasedNode = {
    meta,
    arity: 1,
    try_reduce: (action, _result_map_id) => {
      let ctx : @core.ReduceCtx[String?] = { current: cell.val, action }
      match reducer(ctx) {
        Some(new_val) =>
          Some(
            @core.ReduceResult::new(commit=fn() {
              cell.val = new_val
              erased_ref.set_source(@core.ValueSource::CommandLine)
            }),
          )
        None => None
      }
    },
    commit_reduce: fn(result) { result.run() },
    reset_to_initial: fn(_result_map_id) {
      cell.val = initial.get()
      erased_ref.set_source(@core.ValueSource::Initial)
    },
    children: fn() { [] },
  }
  let opt : @core.Opt[String?] = {
    id,
    initial,
    reducer,
    meta,
    getter: fn(_result_map_id) { cell.val },
  }
  (opt, erased)
}

// ============================================================
// 5. opts ヘルパー
// ============================================================

///|
pub fn opts(arr : Array[@core.Opts]) -> @core.Opts {
  @core.Opts::Array(arr)
}
