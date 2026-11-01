class_name SkillUI
extends PanelContainer
## Skill panel (K): pick a skill bar slot, put any learned skill in it, and link support gems to it.

var hud: Hud
var sel := 0
var slot_row := HBoxContainer.new()
var skill_grid := GridContainer.new()
var gem_grid := GridContainer.new()
var gem_hint := Label.new()


func _ready() -> void:
	add_theme_stylebox_override("panel", Hud.panel_box())
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := Label.new()
	title.text = "スキルとサポートジェム"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#f0d8a0"))
	head.add_child(title)
	var hint := _sub("   スロットを選び、スキルやジェムをクリック。ソケットのジェムはクリックで外す")
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hint)
	var close := Button.new()
	close.text = "×"
	close.pressed.connect(open_close)
	head.add_child(close)

	slot_row.add_theme_constant_override("separation", 8)
	col.add_child(slot_row)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	col.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)
	left.add_child(_sub("スキル"))
	skill_grid.columns = 2
	skill_grid.add_theme_constant_override("h_separation", 6)
	skill_grid.add_theme_constant_override("v_separation", 6)
	left.add_child(skill_grid)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	right.add_child(_sub("サポートジェム"))
	gem_hint.add_theme_font_size_override("font_size", 12)
	gem_hint.add_theme_color_override("font_color", Data.GEM_COLOR)
	right.add_child(gem_hint)
	gem_grid.columns = 2
	gem_grid.add_theme_constant_override("h_separation", 6)
	gem_grid.add_theme_constant_override("v_separation", 6)
	right.add_child(gem_grid)


func _sub(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color("#b8a888"))
	return l


func open_close() -> void:
	visible = not visible
	hud.hide_tip()
	if visible:
		refresh()
		_center.call_deferred()


func open_slot(i: int) -> void:
	sel = i
	if not visible:
		open_close()
	else:
		refresh()


func _center() -> void:
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


static func _box(bg: Color, border: Color, width := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(6)
	return sb


## a flat button whose look is one stylebox for every state
static func card(text: String, bg: Color, border: Color, font: Color, width := 1) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 13)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := _box(bg.lightened(0.08) if st == "hover" else bg, border, width)
		if st == "focus":
			sb.draw_center = false
		b.add_theme_stylebox_override(st, sb)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		b.add_theme_color_override(st, font)
	return b


func _hover(c: Control, lines: Array) -> void:
	c.mouse_entered.connect(func(): hud.show_tip(lines))
	c.mouse_exited.connect(func(): hud.hide_tip())


func skill_tip(id: String, slot := -1) -> Array:
	var sk: Dictionary = Data.SKILLS[id]
	var lines := [[sk.name, sk.color, 17], [Data.tag_text(sk.tags), Color("#9a9080"), 12],
		["マナ %d" % sk.mana + ("　CD %s秒" % sk.cd if sk.cd > 0.0 else ""), Color("#9a9080"), 12], [sk.desc, Color("#dddddd"), 13]]
	if slot >= 0:
		var s: Dictionary = hud.main.slot_sup(slot)
		for gid in s.ids:
			var g := Data.support(gid)
			lines.append(["◆ %s：%s" % [g.name, g.desc], g.color, 12])
	return lines


static func gem_tip(g: Dictionary) -> Array:
	var target := "対象：" + Data.tag_text(g.tags)
	if g.has("not"):
		target += "（%sを除く）" % Data.tag_text(g.not)
	return [[g.name, g.color, 17], ["サポートジェム", Color("#9a9080"), 12], [g.desc, Color("#dddddd"), 13], [target, Color("#8fb4ff"), 12]]


