///| Phase 4 Reducer 大統一設計 — 型定義
/// このパッケージは CLI パーサのコア型を提供する

// ============================================================
// 補助型
// ============================================================

///|
pub(all) enum Kind {
  Option
  Command
  Positional
} derive(Eq, Show, Debug)

///|
pub(all) struct ShortEntry {
  char : Char
} derive(Eq, Show, Debug)

///|
pub(all) struct AliasEntry {
  name : String
  deprecated : Bool
} derive(Eq, Show, Debug)

///|
pub(all) enum FlagInversion {
  No
  EnableDisable
  Custom(String, String)
} derive(Eq, Show, Debug)

///|
pub(all) enum Visibility {
  Visible
  Advanced
  Deprecated
  Hidden
} derive(Eq, Show, Debug)

///|
pub(all) enum ValueSource {
  Initial
  Default
  Environment
  CommandLine
} derive(Eq, Show, Debug)

///|
pub(all) enum ReduceAction {
  Value(String?)
  Negate
} derive(Eq, Show, Debug)

// ============================================================
// OptMeta
// ============================================================

///|
pub(all) struct OptMeta {
  name : String
  kind : Kind
  help : String
  shorts : Array[ShortEntry]
  aliases : Array[AliasEntry]
  inversion : FlagInversion?
  env : String?
  auto_env : Bool?
  choices : Array[String]
  value_name : String
  required : Bool
  visibility : Visibility
  global : Bool
  greedy : Bool
} derive(Show, Debug)

// ============================================================
// InitialValue[T]
// ============================================================

///|
pub(all) enum InitialValue[T] {
  Val(T)
  Thunk(() -> T)
}

///|
pub fn[T] InitialValue::get(self : InitialValue[T]) -> T {
  match self {
    Val(v) => v
    Thunk(f) => f()
  }
}

// ============================================================
// ReduceCtx[T]
// ============================================================

///|
pub(all) struct ReduceCtx[T] {
  current : T
  action : ReduceAction
}

// ============================================================
// ReduceResult — 型消去された一時結果（クロージャ方式）
// ============================================================

///|
pub struct ReduceResult {
  commit : () -> Unit
}

///|
pub fn ReduceResult::new(commit~ : () -> Unit) -> ReduceResult {
  { commit, }
}

///|
pub fn ReduceResult::run(self : ReduceResult) -> Unit {
  (self.commit)()
}

// ============================================================
// ParseError
// ============================================================

///|
pub(all) suberror ParseError {
  UnknownOption(String)
  MissingValue(String)
  InvalidValue(name~ : String, value~ : String, reason~ : String)
  MissingRequired(String)
  AmbiguousOption(input~ : String, candidates~ : Array[String])
  UnexpectedArgument(String)
  ExclusiveViolation(Array[String])
  Custom(String)
} derive(Show)

// ============================================================
// ErasedNode
// ============================================================

///|
pub(all) struct ErasedNode {
  meta : OptMeta
  arity : Int
  try_reduce : (ReduceAction, Int) -> ReduceResult? raise ParseError
  commit_reduce : (ReduceResult) -> Unit
  reset_to_initial : (Int) -> Unit
  children : () -> Array[ErasedNode]
}

// ============================================================
// Opts
// ============================================================

///|
pub(all) enum Opts {
  Node(ErasedNode)
  Array(Array[Opts])
}

// ============================================================
// ErasedRef / RefV
// ============================================================

///|
struct ErasedRef {
  mut source : ValueSource
}

///|
pub fn ErasedRef::new(source? : ValueSource = Initial) -> ErasedRef {
  { source, }
}

///|
pub fn ErasedRef::get_source(self : ErasedRef) -> ValueSource {
  self.source
}

///|
pub fn ErasedRef::set_source(self : ErasedRef, source : ValueSource) -> Unit {
  self.source = source
}

///|
pub(all) enum RefV {
  Value(ErasedRef)
  Array(Array[ErasedRef])
}

// ============================================================
// Parser
// ============================================================

///|
pub(all) struct Parser {
  mut seq : Int
  refs : Map[Int, RefV]
  clone_map : Map[Int, Int]
}

///|
pub fn Parser::new() -> Parser {
  { seq: 0, refs: Map::new(), clone_map: Map::new() }
}

///|
pub fn Parser::next_id(self : Parser) -> Int {
  self.seq = self.seq + 1
  self.seq
}

// ============================================================
// Opt[T]
// ============================================================

///|
pub(all) struct Opt[T] {
  id : Int
  initial : InitialValue[T]
  reducer : (ReduceCtx[T]) -> T? raise ParseError
  meta : OptMeta
  getter : (Int) -> T
}

///|
pub impl[T] Hash for Opt[T] with hash(self) {
  self.id.hash()
}

///|
pub impl[T] Hash for Opt[T] with hash_combine(self, hasher) {
  self.id.hash_combine(hasher)
}

///|
pub impl[T] Eq for Opt[T] with equal(self, other) {
  self.id == other.id
}
