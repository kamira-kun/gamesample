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


## `glv`: the gem level to show (-1: the character's own gem, with its experience)
func skill_tip(id: String, slot := -1, glv := -1) -> Array:
	var sk: Dictionary = Data.SKILLS[id]
	var p: Player = hud.main.player
	var lines := [[sk.name, sk.color, 17], [Data.tag_text(sk.tags), Color("#9a9080"), 12],
		[Data.cost_text(sk) + ("　CD %s秒" % sk.cd if sk.cd > 0.0 else ""), Color("#9a9080"), 12], [sk.desc, Color("#dddddd"), 13]]
	var mine := glv < 0
	if mine:
		glv = p.gem_lv(true, id)
	lines.append_array(gem_lv_lines(true, id, glv, p if mine and id in p.skills else null))
	if slot < 0:
		lines.append(_req_line(Data.gem_req(true, id, glv), p.level))
	if sk.has("aura"):
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
			lines.append(["◆ %s Lv%d：%s" % [g.name, p.gem_lv(false, gid), g.desc], g.color, 12])
	return lines


## a thin bar of a gem's experience toward its next level (full and gold at the top level)
static func xp_bar(p: Player, skill: bool, id: String, w: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(w, 5)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pr := p.gem_progress(skill, id)
	bar.max_value = maxi(1, pr[1])
	bar.value = bar.max_value if pr[1] == 0 else pr[0]
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#0c0a08")
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color("#ffd36a") if pr[1] == 0 else (Color("#ff9a70") if p.gem_waiting(skill, id) else Data.GEM_XP_COLOR)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	return bar


## "必要レベル N", red while the character is below it
static func _req_line(need: int, level: int) -> Array:
	return ["必要レベル %d" % need, Color("#dddddd") if level >= need else Color("#ff8080"), 12]


## the gem level lines of a tooltip: "ジェムLv N / 20", what the level adds, and with `p` (the gem's owner) its
## experience toward the next level
static func gem_lv_lines(skill: bool, id: String, lv: int, p: Player = null) -> Array:
	var out := [["ジェムLv %d / %d" % [lv, Data.GEM_MAX_LV], Data.GEM_XP_COLOR, 13]]
	var t := Data.gem_lv_text(skill, id, lv)
	if t != "":
		out.append([t, Data.GEM_XP_COLOR, 12])
	if p == null:
		return out
	if lv >= Data.GEM_MAX_LV:
		out.append(["最大レベルに達している", Color("#ffd36a"), 12])
		return out
	var pr := p.gem_progress(skill, id)
	out.append(["ジェム経験値 %d / %d（%d%%）" % [pr[0], pr[1], floori(100.0 * pr[0] / maxf(1.0, pr[1]))], Data.GEM_XP_COLOR, 12])
	if p.gem_waiting(skill, id):
		out.append(["次のジェムLvにはキャラクター Lv %d が必要（経験値は満タンで待機中）" % Data.gem_req(skill, id, lv + 1), Color("#ff9a70"), 12])
	else:
		out.append(["スキルバーに付けている間、敵を倒すと経験値がたまる", Color("#9a9080"), 11])
	return out


## `glv`: the gem level shown (its requirement and its strength); `p`: the owner, to show its experience
static func gem_tip(g: Dictionary, level := 999, glv := 1, p: Player = null) -> Array:
	var target := "対象：" + Data.tag_text(g.tags)
	if g.has("not"):
		target += "（%sを除く）" % Data.tag_text(g.not)
	if g.has("need"):
		target += "\n%sスキルのみ" %"・".join(PackedStringArray(g.need.map(func(k): return Data.NEED_NAMES[k])))
	var lines := [[g.name, g.color, 17], ["%s　エネルギー消費 %d" % [Data.AWAKE_KIND if g.get("awake", false) else "サポートジェム", g.energy], Color("#9a9080"), 12],
		[g.desc, Color("#dddddd"), 13], [target, Color("#8fb4ff"), 12]]
	lines.append_array(gem_lv_lines(false, g.id, glv, p))
	lines.append(_req_line(Data.gem_req(false, g.id, glv), level))
	if g.get("awake", false):
		var base := Data.support(g.base)
		lines.append(["「%s」の覚醒体。同じスキルに元のジェムとは一緒にリンクできない" % base.name, Data.AWAKE_COLOR, 12])
		lines.append(["Lv %d 以上のエリアのエリートとボスのドロップか、取引所でのみ手に入る" % Data.AWAKE_DROP_ILVL, Color("#ffd36a"), 12])
	return lines


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
		var b := card("%s　Lv%d\n%s" % [Keybinds.text(Keybinds.skill_action(i)), p.gem_lv(true, id), sk.name], Color("#2a2014") if i == sel else Color("#120e0a"),
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
		card.add_child(xp_bar(p, true, id, 150))
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
				gv.lv = p.gem_lv(false, gid)
				s.add_child(gv)
				var tip := gem_tip(g, p.level, gv.lv, p)
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
		var tag := ("未入手（Lv %d）" % sk.lvl) if not id in p.skills else ("Lv %d から使える" % p.gem_req(true, id)) if locked 			else ("装備中：%s" % Keybinds.text(Keybinds.skill_action(at)) if at >= 0 else "")
		var b := card("%s%s　%s\n%s%s　%s" % [sk.name, "　Lv%d" % p.gem_lv(true, id) if id in p.skills else "", tag, Data.cost_text(sk), "　CD %s秒" % sk.cd if sk.cd > 0.0 else "", Data.tag_text(sk.tags)],
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
	# gems owned come first (awakened gems are only listed once owned)
	var gems: Array = Data.all_supports().filter(func(g): return g.id in p.gems) + Data.SUPPORTS.filter(func(g): return not g.id in p.gems)
	for g in gems:
		var owned: bool = g.id in p.gems
		var twin := _twin_linked(g.id, sel_links)
		var req := p.gem_req(false, g.id)
		var glv := p.gem_lv(false, g.id) if owned else 1
		var fits: bool = Data.support_fits(g, sel_id) and p.level >= req and twin == ""
		if fit_only.button_pressed and not Data.support_fits(g, sel_id) and not g.id in sel_links:
			continue
		var linked: bool = g.id in sel_links
		var tag := ("未入手（Lv %d）" % g.lvl) if not owned else ("リンク中" if linked else ("Lv %d から" % req if p.level < req
			else ("" if fits else ("重複" if twin != "" else "対象外"))))
		tag = "✦%d　%s" % [g.energy, tag]
		var font: Color = g.color if owned and fits else g.color.darkened(0.6)
		var b := card("%s%s　%s" % [g.name, "　Lv%d" % glv if owned else "", tag], Color("#1c2a1c") if linked else Color("#120e0a"), g.color if linked else Color("#3a3024"), font, 2 if linked else 1)
		b.custom_minimum_size = Vector2(200, 34)
		var gv := SkillIcon.View.new()
		gv.gem = g
		gv.dim = not (owned and fits)
		gv.lv = glv if owned else 0
		SkillIcon.attach(b, gv, 26)
		_hover(b, gem_tip(g, p.level, glv, p if owned else null))
		b.pressed.connect(_toggle_gem.bind(g.id))
		gem_grid.add_child(b)


## put a skill in the selected slot; a skill already on the bar swaps places (with its links)
func _assign(id: String) -> void:
	var p: Player = hud.main.player
	if not p.can_use_skill(id):
		var sk: Dictionary = Data.SKILLS[id]
		hud.message(("「%s」のスキルジェムを持っていない" % sk.name) if not id in p.skills else ("「%s」（ジェムLv %d）は Lv %d から使える" % [sk.name, p.gem_lv(true, id), p.gem_req(true, id)]), Color("#ff8080"))
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
	elif p.level < p.gem_req(false, gid):
		hud.message("%s（ジェムLv %d）は Lv %d からリンクできる（いまは Lv %d）" % [g.name, p.gem_lv(false, gid), p.gem_req(false, gid), p.level], Color("#ff8080"))
		return
	elif _twin_linked(gid, links) != "":
		hud.message("%sは「%s」と同じスキルにリンクできない" % [g.name, Data.support(_twin_linked(gid, links)).name], Color("#ff8080"))
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


## the gem in `links` that is `gid`'s base or awakened twin, or ""
static func _twin_linked(gid: String, links: Array) -> String:
	for o in links:
		if o != gid and Data.base_gem(o) == Data.base_gem(gid):
			return o
	return ""


func _changed() -> void:
	hud.hide_tip()
	hud.main.save_game()
	refresh()
