class_name CharUI
extends ColorRect
## Character screen shown at start: pick a character, make one (choosing its base class, and the running
## season or standard), or delete one. Choosing restarts the scene with that character (Profiles.active).

var hud: Hud
var box := VBoxContainer.new()
var season_label := Label.new()
var notes_box := VBoxContainer.new()
var list := VBoxContainer.new()
var name_edit := LineEdit.new()
var league_pick := OptionButton.new()
var leagues: Array = []
var confirm_id := ""   # character whose delete button was pressed once
var cls := Data.DEFAULT_CLASS   # base class the new character will have
var class_row := HBoxContainer.new()
var class_info := VBoxContainer.new()
var preview := Portrait.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.02, 0.015, 0.012, 0.94)
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Hud.panel_box())
	center.add_child(panel)
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(760, 0)
	panel.add_child(box)
	var title := BasePanel.sub("キャラクター選択", 24, Color("#f0d8a0"))
	box.add_child(title)
	season_label.add_theme_font_size_override("font_size", 14)
	box.add_child(season_label)
	box.add_child(notes_box)
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(SkillUI._scroll(list, Vector2(760, 210)))
	box.add_child(BasePanel.sub("新しいキャラクター", 16, Color("#f0d8a0")))
	class_row.add_theme_constant_override("separation", 8)
	box.add_child(class_row)
	var detail := HBoxContainer.new()
	detail.add_theme_constant_override("separation", 12)
	box.add_child(detail)
	preview.preview = true
	detail.add_child(preview)
	preview.frame.custom_minimum_size = Vector2(150, 200)
	class_info.add_theme_constant_override("separation", 4)
	class_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_child(class_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	name_edit.placeholder_text = "名前"
	name_edit.max_length = 16
	name_edit.custom_minimum_size = Vector2(220, 34)
	row.add_child(name_edit)
	league_pick.custom_minimum_size = Vector2(220, 34)
	row.add_child(league_pick)
	var make := Button.new()
	make.text = "作成して始める"
	make.custom_minimum_size = Vector2(150, 34)
	make.pressed.connect(_create)
	row.add_child(make)
	box.add_child(BasePanel.sub("シーズンのキャラクターはシーズン専用のスタッシュを共有し、シーズン終了時にスタッシュごとスタンダードへ移ります。", 12))


func open(notes: Array) -> void:
	visible = true
	BasePanel.clear(notes_box)
	for n in notes:
		notes_box.add_child(BasePanel.sub("◆ " + n, 13, Color("#ffcf7a")))
	refresh()


func refresh() -> void:
	var s := Data.current_season()
	if s.is_empty():
		season_label.text = "開催中のシーズンはありません"
		season_label.add_theme_color_override("font_color", Color("#998a70"))
	else:
		season_label.text = "開催中：シーズン「%s」　%s 〜 %s（残り %d 日）" % [s.name, s.start, s.end, Data.season_days_left(s)]
		season_label.add_theme_color_override("font_color", s.color)
	leagues = [] if s.is_empty() else [s.id]
	leagues.append(Profiles.STANDARD)
	league_pick.clear()
	for lg in leagues:
		league_pick.add_item(("シーズン「%s」" % s.name) if lg != Profiles.STANDARD else "スタンダード")
	league_pick.select(0)
	pick_class(cls)
	BasePanel.clear(list)
	if Profiles.chars().is_empty():
		list.add_child(BasePanel.sub("キャラクターがいません。下で作成してください。", 14))
	for c in Profiles.chars():
		list.add_child(_row(c))


func _row(c: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lg: String = c.league
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	info.add_child(BasePanel.sub("%s　Lv %d" % [c.name, int(c.data.get("level", 1))], 17, Color("#f0e0c0")))
	var bc := Data.base_class(c.cls)
	var asc := Data.ascendancy(str(c.data.get("asc", "")))
	info.add_child(BasePanel.sub("%s %s%s" % [bc.icon, bc.name, "　／　%s %s" % [asc.icon, asc.name] if not asc.is_empty() else ""], 13,
		asc.get("color", bc.color)))
	var tag := Profiles.league_name(lg) if lg == Profiles.STANDARD else "シーズン「%s」" % Profiles.league_name(lg)
	if c.from_season != "":
		tag += "（元シーズン「%s」）" % Profiles.league_name(c.from_season)
	info.add_child(BasePanel.sub(tag, 12, Data.season(lg).get("color", Color("#998a70"))))
	row.add_child(info)
	var play := Button.new()
	play.text = "プレイ"
	play.custom_minimum_size = Vector2(90, 34)
	play.pressed.connect(func(): hud.main.switch_char(c.id))
	row.add_child(play)
	var del := Button.new()
	del.text = "本当に削除？" if confirm_id == c.id else "削除"
	del.custom_minimum_size = Vector2(110, 34)
	if confirm_id == c.id:
		del.add_theme_color_override("font_color", Color("#ff7a6a"))
	del.pressed.connect(func():
		if confirm_id != c.id:
			confirm_id = c.id
		else:
			confirm_id = ""
			Profiles.remove_char(c.id)
			Profiles.save_all()
		refresh())
	row.add_child(del)
	return row


## choose the base class of the new character: highlight its card, show its traits and the heroine in its colors
func pick_class(k: String) -> void:
	cls = k if not Data.base_class(k).is_empty() else Data.DEFAULT_CLASS
	BasePanel.clear(class_row)
	for bc in Data.CLASSES:
		var on: bool = bc.k == cls
		var card := SkillUI.card("%s %s" % [bc.icon, bc.name], bc.color.darkened(0.72) if on else Color("#120e0a"),
			bc.color if on else Color("#4a3c2a"), bc.color if on else Color("#a89878"), 2 if on else 1)
		card.add_theme_font_size_override("font_size", 16)
		card.alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.custom_minimum_size = Vector2(0, 40)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.pressed.connect(pick_class.bind(bc.k))
		class_row.add_child(card)
	var bc := Data.base_class(cls)
	BasePanel.clear(class_info)
	class_info.add_child(BasePanel.sub("%s %s" % [bc.icon, bc.name], 18, bc.color))
	class_info.add_child(BasePanel.sub(bc.desc, 13, Color("#d8c8a8")))
	class_info.add_child(BasePanel.sub("初期能力：" + bc.traits, 13, Color("#c8d8a0")))
	class_info.add_child(BasePanel.sub("初期装備：%s　　初期スキル：%s" % [bc.weapon,
		"・".join(PackedStringArray(bc.slots.map(func(id): return Data.SKILLS[id].name)))], 13, Color("#c8b898")))
	class_info.add_child(BasePanel.sub("選べるアセンダンシー（Lv2から）", 13, Color("#f0d8a0")))
	for a in Data.class_ascs(cls):
		class_info.add_child(BasePanel.sub("　%s %s — %s" % [a.icon, a.name, a.desc], 12, a.color))
	for l: Label in class_info.get_children():
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	preview.show_class(cls)


func _create() -> void:
	var n := name_edit.text.strip_edges()
	if n == "":
		n = "冒険者%d" % (Profiles.chars().size() + 1)
	var c := Profiles.add_char(n, leagues[league_pick.selected], cls)
	Profiles.save_all()
	hud.main.switch_char(c.id)
