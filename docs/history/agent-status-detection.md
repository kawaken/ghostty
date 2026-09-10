# Worktree Status の Agents 状態判定改善

## Issue

[#186](https://github.com/kawaken/zashiki/issues/186)

## 目的

Worktree Status の Agents セクションで、確認待ち・処理中・入力待ちの画面を
`Unknown` と誤表示しない。実際の CLI 画面で prompt や進行表示の位置が末尾1行・
末尾8行の想定から外れても、状態を判定できるようにする。

## 方針

- `Esc to cancel` を確認ダイアログの待機シグナルとして扱う。
- 末尾の複数行から `>`, `❯`, `›` の prompt を探索し、下にツール固有のステータスバーが続く画面を `idle` とする。
- `thought for` と `Running … shell command` の構造化された進行表示を画面から検出する。
- 判定順は入力待ちを優先し、prompt が見つかった場合は古い進行表示より `idle` を優先する。
- 既知のシグナルがない画面は引き続き `unknown` とする。

## 実装

- `AgentDetector` の対象行を末尾16行へ広げ、prompt の探索を最後の1行に限定しない。
- 確認フッター、Codex の進行表示、実際のステータスバー付き prompt を回帰テストに追加する。

## 実装結果

- `Esc to cancel` の確認フッターを `waiting` として検出するようにした。
- 末尾16行から prompt を探索し、ステータスバー付きの `>` prompt を `idle` として検出するようにした。
- `thought for` と画面全体の `Running … shell command` を `working` として検出するようにした。
- prompt が見つかった場合は、画面に残った古い進行表示より `idle` を優先する回帰テストを追加した。

## 検証結果

- `just lint` — 成功。
- `xcodebuild test -only-testing:ZashikiTests/AgentStatusTests` — 成功。追加 fixture を含む16ケースが通過。
- `just test-fast` — macOS アプリの build は成功。続く test runner が約2分無出力のまま終了しなかったため中断した。targeted test は別途完走している。
