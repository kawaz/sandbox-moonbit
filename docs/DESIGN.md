# CLI パーサ設計仕様書

## Context

- Phase 1-3 の PoC は「テストケース = 要件」として引き継ぐ。コードは全削除して完全作り直し
- 核心: 全 OptKind を `initial + ReduceCtx reducer` で統一
- heterogeneous collection は ErasedNode struct（クロージャ束）で実現（trait object 不使用）
- String ベースの中間表現は不要。T ベースで直接動作
- **先食い最長一致への進化**: 旧設計の resolve → resolve_value → do_reduce の3段階を廃止し、各ノードが try_reduce で名前マッチング + 値消費を一括で行う先食い最長一致方式に統合。Resolve フェーズ自体を除去し、5フェーズパイプラインに簡素化

Design rationale: 旧設計では `Map[String, Array[String]]` による String ベースの中間表現を使い、
`ReduceContext` で初期値・デフォルト・明示設定フラグを運搬していた。新設計では ErasedNode struct が
型を閉じ込めたクロージャ群を保持することで heterogeneous collection を実現し、String への変換・逆変換が
完全に不要になり、型安全性が向上する。

---

## 設計原則

- **Opt[T] は完全 immutable** — 定義情報のみ保持。一意 ID で ResultMap のキーとして機能
- **parse はツリーを走査して結果を書き込む** — `ErasedNode` struct 経由で型を知らずに操作
- **ユーザーは `parser.get(opt)` で型付きの値を取得** — Opt[T] がレンズ/キーとして機能
- **defaults は優先順位付きソースからの置き換え**（積み上げではない） — 後のソースが前を丸ごと上書き
- **reducer はシンプルに `(ReduceCtx[T]) -> T? raise ParseError`** — None = マッチしない（候補から脱落）、Some(T) = 消費成功、raise ParseError = エラー
- **try_reduce で名前マッチング + 値消費を一体化** — 旧 Resolve フェーズを廃止し、各ノードが投機的に自身でマッチ判定と消費量決定を行う

---

## Opt ツリー構造

### Opt[T] — リーフノード

各ノードが自身の定義情報と reducer を持つ。完全 immutable。結果は外部の ResultMap に保持。

※ 最終設計は Parser struct + getter 方式（後述）。ここでは概念説明のためシンプルな形を示す

```moonbit
///| リーフノード — 定義情報 + 各 ResultMap ごとの値を分散管理
struct Opt[T] {
  id : Int                    // 一意 ID（生成時にインクリメント）
  initial : InitialValue[T]
  reducer : (ReduceCtx[T]) -> T? raise ParseError
  meta : OptMeta
  slots : Map[Int, Ref[T]]   // result_map.id -> Ref[T]（各 ResultMap ごとの値を分散管理）
}

// Hash/Eq は id ベース — Map のキーとして使える
impl[T] Hash for Opt[T] with hash(self) { self.id.hash() }
impl[T] Eq for Opt[T] with op_equal(self, other) { self.id == other.id }

///| 初期値 — 即値または遅延評価
pub(all) enum InitialValue[T] {
  Val(T)
  Thunk(() -> T)
}
```

Design rationale: 結果は Opt[T] が内部に持つ `slots: Map[Int, Ref[T]]` で各 ResultMap ごとに分散管理。ResultMap は ID + clone レジストリのみ保持し、値は持たない。
`InitialValue[T]` は即値と遅延評価（ランタイム依存の初期値）を統一的に扱う。

### Opts — ツリーの構造化

JSON の Value のような再帰的 enum 構造。リーフ（ErasedNode）と合成（Array）を統一的に表現する。

```moonbit
///| Opt ツリーの構造化 — JSON の Value のような再帰構造
enum Opts {
  Node(ErasedNode)           // 型消去されたリーフ
  Array(Array[Opts])         // オプション群（名前マッチ）= List
}
```

- `Opts::Node` — リーフ。`ErasedNode` struct が型を閉じ込めたクロージャ群を保持
- `Opts::Array` — 通常のオプション群。各要素は名前マッチで独立に解決される
- `serial(...)` — 位置パラメータの順番消費。明示的にマーク（serial コンビネータで生成）
- `rest(opt)` — 可変長消費。明示的にマーク（rest コンビネータで生成）

ノードの名前は `ErasedNode` 内に保持する `OptMeta.name` から取得するため、外部キー不要。
`opts([o1, o2, o3])` は `Opt[T]` の Array を受け取り `Opts::Array` を返すヘルパー関数。

Design rationale: MoonBit にリフレクションがなく、無名 struct をその場で作って T として渡せないため、
ユーザー定義 struct + フィールドアクセス方式は実現困難。JSON の Value と同じ再帰 enum パターンなら、
パーサがリフレクション不要でツリーを走査できる。`Opts::Map` は名前が meta.name と二重になるため廃止。
`opts()` ヘルパーが名前を自動取得することで `.erased()` ノイズと名前二重指定を解消する。

### 合成パターン

- **or** — 排他選択。`opts()` で子をまとめて構造化。子は自動で `required=false`
- **serial** — 固定長連続引数。位置パラメータの順番消費。明示的にマーク
- **group** — 繰り返し出現するオプション群。雛形 Opts を clone して各出現の値を保持
- **never** — 引数消費に使われると常に ParseError を投げるセンチネル。serial の末尾に置くことで、固定長 positionals 消費後に通常消費に戻ることを防止

---

## ErasedNode — 型消去 struct（クロージャ束）

parse がツリーを走査するための型消去 struct。クロージャ群が T を閉じ込め、parse は具体的な T を知る必要がない。

```moonbit
///|
pub(all) struct ErasedNode {
  meta : OptMeta
  try_reduce : (args : Array[String], pos : Int) -> TryReduceResult raise ParseError
  commit_reduce : (ReduceResult) -> Unit
  reset_to_initial : () -> Unit
  children : () -> Array[ErasedNode]
}

///| 先食い結果
pub(all) enum TryReduceResult {
  Accept(consumed~ : Int, result~ : ReduceResult)
  Reject
}

// ReduceResult は型消去された一時結果。commit_reduce でのみ使用
// 内部的には ErasedRef 等で型を保持するが、外部からは opaque
type ReduceResult
```

Design rationale: 旧設計では `arity : Int` フィールドで値消費量を事前宣言していたが、これを廃止。
値消費の判断は try_reduce の戻り値（`Accept.consumed`）で動的に行う。これにより `=` 付き値
（`--port=8080` → consumed=0）と空白区切り値（`--port 8080` → consumed=1）を統一的に扱え、
arity では表現できない柔軟な消費パターンに対応できる。

また、try_reduce と commit_reduce から ResultMap 引数を削除。Parser struct + getter 方式では
ResultMap は Ref[T] クロージャキャプチャに隠蔽されているため、シグネチャに露出する必要がない。

