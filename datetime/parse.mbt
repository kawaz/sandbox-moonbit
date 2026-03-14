///| Internal error type for ISO 8601 parsing failures.
priv suberror Iso8601Fail

///| Default ISO 8601 parser (minimal: YYYY-MM-DDThh:mm:ssZ).
/// Returns epoch seconds or None.
/// Can be replaced via `parse_datetime~` parameter for custom formats.
pub fn default_parse_datetime(input : String) -> Int64? {
  Some(parse_iso8601(input) catch { _ => return None })
}

///| Parse ISO 8601 string, raising on any failure.
fn parse_iso8601(input : String) -> Int64 raise Iso8601Fail {
  let len = input.length()
  guard len >= 10 else { raise Iso8601Fail }
  let year = expect_digits(input, 0, 4)
  guard char_eq(input, 4, '-') else { raise Iso8601Fail }
  let month = expect_digits(input, 5, 7)
  guard char_eq(input, 7, '-') else { raise Iso8601Fail }
  let day = expect_digits(input, 8, 10)
  guard month >= 1 && month <= 12 && day >= 1 && day <= 31 else {
    raise Iso8601Fail
  }
  let mut hour = 0
  let mut minute = 0
  let mut second = 0
  let mut tz_offset_seconds = 0
  if len > 10 {
    guard char_eq(input, 10, 'T') || char_eq(input, 10, 't') else {
      raise Iso8601Fail
    }
    guard len >= 19 else { raise Iso8601Fail }
    hour = expect_digits(input, 11, 13)
    guard char_eq(input, 13, ':') else { raise Iso8601Fail }
    minute = expect_digits(input, 14, 16)
    guard char_eq(input, 16, ':') else { raise Iso8601Fail }
    second = expect_digits(input, 17, 19)
    if len > 19 {
      if char_eq(input, 19, 'Z') || char_eq(input, 19, 'z') {
        tz_offset_seconds = 0
      } else if char_eq(input, 19, '+') || char_eq(input, 19, '-') {
        let tz_sign = if char_eq(input, 19, '+') { 1 } else { -1 }
        if len >= 25 && char_eq(input, 22, ':') {
          let tz_h = expect_digits(input, 20, 22)
          let tz_m = expect_digits(input, 23, 25)
          tz_offset_seconds = tz_sign * (tz_h * 3600 + tz_m * 60)
        } else if len >= 24 {
          let tz_h = expect_digits(input, 20, 22)
          let tz_m = expect_digits(input, 22, 24)
          tz_offset_seconds = tz_sign * (tz_h * 3600 + tz_m * 60)
        } else {
          raise Iso8601Fail
        }
      }
    }
  }
  let epoch = datetime_to_epoch(year, month, day, hour, minute, second)
  epoch - tz_offset_seconds.to_int64()
}

///| Parse digits from input[start..end], raising on non-digit.
fn expect_digits(s : String, start : Int, end : Int) -> Int raise Iso8601Fail {
  let mut result = 0
  for i in start..<end {
    guard char_in_range(s, i, '0', '9') else { raise Iso8601Fail }
    result = result * 10 + (s[i].to_int() - 0x30)
  }
  result
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
  let mut y = year
  let mut m = month
  if m <= 2 {
    y = y - 1
    m = m + 12
  }
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
  for i in pos..<(pos + 4) {
    if not(char_in_range(input, i, '0', '9')) {
      return false
    }
  }
  char_eq(input, pos + 4, '-')
}

