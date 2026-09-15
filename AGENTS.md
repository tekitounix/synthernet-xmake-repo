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
- github.com/tekitounix/okite @ a69c61b5a507921005dcda7ae883ae69788a04c6: `.tazuna/packages/objects/8b2e61d01e55a34cfd19/a69c61b5a507921005dcda7ae883ae69788a04c6`; rules: docs
Reference-only Skills are not registered as project commands. Shared Skills use their separately installed machine edition; explicit project-version reads use the paths above.

The instruction bodies below are already supplied. Do not reopen their source files solely to read the same instructions.

### Instructions from github.com/tekitounix/okite (docs/agent-instructions.md)

Generated from the fixed package above; edit the source, not this block.

- 作業に固有の知識を足す公開Skillは必要な入口だけ読む。読むこと自体を追加運用の承認とせず、外部AI併用、特別quota、認定、独自引継ぎは明示して選んだ範囲だけに適用する。
- 通常の直接作業・標準subagent・tool選択は依頼と権限の範囲でhostの判断に任せる。標準委譲に独自Skillや別の委任依頼を前提としない。特定の外部tool/modelを指定された親のroutingは `tazuna-execution-requirement/v1` を保持し、route-aiの既存の公開入口で同じ要求を解決する。未登録だけで利用不能とせず、別model/harnessやraw `spawn_agent` の回答へ黙って置換しない。割当済みのbounded workerは再登録・再routingを繰り返さず、未充足の条件を親へ返す。adapter/実行体が無ければ `registration-needed` と次操作を返し、未承認のlogin/install/支払い/外部送信を行わない。
- 通常作業は依頼とproject規約に沿って変更・検査し、許可された実装・統合は採用先への反映と作成領域の終了まで扱う（review・提案だけなら反映せず、詳細は接続版Okiteの`docs/work-coordination.md`と`docs/git-safety.md`を対象時だけ読む）。
- 計画の作成・更新を依頼されたら、project所定の保存先と既存計画を確認し、計画ファイルを作成・更新する。「提案だけ」でも計画は保存し、実装は変更しない。回答に計画へのリンクを示す。一般的な質問だけでは計画を作らない。
- AIの利用枠は現行accountを読むhost標準機能を優先し、横断比較や明示quotaにはusage-statusの対応分岐を使う。残量観測と開始判定を区別し、未確認・推定・取得失敗を確定値にしない。無関係な作業で毎回取得しない。
- プロジェクト固有の配置・検証規則を適用する。配布やテストの成功を、モデルの指示遵守や依頼全体の完了と同一視しない。
- 固有名は正本または利用者が示した正式表記を使い、独自の略称や推測を加えない。製品名と実在path・code識別子・正確なtask titleを区別する（詳細は`docs/output-language.md`）。
- Markdown対応の人向け本文の参照URLは説明ラベル付きlinkにする。code・command・schema値・引用・指定された生URL・host固有形式は保つ（詳細は`docs/output-language.md`）。
- この利用者の全projectでは、資格情報の正本を1Passwordに限定する。AIが別の保存先を独自に作らない。選択と例外の正本はOkiteの`docs/agent-access.md`「この環境のproject横断の保管方針」であり、共有機構へ製品選択を埋め込まない。
- 秘密情報の保管先は利用者・組織・projectの採用方針を守る。汎用Skillや配布機構は製品を決めず、AIは別の保存先や複製を独自に作らない。既存sessionの利用を新規保存の許可に拡張しない。
- 秘密値は許可済みの注入・操作経路だけで扱い、.env等の通常file、argv、シェル出力へ出さない。1Passwordを選択した環境のFIFO / op runはsecret-runを参照する。実際の認証失敗は既存の承認範囲でagent-accessから回復し、元の操作へ戻る。経路を回復できなければ秘密を要する処理だけ止め、代替保存先へ逃げない。
- 設定調査は変数名・参照・状態などのmetadataに限定する。値を表示するcat .env、printenv、env、op read、op item get等は実行しない。秘密fileの複製を作らず、保存・移行・接続先変更の権限は現在の依頼から確認する。
- ログ出力・例外表示・テスト fixture にヘッダやトークンを含めない。ライブラリのログレベルは INFO 以上とする。
<!-- tazuna:packages:end -->
