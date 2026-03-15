// ============================================================
// Duration parsing (values are now Duration, epoch in ms)
// ============================================================

///|
test "parse_duration: 5m" {
  inspect(parse_duration("5m", 0, 2), content="Ms(300000)")
}

///|
test "parse_duration: 1h30m" {
  inspect(parse_duration("1h30m", 0, 5), content="Ms(5400000)")
}

///|
test "parse_duration: 2d" {
  inspect(parse_duration("2d", 0, 2), content="Ms(172800000)")
}

///|
test "parse_duration: 90s" {
  inspect(parse_duration("90s", 0, 3), content="Ms(90000)")
}

///|
test "parse_duration: 1w" {
  inspect(parse_duration("1w", 0, 2), content="Ms(604800000)")
}

///|
test "parse_duration: 1h30m45s" {
  inspect(parse_duration("1h30m45s", 0, 8), content="Ms(5445000)")
}

///|
test "parse_duration: 0s" {
  inspect(parse_duration("0s", 0, 2), content="Ms(0)")
}

///|
test "parse_duration: error - no unit" {
  let result : Result[Duration, _] = try {
    Ok(parse_duration("5", 0, 1))
  } catch {
    e => Err(e)
  }
  assert_true(result is Err(_))
}

///|
test "parse_duration: error - unknown unit" {
  let result : Result[Duration, _] = try {
    Ok(parse_duration("5x", 0, 2))
  } catch {
    e => Err(e)
  }
  assert_true(result is Err(_))
}

///|
test "parse_duration: error - empty" {
  let result : Result[Duration, _] = try {
    Ok(parse_duration("", 0, 0))
  } catch {
    e => Err(e)
  }
  assert_true(result is Err(_))
}

///|
test "parse_duration: error - no digit before unit" {
  let result : Result[Duration, _] = try {
    Ok(parse_duration("m", 0, 1))
  } catch {
    e => Err(e)
  }
  assert_true(result is Err(_))
}

// ============================================================
// New: decimal, underscore, sub-second units
// ============================================================

///|
test "parse_duration: 500ms" {
  inspect(parse_duration("500ms", 0, 5), content="Ms(500)")
}

///|
test "parse_duration: 100us" {
  // 100μs = 100_000 ns → MsNs(0, 100000)
  inspect(parse_duration("100us", 0, 5), content="MsNs(0, 100000)")
}

///|
test "parse_duration: 500ns" {
  inspect(parse_duration("500ns", 0, 5), content="MsNs(0, 500)")
}

///|
test "parse_duration: 1.5h" {
  // 1.5h = 5400s = 5_400_000ms
  inspect(parse_duration("1.5h", 0, 4), content="Ms(5400000)")
}

///|
test "parse_duration: 1.5s" {
  // 1.5s = 1_500_000_000 ns = 1500ms
  inspect(parse_duration("1.5s", 0, 4), content="Ms(1500)")
}

///|
test "parse_duration: 0.5m" {
  // 0.5m = 30s = 30_000ms
  inspect(parse_duration("0.5m", 0, 4), content="Ms(30000)")
}

///|
test "parse_duration: 1.2ms900us" {
  // 1.2ms = 1_200_000 ns, 900us = 900_000 ns
  // total = 2_100_000 ns → MsNs(2, 100000)
  inspect(parse_duration("1.2ms900us", 0, 10), content="MsNs(2, 100000)")
}

///|
test "parse_duration: 3_600s (underscore)" {
  inspect(parse_duration("3_600s", 0, 6), content="Ms(3600000)")
}

///|
test "parse_duration: 3_600_000ms (underscore)" {
  inspect(parse_duration("3_600_000ms", 0, 11), content="Ms(3600000)")
}

///|
test "parse_duration: 1_000_000us (underscore)" {
  // 1_000_000 μs = 1s = 1000ms
  inspect(parse_duration("1_000_000us", 0, 11), content="Ms(1000)")
}

// ============================================================
// Duration formatting
// ============================================================

///|
test "format_duration_unsigned: 0" {
  inspect(format_duration_unsigned(Ms(0L)), content="0s")
}

