# Phase 4: Reducer 大統一設計

## Context

- Phase 1-3 の PoC は「テストケース = 要件」として引き継ぐ。コードは全削除して完全作り直し
- 核心: 全 OptKind を `initial + ReduceCtx reducer` で統一
- heterogeneous collection は ErasedNode struct（クロージャ束）で実現（trait object 不使用）
- String ベースの中間表現は不要。T ベースで直接動作

Design rationale: 旧設計では `Map[String, Array[String]]` による String ベースの中間表現を使い、
`ReduceContext` で初期値・デフォルト・明示設定フラグを運搬していた。新設計では ErasedNode struct が
型を閉じ込めたクロージャ群を保持することで heterogeneous collection を実現し、String への変換・逆変換が
完全に不要になり、型安全性が向上する。

---

## 設計原則

- **Opt[T] は完全 immutable** — 定義情報のみ保持。一意 ID でResultMap のキーとして機能
- **parse はツリーを走査して ResultMap に結果を書き込む** — `ErasedNode` struct 経由で型を知らずに操作
- **ユーザーは `result.get(opt)` で型付きの値を取得** — Opt[T] がレンズ/キーとして機能
- **defaults は優先順位付きソースからの置き換え**（積み上げではない） — 後のソースが前を丸ごと上書き
- **reducer はシンプルに `(ReduceCtx[T]) -> T?!ParseError`** — None = マッチしない（候補から脱落）、Some(T) = 消費成功、raise ParseError = エラー

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
  reducer : (ReduceCtx[T]) -> T?!ParseError
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

### ReduceAction

```moonbit
///|
pub(all) enum ReduceAction {
  /// 正方向: Flag/Count は None、Single/Append は Some(value)
  Value(String?)
  /// 反転: --no-xxx。reducer が initial にリセット等を判断
  Negate
} derive(Eq, Show, Debug)
```

### ReduceCtx[T] と reducer 統一パターン

全ての OptKind は `(ReduceCtx[T]) -> T?!ParseError` の reducer で表現される。OptKind enum は不要。

```moonbit
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
| Single | `None` | `(ctx) -> match ctx.action { Value(Some(s)) => Some(Some(parse!(s))); Negate => Some(initial); _ => None }` |
| Append | `[]` | `(ctx) -> match ctx.action { Value(Some(s)) => Some([..ctx.current, parse!(s)]); Negate => Some(initial); _ => None }` |
| OptionalValue | `None` | `(ctx) -> match ctx.action { Value(None) => Some(Some(implicit)); Value(Some(s)) => Some(Some(s)); _ => None }` |

プリミティブ型コンビネータは custom の特殊化: `opt::int` = `opt::custom(parse_int)`

Design rationale: reducer のシグネチャを `(ReduceCtx[T]) -> T?!ParseError` の1引数に統一する。
旧設計の `(T, ReduceAction)` 2引数、その後の `(T, ReduceAction, ParseContext)` 3引数を経て、
**後方互換性**を重視した最終形。ReduceCtx に新しいメソッドを追加しても既存 reducer は壊れない。
MoonBit ではクロージャにラベル付き/オプション引数が使えない（言語制約）ため、struct ラッパーが最適解。
エラーパスは MoonBit の raise 構文で伝搬する。`parse!(s)` が失敗した場合、reducer から ParseError が raise される。
reducer の戻り値は3値: `None`（マッチしない = 候補脱落）、`Some(T)`（消費成功）、raise `ParseError`（エラー）。
消費ループの step 3 で各候補の reducer に引数を渡し、None を返すものを除去する仕組みの根幹。
例: flag は常に Some(true)、since に "1h3m" → Some(Duration)。

reducer の3値の設計根拠:
- None: 「この引数を食えない」= 消費ループの候補選定で使用。他の候補を試す
- Some(T): 「この引数を消費した」= 結果を ResultMap に書き込む
- ParseError: 「マッチしたがバリデーション失敗」= 即座にエラー

重要: None と ParseError の使い分けは**名前解決の前後で異なる**:
- 名前解決前（positional の候補選定等）: 型が合わない → None（他の候補を試す）
- 名前解決後（`--port abc` で port が確定済み）: 値の型変換失敗 → ParseError（エラーを握り潰さない）

例: `--port 123` → 名前解決で port 確定 → int parse "123" → Some(123)。
例: `--port abc` → 名前解決で port 確定 → int parse "abc" → raise ParseError（None にすると別候補に流れて誤動作）。
例: positional の候補選定で "abc" を int と file が競合 → int は None、file が Some → file が消費。

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
(1) **型消去ビュー** — `reduce_erased` クロージャが `Ref[T]` をキャプチャし、T を知らずに操作
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

clone の内部メカニズム:
- `clone()` が新 ID を発行し、`clone_fns` を順に呼ぶ
- 各 clone_fn が対応する Opt[T] の `slots` に新 ID 対応の独立 `Ref[T]` を作成
- 雛形の Opt[T] をレンズとして使う際、`opt.slots[cloned_result.id]` で正しい値にアクセス

clone ID は雛形横断の sequential な一意 ID（グローバルインクリメント）。複合キー (template_id, clone_id) は不要で、clone ID 単体で一意に識別できる。

各グループの ResultMap は独立インスタンスなので、ResultMap 内では雛形の template_id をキーに使える（衝突しない）。

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
clone ID がグローバルに一意なので、雛形 ID との組み合わせ（複合キー）は不要。
各グループの ResultMap は独立インスタンスであり、内部では雛形の template_id をキーとして使用する。
defaults のスナップショットは ResultMap の clone（clone_fns 経由で各 Opt の Ref を複製）で完結。

---

## ErasedNode — 型消去 struct（クロージャ束）

parse がツリーを走査するための型消去 struct。クロージャ群が T を閉じ込め、parse は具体的な T を知る必要がない。

```moonbit
///|
pub(all) struct ErasedNode {
  meta : OptMeta
  arity : Int
  try_reduce : (ReduceAction, ResultMap) -> ReduceResult!ParseError
  // 試行モード: 判定のみ行い ResultMap には書き込まない。成功なら ReduceResult に確定値を保持
  commit_reduce : (ReduceResult, ResultMap) -> Unit
  // 確定モード: try_reduce で得た結果を ResultMap に書き込む（候補が1つに確定した後に呼ぶ）
  // 内部: ReduceCtx[T] { current: ref.val, action, ... } を構築して reducer を呼ぶ
  reset_to_initial : (ResultMap) -> Unit
  children : () -> Array[ErasedNode]       // ツリー走査用
  // 具体的なフィールド構成は実装時に確定
}

