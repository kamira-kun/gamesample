# Emberfall (Godot 4)

ブラウザ版プロトタイプ（リポジトリ直下）を Godot 4 に移植しているプロジェクトです。

## 開き方
1. Godot 4.7 を起動し、「インポート」でこのフォルダの `project.godot` を選ぶ
2. F5（プロジェクトを実行）で遊べます

## 操作
| キー | 動作 |
|---|---|
| WASD | 移動（画面の上下左右） |
| 左クリック / 右クリック | 斬撃 / ファイアボール |
| Q / E / R | フロストノヴァ / チェインライトニング / メテオ |
| Space | シャドウダッシュ |
| F | 回復薬 |

## 構成
- `scripts/main.gd` — ゲームループ、ダンジョンの3D化、スキル・敵AI・戦闘、カメラ
- `scripts/dungeon.gd` — 部屋と通路のダンジョン生成、経路探索（ゲームの計算は平面グリッド上）
- `scripts/player.gd` / `enemy.gd` / `actor.gd` — キャラクターと仮モデル
- `scripts/hud.gd` — HUD（オーブ、スキルバー、体力バー、ダメージ数字、死亡画面）
- `scripts/fx.gd` — 仮メッシュ・マテリアル・エフェクトの生成
- `scripts/data.gd` — スキル・敵・テーマのデータ（オートロード `Data`）

- `scripts/assets.gd` / `level_builder.gd` — KayKit 素材の読み込みと、ダンジョンへの床・壁・たいまつ・小物の配置

## 素材（CC0）
`assets/kaykit/` に Kay Lousberg 氏の KayKit シリーズ（CC0）を収録しています。各フォルダに LICENSE.txt があります。
- [KayKit Dungeon Remastered](https://github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0) — 床、壁、柱、たいまつ、小物
- [KayKit Character Pack: Adventurers](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0) — プレイヤー（騎士）、ボス（バーバリアン）
- [KayKit Character Pack: Skeletons](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0) — スケルトン系の敵

インプはまだ仮の図形です。

## 開発用
自動テスト（スキル発動・ボス撃破・ポータル・死亡と再挑戦）:
```
Godot_v4.7.2-stable_win64.exe --headless --path . -- --smoke
```
