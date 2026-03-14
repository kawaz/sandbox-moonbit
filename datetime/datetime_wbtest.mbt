// ============================================================
// Duration parsing
// ============================================================

///|
test "parse_duration: 5m" {
  inspect(parse_duration("5m", 0, 2), content="300")
}

///|
test "parse_duration: 1h30m" {
  inspect(parse_duration("1h30m", 0, 5), content="5400")
}

///|
test "parse_duration: 2d" {
  inspect(parse_duration("2d", 0, 2), content="172800")
}

///|
test "parse_duration: 90s" {
  inspect(parse_duration("90s", 0, 3), content="90")
}

///|
test "parse_duration: 1w" {
  inspect(parse_duration("1w", 0, 2), content="604800")
}

///|
test "parse_duration: 1h30m45s" {
  inspect(parse_duration("1h30m45s", 0, 8), content="5445")
}

///|
test "parse_duration: 0s" {
  inspect(parse_duration("0s", 0, 2), content="0")
}

///|
test "parse_duration: error - no unit" {
  let result : Result[Int64, _] = try { Ok(parse_duration("5", 0, 1)) } catch {
    e => Err(e)
  }
  assert_true(result is Err(_))
}

///|
test "parse_duration: error - unknown unit" {
  let result : Result[Int64, _] = try { Ok(parse_duration("5x", 0, 2)) } catch {
    e => Err(e)
  }
  assert_true(result is Err(_))
}

///|
test "parse_duration: error - empty" {
  let result : Result[Int64, _] = try { Ok(parse_duration("", 0, 0)) } catch {
    e => Err(e)
  }
  assert_true(result is Err(_))
}

///|
test "parse_duration: error - no digit before unit" {
  let result : Result[Int64, _] = try { Ok(parse_duration("m", 0, 1)) } catch {
    e => Err(e)
  }
  assert_true(result is Err(_))
}

// ============================================================
// Duration formatting
// ============================================================

///|
test "format_duration_unsigned: 0" {
  inspect(format_duration_unsigned(0L), content="0s")
}

///|
test "format_duration_unsigned: 300" {
  inspect(format_duration_unsigned(300L), content="5m")
}

///|
test "format_duration_unsigned: 5400" {
  inspect(format_duration_unsigned(5400L), content="1h30m")
}

///|
test "format_duration_unsigned: 86400" {
  inspect(format_duration_unsigned(86400L), content="1d")
}

///|
test "format_duration_unsigned: 90" {
  inspect(format_duration_unsigned(90L), content="1m30s")
}

///|
test "format_duration_unsigned: 604800 (1 week)" {
  inspect(format_duration_unsigned(604800L), content="1w")
}

///|
test "format_duration_unsigned: complex" {
  // 1w2d3h4m5s = 604800+172800+10800+240+5 = 788645
  inspect(format_duration_unsigned(788645L), content="1w2d3h4m5s")
}

// ============================================================
// format_offset (moved from blackbox, now private)
// ============================================================

///|
test "format_offset: basic durations" {
  inspect(format_offset(0L), content="0s")
  inspect(format_offset(-300L), content="-5m")
  inspect(format_offset(300L), content="+5m")
  inspect(format_offset(-3600L), content="-1h")
  inspect(format_offset(-5400L), content="-1h30m")
  inspect(format_offset(-86400L), content="-1d")
  inspect(format_offset(-90L), content="-1m30s")
}

// ============================================================
// ISO 8601 parsing
// ============================================================

///|
test "default_parse_datetime: date only" {
  inspect(default_parse_datetime("2024-01-01"), content="Some(1704067200)")
}

///|
test "default_parse_datetime: with time and Z" {
  inspect(
    default_parse_datetime("2024-01-01T12:00:00Z"),
    content="Some(1704110400)",
  )
}

///|
test "default_parse_datetime: with timezone +09:00" {
  inspect(
    default_parse_datetime("2024-01-01T00:00:00+09:00"),
    content="Some(1704034800)",
  )
}

///|
test "default_parse_datetime: with timezone -05:00" {
  inspect(
    default_parse_datetime("2024-01-01T00:00:00-05:00"),
    content="Some(1704085200)",
  )
}

///|
test "default_parse_datetime: compact timezone +0900" {
  inspect(
    default_parse_datetime("2024-01-01T00:00:00+0900"),
    content="Some(1704034800)",
  )
}

///|
test "default_parse_datetime: invalid" {
  inspect(default_parse_datetime("not-a-date"), content="None")
}

