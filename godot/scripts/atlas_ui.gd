class_name AtlasUI
extends Control
## Full-screen expedition atlas, opened from the device in the hideout: the fifty maps, a row per element.
## Click a map to see its route and the map items owned for it, pick a tier, then set out from the side panel.

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
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	detail.add_theme_constant_override("separation", 8)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(detail)


func open_close() -> void:
	visible = not visible
	hud.hide_tip()
	if visible:
		refresh()


func _process(_delta: float) -> void:
	if visible:
		board.queue_redraw()


func select(id: String) -> void:
	var at: Atlas = hud.main.atlas
	at.sel = id
	if not at.owns(id, at.sel_tier):   # the tier picked follows the map items of the new map
		at.sel_tier = maxi(1, at.lowest_tier(id))
	refresh()


func pick_tier(t: int) -> void:
	hud.main.atlas.sel_tier = t
	refresh()


## enter the selected map with the selected tier's map item
func set_out() -> bool:
	var at: Atlas = hud.main.atlas
	return hud.main.enter_map(at.sel, at.sel_tier if at.owns(at.sel, at.sel_tier) else 0)


static func buy_price() -> int:
	return roundi(Maps.value(Maps.BUY_TIER) * Data.SHOP_PRICE * Items.discount)


## buy a tier 1 map item of the selected map from the device; returns why not, or ""
func buy() -> String:
	var at: Atlas = hud.main.atlas
	var p: Player = hud.main.player
	var price := buy_price()
	if p.cur.ember < price:
		hud.message("灰燼の欠片が足りない（%d 必要）" % price, Color("#ff8080"))
		return "ember"
	p.cur.ember -= price
	Maps.add(at.maps, Maps.key(at.sel, Maps.BUY_TIER))
	at.sel_tier = Maps.BUY_TIER
	refresh()
	return ""


func refresh() -> void:
	var m = hud.main
	var at: Atlas = m.atlas
	var p: Player = m.player
	info.text = "Lv %d　◆ %d　✧ %d　%s 地図 %d　踏破 %d/%d　最高 T%d    " % [p.level, p.cur.ember, p.cur.compass, Maps.ICON, Maps.count(at.maps),
		at.cleared.size(), Data.ATLAS_NODES.size(), at.best]
	var pts := at.points_free()
	passive_btn.text = "  遠征パッシブ [%s]%s  " % [Keybinds.text("passives"), "（%d）" % pts if pts > 0 else ""]
	BasePanel.clear(detail)
	var n := Data.atlas_node(at.sel)
	if n.is_empty():
		n = Data.ATLAS_NODES[0]
	var el := Maps.element(n)
	var tiers := Maps.tiers_of(at.maps, n.id)
	var owned := at.owns(n.id, at.sel_tier)
	var mods: Array = at.item_mods(n.id, at.sel_tier) if owned else []
	var fx := Charms.apply(at.map_effects(mods), p.charm_slots)
	_line(n.name, el.color, 24)
	_line("%s属性　・　%s　・　%s" % [el.name, n.shape, "踏破済み" if at.is_cleared(n.id) else "未踏"], Color("#a89878"), 14)
	_wrap(_line(n.desc, Color("#d8c8a8"), 14))
	var shape := Route.new()
	shape.def = n
	shape.custom_minimum_size = Vector2(320, 150)
	detail.add_child(shape)
	_line("地形：%s　ボス：%s" % [Data.THEMES[n.elem].name, Data.ENEMY_TYPES[Data.BOSS_ROTATION[n.elem].type].name], Color("#c8b898"), 14)
	_line("%s 所持している地図（Tier で難度が決まる）" % Maps.ICON, Maps.COLOR, 16)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	row.custom_minimum_size = Vector2(320, 0)
	detail.add_child(row)
	for t in tiers:
		var b := Button.new()
		b.text = "T%d ×%d" % [t, at.maps[Maps.key(n.id, t)]]
		b.toggle_mode = true
		b.button_pressed = owned and t == at.sel_tier
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(pick_tier.bind(t))
		row.add_child(b)
	if tiers.is_empty():
		_line("この地図を持っていない（マップの敵とボスが落とす）", Color("#776a58"), 12)
	if owned:
		_line("Tier %d　・　エリアレベル %d" % [at.sel_tier, Maps.level_of(at.sel_tier)], Color("#f0d8a0"), 15)
		_line("マップ効果", Color("#f0d8a0"), 16)
		if mods.is_empty():
			_line("なし", Color("#776a58"), 14)
		for k in mods:
			_line("◆ " + Data.map_mod(k).name, Color("#ff9a7a"), 14)
		if fx.rarity > 0.0:
			_line("アイテムレア度 +%d%%　アイテム数量 +%d%%" % [roundi(fx.rarity * 100), roundi((fx.quantity - 1.0) * 100)], Color("#8fd18f"), 13)
	_charms(p)
	var go := Button.new()
	go.text = ("出撃する（T%d の地図を使う）" % at.sel_tier) if owned else "この地図を持っていない"
	go.disabled = not owned
	go.custom_minimum_size = Vector2(0, 44)
	go.pressed.connect(set_out)
	detail.add_child(go)
	if owned and Maps.mod_count(at.sel_tier).y > 0:
		var rr := Button.new()
		rr.text = "マップ効果を再抽選（✧ 羅針の欠片 1／所持 %d）" % p.cur.compass
		rr.add_theme_font_size_override("font_size", 13)
		rr.disabled = p.cur.compass < 1
		rr.pressed.connect(func():
			if p.cur.compass < 1:
				return
			p.cur.compass -= 1
			at.mods[Maps.key(n.id, at.sel_tier)] = at.roll_mods(at.sel_tier)
			refresh())
		detail.add_child(rr)
	var bb := Button.new()
	bb.text = "T%d の地図を買う（◆ %d）" % [Maps.BUY_TIER, buy_price()]
	bb.add_theme_font_size_override("font_size", 13)
	bb.disabled = p.cur.ember < buy_price()
	bb.pressed.connect(buy)
	detail.add_child(bb)


