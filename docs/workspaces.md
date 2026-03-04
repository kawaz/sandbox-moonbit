# ワークスペース管理

## 現在のワークスペース

### main

- パス: `~/.local/share/repos/github.com/kawaz/sandbox-moonbit/main/`
- bookmark: `main`
- 状態: アクティブ
- 概要: メインワークスペース。ドキュメント管理・MoonBit 汎用知見の蓄積

### wip-cli-parser

- パス: `~/.local/share/repos/github.com/kawaz/sandbox-moonbit/wip-cli-parser/`
- bookmark: `wip-cli-parser`
- 状態: アクティブ
- 概要: CLI 引数パーサの設計・PoC。別プロジェクト（kawaz/cli.mbt 等）に分離予定
- 関連: `wip-cli-parser-implement` bookmark（ボツにした実装ブランチ）

## 卒業済みプロジェクト

sandbox-moonbit で育てて別リポジトリに分離したもの。

| プロジェクト | 分離先 | 元ワークスペース | 備考 |
|---|---|---|---|
| CLI引数パーサ | kawaz/kuu.mbt（予定） | wip-cli-parser | 設計・PoC完了。28パーサ調査+Phase4設計書あり |
| shimux | kawaz/shimux | — | MoonBit移植検討から独立。調査結果は shimux 側に |

## 過去のワークスペース（削除済み）

### default

- 概要: 管理センターとして使用していたが main に統合して削除

### wip-utf8-experiment

- 概要: UTF-8 受け渡し実験。結果は `docs/utf8-experiment.md` に反映済み