///|
test "default_parse_datetime: too short" {
  inspect(default_parse_datetime("2024"), content="None")
}

///|
test "default_parse_datetime: invalid month" {
  inspect(default_parse_datetime("2024-13-01"), content="None")
}

///|
test "default_parse_datetime: invalid day" {
  inspect(default_parse_datetime("2024-01-32"), content="None")
}

// ============================================================
// epoch_to_iso8601 round-trip
// ============================================================

///|
test "epoch_to_iso8601: epoch 0" {
  inspect(epoch_to_iso8601(0L), content="1970-01-01T00:00:00Z")
}

///|
test "epoch_to_iso8601: 2024-01-01" {
  inspect(epoch_to_iso8601(1704067200L), content="2024-01-01T00:00:00Z")
}

///|
test "epoch_to_iso8601: pre-1970" {
  // 1969-12-31T23:59:59Z = -1
  inspect(epoch_to_iso8601(-1L), content="1969-12-31T23:59:59Z")
}

///|
test "epoch_to_iso8601: leap year 2000-02-29" {
  // 2000-02-29T00:00:00Z = 951782400
  inspect(epoch_to_iso8601(951782400L), content="2000-02-29T00:00:00Z")
}

///|
test "epoch_to_iso8601 round-trip with parse" {
  let ts = "2024-06-15T14:30:00Z"
  guard default_parse_datetime(ts) is Some(epoch) else { panic() }
  inspect(epoch_to_iso8601(epoch), content=ts)
}

// ============================================================
// find_trailing_duration
// ============================================================

///|
test "find_trailing_duration: timestamp with -5m" {
  let input = "2024-01-01T12:00:00Z-5m"
  inspect(find_trailing_duration(input, 0, input.length()), content="20")
}

///|
test "find_trailing_duration: no duration" {
  let input = "2024-01-01T12:00:00Z"
  inspect(find_trailing_duration(input, 0, input.length()), content="20")
}

///|
test "find_trailing_duration: compound duration" {
  let input = "2024-01-01T12:00:00Z+1h30m"
  inspect(find_trailing_duration(input, 0, input.length()), content="20")
}

// ============================================================
// parse_part
// ============================================================

///|
test "parse_part: 5m" {
  guard parse_part("5m", 0, 2, default_parse_datetime) is Some(part) else {
    panic()
  }
  assert_false(part.is_absolute)
  assert_true(part.base_epoch is None)
  assert_eq(part.duration, 300L)
  assert_true(part.sign is Unsigned)
}

///|
test "parse_part: @5m" {
  guard parse_part("@5m", 0, 3, default_parse_datetime) is Some(part) else {
    panic()
  }
  assert_true(part.is_absolute)
  assert_true(part.base_epoch is None)
  assert_eq(part.duration, 300L)
  assert_true(part.sign is Unsigned)
}

///|
test "parse_part: -5m" {
  guard parse_part("-5m", 0, 3, default_parse_datetime) is Some(part) else {
    panic()
  }
  assert_false(part.is_absolute)
  assert_eq(part.duration, 300L)
  assert_true(part.sign is Minus)
}

///|
test "parse_part: +5m" {
  guard parse_part("+5m", 0, 3, default_parse_datetime) is Some(part) else {
    panic()
  }
  assert_false(part.is_absolute)
  assert_eq(part.duration, 300L)
  assert_true(part.sign is Plus)
}

///|
test "parse_part: @" {
  guard parse_part("@", 0, 1, default_parse_datetime) is Some(part) else {
    panic()
  }
  assert_true(part.is_absolute)
  assert_eq(part.duration, 0L)
}

///|
test "parse_part: empty" {
  assert_true(parse_part("", 0, 0, default_parse_datetime) is None)
}

///|
test "parse_part: timestamp with duration" {
  guard parse_part(
    "2024-01-01T12:00:00Z-5m", 0, 23, default_parse_datetime,
  ) is Some(part) else {
    panic()
  }
  assert_true(part.is_absolute)
  assert_true(part.base_epoch is Some(_))
  assert_eq(part.duration, 300L)
  assert_true(part.sign is Minus)
}

///|
test "parse_part: timestamp with +duration" {
  guard parse_part(
    "2024-01-01T12:00:00Z+1h", 0, 23, default_parse_datetime,
  ) is Some(part) else {
    panic()
  }
  assert_true(part.is_absolute)
  assert_true(part.base_epoch is Some(_))
  assert_eq(part.duration, 3600L)
  assert_true(part.sign is Plus)
}
