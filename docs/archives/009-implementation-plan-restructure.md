# DR-009: 実装計画の再構築

日付: 2026-03-02

## 概要

古い Step 0-8 の実装計画を、6フェーズフックアーキテクチャに基づく新実装計画に全面書き直し。

## 決定事項

- 実装計画を MVP フェーズ（Step 0-4）+ 拡張フェーズ（Step 5-13）の2段階に構成
- パッケージ分割: core/, combinators/, parse/, resolve/, validate/, finalize/, preprocess/, output/
- MVP マイルストーン: parser.parse(args, opts) → parser.get(opt) のエンドツーエンド
- 拡張フェーズの Step 6-9, 12 は互いに独立で並行実装可能

## 背景・動機

- 旧計画は6フェーズフックアーキテクチャ導入前のもので、PreProcess/Validate/Finalize/Output フェーズが未反映
- Visibility, auto-env, mutual exclusion, dependent options, CompletionCandidate 等の設計済み要素が実装計画に含まれていなかった
- 古い計画がコンテキストに残るとフックアーキテクチャと矛盾した実装になるリスク

## 旧計画との対応

| 旧 | 新 | 変更 |
|----|-----|------|
| Step 0: 準備 | Step 0: 準備 | ほぼ同じ |
| Step 1: スコープ認識局所分解 | Step 3 に統合 | parse/ パッケージに |
| Step 2: 型定義 | Step 1: 型定義 | ReduceCtx, Visibility 等追加 |
| Step 3: コンビネータ | Step 2: コンビネータ | 基本のみ MVP, 拡張は Step 12 |
| Step 4: 名前解決 | Step 4: 名前解決 | Resolve フェーズとして位置づけ |
| Step 5: parse | Step 3: 消費ループ | 局所分解を統合 |
| Step 6: validate | Step 6: Validate | フック化 |
| Step 7: defaults | Step 7: Finalize | 環境変数連携含む |
| Step 8: CmdDef | Step 3 に統合 | 消費ループの一部 |
| (なし) | Step 5: フックパイプライン | 新規 |
| (なし) | Step 8: PreProcess | 新規 |
| (なし) | Step 9-11: Output | 新規（エラー/ヘルプ/補完） |
| (なし) | Step 13: テスト完全移行 | 新規 |

## 参考資料

- docs/phase4-design.md 「実装計画」セクション
- docs/phase4-design.md 「パースライフサイクルとフックアーキテクチャ」セクション
