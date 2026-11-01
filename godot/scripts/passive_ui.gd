class_name PassiveUI
extends BasePanel
## Atlas passives (P): points from first map clears and Ember Abyss clears, spent down three branches.

var points := Label.new()
var reset := Button.new()
var tree := HBoxContainer.new()
var confirm_reset := false


func _title() -> String:
	return "遠征パッシブ"


func _hint() -> String:
	return "初踏破と残り火の深淵の踏破ごとに1ポイント"


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
	tree.add_theme_constant_override("separation", 16)
	body.add_child(tree)


func refresh() -> void:
	if not visible:
		return
	var m = hud.main
	var at: Atlas = m.atlas
	var p: Player = m.player
	var rp := at.reset_price()
	points.text = "残りポイント %d　／　獲得合計 %d" % [at.points_free(), at.points_total()]
	reset.text = "本当に振り直す？（◆ %d）" % rp if confirm_reset else "振り直す（◆ %d）" % rp
	reset.disabled = at.points_spent() == 0 or p.cur.ember < rp
	clear(tree)
	for b in Data.ATLAS_PASSIVES:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		col.add_child(sub(b.branch, 17, b.color))
		for n in b.nodes:
			var r := at.rank(n.id)
			var unlocked := at.passive_unlocked(n.id)
			var now: String = n.fmt.replace("{v}", str(roundi(maxi(r, 1) * n.per)))
			var text: String = "%s　%d / %d\n%s" % [n.name, r, n.max, now]
			if r > 0 and r < n.max:
				text += "\n次：" + n.fmt.replace("{v}", str(roundi((r + 1) * n.per)))
			var bc: Color = b.color
			var card := SkillUI.card(text, bc.darkened(0.75) if r > 0 else Color("#120e0a"), bc if r > 0 else (Color("#5a4a34") if unlocked else Color("#2a2218")),
				bc if unlocked else Color("#5a4e40"), 2 if r >= n.max else 1)
			card.custom_minimum_size = Vector2(250, 64)
			if not unlocked:
				card.modulate = Color(1, 1, 1, 0.55)
			card.pressed.connect(_rank_up.bind(n.id))
			col.add_child(card)
		tree.add_child(col)


func _rank_up(id: String) -> void:
	var at: Atlas = hud.main.atlas
	var n := Data.passive(id)
	if not at.passive_unlocked(id) or at.rank(id) >= n.max or at.points_free() <= 0:
		return
	at.passives[id] = at.rank(id) + 1
	_changed()


func _reset() -> void:
	var m = hud.main
	var at: Atlas = m.atlas
	var rp := at.reset_price()
	if at.points_spent() == 0 or m.player.cur.ember < rp:
		return
	if not confirm_reset:
		confirm_reset = true
		refresh()
		return
	m.player.cur.ember -= rp
	at.passives = {}
	_changed()


func open_close() -> void:
	confirm_reset = false
	super()


func _changed() -> void:
	confirm_reset = false
	hud.main.passives_changed()
	hud.main.save_game()
	refresh()
	if hud.atlas_ui.visible:
		hud.atlas_ui.refresh()
