# Worktree Status / Agents サイドパネル分離

## 背景

現在の `WorktreeStatusPane` は Worktree Status と Agents を同じパネルに固定表示している。#195 で両者の状態がウィンドウ単位に共有されたため、次の段階として、それぞれを独立して表示・非表示できる構成にする。

## 実装方針

- `AgentStatusModel` に表示状態を追加し、`WorktreeStatusModel` と同じ `open` / `close` / `toggle` 操作を提供する。
- `WorktreeStatusPane` から Agents の表示とポーリングを取り除く。
- Agents 専用の `AgentStatusPane` を追加し、表示中だけ検出ポーリングを実行する。
- `WorktreeStatusSplit` を両方の表示状態に対応させる。
  - どちらか一方だけ表示する場合は、既存どおりターミナルの左側に単独表示する。
  - 両方表示する場合は、サイドバー内を上下に分割し、各パネルを個別にリサイズできるようにする。
- View メニューに Agents の表示切り替えを追加する。既存の Worktree Status の切り替えは維持する。
- 既存のウィンドウ単位のモデル共有と、Agents 一覧からの Surface フォーカス移動は維持する。

## 実装結果

- `AgentStatusModel.isVisible` と表示状態操作を追加した。
- Agents 専用ペインへヘッダー、空状態、一覧、Surface フォーカス移動を移した。
- Worktree Status と Agents を同じ左サイドバーに表示し、両方表示時は上下分割できるようにした。
- `⌘⇧A` の View メニュー項目で Agents を個別に切り替えられるようにした。
- Agents 表示状態のモデルテストを追加した。

## 検証結果

- `just lint`: 成功（違反なし）。
- `just test-filter 'togglesAgentsPaneVisibility'`: 成功。
- `just test-fast`: 成功。macOS アプリのビルドと PR 向けテストを実行した。
- macOS 上の実際のパネル操作（表示切り替え、上下分割のリサイズ）は未実施。PR の実機確認対象とする。
