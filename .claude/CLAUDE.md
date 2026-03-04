# sandbox-moonbit

MoonBit の実験・学習・プロトタイプ用リポジトリ。

## リポジトリ構成

- jj bare方式で管理
- GitHub: https://github.com/kawaz/sandbox-moonbit (public)
- 管理センター: `main/` — ドキュメント管理・知見蓄積（後述）
- 実験・作業は `jj workspace add ../{name}` でワークスペースを作って行う

## main ワークスペースの役割

main は**管理センター**。実作業は各ワークスペースで行う。

main の責務:
- ワークスペース一覧と各ワークスペースで何をしているかの管理 → `docs/workspaces.md`
- 全体的な調査知見の蓄積 → `docs/`
- 新規セッションへのコンテキスト引き継ぎ
- 「あれってどこでやってたっけ？」への回答

ワークスペース固有の資料・コードはそのワークスペース内に置く。main に集約する必要はない。

## ワークスペース管理

`docs/workspaces.md` を参照。新規ワークスペース作成・削除時は必ず更新する。

## コミットルール

### 作業区切りでの describe + push

論理的な作業単位（機能追加・バグ修正・ドキュメント整理等）が完了したら：

1. `jj describe -m "適切なメッセージ"` で describe
2. `jj bookmark set {branch} -r @` で bookmark 設定/更新
3. `jj git push` で push

複数の変更を1つの working copy に混ぜず、`jj new` で区切る。

### セッション終了時チェック

セッション終了前に全ワークスペースの状態を確認：

```bash
jj workspace list  # 全ワークスペース一覧
jj log             # 未 push の change 確認
```

- describe が空の change → 適切なメッセージを付ける
- bookmark 未設定の push 対象 change → bookmark を設定
- 未 push の change → push する（wip-* bookmark 含む）
- bookmark conflict → `jj git fetch` で解消

## プロジェクト方針

### MoonBit の好み・方針

- 低レイヤーFFI: C より **Rust** を使う（C ABI 公開で MoonBit から呼ぶ）
- CLI設計: グローバルルール `cli-design-preferences.md` 参照
- テスト: TDD を実践。`moon test -u` でスナップショットテスト活用
- ビルド: `just` でタスクランナー。各ワークスペースに justfile を配置
  - `just` → check + test、`just fmt`、`just release-check` → fmt + info + check + test
  - 新規ワークスペース作成時は justfile も作成する

### 現在の関心事

1. **JS/WASM連携**: wasm-gc + js-string-builtins でのゼロコスト文字列連携パターンの確立
2. **TUI/CLI開発**: claude-session-analysis 等の MoonBit 移植検討

### 卒業済みプロジェクト

ここで育てて別リポジトリに分離したもの。詳細は `docs/workspaces.md` 参照。

- **CLI引数パーサ** → kawaz/kuu.mbt（予定）。設計・PoCは wip-cli-parser で完了
- **shimux** → kawaz/shimux

### MoonBit コーディング規約

**MoonBit コードを書く前に必ず以下を参照すること:**

1. `/moonbit-practice` スキルを実行（言語仕様・FFI・テスト・stdlib の包括的リファレンス）
2. `docs/tui-mbt-patterns.md` を読む（実プロジェクトから抽出した実践パターン集）

#### 主要ポイント（詳細は上記を参照）

- `moon ide` コマンドを Read/Grep より優先
- `moon doc '<Type>'` で API 確認
- 型パラメータは `fn[T] name(...)` 形式
- raise 構文: `fn parse(s: String) -> Int raise Error`
- `///|` はブロックセパレータ（全関数・テスト・型定義の前に配置）
- `for` ループは range for 推奨、`nobreak` で値返却
- スナップショットテスト: `inspect(val, content="")` + `moon test -u`
- テストファイル命名: `*_test.mbt`（ブラックボックス）、`*_wbtest.mbt`（ホワイトボックス）
- パッケージ設定は `moon.pkg`（新形式）を使用
- JS/Native 分岐: `targets` でファイル単位に制御
- FFI: JS は inline `#|`、Native は C ABI（重いロジックは Rust）

### 既存 MoonBit リポジトリ（参考）

- `kawaz/mdp` - ターミナル Markdown プレビュー CLI
- `kawaz/markdown.mbt` - Markdown パーサ
- `kawaz/mermaid-aa-pr4-moonbit` - Mermaid→AA 変換
- `kawaz/LaserGuideV3/moonbit` - ゲーム（wasm-gc）
- `kawaz/syntree.mbt` - 構文木（JS target）
