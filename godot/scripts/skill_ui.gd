class_name SkillUI
extends PanelContainer
## Skill panel (K): pick a skill bar slot, put any owned skill gem the character is high enough level for in it,
## and link support gems to it.

var hud: Hud
var sel := 0
var slot_row := HBoxContainer.new()
var skill_grid := GridContainer.new()
var gem_grid := GridContainer.new()
var gem_hint := Label.new()
var tag_row := HBoxContainer.new()
var tag_sel := ""                # skill list filter: a tag, or "" for every skill
var fit_only := CheckBox.new()   # gem list: only gems the selected skill can use
const FILTER_TAGS := ["", "attack", "spell", "projectile", "aoe", "fire", "cold", "lightning", "chaos", "minion", "buff", "curse", "movement"]


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
	tag_row.add_theme_constant_override("separation", 3)
	left.add_child(tag_row)
	skill_grid.columns = 2
	skill_grid.add_theme_constant_override("h_separation", 6)
	skill_grid.add_theme_constant_override("v_separation", 6)
	left.add_child(_scroll(skill_grid, Vector2(520, 400)))
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	right.add_child(_sub("サポートジェム"))
	gem_hint.add_theme_font_size_override("font_size", 12)
	gem_hint.add_theme_color_override("font_color", Data.GEM_COLOR)
	right.add_child(gem_hint)
	fit_only.text = "このスキルに使えるものだけ表示"
	fit_only.button_pressed = true
	fit_only.add_theme_font_size_override("font_size", 12)
	fit_only.toggled.connect(func(_on): refresh())
	right.add_child(fit_only)
	gem_grid.columns = 2
	gem_grid.add_theme_constant_override("h_separation", 6)
	gem_grid.add_theme_constant_override("v_separation", 6)
	right.add_child(_scroll(gem_grid, Vector2(420, 372)))


## a list that scrolls vertically once it outgrows `size`
static func _scroll(inner: Control, size: Vector2) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = size
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.add_child(inner)
	return sc


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
		[Data.cost_text(sk) + ("　CD %s秒" % sk.cd if sk.cd > 0.0 else ""), Color("#9a9080"), 12], [sk.desc, Color("#dddddd"), 13]]
	if slot < 0:
		lines.append(_req_line(sk.lvl, hud.main.player.level))
	if sk.has("aura"):
		var p: Player = hud.main.player
		var pool: String = sk.aura.pool
		var key := "%sを" % Keybinds.text(Keybinds.skill_action(slot)) if slot >= 0 else ""
		lines.append(["範囲 %dm　%s押すたびに発動／解除" % [sk.aura.r, key], Color("#9a9080"), 12])
		lines.append(["いまのリザーブ量 %s %d%s" % ["ライフ" if pool == "life" else "マナ", p.aura_reserve(id, pool), "（発動中）" if id in p.auras else ""],
			Color("#ffd890"), 12])
	if slot >= 0:
		lines.insert(1, ["スロット %d　キー：%s" % [slot + 1, Keybinds.text(Keybinds.skill_action(slot))], Color("#ffd36a"), 12])
		var s: Dictionary = hud.main.slot_sup(slot)
		for gid in s.ids:
			var g := Data.support(gid)
			lines.append(["◆ %s：%s" % [g.name, g.desc], g.color, 12])
	return lines


## "必要レベル N", red while the character is below it
static func _req_line(need: int, level: int) -> Array:
	return ["必要レベル %d" % need, Color("#dddddd") if level >= need else Color("#ff8080"), 12]


static func gem_tip(g: Dictionary, level := 999) -> Array:
	var target := "対象：" + Data.tag_text(g.tags)
	if g.has("not"):
		target += "（%sを除く）" % Data.tag_text(g.not)
	if g.has("need"):
		target += "\n%sスキルのみ" %"・".join(PackedStringArray(g.need.map(func(k): return Data.NEED_NAMES[k])))
	return [[g.name, g.color, 17], ["サポートジェム　エネルギー消費 %d" % g.energy, Color("#9a9080"), 12], [g.desc, Color("#dddddd"), 13], [target, Color("#8fb4ff"), 12],
		_req_line(g.lvl, level)]


