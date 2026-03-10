# プロジェクト全体レビュー（追加）

- 日付: 2026-03-10
- 対象: kuu.mbt リポジトリ全体（コード + リサーチ + DR + ワークフロー + WASM bridge）
- 前提: 2026-03-04 レビューの追加・更新版。前回は「実装ゼロ」だったが、現在は src/core/ 14モジュール + src/wasm/ + 667テスト + Docker CLI デモが動作

---

## 前回レビューからの変化

**前回の最大の批判「実装ゼロ」は完全に解消された。** kuu.mbt に移行後、以下が実装済み:

- src/core/ に14モジュール（types, parser, options, nodes, commands, positionals, dashdash, constraints, access, parse, help, filter + 2テストファイル）
- src/wasm/ に782行のJSON schema → core → JSON result ブリッジ
- 667/667テスト通過（parse_wbtest.mbt 129KB + filter_wbtest.mbt 8.9KB）
- Docker CLI デモ（19シナリオ全通過）でリアルワールド検証済み

前回の提言 P0「今すぐ実装を始める」は達成。P1 の参照パス修正も kuu.mbt 移行で解消。

---

## リサーチドキュメント評価（13本）

### Tier 1 — 突出して良い（5本）

| ファイル | 評価 |
|---------|------|
| cli-parser-mega-survey | 28パーサ×8言語。ExactNode + Variation + FilterChain の設計根拠として完全に機能 |
| error-message-survey | clap の 17 ErrorKind まで掘り下げる深さ。Phase 4 のエラー設計に直結 |
| cli-argument-edge-cases | POSIX GL5 → X11(1984) → GNU(1992) の歴史。kuu の Priority 分類が実用的 |
| tui-mbt-patterns | tui.mbt から抽出したパターン集。kuu のコード規約に直結 |
| mooncakes-best-practices | 25リポ調査。mooncakes 公開準備に直接使える |

### Tier 2 — 良い（4本）

| ファイル | 評価 |
|---------|------|
| help-format-survey | 8パーサの --help 実出力比較。ヘルプ設計の根拠 |
| result-api-survey | ValueSource enum の発見が将来の multi-source defaults に直結 |
| utf8-experiment | UTF-16 内部表現の罠を実験で特定。CJK 幅計算への布石 |
| binary-size-survey | WASM-GC 37KB、JS minified+brotli 9KB。定量データがある |

### Tier 3 — 薄い（4本）

| ファイル | 問題 |
|---------|------|
| js-wasm-integration | 53行。クイックリファレンス止まり |
| moonbit-overview | 81行。語彙情報レベル |
| tui-cli-survey | 情報密度が低い |
| shimux-analysis | kuu と無関係。「Rust FFI 使え」で終わっている |

**リサーチ総評**: Tier 1 の5本は設計判断の根拠として完全に機能しており、「リサーチの質がコードの質を保証している」状態。Tier 3 の4本は sandbox-moonbit 時代の調査メモで、kuu リポジトリに持ってきた意味が薄い。整理候補。

---

## Decision Records 評価（DR-001〜038）

### 特に価値が高い DR

- **DR-012（ExactNode アーキテクチャ）** — 4層レイヤー構造の根幹。この1本がなければ kuu の設計は成立しない
- **DR-016（FilterChain）** — Kleisli 合成。map/validate/parse の3コンストラクタ + then。理論的に美しく、filter.mbt として動いている
- **DR-024（Variation enum 統一）** — DR-014 の2軸設計を1軸に簡素化。Toggle/True/False/Reset/Unset の5パターンで --no-xxx を完全解決
- **DR-037（alias/proxy プリミティブ）** — clone/link/adjust の3直交プリミティブ。未実装だが設計が美しい
- **DR-034（OC/P フェーズ分離）** — greedy/non-greedy の positional 消費制御

### DR の問題点

1. **DESIGN.md の遅延同期（DR-038 が指摘済み）**: at_least_one→required、alias 実装状態、OC/P フェーズ、cmd 戻り値型が DESIGN.md に未反映
2. **DR-001〜010 は旧世界**: ErasedNode/Opts enum 前提の設計。ExactNode ベースの現設計とは別世界。「DR-012 で全面置換」の注記がない
3. **粒度がバラバラ**: DR-011（121行）と DR-022（41行）と DR-036（356行）が同列

---

## ワークフロー評価

**jj ワークスペース × AI エージェント並列** は独創的。

- main ワークスペース: コード変更・テスト・機能実装に集中
- review ワークスペース: main@ をフォローし、発見を DR/DESIGN.md/.claude rules に落とす
- 10分/30分/1時間/3時間の cron でドキュメント同期を自動チェック

「1体がコードを書き、1体がレビュー/ドキュメントを書く」というワークフローが jj の仕組みで自然に統合される。このプラクティス自体が発表に値する。

---

## WASM bridge 評価（src/wasm/main.mbt, 782行）

**良い点**:
- スキーマバージョニング（version: 1）
- 8種のオプション + serial + command の再帰対応
- variations の5パターン全対応
- exclusive/required の制約サポート
- エラー出力が3種（success/error/help_requested）で構造化

**問題点**:
- kuu_parse が panic する可能性がある（WASM trap → DR-033 に記録済み）
- custom[T] のユーザー定義 reducer は JSON schema で表現不能（設計上の制約として認識済み）

---

## 総合評価の更新

### 前回（2026-03-04）との比較

| 項目 | 前回 | 今回 |
|------|------|------|
| 実装 | 0行 | 14モジュール + WASM bridge + 667テスト |
| 設計検証 | 未検証 | Docker CLI 19シナリオで実証済み |
| 設計文書の同期 | 崩壊 | 一部未同期だが自動チェックが稼働開始 |
| ドキュメント/コード比 | ∞（分母ゼロ） | 適正範囲に収束 |

### 結論

**production-ready な core が動いている。** Phase 1-3 は完了。Phase 4（alias/adjust, completion, multi-language DX）は設計済み・未実装。

前回の「ドキュメントを書き続けることが目的化している兆候がある」という批判は、kuu.mbt では完全に当てはまらない。リサーチの質がコードの質を保証している状態になっており、設計→実装→検証のサイクルが健全に回っている。

残る課題は **ドキュメント同期** の一点。DESIGN.md と実装、リサーチの提言と DESIGN.md、旧 DR と新 DR の間に部分的な陳腐化がある。ワークフローの自動チェックで解消される見込み。
