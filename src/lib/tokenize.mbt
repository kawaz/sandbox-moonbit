///|
/// 引数文字列を Token 列に変換する
///
/// Design rationale: DoubleDash トークン自体は保持する（parse 側で rest への振り分けに使用）。
/// DoubleDash 以降の引数は全て Positional として格納するため、parse/apply_defaults 側で
/// DoubleDash 後に LongOpt 等が来ることはない。
pub fn tokenize(args : Array[String]) -> Array[Token] {
  let tokens : Array[Token] = []
  let mut after_double_dash = false
  for arg in args {
    if after_double_dash {
      tokens.push(Positional(arg))
      continue
    }
    if arg == "--" {
      tokens.push(DoubleDash)
      after_double_dash = true
    } else if arg.has_prefix("--") {
      // ロングオプション: "--" 以降を取り出す
      let rest = arg.unsafe_substring(start=2, end=arg.length())
      // "=" で分割
      match rest.find("=") {
        None => tokens.push(LongOpt(rest))
        Some(i) => {
          let key = rest.unsafe_substring(start=0, end=i)
          let value = rest.unsafe_substring(start=i + 1, end=rest.length())
          tokens.push(LongOptWithValue(key, value))
        }
      }
    } else if arg.has_prefix("-") && arg.length() > 1 {
      // ショートオプション (-abc)
      let shorts = arg.unsafe_substring(start=1, end=arg.length())
      tokens.push(ShortOpts(shorts))
    } else {
      tokens.push(Positional(arg))
    }
  }
  tokens
}
