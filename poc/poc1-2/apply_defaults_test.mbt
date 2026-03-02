///|
/// テスト用のオプション定義を構築するヘルパー（apply_defaults テスト用）
fn make_apply_defaults_test_opts() -> Array[OptDef] {
  [
    // index 0: verbose — Flag, PrefixNo, shorts=[v]
    OptDef::new(
      long="verbose",
      help="Enable verbose output",
      kind=OptKind::Flag(default=false),
      shorts=[ShortEntry::new(char='v')],
      inversion=Some(FlagInversion::PrefixNo),
    ),
    // index 1: format — Single, default=None
    OptDef::new(
      long="format",
      help="Output format",
      kind=OptKind::Single(default=None),
    ),
    // index 2: eval — Append, PrefixNo, defaults=[]
    OptDef::new(
      long="eval",
      help="Evaluate expression",
      kind=OptKind::Append(n=1, defaults=[]),
      inversion=Some(FlagInversion::PrefixNo),
    ),
    // index 3: color — Flag, default=true, PrefixNo
    OptDef::new(
      long="color",
      help="Enable color output",
      kind=OptKind::Flag(default=true),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
}

// === 基本テスト ===

///|
test "apply_defaults: 空引数 → opts そのまま（恒等性）" {
  let opts = make_apply_defaults_test_opts()
  let result = apply_defaults(opts, [])
  inspect(result[0].kind, content="Flag(default=false)")
  inspect(result[1].kind, content="Single(default=None)")
  inspect(
    result[2].kind,
    content=(
      #|Append(defaults=[], n=1)
    ),
  )
  inspect(result[3].kind, content="Flag(default=true)")
}

///|
test "apply_defaults: Flag の上書き (--verbose)" {
  let opts = make_apply_defaults_test_opts()
  let result = apply_defaults(opts, ["--verbose"])
  inspect(result[0].kind, content="Flag(default=true)")
}

///|
test "apply_defaults: Flag の反転 (--no-verbose)" {
  let opts = make_apply_defaults_test_opts()
  let result = apply_defaults(opts, ["--no-verbose"])
  inspect(result[0].kind, content="Flag(default=false)")
}

///|
test "apply_defaults: Flag default=true の反転 (--no-color)" {
  let opts = make_apply_defaults_test_opts()
  let result = apply_defaults(opts, ["--no-color"])
  inspect(result[3].kind, content="Flag(default=false)")
}

///|
test "apply_defaults: Single の上書き (--format json)" {
  let opts = make_apply_defaults_test_opts()
  let result = apply_defaults(opts, ["--format", "json"])
  inspect(result[1].kind, content="Single(default=Some(\"json\"))")
}

///|
test "apply_defaults: Single の = 形式 (--format=yaml)" {
  let opts = make_apply_defaults_test_opts()
  let result = apply_defaults(opts, ["--format=yaml"])
  inspect(result[1].kind, content="Single(default=Some(\"yaml\"))")
}

///|
test "apply_defaults: Append の追加" {
  let opts = make_apply_defaults_test_opts()
  let result = apply_defaults(opts, ["--eval", "1+1", "--eval", "2+2"])
  inspect(
    result[2].kind,
    content=(
      #|Append(defaults=["1+1", "2+2"], n=1)
    ),
  )
}

///|
test "apply_defaults: Append のリセット+追加 (--no-eval, --eval new)" {
  let opts = make_apply_defaults_test_opts()
  // まず既存のデフォルトがある状態を作る
  let opts_with_defaults = apply_defaults(opts, [
    "--eval", "old1", "--eval", "old2",
  ])
  // リセット後に新しい値を追加
  let result = apply_defaults(opts_with_defaults, ["--no-eval", "--eval", "new"])
  inspect(
    result[2].kind,
    content=(
      #|Append(defaults=["new"], n=1)
    ),
  )
}

// === 未知オプション無視 ===

///|
test "apply_defaults: 未知オプション無視" {
  let opts = make_apply_defaults_test_opts()
  let result = apply_defaults(opts, ["--unknown", "value", "--verbose"])
  // verbose のデフォルトだけ変更される。エラーなし。
  inspect(result[0].kind, content="Flag(default=true)")
  // 他は変更なし
  inspect(result[1].kind, content="Single(default=None)")
}

// === 位置引数無視 ===

///|
test "apply_defaults: 位置引数無視" {
  let opts = make_apply_defaults_test_opts()
  let result = apply_defaults(opts, ["file.txt", "--verbose"])
  inspect(result[0].kind, content="Flag(default=true)")
}

///|
test "apply_defaults: -- 以降は無視" {
  let opts = make_apply_defaults_test_opts()
  let result = apply_defaults(opts, ["--verbose", "--", "--format", "yaml"])
  inspect(result[0].kind, content="Flag(default=true)")
  // -- 以降の --format は処理されない
  inspect(result[1].kind, content="Single(default=None)")
}

// === 多段畳み込み ===

///|
test "apply_defaults: 多段畳み込み (layer2 が layer1 を上書き)" {
  let opts = make_apply_defaults_test_opts()
  let layer1 = ["--format", "yaml", "--verbose"]
  let layer2 = ["--format", "json"]
  let result = apply_defaults(apply_defaults(opts, layer1), layer2)
  // layer2 の --format=json が layer1 の --format=yaml を上書き
  inspect(result[1].kind, content="Single(default=Some(\"json\"))")
  // layer1 の --verbose は layer2 で触れていないので残る
  inspect(result[0].kind, content="Flag(default=true)")
}

// === 純粋関数テスト ===

///|
test "apply_defaults: 純粋関数（元の opts が変更されない）" {
  let opts = make_apply_defaults_test_opts()
  let _result = apply_defaults(opts, [
    "--verbose", "--format", "json", "--eval", "1+1",
  ])
  // 元の opts は変更されていないことを確認
  inspect(opts[0].kind, content="Flag(default=false)")
  inspect(opts[1].kind, content="Single(default=None)")
  inspect(
    opts[2].kind,
    content=(
      #|Append(defaults=[], n=1)
    ),
  )
}

// === ショートオプション ===

///|
test "apply_defaults: ショートオプション (-v)" {
  let opts = make_apply_defaults_test_opts()
  let result = apply_defaults(opts, ["-v"])
  inspect(result[0].kind, content="Flag(default=true)")
}

// === ショートオプション結合値 (#83) ===

///|
test "apply_defaults: -fVALUE 結合形式 (Short+Single)" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="file",
      help="File path",
      kind=OptKind::Single(default=None),
      shorts=[ShortEntry::new(char='f')],
    ),
  ]
  let result = apply_defaults(opts, ["-foutput.txt"])
  inspect(result[0].kind, content="Single(default=Some(\"output.txt\"))")
}

