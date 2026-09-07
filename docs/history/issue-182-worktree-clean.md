# Worktree Statusからの削除失敗修正

## 関連

- Issue #182: Worktree Status サイドバーからWorktreeが削除できない

## 問題

Worktree Statusサイドバーで、現在フォーカスしているworktreeを削除しようと
すると、確認ダイアログで削除を承認しても実際には削除されない。

`gw clean`は実行元のworktreeを安全策として削除候補から除外する。Zashikiは
フォーカス中surfaceのpwdから`gw clean`を実行しているため、削除対象自身に
フォーカスしている場合は候補が空になり、エラーなしで終了してしまう。

## 方針

- `gw list --json`が返す`repository.path`を、最後に成功したrefreshの結果として
  保存する。
- `gw clean --json`はフォーカス中surfaceのpwdではなく、保存したrepository root
  から実行する。
- clean後のrefreshもrepository rootから行い、削除対象のディレクトリが消えた後
  でも一覧を更新できるようにする。
- refreshに失敗した場合は、既存一覧と同じく最後に成功したrepository rootを保持
  する。

## 実装

1. `WorktreeStatusModel`に`repositoryDirectory`を追加し、list成功時に更新した。
2. `clean()`の実行先とclean後refreshの実行先を`repositoryDirectory`に変更した。
3. 実装判断と検証結果をこの文書に記録した。

## 検証

- `just test-fast`: 成功（Zigテスト、macOS appのSwiftコンパイル/build）
- `just lint`: 成功（0 violations / 0 serious）
- `git diff --check`: 成功

## 完了条件

- フォーカス中worktreeから削除を実行しても、推奨対象が実際に削除される。
- clean後にWorktree Statusの一覧が更新される。
- 既存の`gw`エラー処理と、別worktreeからのclean動作を壊さない。