## the ember-shell slots: click a set shell to take it out, an owned one to set it; they burn on setting out
func _charms(p: Player) -> void:
	_line("%s コンパス %d / %d（出撃すると燃え尽きる）" % [Charms.ICON, p.charm_slots.size(), Charms.SLOTS], Charms.COLOR, 16)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	detail.add_child(row)
	for i in Charms.SLOTS:
		var id: String = p.charm_slots[i] if i < p.charm_slots.size() else ""
		var sl := Charms.Slot.new(id, 0, hud)
		sl.extra = [["クリックで外す", Color("#7a7266"), 12]]
		sl.clicked.connect(unslot.bind(i))
		row.add_child(sl)
	for id in p.charm_slots:
		_wrap(_line("%s %s" % [Charms.ICON, Charms.effect_text(id)], Charms.color_of(id), 13))
	var owned := HFlowContainer.new()
	detail.add_child(owned)
	owned.add_theme_constant_override("h_separation", 4)
	owned.add_theme_constant_override("v_separation", 4)
	owned.custom_minimum_size = Vector2(320, 0)
	for id in Charms.all_ids():
		var left := int(p.charms.get(id, 0)) - p.charm_slots.count(id)
		if left > 0:
			var sl := Charms.Slot.new(id, left, hud)
			sl.custom_minimum_size = Vector2(40, 40)
			sl.extra = [["クリックではめる", Color("#7a7266"), 12]]
			sl.clicked.connect(slot.bind(id))
			owned.add_child(sl)
	if owned.get_child_count() == 0:
		_line("コンパスを持っていない（マップの敵が落とす）", Color("#776a58"), 12)


## set shell `id` into the next run; returns why not, or ""
func slot(id: String) -> String:
	var p: Player = hud.main.player
	var err := Charms.can_slot(p.charm_slots, p.charms, id)
	if err != "":
		hud.message(err, Color("#ff8080"))
		return err
	p.charm_slots.append(id)
	hud.hide_tip()
	refresh()
	return ""


func unslot(i: int) -> void:
	var p: Player = hud.main.player
	if i < p.charm_slots.size():
		p.charm_slots.remove_at(i)
		hud.hide_tip()
		refresh()


