# Phase 4: Reducer 大統一設計

## Context

- Phase 1-3 の PoC は「テストケース = 要件」として引き継ぐ。コードは全削除して完全作り直し
- 核心: 全 OptKind を `initial + reducer` で統一し、OptKind enum を廃止
- `&Trait` (trait object) で heterogeneous collection が可能（MoonBit v0.1.20260209+）
- String ベースの中間表現は不要。T ベースで直接動作

Design rationale: 旧設計では `Map[String, Array[String]]` による String ベースの中間表現を使い、
`ReduceContext` で初期値・デフォルト・明示設定フラグを運搬していた。しかし `&Trait` (trait object) が
使えるようになったことで、heterogeneous collection の問題が解消され、String への変換・逆変換が
完全に不要になり、型安全性が向上する。

---

## 設計原則

- **Opt[T] は完全 immutable** — 定義情報のみ保持。一意 ID でResultMap のキーとして機能
- **parse はツリーを走査して ResultMap に結果を書き込む** — `&ErasedNode` 経由で型を知らずに操作
- **ユーザーは `result.get(opt)` で型付きの値を取得** — Opt[T] がレンズ/キーとして機能
- **defaults は優先順位付きソースからの置き換え**（積み上げではない） — 後のソースが前を丸ごと上書き
- **reducer はシンプルに `(T, ReduceAction) -> T?!ParseError`** — None = マッチしない（候補から脱落）、Some(T) = 消費成功、raise ParseError = エラー

---

## Opt ツリー構造

### Opt[T] — リーフノード

各ノードが自身の定義情報と reducer を持つ。完全 immutable。結果は外部の ResultMap に保持。

```moonbit
///| リーフノード — 定義情報のみ。完全 immutable
struct Opt[T] {
  id : Int                    // 一意 ID（生成時にインクリメント）
  initial : InitialValue[T]
  reducer : (T, ReduceAction) -> T?!ParseError
  meta : OptMeta
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

Design rationale: Opt を immutable にすることで、定義と結果が分離される。結果は外部の ResultMap に持たせ、defaults のスナップショットは ResultMap のコピーで完結。グループの clone は新 ID を発行するだけで自然に動く。
`InitialValue[T]` は即値と遅延評価（ランタイム依存の初期値）を統一的に扱う。

### Opts — ツリーの構造化

JSON の Value のような再帰的 enum 構造。リーフ（ErasedNode）と合成（Array / Map）を統一的に表現する。

```moonbit
///| Opt ツリーの構造化 — JSON の Value のような再帰構造
enum Opts {
  Node(&ErasedNode)          // 型消去されたリーフ
  Array(Array[Opts])         // 通常のオプション群（名前マッチ）= List
  Map(Map[String, Opts])     // named group / or
}
```

- `Opts::Array` — 通常のオプション群。各要素は名前マッチで独立に解決される
- `serial(...)` — 位置パラメータの順番消費。明示的にマーク（serial コンビネータで生成）
- `rest(opt)` — 可変長消費。明示的にマーク（rest コンビネータで生成）

Design rationale: MoonBit にリフレクションがなく、無名 struct をその場で作って T として渡せないため、
ユーザー定義 struct + フィールドアクセス方式は実現困難。JSON の Value と同じ再帰 enum パターンなら、
パーサがリフレクション不要でツリーを走査できる。

### 合成パターン

- **or** — 排他選択。`Opts::Map` で子を名前付きで構造化。子は自動で `required=false`
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

### reducer 統一パターン

全ての OptKind は `(T, ReduceAction) -> T?!ParseError` の reducer で表現される。OptKind enum は不要。

| 種別 | initial | reducer |
|------|---------|---------|
| Flag | `false` | `(_, Value(None)) -> Some(true)`, `(_, Negate) -> Some(initial)` |
| Count | `0` | `(n, Value(None)) -> Some(n + 1)`, `(_, Negate) -> Some(initial)` |
| Single | `None` | `(_, Value(Some(s))) -> Some(Some(parse!(s)))`, `(_, Negate) -> Some(initial)` |
| Append | `[]` | `(arr, Value(Some(s))) -> Some([...arr, parse!(s)])`, `(_, Negate) -> Some(initial)` |
| OptionalValue | `None` | `(_, Value(None)) -> Some(Some(implicit))`, `(_, Value(Some(s))) -> Some(Some(s))` |

プリミティブ型コンビネータは custom の特殊化: `opt::int` = `opt::custom(parse_int)`

Design rationale: 旧設計では `ReduceContext` が `value`, `initial`, `defaults`, `explicitly_set` を
運搬していた。新設計では Opt[T] は immutable で結果は ResultMap に保持されるため、reducer の引数は
`(T, ReduceAction) -> T?!ParseError` だけで十分。現在値は ResultMap からルックアップし、初期値は `self.initial` で参照できる。
エラーパスは MoonBit の raise 構文で伝搬する。parse!(s) が失敗した場合、reducer から ParseError が raise される。
reducer の戻り値は3値: None（マッチしない = 候補脱落）、Some(T)（消費成功）、raise ParseError（エラー）。
消費ループの step 3 で各候補の reducer に引数を渡し、None を返すものを除去する仕組みの根幹。
例: flag は常に Some(true)、int に "abc" → None、file に存在しないパス → None、since に "1h3m" → Some(Duration)。

reducer の3値の設計根拠:
- None: 「この引数を食えない」= 消費ループの候補選定で使用。他の候補を試す
- Some(T): 「この引数を消費した」= 結果を ResultMap に書き込む
- ParseError: 「マッチしたがバリデーション失敗」= 即座にエラー

これにより reducer は「パーサ（食えるか判定）」と「バリデータ（型変換の検証）」を兼ねる。
例: int の reducer は "123" → Some(123)、"abc" → None。file の reducer は存在するファイルパス → Some(path)、存在しない → None。

---

## ResultMap — パース結果の保持

```moonbit
///| パース結果を保持する型消去された Map
struct ResultMap {
  priv data : Map[Int, ???]  // 型消去された値の保持方法は要検討
}

