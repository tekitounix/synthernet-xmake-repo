# AGENTS.md — synthernet-xmake-repo

最初に [`docs/purpose.md`](docs/purpose.md)、[`README.md`](README.md)、package health を扱う
場合は [`docs/PACKAGE_HEALTH_CHECK_SPEC.md`](docs/PACKAGE_HEALTH_CHECK_SPEC.md) を読む。

この repository は ARM 組込みと UMI consumer 向け xmake package の provider である。
package definition の変更は、source-level check と対象 consumer の isolated build を分けて
検証する。`~/.xmake`、user config、通常の package cache を検証のために変更しない。
`XMAKE_GLOBALDIR` を使う場合は、既存の親 directory を確認した隔離領域に限定する。

検証済みの横断知識を別 authority へ移す場合も、その service への ingest は明示された依頼を
要する。project 固有 Skill は現在なく、共通 Skill と作業規則は下の Tazuna 投影から Okite
を参照する。

<!-- tazuna:packages:begin -->
## Connected rule packages

Use only the relevant rules and Skills at these immutable paths.
Resolve normative tazuna://SOURCE/PATH references using this snapshot's source mapping.
- github.com/tekitounix/okite @ 9c27dc1cbc89e7ffc59bdd5928f102241cfc288e: `.tazuna/packages/objects/8b2e61d01e55a34cfd19/9c27dc1cbc89e7ffc59bdd5928f102241cfc288e`; rules: docs
Reference-only Skills are not registered as project commands. Shared Skills use their separately installed machine edition; explicit project-version reads use the paths above.

The instruction bodies below are already supplied. Do not reopen their source files solely to read the same instructions.

### Instructions from github.com/tekitounix/okite (docs/agent-instructions.md)

Generated from the fixed package above; edit the source, not this block.

- 作業に固有の知識を足す公開Skillは必要な入口だけ読む。読むこと自体を追加運用の承認とせず、外部AI併用、特別quota、認定、独自引継ぎは明示して選んだ範囲だけに適用する。
- 通常の直接作業・標準subagent・tool選択は依頼と権限の範囲でhostの判断に任せる。標準委譲に独自Skillや別の委任依頼を前提としない。ただし依頼がagy/Cursorなど特定の外部tool/modelを要求した場合は `tazuna-execution-requirement/v1` を保持し、未登録でも `tazuna route prepare-registration` → callableなら `register-runtime` を実行してから同じ要求を再評価する。未登録を理由に黙って標準Lunaや別harnessへ置き換えない。adapter/実行体が無い場合は `registration-needed` と次操作を返し、credential/login/install/支払い/外部送信を自動化しない。hostのraw `spawn_agent` の回答は必須routeのreceiptに代用しない。
- 通常作業は依頼とproject規約に沿って変更・検査し、許可された実装・統合は採用先への反映と作成領域の終了まで扱う（review・提案だけなら反映せず、詳細は接続版Okiteの`docs/work-coordination.md`と`docs/git-safety.md`を対象時だけ読む）。
- 計画の作成・更新を依頼されたら、project所定の保存先と既存計画を確認し、計画ファイルを作成・更新する。「提案だけ」でも計画は保存し、実装は変更しない。回答に計画へのリンクを示す。一般的な質問だけでは計画を作らない。
- AIの利用枠は現行accountを読むhost標準機能を優先し、横断比較や明示quotaにはusage-statusの対応分岐を使う。残量観測と開始判定を区別し、未確認・推定・取得失敗を確定値にしない。無関係な作業で毎回取得しない。
- プロジェクト固有の配置・検証規則を適用する。配布やテストの成功を、モデルの指示遵守や依頼全体の完了と同一視しない。
- 固有名は正本または利用者が示した正式表記を使い、独自の略称や推測を加えない。製品名と実在path・code識別子・正確なtask titleを区別する（詳細は`docs/output-language.md`）。
- シークレットは .env の FIFO マウントまたは op run 経由でプロセスに渡す。値をシェルに出力しない。cat .env、printenv、env、op read、op item get を実行しない。
- 変数名の確認は MCP の list_variables で行う。値の確認は人間に依頼する。
- Environments への変数追加や接続先 URL の変更は、人間の承認なしに行わない。
- .env を cp、cat、リダイレクトで複製しない。テンプレートは .env.example と参照ファイル .env.op のみをコミットする。
- ログ出力・例外表示・テスト fixture にヘッダやトークンを含めない。ライブラリのログレベルは INFO 以上とする。
<!-- tazuna:packages:end -->