///|
test "apply_defaults: -eEXPR 結合形式 (Short+Append)" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="eval",
      help="Evaluate expression",
      kind=OptKind::Append(n=1, defaults=[]),
      shorts=[ShortEntry::new(char='e')],
    ),
  ]
  let result = apply_defaults(opts, ["-e1+1"])
  inspect(
    result[0].kind,
    content=(
      #|Append(defaults=["1+1"], n=1)
    ),
  )
}

///|
test "apply_defaults: -abfVALUE 結合形式 (Flag+Flag+Single)" {
  let opts : Array[OptDef] = [
    OptDef::new(long="aaa", help="A", kind=OptKind::Flag(default=false), shorts=[
      ShortEntry::new(char='a'),
    ]),
    OptDef::new(long="bbb", help="B", kind=OptKind::Flag(default=false), shorts=[
      ShortEntry::new(char='b'),
    ]),
    OptDef::new(long="file", help="File", kind=OptKind::Single(default=None), shorts=[
      ShortEntry::new(char='f'),
    ]),
  ]
  let result = apply_defaults(opts, ["-abfVALUE"])
  inspect(result[0].kind, content="Flag(default=true)")
  inspect(result[1].kind, content="Flag(default=true)")
  inspect(result[2].kind, content="Single(default=Some(\"VALUE\"))")
}

// === consume_next_value 全トークンタイプ受容 (#83) ===

