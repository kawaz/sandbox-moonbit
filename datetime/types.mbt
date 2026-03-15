///| Duration with millisecond + optional sub-millisecond nanosecond precision.
///
/// - `Ms(ms)` → millisecond precision only
/// - `MsNs(ms, ns)` → milliseconds + sub-ms nanoseconds (ns: 0..999_999)
pub(all) enum Duration {
  Ms(Int64)
  MsNs(Int64, Int)
} derive(Eq)

///| A time specification - either absolute (pinned to a moment) or relative (sliding window).
///
/// - `Absolute(epoch_ms)` → re-serializes as ISO 8601 timestamp
/// - `Relative(epoch_ms, offset)` → re-serializes as signed duration
pub(all) enum TimeSpec {
  Absolute(Int64)
  Relative(Int64, Duration)
} derive(Eq)

///| A parsed time range (since/until pair).
/// Either side can be `None` if not specified.
pub(all) struct TimeRange {
  since : TimeSpec?
  until : TimeSpec?
} derive(Eq)

///| Parse context determines anchor priority and semantic sign defaults.
pub(all) enum ParseContext {
  /// `--since`: since is anchor for same-type pairs
  Since
  /// `--until`: until is anchor for same-type pairs
  Until
  /// `--time-range`: no semantic defaults for same-type pairs
  Range
} derive(Eq, Show)

///| Parse error with description.
pub(all) suberror ParseError {
  ParseError(String)
} derive(Eq)

///|
pub impl Show for ParseError with output(self, logger) {
  match self {
    ParseError(msg) => logger.write_string("ParseError: " + msg)
  }
}

///|
pub impl Show for Duration with output(self, logger) {
  match self {
    Ms(ms) => {
      logger.write_string("Ms(")
      logger.write_string(ms.to_string())
      logger.write_string(")")
    }
    MsNs(ms, ns) => {
      logger.write_string("MsNs(")
      logger.write_string(ms.to_string())
      logger.write_string(", ")
      logger.write_string(ns.to_string())
      logger.write_string(")")
    }
  }
}

///|
pub impl Show for TimeSpec with output(self, logger) {
  match self {
    Absolute(epoch) => {
      logger.write_string("Absolute(")
      logger.write_string(epoch.to_string())
      logger.write_string(")")
    }
    Relative(epoch, offset) => {
      logger.write_string("Relative(")
      logger.write_string(epoch.to_string())
      logger.write_string(", ")
      offset.output(logger)
      logger.write_string(")")
    }
  }
}

///|
pub impl Show for TimeRange with output(self, logger) {
  logger.write_string("TimeRange { since: ")
  logger.write_string(self.since.to_string())
  logger.write_string(", until: ")
  logger.write_string(self.until.to_string())
  logger.write_string(" }")
}

///| Intermediate: sign as written by user.
priv enum Sign {
  Unsigned
  Plus
  Minus
}

///| Intermediate: raw parsed part (one side of `~`).
priv struct RawPart {
  is_absolute : Bool
  base_epoch : Int64?
  duration : Duration
  sign : Sign
}
