# Worktree Statusパネルをウィンドウ(tabGroup)単位で共有する

## 関連

- Issue #195: Worktree Statusパネルをタブ単位ではなくウィンドウ(tabGroup)単位で共有する
- 派生Issue #197: Worktree StatusとAgentsを分離し個別に切り替え・分割表示できるようにする（本Planのスコープ外）
- 関連Issue #182 / #186: 同じ会話中の調査から派生した別バグ（本Planには含まない）

## 問題

`worktreeStatus`（Worktree Status一覧の状態）と`agentStatus`（Agents一覧、`WorktreeStatusPane`が
`@StateObject`で持つ）は、どちらも「タブ1枚」単位のインスタンスになっている。

Ghosttyの「タブ」は実体としては別々の`NSWindow`であり、`NSWindowTabGroup`
（`window.tabGroup`）でグループ化されて見た目上1つのウィンドウとして表示される
（`TerminalController.newTab`、`addTabbedWindowSafely`）。`worktreeStatus`と`agentStatus`は
`BaseTerminalController`（タブ1枚 = 1インスタンス）にひもづいているため、タブを切り替える
たびにWorktree Status/Agentsパネルの表示状態・読み込み結果がリセットされる。

VSCode等一般的なIDEのサイドパネルと同様、タブ切り替えでは状態を保持し、ウィンドウ（tabGroup）
ごとに1つ、複数ウィンドウを開いた場合はそれぞれ独立して持たせたい。

Markdown Previewは対象外（タブごとの表示のままでよい。プレビューしていないタブで空パネルが
出ると邪魔になるため）。

## 方針

### 共有方式: tabGroupキーのレジストリではなく親からの継承

検討した2案:

- (a) `NSWindowTabGroup`をキーにした共有ストア（レジストリ）を用意し、各`BaseTerminalController`が
  自分の`window.tabGroup`に対応するモデルをそこから取得する
- (b) 新規タブ作成時（`TerminalController.newTab`）に、親コントローラーが持つモデルインスタンスを
  そのまま新しいコントローラーに渡す

(a)はタブの分離・結合（ドラッグで別ウィンドウへ切り離す等）にも正しく追随できる一方、
`NSWindowTabGroup`の同一性やライフサイクル（分離時に新しいインスタンスが割り当てられるか、
identifierが変化するか）を検証する手段がなく、AppKit内部の未確認の挙動に依存するリスクが大きい。

(b)は「+ボタンやCmd+Tでタブを増やす」という最も一般的なユースケースを確実にカバーでき、
実装もシンプル。タブの分離操作への追随はできない（既知の制限として許容する）。

→ 今回は **(b) 親からの継承方式** を採用する。

### `agentStatus`をView層からModel層へ格上げ

現状 `agentStatus: AgentStatusModel` は `WorktreeStatusPane`（View）が`@StateObject`で持って
いる。タブ間で共有するには、`worktreeStatus`と同様に`BaseTerminalController`が所有するモデルに
格上げし、同じ注入パターンで共有する。

### Agents一覧の対象範囲: tabGroup内の全タブ・全ペインを横断する

Issueでの確認により、Agents一覧はアクティブなタブだけでなく、同じウィンドウ（tabGroup）内の
全タブ・全分割ペインのsurfaceを対象にする（一覧から任意のタブ/ペインへ遷移できることが前提の
ため）。

収集方法: `BaseTerminalController`に、自分の`window.tabGroup?.windows`（tabGroupがなければ
自分の`window`のみ）から各windowの`windowController as? BaseTerminalController`を取り出し、
それぞれの`surfaceTree`を合算する`tabGroupSurfaces`を追加する。

既存の`monitorAgents()`は750ms間隔で`agentStatus.refresh(surfaces:)`を呼ぶポーリング実装に
なっている。`surfaces`の取得元を「自分のsurfaceTreeのみ」から`tabGroupSurfaces`に変えるだけで、
タブの追加・削除・並び替えといった構成変化に、次のポーリングで自然に追随できる。tabGroupの
変化を明示的に検知する仕組み（`tabWindowsHash`のような）は不要。

### Worktree Statusのdirectory監視をタブ切り替えにも反応させる

現状、`gw list`の実行対象ディレクトリは`TerminalView`の`onChange(of: pwdURL)`
（フォーカスされているsurfaceのpwd変化）でのみ更新される。共有モデルにすると、
同じtabGroup内の別タブに切り替えたとき（pwdが変化するとは限らない）にも、
「今アクティブなタブのsurfaceのpwd」に応じて再評価したい。

