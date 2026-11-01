class_name TalentUI
extends BasePanel
## Talents (T): spend the point each level gives on stats or on one skill's damage.

var points := Label.new()
var base_list := VBoxContainer.new()
var skill_list := VBoxContainer.new()


func _title() -> String:
	return "タレント"


func _hint() -> String:
	return "レベルが上がるたびにポイントが1つ増える"


func _build() -> void:
	points.add_theme_font_size_override("font_size", 15)
	points.add_theme_color_override("font_color", Color("#ffe27a"))
	body.add_child(points)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	body.add_child(cols)
	for pair in [["基本能力", base_list], ["スキル強化（スキルバーのスキル）", skill_list]]:
		var c := VBoxContainer.new()
		c.add_theme_constant_override("separation", 4)
		c.add_child(sub(pair[0]))
		pair[1].add_theme_constant_override("separation", 4)
		c.add_child(pair[1])
		cols.add_child(c)


func refresh() -> void:
	if not visible:
		return
	var p: Player = hud.main.player
	points.text = "残りポイント %d" % p.talent_pts
	clear(base_list)
	clear(skill_list)
	for t in Data.talents():
		var r: int = p.talents[t.k]
		if t.get("skill", false) and r == 0 and not t.k in p.slots:
			continue   # skill talents: only the skills on the bar and those already ranked
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var col: Color = Data.SKILLS[t.k].color if t.get("skill", false) else Color("#f0dcb4")
		var lbl := sub(("%s %s" % [Data.SKILLS[t.k].icon, t.name]) if t.get("skill", false) else t.name, 14, col)
		lbl.custom_minimum_size = Vector2(170, 0)
		row.add_child(lbl)
		var desc := sub(t.desc, 12, Color("#a89878"))
		desc.custom_minimum_size = Vector2(200 if t.get("skill", false) else 290, 0)
		row.add_child(desc)
		var rank := sub("%d / %d" % [r, t.max], 13, Color("#ffe27a") if r > 0 else Color("#776a58"))
		rank.custom_minimum_size = Vector2(54, 0)
		rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(rank)
		var b := Button.new()
		b.text = "+"
		b.custom_minimum_size = Vector2(30, 26)
		b.disabled = p.talent_pts <= 0 or r >= t.max
		b.pressed.connect(_spend.bind(t.k))
		row.add_child(b)
		(skill_list if t.get("skill", false) else base_list).add_child(row)


func _spend(k: String) -> void:
	var p: Player = hud.main.player
	var t: Dictionary = Data.talents().filter(func(x): return x.k == k)[0]
	if p.talent_pts <= 0 or p.talents[k] >= t.max:
		return
	p.talent_pts -= 1
	p.talents[k] += 1
	p.recalc()
	hud.main.save_game()
	refresh()