`Opt[T]` から `ErasedNode` を生成する際、各クロージャが `Ref[T]` をキャプチャして T を封じ込める。
parse は `ErasedNode` の配列/ツリーを走査して `try_reduce` を呼ぶだけ。型を知らない。

Design rationale: trait object は MoonBit でダウンキャスト不可のため、`result.get(opt)` で型安全に
値を取り出せない。struct（クロージャ束）にすることで trait object を排除しつつ、クロージャが T を
静的に閉じ込める型安全な型消去を実現する。

---

## try_reduce の内部メカニズム

各ノードの try_reduce は名前マッチング + 値消費 + reducer 呼び出しを一体化して行う:

```
try_reduce(args, pos):
  1. match_name(args[pos], self.meta) → Matched(action) | NotMatched
  2. NotMatched なら Reject を返す
  3. action に基づいて値消費を決定（= 付き値 or 次引数消費）
  4. reducer(ReduceCtx { current, action }) を呼ぶ
  5. Accept(consumed, result) を返す
```

### ReduceAction

try_reduce **内部**で使われる（match_name の結果として得られる action を内部の reducer に渡す）。外部 API からは見えない。

```moonbit
///|
pub(all) enum ReduceAction {
  /// 正方向: Flag/Count は None、Single/Append は Some(value)
  Value(String?)
  /// 反転: --no-xxx。reducer が initial にリセット等を判断
  Negate
} derive(Eq, Show, Debug)
```

### match_name — 名前マッチングユーティリティ

各ノードの try_reduce 内部で名前マッチングを行うための共有ユーティリティ。旧 Resolve フェーズの全機能を内包する。

```moonbit
///| 名前マッチング結果
enum MatchResult {
  Matched(action : ReduceAction)  // マッチ、action に =value や Negate 情報
  NotMatched
}

///| 引数文字列を OptMeta に対してマッチング
fn match_name(arg : String, meta : OptMeta) -> MatchResult
```

match_name がカバーする範囲:
- ロングオプション完全一致: `--name`
- ショートオプション: `-n`
- エイリアス完全一致
- プレフィックスマッチ（曖昧でなければ）
- 反転パターン: `--no-name`, `--enable-name`, `--disable-name`
- `=` 付き値分解: `--port=8080` → `Matched(Value(Some("8080")))`
- サブコマンド名マッチ

**プレフィックスマッチの扱い**: 各ノードの match_name はプレフィックスマッチで Matched を返す。スコープ Reducer（消費ループ）が全ノードの結果を比較し、プレフィックスマッチが複数あれば AmbiguousOption エラーを出す。

Design rationale: 旧設計では Resolve フェーズが名前 → Opt の解決を専任し、消費ループとは分離されていた。
しかし名前マッチングと値消費は本質的に不可分（`--port=8080` の = 分解は名前解決と値消費の境界にある）。
try_reduce に統合することで、名前マッチ → 値消費 → reducer 呼び出しが一貫したフローになり、
Resolve フェーズの独立した存在理由がなくなった。did-you-mean 等の旧 Resolve フック機能は
Reduce フェーズのフックに統合する。

### Accept.consumed の解釈

`consumed` は**オプション名自体の1個を含まない**。呼び出し側が `1 + consumed` で pos を進める。

| パターン | 例 | consumed |
|---------|-----|---------|
| フラグ | `--verbose` | 0（名前だけ） |
| 次引数消費 | `--port 8080` | 1（値1つ追加消費） |
| `=` 付き値 | `--port=8080` | 0（= で値が同じ引数内） |
| 反転 | `--no-verbose` | 0（名前だけ） |

---

## ReduceCtx[T] と reducer 統一パターン

全ての OptKind は `(ReduceCtx[T]) -> T? raise ParseError` の reducer で表現される。OptKind enum は不要。

```moonbit
///|
struct ReduceCtx[T] {
  current : T              // 現在の累積値
  action : ReduceAction    // 今回のアクション
  // 以下は内部の ParseContext に委譲（将来追加してもシグネチャ不変）
}

// ParseContext 委譲メソッド（消費ループ中のみ有効）
fn ReduceCtx::get[T, U](self, opt: Opt[U]) -> U?       // 他 Opt の途中結果
fn ReduceCtx::is_set[T](self, opt: Opt[_]) -> Bool      // 消費済みか
fn ReduceCtx::source[T](self, opt: Opt[_]) -> ValueSource?
// 将来拡張例（シグネチャ不変で追加可能）:
// fn ReduceCtx::ahead[T](self, count: Int) -> Array[String]  // 未消費の後続引数を先読み（中間rest等）
```

| 種別 | initial | reducer |
|------|---------|---------|
| Flag | `false` | `(ctx) -> if ctx.action == Value(None) { Some(true) } else { Some(initial) }` |
| Count | `0` | `(ctx) -> if ctx.action == Value(None) { Some(ctx.current + 1) } else { Some(initial) }` |
| Single | `None` | `(ctx) -> match ctx.action { Value(Some(s)) => Some(Some(parse(s))); Negate => Some(initial); _ => None }` |
| Append | `[]` | `(ctx) -> match ctx.action { Value(Some(s)) => Some([..ctx.current, parse(s)]); Negate => Some(initial); _ => None }` |
| OptionalValue | `None` | `(ctx) -> match ctx.action { Value(None) => Some(Some(implicit)); Value(Some(s)) => Some(Some(s)); _ => None }` |

プリミティブ型コンビネータは custom の特殊化: `opt::int` = `opt::custom(parse_int)`

Design rationale: reducer のシグネチャを `(ReduceCtx[T]) -> T? raise ParseError` の1引数に統一する。
旧設計の `(T, ReduceAction)` 2引数、その後の `(T, ReduceAction, ParseContext)` 3引数を経て、
**後方互換性**を重視した最終形。ReduceCtx に新しいメソッドを追加しても既存 reducer は壊れない。
MoonBit ではクロージャにラベル付き/オプション引数が使えない（言語制約）ため、struct ラッパーが最適解。

reducer の3値の設計根拠:
- None: 「この引数を食えない」= 消費ループの候補選定で使用。他の候補を試す
- Some(T): 「この引数を消費した」= 結果を ResultMap に書き込む
- ParseError: 「マッチしたがバリデーション失敗」= 即座にエラー

重要: None と ParseError の使い分けは**名前解決の前後で異なる**:
- 名前解決前（positional の候補選定等）: 型が合わない → None（他の候補を試す）
- 名前解決後（`--port abc` で port が確定済み）: 値の型変換失敗 → ParseError（エラーを握り潰さない）

---

## 引数消費ループ — 先食い最長一致

### 概要

parse のコアは消費ループ。各ノードが try_reduce で投機的にマッチ判定と消費量決定を行い、最長一致で確定する。

