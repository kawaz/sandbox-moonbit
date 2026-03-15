///| now = 1_000_000 ms (1000 seconds) for all tests
fn test_now() -> Int64 {
  1_000_000L
}

// ============================================================
// Single value (no ~)
// ============================================================

///|
test "since: 5m → Relative(now-300_000, Ms(-300_000))" {
  let result = @datetime.parse("5m", context=Since, now=test_now)
  inspect(result.since, content="Some(Relative(700000, Ms(-300000)))")
  assert_true(result.until is None)
}

///|
test "since: @5m → Absolute(now-300_000)" {
  let result = @datetime.parse("@5m", context=Since, now=test_now)
  inspect(result.since, content="Some(Absolute(700000))")
  assert_true(result.until is None)
}

///|
test "since: @ → Absolute(now)" {
  let result = @datetime.parse("@", context=Since, now=test_now)
  inspect(result.since, content="Some(Absolute(1000000))")
}

///|
test "since: +5m → Relative(now+300_000, Ms(300_000))" {
  let result = @datetime.parse("+5m", context=Since, now=test_now)
  inspect(result.since, content="Some(Relative(1300000, Ms(300000)))")
}

///|
test "since: -5m → Relative(now-300_000, Ms(-300_000))" {
  let result = @datetime.parse("-5m", context=Since, now=test_now)
  inspect(result.since, content="Some(Relative(700000, Ms(-300000)))")
}

///|
test "since: @+5m → Absolute(now+300_000)" {
  let result = @datetime.parse("@+5m", context=Since, now=test_now)
  inspect(result.since, content="Some(Absolute(1300000))")
}

// ============================================================
// Both-relative range with Since context
// ============================================================

///|
test "since: 5m~3m → s=R(now-5m,-5m) u=R(now-2m,-3m)" {
  let result = @datetime.parse("5m~3m", context=Since, now=test_now)
  inspect(result.since, content="Some(Relative(700000, Ms(-300000)))")
  inspect(result.until, content="Some(Relative(880000, Ms(-180000)))")
}

///|
test "since: 5m~-3m → same computation, stored sign -" {
  let result = @datetime.parse("5m~-3m", context=Since, now=test_now)
  inspect(result.since, content="Some(Relative(700000, Ms(-300000)))")
  inspect(result.until, content="Some(Relative(880000, Ms(-180000)))")
}

///|
test "since: 5m~+3m → same computation, stored sign +" {
  let result = @datetime.parse("5m~+3m", context=Since, now=test_now)
  inspect(result.since, content="Some(Relative(700000, Ms(-300000)))")
  inspect(result.until, content="Some(Relative(880000, Ms(180000)))")
}

// ============================================================
// Mixed: @ on since side (Since context)
// ============================================================

///|
test "since: @5m~3m → s=A(now-5m) u=R(s+3m)" {
  let result = @datetime.parse("@5m~3m", context=Since, now=test_now)
  inspect(result.since, content="Some(Absolute(700000))")
  inspect(result.until, content="Some(Relative(880000, Ms(-180000)))")
}

///|
test "since: @5m~-3m → explicit minus, until=s-3m" {
  let result = @datetime.parse("@5m~-3m", context=Since, now=test_now)
  inspect(result.since, content="Some(Absolute(700000))")
  inspect(result.until, content="Some(Relative(520000, Ms(-180000)))")
}

///|
test "since: @5m~+3m → explicit plus, until=s+3m" {
  let result = @datetime.parse("@5m~+3m", context=Since, now=test_now)
  inspect(result.since, content="Some(Absolute(700000))")
  inspect(result.until, content="Some(Relative(880000, Ms(180000)))")
}

// ============================================================
// Mixed: @ on until side (Since context)
// ============================================================

///|
test "since: 5m~@3m → u=A(now-3m) s=R(u-5m)" {
  let result = @datetime.parse("5m~@3m", context=Since, now=test_now)
  inspect(result.until, content="Some(Absolute(820000))")
  inspect(result.since, content="Some(Relative(520000, Ms(-300000)))")
}

// ============================================================
// Both absolute (Since context)
// ============================================================

///|
test "since: @5m~@3m → both independent, s=A(now-5m) u=A(now-3m)" {
  let result = @datetime.parse("@5m~@3m", context=Since, now=test_now)
  inspect(result.since, content="Some(Absolute(700000))")
  inspect(result.until, content="Some(Absolute(820000))")
}

///|
test "since: @5m~@+3m → s=A(now-5m) u=A(now+3m)" {
  let result = @datetime.parse("@5m~@+3m", context=Since, now=test_now)
  inspect(result.since, content="Some(Absolute(700000))")
  inspect(result.until, content="Some(Absolute(1180000))")
}

// ============================================================
// Until context
// ============================================================

///|
test "until: 5m~3m → u=R(now-3m) s=R(u-5m)" {
  let result = @datetime.parse("5m~3m", context=Until, now=test_now)
  inspect(result.since, content="Some(Relative(520000, Ms(-300000)))")
  inspect(result.until, content="Some(Relative(820000, Ms(-180000)))")
}

// ============================================================
// Range context
// ============================================================

///|
test "range: 5m~3m → both independent from now" {
  let result = @datetime.parse("5m~3m", context=Range, now=test_now)
  inspect(result.since, content="Some(Relative(700000, Ms(-300000)))")
  inspect(result.until, content="Some(Relative(820000, Ms(-180000)))")
}

