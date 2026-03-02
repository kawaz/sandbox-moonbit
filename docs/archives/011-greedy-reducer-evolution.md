# DR-011: 「resolve は Reducer」— 先食い最長一致への設計進化

## 経緯

### 1. arity への疑問

ユーザーが「arity て何に使ってるの？今のリデューサー設計で必要なの？」と質問。

arity は ErasedNode のフィールドで、以下3箇所で使用されていた:

- **resolve_value**: 名前解決後に次の引数を値として消費するか判断
- **expand_short_combined**: 短縮オプション展開で残り文字を値にするか判断
- **ヘルプ生成**（将来）

arity は reducer を呼ぶ**前に**引数文法レベルの判断に使用するメタデータであり、reducer 自体のロジックとは分離されていた。

### 2. TryReduceResult 3状態の提案

arity を廃止して reducer の戻り値で「値が欲しい」を表現するアイデアが浮上:

```
enum TryReduceResult {
  Accept(ReduceResult)  // マッチ＋結果確定
  NeedValue             // マッチしたが値が必要
  Reject                // マッチしない
}
```

動作イメージ:

- **フラグ**: `try_reduce(Value(None))` → `Accept`
- **値オプション**: `try_reduce(Value(None))` → `NeedValue` → 次の引数消費 → `try_reduce(Value(Some(val)))` → `Accept`

NeedValue に Int（arity 相当）を持たせる案も検討されたが、不要と判断。複数値を取るケースは serial（連続適用）で対応可能。

### 3. 先食い最長一致への飛躍

ユーザーの洞察により、値を取る系のオプションは「行き止まりまで先食い」するモデルへ飛躍した。

OC（Option Candidate）同士の競合ループを再定義:

1. **先食い最長の opt が複数** → `ParseError`（曖昧）
2. **先食い最長の opt が1つ** → その opt が消費 → shift → 繰り返し
3. 「消費可能な opt が1つ」は「先食い最長がそいつのみ、他はゼロ」の特殊ケース

これにより、従来の「1ターンずつの細切れループ」が「先食い最長一致の比較」に単純化された。先食い分の refs は採用されなかった際に捨てるため、別 map に蓄えるなどの工夫が必要。

### 4. 「resolve は Reducer」の洞察

ユーザーの核心的洞察:

> 名前解決自体が、opt/command をたくさん持ってて、次の引数にマッチする opt をその中から探す。っていう機能を持った Reducer なんじゃなかろうか？ resolve って概念自体がいらなくて。

これにより以下が実現する:

- **resolve フェーズが消える** — 各ノードが自分の名前マッチングを知っている
- **消費ループが「先食い最長一致」に統一** — arity も resolve も不要
- **全体が Reducer のツリー**
- **prefix 曖昧性**もスコープ Reducer の比較で自然に解決

## 決定事項

1. **arity フィールド廃止**
2. **resolve フェーズ廃止**（各ノードの `try_reduce` に統合）
3. **`try_reduce` が `args[pos..]` を直接受け取る**
4. **`TryReduceResult = Accept(consumed, result) | Reject`**
5. **スコープ Reducer** = 子ノード群の先食い最長一致を選ぶ
6. **短縮オプション展開**はスコープ Reducer の責務
7. **パイプラインは5フェーズに**: PreProcess → Reduce → Validate → Finalize → Output

## 不採用案

| 案 | 不採用理由 |
|---|---|
| NeedValue(Int) | arity 相当の Int を NeedValue に持たせる案。不要。serial で対応可能であり、実用上 arity は 0 か 1 |
| resolve を残す | 名前マッチングだけ分離する案。各ノードに内包した方が統一的で、フェーズ分離の複雑さを排除できる |

## 付録: 生のチャットやりとり

### arity の質問

> **User**: arity て何に使ってるの？今のリデューサー設計で必要なの？
>
> **AI**: arity は3箇所で使用... reducer を呼ぶ前に引数文法レベルの判断に使用するメタデータ

### reducer 戻り値の提案

> **User**: そうするとreducerって一つ引数を消費した際の戻り値としてTの他に next:EracedOpt? とかが返せると良い？ または nextを用意させるのが大変だとしたら次に値をとるかどうか？を T,Bool で返すみたいな
>
> **AI**: (T, Bool) だと値なしで T を作れないので、3状態の TryReduceResult が最小解

### NeedValue に Int は不要

> **User**: それとも arity みたいに int で欲しい？
>
> **AI**: NeedValue だけ（常に1）で十分。実用上 arity は 0 か 1
>
> **User**: というか複数取るときはserial使えば良いしな。

### 先食い最長一致

> **User**: 値を取る系は行き止まりまで先食いしてしまって良い気がしてきた。で何個先まで食うことが確定してるよ。って感じで先食い済みのArrayを返しちゃえば良いんじゃないかなと。先食い分の refs は採用されなかった際に捨てるから別mapに蓄えるか何かの方が良い気がする。
>
> で横並びのOC同士が引数消費しながらループ回すやつあったけど、あれ1ターンずつに細切れた視点での説明になってるけど、全体としては要は先食い最長のoptが複数いたらParseError(曖昧)、先食い最長のoptが1つならそのoptが消費する→消費した分はshiftしてまた先食い最長比べをする。に単純化できるわ多分。

### resolve 不要

> **User**: その名前解決自体が、opt/command をたくさん持ってて、次の引数にマッチするoptをその中から探す。っていう機能を持ったReducerなんじゃなかろうか？ resolve って概念自体がいらなくて。