### アルゴリズム

```
0. カレントスコープの全ノードを OC (Option/Command) と P (Positional) に分類

while pos < args.length():
  1. 全 OC ノードに args, pos を渡して try_reduce を呼ぶ（投機的実行、副作用なし）
  2. Accept を返したノードを収集
  3. greedy フィルタ: greedy=true があれば greedy=false を除去
  4. 結果判定:
     - Accept 0個: P リストがあれば P モードにフォールスルー、なければ ParseError
     - Accept 1個（最長一致が唯一）: commit_reduce で確定、pos += 1 + consumed
       - Command なら子スコープに遷移（OC/P リスト更新）
     - Accept 2個以上で consumed が同じ: ParseError(曖昧)
     - Accept 2個以上で consumed が異なる: 最長のみ採用（最長が複数なら曖昧）

  P モード:
  - Option 割り込み: args[pos] が `-` で始まり OC ノードにマッチ → Option 消費
  - それ以外: P リストの次の Positional で消費
  - `--` 以降は force_positional（Option 割り込み無効）
```

### kind による区別

全ノードに kind を持たせ、マッチ方法を区別する。

| kind | マッチ条件 | name の意味 |
|------|----------|-----------|
| Option | `--name` でマッチ | オプション名 |
| Command | 名前でマッチ | サブコマンド名 |
| Positional | 位置でマッチ | プレースホルダ名 |

### 短縮オプション展開

`-abc` の展開はスコープ Reducer（消費ループ）の責務として行う:

1. 個別ノードの try_reduce で `-abc` がマッチしない場合
2. スコープ Reducer が `-abc` を `-a`, `-b`, `-c` に展開を試みる
3. 各文字がカレントスコープの ShortEntry にマッチするか確認
4. 値を消費するノード（try_reduce が consumed > 0 相当）が見つかったら残りを値にする
5. 全文字マッチ成功なら展開結果を順次消費

Design rationale: 短縮オプション展開はスコープの知識が必要（どの短縮名が有効かはカレントスコープに依存する）。
旧設計の PreProcess での事前展開ではスコープ外のオプションを誤展開するリスクがあった。
スコープ Reducer が認識する範囲で展開することで正確性が保証される。

### P モードの制約

P 消費に遷移した後:

- **Command は候補にならない**（サブコマンド選択は確定済み）
- 消費対象は: そのサブコマンドレベルの Option + グローバル Option + 残り Positional
- Option が見つかったら割り込み消費し、P の消費に戻る

### スコープ遷移

Command がマッチしたら:

- カレントスコープを Command の子 Opts に切り替え
- `global=true` のノードは親スコープから引き継ぐ
- 以降の消費ループは新スコープ内で OC モードから再開

Design rationale: 引数消費を OC モードと P モードの2層で処理することで、Option/Command を確実に先に解決し、Positional は残り物として扱う。P モードでも Option の割り込みを許容するため、`cmd file1 --verbose file2` のような自然な記述が可能。Command は P モード移行後は候補から外れるため、位置引数とサブコマンド名の衝突を防ぐ。

---

## greedy — 優先消費

`meta.greedy = true` のノードは、消費ループのマッチ判定で非 greedy 候補を脱落させる。greedy 同士は通常通り競合する。

```
消費ループのマッチ判定:
  candidates = マッチした全候補
  if candidates.any(c => c.meta.greedy) {
    candidates = candidates.filter(c => c.meta.greedy)  // greedy=false を除外
  }
  // 残った candidates で通常の消費ループ続行
```

meta に格納するので flag 以外（positional, command 等）にも適用可能。

---

## OptMeta — メタ情報

```moonbit
///|
pub(all) struct OptMeta {
  name : String
  kind : Kind             // Option | Command | Positional
  help : String
  shorts : Array[ShortEntry]
  aliases : Array[AliasEntry]
  inversion : FlagInversion?
  env : String?
  auto_env : Bool?          // None=親Cmdに従う, Some(true)=有効, Some(false)=無効
  choices : Array[String]
  value_name : String
  required : Bool
  visibility : Visibility
  global : Bool             // スコープ以下全体に伝搬
  greedy : Bool             // マッチ時、非 greedy 候補を除外して消費ループ続行
} derive(Eq, Show, Debug)
```

### 補助型定義

```moonbit
///|
enum Kind {
  Option
  Command
  Positional
}

///|
struct ShortEntry {
  char : Char
}

///|
struct AliasEntry {
  name : String
  deprecated : Bool  // deprecated 別名の警告表示
}

///|
enum FlagInversion {
  No                         // --no-xxx
  EnableDisable              // --enable-xxx / --disable-xxx
  Custom(String, String)     // カスタムプレフィックスペア
}
```

---

## ResultMap — パース結果の保持

PoC 検証の結果、**Ref[T] クロージャキャプチャ方式**を採用。ResultMap は値を直接持たず、Opt[T] 側に値が分散する。

```moonbit
///| パース結果のスコープ識別子 + clone レジストリ
struct ResultMap {
  id : Int                                      // 一意 ID
  clone_fns : Map[Int, (Int, Int) -> Unit]      // slot_id -> clone クロージャ
}
```

**値の所有権は Opt[T] 側に分散**（`slots : Map[Int, Ref[T]]` — 前掲の Opt[T] struct 参照）。

**型安全な値の取得**:

```moonbit
///| Opt[T] をキーとして型安全に値を取得
fn get[T](self : ResultMap, opt : Opt[T]) -> T {
  opt.slots[self.id].val    // 直接 T を返す。ダウンキャスト不要
}

///| サブコマンド取得
fn command(self : ResultMap) -> ErasedNode?  // None = トップレベル or サブコマンド以外
```

**clone（グループの独立インスタンス生成）**:

```moonbit
///| 独立した ResultMap を生成（グループの各出現用）
fn clone(self : ResultMap) -> ResultMap {
  let new_id = next_id()
  // 各 Opt の clone_fn が新 ID に対応する独立 Ref を作成
  for _, clone_fn in self.clone_fns {
    clone_fn(self.id, new_id)
  }
  ResultMap { id: new_id, clone_fns: self.clone_fns }
}
```

Design rationale: 同じ `Ref[T]` に対して2つのビューが共存する方式を採用:
(1) **型消去ビュー** — `try_reduce` クロージャが `Ref[T]` をキャプチャし、T を知らずに操作
(2) **型ありビュー** — `Opt[T].slots[result_map.id]` で直接 T として取り出す
最初から T を知っている `Opt[T]` と、T を閉じ込めたクロージャが同じ `Ref[T]` を共有するため、型安全性は静的に保証される。ダウンキャスト不要。

不採用: **enum Value ラッパー方式** — `enum Value { VInt(Int); VBool(Bool); ... }` で型を閉じる方式。
`opt::custom(my_reducer)` でユーザーが任意の T としてパースできる開放性要件を満たせないため不採用。

