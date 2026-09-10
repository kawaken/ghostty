# Agent会話履歴のSurface内ナビゲーション

## Issue

[#187](https://github.com/kawaken/zashiki/issues/187)

## 目的

Claude Code / Codex を実行している Surface 自身に、端末スクロールバック内の
会話候補を示す履歴レールを表示する。候補を選択したときは既存の
`scroll_to_row` action で同じ Surface の該当行へ移動し、Worktree Status の一覧には
会話履歴を追加しない。

## 方針

- 会話履歴は `SurfaceView` ごとのメモリ上モデルとして保持し、Surface の破棄時に破棄する。
- 既存の Agent provider 検出を再利用し、Claude / Codex の識別ができない Surface では
  履歴を作らない。
- provider ごとの画面マーカーを使って、ユーザー入力または Agent 応答の開始行を候補化する。
  マーカーを認識できない画面は安全側に倒して候補を表示しない。
- `ghostty_surface_read_text` の `GHOSTTY_POINT_SCREEN` で取得したスクロールバック全体を
  750ms 間隔で再解析し、候補の行番号は `scrollbar.total` に合わせて `scroll_to_row` の
  行空間へ変換する。
- 履歴レールは Surface の右端に薄く表示し、候補をホバーしたときだけプレビューを出す。
  レール以外のマウス操作は端末へ通過させる。

## 実装

- Agent provider ごとの会話候補パーサーと、Surface 単位の履歴モデルを追加する。
- `SurfaceView` に履歴モデルを所有させ、既存のスクロール状態と画面キャッシュを入力にする。
- `SurfaceWrapper` に overlay と監視タスクを追加し、候補クリック時に Surface を focus して
  `scroll_to_row:<row>` を実行する。
- Claude / Codex の代表的な入力・応答・未認識画面、行番号変換、重複除去の単体テストを追加する。
- 実装完了後はこの文書を `docs/history/` へ移し、実装判断と検証結果を追記する。

## 対象外

- Agent との IPC / hook 連携、入力の再送信・編集・削除。
- 履歴の永続化、検索、Worktree Status への履歴表示。
- すべての TUI の完全な会話構造化。

## 検証

- `xcodebuild` の対象 Swift テストで parser / model の fixture を実行する。
- `just lint` と `just test-fast` を実行する。
- Claude Code / Codex の実機 TUI で、レール表示・ホバー・クリック移動・通常入力への影響を確認する。
