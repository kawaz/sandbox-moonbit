///| Default ISO 8601 parser (minimal: YYYY-MM-DDThh:mm:ssZ).
/// Returns epoch seconds or None.
/// Can be replaced via `ParseOptions.parse_datetime` for custom formats.
pub fn default_parse_datetime(input : String) -> Int64? {
  // Minimal ISO 8601: "YYYY-MM-DD" or "YYYY-MM-DDThh:mm:ss" with optional Z/offset
  let len = input.length()
  if len < 10 {
    return None
  }
  // Parse date part: YYYY-MM-DD
  let year = parse_int_opt(input, 0, 4)?
  if input[4] != '-' {
    return None
  }
  let month = parse_int_opt(input, 5, 7)?
  if input[7] != '-' {
    return None
  }
  let day = parse_int_opt(input, 8, 10)?
  if month < 1 || month > 12 || day < 1 || day > 31 {
    return None
  }
  let mut hour = 0
  let mut minute = 0
  let mut second = 0
  let mut tz_offset_seconds = 0
  if len > 10 {
    if input[10] != 'T' && input[10] != 't' {
      return None
    }
    if len < 19 {
      return None
    }
    hour = parse_int_opt(input, 11, 13)?
    if input[13] != ':' {
      return None
    }
    minute = parse_int_opt(input, 14, 16)?
    if input[16] != ':' {
      return None
    }
    second = parse_int_opt(input, 17, 19)?
    // Parse timezone
    if len > 19 {
      if input[19] == 'Z' || input[19] == 'z' {
        tz_offset_seconds = 0
      } else if input[19] == '+' || input[19] == '-' {
        // +HH:MM or +HHMM
        let tz_sign = if input[19] == '+' { 1 } else { -1 }
        if len >= 25 && input[22] == ':' {
          let tz_h = parse_int_opt(input, 20, 22)?
          let tz_m = parse_int_opt(input, 23, 25)?
          tz_offset_seconds = tz_sign * (tz_h * 3600 + tz_m * 60)
        } else if len >= 24 {
          let tz_h = parse_int_opt(input, 20, 22)?
          let tz_m = parse_int_opt(input, 22, 24)?
          tz_offset_seconds = tz_sign * (tz_h * 3600 + tz_m * 60)
        } else {
          return None
        }
      }
    }
  }
  // Convert to epoch seconds
  let epoch = datetime_to_epoch(year, month, day, hour, minute, second)
  Some(epoch - tz_offset_seconds.to_int64())
}

///| Parse int, returning None on failure.
fn parse_int_opt(s : String, start : Int, end : Int) -> Int? {
  let mut result = 0
  for i = start; i < end; i = i + 1 {
    let c = s[i]
    if c < '0' || c > '9' {
      return None
    }
    result = result * 10 + (c.to_int() - 0x30)
  }
  Some(result)
}

///| Convert date/time components to Unix epoch seconds.
fn datetime_to_epoch(
  year : Int,
  month : Int,
  day : Int,
  hour : Int,
  minute : Int,
  second : Int
) -> Int64 {
  // Days from 1970-01-01 to the given date
  let mut y = year
  let mut m = month
  if m <= 2 {
    y = y - 1
    m = m + 12
  }
  // Days from epoch using a standard formula
  let era = y / 400
  let yoe = y - era * 400
  let doy = (153 * (m - 3) + 2) / 5 + day - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  let days = era * 146097 + doe - 719468
  days.to_int64() * 86400L +
    hour.to_int64() * 3600L +
    minute.to_int64() * 60L +
    second.to_int64()
}

///| Check if input at position looks like a timestamp (YYYY-).
fn is_timestamp_prefix(input : String, pos : Int, end : Int) -> Bool {
  if pos + 5 > end {
    return false
  }
  for i = pos; i < pos + 4; i = i + 1 {
    if input[i] < '0' || input[i] > '9' {
      return false
    }
  }
  input[pos + 4] == '-'
}

