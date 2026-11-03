class_name Charms
## Compasses (コンパス, ember shells): brass pocket compasses whose needles are kindled with ember. Set into the expedition atlas
## before setting out (up to SLOTS of them, one per family), each adds its family's effect to that one map run and
## burns away as the map is entered. Maps drop them; they stack, kept per character (Player.charms) and in the
## league stash (Profiles.stash_charms).
## An id is "<family>_<tier>", e.g. "horde_2"; a stack is a count in a Dictionary id -> n.

const SLOTS := 4
const COLOR := Color("#ffb070")
const ICON := "⊕"
const TIER_NAMES := ["燻る", "灯る", "燃え盛る"]
const TIER_COLORS := [Color("#d8a070"), Color("#ffb860"), Color("#ff7a3a")]

# each family's effect per tier (index 0..2): `fx` is merged into the run's map effects (Atlas.effects keys plus
# the ember-shell ones: seals, boss_life, boss_dmg, boss_loot, tablets, jewel, cur); `value` is the tier I base price
# in ember shards (#59: the merchant prices them from `value`)
const FAMILIES := [
	{"k": "horde", "name": "群呼", "desc": "マップの敵の群れが大きくなる", "value": 30, "shell": Color("#c8643a"),
		"tiers": [{"swarm": 1.2}, {"swarm": 1.35}, {"swarm": 1.5}],
		"fmt": ["敵の群れの数と大きさ +20%", "敵の群れの数と大きさ +35%", "敵の群れの数と大きさ +50%"]},
	{"k": "elite", "name": "精鋭", "desc": "エリート（レアモンスター）が多く現れる", "value": 35, "shell": Color("#e0c050"),
		"tiers": [{"elite": 1.5}, {"elite": 2.0}, {"elite": 3.0}],
		"fmt": ["エリートの出現率 +50%", "エリートの出現率 2倍", "エリートの出現率 3倍"]},
	{"k": "hoard", "name": "蓄財", "desc": "灰燼の欠片とカレンシーが多く落ちる", "value": 35, "shell": Color("#f0a030"),
		"tiers": [{"gold": 0.3, "cur": 1.5}, {"gold": 0.6, "cur": 2.0}, {"gold": 1.0, "cur": 3.0}],
		"fmt": ["灰燼の欠片 +30%　カレンシーのドロップ 1.5倍", "灰燼の欠片 +60%　カレンシーのドロップ 2倍", "灰燼の欠片 +100%　カレンシーのドロップ 3倍"]},
	{"k": "relic", "name": "刻碑", "desc": "ルーンタブレットとジュエルが多く落ちる", "value": 45, "shell": Color("#7ad0e0"),
		"tiers": [{"tablets": 1, "jewel": 1.5}, {"tablets": 1, "jewel": 2.0}, {"tablets": 2, "jewel": 3.0}],
		"fmt": ["ボスのルーンタブレット +1　ジュエルのドロップ 1.5倍", "ボスのルーンタブレット +1　ジュエルのドロップ 2倍", "ボスのルーンタブレット +2　ジュエルのドロップ 3倍"]},
	{"k": "seal", "name": "封紋", "desc": "刻紋の封碑が必ず眠っている", "value": 50, "shell": Color("#5ff0c0"),
		"tiers": [{"seals": 1}, {"seals": 2}, {"seals": 3}],
		"fmt": ["刻紋の封碑 1つ確定", "刻紋の封碑 2つ確定", "刻紋の封碑 3つ確定"]},
	{"k": "tyrant", "name": "燼冠", "desc": "ボスが燼冠を戴き、強く、多くを落とす", "value": 45, "shell": Color("#ff5a3a"),
		"tiers": [{"boss_life": 1.5, "boss_dmg": 1.2, "boss_loot": 2}, {"boss_life": 2.0, "boss_dmg": 1.35, "boss_loot": 3},
			{"boss_life": 3.0, "boss_dmg": 1.5, "boss_loot": 5, "legend": 0.25}],
		"fmt": ["ボスのライフ +50%・ダメージ +20%　ボスのアイテム +2", "ボスのライフ 2倍・ダメージ +35%　ボスのアイテム +3",
			"ボスのライフ 3倍・ダメージ +50%　ボスのアイテム +5　レジェンド率 +25%"]},
	{"k": "peril", "name": "苛烈", "desc": "敵が手強くなり、見返りも大きくなる", "value": 40, "shell": Color("#b060ff"),
		"tiers": [{"life": 1.3, "dmg": 1.15, "rarity": 0.4, "quantity": 0.2, "xp": 0.15},
			{"life": 1.6, "dmg": 1.3, "rarity": 0.8, "quantity": 0.4, "xp": 0.3},
			{"life": 2.0, "dmg": 1.5, "rarity": 1.2, "quantity": 0.6, "xp": 0.5}],
		"fmt": ["敵のライフ +30%・ダメージ +15%　アイテムレア度 +40%・数量 +20%・経験値 +15%",
			"敵のライフ +60%・ダメージ +30%　アイテムレア度 +80%・数量 +40%・経験値 +30%",
			"敵のライフ 2倍・ダメージ +50%　アイテムレア度 +120%・数量 +60%・経験値 +50%"]},
]
const TIER_VALUE := [1.0, 2.5, 6.0]
# effects that multiply when two shells (or a shell and a map modifier) touch them; the rest add up
const MULTIPLY := ["life", "dmg", "speed", "swarm", "elite", "cur", "jewel", "boss_life", "boss_dmg"]


