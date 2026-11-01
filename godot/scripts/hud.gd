class_name Hud
extends CanvasLayer
## On-screen UI built in code: life/mana orbs, skill bar, XP, messages, boss bar,
## and an overlay that draws enemy health bars and damage numbers over the 3D view.

var main               # main.gd (untyped so its members resolve at runtime)
var boss: Enemy = null
var root := Control.new()
var overlay := Overlay.new()
var life_orb := Orb.new()
var mana_orb := Orb.new()
var slots: Array[SkillSlot] = []
var xp_bar := Bar.new()
var info := Label.new()
var potion := Label.new()
var messages := VBoxContainer.new()
var boss_box := VBoxContainer.new()
var boss_name := Label.new()
var boss_bar := Bar.new()
var death := ColorRect.new()
var hurt := ColorRect.new()
var inventory := InventoryUI.new()
var shop_ui := ShopUI.new()
var atlas_ui := AtlasUI.new()
var skill_ui := SkillUI.new()
var talent_ui := TalentUI.new()
var status_ui := StatusUI.new()
var filter_ui := FilterUI.new()
var passive_ui := PassiveUI.new()
var asc_ui := AscUI.new()
var pause_ui := PauseUI.new()
var talent_hint := Label.new()
var tip := PanelContainer.new()
var tip_box := VBoxContainer.new()


func _ready() -> void:
	var th := Theme.new()
	th.default_font = Data.ui_font
	th.default_font_size = 16
	root.theme = th
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	overlay.hud = self
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)

	hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt.color = Color(0.6, 0, 0, 0)
	hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hurt)

	info.position = Vector2(16, 10)
	_shadow(info)
	root.add_child(info)
	talent_hint.position = Vector2(16, 36)
	talent_hint.text = "タレントポイントがあります [T]"
	talent_hint.add_theme_color_override("font_color", Color("#ffe27a"))
	talent_hint.add_theme_font_size_override("font_size", 14)
	_shadow(talent_hint)
	root.add_child(talent_hint)

	messages.set_anchors_preset(Control.PRESET_CENTER_TOP)
	messages.position = Vector2(-400, 80)
	messages.size = Vector2(800, 0)
	messages.alignment = BoxContainer.ALIGNMENT_BEGIN
	messages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(messages)

	boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_box.position = Vector2(-260, 14)
	boss_box.size = Vector2(520, 40)
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_name.add_theme_color_override("font_color", Color("#ff7a5a"))
	_shadow(boss_name)
	boss_box.add_child(boss_name)
	boss_bar.custom_minimum_size = Vector2(520, 12)
	boss_bar.fill = Color("#d03a24")
	boss_box.add_child(boss_bar)
	boss_box.visible = false
	root.add_child(boss_box)

	# bottom bar: life orb, skills, mana orb
	var bottom := HBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.position.y = -14
	bottom.add_theme_constant_override("separation", 14)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(bottom)
	life_orb.fill = Color("#b81a1a")
	mana_orb.fill = Color("#1f44b8")
	bottom.add_child(life_orb)
	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_END
	center.add_theme_constant_override("separation", 6)
	bottom.add_child(center)
	potion.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	potion.add_theme_color_override("font_color", Color("#ff9a8a"))
	potion.add_theme_font_size_override("font_size", 14)
	_shadow(potion)
	center.add_child(potion)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	center.add_child(bar)
	for i in Data.SLOT_KEYS.size():
		var sl := SkillSlot.new()
		sl.index = i
		sl.hud = self
		bar.add_child(sl)
		slots.append(sl)
	xp_bar.custom_minimum_size = Vector2(0, 7)
	xp_bar.fill = Color("#e0b040")
	center.add_child(xp_bar)
	bottom.add_child(mana_orb)

	inventory.hud = self
	root.add_child(inventory)
	shop_ui.hud = self
	root.add_child(shop_ui)
	atlas_ui.hud = self
	root.add_child(atlas_ui)
	skill_ui.hud = self
	root.add_child(skill_ui)
	for pnl in [talent_ui, asc_ui, status_ui, filter_ui, passive_ui, pause_ui]:
		pnl.hud = self
		root.add_child(pnl)
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.03, 0.024, 0.016, 0.97)
	tsb.border_color = Color("#7a6040")
	tsb.set_border_width_all(1)
	tsb.set_content_margin_all(10)
	tip.add_theme_stylebox_override("panel", tsb)
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.visible = false
	tip.add_child(tip_box)
	root.add_child(tip)

	death.set_anchors_preset(Control.PRESET_FULL_RECT)
	death.color = Color(0.05, 0.01, 0.01, 0.82)
	death.visible = false
	root.add_child(death)
	var dbox := VBoxContainer.new()
	dbox.set_anchors_preset(Control.PRESET_CENTER)
	dbox.alignment = BoxContainer.ALIGNMENT_CENTER
	dbox.add_theme_constant_override("separation", 18)
	death.add_child(dbox)
	var dl := Label.new()
	dl.text = "力尽きた…"
	dl.add_theme_font_size_override("font_size", 56)
	dl.add_theme_color_override("font_color", Color("#c03030"))
	dbox.add_child(dl)
	var retry := Button.new()
	retry.text = "もう一度挑戦する"
	retry.custom_minimum_size = Vector2(300, 48)
	retry.pressed.connect(func():
		death.visible = false
		main.retry_floor())
	dbox.add_child(retry)
	var home := Button.new()
	home.text = "隠れ家に戻る"
	home.custom_minimum_size = Vector2(300, 48)
	home.pressed.connect(func():
		death.visible = false
		main.player.xp = int(main.player.xp * 0.7)
		main.enter_hideout())
	dbox.add_child(home)


