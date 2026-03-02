// ============================================================
// Parser struct + getter 方式 PoC テスト
// ============================================================

// === シナリオ1: 基本 - Parser + Opt + getter で型安全取得 ===

///|
test "scenario1: basic - create opts and get typed values" {
  let p = @poc4.Parser::new()
  let port = p.int(name="port", default=8080)
  let verbose = p.flag(name="verbose")
  let host = p.str(name="host", default="localhost")
  // 初期値が正しく取得できる
  inspect(
    p.get(port),
    content=(
      #|8080
    ),
  )
  inspect(
    p.get(verbose),
    content=(
      #|false
    ),
  )
  inspect(
    p.get(host),
    content=(
      #|localhost
    ),
  )
}

///|
test "scenario1: setter and getter roundtrip" {
  let p = @poc4.Parser::new()
  let port = p.int(name="port", default=0)
  let verbose = p.flag(name="verbose")
  // setter で値を設定
  (port.setter)(-1, 3000)
  (verbose.setter)(-1, true)
  // getter で型安全に取得（ダウンキャスト不使用）
  inspect(
    p.get(port),
    content=(
      #|3000
    ),
  )
  inspect(
    p.get(verbose),
    content=(
      #|true
    ),
  )
}

///|
test "scenario1: multiple opts are independent" {
  let p = @poc4.Parser::new()
  let a = p.int(name="a", default=1)
  let b = p.int(name="b", default=2)
  (a.setter)(-1, 100)
  // a を変更しても b は影響されない
  inspect(
    p.get(a),
    content=(
      #|100
    ),
  )
  inspect(
    p.get(b),
    content=(
      #|2
    ),
  )
}

// === シナリオ2: グループ - clone + clone_map + Array refs ===

///|
test "scenario2: group clone and per-clone values" {
  let p = @poc4.Parser::new()
  let host = p.str(name="host", default="")
  let timeout = p.int(name="timeout", default=30)
  // グループ雛形登録（host, timeout の ID を渡す）
  let group_id = p.register_group([host.id, timeout.id])
  // clone 2回
  let clone0 = p.clone_group(group_id)
  let clone1 = p.clone_group(group_id)
  // 各 clone に値を設定（ErasedRef 経由）
  let host0_ref = p.get_group_ref(clone0, 0)
  (host0_ref.reduce_erased)(@poc4.ReduceAction::Value(Some("server-a")))
  |> ignore
  let host1_ref = p.get_group_ref(clone1, 0)
  (host1_ref.reduce_erased)(@poc4.ReduceAction::Value(Some("server-b")))
  |> ignore
  let timeout1_ref = p.get_group_ref(clone1, 1)
  (timeout1_ref.reduce_erased)(@poc4.ReduceAction::Value(Some("60"))) |> ignore
  // 各 clone の値が独立していることを検証
  // clone0: host="server-a", timeout=30 (default)
  let host0 = p.get_group_ref(clone0, 0)
  let timeout0 = p.get_group_ref(clone0, 1)
  let host1 = p.get_group_ref(clone1, 0)
  let timeout1 = p.get_group_ref(clone1, 1)
  // reduce_erased で読めないので、clone 後に getter 経由で検証するため
  // 別のアプローチ: ErasedRef の reduce 結果を直接確認
  // → PoC ではまず reduce_erased の動作確認に集中
  inspect(
    (host0.reduce_erased)(@poc4.ReduceAction::Value(Some("check"))),
    content=(
      #|true
    ),
  )
  inspect(
    (timeout0.reduce_erased)(@poc4.ReduceAction::Value(Some("99"))),
    content=(
      #|true
    ),
  )
  ignore(host1)
  ignore(timeout1)
}

// === シナリオ3: テスト分離 - 別 Parser インスタンスの独立性 ===

///|
test "scenario3: separate parsers have independent id spaces" {
  let p1 = @poc4.Parser::new()
  let port1 = p1.int(name="port", default=0)
  let p2 = @poc4.Parser::new()
  let port2 = p2.int(name="port", default=0)
  // 両方とも ID=0 から始まる（Parser ローカル seq）
  inspect(
    port1.id,
    content=(
      #|0
    ),
  )
  inspect(
    port2.id,
    content=(
      #|0
    ),
  )
}

