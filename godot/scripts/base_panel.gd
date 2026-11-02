class_name BasePanel
extends PanelContainer
## Frame shared by the centered panels: a title row with a close button, then the panel's own content.
## Subclasses fill `body` in `_build()` and redraw it in `refresh()`.

var hud: Hud
var body := VBoxContainer.new()


func _ready() -> void:
	add_theme_stylebox_override("panel", Hud.panel_box())
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := Label.new()
	title.text = _title()
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#f0d8a0"))
	head.add_child(title)
	var hint := sub("   " + _hint())
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hint)
	var close := Button.new()
	close.text = "×"
	close.pressed.connect(open_close)
	head.add_child(close)
	body.add_theme_constant_override("separation", 8)
	col.add_child(body)
	_build()


func _title() -> String:
	return ""


func _hint() -> String:
	return ""


func _build() -> void:
	pass


func refresh() -> void:
	pass


func open_close() -> void:
	visible = not visible
	hud.hide_tip()
	if visible:
		refresh()
		_center.call_deferred()


func _center() -> void:
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


static func sub(text: String, size := 13, color := Color("#b8a888")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## empty a box to rebuild it; the old children leave at once but are freed at the end of the frame, since the
## rebuild often runs from a button inside the box (the character screen's delete button), still emitting its signal
static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func hover(c: Control, lines: Array) -> void:
	c.mouse_entered.connect(func(): hud.show_tip(lines))
	c.mouse_exited.connect(func(): hud.hide_tip())
