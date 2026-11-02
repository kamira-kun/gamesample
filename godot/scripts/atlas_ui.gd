class_name AtlasUI
extends Control
## Full-screen expedition atlas, opened from the device in the hideout.
## Click a node to see its details, then set out from the side panel.

var hud: Hud
var board := Board.new()
var info := Label.new()
var detail := VBoxContainer.new()
var passive_btn := Button.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var bg := ColorRect.new()
	bg.color = Color("#0a0705")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 0)
	add_child(col)
	var head := HBoxContainer.new()
	head.custom_minimum_size = Vector2(0, 48)
	col.add_child(head)
	var title := Label.new()
	title.text = "  遠征図"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#f0d8a0"))
	head.add_child(title)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info.add_theme_color_override("font_color", Color("#c8b898"))
	head.add_child(info)
	passive_btn.pressed.connect(func(): hud.toggle(hud.passive_ui))
	head.add_child(passive_btn)
	var close := Button.new()
	close.text = "  閉じる（Esc）  "
	close.pressed.connect(open_close)
	head.add_child(close)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	board.ui = self
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(board)
	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(360, 0)
	side.add_theme_stylebox_override("panel", Hud.panel_box())
	body.add_child(side)
	detail.add_theme_constant_override("separation", 8)
	side.add_child(detail)


func open_close() -> void:
	visible = not visible
	hud.hide_tip()
	if visible:
		refresh()


func _process(_delta: float) -> void:
	if visible:
		board.queue_redraw()


func select(id: String) -> void:
	hud.main.atlas.sel = id
	refresh()


func refresh() -> void:
	var m = hud.main
	var at: Atlas = m.atlas
	var p: Player = m.player
	info.text = "Lv %d　◆ %d　✧ %d　踏破 %d/%d    " % [p.level, p.cur.ember, p.cur.compass, at.cleared.size(), Data.ATLAS_NODES.size()]
	var pts := at.points_free()
	passive_btn.text = "  遠征パッシブ [%s]%s  " % [Keybinds.text("passives"), "（%d）" % pts if pts > 0 else ""]
	BasePanel.clear(detail)
	var n := Data.atlas_node(at.sel)
	if n.is_empty():
		n = Data.ATLAS_NODES[0]
	var unlocked := at.is_unlocked(n)
	var mods: Array = at.node_mods(n) if unlocked else []
	var fx := at.map_effects(mods)
	_line(n.name, Data.THEME_COLORS[3 if n.get("endless", false) else n.theme], 24)
	var status := "踏破済み" if at.is_cleared(n) else ("未踏" if unlocked else "未開放")
	_line("エリアレベル %d　・　%s" % [at.node_level(n), status], Color("#a89878"), 14)
	var desc := _line(n.desc, Color("#d8c8a8"), 14)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(320, 0)
	_line("地形：%s" % Data.THEMES[at.node_theme(n)].name, Color("#c8b898"), 14)
	_line("ボス：%s" % Data.ENEMY_TYPES[Data.BOSS_ROTATION[at.node_theme(n)].type].name, Color("#ff7a5a"), 14)
	_line("マップ効果", Color("#f0d8a0"), 16)
	if mods.is_empty():
		_line("なし", Color("#776a58"), 14)
	for k in mods:
		_line("◆ " + Data.map_mod(k).name, Color("#ff9a7a"), 14)
	if fx.rarity > 0.0:
		_line("アイテムレア度 +%d%%　アイテム数量 +%d%%" % [roundi(fx.rarity * 100), roundi((fx.quantity - 1.0) * 100)], Color("#8fd18f"), 13)
	var go := Button.new()
	go.text = "出撃する" if unlocked else "隣接する地点を踏破すると開放"
	go.disabled = not unlocked
	go.custom_minimum_size = Vector2(0, 44)
	go.pressed.connect(func(): m.enter_map(n.id))
	detail.add_child(go)
	if unlocked and at.node_level(n) >= 3:
		var rr := Button.new()
		rr.text = "マップ効果を再抽選（✧ 羅針の欠片 1／所持 %d）" % p.cur.compass
		rr.add_theme_font_size_override("font_size", 13)
		rr.disabled = p.cur.compass < 1
		rr.pressed.connect(func():
			if p.cur.compass < 1:
				return
			p.cur.compass -= 1
			at.mods[n.id] = at.roll_mods(n)
			refresh())
		detail.add_child(rr)


