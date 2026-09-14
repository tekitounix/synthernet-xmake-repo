---
status: live
---

# Purpose

## 目的

`synthernet-xmake-repo` は、ARM embedded development と UMI package consumption に必要な
xmake package definitions、rules、plugins、toolchain adapters を提供する source repository
である。

## 境界

- `packages/` の definition が provider-side の正本であり、user の `~/.xmake` に展開された
  cache/rule/plugin は生成・導出物である。
- UMI product 固有の判断や source は consumer repository が所有する。
- package health は静的定義、isolated install、consumer build を区別して評価する。
- test のために user config や通常 cache を変更しない。flash/probe/device 操作は別の明示的
  権限を要する。

## 検証

変更対象に応じて xmake definition の読み込み、isolated package cache、対象 consumer の build
を選ぶ。不足 dependency や未実行の hardware validation を成功扱いしない。
