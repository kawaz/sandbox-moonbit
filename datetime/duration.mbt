///| Create Duration from total nanoseconds, normalizing to Ms or MsNs.
fn Duration::from_ns(total_ns : Int64) -> Duration {
  let ms = total_ns / 1_000_000L
  let ns = (total_ns % 1_000_000L).to_int()
  if ns == 0 {
    Ms(ms)
  } else if ns < 0 {
    MsNs(ms - 1L, ns + 1_000_000)
  } else {
    MsNs(ms, ns)
  }
}

///| Get the millisecond component.
pub fn Duration::to_ms(self : Duration) -> Int64 {
  match self {
    Ms(ms) => ms
    MsNs(ms, _) => ms
  }
}

///| Get the sub-millisecond nanosecond component (0..999_999).
pub fn Duration::sub_ms_ns(self : Duration) -> Int {
  match self {
    Ms(_) => 0
    MsNs(_, ns) => ns
  }
}

///| Convert to total nanoseconds.
pub fn Duration::to_total_ns(self : Duration) -> Int64 {
  match self {
    Ms(ms) => ms * 1_000_000L
    MsNs(ms, ns) => ms * 1_000_000L + ns.to_int64()
  }
}

///| Check if duration is zero.
fn Duration::is_zero(self : Duration) -> Bool {
  match self {
    Ms(ms) => ms == 0L
    MsNs(_, _) => false
  }
}

///| Check if duration is negative.
fn Duration::is_negative(self : Duration) -> Bool {
  self.to_ms() < 0L
}

///| Negate the duration.
fn Duration::negate(self : Duration) -> Duration {
  Duration::from_ns(-self.to_total_ns())
}

///| Absolute value.
fn Duration::abs(self : Duration) -> Duration {
  if self.is_negative() {
    self.negate()
  } else {
    self
  }
}

///| Parse a compound duration string like "5m", "1h30m", "500ms", "1.5h", "3_600s".
/// Returns Duration (always >= 0).
/// Parses from `input[start..end]`.
fn parse_duration(
  input : String,
  start : Int,
  end : Int
) -> Duration raise ParseError {
  let mut pos = start
  let mut total_ns : Int64 = 0
  let mut found = false
  while pos < end {
    // Parse number: digits with optional underscores
    let num_start = pos
    let mut has_digits = false
    while pos < end &&
      (char_in_range(input, pos, '0', '9') || char_eq(input, pos, '_')) {
      if char_in_range(input, pos, '0', '9') {
        has_digits = true
      }
      pos = pos + 1
    }
    if not(has_digits) {
      raise ParseError("expected digit at position \{pos}")
    }
    let whole = parse_int_sep(input, num_start, pos)
    // Optional fractional part
    let mut frac_num : Int64 = 0
    let mut frac_den : Int64 = 1
    if pos < end && char_eq(input, pos, '.') {
      pos = pos + 1
      let frac_start = pos
      while pos < end &&
        (char_in_range(input, pos, '0', '9') || char_eq(input, pos, '_')) {
        if char_in_range(input, pos, '0', '9') {
          frac_den = frac_den * 10L
        }
        pos = pos + 1
      }
      guard pos > frac_start else {
        raise ParseError("expected digit after decimal point")
      }
      frac_num = parse_int_sep(input, frac_start, pos)
    }
    guard pos < end else {
      raise ParseError("expected unit after number")
    }
    // Parse unit
    let (mult_ns, unit_len) = parse_unit_at(input, pos, end)
    pos = pos + unit_len
    // Accumulate nanoseconds
    total_ns = total_ns + whole * mult_ns + frac_num * mult_ns / frac_den
    found = true
  }
  guard found else { raise ParseError("empty duration") }
  Duration::from_ns(total_ns)
}

///| Parse unit at position, returning (nanosecond multiplier, char count).
fn parse_unit_at(
  input : String,
  pos : Int,
  end : Int
) -> (Int64, Int) raise ParseError {
  // Check 2-char units first
  if pos + 1 < end {
    let c0 = input[pos].to_int()
    let c1 = input[pos + 1].to_int()
    if c0 == 'm'.to_int() && c1 == 's'.to_int() {
      return (1_000_000L, 2)
    }
    if c0 == 'n'.to_int() && c1 == 's'.to_int() {
      return (1L, 2)
    }
    // μ (U+03BC), µ (U+00B5 micro sign), u (ASCII)
    if (c0 == 'u'.to_int() || c0 == 0x03BC || c0 == 0x00B5) &&
      c1 == 's'.to_int() {
      return (1_000L, 2)
    }
  }
  // Single char units
  guard pos < end else {
    raise ParseError("expected unit after number")
  }
  match input[pos].to_int() {
    c if c == 's'.to_int() => (1_000_000_000L, 1)
    c if c == 'm'.to_int() => (60_000_000_000L, 1)
    c if c == 'h'.to_int() => (3_600_000_000_000L, 1)
    c if c == 'd'.to_int() => (86_400_000_000_000L, 1)
    c if c == 'w'.to_int() => (604_800_000_000_000L, 1)
    _ => raise ParseError("unknown unit at position \{pos}")
  }
}