///| Parse one part (one side of `~`).
/// Input is `input[start..end]`.
fn parse_part(
  input : String,
  start : Int,
  end : Int,
  parse_dt : (String) -> Int64?
) -> RawPart? raise ParseError {
  if start >= end {
    return None
  }
  let mut pos = start
  // Check for @ prefix
  let mut is_absolute = false
  if char_eq(input, pos, '@') {
    is_absolute = true
    pos = pos + 1
    if pos >= end {
      return Some(
        { is_absolute: true, base_epoch: None, duration: 0L, sign: Unsigned },
      )
    }
  }
  // Check for timestamp literal
  if is_timestamp_prefix(input, pos, end) {
    let dur_start = find_trailing_duration(input, pos, end)
    let ts_str = input[pos:dur_start].to_string()
    let base_epoch = match parse_dt(ts_str) {
      Some(epoch) => epoch
      None =>
        raise ParseError("failed to parse datetime: '\{ts_str}'")
    }
    let mut duration : Int64 = 0
    let mut sign : Sign = Unsigned
    if dur_start < end {
      if char_eq(input, dur_start, '+') {
        sign = Plus
      } else if char_eq(input, dur_start, '-') {
        sign = Minus
      } else {
        raise ParseError("expected +/- after timestamp")
      }
      duration = parse_duration(input, dur_start + 1, end)
    }
    return Some(
      {
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
    if char_eq(input, pos, '+') {
      sign = Plus
      pos = pos + 1
    } else if char_eq(input, pos, '-') {
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
  Some({ is_absolute, base_epoch: None, duration, sign })
}

///| Compute epoch for a raw part resolved against a base time.
fn resolve_epoch(part : RawPart, base : Int64) -> Int64 {
  let actual_base = match part.base_epoch {
    Some(b) => b
    None => base
  }
  let signed_offset = match part.sign {
    Plus => part.duration
    _ => -part.duration
  }
  actual_base + signed_offset
}

///| Compute the stored offset value (signed, for re-serialization).
fn stored_offset(part : RawPart) -> Int64 {
  match part.sign {
    Plus => part.duration
    Minus | Unsigned => -part.duration
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
/// # Parameters
///
/// - `input` - The time spec string to parse
/// - `context~` - Parse context (Since/Until/Range)
/// - `now~` - Current time as Unix epoch seconds
/// - `swap~` - If true, swap since/until when since > until (default: false)
/// - `parse_datetime~` - Custom datetime parser (default: built-in ISO 8601)
pub fn parse(
  input : String,
  context~ : ParseContext,
  now~ : Int64,
  swap~ : Bool = false,
  parse_datetime~ : (String) -> Int64? = default_parse_datetime
) -> TimeRange raise ParseError {
  let parse_dt = parse_datetime
  let tilde = find_char(input, '~', 0, input.length())
  match tilde {
    None => {
      let part = parse_part(input, 0, input.length(), parse_dt)
      match part {
        None => raise ParseError("empty input")
        Some(raw) => {
          let epoch = resolve_epoch(raw, now)
          let ts = make_timespec(raw, epoch)
          match context {
            Since => { since: Some(ts), until: None }
            Until => { since: None, until: Some(ts) }
            Range => raise ParseError("range context requires ~ separator")
          }
        }
      }
    }
    Some(tilde_pos) => {
      let since_raw = parse_part(input, 0, tilde_pos, parse_dt)
      let until_raw = parse_part(
        input, tilde_pos + 1, input.length(), parse_dt,
      )
      resolve_range(since_raw, until_raw, context, now, swap)
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
  let empty_part : RawPart = {
    is_absolute: false,
    base_epoch: None,
    duration: 0L,
    sign: Unsigned,
  }
  let sr = match since_raw {
    Some(r) => r
    None => empty_part
  }
  let ur = match until_raw {
    Some(r) => r
    None => empty_part
  }
  let mixed = sr.is_absolute != ur.is_absolute
  let both_absolute = sr.is_absolute && ur.is_absolute
  let (since_ts, until_ts) = if mixed {
    resolve_mixed(sr, ur, now)
  } else if both_absolute {
    resolve_independent(sr, ur, now)
  } else {
    match ctx {
      Range => resolve_independent(sr, ur, now)
      Since => resolve_anchored(sr, ur, anchor_is_since=true, now)
      Until => resolve_anchored(sr, ur, anchor_is_since=false, now)
    }
  }
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
  { since: Some(final_since), until: Some(final_until) }
}

///|
fn timespec_epoch(ts : TimeSpec) -> Int64 {
  match ts {
    Absolute(epoch) => epoch
    Relative(epoch, _) => epoch
  }
}

///| Resolve mixed (one @, one non-@).
fn resolve_mixed(
  sr : RawPart,
  ur : RawPart,
  now : Int64
) -> (TimeSpec, TimeSpec) {
  if sr.is_absolute {
    let since_epoch = resolve_epoch(sr, now)
    let since_ts = make_timespec(sr, since_epoch)
    let until_epoch = resolve_non_anchor_mixed(
      ur, since_epoch, is_toward_future=true,
    )
    let until_ts = make_timespec(ur, until_epoch)
    (since_ts, until_ts)
  } else {
    let until_epoch = resolve_epoch(ur, now)
    let until_ts = make_timespec(ur, until_epoch)
    let since_epoch = resolve_non_anchor_mixed(
      sr, until_epoch, is_toward_future=false,
    )
    let since_ts = make_timespec(sr, since_epoch)
    (since_ts, until_ts)
  }
}

///| Resolve non-anchor in mixed mode.
fn resolve_non_anchor_mixed(
  part : RawPart,
  anchor_epoch : Int64,
  is_toward_future~ : Bool
) -> Int64 {
  match part.sign {
    Plus => anchor_epoch + part.duration
    Minus => anchor_epoch - part.duration
    Unsigned =>
      if is_toward_future {
        anchor_epoch + part.duration
      } else {
        anchor_epoch - part.duration
      }
  }
}

///| Resolve both-relative pair in Since/Until context.
fn resolve_anchored(
  sr : RawPart,
  ur : RawPart,
  anchor_is_since~ : Bool,
  now : Int64
) -> (TimeSpec, TimeSpec) {
  if anchor_is_since {
    let since_epoch = resolve_epoch(sr, now)
    let since_ts = make_timespec(sr, since_epoch)
    let until_epoch = since_epoch + ur.duration
    let until_ts = make_timespec(ur, until_epoch)
    (since_ts, until_ts)
  } else {
    let until_epoch = resolve_epoch(ur, now)
    let until_ts = make_timespec(ur, until_epoch)
    let since_epoch = until_epoch - sr.duration
    let since_ts = make_timespec(sr, since_epoch)
    (since_ts, until_ts)
  }
}

///| Resolve same-type pair independently.
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
  for i in start..<end {
    if char_eq(input, i, c) {
      return Some(i)
    }
  }
  None
}