///| Opt[T] をキーとして型安全に値を取得
fn get[T](self : ResultMap, opt : Opt[T]) -> T {
  // opt.id でルックアップ → T に変換
}

///| サブコマンド取得
fn command(self : ResultMap) -> Opt?  // None = トップレベル or サブコマンド以外
```

Design rationale: Opt が immutable なので結果は外部に持つ。ResultMap は内部的に Map[Int, 型消去された値] で、Opt[T] の id でルックアップし、T への変換は Opt[T] がクロージャで知っている。

---

## 型付き結果の取り出し

### 通常 Opt — 変数バインド + result.get()

構築時に変数バインドし、parse 後に `result.get(opt)` で型安全に取得する。

```moonbit
let port = opt::int(name="port")
let verbose = opt::flag(name="verbose")

let opts = Opts::Map({
  "port": Opts::Node(port.erased()),
  "verbose": Opts::Node(verbose.erased()),
})

let result = parse(args, opts)  // ResultMap を返す

result.get(port)     // Int
result.get(verbose)  // Bool
```

### グループ Opt — 雛形 + clone 方式

parse がグループ出現ごとに Opts を clone（新 clone ID 発行）して ResultMap に値を詰める。

clone ID は雛形横断の sequential な一意 ID（グローバルインクリメント）。複合キー (template_id, clone_id) は不要で、clone ID 単体で一意に識別できる。

各グループの ResultMap は独立インスタンスなので、ResultMap 内では雛形の template_id をキーに使える（衝突しない）。

```moonbit
let upstream_host = opt::str(name="host")
let upstream_timeout = opt::int(name="timeout")
let upstream_tmpl = Opts::Map({
  "host": Opts::Node(upstream_host.erased()),
  "timeout": Opts::Node(upstream_timeout.erased()),
})
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
Opt が immutable なので defaults のスナップショットは ResultMap のコピーで完結。

---

## ErasedNode — 型消去インターフェース

parse がツリーを走査するための trait object。parse は具体的な T を知る必要がない。

```moonbit
///|
pub(open) trait ErasedNode {
  meta(Self) -> OptMeta
  arity(Self) -> Int
  reduce_erased(Self, ReduceAction, &ResultMap) -> Unit?!ParseError  // None = マッチしない、ResultMap に書き込み
  reset_to_initial(Self, &ResultMap) -> Unit
  children(Self) -> Array[&ErasedNode]       // ツリー走査用
}
```

`Opt[T]` は `&ErasedNode` を実装。parse は `&ErasedNode` の配列/ツリーを走査して `reduce_erased` を呼ぶだけ。型を知らない。

Design rationale: 旧設計の `ErasedOpt` trait は `initial_raw`, `reduce_raw` など String ベースの
メソッドを持っていた。新設計では `reduce_erased` が ResultMap に書き込むため、
String への変換が不要。`children()` はツリー構造の走査用だが、Opts enum がツリー全体の構造を
表現するため、実際の走査は Opts enum 側に委譲される。ErasedNode の `children()` は
個々のノードが直接の子を返すインターフェースとして機能する。

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

3. 各 OC の reducer に args(n) を渡し、None を返すものを除去
   （reducer が T? を返す: None = 食えない、Some(T) = 食えた）

4. greedy フィルタ
   OC リストに greedy=true があれば greedy=false を除去

5. OC=0 かつ args(n+1) なし → パース完了。消費ループ脱出

6. OC=0 かつ args(n+1) あり
   6a. P リストなし → ParseError（予期しない引数）
   6b. P リストあり → P モードに遷移して消費ループ継続