///| Parse one part (one side of `~`).
/// Input is `input[start..end]`.
fn parse_part(
  input : String,
  start : Int,
  end : Int,
  now : Int64,
  parse_dt : (String) -> Int64?
) -> RawPart? raise ParseError {
  if start >= end {
    return None
  }
  let mut pos = start
  // Check for @ prefix
  let mut is_absolute = false
  if input[pos] == '@' {
    is_absolute = true
    pos = pos + 1
    if pos >= end {
      // Just "@" → Absolute(now, 0)
      return Some(
        RawPart::{ is_absolute: true, base_epoch: None, duration: 0L, sign: Unsigned },
      )
    }
  }
  // Check for timestamp literal
  if is_timestamp_prefix(input, pos, end) {
    // Find where the timestamp ends and duration suffix begins
    let dur_start = find_trailing_duration(input, pos, end)
    // Extract timestamp string
    let ts_str = input.substring(start=pos, end=dur_start)
    let base_epoch = match parse_dt(ts_str) {
      Some(epoch) => epoch
      None =>
        raise ParseError("failed to parse datetime: '\{ts_str}'")
    }
    // Parse trailing duration if present
    let mut duration : Int64 = 0
    let mut sign : Sign = Unsigned
    if dur_start < end {
      let c = input[dur_start]
      if c == '+' {
        sign = Plus
      } else if c == '-' {
        sign = Minus
      } else {
        raise ParseError(
          "expected +/- after timestamp, got '\{c}'",
        )
      }
      duration = parse_duration(input, dur_start + 1, end)
    }
    return Some(
      RawPart::{
        is_absolute: true,
        base_epoch: Some(base_epoch),
        duration,
        sign,
      },
    )
  }
  // Parse optional sign
  let mut sign : Sign = Unsigned
  if pos < end {
    let c = input[pos]
    if c == '+' {
      sign = Plus
      pos = pos + 1
    } else if c == '-' {
      sign = Minus
      pos = pos + 1
    }
  }
  // Parse duration
  let duration = if pos < end {
    parse_duration(input, pos, end)
  } else {
    0L
  }
  Some(
    RawPart::{ is_absolute, base_epoch: None, duration, sign },
  )
}

///| Compute epoch for a raw part resolved against a base time.
fn resolve_epoch(part : RawPart, base : Int64) -> Int64 {
  let actual_base = match part.base_epoch {
    Some(b) => b
    None => base
  }
  let signed_offset = match part.sign {
    Plus => part.duration
    _ => -part.duration // Unsigned defaults to minus
  }
  actual_base + signed_offset
}

///| Compute the stored offset value (signed, for re-serialization).
fn stored_offset(part : RawPart) -> Int64 {
  match part.sign {
    Plus => part.duration
    Minus => -part.duration
    Unsigned => -part.duration
  }
}

///| Build a TimeSpec from a raw part and a computed epoch.
fn make_timespec(part : RawPart, epoch : Int64) -> TimeSpec {
  if part.is_absolute {
    Absolute(epoch)
  } else {
    Relative(epoch, stored_offset(part))
  }
}

///| Main parse function.
///
/// Parses a time spec string into a `TimeRange`.
///
/// # Examples
///
/// ```
/// parse("5m~3m", { context: Since, now: 1000, swap: false, parse_datetime: default_parse_datetime })
/// ```
pub fn parse(input : String, options : ParseOptions) -> TimeRange raise ParseError {
  let now = options.now
  let ctx = options.context
  let parse_dt = options.parse_datetime
  // Find ~ separator
  let tilde = find_char(input, '~', 0, input.length())
  match tilde {
    None => {
      // Single value, no range
      let part = parse_part(input, 0, input.length(), now, parse_dt)
      match part {
        None => raise ParseError("empty input")
        Some(raw) => {
          let epoch = resolve_epoch(raw, now)
          let ts = make_timespec(raw, epoch)
          match ctx {
            Since => TimeRange::{ since: Some(ts), until: None }
            Until => TimeRange::{ since: None, until: Some(ts) }
            Range => raise ParseError("range context requires ~ separator")
          }
        }
      }
    }
    Some(tilde_pos) => {
      let since_raw = parse_part(input, 0, tilde_pos, now, parse_dt)
      let until_raw = parse_part(
        input, tilde_pos + 1, input.length(), now, parse_dt,
      )
      resolve_range(since_raw, until_raw, ctx, now, options.swap)
    }
  }
}

///| Resolve a range from two raw parts according to anchor and sign rules.
fn resolve_range(
  since_raw : RawPart?,
  until_raw : RawPart?,
  ctx : ParseContext,
  now : Int64,
  swap : Bool
) -> TimeRange {
  // Handle empty parts (e.g., "~" → both empty → both Relative(now, 0))
  let sr = match since_raw {
    Some(r) => r
    None =>
      RawPart::{ is_absolute: false, base_epoch: None, duration: 0L, sign: Unsigned }
  }
  let ur = match until_raw {
    Some(r) => r
    None =>
      RawPart::{ is_absolute: false, base_epoch: None, duration: 0L, sign: Unsigned }
  }
  // Determine the anchor relationship
  let mixed = sr.is_absolute != ur.is_absolute
  let both_absolute = sr.is_absolute && ur.is_absolute
  let both_relative = not(sr.is_absolute) && not(ur.is_absolute)
  // Resolve based on rules:
  // 1. Mixed (@/non-@): absolute side is anchor, semantic defaults apply
  // 2. Both absolute (@@): resolve independently against now (no anchor relationship)
  // 3. Both relative: depends on context
  //    - Range: independent (no semantic defaults)
  //    - Since/Until: anchored (sign is cosmetic, direction forced by s<=u)
  let (since_ts, until_ts) = if mixed {
    resolve_mixed(sr, ur, ctx, now)
  } else if both_absolute {
    // Both @: each resolves independently against now with default minus.
    // "Option side resolves first, other resolves by semantic default"
    // → in practice, both use default minus independently.
    resolve_independent(sr, ur, now)
  } else {
    // Both relative
    match ctx {
      Range => resolve_independent(sr, ur, now)
      Since => resolve_anchored(sr, ur, anchor_is_since=true, now)
      Until => resolve_anchored(sr, ur, anchor_is_since=false, now)
    }
  }
  // Optionally swap if since > until
  let (final_since, final_until) = if swap {
    let s_epoch = timespec_epoch(since_ts)
    let u_epoch = timespec_epoch(until_ts)
    if s_epoch > u_epoch {
      (until_ts, since_ts)
    } else {
      (since_ts, until_ts)
    }
  } else {
    (since_ts, until_ts)
  }
  TimeRange::{ since: Some(final_since), until: Some(final_until) }
}

