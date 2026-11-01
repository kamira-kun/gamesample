class_name AscUI
extends BasePanel
## Ascendancy (U): choose a lineage, spend the points every second level gives on its minor nodes,
## and pick one core talent in each tier those points open. Core picks can be swapped at no cost.

var points := Label.new()
var reset := Button.new()
var content := VBoxContainer.new()
var confirm_reset := false


func _title() -> String:
	return "アセンダンシー"


func _hint() -> String:
	return "2レベルごとに1ポイント。基礎ノードに振ったポイントでコアタレントが解放される"


func _build() -> void:
	var top := HBoxContainer.new()
	body.add_child(top)
	points.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	points.add_theme_font_size_override("font_size", 15)
	points.add_theme_color_override("font_color", Color("#ffe27a"))
	top.add_child(points)
	reset.add_theme_font_size_override("font_size", 13)
	reset.pressed.connect(_reset)
	top.add_child(reset)
	content.add_theme_constant_override("separation", 10)
	body.add_child(content)


func refresh() -> void:
	if not visible:
		return
	var p: Player = hud.main.player
	points.text = "残りポイント %d　／　獲得合計 %d" % [p.asc_free(), Data.asc_points(p.level)]
	var rp := p.asc_reset_price()
	reset.visible = p.asc != ""
	reset.text = ("本当に選び直す？（◆ %d）" if confirm_reset else "系譜を選び直す（◆ %d）") % rp
	reset.disabled = p.cur.ember < rp
	clear(content)
	if p.asc == "":
		_build_pick()
	else:
		_build_tree(p, Data.ascendancy(p.asc))


## no lineage yet: one card per ascendancy
func _build_pick() -> void:
	content.add_child(sub("系譜を選ぶ（最初の選択は無料）", 15, Color("#f0dcb4")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	content.add_child(row)
	for a in Data.ASCENDANCIES:
		var lines: Array = ["%s %s" % [a.icon, a.name], a.desc, ""]
		for tier in a.cores:
			lines.append("◇ " + " ／ ".join(PackedStringArray(tier.map(func(c): return c.name))))
		var card := _card("\n".join(PackedStringArray(lines)), a.color, true, false)
		card.custom_minimum_size = Vector2(230, 190)
		card.pressed.connect(_choose.bind(a.k))
		row.add_child(card)


func _build_tree(p: Player, a: Dictionary) -> void:
	content.add_child(sub("%s %s" % [a.icon, a.name], 18, a.color))
	content.add_child(sub(a.desc, 12, Color("#a89878")))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	content.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.add_child(sub("基礎ノード（使用 %d）" % p.asc_spent(), 14, Color("#f0dcb4")))
	cols.add_child(left)
	for n in a.minors:
		var r := p.asc_rank(n.id)
		var text: String = "%s　%d / %d\n%s" % [n.name, r, n.max, _fmt(n, maxi(r, 1))]
		if r > 0 and r < n.max:
			text += "\n次：" + _fmt(n, r + 1)
		var card := _card(text, a.color, p.asc_free() > 0 and r < n.max, r > 0, r >= n.max)
		card.custom_minimum_size = Vector2(250, 64)
		card.pressed.connect(_rank_up.bind(n.id))
		left.add_child(card)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.add_child(sub("コアタレント（各段階から1つ・クリックで切り替え）", 14, Color("#f0dcb4")))
	cols.add_child(right)
	for i in a.cores.size():
		var req: int = Data.ASC_CORE_REQ[i]
		var open := p.asc_spent() >= req
		right.add_child(sub("第%d段階　（基礎ノードに %d ポイントで解放）" % [i + 1, req], 12, a.color if open else Color("#776a58")))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		right.add_child(row)
		for c in a.cores[i]:
			var picked: bool = p.asc_cores[i] == c.id
			var card := _card("%s%s\n%s" % ["◆ " if picked else "◇ ", c.name, c.desc], a.color, open, picked, picked)
			card.custom_minimum_size = Vector2(250, 76)
			card.pressed.connect(_pick_core.bind(i, c.id))
			row.add_child(card)


static func _fmt(n: Dictionary, r: int) -> String:
	var v: float = n.stats.values()[0] * r
	return n.fmt.replace("{v}", str(v) if v != roundf(v) else str(roundi(v)))


## a node card: bright when taken, outlined when it can be clicked, dimmed when it cannot
func _card(text: String, col: Color, usable: bool, taken: bool, full := false) -> Button:
	var card := SkillUI.card(text, col.darkened(0.75) if taken else Color("#120e0a"),
		col if taken else (Color("#5a4a34") if usable else Color("#2a2218")), col if usable or taken else Color("#5a4e40"), 2 if full else 1)
	card.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	if not usable and not taken:
		card.modulate = Color(1, 1, 1, 0.55)
	return card


func _choose(k: String) -> void:
	var p: Player = hud.main.player
	if p.asc != "":
		return
	p.asc = k
	p.asc_ranks = {}
	p.asc_cores = ["", "", ""]
	hud.message("系譜「%s」を継承した" % Data.ascendancy(k).name, Data.ascendancy(k).color)
	_changed()


func _rank_up(id: String) -> void:
	var p: Player = hud.main.player
	var n: Dictionary = Data.ascendancy(p.asc).minors.filter(func(x): return x.id == id)[0]
	if p.asc_free() <= 0 or p.asc_rank(id) >= n.max:
		return
	p.asc_ranks[id] = p.asc_rank(id) + 1
	_changed()


func _pick_core(tier: int, id: String) -> void:
	var p: Player = hud.main.player
	if p.asc_spent() < Data.ASC_CORE_REQ[tier] or p.asc_cores[tier] == id:
		return
	p.asc_cores[tier] = id
	_changed()


## back to choosing a lineage; costs ember for every point spent
func _reset() -> void:
	var p: Player = hud.main.player
	var rp := p.asc_reset_price()
	if p.asc == "" or p.cur.ember < rp:
		return
	if not confirm_reset:
		confirm_reset = true
		refresh()
		return
	p.cur.ember -= rp
	p.asc = ""
	p.asc_ranks = {}
	p.asc_cores = ["", "", ""]
	_changed()


func open_close() -> void:
	confirm_reset = false
	super()


func _changed() -> void:
	confirm_reset = false
	hud.main.player.recalc()
	hud.main.save_game()
	refresh()
	_center.call_deferred()
