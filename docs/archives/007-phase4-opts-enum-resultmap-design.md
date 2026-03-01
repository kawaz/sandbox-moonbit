# DR-007: Opts enum + ResultMap + immutable Opt + greedy/never 設計（2026-03-01）

## 概要

Phase 4 設計において、ユーザー定義 struct + val() フィールドアクセス方式から、JSON-like な Opts enum + ResultMap + immutable Opt 方式への大幅な設計転換を行った。

## 前提（前セッション 006 時点の設計）

- Opt[T] が `mut value : T` を持ち、parse が直接書き込む
- ユーザー定義 struct（ColorChoice, RgbArgs 等）のフィールドが Opt[U] で、`.val()` + フィールドアクセスでツリーを辿る
- parse がツリーを走査するために子ノードを発見する仕組みが未解決（MoonBit にリフレクションがない）

## 問題点

1. **リフレクション問題** — MoonBit では無名 struct をその場で作って T として渡せず、ユーザー定義 struct のフィールドから Opt[U] を自動発見できない。children() の実装が困難
2. **Opt の mutable 性** — `mut value` を持つと defaults のスナップショットが面倒。グループの clone 時にも状態管理が複雑になる
3. **グループ（Append されるオプション群）** — 同じ構造が複数回出現する場合、個別の変数バインドでは対応できない

## 設計変更の経緯

### Step 1: Opts enum の導入

リフレクション問題の解消として、JSON の Value のような再帰的 enum 構造を採用:

```moonbit
enum Opts {
  Node(&ErasedNode)
  Array(Array[Opts])
  Map(Map[String, Opts])
}
```

- パーサがリフレクション不要でツリーを走査できる
- 名前は Map のキーで管理（フィールドアクセスではなく）

### Step 2: グループの雛形 + clone 方式

グループ（繰り返しオプション群）は:
- 最初に渡された Opts を雛形として保持
- parse がグループ出現ごとに clone して値を詰める
- namedGroup → Map、namelessGroup → Array[Opts] で返す
- 雛形の Opt[T] をレンズ/キーとして、clone 先から型安全に値を取り出す

### Step 3: Opt[T] の immutable 化 + ResultMap

- Opt[T] から `mut value` を削除し、`id : Int` を追加。完全 immutable
- 結果は外部の ResultMap（Map[Int, 型消去された値]）に保持
- Opt[T] の id で ResultMap をルックアップし、T への変換は Opt[T] が知っている
- defaults のスナップショットは ResultMap のコピーで完結
- グループの clone は新 ID 発行で自然に動く

### Step 4: サブコマンド・位置パラメータの具体的表現

- サブコマンド: `opt::cmd(name, children_opts)` kind=Command
  - 同一階層で常に1つに決まる（引数消費ループの仕様）
  - `result.command() -> Opt?` で選ばれたサブコマンドを取得
- グローバルオプション: `meta.global` フラグ。そのスコープ以下全体に伝搬
- 位置パラメータ:
  - `serial(o1, o2, o3)` — 固定長、順番消費
  - `rest(opt)` — 可変長消費
  - `serial(file, rest(path))` — 固定 + 末尾 rest
  - 中間 rest は未サポート（将来検討）

### Step 5: レビュー対応 — reducer エラーパス追加

マルチペルソナレビュー（5ペルソナ + codex）で 6 レビュアー全員が ISSUES_FOUND。致命的問題4点を特定し対応:

1. **グループ clone ID 矛盾** → clone ID をグローバル sequential 一意 ID に。複合キー不要、各 ResultMap は独立インスタンスなので雛形 template_id をキーに使える
2. **reducer エラーパス欠如** → `(T, ReduceAction) -> T!ParseError` に変更。MoonBit の raise 構文で伝搬
3. **defaults Append replace 矛盾** → 各ソースごと新 ResultMap（initial から）で parse し、最後に後勝ちマージ
4. **ResultMap 型消去未定義** → PoC 検証で優先対応（次ステップ）

### Step 6: Opts::Array セマンティクス明確化

- Opts::Array = 通常のオプション群（名前マッチ）= List
- serial/rest は明示マーク
- tuple2 left fold パターンは不要になったため削除

### Step 7: greedy + never() コンビネータ

- `meta.greedy = true`: 消費ループで非 greedy 候補を除外するフィルタ。greedy 同士は通常通り競合
- `never()`: 引数消費に使われると常に ParseError を投げるセンチネル