func _shadow(l: Label) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)


static func panel_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.063, 0.047, 0.035, 0.97)
	sb.border_color = Color("#7a6040")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(16)
	return sb


func panels() -> Array:
	return [inventory, shop_ui, atlas_ui, skill_ui, talent_ui, asc_ui, status_ui, filter_ui, passive_ui, pause_ui]


func any_open() -> bool:
	return panels().any(func(pnl): return pnl.visible)


func blocking() -> bool:
	return death.visible or any_open()


func close_panels() -> void:
	for pnl in panels():
		if pnl.visible:
			pnl.open_close()


## open one panel (closing the others, except the atlas it can sit on top of), or close it
func toggle(pnl: Control) -> void:
	if death.visible:
		return
	if pnl.visible:
		pnl.open_close()
		return
	for o in panels():
		if o != pnl and o != atlas_ui and o.visible:
			o.open_close()
	pnl.open_close()


func toggle_inventory() -> void:
	inventory.open_close()


func refresh_inventory() -> void:
	inventory.refresh()
	shop_ui.refresh()


## lines: [text, color, size]
func show_tip(lines: Array) -> void:
	for c in tip_box.get_children():
		c.free()
	for l in lines:
		var lab := Label.new()
		lab.text = l[0]
		lab.add_theme_color_override("font_color", l[1])
		lab.add_theme_font_size_override("font_size", l[2])
		tip_box.add_child(lab)
	tip.reset_size()
	tip.visible = true
	_place_tip()


func hide_tip() -> void:
	tip.visible = false


func _place_tip() -> void:
	var m := root.get_global_mouse_position() + Vector2(18, 18)
	var vp := root.get_viewport_rect().size
	if m.x + tip.size.x > vp.x - 8:
		m.x -= tip.size.x + 36
	m.y = minf(m.y, vp.y - tip.size.y - 8)
	tip.position = m


func refresh() -> void:
	var p: Player = main.player
	life_orb.value = p.life / p.s.max_life
	life_orb.text = "%d / %d" % [ceili(p.life), p.s.max_life]
	mana_orb.value = p.mana / p.s.max_mana
	mana_orb.text = "%d / %d" % [floori(p.mana), p.s.max_mana]
	xp_bar.value = float(p.xp) / Data.xp_need(p.level)
	var where: String = main.area.name if main.in_hideout() else "%s エリアLv %d" % [main.area.name, main.floor_level]
	info.text = "%s　Lv %d　◆ %d" % [where, p.level, p.cur.ember]
	if tip.visible:
		_place_tip()
	potion.text = "回復薬 %d/%d  [F]" % [p.potions, p.max_potions()]
	var hints := []
	if p.talent_pts > 0:
		hints.append("タレントポイントがあります [T]")
	if p.asc_free() > 0 or (p.asc == "" and p.level >= 2):
		hints.append("アセンダンシーポイントがあります [U]" if p.asc != "" else "アセンダンシーを選べます [U]")
	talent_hint.text = "\n".join(PackedStringArray(hints))
	talent_hint.visible = not hints.is_empty()
	if boss:
		boss_bar.value = maxf(0.0, boss.life / boss.max_life)
	for sl in slots:
		sl.queue_redraw()
	life_orb.queue_redraw()
	mana_orb.queue_redraw()
	xp_bar.queue_redraw()
	boss_bar.queue_redraw()
	overlay.queue_redraw()
	hurt.color.a = maxf(0.0, hurt.color.a - get_process_delta_time() * 1.5)
	if p.life / p.s.max_life < 0.3:
		hurt.color.a = maxf(hurt.color.a, 0.12 + 0.08 * sin(Time.get_ticks_msec() / 160.0))