func _line(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	detail.add_child(l)
	return l


## the node graph, drawn by hand
class Board extends Control:
	var ui: AtlasUI

	func node_pos(n: Dictionary) -> Vector2:
		return Vector2(60 + n.x * (size.x - 120), 50 + n.y * (size.y - 110))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			for n in Data.ATLAS_NODES:
				if node_pos(n).distance_to(e.position) < 30.0:
					ui.select(n.id)
					accept_event()
					return

	func _draw() -> void:
		var at: Atlas = ui.hud.main.atlas
		var t := Time.get_ticks_msec() / 1000.0
		var font := Data.ui_font
		for n in Data.ATLAS_NODES:
			var col: Color = Data.THEME_COLORS[3 if n.get("endless", false) else n.theme]
			for i in 6:   # stacked translucent discs make a soft glow
				draw_circle(node_pos(n), 130.0 - i * 20.0, Color(col, 0.01))
		# links
		for n in Data.ATLAS_NODES:
			for id in n.links:
				var a := node_pos(n)
				var b := node_pos(Data.atlas_node(id))
				var open := at.is_cleared(n)
				var mid := (a + b) / 2.0 - Vector2(0, 20)
				var pts := PackedVector2Array()
				for i in 17:
					var k := i / 16.0
					pts.append(a.lerp(mid, k).lerp(mid.lerp(b, k), k))
				if open:
					draw_polyline(pts, Color(1.0, 0.78, 0.43, 0.7), 3.0, true)
				else:
					for i in range(0, 16, 2):
						draw_line(pts[i], pts[i + 1], Color(0.47, 0.39, 0.31, 0.35), 2.0, true)
		# nodes
		for n in Data.ATLAS_NODES:
			var q := node_pos(n)
			var unlocked := at.is_unlocked(n)
			var cleared := at.is_cleared(n)
			var col: Color = Data.THEME_COLORS[3 if n.get("endless", false) else n.theme]
			if unlocked:
				for i in 4:
					draw_circle(q, 44.0 - i * 9.0, Color(col, 0.08 + i * 0.05))
			if at.sel == n.id:
				draw_arc(q, 27.0 + sin(t * 4.0) * 2.0, 0, TAU, 48, Color(1.0, 0.86, 0.55, 0.6 + sin(t * 4.0) * 0.3), 2.0, true)
			var edge := col if unlocked else Color("#3a3024")
			if n.get("endless", false):
				var star := PackedVector2Array()
				for i in 8:
					var a := i / 8.0 * TAU + t * 0.3
					star.append(q + Vector2(cos(a), sin(a)) * (15.0 if i % 2 else 22.0))
				draw_colored_polygon(star, Color("#1a120c") if unlocked else Color("#0c0a08"))
				star.append(star[0])
				draw_polyline(star, edge, 3.0, true)
			else:
				draw_circle(q, 18.0, Color("#1a120c") if unlocked else Color("#0c0a08"))
				draw_arc(q, 18.0, 0, TAU, 32, edge, 3.0, true)
			var mark := "✓" if cleared else (str(at.node_level(n)) if unlocked else "—")
			draw_string(font, q + Vector2(-30, 6), mark, HORIZONTAL_ALIGNMENT_CENTER, 60, 15, col if unlocked else Color("#4a4032"))
			draw_string_outline(font, q + Vector2(-90, 42), n.name, HORIZONTAL_ALIGNMENT_CENTER, 180, 14, 3, Color.BLACK)
			draw_string(font, q + Vector2(-90, 42), n.name, HORIZONTAL_ALIGNMENT_CENTER, 180, 14, Color("#f0dcb4") if unlocked else Color("#5a4e40"))
			draw_string(font, q + Vector2(-90, 58), "Lv %d" % at.node_level(n), HORIZONTAL_ALIGNMENT_CENTER, 180, 11, Color("#a89878") if unlocked else Color("#4a4032"))
