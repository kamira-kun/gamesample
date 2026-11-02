class_name KeyconfigUI
extends BasePanel
## Key config: every action with its two bindings. Click a binding, then press the key or mouse
## button to put there (Esc cancels); right-click clears it. A binding already used by another
## action is swapped onto that action. Saved to the user settings file on every change.

var save_path := Keybinds.PATH   # "" in dev runs, so they never touch the player's settings
var listening := []              # [action id, slot] waiting for a press
var cols := HBoxContainer.new()
var warn := Label.new()
var reset := Button.new()


func _title() -> String:
	return "キー設定"


func _hint() -> String:
	return "クリックしてから割り当てるキー／マウスボタンを押す（Esc で取消）。右クリックで解除"


func _build() -> void:
	cols.add_theme_constant_override("separation", 28)
	body.add_child(cols)
	warn.add_theme_font_size_override("font_size", 13)
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.custom_minimum_size = Vector2(900, 0)
	body.add_child(warn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	reset.text = "  既定に戻す  "
	reset.pressed.connect(func():
		Keybinds.reset()
		_changed("すべて既定のキーに戻しました", Color("#c8b898")))
	row.add_child(reset)
	var close := Button.new()
	close.text = "  閉じる（Esc）  "
	close.pressed.connect(open_close)
	row.add_child(close)


func open_close() -> void:
	listening = []
	warn.text = ""
	super.open_close()


func refresh() -> void:
	clear(cols)
	var left := _grid()
	var right := _grid()
	var group := ""
	for a in Keybinds.ACTIONS:
		var g: GridContainer = right if a.group == "画面" else left
		if a.group != group:
			group = a.group
			_cells(g, [sub(group, 14, Color("#f0d8a0")), Control.new(), Control.new()])
		var cells: Array = [sub(a.name, 14, Color("#d8c8a8"))]
		for i in Keybinds.SLOTS:
			cells.append(_bind_button(a.id, i))
		_cells(g, cells)
	_cells(right, [sub("固定", 14, Color("#f0d8a0")), Control.new(), Control.new()])
	_cells(right, [sub("画面を閉じる／一時停止", 14, Color("#8a7c64")), _fixed("Esc"), Control.new()])
	_cells(right, [sub("ツールチップに数値の範囲（押している間）", 14, Color("#8a7c64")), _fixed("Alt"), Control.new()])
	var dup := Keybinds.conflicts()
	if not dup.is_empty():
		var names := PackedStringArray(dup.map(func(grp): return "・".join(PackedStringArray(grp.map(func(x): return Keybinds.action(x[0]).name)))))
		warn.text = "重複している割り当てがあります（赤）：" + "、".join(names)
		warn.add_theme_color_override("font_color", Color("#ff7a6a"))


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 1 + Keybinds.SLOTS
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 5)
	cols.add_child(g)
	return g


func _cells(g: GridContainer, cells: Array) -> void:
	for c in cells:
		g.add_child(c)


func _fixed(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = true
	b.custom_minimum_size = Vector2(130, 30)
	return b


func _bind_button(id: String, slot: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(130, 30)
	b.focus_mode = Control.FOCUS_NONE   # Space/Enter must reach the capture, not press the button again
	var now := listening == [id, slot]
	var bind: Dictionary = Keybinds.binds[id][slot]
	b.text = "キーを押す…" if now else (Keybinds.label_of(bind) if not bind.is_empty() else "—")
	if now:
		b.add_theme_color_override("font_color", Color("#ffd36a"))
	elif Keybinds.conflicted(id, slot):
		b.add_theme_color_override("font_color", Color("#ff6a5a"))
	elif bind.is_empty():
		b.add_theme_color_override("font_color", Color("#6a604c"))
	# deferred: both rebuild the rows, which frees this button
	b.pressed.connect(listen.bind(id, slot), CONNECT_DEFERRED)
	b.gui_input.connect(func(e: InputEvent):
		if listening.is_empty() and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			bind_to.call_deferred(id, slot, {}))
	return b


func listen(id: String, slot: int) -> void:
	listening = [id, slot]
	warn.text = "「%s」に割り当てるキーかマウスボタンを押してください（Esc で取消）" % Keybinds.action(id).name
	warn.add_theme_color_override("font_color", Color("#ffd36a"))
	refresh()


## while listening, the next key or mouse press is the new binding; nothing else sees it
func _input(e: InputEvent) -> void:
	if not visible or listening.is_empty():
		return
	if e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE:
		listening = []
		get_viewport().set_input_as_handled()
		_changed("取り消しました", Color("#c8b898"))
		return
	var b := Keybinds.from_event(e)
	if b.is_empty():
		if e is InputEventKey or e is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()
	bind_to(listening[0], listening[1], b)


func bind_to(id: String, slot: int, b: Dictionary) -> void:
	listening = []
	var lost := Keybinds.assign(id, slot, b)
	if b.is_empty():
		_changed("「%s」の割り当てを解除しました" % Keybinds.action(id).name, Color("#c8b898"))
	elif lost != "":
		_changed("%s は「%s」に割り当て済みでした。入れ替えて「%s」は %s になりました" % [Keybinds.label_of(b), Keybinds.action(lost).name,
			Keybinds.action(lost).name, Keybinds.text(lost)], Color("#ffb060"))
	else:
		_changed("「%s」を %s に割り当てました" % [Keybinds.action(id).name, Keybinds.label_of(b)], Color("#a8e0a0"))


func _changed(msg: String, color: Color) -> void:
	if save_path != "":
		Keybinds.save(save_path)
	warn.text = msg
	warn.add_theme_color_override("font_color", color)
	refresh()
	hud.pause_ui.refresh()
	for sl in hud.slots:
		sl.queue_redraw()
	_center.call_deferred()
