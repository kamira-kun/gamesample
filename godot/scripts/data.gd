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


# =================== items ===================
const RARITY := [
	{"name": "ノーマル", "color": Color("#cfcfcf"), "aff": [0, 0], "w": 60.0},
	{"name": "マジック", "color": Color("#5b9bff"), "aff": [1, 2], "w": 29.0},
	{"name": "レア", "color": Color("#ffd23f"), "aff": [3, 4], "w": 9.0},
	{"name": "レジェンド", "color": Color("#ff7b1c"), "aff": [3, 4], "w": 1.6},
]

const SLOTS := ["weapon", "helm", "armor", "gloves", "boots", "ring", "amulet"]
const SLOT_INFO := {
	"weapon": {"name": "武器", "glyph": "剣"}, "helm": {"name": "兜", "glyph": "兜"}, "armor": {"name": "鎧", "glyph": "鎧"},
	"gloves": {"name": "手袋", "glyph": "甲"}, "boots": {"name": "靴", "glyph": "靴"}, "ring": {"name": "指輪", "glyph": "環"},
	"amulet": {"name": "首飾り", "glyph": "飾"},
}

const BASES := {
	"weapon": [
		{"name": "片手剣", "min": 4, "max": 8, "aps": 1.5},
		{"name": "戦斧", "min": 6, "max": 12, "aps": 1.2},
		{"name": "大槌", "min": 9, "max": 17, "aps": 0.95},
		{"name": "ルーンの杖", "min": 3, "max": 7, "aps": 1.3, "implicit": {"spell_dmg": 25}},
		{"name": "短剣", "min": 3, "max": 6, "aps": 1.8, "implicit": {"crit": 3}},
	],
	"helm": [{"name": "革の頭巾", "armor": 4, "implicit": {"mana": 8}}, {"name": "鉄兜", "armor": 9}],
	"armor": [{"name": "布のローブ", "armor": 6, "implicit": {"mana": 15}}, {"name": "鎖帷子", "armor": 14}, {"name": "板金鎧", "armor": 22}],
	"gloves": [{"name": "革手袋", "armor": 3, "implicit": {"atk_spd": 3}}, {"name": "鉄の篭手", "armor": 7}],
	"boots": [{"name": "革靴", "armor": 3, "implicit": {"move_spd": 4}}, {"name": "鉄靴", "armor": 7}],
	"ring": [{"name": "銅の指輪", "implicit": {"life": 12}}, {"name": "銀の指輪", "implicit": {"mana": 12}}, {"name": "金の指輪", "implicit": {"crit": 2}}],
	"amulet": [{"name": "牙の首飾り", "implicit": {"inc_dmg": 8}}, {"name": "琥珀の護符", "implicit": {"life_regen": 2}}],
}