///| Parse unsigned integer, skipping underscore separators.
fn parse_int_sep(
  s : String,
  start : Int,
  end : Int
) -> Int64 raise ParseError {
  let mut result : Int64 = 0
  for i in start..<end {
    if not(char_eq(s, i, '_')) {
      let digit = s[i].to_int() - 0x30
      guard digit >= 0 && digit <= 9 else {
        raise ParseError("expected digit at position \{i}")
      }
      result = result * 10L + digit.to_int64()
      guard result >= 0L else {
        raise ParseError("number overflow at position \{i}")
      }
    }
  }
  result
}

///| Format a Duration as a human-readable string (uses absolute value).
/// Examples: Ms(300_000) → "5m", MsNs(2, 100_000) → "2ms100μs"
fn format_duration_unsigned(d : Duration) -> String {
  let abs_d = d.abs()
  let mut remaining_ms = abs_d.to_ms()
  let sub_ns = abs_d.sub_ms_ns()
  let buf = StringBuilder::new()
  let mut has_output = false
  // Weeks
  if remaining_ms >= 604_800_000L {
    buf.write_string((remaining_ms / 604_800_000L).to_string())
    buf.write_char('w')
    remaining_ms = remaining_ms % 604_800_000L
    has_output = true
  }
  // Days
  if remaining_ms >= 86_400_000L {
    buf.write_string((remaining_ms / 86_400_000L).to_string())
    buf.write_char('d')
    remaining_ms = remaining_ms % 86_400_000L
    has_output = true
  }
  // Hours
  if remaining_ms >= 3_600_000L {
    buf.write_string((remaining_ms / 3_600_000L).to_string())
    buf.write_char('h')
    remaining_ms = remaining_ms % 3_600_000L
    has_output = true
  }
  // Minutes
  if remaining_ms >= 60_000L {
    buf.write_string((remaining_ms / 60_000L).to_string())
    buf.write_char('m')
    remaining_ms = remaining_ms % 60_000L
    has_output = true
  }
  // Seconds
  if remaining_ms >= 1000L {
    buf.write_string((remaining_ms / 1000L).to_string())
    buf.write_char('s')
    remaining_ms = remaining_ms % 1000L
    has_output = true
  }
  // Milliseconds
  if remaining_ms > 0L {
    buf.write_string(remaining_ms.to_string())
    buf.write_string("ms")
    has_output = true
  }
  // Sub-ms: microseconds
  let mut remaining_ns = sub_ns
  if remaining_ns >= 1000 {
    buf.write_string((remaining_ns / 1000).to_string())
    buf.write_string("μs")
    remaining_ns = remaining_ns % 1000
    has_output = true
  }
  // Nanoseconds
  if remaining_ns > 0 {
    buf.write_string(remaining_ns.to_string())
    buf.write_string("ns")
    has_output = true
  }
  if not(has_output) {
    buf.write_string("0s")
  }
  buf.to_string()
}

///| Format a signed Duration as a CLI offset string.
/// Examples: Ms(-300_000) → "-5m", Ms(300_000) → "+5m", Ms(0) → "0s"
fn format_offset(d : Duration) -> String {
  if d.is_zero() {
    "0s"
  } else if d.is_negative() {
    "-" + format_duration_unsigned(d)
  } else {
    "+" + format_duration_unsigned(d)
  }
}

///| Find the start of trailing duration suffix in a string.
/// Handles all duration units including multi-char (ms, μs, us, ns).
/// Supports underscore separators and decimal points in numbers.
/// E.g., "2024-01-01T12:00:00Z-5m" → returns index of '-' before "5m".
/// Returns `end` if no trailing duration found.
fn find_trailing_duration(input : String, start : Int, end : Int) -> Int {
  let mut pos = end
  while pos > start {
    let c = input[pos - 1].to_int()
    if c == 's'.to_int() {
      // Could be s, ms, ns, μs, us
      pos = pos - 1
      if pos > start {
        let prev = input[pos - 1].to_int()
        if prev == 'm'.to_int() || prev == 'n'.to_int() ||
          prev == 'u'.to_int() || prev == 0x03BC || prev == 0x00B5 {
          pos = pos - 1
        }
      }
      let unit_pos = pos
      while pos > start && is_num_char(input, pos - 1) {
        pos = pos - 1
      }
      if pos == unit_pos {
        return end
      }
      if pos > start &&
        (char_eq(input, pos - 1, '+') || char_eq(input, pos - 1, '-')) {
        pos = pos - 1
      }
    } else if c == 'm'.to_int() || c == 'h'.to_int() || c == 'd'.to_int() ||
      c == 'w'.to_int() {
      pos = pos - 1
      let unit_pos = pos
      while pos > start && is_num_char(input, pos - 1) {
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
