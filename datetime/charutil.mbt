///| Compare string code unit at position with a char literal.
/// String indexing returns UInt16 (UTF-16 code unit), so we compare via Int.
fn char_eq(s : String, pos : Int, c : Char) -> Bool {
  pos >= 0 && pos < s.length() && s[pos].to_int() == c.to_int()
}

///| Check if string code unit at position is in [lo, hi] (inclusive).
fn char_in_range(s : String, pos : Int, lo : Char, hi : Char) -> Bool {
  guard pos >= 0 && pos < s.length() else { return false }
  let code = s[pos].to_int()
  code >= lo.to_int() && code <= hi.to_int()
}
