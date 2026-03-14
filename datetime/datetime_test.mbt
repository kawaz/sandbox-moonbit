///| now = 1000 for all tests (easy arithmetic)
let test_now : Int64 = 1000L

// ============================================================
// Duration formatting
// ============================================================

///|
test "format_offset: basic durations" {
  inspect(@datetime.format_offset(0L), content="0s")
  inspect(@datetime.format_offset(-300L), content="-5m")
  inspect(@datetime.format_offset(300L), content="+5m")
  inspect(@datetime.format_offset(-3600L), content="-1h")
  inspect(@datetime.format_offset(-5400L), content="-1h30m")
  inspect(@datetime.format_offset(-86400L), content="-1d")
  inspect(@datetime.format_offset(-90L), content="-1m30s")
}

// ============================================================
// Single value (no ~)
// ============================================================

///|
test "since: 5m → Relative(now-300, -300)" {
  let result = @datetime.parse("5m", context=Since, now=test_now)
  inspect(result.since, content="Some(Relative(700, -300))")
  assert_true(result.until is None)
}

///|
test "since: @5m → Absolute(now-300)" {
  let result = @datetime.parse("@5m", context=Since, now=test_now)
  inspect(result.since, content="Some(Absolute(700))")
  assert_true(result.until is None)
}

///|
test "since: @ → Absolute(now)" {
  let result = @datetime.parse("@", context=Since, now=test_now)
  inspect(result.since, content="Some(Absolute(1000))")
}

///|
test "since: +5m → Relative(now+300, +300)" {
  let result = @datetime.parse("+5m", context=Since, now=test_now)
  inspect(result.since, content="Some(Relative(1300, 300))")
}

///|
test "since: -5m → Relative(now-300, -300)" {
  let result = @datetime.parse("-5m", context=Since, now=test_now)
  inspect(result.since, content="Some(Relative(700, -300))")
}

///|
test "since: @+5m → Absolute(now+300)" {
  let result = @datetime.parse("@+5m", context=Since, now=test_now)
  inspect(result.since, content="Some(Absolute(1300))")
}

// ============================================================
// Both-relative range with Since context
// ============================================================

///|
test "since: 5m~3m → s=R(now-5m,-5m) u=R(now-2m,-3m)" {
  let result = @datetime.parse("5m~3m", context=Since, now=test_now)
  inspect(result.since, content="Some(Relative(700, -300))")
  inspect(result.until, content="Some(Relative(880, -180))")
}

///|
test "since: 5m~-3m → same computation, stored sign -" {
  let result = @datetime.parse("5m~-3m", context=Since, now=test_now)
  inspect(result.since, content="Some(Relative(700, -300))")
  inspect(result.until, content="Some(Relative(880, -180))")
}

///|
test "since: 5m~+3m → same computation, stored sign +" {
  let result = @datetime.parse("5m~+3m", context=Since, now=test_now)
  inspect(result.since, content="Some(Relative(700, -300))")
  inspect(result.until, content="Some(Relative(880, 180))")
}

// ============================================================
// Mixed: @ on since side (Since context)
// ============================================================

///|
test "since: @5m~3m → s=A(now-5m) u=R(s+3m)" {
  let result = @datetime.parse("@5m~3m", context=Since, now=test_now)
  inspect(result.since, content="Some(Absolute(700))")
  inspect(result.until, content="Some(Relative(880, -180))")
}

///|
test "since: @5m~-3m → explicit minus, until=s-3m" {
  let result = @datetime.parse("@5m~-3m", context=Since, now=test_now)
  inspect(result.since, content="Some(Absolute(700))")
  inspect(result.until, content="Some(Relative(520, -180))")
}

///|
test "since: @5m~+3m → explicit plus, until=s+3m" {
  let result = @datetime.parse("@5m~+3m", context=Since, now=test_now)
  inspect(result.since, content="Some(Absolute(700))")
  inspect(result.until, content="Some(Relative(880, 180))")
}

// ============================================================
// Mixed: @ on until side (Since context)
// ============================================================

///|
test "since: 5m~@3m → u=A(now-3m) s=R(u-5m)" {
  let result = @datetime.parse("5m~@3m", context=Since, now=test_now)
  inspect(result.until, content="Some(Absolute(820))")
  inspect(result.since, content="Some(Relative(520, -300))")
}

// ============================================================
// Both absolute (Since context)
// ============================================================

///|
test "since: @5m~@3m → both independent, s=A(now-5m) u=A(now-3m)" {
  let result = @datetime.parse("@5m~@3m", context=Since, now=test_now)
  inspect(result.since, content="Some(Absolute(700))")
  inspect(result.until, content="Some(Absolute(820))")
}

///|
test "since: @5m~@+3m → s=A(now-5m) u=A(now+3m)" {
  let result = @datetime.parse("@5m~@+3m", context=Since, now=test_now)
  inspect(result.since, content="Some(Absolute(700))")
  inspect(result.until, content="Some(Absolute(1180))")
}

// ============================================================
// Until context
// ============================================================

///|
test "until: 5m~3m → u=R(now-3m) s=R(u-5m)" {
  let result = @datetime.parse("5m~3m", context=Until, now=test_now)
  inspect(result.since, content="Some(Relative(520, -300))")
  inspect(result.until, content="Some(Relative(820, -180))")
}

// ============================================================
// Range context
// ============================================================

///|
test "range: 5m~3m → both independent from now" {
  let result = @datetime.parse("5m~3m", context=Range, now=test_now)
  inspect(result.since, content="Some(Relative(700, -300))")
  inspect(result.until, content="Some(Relative(820, -180))")
}

///|
test "range: 3m~5m → inverted (no swap)" {
  let result = @datetime.parse("3m~5m", context=Range, now=test_now)
  inspect(result.since, content="Some(Relative(820, -180))")
  inspect(result.until, content="Some(Relative(700, -300))")
}

///|
test "range: 3m~5m with swap" {
  let result = @datetime.parse("3m~5m", context=Range, now=test_now, swap=true)
  let s_epoch = match result.since {
    Some(Relative(e, _)) => e
    _ => panic()
  }
  let u_epoch = match result.until {
    Some(Relative(e, _)) => e
    _ => panic()
  }
  assert_true(s_epoch <= u_epoch)
}

// ============================================================
// Tilde edge cases
// ============================================================

///|
test "since: ~ → both Relative(now, 0)" {
  let result = @datetime.parse("~", context=Since, now=test_now)
  inspect(result.since, content="Some(Relative(1000, 0))")
  inspect(result.until, content="Some(Relative(1000, 0))")
}

// ============================================================
// ISO 8601 timestamp
// ============================================================

///|
test "since: 2024-01-01T00:00:00Z → Absolute" {
  let result = @datetime.parse(
    "2024-01-01T00:00:00Z", context=Since, now=test_now,
  )
  inspect(result.since, content="Some(Absolute(1704067200))")
}

// ============================================================
// Re-serialization round-trip
// ============================================================

///|
test "re-serialize: Relative" {
  let ts : @datetime.TimeSpec = Relative(700L, -300L)
  inspect(ts.to_cli_string(), content="-5m")
}

///|
test "re-serialize: Absolute epoch 0" {
  let ts : @datetime.TimeSpec = Absolute(0L)
  inspect(ts.to_cli_string(), content="1970-01-01T00:00:00Z")
}

///|
test "re-serialize: Absolute epoch 1704067200" {
  let ts : @datetime.TimeSpec = Absolute(1704067200L)
  inspect(ts.to_cli_string(), content="2024-01-01T00:00:00Z")
}
