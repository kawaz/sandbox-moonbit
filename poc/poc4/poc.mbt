// ============================================================
// Parser struct + getter 方式 PoC
//
// 前回 PoC (poc3 方式A) からの変更点:
// - グローバル ID カウンタ → Parser ローカル seq（テスト分離）
// - Opt[T].slots → Opt[T].getter クロージャのみ（slots フィールド不要）
// - 値の所有権: Parser.refs に集約（Opt 側に分散しない）
// - グループ: clone_map + RefV::Array で管理
// ============================================================

// === 型消去された参照 ===

///|
/// ErasedRef — 型消去された単一値への参照。
/// reduce_erased クロージャが Ref[T] をキャプチャし、型を知らずに操作する。
pub(all) struct ErasedRef {
  /// 型消去された reduce: ReduceAction を受け取り Ref[T] を更新
  reduce_erased : (ReduceAction) -> Bool
  /// 初期値にリセット
  reset : () -> Unit
  /// clone: 現在値のコピーを持つ新しい ErasedRef を返す
  clone_ref : () -> ErasedRef
}

///|
/// ReduceAction — パーサが発行するアクション
pub(all) enum ReduceAction {
  Value(String?)
  Negate
}

///|
/// RefV — Parser.refs に格納される値
pub(all) enum RefV {
  Single(ErasedRef)
  Group(Array[ErasedRef])
}

// === Parser ===

///|
/// Parser — Opt を生成し、refs で値を管理する。
/// 各 Parser インスタンスが独自の seq を持つためテスト間で独立。
pub(all) struct Parser {
  mut seq : Int
  refs : Map[Int, RefV]
  clone_map : Map[Int, Int] // clone_id → template_id
}

///|
pub fn Parser::new() -> Parser {
  { seq: 0, refs: Map::new(), clone_map: Map::new() }
}

///|
fn Parser::next_id(self : Parser) -> Int {
  let id = self.seq
  self.seq = self.seq + 1
  id
}

// === Opt[T] ===

///|
/// Opt[T] — オプション定義。値は Parser.refs に管理される。
/// getter クロージャが Parser の refs 内の Ref[T] をキャプチャしている。
pub(all) struct Opt[T] {
  id : Int
  name : String
  /// getter: instance_id → T
  /// instance_id = -1 の場合は Parser 直属の値、
  /// instance_id >= 0 の場合は clone 内の Array インデックス
  getter : (Int) -> T
  /// setter: (instance_id, T) → Unit（テスト用、通常は reduce_erased 経由）
  setter : (Int, T) -> Unit
}

// === Parser のファクトリメソッド ===

///|
/// 型消去された Ref[T] + ErasedRef + getter/setter を一括生成するヘルパー。
/// Opt[T] に Ref フィールドを持たせず、クロージャだけで接続する。
fn[T] Parser::register_opt(
  self : Parser,
  name : String,
  initial : T,
  reducer : (T, ReduceAction) -> T?,
) -> Opt[T] {
  let id = self.next_id()
  let cell : Ref[T] = { val: initial }
  let initial_val = initial
  let erased = ErasedRef::{
    reduce_erased: fn(action : ReduceAction) -> Bool {
      match reducer(cell.val, action) {
        Some(v) => {
          cell.val = v
          true
        }
        None => false
      }
    },
    reset: fn() { cell.val = initial_val },
    clone_ref: fn() -> ErasedRef {
      let new_cell : Ref[T] = { val: cell.val }
      ErasedRef::{
        reduce_erased: fn(action : ReduceAction) -> Bool {
          match reducer(new_cell.val, action) {
            Some(v) => {
              new_cell.val = v
              true
            }
            None => false
          }
        },
        reset: fn() { new_cell.val = initial_val },
        clone_ref: fn() -> ErasedRef {
          // 再帰的 clone は PoC では未対応
          abort("nested clone not supported in PoC")
        },
      }
    },
  }
  self.refs.set(id, Single(erased))
  // getter/setter は cell を直接キャプチャ（Parser.refs 経由ではない）
  // → Opt[T] は id と getter/setter クロージャだけ保持
  let opt : Opt[T] = {
    id,
    name,
    getter: fn(instance_id : Int) -> T {
      if instance_id < 0 {
        // 直属の値
        cell.val
      } else {
        // グループ clone からの取得
        // → register_group_opt で上書きされる getter が使われる
        // ここは直属用のフォールバック
        cell.val
      }
    },
    setter: fn(instance_id : Int, value : T) -> Unit {
      ignore(instance_id)
      cell.val = value
    },
  }
  opt
}

