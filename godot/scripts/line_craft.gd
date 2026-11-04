class_name LineCraft
## One-line crafting (一行クラフト): work on a single stat line of a magic or rare item, or of a rune tablet,
## leaving the other lines as they are. 付け替え turns the line into another one the item can carry (a new roll),
## 磨き直し rerolls only its value. What it costs follows the item level: each band of item levels asks for
## its own currency, and more of it the deeper into the band the item is (TIERS).

const ACTIONS := [
	{"k": "swap", "name": "付け替え", "desc": "この行を別の能力に変える"},
	{"k": "tune", "name": "磨き直し", "desc": "この行の数値だけを振り直す"},
]

# the item-level bands, from `from` up to the next band: for each action the currency, how many at the
# band's first level (`n`) and one more every `step` levels after it. The bands are set so that the price
# in exchange value never drops from one band to the next (whet 15 / chaos 25 / divine 80, transmute 5)
const TIERS := [
	{"from": 0, "name": "浅層", "swap": {"k": "whet", "n": 1, "step": 3}, "tune": {"k": "transmute", "n": 1, "step": 3}},
	{"from": 9, "name": "中層", "swap": {"k": "chaos", "n": 2, "step": 4}, "tune": {"k": "whet", "n": 1, "step": 4}},
	{"from": 17, "name": "深層", "swap": {"k": "divine", "n": 1, "step": 6}, "tune": {"k": "chaos", "n": 2, "step": 6}},
]
const MAX_COST := 9


static func tier(ilvl: int) -> Dictionary:
	var out: Dictionary = TIERS[0]
	for t in TIERS:
		if ilvl >= t.from:
			out = t
	return out


static func action(k: String) -> Dictionary:
	for a in ACTIONS:
		if a.k == k:
			return a
	return {}


## what action `act` costs on something of item level `ilvl`: {k: currency, n: how many}
static func cost(ilvl: int, act: String) -> Dictionary:
	var t := tier(ilvl)
	var c: Dictionary = t[act]
	return {"k": c.k, "n": mini(MAX_COST, c.n + (maxi(ilvl, 0) - t.from) / c.step)}


static func is_tablet(x: Dictionary) -> bool:
	return x.has("shape")


## "" when the line `line` of `x` (an item or a tablet) can be worked with `act`, else why not
static func can(x: Dictionary, line: String, act: String) -> String:
	if not is_tablet(x) and int(x.rarity) not in [1, 2]:
		return "マジック・レアアイテムにのみ使えます"
	if is_tablet(x) and Tablets.is_unique(x):
		return "ユニークのルーンタブレットは加工できません"
	if not x.mods.has(line):
		return "その行はありません"
	if act == "swap" and _pool(x).is_empty():
		return "ほかに付けられる能力がありません"
	if action(act).is_empty():
		return "その操作はありません"
	return ""


## the lines `x` could take instead of one of its own
static func _pool(x: Dictionary) -> Array:
	if is_tablet(x):
		return Tablets.MODS.filter(func(m): return not x.mods.has(m.k)).map(func(m): return m.k)
	return Data.AFFIXES.filter(func(a): return x.slot in a.slots and not x.mods.has(a.k)).map(func(a): return a.k)


static func _roll(x: Dictionary, k: String) -> int:
	return Tablets.roll_value(x, k) if is_tablet(x) else Items.roll_value(x, Data.affix(k))


## work line `line` of `x` with `act`, spending the currency from `cur`; returns an error message, or "" on success
static func apply(x: Dictionary, line: String, act: String, cur: Dictionary) -> String:
	var err := can(x, line, act)
	if err != "":
		return err
	var c := cost(int(x.ilvl), act)
	if int(cur.get(c.k, 0)) < c.n:
		return "%sが足りません（%d 必要）" % [Data.currency(c.k).name, c.n]
	if act == "swap":
		# the new line takes the old one's place, so the order of the lines (and a magic item's name) holds
		var nk: String = _pool(x).pick_random()
		var mods := {}
		for k in x.mods:
			if k == line:
				mods[nk] = _roll(x, nk)
			else:
				mods[k] = x.mods[k]
		x.mods = mods
		if not is_tablet(x) and int(x.rarity) == 1:
			Items.name_item(x)
	else:
		x.mods[line] = _roll(x, line)
	cur[c.k] -= c.n
	return ""


static func cost_text(c: Dictionary) -> String:
	var cd := Data.currency(c.k)
	return "%s×%d" % [cd.icon, c.n]


## the line-crafting box shown under the inventory and the tablet board: a row per line of `target`
## with a button per action. `crafted` fires after a line changed (the currency is already spent)
class Box extends VBoxContainer:
	signal crafted
	var player: Player
	var target := {}
	var note := Label.new()

	func _ready() -> void:
		add_theme_constant_override("separation", 4)
		note.add_theme_font_size_override("font_size", 12)
		note.add_theme_color_override("font_color", Color("#ff8a70"))
		add_child(note)

	func show_for(p: Player, x: Dictionary) -> void:
		if not is_same(x, target):
			note.text = ""
		player = p
		target = x
		rebuild()

	func rebuild() -> void:
		# queue_free: the button that was just pressed is among them
		for c in get_children():
			if c != note:
				remove_child(c)
				c.queue_free()
		visible = not target.is_empty()
		if target.is_empty():
			return
		var t := LineCraft.tier(int(target.ilvl))
		var head := Label.new()
		head.text = "一行クラフト：%s（iLv%d・%s）" % [Tablets.name_of(target) if LineCraft.is_tablet(target) else target.name, target.ilvl, t.name]
		head.add_theme_font_size_override("font_size", 13)
		head.add_theme_color_override("font_color", Color("#ffd36a"))
		add_child(head)
		if target.mods.is_empty():
			var none := Label.new()
			none.text = "刻まれた行がありません"
			none.add_theme_font_size_override("font_size", 12)
			none.add_theme_color_override("font_color", Color("#998a70"))
			add_child(none)
		for k in target.mods:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			add_child(row)
			var l := Label.new()
			l.text = (Data.affix(k).fmt % target.mods[k]).replace("+-", "-")
			if ModRange.detail:   # Alt held: what this line can roll to
				l.text += ModRange.tag(ModRange.of(target, k))
			l.add_theme_font_size_override("font_size", 13)
			l.add_theme_color_override("font_color", Color("#8fd8ff") if LineCraft.is_tablet(target) else Color("#8fb4ff"))
			l.custom_minimum_size = Vector2(300 if ModRange.detail else 190, 0)
			l.clip_text = true
			row.add_child(l)
			for a in LineCraft.ACTIONS:
				var c := LineCraft.cost(int(target.ilvl), a.k)
				var cd := Data.currency(c.k)
				var b := Button.new()
				b.text = "%s %s" % [a.name, LineCraft.cost_text(c)]
				b.add_theme_font_size_override("font_size", 12)
				b.add_theme_color_override("font_color", cd.color)
				b.disabled = int(player.cur.get(c.k, 0)) < c.n or LineCraft.can(target, k, a.k) != ""
				b.tooltip_text = "%s\n%s ×%d（所持 %d）" % [a.desc, cd.name, c.n, player.cur.get(c.k, 0)]
				b.pressed.connect(craft.bind(k, a.k))
				row.add_child(b)
		move_child(note, -1)

	func craft(line: String, act: String) -> void:
		note.text = LineCraft.apply(target, line, act, player.cur)
		if note.text == "":
			crafted.emit()
		rebuild()