// ReduceResult は型消去された一時結果。commit_reduce でのみ使用
// 内部的には ErasedRef 等で型を保持するが、外部からは opaque
type ReduceResult
```

`Opt[T]` から `ErasedNode` を生成する際、各クロージャが `Ref[T]` をキャプチャして T を封じ込める。
parse は `ErasedNode` の配列/ツリーを走査して `reduce_erased` を呼ぶだけ。型を知らない。

`reduce_erased` の内部メカニズム:
- クロージャが Opt[T] の `slots` 内の `Ref[T]` をキャプチャしている
- `result_map.id` を使って正しい Ref を選択し、reducer を適用して書き戻す
- ResultMap への「書き込み」は実際には Opt[T] 側の `Ref[T]` への書き込み

Design rationale: trait object は MoonBit でダウンキャスト不可のため、`result.get(opt)` で型安全に
値を取り出せない。struct（クロージャ束）にすることで trait object を排除しつつ、クロージャが T を
静的に閉じ込める型安全な型消去を実現する。旧設計の `ErasedOpt` trait は `initial_raw`, `reduce_raw`
など String ベースのメソッドを持っていたが、新設計では String への変換が不要。

---

## kind による区別

全ノードに kind を持たせ、マッチ方法を区別する。

| kind | マッチ条件 | name の意味 |
|------|----------|-----------|
| Option | `--name` でマッチ | オプション名 |
| Command | 名前でマッチ | サブコマンド名 |
| Positional | 位置でマッチ | プレースホルダ名 |

---

## greedy — 優先消費

`meta.greedy = true` のノードは、消費ループのマッチ判定で非 greedy 候補を脱落させる。greedy 同士は通常通り1つずつ引数消費で競合する。

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

## 引数消費ループ — parse コアアルゴリズム

### 概要

parse のコアは引数消費ループ。2つのモードを持つ:

- **OC モード（初期）**: Option/Command を優先マッチ。Positional はフォールバック
- **P モード**: OC 全滅後に遷移。Command はもう候補にならない。Option は割り込み可能

kind の優先度: Option = Command > Positional

### アルゴリズム（n番目の引数消費、n=1スタート）

```
0. カレントスコープ = parse に渡された Opts

1. 正規化: Node(opt) → Array([opt])

2. カレントスコープから OC リスト（Option/Command）と P リスト（Positional）を収集
   - コンテナ（Array/serial/or 等）なら再帰的に1つ目の OC を取得
   - フラットな OC リストにする
   - OC に引っかからなかったものは P リストへ

3. 候補選別（副作用なし）: 各 OC の reducer を試行モードで呼び、結果を収集
   - None → 候補脱落（この引数を食えない）
   - Some(T) → 候補残留（結果値を一時保持、まだ ResultMap には書き込まない）
   - raise ParseError → 即座にエラー

4. greedy フィルタ
   残留候補に greedy=true があれば greedy=false を除去

5. OC=0 かつ args(n+1) なし → パース完了。消費ループ脱出

6. OC=0 かつ args(n+1) あり
   6a. P リストなし → ParseError（予期しない引数）
   6b. P リストあり → P モードに遷移して消費ループ継続

7. OC=1 (Node) → 状態確定: step 3 で一時保持した結果値を ResultMap に書き込む。カレントスコープ更新、消費ループ継続

8. （7と同じく単一候補の変種があればここに追加）

9. OC=2+ (全 Node) → ParseError（曖昧）

10. OC=2+ (全 Array) → 各 OC が args(n) を仮消費して
    それぞれの OC で消費ループ継続（並列探索）
    - 1つだけ成功（食い残しなし）→ その結果を採用
    - 全パス成功（食い残しなし）→ ParseError（曖昧）
    - 全パス失敗 → ParseError
```

### P モードの制約

P 消費に遷移した後:

- **Command は候補にならない**（サブコマンド選択は確定済み）
- 消費対象は: そのサブコマンドレベルの Option + グローバル Option + 残り Positional
- Option が見つかったら割り込み消費し、P の消費に戻る

```
P モード:
  token = args(n)
  if token が Option としてマッチ → Option を消費、P に戻る
  else → P リストの次の Positional で消費