func _line(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	detail.add_child(l)
	return l


func _wrap(l: Label) -> void:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(320, 0)


## a map's route drawn small: corridors as lines, rooms as dots, the entrance green and the boss room red
class Route extends Control:
	var def: Dictionary

	func _draw() -> void:
		draw_route(self, def, Rect2(Vector2.ZERO, size))

	static func draw_route(c: CanvasItem, m: Dictionary, r: Rect2, faded := false) -> void:
		var col: Color = Maps.element(m).color
		if faded:
			col = col.darkened(0.55)
		var s := minf(r.size.x, r.size.y) / (Maps.GRID + 2.0)
		var o := r.position + (r.size - Vector2.ONE * s * Maps.GRID) / 2.0
		for ch in Maps.chains(m):
			for j in range(1, ch.size()):
				c.draw_line(o + Vector2(ch[j - 1]) * s, o + Vector2(ch[j]) * s, Color(col, 0.75), maxf(1.5, s * 0.35), true)
		var pts := Maps.points(m)
		for i in pts.size():
			var last := i == pts.size() - 1
			var dot := Color("#7fe07f") if i == 0 else (Color("#ff5a3a") if last else col.lightened(0.3))
			c.draw_circle(o + Vector2(pts[i]) * s, s * (0.9 if last else 0.55), dot.darkened(0.5) if faded else dot)


## the fifty maps: a row per element, each map's route drawn in its cell
class Board extends Control:
	const COLS := 10
	const LEFT := 64.0
	var ui: AtlasUI

	func cell(i: int) -> Rect2:
		var w := (size.x - LEFT - 12.0) / COLS
		var h := (size.y - 16.0) / Maps.ELEMENTS.size()
		var m: Dictionary = Data.ATLAS_NODES[i]
		return Rect2(LEFT + (i % COLS) * w + 3.0, 8.0 + m.elem * h + 3.0, w - 6.0, h - 6.0)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			for i in Data.ATLAS_NODES.size():
				if cell(i).has_point(e.position):
					ui.select(Data.ATLAS_NODES[i].id)
					accept_event()
					return

	func _draw() -> void:
		var at: Atlas = ui.hud.main.atlas
		var t := Time.get_ticks_msec() / 1000.0
		var font := Data.ui_font
		var h := (size.y - 16.0) / Maps.ELEMENTS.size()
		for k in Maps.ELEMENTS.size():
			var el: Dictionary = Maps.ELEMENTS[k]
			draw_rect(Rect2(4, 8.0 + k * h + 1.0, size.x - 8.0, h - 2.0), Color(el.color, 0.05))
			draw_string(font, Vector2(4, 8.0 + k * h + h / 2.0 + 6.0), el.name, HORIZONTAL_ALIGNMENT_CENTER, LEFT - 8.0, 16, el.color)
		for i in Data.ATLAS_NODES.size():
			var m: Dictionary = Data.ATLAS_NODES[i]
			var r := cell(i)
			var col: Color = Maps.element(m).color
			var tiers := Maps.tiers_of(at.maps, m.id)
			var have := not tiers.is_empty()
			draw_rect(r, Color("#1a120c") if have else Color("#0e0b08"))
			draw_rect(r, Color(col, 0.6 if have else 0.18), false, 1.5)
			if at.sel == m.id:
				draw_rect(r.grow(2.0), Color(1.0, 0.86, 0.55, 0.6 + sin(t * 4.0) * 0.3), false, 2.0)
			Route.draw_route(self, m, Rect2(r.position + Vector2(4, 4), Vector2(r.size.x - 8, r.size.y - 40)), not have and not at.is_cleared(m.id))
			draw_string_outline(font, Vector2(r.position.x, r.end.y - 22), m.name, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, 3, Color.BLACK)
			draw_string(font, Vector2(r.position.x, r.end.y - 22), m.name, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, Color("#f0dcb4") if have else Color("#7a6c58"))
			var n := 0
			for x in tiers:
				n += int(at.maps[Maps.key(m.id, x)])
			var sub: String = ("%s ×%d（T%d〜）" % [Maps.ICON, n, tiers[0]]) if have else m.shape
			draw_string(font, Vector2(r.position.x, r.end.y - 7), sub, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 11, Maps.COLOR if have else Color("#5a4e40"))
			if at.is_cleared(m.id):
				draw_string(font, r.position + Vector2(r.size.x - 18, 16), "✓", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#ffd36a"))
