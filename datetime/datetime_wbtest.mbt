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
test "default_parse_datetime: invalid" {
  inspect(default_parse_datetime("not-a-date"), content="None")
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
