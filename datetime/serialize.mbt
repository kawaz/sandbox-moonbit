///| Re-serialize a TimeSpec as a CLI-friendly string.
///
/// - `Absolute` → ISO 8601 timestamp (e.g., `2025-03-15T00:56:14Z`)
/// - `Relative` → signed duration (e.g., `-5m`, `+3m`, `0s`)
pub fn TimeSpec::to_cli_string(self : TimeSpec) -> String {
  match self {
    Absolute(epoch) => epoch_to_iso8601(epoch)
    Relative(_, offset) => format_offset(offset)
  }
}

///| Convert epoch seconds to ISO 8601 UTC string.
fn epoch_to_iso8601(epoch : Int64) -> String {
  let mut seconds = epoch
  let mut days = seconds / 86400L
  seconds = seconds % 86400L
  if seconds < 0L {
    seconds = seconds + 86400L
    days = days - 1L
  }
  let hour = (seconds / 3600L).to_int()
  seconds = seconds % 3600L
  let minute = (seconds / 60L).to_int()
  let second = (seconds % 60L).to_int()
  let (year, month, day) = days_to_civil(days)
  let buf = StringBuilder::new()
  buf.write_string(pad4(year))
  buf.write_char('-')
  buf.write_string(pad2(month))
  buf.write_char('-')
  buf.write_string(pad2(day))
  buf.write_char('T')
  buf.write_string(pad2(hour))
  buf.write_char(':')
  buf.write_string(pad2(minute))
  buf.write_char(':')
  buf.write_string(pad2(second))
  buf.write_char('Z')
  buf.to_string()
}

///| Convert days since Unix epoch to (year, month, day).
fn days_to_civil(days : Int64) -> (Int, Int, Int) {
  let z = days + 719468L
  let era = (if z >= 0L { z } else { z - 146096L }) / 146097L
  let doe = z - era * 146097L
  let yoe = (doe - doe / 1460L + doe / 36524L - doe / 146096L) / 365L
  let y = yoe + era * 400L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
  let mp = (5L * doy + 2L) / 153L
  let d = doy - (153L * mp + 2L) / 5L + 1L
  let m = mp + (if mp < 10L { 3L } else { -9L })
  let year = y + (if m <= 2L { 1L } else { 0L })
  (year.to_int(), m.to_int(), d.to_int())
}

///|
fn pad2(n : Int) -> String {
  if n < 10 {
    "0" + n.to_string()
  } else {
    n.to_string()
  }
}

///|
fn pad4(n : Int) -> String {
  if n < 10 {
    "000" + n.to_string()
  } else if n < 100 {
    "00" + n.to_string()
  } else if n < 1000 {
    "0" + n.to_string()
  } else {
    n.to_string()
  }
}
