// ============================================================
// Duration parsing (internal)
// ============================================================

///|
test "parse_duration: 5m" {
  inspect!(parse_duration!("5m", 0, 2), content="300")
}

///|
test "parse_duration: 1h30m" {
  inspect!(parse_duration!("1h30m", 0, 5), content="5400")
}

///|
test "parse_duration: 2d" {
  inspect!(parse_duration!("2d", 0, 2), content="172800")
}

///|
test "parse_duration: 90s" {
  inspect!(parse_duration!("90s", 0, 3), content="90")
}

///|
test "parse_duration: 1w" {
  inspect!(parse_duration!("1w", 0, 2), content="604800")
}

///|
test "parse_duration: 1h30m45s" {
  inspect!(parse_duration!("1h30m45s", 0, 7), content="5445")
}

///|
test "parse_duration: 0s" {
  inspect!(parse_duration!("0s", 0, 2), content="0")
}

// ============================================================
// Duration formatting (internal)
// ============================================================

///|
test "format_duration_unsigned: 0" {
  inspect!(format_duration_unsigned(0L), content="0s")
}

///|
test "format_duration_unsigned: 300" {
  inspect!(format_duration_unsigned(300L), content="5m")
}

///|
test "format_duration_unsigned: 5400" {
  inspect!(format_duration_unsigned(5400L), content="1h30m")
}

///|
test "format_duration_unsigned: 86400" {
  inspect!(format_duration_unsigned(86400L), content="1d")
}

///|
test "format_duration_unsigned: 90" {
  inspect!(format_duration_unsigned(90L), content="1m30s")
}

// ============================================================
// ISO 8601 parsing (internal)
// ============================================================

///|
test "default_parse_datetime: date only" {
  inspect!(
    default_parse_datetime("2024-01-01"),
    content="Some(1704067200)",
  )
}

///|
test "default_parse_datetime: with time and Z" {
  inspect!(
    default_parse_datetime("2024-01-01T12:00:00Z"),
    content="Some(1704110400)",
  )
}

///|
test "default_parse_datetime: with timezone +09:00" {
  // 2024-01-01T00:00:00+09:00 = 2023-12-31T15:00:00Z = 1704067200 - 9*3600
  let result = default_parse_datetime("2024-01-01T00:00:00+09:00")
  inspect!(result, content="Some(1704034800)")
}

///|
test "default_parse_datetime: invalid" {
  inspect!(default_parse_datetime("not-a-date"), content="None")
}

// ============================================================
// epoch_to_iso8601 round-trip
// ============================================================

///|
test "epoch_to_iso8601: epoch 0" {
  inspect!(epoch_to_iso8601(0L), content="1970-01-01T00:00:00Z")
}

///|
test "epoch_to_iso8601: 2024-01-01" {
  inspect!(
    epoch_to_iso8601(1704067200L),
    content="2024-01-01T00:00:00Z",
  )
}

// ============================================================
// find_trailing_duration (internal)
// ============================================================

///|
test "find_trailing_duration: timestamp with -5m" {
  let input = "2024-01-01T12:00:00Z-5m"
  let result = find_trailing_duration(input, 0, input.length())
  inspect!(result, content="20")
  // input[20..] = "-5m"
}

///|
test "find_trailing_duration: no duration" {
  let input = "2024-01-01T12:00:00Z"
  let result = find_trailing_duration(input, 0, input.length())
  inspect!(result, content="20")
  // returns end (no trailing duration)
}

///|
test "find_trailing_duration: compound duration" {
  let input = "2024-01-01T12:00:00Z+1h30m"
  let result = find_trailing_duration(input, 0, input.length())
  inspect!(result, content="20")
}

// ============================================================
// parse_part (internal)
// ============================================================

///|
test "parse_part: 5m" {
  let result = parse_part!("5m", 0, 2, 1000L, default_parse_datetime)
  inspect!(
    result,
    content="Some({is_absolute: false, base_epoch: None, duration: 300, sign: Unsigned})",
  )
}

///|
test "parse_part: @5m" {
  let result = parse_part!("@5m", 0, 3, 1000L, default_parse_datetime)
  inspect!(
    result,
    content="Some({is_absolute: true, base_epoch: None, duration: 300, sign: Unsigned})",
  )
}

///|
test "parse_part: -5m" {
  let result = parse_part!("-5m", 0, 3, 1000L, default_parse_datetime)
  inspect!(
    result,
    content="Some({is_absolute: false, base_epoch: None, duration: 300, sign: Minus})",
  )
}

///|
test "parse_part: +5m" {
  let result = parse_part!("+5m", 0, 3, 1000L, default_parse_datetime)
  inspect!(
    result,
    content="Some({is_absolute: false, base_epoch: None, duration: 300, sign: Plus})",
  )
}

///|
test "parse_part: @" {
  let result = parse_part!("@", 0, 1, 1000L, default_parse_datetime)
  inspect!(
    result,
    content="Some({is_absolute: true, base_epoch: None, duration: 0, sign: Unsigned})",
  )
}

///|
test "parse_part: empty" {
  let result = parse_part!("", 0, 0, 1000L, default_parse_datetime)
  inspect!(result, content="None")
}