const ELEM_SLOTS := ["weapon", "helm", "ring", "amulet"]
const AFFIXES := [
	{"k": "inc_dmg", "fmt": "ダメージ +%d%%", "word": "猛き", "min": 6, "max": 14, "sc": 0.07, "slots": ["weapon", "ring", "amulet", "gloves"]},
	{"k": "flat_dmg", "fmt": "武器ダメージ +%d", "word": "鋭い", "min": 1, "max": 4, "sc": 0.2, "slots": ["weapon", "gloves", "ring"]},
	{"k": "life", "fmt": "最大ライフ +%d", "word": "頑強な", "min": 10, "max": 25, "sc": 0.12, "slots": ["helm", "armor", "gloves", "boots", "ring", "amulet"]},
	{"k": "mana", "fmt": "最大マナ +%d", "word": "賢明な", "min": 8, "max": 18, "sc": 0.08, "slots": ["helm", "armor", "ring", "amulet", "weapon"]},
	{"k": "armor", "fmt": "アーマー +%d", "word": "堅牢な", "min": 5, "max": 14, "sc": 0.15, "slots": ["helm", "armor", "gloves", "boots"]},
	{"k": "crit", "fmt": "クリティカル率 +%d%%", "word": "狙い澄ました", "min": 1, "max": 4, "sc": 0.02, "slots": ["weapon", "gloves", "ring", "amulet", "helm"]},
	{"k": "crit_multi", "fmt": "クリティカルダメージ +%d%%", "word": "残忍な", "min": 10, "max": 25, "sc": 0.04, "slots": ["weapon", "amulet", "gloves"]},
	{"k": "atk_spd", "fmt": "攻撃速度 +%d%%", "word": "迅速な", "min": 4, "max": 10, "sc": 0.02, "slots": ["weapon", "gloves", "ring"]},
	{"k": "cast_spd", "fmt": "詠唱速度 +%d%%", "word": "流麗な", "min": 4, "max": 10, "sc": 0.02, "slots": ["weapon", "helm", "ring", "amulet"]},
	{"k": "move_spd", "fmt": "移動速度 +%d%%", "word": "疾風の", "min": 4, "max": 10, "sc": 0.015, "slots": ["boots"]},
	{"k": "fire_dmg", "fmt": "火炎ダメージ +%d%%", "word": "燃え盛る", "min": 8, "max": 20, "sc": 0.07, "slots": ELEM_SLOTS},
	{"k": "cold_dmg", "fmt": "冷気ダメージ +%d%%", "word": "凍てつく", "min": 8, "max": 20, "sc": 0.07, "slots": ELEM_SLOTS},
	{"k": "light_dmg", "fmt": "雷ダメージ +%d%%", "word": "轟く", "min": 8, "max": 20, "sc": 0.07, "slots": ELEM_SLOTS},
	{"k": "spell_dmg", "fmt": "スキルダメージ +%d%%", "word": "神秘の", "min": 8, "max": 18, "sc": 0.07, "slots": ["weapon", "helm", "amulet", "armor"]},
	{"k": "life_regen", "fmt": "ライフ回復 +%d/秒", "word": "再生の", "min": 1, "max": 3, "sc": 0.1, "slots": ["armor", "helm", "amulet", "boots"]},
	{"k": "mana_regen", "fmt": "マナ回復 +%d/秒", "word": "瞑想の", "min": 1, "max": 3, "sc": 0.05, "slots": ["helm", "ring", "amulet", "armor"]},
	{"k": "life_on_kill", "fmt": "撃破時ライフ +%d", "word": "貪欲な", "min": 2, "max": 5, "sc": 0.12, "slots": ["weapon", "gloves", "ring"]},
	{"k": "cdr", "fmt": "クールダウン短縮 +%d%%", "word": "時を刻む", "min": 3, "max": 7, "sc": 0.0, "slots": ["helm", "amulet"]},
]

const LEGENDARY := [
	{"name": "灰燼の王冠", "slot": "helm", "base": 1, "effect": "fireball_multi", "desc": "ファイアボールが3方向に放たれる"},
	{"name": "霜纏いの足跡", "slot": "boots", "base": 0, "effect": "dash_nova", "desc": "シャドウダッシュの終点でフロストノヴァが発動する"},
	{"name": "嵐呼びの指輪", "slot": "ring", "base": 2, "effect": "chain_plus", "desc": "チェインライトニングの連鎖数 +4"},
	{"name": "処刑人の大剣", "slot": "weapon", "base": 1, "effect": "slash_wave", "desc": "斬撃が貫通する衝撃波を放つ"},
	{"name": "血盟の首飾り", "slot": "amulet", "base": 0, "effect": "kill_heal", "desc": "敵を倒すと最大ライフの3%を回復する"},
	{"name": "流星の籠手", "slot": "gloves", "base": 1, "effect": "meteor_shower", "desc": "メテオが追加で2つ降り注ぐ"},
	{"name": "不屈の胸当て", "slot": "armor", "base": 2, "effect": "nova_on_hit", "desc": "被弾時20%の確率でフロストノヴァが発動する"},
]

const RARE_A := ["災厄", "黄昏", "血染め", "嵐", "亡霊", "灰", "深淵", "黒鉄", "緋色", "月影", "残光", "骸"]
const RARE_B := ["の牙", "の囁き", "の誓約", "の棘", "の鎖", "の祈り", "の咆哮", "の残響", "の印", "の爪"]

# =================== currencies ===================
# ember shards are spent with the merchant; the rest craft items
const CURRENCIES := [
	{"k": "ember", "name": "灰燼の欠片", "icon": "◆", "color": Color("#ffb35a"), "w": 0.0, "desc": "商人との取引に使う基本通貨。"},
	{"k": "transmute", "name": "変容の結晶", "icon": "✦", "color": Color("#6aa8ff"), "w": 40.0, "value": 5, "desc": "ノーマルアイテムをマジックに変える。"},
	{"k": "ascend", "name": "昇華の焔", "icon": "▲", "color": Color("#ffd23f"), "w": 12.0, "value": 20, "desc": "マジックアイテムをレアに変える。"},
	{"k": "chaos", "name": "混沌の残光", "icon": "✺", "color": Color("#c070ff"), "w": 14.0, "value": 25, "desc": "マジック・レアのオプションをすべて作り直す。"},
	{"k": "whet", "name": "鍛錬の砥石", "icon": "◈", "color": Color("#9ad0a0"), "w": 16.0, "value": 15, "desc": "マジック・レアにオプションを1つ追加する。"},
	{"k": "purify", "name": "浄化の雫", "icon": "◯", "color": Color("#d8e8f0"), "w": 12.0, "value": 8, "desc": "オプションをすべて消してノーマルに戻す。"},
	{"k": "divine", "name": "神秘の核", "icon": "✷", "color": Color("#ff8a2c"), "w": 3.0, "value": 80, "desc": "オプションの数値だけを振り直す。レジェンドにも使える。"},
	{"k": "compass", "name": "羅針の欠片", "icon": "✧", "color": Color("#7fd4ff"), "w": 10.0, "value": 12, "desc": "遠征図でマップ効果を振り直す。"},
]