static func family(k: String) -> Dictionary:
	for f in FAMILIES:
		if f.k == k:
			return f
	return {}


static func id_of(fam: String, tier: int) -> String:
	return "%s_%d" % [fam, tier + 1]


## {fam, tier (0..2), def} for an id, or {} when it names no shell
static func parse(id: String) -> Dictionary:
	var i := id.rfind("_")
	if i < 0:
		return {}
	var f := family(id.left(i))
	var t := int(id.substr(i + 1)) - 1
	if f.is_empty() or t < 0 or t >= f.tiers.size() or str(t + 1) != id.substr(i + 1):
		return {}
	return {"fam": f.k, "tier": t, "def": f}


static func valid(id: String) -> bool:
	return not parse(id).is_empty()


## every id, family by family and tier by tier
static func all_ids() -> Array:
	var out := []
	for f in FAMILIES:
		for t in f.tiers.size():
			out.append(id_of(f.k, t))
	return out


static func name_of(id: String) -> String:
	var c := parse(id)
	return "%s%sのコンパス" % [TIER_NAMES[c.tier], c.def.name] if not c.is_empty() else id


static func color_of(id: String) -> Color:
	var c := parse(id)
	return TIER_COLORS[c.tier] if not c.is_empty() else COLOR


## the effect text of an id
static func effect_text(id: String) -> String:
	var c := parse(id)
	return c.def.fmt[c.tier] if not c.is_empty() else ""


## the base price in ember shards (#59 prices the merchant's stock from this)
static func value(id: String) -> int:
	var c := parse(id)
	return roundi(c.def.value * TIER_VALUE[c.tier]) if not c.is_empty() else 0


## what a shell adds to a run's map effects
static func fx_of(id: String) -> Dictionary:
	var c := parse(id)
	return c.def.tiers[c.tier] if not c.is_empty() else {}


## fold the shells `ids` into map effects `fx` (from Atlas.effects)
static func apply(fx: Dictionary, ids: Array) -> Dictionary:
	for k in ["seals", "boss_loot", "tablets"]:
		fx[k] = fx.get(k, 0)
	for k in ["cur", "jewel", "boss_life", "boss_dmg"]:
		fx[k] = fx.get(k, 1.0)
	for id in ids:
		var add := fx_of(id)
		for k in add:
			if k in MULTIPLY:
				fx[k] = fx.get(k, 1.0) * add[k]
			else:
				fx[k] = fx.get(k, 0) + add[k]
	return fx


# =================== slotting ===================
## "" when shell `id` can be set into `slots` with `owned` stacks, else why not
static func can_slot(slots: Array, owned: Dictionary, id: String) -> String:
	if not valid(id):
		return "コンパスではない"
	if slots.size() >= SLOTS:
		return "コンパスは %d つまで" % SLOTS
	if int(owned.get(id, 0)) <= slots.count(id):
		return "%s を持っていない" % name_of(id)
	var fam: String = parse(id).fam
	if slots.any(func(s): return parse(s).get("fam", "") == fam):
		return "同じ系統のコンパスは1つまで"
	return ""


