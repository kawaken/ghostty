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

- `AgentConversationParser` と `AgentConversationHistory` を追加し、Claude / Codex の
  代表的なユーザー入力・応答マーカーを provider 別に解析する。
- `SurfaceView` に Surface 単位の履歴モデルを所有させ、SurfaceWrapper の監視タスクから
  750ms 間隔で更新する。Agent が終了・Surface が破棄された場合はモデルを空に戻す。
- Surface 右端に最大 24 件の薄いマーカーを表示し、ホバー時に短いプレビューを表示する。
  クリック時は既存の Surface focus と `scroll_to_row:<row>` action を使って移動する。
- Worktree Status の Agent 一覧は同じ Surface モデルを参照するようにし、検出ロジックと
  provider 状態が overlay と一覧で分裂しないようにした。
- parser fixture として Claude の user/assistant、Codex の複数行応答、未知マーカーの除外、
  スクロールバック行番号変換を追加した。

## 検証結果

- `swiftlint lint --strict` 通過。
- `just test-fast` は macOS app build まで成功したが、続く Zig 統合テストが無出力のまま長時間継続したため中断した。
- `xcodebuild -project macos/Zashiki.xcodeproj -scheme Zashiki -configuration Debug -destination platform=macOS -only-testing:ZashikiTests/AgentStatusTests SWIFT_ENABLE_EXPLICIT_MODULES=NO ENABLE_CODE_COVERAGE=NO test` 通過。
- Claude Code / Codex の実機 TUI におけるレールの見た目、ホバー、クリック後の位置、通常のマウス入力との干渉は hands-on verification 待ち。

## 対象外

- Agent との IPC / hook 連携、入力の再送信・編集・削除。
- 履歴の永続化、検索、Worktree Status への履歴表示。
- すべての TUI の完全な会話構造化。
