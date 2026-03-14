///| A time specification - either absolute (pinned to a moment) or relative (sliding window).
///
/// - `Absolute(epoch)` → re-serializes as ISO 8601 timestamp (e.g., `2025-03-15T00:56:14Z`)
/// - `Relative(epoch, offset)` → re-serializes as signed duration (e.g., `-5m`, `+3m`)
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
  /// `--since`: since is anchor for same-type pairs, semantic defaults apply
  Since
  /// `--until`: until is anchor for same-type pairs, semantic defaults apply
  Until
  /// `--time-range`: no semantic defaults for same-type pairs
  Range
} derive(Eq, Show)

///| Options for parsing a time spec string.
pub(all) struct ParseOptions {
  /// Parse context (since/until/range)
  context : ParseContext
  /// Current time as Unix epoch seconds
  now : Int64
  /// If true, swap since/until when since > until (default: false)
  swap : Bool
  /// Custom datetime parser. Receives trimmed timestamp string, returns epoch seconds or None.
  /// Default: built-in ISO 8601 parser.
  parse_datetime : (String) -> Int64?
} derive(Eq)

///| Parse error with description.
pub(all) type! ParseError String derive(Eq)

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

///| Intermediate: sign as written by user (for re-serialization).
priv enum Sign {
  Unsigned
  Plus
  Minus
} derive(Eq, Show)

///| Intermediate: raw parsed part (one side of `~`).
priv struct RawPart {
  is_absolute : Bool
  base_epoch : Int64?
  duration : Int64
  sign : Sign
} derive(Eq, Show)
