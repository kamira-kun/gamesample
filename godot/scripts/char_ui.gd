class_name CharUI
extends ColorRect
## Character screen shown at start: pick a character, make one in the running season or standard, or delete one.
## Choosing restarts the scene with that character (Profiles.active).

var hud: Hud
var box := VBoxContainer.new()
var season_label := Label.new()
var notes_box := VBoxContainer.new()
var list := VBoxContainer.new()
var name_edit := LineEdit.new()
var league_pick := OptionButton.new()
var leagues: Array = []
var confirm_id := ""   # character whose delete button was pressed once


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
	box.custom_minimum_size = Vector2(620, 0)
	panel.add_child(box)
	var title := BasePanel.sub("キャラクター選択", 24, Color("#f0d8a0"))
	box.add_child(title)
	season_label.add_theme_font_size_override("font_size", 14)
	box.add_child(season_label)
	box.add_child(notes_box)
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(SkillUI._scroll(list, Vector2(620, 300)))
	box.add_child(BasePanel.sub("新しいキャラクター", 16, Color("#f0d8a0")))
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


func _create() -> void:
	var n := name_edit.text.strip_edges()
	if n == "":
		n = "冒険者%d" % (Profiles.chars().size() + 1)
	var c := Profiles.add_char(n, leagues[league_pick.selected])
	Profiles.save_all()
	hud.main.switch_char(c.id)