///|
test "apply_defaults: consume_next_value accepts --verbose as value for --format" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="format",
      help="Output format",
      kind=OptKind::Single(default=None),
    ),
    OptDef::new(
      long="verbose",
      help="Verbose",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let result = apply_defaults(opts, ["--format", "--verbose"])
  // --verbose が format の値として消費される
  inspect(result[0].kind, content="Single(default=Some(\"--verbose\"))")
}

// === Count の apply_defaults テスト ===

///|
test "apply_defaults: Count の上書き (--verbose)" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbosity",
      kind=OptKind::Count(default=0),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = apply_defaults(opts, ["--verbose"])
  inspect(result[0].kind, content="Count(default=1)")
}

///|
test "apply_defaults: Count 累積 (--verbose --verbose)" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbosity",
      kind=OptKind::Count(default=0),
    ),
  ]
  let result = apply_defaults(opts, ["--verbose", "--verbose"])
  inspect(result[0].kind, content="Count(default=2)")
}

///|
test "apply_defaults: Count リセット (--no-verbose)" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbosity",
      kind=OptKind::Count(default=3),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = apply_defaults(opts, ["--no-verbose"])
  inspect(result[0].kind, content="Count(default=0)")
}

///|
test "apply_defaults: Count ショート -vvv" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbosity",
      kind=OptKind::Count(default=0),
      shorts=[ShortEntry::new(char='v')],
    ),
  ]
  let result = apply_defaults(opts, ["-vvv"])
  inspect(result[0].kind, content="Count(default=3)")
}

///|
test "apply_defaults: Count = 形式 (--verbose=ignored)" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbosity",
      kind=OptKind::Count(default=0),
    ),
  ]
  let result = apply_defaults(opts, ["--verbose=5"])
  // = 形式でも値を無視してインクリメント
  inspect(result[0].kind, content="Count(default=1)")
}

///|
test "apply_defaults: Count 多段畳み込み" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbosity",
      kind=OptKind::Count(default=0),
      shorts=[ShortEntry::new(char='v')],
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let layer1 = apply_defaults(opts, ["-vv"])
  let layer2 = apply_defaults(layer1, ["-v"])
  inspect(layer2[0].kind, content="Count(default=3)")
}

// === OptionalValue の apply_defaults テスト ===

///|
test "apply_defaults: OptionalValue LongOpt (--color)" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="color",
      help="Color",
      kind=OptKind::OptionalValue(
        default=None,
        implicit="auto",
        negated=Some("never"),
      ),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = apply_defaults(opts, ["--color"])
  inspect(
    result[0].kind,
    content=(
      #|OptionalValue(default=Some("auto"), implicit="auto", negated=Some("never"))
    ),
  )
}

///|
test "apply_defaults: OptionalValue LongOptWithValue (--color=always)" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="color",
      help="Color",
      kind=OptKind::OptionalValue(
        default=None,
        implicit="auto",
        negated=Some("never"),
      ),
    ),
  ]
  let result = apply_defaults(opts, ["--color=always"])
  inspect(
    result[0].kind,
    content=(
      #|OptionalValue(default=Some("always"), implicit="auto", negated=Some("never"))
    ),
  )
}

///|
test "apply_defaults: OptionalValue Inverted (--no-color)" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="color",
      help="Color",
      kind=OptKind::OptionalValue(
        default=Some("auto"),
        implicit="auto",
        negated=Some("never"),
      ),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = apply_defaults(opts, ["--no-color"])
  inspect(
    result[0].kind,
    content=(
      #|OptionalValue(default=Some("never"), implicit="auto", negated=Some("never"))
    ),
  )
}

///|
test "apply_defaults: OptionalValue Inverted negated=None (--no-color)" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="color",
      help="Color",
      kind=OptKind::OptionalValue(
        default=Some("auto"),
        implicit="auto",
        negated=None,
      ),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = apply_defaults(opts, ["--no-color"])
  inspect(
    result[0].kind,
    content=(
      #|OptionalValue(default=None, implicit="auto", negated=None)
    ),
  )
}

