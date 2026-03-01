// ============================================================
// poc3: 型消去→型復元の最小 PoC
//
// 方式A: Ref[T] クロージャキャプチャ方式
//   Slot[T] が Map[Int, Ref[T]] を保持し、Store の ID をキーに Ref[T] を管理。
//   Store は値を持たない。Slot が各 Store ごとの Ref を保持する。
//
// 方式B: enum Value 方式（閉じた型集合）
//   Store が Map[Int, Value] で値を保持。Slot[T] が wrap/unwrap クロージャを持つ。
// ============================================================

// === ID カウンタ ===

///|
/// SlotA/SlotB 用 ID カウンタ
let id_counter : Ref[Int] = { val: 0 }

///|
fn next_id() -> Int {
  let id = id_counter.val
  id_counter.val = id + 1
  id
}

///|
/// StoreA 用 ID カウンタ
let store_id_counter : Ref[Int] = { val: 0 }

///|
fn next_store_id() -> Int {
  let id = store_id_counter.val
  store_id_counter.val = id + 1
  id
}

// ============================================================
// 方式A: Ref[T] クロージャキャプチャ
// ============================================================

///|
/// SlotA[T] -- 型パラメータ T を保持したまま値を分散管理する。
/// slots に StoreA ごとの Ref[T] を保持する。
pub(all) struct SlotA[T] {
  id : Int
  default_value : T
  /// store_id -> Ref[T] のマッピング
  slots : Map[Int, Ref[T]]
}

///|
/// SlotA[T] を作る。default_value は get 時に未設定なら返す値。
pub fn[T] SlotA::new(default_value : T) -> SlotA[T] {
  { id: next_id(), default_value, slots: Map::new() }
}

///|
/// StoreA -- 値は持たず、clone 用クロージャレジストリとして機能する。
pub(all) struct StoreA {
  id : Int
  /// slot_id -> clone クロージャ: (src_store_id, dst_store_id) -> Unit
  clone_fns : Map[Int, (Int, Int) -> Unit]
}

///|
pub fn StoreA::new() -> StoreA {
  { id: next_store_id(), clone_fns: Map::new() }
}

///|
/// StoreA から SlotA[T] の値を取得
pub fn[T] StoreA::get(self : StoreA, slot : SlotA[T]) -> T {
  match slot.slots.get(self.id) {
    Some(r) => r.val
    None => slot.default_value
  }
}

///|
/// StoreA に SlotA[T] の値を設定
pub fn[T] StoreA::set(self : StoreA, slot : SlotA[T], value : T) -> Unit {
  match slot.slots.get(self.id) {
    Some(r) => r.val = value
    None => {
      slot.slots.set(self.id, { val: value })
      // clone クロージャを登録（初回のみ）
      // Design rationale: クロージャが slot.slots と slot.default_value を
      // キャプチャしているため、どの StoreA から clone されても
      // 正しい SlotA の slots にアクセスする。
      let slot_id = slot.id
      let slots = slot.slots
      let default_value = slot.default_value
      self.clone_fns.set(slot_id, fn(src_store_id, dst_store_id) {
        let val = match slots.get(src_store_id) {
          Some(r) => r.val
          None => default_value
        }
        slots.set(dst_store_id, { val, })
      })
    }
  }
}

///|
/// StoreA を clone する（各 SlotA に独立した Ref を作る）
pub fn StoreA::clone(self : StoreA) -> StoreA {
  let new_store = StoreA::new()
  self.clone_fns.each(fn(slot_id, clone_fn) {
    clone_fn(self.id, new_store.id)
    new_store.clone_fns.set(slot_id, clone_fn)
  })
  new_store
}

// ============================================================
// 方式B: enum Value（閉じた型集合）
// ============================================================

///|
/// CLI パーサで扱う値の閉じた型集合
pub(all) enum Value {
  VInt(Int)
  VBool(Bool)
  VStr(String)
} derive(Eq, Show, Debug)

///|
/// SlotB[T] -- wrap/unwrap クロージャで T <-> Value の変換を閉じ込める。
pub(all) struct SlotB[T] {
  id : Int
  default_value : T
  wrap : (T) -> Value
  unwrap : (Value) -> T
}

///|
/// SlotB ファクトリ: Int 用
pub fn SlotB::int(default_value : Int) -> SlotB[Int] {
  {
    id: next_id(),
    default_value,
    wrap: fn(v : Int) -> Value { VInt(v) },
    unwrap: fn(v : Value) -> Int {
      match v {
        VInt(i) => i
        _ => abort("SlotB::int unwrap: type mismatch")
      }
    },
  }
}

///|
/// SlotB ファクトリ: Bool 用
pub fn SlotB::bool(default_value : Bool) -> SlotB[Bool] {
  {
    id: next_id(),
    default_value,
    wrap: fn(v : Bool) -> Value { VBool(v) },
    unwrap: fn(v : Value) -> Bool {
      match v {
        VBool(b) => b
        _ => abort("SlotB::bool unwrap: type mismatch")
      }
    },
  }
}

///|
/// SlotB ファクトリ: String 用
pub fn SlotB::str(default_value : String) -> SlotB[String] {
  {
    id: next_id(),
    default_value,
    wrap: fn(v : String) -> Value { VStr(v) },
    unwrap: fn(v : Value) -> String {
      match v {
        VStr(s) => s
        _ => abort("SlotB::str unwrap: type mismatch")
      }
    },
  }
}

///|
/// StoreB -- enum Value の Map で値を保持
pub(all) struct StoreB {
  data : Map[Int, Value]
}

///|
pub fn StoreB::new() -> StoreB {
  { data: Map::new() }
}

///|
/// StoreB から SlotB[T] の値を取得
pub fn[T] StoreB::get(self : StoreB, slot : SlotB[T]) -> T {
  match self.data.get(slot.id) {
    Some(v) => (slot.unwrap)(v)
    None => slot.default_value
  }
}

///|
/// StoreB に SlotB[T] の値を設定
pub fn[T] StoreB::set(self : StoreB, slot : SlotB[T], value : T) -> Unit {
  self.data.set(slot.id, (slot.wrap)(value))
}

///|
/// StoreB を clone する（Map をコピー）
pub fn StoreB::clone(self : StoreB) -> StoreB {
  let new_data : Map[Int, Value] = Map::new()
  self.data.each(fn(k, v) { new_data.set(k, v) })
  { data: new_data }
}
