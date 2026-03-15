///| kawaz/datetime - CLI-oriented time specification parser.
///
/// Parses flexible time specs for `--since` / `--until` / `--time-range` CLI options.
///
/// ## Features
///
/// - Duration format: `5m`, `1h30m`, `2d` etc.
/// - `@` prefix for absolute (pinned) time specs
/// - `~` for range: `5m~3m` (since~until)
/// - Re-serialization: Relative → duration string, Absolute → ISO 8601
/// - Pluggable datetime parser for custom formats
///
/// ## Parse contexts
///
/// - `Since`: anchor is since-side, semantic defaults ensure s<=u
/// - `Until`: anchor is until-side, semantic defaults ensure s<=u
/// - `Range`: no semantic defaults for same-type pairs
///
/// ## Examples
///
/// ```
/// let opts = default_options(now)
/// let range = parse!("5m~3m", opts)
/// // range.since = Relative(now-300, -300)
/// // range.until = Relative(now-120, -180)
/// ```