7. OC=1 (Node) → その OC が args(n) を消費、カレントスコープ更新、消費ループ継続

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

let serve = opt::cmd(name="serve", Opts::Map({
  "port": Opts::Node(port.erased()),
  "host": Opts::Node(host.erased()),
  "DIR":  Opts::Node(dir.erased()),
}))

let target = opt::str(name="target")
let force = opt::flag(name="force")

let deploy = opt::cmd(name="deploy", Opts::Map({
  "target": Opts::Node(target.erased()),
  "force":  Opts::Node(force.erased()),
}))

let app = Opts::Map({
  "verbose": Opts::Node(verbose.erased()),
  "serve":   Opts::Node(serve.erased()),
  "deploy":  Opts::Node(deploy.erased()),
})

let result = parse(args, app)
result.get(verbose)      // Bool（どのサブコマンドでも有効）
result.command()         // Opt?（serve or deploy。None = トップレベル）
result.get(port)         // Int?（serve が選ばれた場合のみ）
```

- 同一階層のサブコマンドは引数消費ループで常に1つに決まる。排他の仕組みは不要
- `result.command() -> Opt?` で選ばれたサブコマンドを取得。None はトップレベルまたはサブコマンド以外の result の場合
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

各デフォルトソースは独立。後のソースが前を丸ごと上書きする。ReduceContext は不要。

**解決策**: 各ソースごとに新しい ResultMap（initial から）で parse し、最後に後勝ちマージする。同一 ResultMap への累積 parse ではない。

```
source1 (config):  --port 3000 --tags a --tags b
source2 (env):     --port 8080
CLI:               --tags c

source1 result: { port: 3000, tags: [a, b] }
source2 result: { port: 8080 }
CLI result:     { tags: [c] }

→ merge（後勝ち）: port = 8080, tags = [c]
→ port: source2 が source1 を上書き、CLI 指定なし
→ tags: CLI が source1 の [a,b] を丸ごと置き換え
```

Opt が immutable なので defaults のスナップショットは ResultMap のコピーで完結する。

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
  choices : Array[String]
  value_name : String
  required : Bool
  visibility : Visibility
  global : Bool             // スコープ以下全体に伝搬
  greedy : Bool             // マッチ時、非 greedy 候補を除外して消費ループ続行
} derive(Eq, Show, Debug)
```

---

## 未解決・要検討事項

1. **ResultMap の型消去メカニズムの PoC 検証**（最優先） — `Map[Int, ???]` の型消去された値の保持方法を実際に MoonBit で動かして検証する
2. **ユーザー API のインターフェース設計** — `opt::array(o1, o2, o3)` vs builder パターン vs その他
3. **or の結果型と required の関係** — or の子は自動で `required=false`。どちらもマッチしなかった場合の表現
4. **completion の詳細設計** — セルフ呼び出し動的ヒント方式は確定。詳細は後日
5. **ヘルプ生成** — reducer からヘルプテキストをどう生成するか
6. **kind の区別のユーザー API 表現** — `long:` vs `name:` vs `kind: Option` 等

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

---

## 実装計画

### Step 0: 準備

- `src/lib/` を `src/lib-old/` にリネーム（テストケース参照用に保持）
- `src/lib/` をゼロから作り直す

### Step 1: Token + tokenize

旧実装からそのまま移植。字句解析。

```moonbit
///|
pub(all) enum Token {
  LongOpt(String)
  LongOptWithValue(String, String)
  ShortOpts(String)
  Positional(String)
  DoubleDash  // `--` を greedy Opt で表現する新設計により不要になる可能性がある。PoC で検証
} derive(Eq, Show, Debug)

pub fn tokenize(args : Array[String]) -> Array[Token]
```

### Step 2: 型定義

`Opt[T]`, `OptMeta`, `ReduceAction`, `InitialValue`, `ErasedNode` trait 等。

### Step 3: コンビネータ関数群

flag, string_opt, int_opt, count, append, optional_value, custom。

### Step 4: 名前解決 (resolve)

long → エイリアス → 反転パターン の順にマッチ。

### Step 5: parse（コアロジック）

ツリー走査 + reduce。

### Step 6: validate

メタ情報ベースのバリデーション。

### Step 7: defaults

優先順位付きソースからの置き換え方式。

### Step 8: CmdDef + サブコマンド

find_command / scan_for_subcommand。

### Step 9: Group（後続フェーズ）

### Step 10: テスト完全移行

旧 399 件のテストケースが検証する「要件」を全て新 API で書き直す。

### 実装順序

```
Step 0 → Step 1 → Step 2 → Step 3 → Step 4 → Step 5 → Step 6 → Step 7 → Step 8
```

### 検証方法

各 Step で TDD:
1. 旧テストケースから要件を抽出
2. 新 API でテストを書く（RED）
3. 実装する（GREEN）
4. `moon test` で全 pass 確認
5. `just release-check` で品質確認