## burn the slotted shells out of `owned`: returns the ids that were really there to burn
static func consume(slots: Array, owned: Dictionary) -> Array:
	var used := []
	for id in slots:
		if int(owned.get(id, 0)) > 0:
			owned[id] = int(owned[id]) - 1
			if owned[id] <= 0:
				owned.erase(id)
			used.append(id)
	slots.clear()
	return used


static func add(owned: Dictionary, id: String, n := 1) -> void:
	if valid(id) and n > 0:
		owned[id] = int(owned.get(id, 0)) + n


static func count(owned: Dictionary) -> int:
	var n := 0
	for id in owned:
		n += int(owned[id])
	return n


# =================== drops ===================
## a random shell for an area of level `lvl`: the higher tiers grow likelier with the level
static func roll(lvl: int) -> String:
	var f: Dictionary = FAMILIES.pick_random()
	var w: Array[float] = [6.0, 2.0 + lvl * 0.15, 0.4 + lvl * 0.08]
	var r := randf() * (w[0] + w[1] + w[2])
	var t := 0 if r < w[0] else (1 if r < w[0] + w[1] else 2)
	return id_of(f.k, t)


## the chance a slain enemy drops a shell
static func drop_chance(boss: bool, elite: bool) -> float:
	return 0.6 if boss else (0.05 if elite else 0.004)


# =================== text ===================
static func lines(id: String, n := 0) -> Array:
	var c := parse(id)
	if c.is_empty():
		return [[id, COLOR, 16]]
	var out := [[name_of(id), color_of(id), 17], ["コンパス（%s・階位 %d）" % [c.def.name, c.tier + 1], Color("#9a9080"), 13]]
	var tiers := []
	for t in c.def.tiers.size():
		tiers.append("階位%d：%s" % [t + 1, c.def.fmt[t]])
	# Alt shows what every tier of the family does
	out.append([effect_text(id), Color("#ffcf8a"), 14, effect_text(id) + "\n" + "\n".join(PackedStringArray(tiers))])
	out.append([c.def.desc, Color("#c8b898"), 13])
	out.append(["遠征図で出撃前にはめる。マップに入ると燃え尽きる（%d つまで・同じ系統は1つ）" % SLOTS, Color("#7a7266"), 12])
	out.append(["価値 ◆ %d" % value(id) + ("　所持 %d" % n if n > 0 else ""), Color("#b8a888"), 12])
	return out


## a saved stack dictionary, with unknown ids and bad counts dropped
static func normalize(raw) -> Dictionary:
	var out := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for id in raw:
		var n := int(raw[id]) if typeof(raw[id]) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING] else 0
		if valid(str(id)) and n > 0:
			out[str(id)] = n
	return out


## saved slots: known ids the stacks still hold, one per family, SLOTS at most
static func normalize_slots(raw, owned: Dictionary) -> Array:
	var out := []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for id in raw:
		if can_slot(out, owned, str(id)) == "":
			out.append(str(id))
	return out


## how a compass's icon tells it apart: the family's colour lights the dial, the crown gem and the needle; the tier adds
## dial ticks (4 / 8 / 16) and studs on the bezel (0 / 4 / 8)
const TIER_TICKS := [4, 8, 16]
const TIER_STUDS := [0, 4, 8]
const BRASS := Color("#c49a4c")


static func icon_spec(id: String) -> Dictionary:
	var p := parse(id)
	var t: int = p.tier if not p.is_empty() else 0
	var fam: Color = p.def.shell if not p.is_empty() else COLOR
	return {"fam": fam, "glow": color_of(id), "ticks": TIER_TICKS[t], "studs": TIER_STUDS[t]}


