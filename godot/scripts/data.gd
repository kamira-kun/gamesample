extends Node
## Static game data (autoload "Data"). Ported from the browser version's data.js.

var ui_font: SystemFont

const SKILL_ORDER := ["slash", "fireball", "nova", "chain", "meteor", "dash"]
const SKILLS := {
	"slash": {"name": "斬撃", "icon": "⚔", "mana": 0, "cd": 0.0, "attack": true, "color": Color("#c9b48a"), "key": "LMB",
		"desc": "前方の敵を薙ぎ払う。攻撃速度の影響を受ける。"},
	"fireball": {"name": "ファイアボール", "icon": "✹", "mana": 6, "cd": 0.0, "cast": 0.42, "color": Color("#ff7a2a"), "key": "RMB",
		"desc": "着弾時に爆発する火球を放つ。"},
	"nova": {"name": "フロストノヴァ", "icon": "❄", "mana": 16, "cd": 5.0, "cast": 0.3, "color": Color("#7fd4ff"), "key": "Q",
		"desc": "周囲に冷気を放ち、敵を凍結させる。"},
	"chain": {"name": "チェインライトニング", "icon": "ϟ", "mana": 12, "cd": 1.0, "cast": 0.35, "color": Color("#c9a8ff"), "key": "E",
		"desc": "カーソル付近の敵に雷を放ち、次々と連鎖する。"},
	"meteor": {"name": "メテオ", "icon": "☄", "mana": 30, "cd": 9.0, "cast": 0.5, "color": Color("#ff4d2a"), "key": "R",
		"desc": "カーソル位置に隕石を落とし、地面を燃やす。"},
	"dash": {"name": "シャドウダッシュ", "icon": "➤", "mana": 8, "cd": 2.5, "color": Color("#9a8cff"), "key": "SPC",
		"desc": "カーソル方向へ駆け抜け、通過した敵を切り裂く。移動中は無敵。"},
}

# radii and ranges are in meters (one dungeon tile = 2 m)
const ENEMY_TYPES := {
	"imp": {"name": "インプ", "r": 0.45, "life": 10, "dmg": 4, "speed": 6.8, "color": Color("#c4523a"), "atk_range": 0.6, "atk_cd": 0.9, "windup": 0.2, "xp": 4, "h": 1.0},
	"ghoul": {"name": "グール", "r": 0.55, "life": 18, "dmg": 7, "speed": 4.6, "color": Color("#7a9a5a"), "atk_range": 0.7, "atk_cd": 1.2, "windup": 0.3, "xp": 6, "h": 1.7},
	"archer": {"name": "骸骨弓兵", "r": 0.5, "life": 14, "dmg": 6, "speed": 4.2, "color": Color("#d8d0b8"), "ranged": true, "range": 15.0, "atk_cd": 1.9, "windup": 0.45, "xp": 7, "h": 1.8},
	"brute": {"name": "ブルート", "r": 0.9, "life": 60, "dmg": 16, "speed": 3.3, "color": Color("#8a5a9a"), "atk_range": 1.2, "atk_cd": 2.4, "windup": 0.75, "aoe": 3.2, "xp": 16, "h": 2.8},
	"shaman": {"name": "呪術師", "r": 0.5, "life": 16, "dmg": 11, "speed": 3.9, "color": Color("#4fb0c0"), "caster": true, "range": 15.0, "atk_cd": 3.2, "windup": 0.9, "xp": 10, "h": 1.9},
	"boss": {"name": "深淵の番人", "r": 1.5, "life": 650, "dmg": 20, "speed": 3.7, "color": Color("#b03030"), "boss": true, "atk_range": 1.6, "atk_cd": 1.6, "windup": 0.4, "xp": 220, "h": 4.1},
}

const ELITE_AFFIXES := [
	{"k": "swift", "name": "俊足"}, {"k": "armored", "name": "鉄壁"},
	{"k": "volatile", "name": "爆裂"}, {"k": "frenzied", "name": "狂乱"},
]

const THEMES := [
	{"name": "朽ちた地下墓所", "tint": Color.WHITE, "torch": Color("#ffbe78")},
	{"name": "溶岩の洞窟", "tint": Color("#ffb49a"), "torch": Color("#ff9a5a")},
	{"name": "凍てつく聖堂", "tint": Color("#b8d0ff"), "torch": Color("#c8dcff")},
]

const DMG_COLORS := {"phys": Color.WHITE, "fire": Color("#ff9a40"), "cold": Color("#8fdcff"), "light": Color("#d9b8ff")}


func _ready() -> void:
	# Japanese UI text needs a CJK font; use whatever the OS provides
	ui_font = SystemFont.new()
	ui_font.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo", "Hiragino Sans", "Noto Sans CJK JP", "sans-serif"])


static func xp_need(level: int) -> int:
	return roundi(25.0 * pow(level, 1.7) + 20.0)