`TerminalController.windowDidBecomeKey`（タブ切り替えでそのタブがkeyWindowになったタイミングで
必ず呼ばれる）に、`worktreeStatus.refresh(directory:)`を呼ぶ処理を追加する。

### スコープ外・既知の制限

- タブをドラッグして別ウィンドウへ切り離す／別ウィンドウへ統合する操作をした場合、
  切り離されたタブは元の共有モデルをそのまま参照し続ける（新しいモデルには切り替わらない）。
  クラッシュや不整合データは起きないが、期待される分離後の独立性は今回のスコープでは
  提供しない。
- パネルの分離・切り替え・分割表示UI自体はIssue #197のスコープ。

## 実装

1. `AgentStatusModel`の所有を`WorktreeStatusPane`の`@StateObject`から
   `BaseTerminalController`の`let`プロパティに移す。
2. `BaseTerminalController.init`（および`TerminalController.init`）に
   `worktreeStatus: WorktreeStatusModel? = nil`・`agentStatus: AgentStatusModel? = nil`の
   注入引数を追加し、`nil`なら新規作成する。
3. `BaseTerminalController`に`tabGroupSurfaces: [Zashiki.SurfaceView]`
   （tabGroup内の全controllerのsurfaceTreeを合算するcomputed property）を追加する。
4. `TerminalController.newTab`で、新しいcontrollerの生成時に親controllerの
   `worktreeStatus`・`agentStatus`をそのまま渡す。`TerminalController.newWindow`は
   現状通り新規モデルを作成する（変更なし）。
5. `TerminalViewModel`プロトコルに`agentStatus`・`tabGroupSurfaces`を追加し、
   `TerminalView`/`WorktreeStatusPane`が`viewModel`経由でアクセスするように更新する。
   `WorktreeStatusPane`は`agentStatus`を`@StateObject`ではなく`@ObservedObject`で受け取る
   形に変更する。
6. `TerminalController.windowDidBecomeKey`で、アクティブになったタブの
   `focusedSurface?.pwd`に応じて`worktreeStatus.refresh(directory:)`を呼ぶ
   （`worktreeStatus.isVisible`のときのみ）。
7. 実装判断と検証結果をこの文書へ追記し、`docs/history/`へ移動する。

## 検証

- `just test-fast`
- `just lint`
- macOS app build
- 実機確認（ローカルビルド、既存の別アプリは終了しない）:
  - 新規タブを開いてもWorktree Statusパネルの表示状態・一覧内容が保持されること
  - 新しいウィンドウ（`newWindow`）を開くと、そちらは独立したWorktree Statusを持つこと
  - タブを切り替えるとAgents一覧に同じウィンドウ内の全タブのAgentが表示され、
    一覧から選んだAgentのタブ/ペインへフォーカス遷移できること
  - タブを切り替えたときに、そのタブのディレクトリを基準にWorktree Status一覧が更新されること

## 完了条件

- Issue #195の要望（タブ単位ではなくウィンドウ単位でWorktree Status/Agentsの状態を共有する）が
  実アプリで確認できる（人手確認待ち）。
- 既存のWorktree Status/Agents/Markdown Previewの表示・操作を壊していない。
- Planに実装判断とCI/実機検証結果を記録し、実装PRで`docs/history/`に移動する。

## 実装結果

「実装」セクションの1〜6を計画通りに実装した。

### 既知の制限（実装後の確認）

- `WorktreeStatusPane`の`.task(id: surfaces.map(\.id))`によるAgentsポーリング（750ms間隔）は、
  tabGroup内のタブごとに1つ動く（各タブが自分のSwiftUIビュー階層内で`WorktreeStatusPane`を
  描画するため）。同じ`agentStatus`に対して重複してrefreshするだけで結果は壊れないが、
  タブ数分のポーリングが並行して走る。タブ数が数個程度の通常利用では実用上問題ないと判断し、
  今回は対処しない。
- 方針通り、タブをドラッグして別ウィンドウへ切り離す操作には追随しない（切り離し後も元の
  共有モデルをそのまま参照し続ける）。

## 検証結果

- `just lint`: 成功（0 violations, 0 serious / 187 files）
- `just test-fast`（`zig build test -Dmacos-app-xctest=false`、macOSアプリのビルドを含む）:
  `BUILD SUCCEEDED`、exit code 0
- `just test`（フルスイート、macOS XCTestを含む）: 全テストケースpassed、exit code 0。
  `AgentStatusTests`・`GwClientTests`を含め failure 0件。
- 実機でのタブ切り替え・複数ウィンドウ・Agents一覧からのタブ/ペイン遷移の目視確認は未実施
  （人手確認待ち）。