func refresh() -> void:
	if not visible:
		return
	var p: Player = hud.main.player
	var e_left := p.energy_max() - p.energy_used()
	BasePanel.clear(slot_row)
	BasePanel.clear(skill_grid)
	BasePanel.clear(gem_grid)
	BasePanel.clear(tag_row)
	for t in FILTER_TAGS:
		var on: bool = tag_sel == t
		var tb := card("すべて" if t == "" else Data.TAG_NAMES[t], Color("#2a2014") if on else Color("#120e0a"),
			Color("#ffd36a") if on else Color("#3a3024"), Color("#ffe8b0") if on else Color("#a89878"))
		tb.add_theme_font_size_override("font_size", 11)
		tb.pressed.connect(func():
			tag_sel = t
			refresh())
		tag_row.add_child(tb)

	for i in Data.SLOT_COUNT:
		var id: String = p.slots[i]
		var sk: Dictionary = Data.SKILLS[id]
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 3)
		var b := card("%s\n%s" % [Keybinds.text(Keybinds.skill_action(i)), sk.name], Color("#2a2014") if i == sel else Color("#120e0a"),
			Color("#ffd36a") if i == sel else Color("#4a3a26"), sk.color, 2 if i == sel else 1)
		b.custom_minimum_size = Vector2(150, 52)
		var iv := SkillIcon.View.new()
		iv.skill = id
		SkillIcon.attach(b, iv, 40)
		b.pressed.connect(func():
			sel = i
			refresh())
		_hover(b, skill_tip(id, i))
		card.add_child(b)
		var socks := HBoxContainer.new()
		socks.add_theme_constant_override("separation", 2)
		socks.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_child(socks)
		var links: Array = p.links[i]
		var powered := p.active_links(i)
		for k in Data.LINK_MAX:
			var gid: String = links[k] if k < links.size() else ""
			var g := Data.support(gid)
			var fits := not g.is_empty() and Data.support_fits(g, id)
			var dark := not g.is_empty() and not gid in powered
			var s := card("", Color("#0c0a08"),
				Color("#ff5050") if not g.is_empty() and (not fits or dark) else Color("#5a4a34"), Color.WHITE)
			s.custom_minimum_size = Vector2(22, 22)
			if dark:
				s.modulate = Color(1, 1, 1, 0.55)
			if not g.is_empty():
				var gv := SkillIcon.View.new()
				gv.gem = g
				gv.mark = "✕" if not fits else ("!" if dark else "")
				s.add_child(gv)
				var tip := gem_tip(g, p.level)
				if dark:
					tip.append(["エネルギー不足で無効", Color("#ff8080"), 12])
				tip.append(["クリックで外す" + ("" if fits else "（このスキルには無効）"), Color("#ffd36a"), 12])
				_hover(s, tip)
				s.pressed.connect(func():
					links.erase(gid)
					_changed())
			socks.add_child(s)
		slot_row.add_child(card)

	# owned skill gems first; the rest show where they come from
	var order: Array = Data.SKILL_ORDER.filter(func(id): return id in p.skills) + Data.SKILL_ORDER.filter(func(id): return not id in p.skills)
	for id in order:
		var sk: Dictionary = Data.SKILLS[id]
		if tag_sel != "" and not tag_sel in sk.tags:
			continue
		var locked: bool = not p.can_use_skill(id)
		var at := p.slots.find(id)
		var tag := ("未入手（Lv %d）" % sk.lvl) if not id in p.skills else ("Lv %d から使える" % sk.lvl) if locked 			else ("装備中：%s" % Keybinds.text(Keybinds.skill_action(at)) if at >= 0 else "")
		var b := card("%s　%s\n%s%s　%s" % [sk.name, tag, Data.cost_text(sk), "　CD %s秒" % sk.cd if sk.cd > 0.0 else "", Data.tag_text(sk.tags)],
			Color("#120e0a"), Color("#6a5a44") if at >= 0 else Color("#3a3024"), sk.color.darkened(0.55) if locked else sk.color)
		b.custom_minimum_size = Vector2(250, 48)
		var iv := SkillIcon.View.new()
		iv.skill = id
		iv.dim = locked
		SkillIcon.attach(b, iv, 38)
		var tip := skill_tip(id)
		if not id in p.skills:
			tip.append(["敵のドロップか商人で手に入る", Color("#ffd36a"), 12])
		_hover(b, tip)
		if not locked:
			b.pressed.connect(_assign.bind(id))
		skill_grid.add_child(b)

	var sel_id: String = p.slots[sel]
	var sel_links: Array = p.links[sel]
	gem_hint.text = "エネルギー %d / %d（残り %d）　「%s」にリンク %d / %d\nジェムごとにエネルギーを消費。上限はレベルと装備で増える" % [
		p.energy_used(), p.energy_max(), e_left, Data.SKILLS[sel_id].name, sel_links.size(), Data.LINK_MAX]
	# gems owned come first
	var gems: Array = Data.SUPPORTS.filter(func(g): return g.id in p.gems) + Data.SUPPORTS.filter(func(g): return not g.id in p.gems)
	for g in gems:
		var owned: bool = g.id in p.gems
		var fits: bool = Data.support_fits(g, sel_id) and p.level >= g.lvl
		if fit_only.button_pressed and not Data.support_fits(g, sel_id) and not g.id in sel_links:
			continue
		var linked: bool = g.id in sel_links
		var tag := ("未入手（Lv %d）" % g.lvl) if not owned else ("リンク中" if linked else ("Lv %d から" % g.lvl if p.level < g.lvl else ("" if fits else "対象外")))
		tag = "✦%d　%s" % [g.energy, tag]
		var font: Color = g.color if owned and fits else g.color.darkened(0.6)
		var b := card("%s　%s" % [g.name, tag], Color("#1c2a1c") if linked else Color("#120e0a"), g.color if linked else Color("#3a3024"), font, 2 if linked else 1)
		b.custom_minimum_size = Vector2(200, 34)
		var gv := SkillIcon.View.new()
		gv.gem = g
		gv.dim = not (owned and fits)
		SkillIcon.attach(b, gv, 26)
		_hover(b, gem_tip(g, p.level))
		b.pressed.connect(_toggle_gem.bind(g.id))
		gem_grid.add_child(b)