static func affix(k: String) -> Dictionary:
	for a in AFFIXES:
		if a.k == k:
			return a
	return {}


static func currency(k: String) -> Dictionary:
	for c in CURRENCIES:
		if c.k == k:
			return c
	return {}


# =================== expedition atlas ===================
const ATLAS_NODES := [
	{"id": "ash", "name": "灰の入口", "theme": 0, "level": 1, "x": 0.07, "y": 0.55, "links": ["bone", "wail"], "desc": "深淵へ続く最初の階段。灯火を掲げて進め。"},
	{"id": "bone", "name": "骨の回廊", "theme": 0, "level": 2, "x": 0.2, "y": 0.3, "links": ["ember"], "desc": "無数の骨が積み上げられた細い通路。"},
	{"id": "wail", "name": "嘆きの納骨堂", "theme": 0, "level": 3, "x": 0.24, "y": 0.75, "links": ["ember", "obsidian"], "desc": "夜な夜な泣き声が響くという古い納骨堂。"},
	{"id": "ember", "name": "燻る坑道", "theme": 1, "level": 4, "x": 0.38, "y": 0.42, "links": ["forge"], "desc": "地熱で焼けた岩が赤く光る廃坑。"},
	{"id": "obsidian", "name": "黒曜の裂け目", "theme": 1, "level": 5, "x": 0.43, "y": 0.8, "links": ["forge", "frost"], "desc": "溶岩が冷えて固まった鋭い岩の谷。"},
	{"id": "forge", "name": "溶鉄の炉心", "theme": 1, "level": 6, "x": 0.55, "y": 0.52, "links": ["cathedral"], "desc": "巨像が生まれたと伝わる灼熱の炉。"},
	{"id": "frost", "name": "凍てつく参道", "theme": 2, "level": 7, "x": 0.62, "y": 0.82, "links": ["cathedral", "grave"], "desc": "氷に閉ざされた巡礼者の道。"},
	{"id": "cathedral", "name": "霜の大聖堂", "theme": 2, "level": 8, "x": 0.72, "y": 0.35, "links": ["abyss"], "desc": "魔女が祈りを捧げる凍った聖堂。"},
	{"id": "grave", "name": "氷霧の墓標", "theme": 2, "level": 9, "x": 0.8, "y": 0.72, "links": ["abyss"], "desc": "霧の中に墓標が並ぶ静寂の丘。"},
	{"id": "abyss", "name": "残り火の深淵", "theme": -1, "level": 10, "x": 0.92, "y": 0.5, "links": [], "endless": true, "desc": "終わりなき深淵。踏破するたびに、さらに深く強大になる。"},
]
const THEME_COLORS := [Color("#c9b89a"), Color("#ff7a3a"), Color("#7fd4ff"), Color("#b48cff")]

const MAP_MODS := [
	{"k": "life", "name": "敵のライフ +40%", "life": 1.4},
	{"k": "dmg", "name": "敵のダメージ +30%", "dmg": 1.3},
	{"k": "swarm", "name": "敵の数 +40%", "swarm": 1.4},
	{"k": "fast", "name": "敵の移動速度 +25%", "speed": 1.25},
	{"k": "elite", "name": "エリートの出現率 2倍", "elite": 2.0},
]

const HIDEOUT := {"id": "hideout", "name": "隠れ家", "hideout": true}
const HIDEOUT_THEME := {"name": "隠れ家", "tint": Color("#ffe6c8"), "torch": Color("#ffc88c")}


static func atlas_node(id: String) -> Dictionary:
	for n in ATLAS_NODES:
		if n.id == id:
			return n
	return {}


static func map_mod(k: String) -> Dictionary:
	for m in MAP_MODS:
		if m.k == k:
			return m
	return {}