///|
/// Int オプションを生成
pub fn Parser::int(
  self : Parser,
  name~ : String,
  default? : Int = 0,
) -> Opt[Int] {
  self.register_opt(name, default, fn(_cur, action) {
    match action {
      Value(Some(s)) => {
        let result : Result[Int, _] = try? @strconv.parse_int(s.view())
        match result {
          Ok(v) => Some(v)
          Err(_) => None
        }
      }
      Value(None) => None
      Negate => Some(default)
    }
  })
}

///|
/// Bool (flag) オプションを生成
pub fn Parser::flag(
  self : Parser,
  name~ : String,
  default? : Bool = false,
) -> Opt[Bool] {
  self.register_opt(name, default, fn(_, action) {
    match action {
      Value(None) => Some(true)
      Value(_) => None
      Negate => Some(default)
    }
  })
}

///|
/// String オプションを生成
pub fn Parser::str(
  self : Parser,
  name~ : String,
  default? : String = "",
) -> Opt[String] {
  self.register_opt(name, default, fn(_, action) {
    match action {
      Value(Some(s)) => Some(s)
      Value(None) => None
      Negate => Some(default)
    }
  })
}

// === 値の取得 ===

///|
/// Parser から Opt[T] の値を取得（直属の値）
pub fn[T] Parser::get(self : Parser, opt : Opt[T]) -> T {
  ignore(self)
  (opt.getter)(-1)
}

///|
/// Parser からグループ clone インスタンスの値を取得
pub fn[T] Parser::get_clone(self : Parser, opt : Opt[T], clone_id : Int) -> T {
  // clone_map から template_id を引く
  match self.clone_map.get(clone_id) {
    Some(_template_id) =>
      // clone_id からグループ内の Array インデックスを特定
      // (clone_id - template_id - 1) がインデックス
      (opt.getter)(clone_id)
    None => abort("get_clone: unknown clone_id")
  }
}

// === グループ ===

///|
/// グループ雛形を登録。template_id を返す。
/// 各 Opt の ErasedRef を Array にまとめて refs に格納。
pub fn Parser::register_group(self : Parser, opt_ids : Array[Int]) -> Int {
  let template_id = self.next_id()
  let group : Array[ErasedRef] = []
  for id in opt_ids {
    match self.refs.get(id) {
      Some(Single(erased)) => group.push(erased)
      _ => abort("register_group: opt not found or not single")
    }
  }
  self.refs.set(template_id, Group(group))
  template_id
}

///|
/// グループを clone し、clone_id を返す。
/// 各 ErasedRef を clone_ref() で複製して新しい Array に格納。
pub fn Parser::clone_group(self : Parser, template_id : Int) -> Int {
  let clone_id = self.next_id()
  match self.refs.get(template_id) {
    Some(Group(template_refs)) => {
      let cloned : Array[ErasedRef] = []
      for er in template_refs {
        cloned.push((er.clone_ref)())
      }
      self.refs.set(clone_id, Group(cloned))
      self.clone_map.set(clone_id, template_id)
    }
    _ => abort("clone_group: template not found or not a group")
  }
  clone_id
}

///|
/// グループ clone 内の特定 opt の ErasedRef を取得
pub fn Parser::get_group_ref(
  self : Parser,
  clone_id : Int,
  opt_index : Int,
) -> ErasedRef {
  match self.refs.get(clone_id) {
    Some(Group(refs)) => refs[opt_index]
    _ => abort("get_group_ref: not a group")
  }
}
