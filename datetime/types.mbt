///| A time specification - either absolute (pinned to a moment) or relative (sliding window).
///
/// - `Absolute(epoch)` → re-serializes as ISO 8601 timestamp
/// - `Relative(epoch, offset)` → re-serializes as signed duration
pub(all) enum TimeSpec {
  Absolute(Int64)
  Relative(Int64, Int64)
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
      logger.write_string(offset.to_string())
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
  duration : Int64
  sign : Sign
}