## the compass drawn as a brass pocket compass: a ring on top set with the family's gem, a bezel (studded by tier),
## a dark dial tinted by the family with cardinal ticks and a north mark, and a needle whose north half glows
static func draw_icon(ci: CanvasItem, c: Vector2, s: float, id: String) -> void:
	var sp := icon_spec(id)
	var fam: Color = sp.fam
	var w := maxf(1.0, s * 0.05)
	var r := s * 0.44
	c += Vector2(0, s * 0.08)
	var top := c + Vector2(0, -r)
	ci.draw_arc(top + Vector2(0, -s * 0.13), s * 0.09, 0, TAU, 16, BRASS.darkened(0.2), w * 1.4, true)   # the bow
	ci.draw_rect(Rect2(top + Vector2(-s * 0.07, -s * 0.07), Vector2(s * 0.14, s * 0.09)), BRASS.darkened(0.1))   # the crown
	ci.draw_circle(c, r, BRASS.darkened(0.45))   # the case
	ci.draw_circle(c, r * 0.94, BRASS)
	ci.draw_arc(c, r * 0.88, PI * 1.05, PI * 1.6, 12, BRASS.lightened(0.45), w, true)   # light on the bezel
	ci.draw_circle(c, r * 0.76, BRASS.darkened(0.55))
	ci.draw_circle(c, r * 0.72, fam.darkened(0.68).lerp(Color("#1a140c"), 0.35))   # the dial
	for k in sp.studs:
		var a: float = TAU * (k + 0.5) / sp.studs - PI / 2
		ci.draw_circle(c + Vector2(cos(a), sin(a)) * r * 0.85, maxf(0.8, s * 0.035), fam.lightened(0.35))
	for k in sp.ticks:
		var a: float = TAU * k / sp.ticks - PI / 2
		var major: bool = k % (sp.ticks / 4) == 0
		var dir := Vector2(cos(a), sin(a))
		ci.draw_line(c + dir * r * (0.5 if major else 0.6), c + dir * r * 0.68, BRASS.lightened(0.2) if major else BRASS.darkened(0.15), w if major else maxf(1.0, w * 0.6))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.7), c + Vector2(-r * 0.09, -r * 0.54), c + Vector2(r * 0.09, -r * 0.54)]), sp.glow)   # north
	# the needle, set a little east of north: a lit north half, a dark steel tail
	var d := Vector2.from_angle(-PI / 2 + 0.5)
	var n := d.orthogonal() * r * 0.11
	var tip := c + d * r * 0.6
	ci.draw_colored_polygon(PackedVector2Array([tip, c + n, c - n]), fam.lightened(0.25))
	ci.draw_colored_polygon(PackedVector2Array([c - d * r * 0.5, c - n, c + n]), Color("#8a8f98").darkened(0.3))
	ci.draw_circle(tip, s * 0.07, Color(sp.glow, 0.35))
	ci.draw_circle(tip, s * 0.035, sp.glow.lightened(0.5))
	ci.draw_circle(c, s * 0.055, BRASS.lightened(0.2))   # the pivot
	ci.draw_circle(top + Vector2(0, -s * 0.13), s * 0.05, fam.lightened(0.15))   # the crown gem in the bow
	ci.draw_arc(c, r * 0.6, PI * 1.15, PI * 1.45, 8, Color(1, 1, 1, 0.22), w, true)   # glint on the glass


## one square of a compass grid: the compass on a tile with the stack's count; hovering shows the tooltip
class Slot extends Control:
	signal clicked
	signal right_clicked
	var id := ""
	var n := 0
	var hud: Hud
	var extra: Array = []

	func _init(shell := "", count := 0, h: Hud = null) -> void:
		id = shell
		n = count
		hud = h
		custom_minimum_size = Vector2(52, 52)
		mouse_entered.connect(func():
			if id != "" and hud:
				hud.show_tip(Charms.lines(id, n) + extra))
		mouse_exited.connect(func():
			if hud:
				hud.hide_tip())

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_LEFT:
				clicked.emit()
			elif e.button_index == MOUSE_BUTTON_RIGHT:
				right_clicked.emit()
			accept_event()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		if id == "":
			draw_rect(rect, Color("#0c0a08"))
			draw_rect(rect, Color("#3a3024"), false, 1.0)
			draw_string(Data.ui_font, Vector2(0, size.y / 2 + 5), "コンパス", HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, Color("#554a3a"))
			return
		var c := Charms.color_of(id)
		draw_rect(rect, c.darkened(0.85))
		draw_rect(rect, c.darkened(0.3), false, 1.0)
		Charms.draw_icon(self, size / 2.0 + Vector2(0, -2), minf(size.x, size.y) * 0.62, id)
		if n > 1:
			draw_string_outline(Data.ui_font, Vector2(2, size.y - 4), str(n), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 5, 13, 3, Color.BLACK)
			draw_string(Data.ui_font, Vector2(2, size.y - 4), str(n), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 5, 13, Color("#fff0d0"))