```

### スコープ遷移

Command がマッチしたら:

- カレントスコープを Command の子 Opts に切り替え
- `global=true` のノードは親スコープから引き継ぐ
- 以降の消費ループは新スコープ内で OC モードから再開

Design rationale: 引数消費を OC モードと P モードの2層で処理することで、Option/Command を確実に先に解決し、Positional は残り物として扱う。P モードでも Option の割り込みを許容するため、`cmd file1 --verbose file2` のような自然な記述が可能。Command は P モード移行後は候補から外れるため、位置引数とサブコマンド名の衝突を防ぐ。

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
- `result.command() -> ErasedNode?` で選ばれたサブコマンドを取得。None はトップレベルまたはサブコマンド以外の result の場合

**result.get の型契約**: `result.get(opt : Opt[T]) -> T` は常に `T` を返す（`T?` ではない）。
スコープ外の Opt は initial 値が返る。「指定されたか」を知りたい場合は `result.source(opt) -> ValueSource` を使い、`ValueSource::Initial` ならスコープ外または未指定と判断する。
これにより利用側は `T?` のアンラップを強いられず、型が安定する。
- `meta.global` フラグでスコープ付きグローバル。そのスコープ以下全体に伝搬。トップに置けば全体グローバル、特定サブコマンドに置けばその配下のみ

### 位置パラメータの表現

```moonbit
// 固定長、順番消費
serial(file, dir)

// 可変長、単一 Opt の繰り返し
rest(path)

// 組み合わせ: 固定 + 末尾 rest
serial(file, rest(path))    // zip = zip file path1 path2 ...

// rest が末尾以外は未サポート（将来検討）
// serial(rest(file), dir)  // mv = mv file1 file2 ... dir（未サポート）
```

Design rationale: 位置パラメータは serial で固定長順番消費、rest で可変長消費を表現。組み合わせは serial + 末尾 rest のみ現時点でサポート。中間 rest（rest の後に固定パラメータ）は論理的には可能だが複雑なため将来検討。

### `--` (double dash) の表現

`--` を特殊トークンとしてハードコードするのではなく、通常の Opt として統一的に表現する。

- `flag(name="", greedy=true, global=true)` で `--` にマッチ（name="" = 名前なし = `--` そのもの）
- greedy なので、他の非 greedy 候補がいても `--` 以降は greedy 候補のみで消費

```moonbit
// -- は name="" の greedy フラグ
let double_dash = flag(name="", greedy=true, global=true)

// 固定長 positionals の場合: never() で余剰消費を防止
let hh = serial(double_dash, file1, file2, never())

// rest ありの場合: rest が全て吸収するので never() 不要
let hh = serial(double_dash, rest(path))
```

Design rationale: 従来 `--` は tokenize 段階で `DoubleDash` として特殊トークン化し、パーサ内でハードコードされた特殊処理をしていた。greedy + serial の組み合わせで `--` を通常の Opt として表現することで、特殊処理が不要になり、`--exec` 的な「以降全て引数」パターンにも同じ仕組みで対応できる。

---

## defaults（置き換え方式）

各デフォルトソースは独立。旧設計の ReduceContext は不要。

**解決策**: 各ソースごとに新しい ResultMap（initial から）で parse し、最後に**明示指定のみ後勝ちマージ**する。同一 ResultMap への累積 parse ではない。

**マージルール**: 各 Opt について、後のソースで**明示的に指定された値のみ**が前のソースの値を上書きする。未指定（initial のまま）の Opt は上書きしない。これにより下位ソースの値が消し飛ぶ事故を防ぐ。

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

defaults のスナップショットは ResultMap の clone で完結する。clone はクロージャレジストリ（clone_fns）経由で各 Opt の Ref を複製する方式。Map の単純コピーではなく、clone_fns を呼んで新 ID に対応する独立 Ref を作成する。

Design rationale: 旧設計では `ReduceContext.defaults` と `explicitly_set` で
Append の replace/stacking semantics を制御していた。新設計では defaults は
単純な「後勝ち」方式。各ソースごとに initial から新規 ResultMap を作って parse し、
最後にマージする。同一 ResultMap に累積 parse するのではなく、独立した結果を後勝ちで合成する。
Append の replace semantics は「CLI で --tags が1回でも指定されたら、previous source の tags を
破棄して CLI 指定分だけにする」という単純なルールになる。ResultMap のコピーでスナップショットが取れるため、ロールバックも容易。

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
enum Kind {
  Option
  Command
  Positional
}

struct ShortEntry {
  char : Char
}

struct AliasEntry {
  name : String
  deprecated : Bool  // deprecated 別名の警告表示
}

enum FlagInversion {
  No                         // --no-xxx
  EnableDisable              // --enable-xxx / --disable-xxx
  Custom(String, String)     // カスタムプレフィックスペア
}
```

---

## 未解決・要検討事項

1. **ユーザー API のインターフェース設計** — `opts([o1, o2, o3])` ヘルパーは確定。builder パターン等の追加はまだ検討中
2. **or の結果型と required の関係** — or の子は自動で `required=false`。どちらもマッチしなかった場合の表現
3. **completion の詳細設計** — 3段階カスタマイズ + CompleteCtx + CompletionCandidate は設計済み。シェル別出力形式の詳細は未着手
4. **ヘルプ生成** — 3段階カスタマイズ + HelpCtx は設計済み。具体的なフォーマット詳細は未着手（参考: help-format-survey.md）
5. **kind の区別のユーザー API 表現** — コンビネータ（opt::flag, opt::int, cmd() 等）で暗黙決定する方式で進行中
6. **複数値パラメータは常に Array** — `aliases`, `shorts` 等は MoonBit コアでは常に `Array` で受ける。ターゲット別ラッパー（TS なら `string | string[]` 等）で各言語の慣用的 DX を提供

