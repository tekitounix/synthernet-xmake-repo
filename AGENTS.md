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
