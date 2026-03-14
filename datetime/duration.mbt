///| Parse a compound duration string like "5m", "1h30m", "2d", "90s".
/// Returns the total seconds (always >= 0).
/// Parses from `input[start..end]`.
fn parse_duration(input : String, start : Int, end : Int) -> Int64 raise ParseError {
  let mut pos = start
  let mut total : Int64 = 0
  let mut found = false
  while pos < end {
    let num_start = pos
    while pos < end && char_in_range(input, pos, '0', '9') {
      pos = pos + 1
    }
    if pos == num_start {
      raise ParseError(
        "expected digit at position \{pos}",
      )
    }
    let num = parse_int(input, num_start, pos)
    guard pos < end else {
      raise ParseError("expected unit (s/m/h/d/w) after number")
    }
    let multiplier : Int64 = match input[pos].to_int() {
      c if c == 's'.to_int() => 1L
      c if c == 'm'.to_int() => 60L
      c if c == 'h'.to_int() => 3600L
      c if c == 'd'.to_int() => 86400L
      c if c == 'w'.to_int() => 604800L
      _ => raise ParseError("unknown unit, expected s/m/h/d/w")
    }
    pos = pos + 1
    total = total + num * multiplier
    found = true
  }
  guard found else { raise ParseError("empty duration") }
  total
}

///| Parse an unsigned integer from input[start..end].
/// Returns Int64 to avoid overflow for large numbers.
fn parse_int(s : String, start : Int, end : Int) -> Int64 raise ParseError {
  let mut result : Int64 = 0
  for i in start..<end {
    let digit = s[i].to_int() - 0x30
    guard digit >= 0 && digit <= 9 else {
      raise ParseError("expected digit at position \{i}")
    }
    result = result * 10L + digit.to_int64()
    guard result >= 0L else {
      raise ParseError("number overflow at position \{i}")
    }
  }
  result
}

///| Format seconds as a human-readable duration string.
/// Examples: 300 → "5m", 3600 → "1h", 5400 → "1h30m", 0 → "0s"
fn format_duration_unsigned(seconds : Int64) -> String {
  let mut remaining = seconds
  let buf = StringBuilder::new()
  let mut has_output = false
  if remaining >= 604800L {
    buf.write_string((remaining / 604800L).to_string())
    buf.write_char('w')
    remaining = remaining % 604800L
    has_output = true
  }
  if remaining >= 86400L {
    buf.write_string((remaining / 86400L).to_string())
    buf.write_char('d')
    remaining = remaining % 86400L
    has_output = true
  }
  if remaining >= 3600L {
    buf.write_string((remaining / 3600L).to_string())
    buf.write_char('h')
    remaining = remaining % 3600L
    has_output = true
  }
  if remaining >= 60L {
    buf.write_string((remaining / 60L).to_string())
    buf.write_char('m')
    remaining = remaining % 60L
    has_output = true
  }
  if remaining > 0L || not(has_output) {
    buf.write_string(remaining.to_string())
    buf.write_char('s')
  }
  buf.to_string()
}

///| Format a signed offset as a CLI duration string.
/// Examples: -300 → "-5m", 300 → "+5m", 0 → "0s"
fn format_offset(offset : Int64) -> String {
  if offset == 0L {
    "0s"
  } else if offset < 0L {
    "-" + format_duration_unsigned(-offset)
  } else {
    "+" + format_duration_unsigned(offset)
  }
}

///| Check if char at position is a duration unit (s/m/h/d/w).
fn is_duration_char_at(s : String, pos : Int) -> Bool {
  guard pos >= 0 && pos < s.length() else { return false }
  let c = s[pos].to_int()
  c == 's'.to_int() ||
  c == 'm'.to_int() ||
  c == 'h'.to_int() ||
  c == 'd'.to_int() ||
  c == 'w'.to_int()
}

///| Find the start of trailing duration suffix in a string.
/// E.g., "2024-01-01T12:00:00Z-5m" → returns index of '-' before "5m".
/// Returns `end` if no trailing duration found.
fn find_trailing_duration(input : String, start : Int, end : Int) -> Int {
  let mut pos = end
  while pos > start {
    if pos - 1 >= start && is_duration_char_at(input, pos - 1) {
      pos = pos - 1
      let unit_pos = pos
      while pos > start && char_in_range(input, pos - 1, '0', '9') {
        pos = pos - 1
      }
      if pos == unit_pos {
        return end
      }
      if pos > start &&
        (char_eq(input, pos - 1, '+') || char_eq(input, pos - 1, '-')) {
        pos = pos - 1
      }
    } else {
      break
    }
  }
  if pos < end {
    pos
  } else {
    end
  }
}
