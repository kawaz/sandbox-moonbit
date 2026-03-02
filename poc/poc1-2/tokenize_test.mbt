///|
test "tokenize: long option" {
  inspect(
    tokenize(["--verbose"]),
    content=(
      #|[LongOpt("verbose")]
    ),
  )
}

///|
test "tokenize: long option with value" {
  inspect(
    tokenize(["--format=json"]),
    content=(
      #|[LongOptWithValue("format", "json")]
    ),
  )
}

///|
test "tokenize: long option with separate value" {
  inspect(
    tokenize(["--format", "json"]),
    content=(
      #|[LongOpt("format"), Positional("json")]
    ),
  )
}

///|
test "tokenize: short options" {
  inspect(
    tokenize(["-abc"]),
    content=(
      #|[ShortOpts("abc")]
    ),
  )
}

///|
test "tokenize: single short option" {
  inspect(
    tokenize(["-v"]),
    content=(
      #|[ShortOpts("v")]
    ),
  )
}

///|
test "tokenize: positional args" {
  inspect(
    tokenize(["file.txt", "other.txt"]),
    content=(
      #|[Positional("file.txt"), Positional("other.txt")]
    ),
  )
}

///|
test "tokenize: double dash" {
  inspect(
    tokenize(["--verbose", "--", "--not-an-option", "file.txt"]),
    content=(
      #|[LongOpt("verbose"), DoubleDash, Positional("--not-an-option"), Positional("file.txt")]
    ),
  )
}

///|
test "tokenize: standalone dash" {
  inspect(
    tokenize(["-"]),
    content=(
      #|[Positional("-")]
    ),
  )
}

///|
test "tokenize: empty args" {
  inspect(tokenize([]), content="[]")
}

///|
test "tokenize: mixed args" {
  inspect(
    tokenize(["--format=json", "-v", "input.txt", "--", "extra"]),
    content=(
      #|[LongOptWithValue("format", "json"), ShortOpts("v"), Positional("input.txt"), DoubleDash, Positional("extra")]
    ),
  )
}

///|
test "tokenize: long option with empty value" {
  inspect(
    tokenize(["--format="]),
    content=(
      #|[LongOptWithValue("format", "")]
    ),
  )
}

///|
test "tokenize: long option with value containing equals" {
  inspect(
    tokenize(["--query=a=b"]),
    content=(
      #|[LongOptWithValue("query", "a=b")]
    ),
  )
}