## put a skill in the selected slot; a skill already on the bar swaps places (with its links)
func _assign(id: String) -> void:
	var p: Player = hud.main.player
	if not p.can_use_skill(id):
		var sk: Dictionary = Data.SKILLS[id]
		hud.message(("「%s」のスキルジェムを持っていない" % sk.name) if not id in p.skills else ("「%s」は Lv %d から使える" % [sk.name, sk.lvl]), Color("#ff8080"))
		return
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
	elif p.level < g.lvl:
		hud.message("%sは Lv %d からリンクできる" % [g.name, g.lvl], Color("#ff8080"))
		return
	elif not Data.support_fits(g, sel_id):
		hud.message("%sは「%s」に使えない" % [g.name, Data.SKILLS[sel_id].name], Color("#ff8080"))
		return
	elif links.size() >= Data.LINK_MAX:
		hud.message("リンクは最大%d個まで" % Data.LINK_MAX, Color("#ff8080"))
		return
	elif p.energy_used() + g.energy > p.energy_max():
		hud.message("エネルギーが足りない（あと %d 必要）" % (p.energy_used() + g.energy - p.energy_max()), Color("#ff8080"))
		return
	else:
		links.append(gid)
	_changed()


func _changed() -> void:
	hud.hide_tip()
	hud.main.save_game()
	refresh()