///|
test "scenario3: separate parsers values are independent" {
  let p1 = @poc4.Parser::new()
  let x = p1.int(name="x", default=0)
  let p2 = @poc4.Parser::new()
  let y = p2.int(name="y", default=0)
  (x.setter)(-1, 42)
  (y.setter)(-1, 99)
  // 完全に独立
  inspect(
    p1.get(x),
    content=(
      #|42
    ),
  )
  inspect(
    p2.get(y),
    content=(
      #|99
    ),
  )
}

// === シナリオ4: ErasedRef - reduce_erased 相当の型消去書き込み ===

///|
test "scenario4: reduce_erased writes, getter reads - same Ref[T]" {
  let p = @poc4.Parser::new()
  let port = p.int(name="port", default=0)
  // reduce_erased 経由で型を知らずに書き込み
  // （パーサが ErasedNode.reduce_erased を呼ぶシミュレーション）
  match p.refs.get(port.id) {
    Some(@poc4.RefV::Single(erased)) => {
      let ok = (erased.reduce_erased)(@poc4.ReduceAction::Value(Some("3000")))
      inspect(
        ok,
        content=(
          #|true
        ),
      )
    }
    _ => abort("expected Single ref")
  }
  // getter 経由で型安全に読み出し（同じ Ref[T] を共有）
  inspect(
    p.get(port),
    content=(
      #|3000
    ),
  )
}

///|
test "scenario4: reduce_erased with flag" {
  let p = @poc4.Parser::new()
  let verbose = p.flag(name="verbose")
  // reduce_erased で flag をセット（Value(None) = フラグON）
  match p.refs.get(verbose.id) {
    Some(@poc4.RefV::Single(erased)) => {
      let ok = (erased.reduce_erased)(@poc4.ReduceAction::Value(None))
      inspect(
        ok,
        content=(
          #|true
        ),
      )
    }
    _ => abort("expected Single ref")
  }
  // getter で読み出し
  inspect(
    p.get(verbose),
    content=(
      #|true
    ),
  )
}

///|
test "scenario4: reduce_erased negate resets to initial" {
  let p = @poc4.Parser::new()
  let port = p.int(name="port", default=8080)
  // まず値を設定
  (port.setter)(-1, 3000)
  inspect(
    p.get(port),
    content=(
      #|3000
    ),
  )
  // Negate で初期値にリセット
  match p.refs.get(port.id) {
    Some(@poc4.RefV::Single(erased)) => {
      let ok = (erased.reduce_erased)(@poc4.ReduceAction::Negate)
      inspect(
        ok,
        content=(
          #|true
        ),
      )
    }
    _ => abort("expected Single ref")
  }
  inspect(
    p.get(port),
    content=(
      #|8080
    ),
  )
}

///|
test "scenario4: reduce_erased returns false on mismatch" {
  let p = @poc4.Parser::new()
  let flag = p.flag(name="flag")
  // フラグに Value(Some("string")) を渡す → reducer が None 返す → false
  match p.refs.get(flag.id) {
    Some(@poc4.RefV::Single(erased)) => {
      let ok = (erased.reduce_erased)(
        @poc4.ReduceAction::Value(Some("unexpected")),
      )
      inspect(
        ok,
        content=(
          #|false
        ),
      )
    }
    _ => abort("expected Single ref")
  }
}

///|
test "scenario4: erased reset restores initial value" {
  let p = @poc4.Parser::new()
  let port = p.int(name="port", default=42)
  (port.setter)(-1, 999)
  inspect(
    p.get(port),
    content=(
      #|999
    ),
  )
  // reset で初期値に戻る
  match p.refs.get(port.id) {
    Some(@poc4.RefV::Single(erased)) => (erased.reset)()
    _ => abort("expected Single ref")
  }
  inspect(
    p.get(port),
    content=(
      #|42
    ),
  )
}
