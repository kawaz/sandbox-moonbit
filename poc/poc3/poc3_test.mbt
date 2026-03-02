///|
test "poc3a: type erasure with Ref[T] capture - basics" {
  // 異なる型の Slot を作る
  let int_slot = @poc3.SlotA::new(42)
  let bool_slot = @poc3.SlotA::new(true)
  let str_slot = @poc3.SlotA::new("hello")

  // 1つの Store に入れる
  let store = @poc3.StoreA::new()
  store.set(int_slot, 42)
  store.set(bool_slot, true)
  store.set(str_slot, "hello")

  // 型安全に取り出す
  inspect(store.get(int_slot), content="42")
  inspect(store.get(bool_slot), content="true")
  inspect(store.get(str_slot), content="hello")

  // 上書きできる
  store.set(int_slot, 100)
  inspect(store.get(int_slot), content="100")

  // デフォルト値（setしていないSlotはdefaultを返す）
  let unset = @poc3.SlotA::new(0)
  inspect(store.get(unset), content="0")
}

///|
test "poc3a: store clone produces independent copy" {
  let slot = @poc3.SlotA::new(0)
  let store = @poc3.StoreA::new()
  store.set(slot, 10)

  let cloned = store.clone()
  cloned.set(slot, 99)

  // 互いに独立
  inspect(store.get(slot), content="10")
  inspect(cloned.get(slot), content="99")
}

///|
test "poc3b: type erasure with enum Value - basics" {
  // 異なる型の Slot を作る（wrap/unwrap を指定）
  let int_slot = @poc3.SlotB::int(42)
  let bool_slot = @poc3.SlotB::bool(true)
  let str_slot = @poc3.SlotB::str("hello")

  // 1つの Store に入れる
  let store = @poc3.StoreB::new()
  store.set(int_slot, 42)
  store.set(bool_slot, true)
  store.set(str_slot, "hello")

  // 型安全に取り出す
  inspect(store.get(int_slot), content="42")
  inspect(store.get(bool_slot), content="true")
  inspect(store.get(str_slot), content="hello")

  // 上書きできる
  store.set(int_slot, 100)
  inspect(store.get(int_slot), content="100")

  // デフォルト値
  let unset = @poc3.SlotB::int(0)
  inspect(store.get(unset), content="0")
}

///|
test "poc3b: store clone produces independent copy" {
  let slot = @poc3.SlotB::int(0)
  let store = @poc3.StoreB::new()
  store.set(slot, 10)

  let cloned = store.clone()
  cloned.set(slot, 99)

  inspect(store.get(slot), content="10")
  inspect(cloned.get(slot), content="99")
}
