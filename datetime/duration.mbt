///| Parse a compound duration string like "5m", "1h30m", "2d", "90s".
/// Returns the total seconds (always >= 0).
/// Parses from `input[start..end]`.
fn parse_duration(input : String, start : Int, end : Int) -> Int64 raise ParseError {
  let mut pos = start
  let mut total : Int64 = 0
  let mut found = false
  while pos < end {
    let num_start = pos
    while pos < end && input[pos] >= '0' && input[pos] <= '9' {
      pos = pos + 1
    }
    if pos == num_start {
      raise ParseError(
        "expected digit at position \{pos}, got '\{input[pos]}'",
      )
    }
    let num = parse_int(input, num_start, pos)
    if pos >= end {
      raise ParseError("expected unit (s/m/h/d/w) after number")
    }
    let unit = input[pos]
    pos = pos + 1
    let multiplier : Int64 = match unit {
      's' => 1L
      'm' => 60L
      'h' => 3600L
      'd' => 86400L
      'w' => 604800L
      _ => raise ParseError("unknown unit '\{unit}', expected s/m/h/d/w")
    }
    total = total + num.to_int64() * multiplier
    found = true
  }
  if not(found) {
    raise ParseError("empty duration")
  }
  total
}

///| Parse an unsigned integer from input[start..end].
fn parse_int(s : String, start : Int, end : Int) -> Int {
  let mut result = 0
  for i = start; i < end; i = i + 1 {
    result = result * 10 + (s[i].to_int() - 0x30)
  }
  result
}

///| Format seconds as a human-readable duration string.
/// Examples: 300 → "5m", 3600 → "1h", 5400 → "1h30m", 0 → "0s"
fn format_duration_unsigned(seconds : Int64) -> String {
  let mut remaining = seconds
  let mut buf = StringBuilder::new()
  if remaining >= 604800L {
    let weeks = remaining / 604800L
    buf.write_string(weeks.to_string())
    buf.write_char('w')
    remaining = remaining % 604800L
  }
  if remaining >= 86400L {
    let days = remaining / 86400L
    buf.write_string(days.to_string())
    buf.write_char('d')
    remaining = remaining % 86400L
  }
  if remaining >= 3600L {
    let hours = remaining / 3600L
    buf.write_string(hours.to_string())
    buf.write_char('h')
    remaining = remaining % 3600L
  }
  if remaining >= 60L {
    let minutes = remaining / 60L
    buf.write_string(minutes.to_string())
    buf.write_char('m')
    remaining = remaining % 60L
  }
  if remaining > 0L || buf.is_empty() {
    buf.write_string(remaining.to_string())
    buf.write_char('s')
  }
  buf.to_string()
}

///| Format a signed offset as a CLI duration string.
/// Examples: -300 → "-5m", 300 → "+5m", 0 → "0s"
pub fn format_offset(offset : Int64) -> String {
  if offset == 0L {
    "0s"
  } else if offset < 0L {
    "-" + format_duration_unsigned(-offset)
  } else {
    "+" + format_duration_unsigned(offset)
  }
}

///| Check if position range contains a duration pattern: digits followed by unit char.
fn is_duration_char(c : Char) -> Bool {
  c == 's' || c == 'm' || c == 'h' || c == 'd' || c == 'w'
}

///| Find the start of trailing duration suffix in a string.
/// E.g., "2024-01-01T12:00:00Z-5m" → returns index of '-' before "5m".
/// Returns `end` if no trailing duration found.
fn find_trailing_duration(input : String, start : Int, end : Int) -> Int {
  // Scan backwards: expect (unit digit+ [+-])*
  let mut pos = end
  while pos > start {
    // Expect unit char
    if pos - 1 >= start && is_duration_char(input[pos - 1]) {
      pos = pos - 1
      // Expect digits
      let unit_pos = pos
      while pos > start && input[pos - 1] >= '0' && input[pos - 1] <= '9' {
        pos = pos - 1
      }
      if pos == unit_pos {
        // No digits before unit → not a duration suffix
        return end
      }
      // Expect optional +/- sign
      if pos > start && (input[pos - 1] == '+' || input[pos - 1] == '-') {
        pos = pos - 1
      }
      // Continue scanning for more duration components
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