///|
test "format_duration_unsigned: 5m" {
  inspect(format_duration_unsigned(Ms(300_000L)), content="5m")
}

///|
test "format_duration_unsigned: 1h30m" {
  inspect(format_duration_unsigned(Ms(5_400_000L)), content="1h30m")
}

///|
test "format_duration_unsigned: 1d" {
  inspect(format_duration_unsigned(Ms(86_400_000L)), content="1d")
}

///|
test "format_duration_unsigned: 1m30s" {
  inspect(format_duration_unsigned(Ms(90_000L)), content="1m30s")
}

///|
test "format_duration_unsigned: 1w" {
  inspect(format_duration_unsigned(Ms(604_800_000L)), content="1w")
}

///|
test "format_duration_unsigned: complex" {
  // 1w2d3h4m5s = (604800+172800+10800+240+5)s = 788645s = 788_645_000ms
  inspect(format_duration_unsigned(Ms(788_645_000L)), content="1w2d3h4m5s")
}

///|
test "format_duration_unsigned: 500ms" {
  inspect(format_duration_unsigned(Ms(500L)), content="500ms")
}

///|
test "format_duration_unsigned: sub-ms μs" {
  inspect(
    format_duration_unsigned(MsNs(0L, 100_000)),
    content="100μs",
  )
}

///|
test "format_duration_unsigned: sub-ms ns" {
  inspect(format_duration_unsigned(MsNs(0L, 500)), content="500ns")
}

///|
test "format_duration_unsigned: ms + μs" {
  inspect(
    format_duration_unsigned(MsNs(2L, 100_000)),
    content="2ms100μs",
  )
}

///|
test "format_duration_unsigned: 1s500ms" {
  inspect(format_duration_unsigned(Ms(1500L)), content="1s500ms")
}

// ============================================================
// format_offset
// ============================================================

///|
test "format_offset: basic durations" {
  inspect(format_offset(Ms(0L)), content="0s")
  inspect(format_offset(Ms(-300_000L)), content="-5m")
  inspect(format_offset(Ms(300_000L)), content="+5m")
  inspect(format_offset(Ms(-3_600_000L)), content="-1h")
  inspect(format_offset(Ms(-5_400_000L)), content="-1h30m")
  inspect(format_offset(Ms(-86_400_000L)), content="-1d")
  inspect(format_offset(Ms(-90_000L)), content="-1m30s")
}

///|
test "format_offset: sub-ms" {
  inspect(format_offset(MsNs(0L, 500)), content="+500ns")
  inspect(format_offset(MsNs(-1L, 990_000)), content="-10μs")
}

// ============================================================
// ISO 8601 parsing (returns ms)
// ============================================================

///|
test "default_parse_datetime: date only" {
  inspect(default_parse_datetime("2024-01-01"), content="Some(1704067200000)")
}

///|
test "default_parse_datetime: with time and Z" {
  inspect(
    default_parse_datetime("2024-01-01T12:00:00Z"),
    content="Some(1704110400000)",
  )
}

///|
test "default_parse_datetime: with timezone +09:00" {
  inspect(
    default_parse_datetime("2024-01-01T00:00:00+09:00"),
    content="Some(1704034800000)",
  )
}

///|
test "default_parse_datetime: with timezone -05:00" {
  inspect(
    default_parse_datetime("2024-01-01T00:00:00-05:00"),
    content="Some(1704085200000)",
  )
}