///|
test "apply_defaults: OptionalValue 純粋関数" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="color",
      help="Color",
      kind=OptKind::OptionalValue(
        default=None,
        implicit="auto",
        negated=Some("never"),
      ),
    ),
  ]
  let _result = apply_defaults(opts, ["--color=always"])
  // 元の opts は変更されない
  inspect(
    opts[0].kind,
    content=(
      #|OptionalValue(default=None, implicit="auto", negated=Some("never"))
    ),
  )
}

// === Append n=2 の apply_defaults テスト ===

///|
test "apply_defaults: Append n=2 (--arg k v)" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="arg",
      help="Key-value pair",
      kind=OptKind::Append(n=2, defaults=[]),
    ),
  ]
  let result = apply_defaults(opts, ["--arg", "k", "v"])
  inspect(
    result[0].kind,
    content=(
      #|Append(defaults=["k", "v"], n=2)
    ),
  )
}

///|
test "apply_defaults: Append n=2 inverted (--no-arg)" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="arg",
      help="Key-value pair",
      kind=OptKind::Append(n=2, defaults=["dk", "dv"]),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = apply_defaults(opts, ["--no-arg"])
  inspect(
    result[0].kind,
    content=(
      #|Append(defaults=[], n=2)
    ),
  )
}

///|
test "apply_defaults: Append n=2 = form ignored" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="arg",
      help="Key-value pair",
      kind=OptKind::Append(n=2, defaults=[]),
    ),
  ]
  let result = apply_defaults(opts, ["--arg=k"])
  // n>1 の = 形式は値が足りないので無視
  inspect(
    result[0].kind,
    content=(
      #|Append(defaults=[], n=2)
    ),
  )
}

///|
test "apply_defaults: Append n=2 short -ak v" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="arg",
      help="Key-value pair",
      kind=OptKind::Append(n=2, defaults=[]),
      shorts=[ShortEntry::new(char='a')],
    ),
  ]
  let result = apply_defaults(opts, ["-ak", "v"])
  inspect(
    result[0].kind,
    content=(
      #|Append(defaults=["k", "v"], n=2)
    ),
  )
}

// === W8: 追加テスト ===

///|
test "apply_defaults: Append n=2 partial consumption" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="arg",
      help="Key-value pair",
      kind=OptKind::Append(n=2, defaults=["dk", "dv"]),
    ),
  ]
  // n=2 で値が1個しかない → defaults 変更なし
  let result = apply_defaults(opts, ["--arg", "k"])
  inspect(
    result[0].kind,
    content=(
      #|Append(defaults=["dk", "dv"], n=2)
    ),
  )
}

///|
test "apply_defaults: Count short -vxv mixed" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbosity",
      kind=OptKind::Count(default=0),
      shorts=[ShortEntry::new(char='v')],
    ),
    OptDef::new(long="xxx", help="X flag", kind=OptKind::Flag(default=false), shorts=[
      ShortEntry::new(char='x'),
    ]),
  ]
  let result = apply_defaults(opts, ["-vxv"])
  // v=1, x=true, v=1 more → v=2
  inspect(result[0].kind, content="Count(default=2)")
  inspect(result[1].kind, content="Flag(default=true)")
}

///|
test "apply_defaults: unknown short in combined" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="verbose",
      help="Verbosity",
      kind=OptKind::Flag(default=false),
      shorts=[ShortEntry::new(char='v')],
    ),
  ]
  // -xv where x is unknown → x はスキップ、v だけ処理
  let result = apply_defaults(opts, ["-xv"])
  inspect(result[0].kind, content="Flag(default=true)")
}

// === Group の apply_defaults テスト ===

///|
test "apply_defaults: Group(WithValue) deep copy — opts 変更が元に影響しない" {
  let inner_opts : Array[OptDef] = [
    OptDef::new(
      long="inner",
      help="Inner opt",
      kind=OptKind::Flag(default=false),
    ),
  ]
  let opts : Array[OptDef] = [
    OptDef::new(
      long="output",
      help="Output group",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=Some("json")),
        opts=inner_opts,
        positional=Positional::Fixed([PositionalDef::new(name="FILE")]),
      ),
    ),
  ]
  // apply_defaults は内部で copy_opt_kind を呼ぶ。空引数でもコピーは行われる
  let result = apply_defaults(opts, [])
  // result の Group 内 opts を変更しても元に影響しないことを確認
  match result[0].kind {
    OptKind::Group(opts=copied_opts, ..) =>
      copied_opts.push(
        OptDef::new(
          long="extra",
          help="Extra",
          kind=OptKind::Flag(default=false),
        ),
      )
    _ => abort("expected Group")
  }
  // 元の inner_opts は変更されていない
  inspect(inner_opts.length(), content="1")
}