### コア設計: Parser struct + getter 方式（PoC4 検証済み・採用）

cobra-style (#3) とハイブリッド (#4) を統合する新方向性。

**概要**: Parser struct が ID 空間と ref ストレージを一元管理。Opt[T] は getter クロージャで型消去を解決。

```moonbit
struct Parser {
  mut seq : Int              // ローカル ID カウンタ（テスト分離）
  refs : Map[Int, RefV]      // id → 値の一元管理
  clone_map : Map[Int, Int]  // clone_id → template_id（clone 時に登録）
}

enum RefV {
  Value(ErasedRef)           // 個別 opt インスタンス
  Array(Array[ErasedRef])    // グループの全インスタンス一覧
}

struct Opt[T] {
  id : Int                   // 一意 ID（これだけ）
  initial : InitialValue[T]
  reducer : (ReduceCtx[T]) -> T?!ParseError
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

**検証結果**:
- 基本 parse+get: 実現可能（getter クロージャ）
- グループ: Parser.refs + clone_map で管理
- defaults マルチソース: Parser 内部で ResultMap.clone 相当を管理
- テスト分離: 完全に解決（Parser ローカル seq）

PoC4 で全4シナリオ検証済み。本方式を採用

### 将来実装（優先度はその時の気分）

- **did you mean? サジェスト** — Resolve フェーズのフックとして実装。Levenshtein 距離によるスペルミス候補提示
- **エラーメッセージ品質** — Output フェーズ。既存最高峰以上を目指す（設計済み）
- **中間 rest 対応** — `mv file... dir` パターン。ReduceCtx.ahead() で先読み
- **mutual exclusion** — Validate フェーズの制約フック（設計済み）
- **dependent options** — Validate フェーズの制約フック + ReduceCtx 途中参照（設計済み）
- **リザルト取得サポート** — シンプル JSON 出力等（設計済み）
- **ヘルプ生成** — Output フェーズ。3段階カスタマイズ（調査レポート: help-format-survey.md）
- **補完生成** — Output フェーズ。3段階カスタマイズ + CompleteCtx + CompletionCandidate
- **@file 展開** — PreProcess フェーズのフック。gcc/javac 方式
- **環境変数連携** — 個別env / プレフィックス / auto-env の3方式（設計済み）
- **Visibility** — Visible/Advanced/Deprecated/Hidden の4段階（設計済み）

---

## パースライフサイクルとフックアーキテクチャ

パーサのコアは各フェーズのパイプラインを回すだけ。具体的な振る舞いはフックで注入する。
組み込みの便利関数（`exclusive()`, `opt::flag()` 等）は内部でフックを登録するだけの薄いラッパー。

```
引数入力 → [PreProcess] → [Resolve] → [Reduce] → [Validate] → [Finalize] → [Output]
```

### フェーズ一覧

| フェーズ | 責務 | フック型 |
|---------|------|---------|
| **PreProcess** | 引数の前処理・正規化 | `(Array[String]) -> Array[String]` |
| **Resolve** | 名前 → Opt の解決 | `(String, ResolveCtx) -> ResolveResult` |
| **Reduce** | 消費ループ（値の畳み込み） | `(ReduceCtx[T]) -> T?!ParseError` |
| **Validate** | 制約チェック | `(ValidateCtx) -> Unit!ParseError` |
| **Finalize** | デフォルト適用・後処理 | `(FinalizeCtx) -> Unit!ParseError` |
| **Output** | ヘルプ/補完/エラー/バージョン | フェーズごとに別型（後述） |

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
- `-abc` → `-a -b -c` の短縮オプション展開（デフォルト有効）

### Resolve — 名前解決

`--name` / `-n` / `--no-xxx` を対応する Opt に解決する。

組み込み: 完全一致 → プレフィックスマッチ → 反転パターン（`--no-`, `--enable-`, `--disable-`）
フック: did-you-mean サジェスト、あいまいマッチ、カスタム辞書

### Reduce — 消費ループ

ReduceCtx[T] 方式（前述）。パーサのコアロジック。

### Validate — 制約チェック

消費完了後に制約を検証する。早期確定可能なものは消費中にも検証。

```moonbit
// 組み込み便利関数（内部で制約フックを登録）
parser.exclusive([json, csv, yaml])
parser.exclusive([json, csv, yaml], required=true)  // ちょうど1つ必須
parser.at_least_one([json, csv, yaml])              // 最低1つ必須

// Opt レベルの宣言的 requires（OptMeta ではなくフックとして登録）
opt::string(name="delimiter", requires=[Require(format, value="csv")])
// requires はコンビネータのパラメータ。内部的に Parser の制約フックとして登録される（OptMeta には含めない）

// カスタム制約
parser.add_constraint(Constraint(
  check=fn(ctx : ValidateCtx) -> Unit!ParseError { ... },
  help_hint="--delimiter requires --format=csv",  // ヘルプ・補完に反映
))
```

`help_hint` によりカスタム制約でもヘルプ・補完に情報を公開可能。

### Finalize — 後処理

全引数確定後の値の変換・補完。

```moonbit
// 他の値を参照して自動補完
parser.add_finalizer(fn(ctx : FinalizeCtx) {
  if ctx.get(output).is_none() {
    // --output 未指定なら --format から拡張子推定
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
// 補完: 候補リストだけ動的生成（最も需要が高い）
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
// 補完: 行全体の書き換え等もここで
parser.set_completion_handler(fn(ctx : CompleteCtx) -> CompletionOutput { ... })

// ヘルプ: 完全にカスタム
parser.set_help_handler(fn(ctx : HelpCtx) -> String { ... })
```

### CompletionCandidate

```moonbit
struct CompletionCandidate {
  value : String
  description : String?       // zsh/fish の説明表示
  group : String?             // zsh のグループ分け
  style : CompletionStyle?    // 警告色等（dependent の警告表示用）
}
```

### 設計上の利点

- **コアが薄い**: パーサ本体はパイプライン駆動。機能追加はフック追加で完結
- **消費ループの分岐が減る**: 制約・出力がフック外出しされスッキリ
- **後方互換**: フェーズ追加やフック型の拡張は既存コードに影響しない
- **テスタビリティ**: 各フックが独立した関数なので単体テスト容易

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
| clone ID | グローバルインクリメントの一意 ID。雛形横断で sequential。複合キー不要 |
| スコープグローバル | `meta.global = true` |
| greedy | `meta.greedy = true` — 消費ループで非 greedy 候補を除外 |
| never | `never()` — 常に ParseError。serial 末尾のセンチネル |
| `--` (double dash) | `flag(name="", greedy=true, global=true)` + serial で統一表現 |
| OC モード | 初期モード。Option/Command 優先、Positional はフォールバック |
| P モード | OC 全滅後。Option 割り込み可、Command 不可 |
| 結果保持 | `ResultMap`（Opt immutable、ID ベース） |
| reducer コンテキスト | `ReduceCtx[T]` — 1引数方式で後方互換 |
| 表示制御 | `Visibility` (Visible/Advanced/Deprecated/Hidden) |
| 排他オプション | `parser.exclusive([...])` — Validate フェーズの制約フック |
| 条件付きオプション | `requires=[...]` — Validate フェーズの制約フック |
| 環境変数連携 | `env`, `env_prefix`, `auto_env` — Finalize フェーズ |
| 値のソース | `ValueSource` (Initial/Default/Environment/CommandLine) |
| パイプライン | PreProcess → Resolve → Reduce → Validate → Finalize → Output |
| 補完候補 | `CompletionCandidate` struct |

---

## 実装計画

6フェーズパイプライン（PreProcess → Resolve → Reduce → Validate → Finalize → Output）に基づき、MVP → 拡張の2段階で実装する。

### パッケージ構成方針

`src/` はフラットにせず機能ごとに分割する。具体的な分割は実装進行に合わせて決定するが、初期構想は以下:

```
src/
  core/       # Opt[T], OptMeta, ErasedNode, InitialValue, Parser struct 等の型定義
  parse/      # 消費ループ（Reduce フェーズのコアロジック）+ スコープ認識局所分解
  resolve/    # 名前解決（Resolve フェーズ）
  validate/   # 制約チェック（Validate フェーズ）
  finalize/   # デフォルト適用・環境変数連携（Finalize フェーズ）
  output/     # ヘルプ・補完・エラー表示（Output フェーズ）
  preprocess/ # 引数前処理（PreProcess フェーズ）
  combinators/ # flag, string_opt, int_opt 等のコンビネータ関数群
```

参考: mizchi の MoonBit リポジトリ群のパッケージ分割構成。

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
- `ErasedNode` — 型消去 struct（PoC3, PoC4 検証済み）
- `Parser` struct — seq, refs, clone_map（PoC4 の ID 空間一元管理）
- `ReduceCtx[T]` — 1引数方式（PoC4 検証済み）
- `ValueSource` — Initial / Default / Environment / CommandLine
- `Kind`, `Visibility`, `ShortEntry`, `AliasEntry`, `FlagInversion` 等の補助型
- **依存**: Step 0
- **パッケージ**: `core/`
- **テスト**: 型の生成・Hash/Eq・InitialValue の即値/遅延評価

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

#### Step 3: スコープ認識局所分解 + 消費ループ（parse/）

パーサのコアロジック。Reduce フェーズの実体。

**スコープ認識局所分解**:

- `--port=8080`: カレントスコープの LongOption に `port` がマッチするなら `--port` + `8080` に分解
- `-abc`: カレントスコープの ShortOption を集めて全文字が完全分解可能なら `-a` + `-b` + `-c` に分解
- マッチしない場合: 分解せず生のまま reducer に渡す
- 生の引数と分解結果は両方保持する（エラー表示で元の引数を表示するため）

Design rationale: 事前 tokenize は全体を一様に分解するため、スコープによってマッチするノードが異なる
状況（サブコマンド切り替え後の短縮オプション等）で分解結果がスコープ文脈に依存する問題がある。
局所分解なら消費ループが現在のスコープを知った状態で分解するため、スコープ外れの誤分解を防げる。

**消費ループ**:

- OC/P モード切り替え（OC: Option/Command 優先、P: Positional 優先）
- 各引数に対し、スコープ内 Opt の reducer を順に試行
- reducer が `Some(T)` → 消費成功、`None` → 候補脱落、`raise` → エラー
- サブコマンドマッチ時のスコープ切り替え
- greedy Opt のマッチ後に非 greedy 候補を除外
- `parser.parse(args, root_opts)` → 結果は Parser 内の refs に書き込まれる
- `parser.get(opt)` → getter クロージャ経由で型付き値を取得
- **依存**: Step 1, Step 2
- **パッケージ**: `parse/`（`core/`, `combinators/` に依存）
- **テスト**: フラグ/値オプション/位置パラメータの基本パース、サブコマンド切り替え、OC/P モード遷移、`--` 処理、未知オプションエラー

#### Step 4: 名前解決（resolve/）

Resolve フェーズの実体。消費ループ内から呼ばれる。

- ロングオプション完全一致
- エイリアスマッチ
- プレフィックスマッチ（曖昧でなければ）
- 反転パターン（`--no-xxx`, `--enable-xxx`, `--disable-xxx`）
- **依存**: Step 1
- **パッケージ**: `resolve/`（`core/` に依存）
- **テスト**: 完全一致、エイリアス、プレフィックス、反転パターン、曖昧時エラー

**MVP マイルストーン**: Step 0-4 完了で「フラグ + 値オプション + 位置パラメータ + サブコマンド」の基本パーサが動作する。`parser.parse(args, opts) → parser.get(opt)` のエンドツーエンドが通る状態。

---

### 拡張フェーズ（フック・制約・出力）

#### Step 5: フックパイプライン基盤

6フェーズのフック登録・実行基盤を Parser に実装。

- `parser.add_preprocessor(fn)` — PreProcess フック登録
- `parser.add_resolver(fn)` — Resolve フック登録（組み込み resolve を差し替え/拡張）
- `parser.add_constraint(fn)` — Validate フック登録
- `parser.add_finalizer(fn)` — Finalize フック登録
- フックチェーンの実行順序管理（登録順）
- `parser.parse()` 内部をフックパイプライン駆動に再構成（Step 3-4 のロジックを Resolve/Reduce フックとして再配置）
- **依存**: Step 3, Step 4
- **パッケージ**: `core/` に Parser メソッド追加 + 各フェーズパッケージの接続
- **テスト**: フック登録・実行順序、カスタムフックの動作

#### Step 6: Validate フェーズ（validate/）

制約チェック。組み込み便利関数はフックを登録する薄いラッパー。

- `parser.exclusive([...])` — 排他オプション（設計済み）
- `parser.exclusive([...], required=true)` — ちょうど1つ必須
- `parser.at_least_one([...])` — 最低1つ必須
- `requires=[...]` — 条件付きオプション（コンビネータのパラメータとして設計済み）
- required オプションの未指定チェック
- カスタム制約（`Constraint` struct + `help_hint`）
- **依存**: Step 5
- **パッケージ**: `validate/`
- **テスト**: 排他、必須、条件付き、カスタム制約のそれぞれで pass/fail ケース

#### Step 7: Finalize フェーズ（finalize/）

デフォルト適用・環境変数連携・後処理。

- defaults 置き換え方式（設計済み: 各ソースごとに独立 ResultMap → 後勝ちマージ）
- 環境変数連携: `env`（個別指定）、`env_prefix`（プレフィックス）、`auto_env`（自動）の3方式（設計済み）
- ValueSource トラッキング（どのソースから値が来たかを記録）
- カスタム Finalizer（`parser.add_finalizer(fn)`）
- **依存**: Step 5
- **パッケージ**: `finalize/`
- **テスト**: defaults のソース優先順位、環境変数の3方式、ValueSource の正確な記録

#### Step 8: PreProcess フェーズ（preprocess/）

引数配列の前処理。

- `@file` 展開（gcc/javac 方式）
- カスタムプリプロセッサ（`parser.add_preprocessor(fn)`）
- **依存**: Step 5
- **パッケージ**: `preprocess/`
- **テスト**: `@file` 展開、複数プリプロセッサの連鎖

#### Step 9: Output フェーズ — エラーメッセージ（output/）

4層構造 + ErrorKind（設計済み）。

- ErrorKind enum + ParseError 構造化
- 4層エラー出力（error / Help 行 / tip / Usage）
- did you mean? サジェスト（Resolve フック連携。Levenshtein 距離）
- **依存**: Step 5
- **パッケージ**: `output/`
- **テスト**: 各 ErrorKind のフォーマット、did you mean? の候補精度

#### Step 10: Output フェーズ — ヘルプ生成（output/）

3段階カスタマイズ。

- Level 0: OptMeta + Visibility からの自動生成
- Level 1: 部分フック（`CmdHelpHook` の `insert_after` / `transform`）
- Level 2: 全面差し替え（`parser.set_help_handler(fn)`）
- セクション構成: サブコマンド一覧 / オプション / グローバルオプション / 環境変数
- **依存**: Step 6, Step 7（制約の help_hint、環境変数情報が必要）
- **パッケージ**: `output/`
- **テスト**: 自動生成のフォーマット、Visibility によるフィルタ、フック適用

#### Step 11: Output フェーズ — 補完生成（output/）

3段階カスタマイズ + CompletionCandidate。

- Level 0: OptMeta からの自動補完候補
- Level 1: `completer` フック（動的候補）
- Level 2: 全面差し替え（`parser.set_completion_handler(fn)`）
- シェル別出力形式（bash/zsh/fish）
- セルフ呼び出しプロトコル
- **依存**: Step 10
- **パッケージ**: `output/`
- **テスト**: 各シェルの出力形式、動的候補、コンテキスト対応補完

#### Step 12: 拡張コンビネータ + Group

MVP のコンビネータに加えて高度な機能を追加。

- `count` — カウンタ（`-vvv`）
- `append` — 繰り返し蓄積（`--tag a --tag b`）
- `optional_value` — 値省略可能オプション
- `or(...)` — 排他選択
- `group(name, tmpl)` — 繰り返しグループ（雛形 clone、clone ID 発行）
- `never()` — serial 末尾のセンチネル
- `custom(fn)` — ユーザー定義 reducer
- **依存**: Step 5（フックパイプライン基盤）
- **パッケージ**: `combinators/` 拡張
- **テスト**: 各コンビネータの消費・蓄積動作、group の clone と ID 管理

#### Step 13: テスト完全移行

poc/poc1-2 の 399 テストケースが検証する「要件」を全て新 API で書き直す。

- 要件抽出 → 新 API でテスト作成（直接のテスト移植ではなく要件ベース）
- poc/poc4 の 14 構造テストも新 API で再実装
- カバレッジ確認
- **依存**: Step 12（全コンビネータ実装後）
- **パッケージ**: 全パッケージのテスト
- **テスト**: 399 要件の網羅

---

### 依存関係図

```
Step 0 ─→ Step 1 ─→ Step 2 ─→ Step 3 ─→ [MVP マイルストーン]
                │               ↑
                └→ Step 4 ──────┘
                                     ↓
                                Step 5（フック基盤）
                              ┌──┬──┼──┐
                              ↓  ↓  ↓  ↓
                           St6 St7 St8 St12
                              │  │
                              ↓  ↓
                             Step 10 ─→ Step 11
                                          │
                           Step 9         │
                              │           │
                              └─────┬─────┘
                                    ↓
                                 Step 13
```

Step 6, 7, 8, 9, 12 は互いに独立しており並行実装可能。Step 10 は Step 6, 7 に依存（制約と環境変数の情報がヘルプに必要）。Step 11 は Step 10 に依存。Step 13 は全ステップ完了後。

### テスト方針

各 Step で TDD（t_wada 流）を実践:

1. 要件からテストを書く（RED）— poc/poc1-2 の 399 ケースは「要件集」として参照
2. 実装する（GREEN）
3. リファクタ
4. `moon test -u` でスナップショットテスト活用
5. `just` で check + test 確認
6. `just release-check` で品質確認（fmt + info + check + test）

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

5カテゴリで出力を装飾（ターミナル対応時）:

| カテゴリ | 用途 | 例 |
|---------|------|-----|
| error | エラーラベル | `error:` |
| valid | 正しい部分 | `myapp serve` |
| invalid | 問題の部分 | `--prot` |
| literal | リテラル値 | `'--port'` |
| hint | 提案・補足 | `tip:`, `Help:` |

### ParseError 設計

```moonbit
enum ParseError {
  Usage(ErrorKind, String, ErrorContext)  // ユーザー起因エラー
  Internal(String)                        // パーサ内部エラー
}

enum ErrorKind {
  UnknownOption; UnexpectedArgument; MissingRequired; InvalidValue
  ArgumentConflict; AmbiguousMatch; MissingValue; TooManyValues
  MissingSubcommand; PositionalAsFlag; MultipleUse
}
```

### 実装優先度

1. **初期**: 基本エラー + 1行メッセージ（ErrorKind + メッセージ）
2. **中期**: 4層構造 + Help 行 + did-you-mean サジェスト
3. **後期**: セマンティックスタイリング + カスタマイズ API

---

## リザルト取得・構造化出力

### ValueSource

パース結果の値がどのソースから来たかを追跡:

```moonbit
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

### defaults 優先順位（viper 参考）

```
CLI > 環境変数 > 設定ファイル > initial
```

各ソースごとに独立した ResultMap で parse し、後勝ちマージ（前述の defaults 設計と整合）。

---

## Mutual Exclusion（排他オプション）

同時に使えないオプション群を宣言する。

```moonbit
let json = opt::flag(name="json")
let csv = opt::flag(name="csv")
let yaml = opt::flag(name="yaml")

// 最大1つ（どれも指定しなくてもOK）
let format = exclusive([json, csv, yaml])

// ちょうど1つ（必須）
let format = exclusive([json, csv, yaml], required=true)
```

### バリデーションタイミング

- **消費時**: 同グループの別オプションが既に消費済みなら即 `ParseError(Exclusive)`（早期確定）
- エラー: `error: --csv cannot be used with --json`

### exclusive の戻り値

`exclusive()` はバリデーション制約を Parser に登録するだけ。各 Opt の値は個別に `parser.get(json)` 等で取得する。

---

## Dependent Options（条件付きオプション）

あるオプションが別のオプションの存在・値に依存する関係を宣言する。

```moonbit
let ssl = opt::flag(name="ssl")
let ssl_cert = opt::string(name="ssl-cert", requires=[ssl])

let format = opt::string(name="format", choices=["json", "csv", "tsv"])
// 簡易: 文字列一致
let delimiter = opt::string(name="delimiter", requires=[Require(format, value="csv")])
// カスタム述語: T が String とは限らないケースにも対応
let delimiter = opt::string(name="delimiter", requires=[RequireWhen(format, fn(v) { v != "json" })])
```

### バリデーションタイミング

- **基本は finalize 時**: まだ入力途中かもしれないので、全引数消費後にチェック
- **早期確定可能なケース**: 消費時点で依存先の値が確定済みなら早期エラーも可
- エラー: `error: --delimiter requires --format=csv`

### 補完連携

- `--delimiter` 補完時に依存元 `--format csv` が未指定なら description に警告表示
- 依存元が一意（`--format csv` のみ）なら自動展開も検討

### ReduceCtx 経由の途中参照

dependent options の reducer 内で依存先の値を参照可能:

```moonbit
let delimiter = opt::custom(
  name="delimiter",
  initial=",",
  reducer=fn(ctx) {
    // format の現在値を参照して挙動を変える
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

**1. 個別指定**: 特定のオプションに環境変数を明示バインド

```moonbit
let port = opt::int(name="port", env="PORT")
// PORT=8080 → port の値が 8080 に
```

**2. プレフィックス連結**: コマンドのプレフィックスと個別 env を結合

```moonbit
let app = cmd("myapp", env_prefix="MYAPP")
let port = opt::int(name="port", env="PORT")  // → MYAPP_PORT を参照
```

**3. auto-env**: 全フラグを自動バインド（デフォルト無効）

```moonbit
let app = cmd("myapp", env_prefix="MYAPP", auto_env=true)
let port = opt::int(name="port")      // → MYAPP_PORT を自動参照
let verbose = opt::flag(name="verbose") // → MYAPP_VERBOSE を自動参照
```

### サブコマンドのプレフィックスネスト

```
myapp serve --port 8080
→ MYAPP_SERVE_PORT
```

### オーバーライド

env でフルパス指定すればプレフィックスを無視:

```moonbit
let port = opt::int(name="port", env="CUSTOM_PORT")
// env_prefix="MYAPP" でも MYAPP_PORT ではなく CUSTOM_PORT を参照
```

### Opt レベルの auto-env 制御

auto-env は Parser/Cmd レベルだけでなく、各 Opt で `auto_env : Bool?` により個別に制御可能:

```moonbit
let app = cmd("myapp", env_prefix="MYAPP", auto_env=true)
let port = opt::int(name="port")                           // None → 親に従う（MYAPP_PORT）
let secret = opt::int(name="secret-key", auto_env=false)   // false → auto-env 無効
let debug = opt::flag(name="debug", auto_env=true)         // true → 親が auto_env=false でも有効
```

- `None`（デフォルト）: 親 Cmd の設定を継承
- `Some(true)`: この Opt は auto-env 有効（親が無効でも）
- `Some(false)`: この Opt は auto-env 無効（親が有効でも）

オプションスコープが明確に管理されるため、Opt 単位での粒度制御が自然に実現できる。

### 安全性

- auto-env はデフォルト無効（Cmd で明示的に `auto_env=true` が必要）
- Opt レベルの `auto_env=false` で内部フラグの環境変数への漏洩を個別に防止
- `visibility` 属性との連動: help/補完で非表示のオプションは auto-env も自動 Off（明示 `true` で上書き可）

---

## Visibility — ヘルプ・補完の表示制御

Opt / Cmd に設定する表示レベル。手入力すれば全て動作する（visibility はあくまで発見性の制御）。

```
enum Visibility {
  Visible      // デフォルト
  Advanced     // help ✗, 補完 ✓（パワーユーザー向け）
  Deprecated   // help ✓（deprecated 注記）, 補完 ✗
  Hidden       // help ✗, 補完 ✗
}
```

| | help | help-all | 補完 | 手入力 |
|--|------|----------|------|--------|
| Visible | ✓ | ✓ | ✓ | ✓ |
| Advanced | ✗ | ✓ | ✓ | ✓ |
| Deprecated | ✓ (注記) | ✓ (注記) | ✗ | ✓ (警告) |
| Hidden | ✗ | ✓ | ✗ | ✓ |

### help-all

Parser レベルで `help_all=true` を有効にすると `--help-all` フラグが自動追加される。
指定時は Hidden/Advanced を含む全エントリをヘルプに表示（git の全サブコマンド表示と同パターン）。

### ショート別名の扱い

ショート別名（`-p` 等）は独立した Opt ではなく、ロングオプションのヘルプ行に `-p, --port` と併記される。
補完に出さないのは標準的な挙動であり、visibility 設定の対象外。

### deprecated 別名の扱い

`aliases` に `deprecated=true` を付けた別名はヘルプに deprecated 注記付きで表示、補完には出さない。
手入力時は動作するが「`--old-name` is deprecated, use `--new-name`」の警告を出す。

### auto-env との連動

- `Hidden` / `Advanced` → auto-env デフォルト Off（`auto_env=true` で明示上書き可）
- `Visible` / `Deprecated` → 親 Cmd の auto-env 設定に従う

---

## プロジェクト構成

`src/` はフラットにせず、パッケージ分割で管理する（`core/`, `parse/`, `resolve/`, `validate/`, `help/`, `complete/` 等）。MoonBit のテストファイル命名パターン（`foo_test.mbt`, `foo_wbtest.mbt` 等）により、機能ごとのファイル数が増加するため。具体的な分割粒度は実装進行に合わせて決定。参考: mizchi の MoonBit リポジトリ群のパッケージ分割構成。