---

## 型付き結果の取り出し

### 通常 Opt — 変数バインド + result.get()

構築時に変数バインドし、parse 後に `result.get(opt)` で型安全に取得する。

```moonbit
let port = opt::int(name="port")
let verbose = opt::flag(name="verbose")

let result = parse(args, opts([port, verbose]))  // ResultMap を返す

result.get(port)     // Int
result.get(verbose)  // Bool
```

`result.get(port)` は内部的に `port.slots[result.id].val` で直接 T を返す。

### グループ Opt — 雛形 + clone 方式

parse がグループ出現ごとに `result_map.clone()` を呼び、独立した ResultMap を生成する。

```moonbit
let upstream_host = opt::str(name="host")
let upstream_timeout = opt::int(name="timeout")
let upstream_tmpl = opts([upstream_host, upstream_timeout])
let upstream = opt::group(name="upstream", upstream_tmpl)

let result = parse(args, ...)

// グループ: 出現ごとに clone（新 clone ID 発行）して値を詰めた Array[ResultMap]
let groups = result.get_groups(upstream)  // Array[ResultMap]

// 雛形 Opt[T] をレンズとして clone 先の ResultMap から型安全に取得
let host : String = groups[0].get(upstream_host)
let timeout : Int = groups[0].get(upstream_timeout)
```

Design rationale: 通常 Opt は変数バインド + result.get() で型安全にアクセス。グループは同じ構造が
複数出現するため静的変数バインドでは対応できないが、雛形 Opt[T] をレンズとして使うことで型安全性を維持。

---

## Parser struct + getter 方式（PoC4 検証済み・採用）

cobra-style とハイブリッドを統合する方向性。

**概要**: Parser struct が ID 空間と ref ストレージを一元管理。Opt[T] は getter クロージャで型消去を解決。

```moonbit
///|
struct Parser {
  mut seq : Int              // ローカル ID カウンタ（テスト分離）
  refs : Map[Int, RefV]      // id → 値の一元管理
  clone_map : Map[Int, Int]  // clone_id → template_id（clone 時に登録）
}

///|
enum RefV {
  Value(ErasedRef)           // 個別 opt インスタンス
  Array(Array[ErasedRef])    // グループの全インスタンス一覧
}

///|
struct Opt[T] {
  id : Int                   // 一意 ID（これだけ）
  initial : InitialValue[T]
  reducer : (ReduceCtx[T]) -> T? raise ParseError
  meta : OptMeta
  getter : (Int) -> T        // instance_id を受け取り T を返す（内部で Map[Int, Ref[T]] をキャプチャ）
  // slots は struct フィールドから消え、getter クロージャ内に隠蔽
  // template_id は持たない — clone 関係は Parser.clone_map で管理
}
```

**全 ID は同一 seq から採番**（デバッグ時の混乱防止）:
```
seq=1: port      → refs[1] = Value(ref)
seq=2: upstream  → refs[2] = Array([])           グループ雛形
seq=3: clone 0   → refs[3] = Value(ref_a)        clone_map[3] = 2
seq=4: clone 1   → refs[4] = Value(ref_b)        clone_map[4] = 2
                    refs[2] = Array([ref_a, ref_b])
```

**API**:
```moonbit
let p = Parser::new()
let port = p.int(name="port")
p.parse(args, opts([port]))
p.get(port)                          // port.getter(p.root_result_id)
let groups = p.get_groups(upstream)   // refs[upstream.id] の Array
groups[0].get(port)                  // port.getter(groups[0].id)
```

**メリット**:
- Opt[T] struct フィールドは全て不変（getter クロージャの参照先が mutable なだけ）
- slots が struct から消え、getter クロージャ内に隠蔽される
- ref 管理が Parser に一元化（slots メモリリーク問題が構造的に解消）
- Parser ローカル seq でテスト分離・並行処理対応
- `enum RefV` で Map[Int, RefV] に一元保存

---

## defaults（置き換え方式）

各デフォルトソースは独立。旧設計の ReduceContext は不要。

**解決策**: 各ソースごとに新しい ResultMap（initial から）で parse し、最後に**明示指定のみ後勝ちマージ**する。同一 ResultMap への累積 parse ではない。

**マージルール**: 各 Opt について、後のソースで**明示的に指定された値のみ**が前のソースの値を上書きする。未指定（initial のまま）の Opt は上書きしない。

```
source1 (config):  --port 3000 --tags a --tags b
source2 (env):     --port 8080
CLI:               --tags c

source1 result: { port: 3000 [explicit], tags: [a, b] [explicit] }
source2 result: { port: 8080 [explicit], tags: [] [initial] }
CLI result:     { port: 0 [initial], tags: [c] [explicit] }

→ merge（明示指定のみ後勝ち）:
→ port: source1=3000 ← source2=8080(explicit) 上書き ← CLI=initial なので上書きしない → 8080
→ tags: source1=[a,b] ← source2=initial なので上書きしない ← CLI=[c](explicit) 上書き → [c]
```

判定基準: `ValueSource != Initial` の場合のみ上書き対象。

### defaults 優先順位（viper 参考）

```
CLI > 環境変数 > 設定ファイル > initial
```

各ソースごとに独立した ResultMap で parse し、後勝ちマージ。

Design rationale: 旧設計では `ReduceContext.defaults` と `explicitly_set` で
Append の replace/stacking semantics を制御していた。新設計では defaults は
単純な「後勝ち」方式。Append の replace semantics は「CLI で --tags が1回でも指定されたら、
previous source の tags を破棄して CLI 指定分だけにする」という単純なルールになる。

---

## サブコマンド・位置パラメータの具体的表現

### サブコマンドの表現

```moonbit
let verbose = opt::flag(name="verbose", global=true)  // スコープ付きグローバル

let port = opt::int(name="port")
let host = opt::str(name="host")
let dir = opt::positional(name="DIR")

let serve = cmd("serve", opts([port, host, dir]))

let target = opt::str(name="target")
let force = opt::flag(name="force")

let deploy = cmd("deploy", opts([target, force]))

let app = opts([verbose, serve, deploy])

let result = parse(args, app)
result.get(verbose)      // Bool（どのサブコマンドでも有効）
result.command()         // ErasedNode?（serve or deploy。None = トップレベル）
result.get(port)         // Int（serve スコープ外なら initial 値。型は常に T）
```

- 同一階層のサブコマンドは引数消費ループで常に1つに決まる。排他の仕組みは不要
- `result.command() -> ErasedNode?` で選ばれたサブコマンドを取得

**result.get の型契約**: `result.get(opt : Opt[T]) -> T` は常に `T` を返す（`T?` ではない）。
スコープ外の Opt は initial 値が返る。「指定されたか」を知りたい場合は `result.source(opt) -> ValueSource` を使う。

