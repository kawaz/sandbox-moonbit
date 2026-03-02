///| ホワイトボックステスト — 内部型の構築テスト

///|
test "ErasedRef construction" {
  let er = ErasedRef::{ source: ValueSource::Initial }
  inspect(er.source, content="Initial")
  er.source = ValueSource::CommandLine
  inspect(er.source, content="CommandLine")
}

///|
test "ReduceResult construction and commit" {
  let called : Ref[Bool] = { val: false }
  let rr = ReduceResult::{ commit: fn() { called.val = true } }
  assert_false(called.val)
  (rr.commit)()
  assert_true(called.val)
}