func flash() -> void:
	hurt.color.a = 0.3


func message(text: String, color := Color.WHITE) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	_shadow(l)
	messages.add_child(l)
	while messages.get_child_count() > 5:
		messages.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func set_boss(e: Enemy) -> void:
	boss = e
	boss_box.visible = e != null
	if e:
		boss_name.text = e.display_name


func show_death() -> void:
	death.visible = true


# ---------- widgets ----------
class Orb extends Control:
	var value := 1.0
	var fill := Color.RED
	var text := ""

	func _init() -> void:
		custom_minimum_size = Vector2(118, 118)

	func _draw() -> void:
		var c := size / 2.0
		var rad := size.x / 2.0 - 3.0
		draw_circle(c, rad + 3.0, Color("#6a5434"))
		draw_circle(c, rad, Color("#0c0808"))
		# liquid: the part of the circle below the fill line
		var top := c.y + rad - value * rad * 2.0
		var pts := PackedVector2Array()
		for i in 49:
			var a := float(i) / 48.0 * TAU
			var p := c + Vector2(cos(a), sin(a)) * rad
			p.y = maxf(p.y, top)
			pts.append(p)
		if value > 0.01:
			draw_colored_polygon(pts, fill)
			draw_circle(c + Vector2(-rad * 0.3, -rad * 0.35), rad * 0.35, Color(1, 1, 1, 0.08))
		draw_string_outline(Data.ui_font, Vector2(0, c.y + 6), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, 4, Color.BLACK)
		draw_string(Data.ui_font, Vector2(0, c.y + 6), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color.WHITE)


class Bar extends Control:
	var value := 0.0
	var fill := Color.ORANGE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#1a1610"))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(value, 0.0, 1.0), size.y)), fill)
		draw_rect(Rect2(Vector2.ZERO, size), Color("#4a3a26"), false, 1.0)