### 位置パラメータの表現

```moonbit
// 固定長、順番消費
serial(file, dir)

// 可変長、単一 Opt の繰り返し
rest(path)

// 組み合わせ: 固定 + 末尾 rest
serial(file, rest(path))    // zip = zip file path1 path2 ...
```

Design rationale: 位置パラメータは serial で固定長順番消費、rest で可変長消費を表現。中間 rest（rest の後に固定パラメータ）は複雑なため将来検討。

### `--` (double dash) の表現

`--` を特殊トークンとしてハードコードするのではなく、通常の Opt として統一的に表現する。

```moonbit
// -- は name="" の greedy フラグ
let double_dash = flag(name="", greedy=true, global=true)

// 固定長 positionals の場合: never() で余剰消費を防止
let hh = serial(double_dash, file1, file2, never())

// rest ありの場合: rest が全て吸収するので never() 不要
let hh = serial(double_dash, rest(path))
```

Design rationale: greedy + serial の組み合わせで `--` を通常の Opt として表現することで、
特殊処理が不要になり、`--exec` 的な「以降全て引数」パターンにも同じ仕組みで対応できる。

---

## パースライフサイクルとフックアーキテクチャ

パーサのコアは各フェーズのパイプラインを回すだけ。具体的な振る舞いはフックで注入する。
組み込みの便利関数（`exclusive()`, `opt::flag()` 等）は内部でフックを登録するだけの薄いラッパー。

```
引数入力 → [PreProcess] → [Reduce] → [Validate] → [Finalize] → [Output]
```

### フェーズ一覧

| フェーズ | 責務 | フック型 |
|---------|------|---------|
| **PreProcess** | 引数の前処理・正規化 | `(Array[String]) -> Array[String]` |
| **Reduce** | 先食い最長一致の消費ループ | `(ReduceCtx[T]) -> T? raise ParseError` |
| **Validate** | 制約チェック | `(ValidateCtx) -> Unit raise ParseError` |
| **Finalize** | デフォルト適用・後処理 | `(FinalizeCtx) -> Unit raise ParseError` |
| **Output** | ヘルプ/補完/エラー/バージョン | フェーズごとに別型 |

Design rationale: 旧設計の6フェーズパイプラインから Resolve フェーズを除去し5フェーズに簡素化。
名前マッチング（旧 Resolve の責務）は各ノードの try_reduce に統合され、独立フェーズとしての存在理由がなくなった。
did-you-mean サジェスト等の旧 Resolve フック機能は Reduce フェーズのフックに統合する。

### PreProcess — 引数の前処理

パーサに渡る前に引数配列を変換する。

```moonbit
// @file 展開: @args.txt → ファイル内容を引数に展開（gcc/javac 方式）
parser.add_preprocessor(fn(args) {
  args.flat_map(fn(a) {
    if a.starts_with("@") { read_lines(a.substring(1)) } else { [a] }
  })
})
```

組み込みプリプロセッサ候補:
- `@file` 展開

注: `-abc` → `-a -b -c` の短縮オプション展開はスコープ Reducer の責務に移動（前述）。

### Reduce — 先食い最長一致の消費ループ

ReduceCtx[T] 方式 + try_reduce による先食い最長一致（前述）。パーサのコアロジック。

### Validate — 制約チェック

消費完了後に制約を検証する。早期確定可能なものは消費中にも検証。

```moonbit
// 組み込み便利関数（内部で制約フックを登録）
parser.exclusive([json, csv, yaml])
parser.exclusive([json, csv, yaml], required=true)  // ちょうど1つ必須
parser.at_least_one([json, csv, yaml])              // 最低1つ必須

// Opt レベルの宣言的 requires（OptMeta ではなくフックとして登録）
opt::string(name="delimiter", requires=[Require(format, value="csv")])

// カスタム制約
parser.add_constraint(Constraint(
  check=fn(ctx : ValidateCtx) -> Unit!ParseError { ... },
  help_hint="--delimiter requires --format=csv",  // ヘルプ・補完に反映
))
```

### Finalize — 後処理

全引数確定後の値の変換・補完。

```moonbit
// 他の値を参照して自動補完
parser.add_finalizer(fn(ctx : FinalizeCtx) {
  if ctx.get(output).is_none() {
    let ext = match ctx.get(format) { Some("json") => ".json"; _ => ".txt" }
    ctx.set(output, "output" + ext)
  }
})
```

### Output — 表示系フック

3段階のカスタマイズ深度（ヘルプ・補完・エラーで共通の考え方）:

**Level 0: 自動生成**（組み込み。OptMeta + Visibility から生成）

**Level 1: 部分フック**（一部だけ調整）

```moonbit
// 補完: 候補リストだけ動的生成
let file = opt::string(name="config",
  completer=fn(ctx : CompleteCtx) -> Array[CompletionCandidate] {
    glob("*.toml").map(fn(p) { { value: p, description: Some("Config file") } })
  },
)

// ヘルプ: 部分的な挿入・変換
let app = cmd("myapp",
  help_hook=CmdHelpHook(
    insert_after=fn(ctx : HelpCtx) -> Array[String] {
      ["", "Examples:", "  myapp serve --port 3000"]
    },
    transform=fn(sections, ctx : HelpCtx) -> Array[HelpSection] { ... },
  ),
)
```

**Level 2: 全面差し替え**（完全カスタム）

```moonbit
parser.set_completion_handler(fn(ctx : CompleteCtx) -> CompletionOutput { ... })
parser.set_help_handler(fn(ctx : HelpCtx) -> String { ... })
```

### CompletionCandidate

```moonbit
///|
struct CompletionCandidate {
  value : String
  description : String?       // zsh/fish の説明表示
  group : String?             // zsh のグループ分け
  style : CompletionStyle?    // 警告色等（dependent の警告表示用）
}
```

---

## エラーメッセージ設計

### 出力構造

clap の4層構造を採用し、Swift ArgumentParser の Help 行を追加:

```
error: unknown option '--prot'
  Help: --port <PORT>    ポート番号を指定 [default: 8080]
  tip: a similar option exists: '--port'
Usage: myapp serve [OPTIONS] <DIR>
For more information, try '--help'.
```

### サジェスト

- Levenshtein 距離ベースの did-you-mean（オプション名・サブコマンド名の両方）
- bpaf 式のコンテキスト認識: "not expected in this context"（スコープ外のオプション検出）

### セマンティックスタイリング

| カテゴリ | 用途 | 例 |
|---------|------|-----|
| error | エラーラベル | `error:` |
| valid | 正しい部分 | `myapp serve` |
| invalid | 問題の部分 | `--prot` |
| literal | リテラル値 | `'--port'` |
| hint | 提案・補足 | `tip:`, `Help:` |