```
消費ループのマッチ判定:
  candidates = マッチした全候補
  if candidates.any(c => c.meta.greedy) {
    candidates = candidates.filter(c => c.meta.greedy)
  }
  // 残った candidates で通常の消費ループ続行
```

### Step 8: `--` (double dash) の統一表現

- 従来は tokenize で DoubleDash 特殊トークン化 → パーサ内ハードコード
- 新設計: `flag(name="", greedy=true, global=true)` で `--` を通常の Opt として表現
- serial + never() or rest との組み合わせで位置パラメータ消費を制御
- `--exec` 的パターンにも同じ仕組みで対応可能

## 決定事項

| 項目 | 決定 |
|---|---|
| ツリー構造 | Opts enum（Node/Array/Map）— JSON-like 再帰構造 |
| Opt の mutability | 完全 immutable。id : Int で一意識別 |
| 結果保持 | ResultMap（ID + clone レジストリのみ）。値は Opt[T] 側に分散（Ref[T] クロージャキャプチャ方式） |
| 値の取得 | result.get(opt) = opt.slots[result.id].val で直接 T を返す。ダウンキャスト不使用 |
| グループ | 雛形 + clone（新 ID 発行）。result.get_groups(upstream) -> Array[ResultMap] |
| サブコマンド取得 | result.command() -> &ErasedNode? |
| グローバルオプション | meta.global フラグ。スコープ以下に伝搬 |
| 位置パラメータ | serial（固定長）+ rest（可変長）+ 組み合わせ |
| defaults | 後勝ち上書き。ResultMap clone でスナップショット（clone_fns 経由で独立 Ref 作成） |
| reducer 署名 | `(T, ReduceAction) -> T?!ParseError`。None=食えない、Some(T)=消費成功、raise=エラー |
| clone ID | グローバル sequential 一意 ID。複合キー不要 |
| defaults マージ | 各ソースごと新 ResultMap + 後勝ちマージ |
| greedy | `meta.greedy = true` — 非 greedy を除外するフィルタ |
| never | `never()` — 常に ParseError のセンチネル |
| `--` (double dash) | `flag(name="", greedy=true, global=true)` + serial で統一表現 |

## 不採用とした設計

### ユーザー定義 struct + val() フィールドアクセス方式
不採用理由: MoonBit にリフレクションがなく、struct のフィールドから子 Opt を自動発見できない。children() trait を要求するとユーザーの負担が大きい。

### Opt[T] に mut value を持たせる方式
不採用理由: defaults のスナップショットが複雑（snapshot/restore が必要）。グループの clone 時に状態管理が煩雑。ResultMap で外部化した方がシンプル。

### Map[String, Array[String]] ベースの ParseResult
不採用理由: trait object で heterogeneous collection が可能になった以上、String ベース中間表現は不要。ネームレス Opt の存在で名前キー Map は構造的に破綻。

### tuple2 left fold 方式
不採用理由: trait object + Opts enum でツリーを直接表現する設計に移行したため。tuple2 の左畳み込みによる n-ary 表現は不要。

### `--` を DoubleDash 特殊トークンとする方式
不採用理由: greedy + serial の組み合わせで `--` を通常の Opt として統一的に表現可能。特殊処理をなくすことでパーサがシンプルになり、`--exec` 等のパターンにも同じ仕組みで対応できる。

### グループ clone 時に複合キー (template_id, clone_id) を使う方式
不採用理由: clone ID がグローバルに一意なので複合キー不要。各グループの ResultMap は独立インスタンスであり、雛形の template_id をキーに使えば衝突しない。

### Step 9: ResultMap 型消去 PoC 検証（解決済み）

- **方式A: Ref[T] クロージャキャプチャ方式を採用**
- ResultMap は値を持たない。ID + clone 用クロージャレジストリのみ
- Opt[T] が `slots: Map[Int, Ref[T]]` で各 ResultMap ごとの値を分散管理
- `result.get(opt)` = `opt.slots[result.id].val` で直接 T を返す
- ダウンキャスト不使用、型安全性は静的に保証

不採用: **enum Value ラッパー方式** — 閉じた型集合 `enum Value { VInt(Int); VBool(Bool); ... }` では `opt::custom` の開放性要件を満たせない

### Step 10: 消費ループアルゴリズム明記