func refresh() -> void:
	if not visible:
		return
	var p: Player = hud.main.player
	var sockets := Data.link_sockets(p.level)
	for c in slot_row.get_children():
		c.free()
	for c in skill_grid.get_children():
		c.free()
	for c in gem_grid.get_children():
		c.free()

	for i in Data.SLOT_KEYS.size():
		var id: String = p.slots[i]
		var sk: Dictionary = Data.SKILLS[id]
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 3)
		var b := card("%s\n%s %s" % [Data.SLOT_KEYS[i].label, sk.icon, sk.name], Color("#2a2014") if i == sel else Color("#120e0a"),
			Color("#ffd36a") if i == sel else Color("#4a3a26"), sk.color, 2 if i == sel else 1)
		b.custom_minimum_size = Vector2(132, 52)
		b.pressed.connect(func():
			sel = i
			refresh())
		_hover(b, skill_tip(id, i))
		card.add_child(b)
		var socks := HBoxContainer.new()
		socks.add_theme_constant_override("separation", 4)
		socks.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_child(socks)
		var links: Array = p.links[i]
		for k in Data.LINK_MAX:
			var gid: String = links[k] if k < links.size() else ""
			var g := Data.support(gid)
			var locked := k >= sockets
			var fits := not g.is_empty() and Data.support_fits(g, id)
			var bg: Color = g.color.darkened(0.2) if not g.is_empty() else Color("#0c0a08")
			var s := card("✕" if not g.is_empty() and not fits else "", bg, Color("#ff5050") if not g.is_empty() and not fits else Color("#5a4a34"), Color.WHITE)
			s.custom_minimum_size = Vector2(22, 22)
			s.alignment = HORIZONTAL_ALIGNMENT_CENTER
			if locked:
				s.modulate = Color(1, 1, 1, 0.3)
				_hover(s, [["Lv %d で開放" % [1, 5, 10][k], Color("#9a9080"), 13]])
			elif not g.is_empty():
				var tip := gem_tip(g)
				tip.append(["クリックで外す" + ("" if fits else "（このスキルには無効）"), Color("#ffd36a"), 12])
				_hover(s, tip)
				s.pressed.connect(func():
					links.erase(gid)
					_changed())
			socks.add_child(s)
		slot_row.add_child(card)

	for id in Data.SKILL_ORDER:
		var sk: Dictionary = Data.SKILLS[id]
		var locked: bool = p.level < sk.lvl
		var at := p.slots.find(id)
		var tag := "Lv %d で習得" % sk.lvl if locked else ("装備中：%s" % Data.SLOT_KEYS[at].label if at >= 0 else "")
		var b := card("%s %s　%s\nマナ %d%s　%s" % [sk.icon, sk.name, tag, sk.mana, "　CD %s秒" % sk.cd if sk.cd > 0.0 else "", Data.tag_text(sk.tags)],
			Color("#120e0a"), Color("#6a5a44") if at >= 0 else Color("#3a3024"), sk.color.darkened(0.55) if locked else sk.color)
		b.custom_minimum_size = Vector2(250, 48)
		_hover(b, skill_tip(id))
		if not locked:
			b.pressed.connect(_assign.bind(id))
		skill_grid.add_child(b)

	var sel_id: String = p.slots[sel]
	var sel_links: Array = p.links[sel]
	gem_hint.text = "「%s」に%d個までリンクできます（Lv5・Lv10でソケット追加）" % [Data.SKILLS[sel_id].name, sockets]
	for g in Data.SUPPORTS:
		var owned: bool = g.id in p.gems
		var fits := Data.support_fits(g, sel_id)
		var linked: bool = g.id in sel_links
		var tag := "未入手" if not owned else ("リンク中" if linked else ("" if fits else "対象外"))
		var font: Color = g.color if owned and fits else g.color.darkened(0.6)
		var b := card("◇ %s　%s" % [g.name, tag], Color("#1c2a1c") if linked else Color("#120e0a"), g.color if linked else Color("#3a3024"), font, 2 if linked else 1)
		b.custom_minimum_size = Vector2(200, 34)
		_hover(b, gem_tip(g))
		b.pressed.connect(_toggle_gem.bind(g.id))
		gem_grid.add_child(b)


## put a skill in the selected slot; a skill already on the bar swaps places (with its links)
func _assign(id: String) -> void:
	var p: Player = hud.main.player
	var at := p.slots.find(id)
	if at >= 0:
		var t: String = p.slots[sel]
		p.slots[sel] = p.slots[at]
		p.slots[at] = t
		var l: Array = p.links[sel]
		p.links[sel] = p.links[at]
		p.links[at] = l
	else:
		p.slots[sel] = id
	_changed()


func _toggle_gem(gid: String) -> void:
	var p: Player = hud.main.player
	var g := Data.support(gid)
	var sel_id: String = p.slots[sel]
	var links: Array = p.links[sel]
	if not gid in p.gems:
		return
	if gid in links:
		links.erase(gid)
	elif not Data.support_fits(g, sel_id):
		hud.message("%sは「%s」に使えない" % [g.name, Data.SKILLS[sel_id].name], Color("#ff8080"))
		return
	elif links.size() >= Data.link_sockets(p.level):
		hud.message("空きソケットがない", Color("#ff8080"))
		return
	else:
		links.append(gid)
	_changed()


func _changed() -> void:
	hud.hide_tip()
	hud.main.save_game()
	refresh()