### ParseError 設計

```moonbit
///|
enum ParseError {
  Usage(ErrorKind, String, ErrorContext)  // ユーザー起因エラー
  Internal(String)                        // パーサ内部エラー
}

///|
enum ErrorKind {
  UnknownOption; UnexpectedArgument; MissingRequired; InvalidValue
  ArgumentConflict; AmbiguousMatch; MissingValue; TooManyValues
  MissingSubcommand; PositionalAsFlag; MultipleUse
}
```

---

## リザルト取得・構造化出力

### ValueSource

パース結果の値がどのソースから来たかを追跡:

```moonbit
///|
enum ValueSource {
  Initial         // Opt 定義時の initial 値（未指定）
  Default(String) // default ソース名（"config", "profile" 等）
  Environment     // 環境変数から
  CommandLine     // CLI 引数から
}
```

### API

```moonbit
result.get(opt)         // -> T        値を取得
result.source(opt)      // -> ValueSource  値のソースを取得
result.is_explicit(opt) // -> Bool     Initial/Default 以外なら true
```

### 構造化出力

```moonbit
// 全パース結果をフラット列挙（JSON 等のシリアライズはユーザー側）
result.to_entries()  // -> Array[(String, String, ValueSource)]
                     //    (name, value_str, source)
```

### サブコマンドディスパッチ

- **プライマリ**: callback 方式（cmd 定義時にハンドラ登録）
- **セカンダリ**: `result.command()` で手動分岐

---

## Mutual Exclusion（排他オプション）

```moonbit
let json = opt::flag(name="json")
let csv = opt::flag(name="csv")
let yaml = opt::flag(name="yaml")

// 最大1つ（どれも指定しなくてもOK）
let format = exclusive([json, csv, yaml])

// ちょうど1つ（必須）
let format = exclusive([json, csv, yaml], required=true)
```

- **消費時**: 同グループの別オプションが既に消費済みなら即 `ParseError(Exclusive)`（早期確定）
- エラー: `error: --csv cannot be used with --json`
- `exclusive()` はバリデーション制約を Parser に登録するだけ。各 Opt の値は個別に取得する

---

## Dependent Options（条件付きオプション）

```moonbit
let ssl = opt::flag(name="ssl")
let ssl_cert = opt::string(name="ssl-cert", requires=[ssl])

let format = opt::string(name="format", choices=["json", "csv", "tsv"])
let delimiter = opt::string(name="delimiter", requires=[Require(format, value="csv")])
// カスタム述語
let delimiter = opt::string(name="delimiter", requires=[RequireWhen(format, fn(v) { v != "json" })])
```

- **基本は finalize 時**チェック。依存先の値が確定済みなら早期エラーも可
- エラー: `error: --delimiter requires --format=csv`
- 補完連携: 依存元未指定なら description に警告表示

### ReduceCtx 経由の途中参照

```moonbit
let delimiter = opt::custom(
  name="delimiter",
  initial=",",
  reducer=fn(ctx) {
    let fmt = ctx.get(format)
    match (ctx.action, fmt) {
      (Value(Some(s)), Some("csv")) => Some(s)
      (Value(_), _) => raise ParseError::DependencyNotMet("--delimiter requires --format=csv")
      _ => None
    }
  },
)
```

---

## 環境変数連携

### 3つの方式

**1. 個別指定**: `opt::int(name="port", env="PORT")`

**2. プレフィックス連結**: `cmd("myapp", env_prefix="MYAPP")` + `opt::int(name="port", env="PORT")` → `MYAPP_PORT`

**3. auto-env**: `cmd("myapp", env_prefix="MYAPP", auto_env=true)` → 全オプション自動バインド

### サブコマンドのプレフィックスネスト

```
myapp serve --port 8080 → MYAPP_SERVE_PORT
```

### オーバーライド

env でフルパス指定すればプレフィックスを無視。

### Opt レベルの auto-env 制御

```moonbit
let app = cmd("myapp", env_prefix="MYAPP", auto_env=true)
let port = opt::int(name="port")                           // None → 親に従う（MYAPP_PORT）
let secret = opt::int(name="secret-key", auto_env=false)   // false → auto-env 無効
let debug = opt::flag(name="debug", auto_env=true)         // true → 親が auto_env=false でも有効
```

- `None`（デフォルト）: 親 Cmd の設定を継承
- `Some(true)`: この Opt は auto-env 有効（親が無効でも）
- `Some(false)`: この Opt は auto-env 無効（親が有効でも）

### 安全性

- auto-env はデフォルト無効
- Opt レベルの `auto_env=false` で漏洩を個別に防止
- `visibility` 属性との連動: Hidden/Advanced → auto-env デフォルト Off（明示 `true` で上書き可）

---

## Visibility — ヘルプ・補完の表示制御

```moonbit
///|
enum Visibility {
  Visible      // デフォルト
  Advanced     // help ✗, 補完 ✓（パワーユーザー向け）
  Deprecated   // help ✓（deprecated 注記）, 補完 ✗
  Hidden       // help ✗, 補完 ✗
}
```

| | help | help-all | 補完 | 手入力 |
|--|------|----------|------|--------|
| Visible | yes | yes | yes | yes |
| Advanced | no | yes | yes | yes |
| Deprecated | yes (注記) | yes (注記) | no | yes (警告) |
| Hidden | no | yes | no | yes |

- `help_all=true` で `--help-all` フラグ自動追加
- ショート別名は独立 Opt ではなくロングオプションのヘルプ行に併記
- deprecated 別名は手入力時に警告表示

---

## 大統一設計の概念一覧

| 概念 | 表現 |
|---|---|
| オプション | `Opt[T]` kind=Option |
| サブコマンド | `Opt[T]` kind=Command + 子 Opts |
| 位置パラメータ | `Opt[T]` kind=Positional |
| 固定長引数列 | `serial(o1, o2, ...)` |
| 可変長引数 | `rest(opt)` |
| 排他選択 | `or(...)` |
| 繰り返しグループ | `group(name, tmpl)` — 雛形 clone、新 clone ID 発行 |
| スコープグローバル | `meta.global = true` |
| greedy | `meta.greedy = true` — 消費ループで非 greedy 候補を除外 |
| never | `never()` — 常に ParseError。serial 末尾のセンチネル |
| `--` (double dash) | `flag(name="", greedy=true, global=true)` + serial で統一表現 |
| 先食い最長一致 | 全 OC ノードに try_reduce → 最長 consumed を採用 |
| P モード | OC 全滅後。Option 割り込み可、Command 不可 |
| 結果保持 | `ResultMap`（Opt immutable、ID ベース） |
| reducer コンテキスト | `ReduceCtx[T]` — 1引数方式で後方互換 |
| 名前マッチング | `match_name` ユーティリティ（try_reduce 内部で使用） |
| 表示制御 | `Visibility` (Visible/Advanced/Deprecated/Hidden) |
| 排他オプション | `parser.exclusive([...])` — Validate フェーズの制約フック |
| 条件付きオプション | `requires=[...]` — Validate フェーズの制約フック |
| 環境変数連携 | `env`, `env_prefix`, `auto_env` — Finalize フェーズ |
| 値のソース | `ValueSource` (Initial/Default/Environment/CommandLine) |
| パイプライン | PreProcess → Reduce → Validate → Finalize → Output |
| 補完候補 | `CompletionCandidate` struct |