///|
test "apply_defaults: Group(Valueless) deep copy" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="ssl",
      help="SSL group",
      kind=OptKind::Group(
        group_kind=GroupKind::Valueless,
        opts=[
          OptDef::new(
            long="cert",
            help="Certificate",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result = apply_defaults(opts, [])
  // コピーされた opts の kind を変更
  match result[0].kind {
    OptKind::Group(opts=copied_opts, ..) =>
      copied_opts[0] = {
        ..copied_opts[0],
        kind: OptKind::Single(default=Some("changed")),
      }
    _ => abort("expected Group")
  }
  // 元は変更されない
  match opts[0].kind {
    OptKind::Group(opts=original_opts, ..) =>
      inspect(original_opts[0].kind, content="Single(default=None)")
    _ => abort("expected Group")
  }
}

///|
test "apply_defaults: Group(WithValue(default=Some)) のデフォルト上書き" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="output",
      help="Output group",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=Some("text")),
        opts=[
          OptDef::new(
            long="format",
            help="Format",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  // --output json → WithValue の default を "json" に上書き
  let result = apply_defaults(opts, ["--output", "json"])
  match result[0].kind {
    OptKind::Group(group_kind~, ..) =>
      inspect(
        group_kind,
        content=(
          #|WithValue(default=Some("json"))
        ),
      )
    _ => abort("expected Group")
  }
}

///|
test "apply_defaults: Group(WithValue) = 形式 (--output=yaml)" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="output",
      help="Output group",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=Some("text")),
        opts=[
          OptDef::new(
            long="format",
            help="Format",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result = apply_defaults(opts, ["--output=yaml"])
  match result[0].kind {
    OptKind::Group(group_kind~, ..) =>
      inspect(
        group_kind,
        content=(
          #|WithValue(default=Some("yaml"))
        ),
      )
    _ => abort("expected Group")
  }
}

///|
test "apply_defaults: Group(WithValue) 反転で default を None にクリア" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="output",
      help="Output group",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=Some("json")),
        opts=[
          OptDef::new(
            long="format",
            help="Format",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
      inversion=Some(FlagInversion::PrefixNo),
    ),
  ]
  let result = apply_defaults(opts, ["--no-output"])
  match result[0].kind {
    OptKind::Group(group_kind~, ..) =>
      inspect(
        group_kind,
        content=(
          #|WithValue(default=None)
        ),
      )
    _ => abort("expected Group")
  }
}

///|
test "apply_defaults: Group(Valueless) は変更なし" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="ssl",
      help="SSL group",
      kind=OptKind::Group(
        group_kind=GroupKind::Valueless,
        opts=[
          OptDef::new(
            long="cert",
            help="Certificate",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let result = apply_defaults(opts, ["--ssl"])
  // Valueless は何もしない
  match result[0].kind {
    OptKind::Group(group_kind~, ..) => inspect(group_kind, content="Valueless")
    _ => abort("expected Group")
  }
}

///|
test "apply_defaults: Group 純粋関数（元 opts が変更されない）" {
  let opts : Array[OptDef] = [
    OptDef::new(
      long="output",
      help="Output group",
      kind=OptKind::Group(
        group_kind=GroupKind::WithValue(default=Some("text")),
        opts=[
          OptDef::new(
            long="format",
            help="Format",
            kind=OptKind::Single(default=None),
          ),
        ],
        positional=Positional::Disallowed,
      ),
    ),
  ]
  let _result = apply_defaults(opts, ["--output", "json"])
  // 元の opts は変更されない
  match opts[0].kind {
    OptKind::Group(group_kind~, ..) =>
      inspect(group_kind, content="WithValue(default=Some(\"text\"))")
    _ => abort("expected Group")
  }
}