class SkillSlot extends Control:
	var index := 0
	var hud: Hud

	func _init() -> void:
		custom_minimum_size = Vector2(58, 58)

	func _ready() -> void:
		mouse_entered.connect(func(): hud.show_tip(hud.skill_ui.skill_tip(hud.main.player.slots[index], index)))
		mouse_exited.connect(func(): hud.hide_tip())

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			hud.hide_tip()
			hud.skill_ui.open_slot(index)
			accept_event()

	func _draw() -> void:
		var p: Player = hud.main.player
		var id: String = p.slots[index]
		var sk: Dictionary = Data.SKILLS[id]
		var cost: int = hud.main.slot_cost(index)
		var col: Color = sk.color
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, Color("#0c0a08"))
		draw_circle(size / 2.0, size.x * 0.42, col.darkened(0.6))
		var font_col := col if p.mana >= cost else col.darkened(0.6)
		draw_string(Data.ui_font, Vector2(0, size.y * 0.66), sk.icon, HORIZONTAL_ALIGNMENT_CENTER, size.x, 28, font_col)
		var left: float = p.cds.get(id, 0.0)
		if left > 0.0:
			var k: float = clampf(left / maxf(sk.cd, 1.5), 0.0, 1.0)
			var pts := PackedVector2Array([size / 2.0])
			for i in 33:
				var a := -PI / 2.0 + k * TAU * float(i) / 32.0
				var q := size / 2.0 + Vector2(cos(a), sin(a)) * size.x
				pts.append(q.clamp(Vector2.ZERO, size))   # keep the pie inside the square slot
			draw_colored_polygon(pts, Color(0, 0, 0, 0.7))
		draw_rect(rect, Color("#6a5a44"), false, 1.5)
		var key: String = Data.SLOT_KEYS[index].short
		draw_string_outline(Data.ui_font, Vector2(3, size.y - 4), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
		draw_string(Data.ui_font, Vector2(3, size.y - 4), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#dddddd"))
		if cost > 0:
			draw_string(Data.ui_font, Vector2(0, 13), str(cost), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 3, 11, Color("#8fb4ff"))
		# one pip per support gem that applies to this slot
		var ids: Array = hud.main.slot_sup(index).ids
		for j in ids.size():
			draw_rect(Rect2(3 + j * 8, 3, 6, 6), Data.support(ids[j]).color)


## draws health bars, elite names and floating numbers by projecting 3D positions
class Overlay extends Control:
	var hud: Hud

	func _draw() -> void:
		var m = hud.main
		var cam: Camera3D = m.cam
		for e in m.enemies:
			if e.dead or (e.life >= e.max_life and e.elite.is_empty()):
				continue
			var top := Vector3(e.pos.x, float(e.t.h) * e.model.scale.y + 0.5, e.pos.y)
			if cam.is_position_behind(top):
				continue
			var s := cam.unproject_position(top)
			var w := maxf(34.0, e.r * 60.0)
			draw_rect(Rect2(s.x - w / 2 - 1, s.y - 1, w + 2, 7), Color(0, 0, 0, 0.75))
			draw_rect(Rect2(s.x - w / 2, s.y, w * maxf(0.0, e.life / e.max_life), 5), Color("#4f8cff") if not e.elite.is_empty() else Color("#c42a2a"))
			if not e.elite.is_empty():
				draw_string_outline(Data.ui_font, Vector2(s.x - 150, s.y - 6), e.display_name, HORIZONTAL_ALIGNMENT_CENTER, 300, 13, 3, Color.BLACK)
				draw_string(Data.ui_font, Vector2(s.x - 150, s.y - 6), e.display_name, HORIZONTAL_ALIGNMENT_CENTER, 300, 13, Color("#8fb4ff"))
		for g in m.ground:
			var d: float = g.pos.distance_to(m.player.pos)
			if d > 25.0 or (g.item.rarity == 0 and d > 10.0):
				continue
			var s3 := Vector3(g.pos.x, 0.9, g.pos.y)
			if cam.is_position_behind(s3):
				continue
			var sp := cam.unproject_position(s3)
			var label: String = g.item.name
			var w := Data.ui_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 12
			draw_rect(Rect2(sp.x - w / 2, sp.y - 18, w, 19), Color(0, 0, 0, 0.75))
			draw_string(Data.ui_font, Vector2(sp.x - w / 2, sp.y - 4), label, HORIZONTAL_ALIGNMENT_CENTER, w, 13, Data.RARITY[g.item.rarity].color)
		for dr in m.drops:
			if dr.k == "ember" or dr.pos.distance_to(m.player.pos) > 25.0:
				continue
			var sp := cam.unproject_position(Vector3(dr.pos.x, 0.8, dr.pos.y))
			var c := {"icon": "◇", "name": "サポートジェム：" + Data.support(dr.gem).name, "color": Data.GEM_COLOR} if dr.k == "gem" else Data.currency(dr.k)
			var label: String = "%s %s" % [c.icon, c.name]
			var w := Data.ui_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 12
			draw_rect(Rect2(sp.x - w / 2, sp.y - 18, w, 19), Color(0, 0, 0, 0.75))
			draw_string(Data.ui_font, Vector2(sp.x - w / 2, sp.y - 4), label, HORIZONTAL_ALIGNMENT_CENTER, w, 13, c.color)
		for o in m.interacts:
			var sp := cam.unproject_position(Vector3(o.pos.x, 3.4, o.pos.y))
			var label: String = "%s  [B]" % o.name
			draw_string_outline(Data.ui_font, Vector2(sp.x - 120, sp.y), label, HORIZONTAL_ALIGNMENT_CENTER, 240, 16, 4, Color.BLACK)
			draw_string(Data.ui_font, Vector2(sp.x - 120, sp.y), label, HORIZONTAL_ALIGNMENT_CENTER, 240, 16, Color("#ffd890"))
		for tx in m.texts:
			var p3: Vector3 = tx.pos + Vector3(0, tx.z, 0)
			if cam.is_position_behind(p3):
				continue
			var s := cam.unproject_position(p3)
			var a := clampf((0.9 - tx.t) * 3.0, 0.0, 1.0)
			var col: Color = tx.color
			draw_string_outline(Data.ui_font, Vector2(s.x - 100, s.y), tx.str, HORIZONTAL_ALIGNMENT_CENTER, 200, tx.size, 4, Color(0, 0, 0, a))
			draw_string(Data.ui_font, Vector2(s.x - 100, s.y), tx.str, HORIZONTAL_ALIGNMENT_CENTER, 200, tx.size, Color(col, a))