---

## 実装計画

5フェーズパイプライン（PreProcess → Reduce → Validate → Finalize → Output）に基づき、MVP → 拡張の2段階で実装する。

### パッケージ構成方針

```
src/
  core/         # Opt[T], OptMeta, ErasedNode, InitialValue, Parser struct,
                # match_name ユーティリティ等の型定義
  parse/        # 消費ループ（Reduce フェーズのコアロジック）+ スコープ認識短縮展開
  validate/     # 制約チェック（Validate フェーズ）
  finalize/     # デフォルト適用・環境変数連携（Finalize フェーズ）
  output/       # ヘルプ・補完・エラー表示（Output フェーズ）
  preprocess/   # 引数前処理（PreProcess フェーズ）
  combinators/  # flag, string_opt, int_opt 等のコンビネータ関数群
```

旧設計の `resolve/` パッケージは廃止。名前マッチング機能は `core/` の `match_name` ユーティリティに統合。

---

### MVP フェーズ（動くパーサ: フラグ + 値オプション + サブコマンド）

#### Step 0: 準備

- `src/lib/` を `src/lib-old/` にリネーム（テストケース参照用に保持）
- `src/` をゼロから作り直す（上記パッケージ構成で初期化）
- justfile 更新（新パッケージ構成に対応）
- **パッケージ**: なし（ディレクトリ構造のみ）
- **テスト**: `moon check` が通ること

#### Step 1: 型定義（core/）

PoC3, PoC4 検証済みの型をプロダクション品質で実装する。

- `Opt[T]` — id, initial, reducer, meta, getter（PoC4 の Parser struct + getter 方式）
- `OptMeta` — name, kind, shorts, aliases, inversion, visibility, global, greedy 等
- `InitialValue[T]` — Immediate / Lazy
- `ErasedNode` — 型消去 struct（arity フィールドなし。try_reduce の新シグネチャ）
- `TryReduceResult` — Accept(consumed, result) / Reject
- `ReduceResult` — opaque な型消去一時結果
- `Parser` struct — seq, refs, clone_map（PoC4 の ID 空間一元管理）
- `ReduceCtx[T]` — 1引数方式（PoC4 検証済み）
- `ReduceAction` — Value(String?) / Negate（try_reduce 内部用）
- `match_name` — 名前マッチングユーティリティ（旧 resolve の全機能を内包）
- `MatchResult` — Matched(action) / NotMatched
- `ValueSource` — Initial / Default / Environment / CommandLine
- `Kind`, `Visibility`, `ShortEntry`, `AliasEntry`, `FlagInversion` 等の補助型
- **依存**: Step 0
- **パッケージ**: `core/`
- **テスト**: 型の生成・Hash/Eq・InitialValue の即値/遅延評価、match_name の各パターン（完全一致、エイリアス、プレフィックス、反転、= 付き値分解、曖昧時）

#### Step 2: コンビネータ関数群（combinators/）

Parser のメソッドとして実装。内部で Opt[T] + ErasedNode を生成し Parser に登録。

- `parser.flag(name=...)` — Bool フラグ
- `parser.string(name=...)` — String オプション
- `parser.int(name=...)` — Int オプション
- `parser.cmd(name=..., children=...)` — サブコマンド
- `parser.positional(name=...)` — 位置パラメータ
- `opts([...])` — Opt リストのラッパー
- `serial(...)`, `rest(...)` — 位置パラメータの構造化
- **依存**: Step 1
- **パッケージ**: `combinators/`（`core/` に依存）
- **テスト**: 各コンビネータが正しい OptMeta と reducer を持つ Opt を生成すること

#### Step 3: 先食い最長一致の消費ループ（parse/）

パーサのコアロジック。Reduce フェーズの実体。

**先食い最長一致の消費ループ**:

- 全 OC ノードに try_reduce を投機的に呼び、Accept を収集
- greedy フィルタ → consumed による最長一致選択 → commit_reduce で確定
- OC/P モード切り替え
- サブコマンドマッチ時のスコープ切り替え
- 短縮オプション展開（スコープ Reducer の責務としてスコープ認識で展開）

**名前マッチングは try_reduce 内部で実行**（core/ の match_name を使用）:

- ロングオプション完全一致
- エイリアスマッチ
- プレフィックスマッチ（スコープ Reducer が曖昧判定）
- 反転パターン（`--no-xxx`, `--enable-xxx`, `--disable-xxx`）
- `=` 付き値分解

- `parser.parse(args, root_opts)` → 結果は Parser 内の refs に書き込まれる
- `parser.get(opt)` → getter クロージャ経由で型付き値を取得
- **依存**: Step 1, Step 2
- **パッケージ**: `parse/`（`core/`, `combinators/` に依存）
- **テスト**: フラグ/値オプション/位置パラメータの基本パース、サブコマンド切り替え、OC/P モード遷移、`--` 処理、未知オプションエラー、先食い最長一致の確認、プレフィックスマッチの曖昧エラー

**MVP マイルストーン**: Step 0-3 完了で「フラグ + 値オプション + 位置パラメータ + サブコマンド」の基本パーサが動作する。`parser.parse(args, opts) → parser.get(opt)` のエンドツーエンドが通る状態。

---

### 拡張フェーズ（フック・制約・出力）

#### Step 4: フックパイプライン基盤

5フェーズのフック登録・実行基盤を Parser に実装。

- `parser.add_preprocessor(fn)` — PreProcess フック登録
- `parser.add_constraint(fn)` — Validate フック登録
- `parser.add_finalizer(fn)` — Finalize フック登録
- フックチェーンの実行順序管理（登録順）
- `parser.parse()` 内部をフックパイプライン駆動に再構成
- **依存**: Step 3
- **パッケージ**: `core/` に Parser メソッド追加 + 各フェーズパッケージの接続
- **テスト**: フック登録・実行順序、カスタムフックの動作

#### Step 5: Validate フェーズ（validate/）

制約チェック。組み込み便利関数はフックを登録する薄いラッパー。

- `parser.exclusive([...])` — 排他オプション
- `parser.exclusive([...], required=true)` — ちょうど1つ必須
- `parser.at_least_one([...])` — 最低1つ必須
- `requires=[...]` — 条件付きオプション
- required オプションの未指定チェック
- カスタム制約（`Constraint` struct + `help_hint`）
- **依存**: Step 4
- **パッケージ**: `validate/`
- **テスト**: 排他、必須、条件付き、カスタム制約のそれぞれで pass/fail ケース