///| Extract epoch from a TimeSpec.
fn timespec_epoch(ts : TimeSpec) -> Int64 {
  match ts {
    Absolute(epoch) => epoch
    Relative(epoch, _) => epoch
  }
}

///| Resolve mixed (one absolute, one relative).
/// Absolute side is anchor. Semantic defaults apply for unsigned non-anchor.
fn resolve_mixed(
  sr : RawPart,
  ur : RawPart,
  ctx : ParseContext,
  now : Int64
) -> (TimeSpec, TimeSpec) {
  if sr.is_absolute {
    // Since is absolute (anchor)
    let since_epoch = resolve_epoch(sr, now)
    let since_ts = make_timespec(sr, since_epoch)
    // Until is relative to since
    let until_epoch = resolve_non_anchor_mixed(
      ur, since_epoch, is_toward_future=true,
    )
    let until_ts = make_timespec(ur, until_epoch)
    (since_ts, until_ts)
  } else {
    // Until is absolute (anchor)
    let until_epoch = resolve_epoch(ur, now)
    let until_ts = make_timespec(ur, until_epoch)
    // Since is relative to until
    let since_epoch = resolve_non_anchor_mixed(
      sr, until_epoch, is_toward_future=false,
    )
    let since_ts = make_timespec(sr, since_epoch)
    (since_ts, until_ts)
  }
}

///| Resolve non-anchor in mixed mode.
/// Explicit sign is respected. Unsigned defaults to context direction.
fn resolve_non_anchor_mixed(
  part : RawPart,
  anchor_epoch : Int64,
  is_toward_future~ : Bool
) -> Int64 {
  match part.sign {
    Plus => anchor_epoch + part.duration
    Minus => anchor_epoch - part.duration
    Unsigned =>
      // Semantic default: toward the other end (future for since→until, past for until→since)
      if is_toward_future {
        anchor_epoch + part.duration
      } else {
        anchor_epoch - part.duration
      }
  }
}

///| Resolve both-relative pair in Since/Until context.
/// Anchor is resolved first against now.
/// Non-anchor's sign is cosmetic — direction is always inward (s<=u).
fn resolve_anchored(
  sr : RawPart,
  ur : RawPart,
  anchor_is_since~ : Bool,
  now : Int64
) -> (TimeSpec, TimeSpec) {
  if anchor_is_since {
    let since_epoch = resolve_epoch(sr, now)
    let since_ts = make_timespec(sr, since_epoch)
    // Non-anchor: always + (toward future) to satisfy s<=u
    let until_epoch = since_epoch + ur.duration
    let until_ts = make_timespec(ur, until_epoch)
    (since_ts, until_ts)
  } else {
    let until_epoch = resolve_epoch(ur, now)
    let until_ts = make_timespec(ur, until_epoch)
    // Non-anchor: always - (toward past) to satisfy s<=u
    let since_epoch = until_epoch - sr.duration
    let since_ts = make_timespec(sr, since_epoch)
    (since_ts, until_ts)
  }
}

///| Resolve same-type pair in Range context (no semantic defaults).
/// Each side resolved independently against now.
fn resolve_independent(
  sr : RawPart,
  ur : RawPart,
  now : Int64
) -> (TimeSpec, TimeSpec) {
  let since_epoch = resolve_epoch(sr, now)
  let since_ts = make_timespec(sr, since_epoch)
  let until_epoch = resolve_epoch(ur, now)
  let until_ts = make_timespec(ur, until_epoch)
  (since_ts, until_ts)
}

///| Find first occurrence of a character in input[start..end].
fn find_char(input : String, c : Char, start : Int, end : Int) -> Int? {
  for i = start; i < end; i = i + 1 {
    if input[i] == c {
      return Some(i)
    }
  }
  None
}

///| Create default parse options.
pub fn default_options(now : Int64) -> ParseOptions {
  {
    context: Since,
    now,
    swap: false,
    parse_datetime: default_parse_datetime,
  }
}
