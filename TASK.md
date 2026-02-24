# CLI引数パーサ自作プロジェクト

## 目標

MoonBit でフルスクラッチの CLI 引数パーサライブラリを設計・実装する。
各言語のパーサを大規模調査した知見（`../main/docs/cli-parser-mega-survey.md`）を踏まえ、理想のパーサを作る。

## 必須要件（ユーザーの好み）

1. **サブコマンド**: 無制限ネスト（子・孫サブコマンド）
2. **引数なし実行 → `--help` 表示**: トップ・子・孫すべてで共通
3. **`--help` セクション分け**: サブコマンド一覧 / ローカルオプション / グローバルオプション / 環境変数
4. **ロングオプション基本**: ショートオプションは明示追加のみ
5. **`--no-xxx` boolフラグ反転**: Swift ArgumentParser の `FlagInversion` 3パターン参考
6. **オプション位置自由**: メイン引数の後ろにもオプションを置ける
7. **`--` セパレータ**: `opts... -- args...`
8. **completion 出力**: bash/zsh/fish 対応
9. **環境変数連携**: env 属性 + ヘルプへの表示 + プレフィックス自動バインド
10. **グローバルオプション**: 親→子への継承（cobra の Persistent Flags 相当）

## 調査で発見した取り入れるべき設計

- **Applicative 合成** (bpaf/optparse-applicative): 引数順序の自由度を構造的に保証
- **FlagInversion 3パターン** (Swift AP): `--no-xxx`, `--enable-xxx`/`--disable-xxx`, Optional Bool
- **FSM ベースコマンド解決** (Clipanion): 静的な曖昧さ検出
- **フラグ間制約** (kong/oclif): `xor`(排他), `and`(依存), `exactly_one`
- **プレフィックス自動バインド** (yargs): `MYAPP_VERBOSE` → `--verbose`
- **あいまいプレフィックスマッチ** (cligen): `--dry` = `--dry-run`（一意の場合）
- **did you mean? サジェスト** (cobra/clap): タイポ時の候補表示

## 理想的な `--help` 出力

```
myapp 1.0.0 - Description of the application

Usage: myapp [OPTIONS] <COMMAND>

Commands:
  serve     Start the server
  deploy    Deploy to production
  config    Manage configuration

Options:
  --verbose          Enable verbose output
  --format <FORMAT>  Output format [possible: json, yaml, text] [default: json]

Global Options:
  --config <PATH>    Configuration file path [env: MYAPP_CONFIG]
  --no-color         Disable colored output
  --help             Show this help message

Environment Variables:
  MYAPP_CONFIG       Configuration file path (overridden by --config)
  MYAPP_LOG_LEVEL    Log level [possible: debug, info, warn, error]
  MYAPP_NO_COLOR     Disable colored output (overridden by --no-color)
```

## 実装フェーズ

1. **Phase 1**: 型設計（enum/struct/suberror の定義とテスト）
2. **Phase 2**: パーサ実装 + apply_defaults + サブコマンド + `--no-xxx` 反転
3. **Phase 3**: ヘルプ生成 + completion 生成（bash/zsh/fish）
4. **Phase 4**: 高度な機能（FSM 最適化、i18n、プレフィックスマッチ、フラグ間制約）

## 参考資料

- `../main/docs/cli-parser-mega-survey.md` - 28パーサの大規模調査
- `../main/docs/cli-parser-initial.md` - MoonBit既存パーサ評価
- `/moonbit-practice` スキル - MoonBit コーディング規約

## MoonBit の方針

- TDD: テストファーストで実装
- `moon test -u` でスナップショットテスト活用
- 低レイヤーは不要（純粋なパーサロジック）
- `@env.args()` でコマンドライン引数取得