///|
test "range: 3m~5m → inverted (no swap)" {
  let result = @datetime.parse("3m~5m", context=Range, now=test_now)
  inspect(result.since, content="Some(Relative(820000, Ms(-180000)))")
  inspect(result.until, content="Some(Relative(700000, Ms(-300000)))")
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
  inspect(result.since, content="Some(Relative(1000000, Ms(0)))")
  inspect(result.until, content="Some(Relative(1000000, Ms(0)))")
}

// ============================================================
// ISO 8601 timestamp
// ============================================================

///|
test "since: 2024-01-01T00:00:00Z → Absolute" {
  let result = @datetime.parse(
    "2024-01-01T00:00:00Z", context=Since, now=test_now,
  )
  inspect(result.since, content="Some(Absolute(1704067200000))")
}

// ============================================================
// Re-serialization round-trip
// ============================================================

///|
test "re-serialize: Relative" {
  let ts : @datetime.TimeSpec = Relative(700_000L, Ms(-300_000L))
  inspect(ts.to_cli_string(), content="-5m")
}

///|
test "re-serialize: Absolute epoch 0" {
  let ts : @datetime.TimeSpec = Absolute(0L)
  inspect(ts.to_cli_string(), content="1970-01-01T00:00:00Z")
}

///|
test "re-serialize: Absolute epoch 2024-01-01" {
  let ts : @datetime.TimeSpec = Absolute(1_704_067_200_000L)
  inspect(ts.to_cli_string(), content="2024-01-01T00:00:00Z")
}

// ============================================================
// Timestamp with duration offset
// ============================================================

///|
test "since: timestamp-5m → Absolute(epoch-300_000)" {
  let result = @datetime.parse(
    "2024-01-01T12:00:00Z-5m", context=Since, now=test_now,
  )
  // 1704110400000 - 300000 = 1704110100000
  inspect(result.since, content="Some(Absolute(1704110100000))")
}

///|
test "since: timestamp+1h → Absolute(epoch+3_600_000)" {
  let result = @datetime.parse(
    "2024-01-01T12:00:00Z+1h", context=Since, now=test_now,
  )
  // 1704110400000 + 3600000 = 1704114000000
  inspect(result.since, content="Some(Absolute(1704114000000))")
}

// ============================================================
// Custom datetime parser
// ============================================================

///|
test "custom parser: override ISO parsing" {
  // Custom parser that returns a fixed epoch in ms
  fn parse_shifted(_input : String) -> Int64? {
    Some(1_704_070_800_000L) // 2024-01-01T01:00:00Z in ms
  }

  let result = @datetime.parse(
    "2024-01-01T00:00:00Z",
    context=Since,
    now=test_now,
    parse_datetime=parse_shifted,
  )
  inspect(result.since, content="Some(Absolute(1704070800000))")
}

// ============================================================
// Error cases
// ============================================================

///|
test "parse error: empty input" {
  let result : Result[@datetime.TimeRange, _] = try {
    Ok(@datetime.parse("", context=Since, now=test_now))
  } catch {
    e => Err(e)
  }
  assert_true(result is Err(_))
}

///|
test "parse error: invalid duration unit" {
  let result : Result[@datetime.TimeRange, _] = try {
    Ok(@datetime.parse("5x", context=Since, now=test_now))
  } catch {
    e => Err(e)
  }
  assert_true(result is Err(_))
}

///|
test "single value in Until context" {
  let result = @datetime.parse("5m", context=Until, now=test_now)
  assert_true(result.since is None)
  inspect(result.until, content="Some(Relative(700000, Ms(-300000)))")
}

///|
test "re-serialize: Relative positive" {
  let ts : @datetime.TimeSpec = Relative(1_300_000L, Ms(300_000L))
  inspect(ts.to_cli_string(), content="+5m")
}

///|
test "re-serialize: Relative zero" {
  let ts : @datetime.TimeSpec = Relative(1_000_000L, Ms(0L))
  inspect(ts.to_cli_string(), content="0s")
}

// ============================================================
// New features: decimal, underscore, sub-second units
// ============================================================

///|
test "since: 500ms" {
  let result = @datetime.parse("500ms", context=Since, now=test_now)
  // 500ms offset → epoch = 1000000 - 500 = 999500
  inspect(result.since, content="Some(Relative(999500, Ms(-500)))")
}

///|
test "since: 1.5h" {
  let result = @datetime.parse("1.5h", context=Since, now=test_now)
  // 1.5h = 5400s = 5_400_000ms → epoch = 1000000 - 5400000 = -4400000
  inspect(result.since, content="Some(Relative(-4400000, Ms(-5400000)))")
}

///|
test "since: 3_600s" {
  let result = @datetime.parse("3_600s", context=Since, now=test_now)
  // 3600s = 3_600_000ms → epoch = 1000000 - 3600000 = -2600000
  inspect(result.since, content="Some(Relative(-2600000, Ms(-3600000)))")
}

///|
test "re-serialize: Relative with sub-ms Duration" {
  let ts : @datetime.TimeSpec = Relative(1_000_000L, MsNs(-5L, 990_000))
  // total ns = -5 * 1_000_000 + 990_000 = -4_010_000 → abs = 4_010_000
  // abs: ms=4, ns=10_000 → 4ms10μs
  inspect(ts.to_cli_string(), content="-4ms10μs")
}