#### Step 6: Finalize フェーズ（finalize/）

デフォルト適用・環境変数連携・後処理。

- defaults 置き換え方式（各ソースごとに独立 ResultMap → 後勝ちマージ）
- 環境変数連携: `env`（個別指定）、`env_prefix`（プレフィックス）、`auto_env`（自動）の3方式
- ValueSource トラッキング
- カスタム Finalizer
- **依存**: Step 4
- **パッケージ**: `finalize/`
- **テスト**: defaults のソース優先順位、環境変数の3方式、ValueSource の正確な記録

#### Step 7: PreProcess フェーズ（preprocess/）

引数配列の前処理。

- `@file` 展開（gcc/javac 方式）
- カスタムプリプロセッサ
- **依存**: Step 4
- **パッケージ**: `preprocess/`
- **テスト**: `@file` 展開、複数プリプロセッサの連鎖

#### Step 8: Output フェーズ — エラーメッセージ（output/）

4層構造 + ErrorKind。

- ErrorKind enum + ParseError 構造化
- 4層エラー出力（error / Help 行 / tip / Usage）
- did you mean? サジェスト（Levenshtein 距離。旧 Resolve フックの機能を Reduce フェーズのフックとして統合）
- **依存**: Step 4
- **パッケージ**: `output/`
- **テスト**: 各 ErrorKind のフォーマット、did you mean? の候補精度

#### Step 9: Output フェーズ — ヘルプ生成（output/）

3段階カスタマイズ。

- Level 0: OptMeta + Visibility からの自動生成
- Level 1: 部分フック
- Level 2: 全面差し替え
- セクション構成: サブコマンド一覧 / オプション / グローバルオプション / 環境変数
- **依存**: Step 5, Step 6（制約の help_hint、環境変数情報が必要）
- **パッケージ**: `output/`
- **テスト**: 自動生成のフォーマット、Visibility によるフィルタ、フック適用

#### Step 10: Output フェーズ — 補完生成（output/）

3段階カスタマイズ + CompletionCandidate。

- Level 0: OptMeta からの自動補完候補
- Level 1: `completer` フック（動的候補）
- Level 2: 全面差し替え
- シェル別出力形式（bash/zsh/fish）
- セルフ呼び出しプロトコル
- **依存**: Step 9
- **パッケージ**: `output/`
- **テスト**: 各シェルの出力形式、動的候補、コンテキスト対応補完

#### Step 11: 拡張コンビネータ + Group

MVP のコンビネータに加えて高度な機能を追加。

- `count` — カウンタ（`-vvv`）
- `append` — 繰り返し蓄積（`--tag a --tag b`）
- `optional_value` — 値省略可能オプション
- `or(...)` — 排他選択
- `group(name, tmpl)` — 繰り返しグループ（雛形 clone、clone ID 発行）
- `never()` — serial 末尾のセンチネル
- `custom(fn)` — ユーザー定義 reducer
- **依存**: Step 4（フックパイプライン基盤）
- **パッケージ**: `combinators/` 拡張
- **テスト**: 各コンビネータの消費・蓄積動作、group の clone と ID 管理

#### Step 12: テスト完全移行

poc/poc1-2 の 399 テストケースが検証する「要件」を全て新 API で書き直す。

- 要件抽出 → 新 API でテスト作成（直接のテスト移植ではなく要件ベース）
- poc/poc4 の 14 構造テストも新 API で再実装
- カバレッジ確認
- **依存**: Step 11（全コンビネータ実装後）
- **パッケージ**: 全パッケージのテスト
- **テスト**: 399 要件の網羅

---

### 依存関係図

```
Step 0 ─→ Step 1 ─→ Step 2 ─→ Step 3 ─→ [MVP マイルストーン]
                                    ↓
                                Step 4（フック基盤）
                              ┌──┬──┼──┐
                              ↓  ↓  ↓  ↓
                           St5 St6 St7 St11
                              │  │
                              ↓  ↓
                             Step 9 ─→ Step 10
                                          │
                           Step 8         │
                              │           │
                              └─────┬─────┘
                                    ↓
                                 Step 12
```

Step 5, 6, 7, 8, 11 は互いに独立しており並行実装可能。Step 9 は Step 5, 6 に依存（制約と環境変数の情報がヘルプに必要）。Step 10 は Step 9 に依存。Step 12 は全ステップ完了後。

### テスト方針

各 Step で TDD（t_wada 流）を実践:

1. 要件からテストを書く（RED）— poc/poc1-2 の 399 ケースは「要件集」として参照
2. 実装する（GREEN）
3. リファクタ
4. `moon test -u` でスナップショットテスト活用
5. `just` で check + test 確認
6. `just release-check` で品質確認（fmt + info + check + test）

---

## 未解決・要検討事項

1. **ユーザー API のインターフェース設計** — `opts([o1, o2, o3])` ヘルパーは確定。builder パターン等の追加はまだ検討中
2. **or の結果型と required の関係** — or の子は自動で `required=false`。どちらもマッチしなかった場合の表現
3. **completion の詳細設計** — 3段階カスタマイズ + CompleteCtx + CompletionCandidate は設計済み。シェル別出力形式の詳細は未着手
4. **ヘルプ生成** — 3段階カスタマイズ + HelpCtx は設計済み。具体的なフォーマット詳細は未着手
5. **kind の区別のユーザー API 表現** — コンビネータで暗黙決定する方式で進行中
6. **複数値パラメータは常に Array** — `aliases`, `shorts` 等は MoonBit コアでは常に `Array`。ターゲット別ラッパーで各言語の慣用的 DX を提供

### 将来実装（優先度はその時の気分）

- **did you mean? サジェスト** — Reduce フェーズのフックとして実装。Levenshtein 距離によるスペルミス候補提示
- **エラーメッセージ品質** — Output フェーズ。既存最高峰以上を目指す
- **中間 rest 対応** — `mv file... dir` パターン。ReduceCtx.ahead() で先読み
- **mutual exclusion** — Validate フェーズの制約フック
- **dependent options** — Validate フェーズの制約フック + ReduceCtx 途中参照
- **リザルト取得サポート** — シンプル JSON 出力等
- **ヘルプ生成** — Output フェーズ。3段階カスタマイズ
- **補完生成** — Output フェーズ。3段階カスタマイズ + CompleteCtx + CompletionCandidate
- **@file 展開** — PreProcess フェーズのフック。gcc/javac 方式
- **環境変数連携** — 個別env / プレフィックス / auto-env の3方式
- **Visibility** — Visible/Advanced/Deprecated/Hidden の4段階