- OC モード（Option/Command 優先）→ P モード（Positional フォールバック）の2層構造
- reducer 署名を `(T, ReduceAction) -> T?!ParseError` に変更（3値: None/Some(T)/raise）
- 10ステップのアルゴリズムを設計書に明記

## 未解決事項

- ~~ResultMap 内部の型消去された値の保持方法~~ → **解決済み**: Ref[T] クロージャキャプチャ方式
- `or` の結果型と required の関係
- `--` の tokenize/parse 間の接続方式（DoubleDash トークン廃止の PoC）

## 付録: 生チャットログ

以下は設計議論の主要なやりとりの記録。

### Opts enum の着想

ユーザー:
> ちなみにMoonbitってJson走査するの考えたらいける気がするけど、こういうの処理できるよね？多分。
> enum Opt { Map(Map[String,Opt]), Array(Array[Opt]), Single(Opt) }
> だとしたら parse(args, Opt) でいけて、構造も何もいじらないでも良いんじゃないかな。ユーザは自分が好きに作った構造からオプション取り出せば良い。

### グループの雛形 + clone

ユーザー:
> 考慮しなきゃいけないのはグループを作るoptだね。これは外で一つの変数にバインドじゃダメでグループ毎のoptのcloneが必要になるのでその参照をどう取らせるか。シンプルに最初に渡されたOptsは雛形として持って、リザルト用はOptsをcloneしてそれに値詰めて返せば良いんかな。namedGroupならMap,namelessGroupならArray(Opts)で返せば良いか。

### 雛形 Opt をレンズとして使う

ユーザー:
> opt[T].as_typed(opt) みたいに自己解決すればよい？

→ 雛形の Opt[T] の meta.name で Map をルックアップし、T への変換も Opt[T] が知っている。

### immutable Opt + ResultMap

ユーザー:
> moonbitって Hash+Eq でキーになるのか。jsみたいにsameでキーになるみたいなやつってないのかな？
> それができるなら Opt は値を持たなくて、opt.value してるところを resultMap.set(opt, v) みたいにして置いて、resultMap.get(opt) で取り出す感じにすると Opt をまた immutable に出来るのでは?

### サブコマンド・位置パラメータ

ユーザー:
> 1 同一階層一つ。というか引数消費ループの仕様からに常に一つになる筈。
> 2 result.command() -> Opt? Noneはトップレベルコマンドの場合とカレントresultがサブコマンド以外の場合
> 3 opt.meta.globalフラグの導入が自然かな。ただしここでは仮にグローバルと言ってるが正確にはそのスコープ以下でのグローバルが正しい。
> 4 位置パラメータは serial(o1,o2,o3)は順番消費、それ以外は単にrest(opt)で単一Optの可変長消費。あとはその組み合わせパターンもあり得るか。mv=serial(rest(file),dir) とか、zip=serial(file,rest(path)) みたいなパターン。中間restは未検討だが論理的には可能なパターンなら可能かもだが大変なので取り敢えず今は未サポートとして考えない。

### レビュー対応 — clone ID の整理

ユーザー:
> cloneidを雛形横断のseqによる一意IDという位置付けにすれば組み合わせ不要か。

### reducer エラーパス

ユーザー:
> reducerの->TをResult[T,E]にする？

→ MoonBit の raise 構文 `-> T!ParseError` を採用。

### greedy の着想

ユーザー:
> -- は常に引数処理を中断して以降を位置パラメータとするみたいな特殊な値としていたが、meta{name="", greedy=true, global=true} を持つOptと定義すると良いかも。
> ここで greedy=true は、それが見つかった場合、他のマッチ候補があったとしても次の評価無しに最優先で次以降の引数を消費するという仕組み。

### greedy のセマンティクス修正

ユーザー:
> greedy=trueはマッチした瞬間他のオプション解決をスキップは間違い。あまりないかもだが、greedyが2つ以上いた場合はgreedy同士で一つずつ引数消費していくいつもの消費ループになる＝複数マッチがあった場合にgreedyがいたらgreedy=falseを除外して消費ループを継続。という表現が実装に近いかな。

### never() コンビネータ

ユーザー:
> hhの方にneverというのを新たに作ったのは greedy の最後が rest じゃなく固定長の場合は、元の引数消費に戻って欲しくないから、never() は引数消費に使われると常にParseErrorを投げる。