///|
test "default_parse_datetime: compact timezone +0900" {
  inspect(
    default_parse_datetime("2024-01-01T00:00:00+0900"),
    content="Some(1704034800000)",
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
// epoch_to_iso8601 round-trip (ms input)
// ============================================================

///|
test "epoch_to_iso8601: epoch 0" {
  inspect(epoch_to_iso8601(0L), content="1970-01-01T00:00:00Z")
}

///|
test "epoch_to_iso8601: 2024-01-01" {
  inspect(epoch_to_iso8601(1_704_067_200_000L), content="2024-01-01T00:00:00Z")
}

///|
test "epoch_to_iso8601: pre-1970" {
  // -1000ms = -1 second → 1969-12-31T23:59:59Z
  inspect(epoch_to_iso8601(-1000L), content="1969-12-31T23:59:59Z")
}

///|
test "epoch_to_iso8601: leap year 2000-02-29" {
  inspect(epoch_to_iso8601(951_782_400_000L), content="2000-02-29T00:00:00Z")
}

///|
test "epoch_to_iso8601: with sub-second ms" {
  // 500ms after epoch 0
  inspect(epoch_to_iso8601(500L), content="1970-01-01T00:00:00.500Z")
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

///|
test "find_trailing_duration: with ms suffix" {
  let input = "2024-01-01T12:00:00Z-500ms"
  inspect(find_trailing_duration(input, 0, input.length()), content="20")
}

///|
test "find_trailing_duration: with ns suffix" {
  let input = "2024-01-01T12:00:00Z+100ns"
  inspect(find_trailing_duration(input, 0, input.length()), content="20")
}

///|
test "find_trailing_duration: with underscore in number" {
  let input = "2024-01-01T12:00:00Z-3_600s"
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
  assert_eq(part.duration, Ms(300_000L))
  assert_true(part.sign is Unsigned)
}

///|
test "parse_part: @5m" {
  guard parse_part("@5m", 0, 3, default_parse_datetime) is Some(part) else {
    panic()
  }
  assert_true(part.is_absolute)
  assert_true(part.base_epoch is None)
  assert_eq(part.duration, Ms(300_000L))
  assert_true(part.sign is Unsigned)
}

///|
test "parse_part: -5m" {
  guard parse_part("-5m", 0, 3, default_parse_datetime) is Some(part) else {
    panic()
  }
  assert_false(part.is_absolute)
  assert_eq(part.duration, Ms(300_000L))
  assert_true(part.sign is Minus)
}

///|
test "parse_part: +5m" {
  guard parse_part("+5m", 0, 3, default_parse_datetime) is Some(part) else {
    panic()
  }
  assert_false(part.is_absolute)
  assert_eq(part.duration, Ms(300_000L))
  assert_true(part.sign is Plus)
}

///|
test "parse_part: @" {
  guard parse_part("@", 0, 1, default_parse_datetime) is Some(part) else {
    panic()
  }
  assert_true(part.is_absolute)
  assert_eq(part.duration, Ms(0L))
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
  assert_eq(part.duration, Ms(300_000L))
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
  assert_eq(part.duration, Ms(3_600_000L))
  assert_true(part.sign is Plus)
}

// ============================================================
// Duration construction and methods
// ============================================================

///|
test "Duration::from_ns normalization" {
  // Simple ms
  inspect(Duration::from_ns(5_000_000L), content="Ms(5)")
  // ms + sub-ms
  inspect(Duration::from_ns(2_100_000L), content="MsNs(2, 100000)")
  // Just ns
  inspect(Duration::from_ns(500L), content="MsNs(0, 500)")
  // Zero
  inspect(Duration::from_ns(0L), content="Ms(0)")
  // Negative
  inspect(Duration::from_ns(-5_010_000L), content="MsNs(-6, 990000)")
}

///|
test "Duration::negate" {
  inspect(Ms(5L).negate(), content="Ms(-5)")
  inspect(MsNs(2L, 100_000).negate(), content="MsNs(-3, 900000)")
  inspect(Ms(0L).negate(), content="Ms(0)")
}

///|
test "Duration::abs" {
  inspect(Ms(-5L).abs(), content="Ms(5)")
  inspect(MsNs(-3L, 900_000).abs(), content="MsNs(2, 100000)")
  inspect(Ms(5L).abs(), content="Ms(5)")
}

///|
test "parse_duration: 1_000.5s (underscore + decimal)" {
  inspect(parse_duration("1_000.5s", 0, 8), content="Ms(1000500)")
}

///|
test "parse_duration: 1_000.5_0s (underscore in both parts)" {
  inspect(parse_duration("1_000.5_0s", 0, 10), content="Ms(1000500)")
}
