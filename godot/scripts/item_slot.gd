class_name ItemSlot
extends Control
## One square of an item grid: an item colored by rarity, or an empty slot.
## Hovering shows the item's tooltip (plus `extra` lines, and the equipped item when `compare`).

signal clicked
signal right_clicked
var item: Dictionary = {}
var empty_text := ""
var hud: Hud
var extra: Array = []
var compare := false
var glow := false


func _ready() -> void:
	mouse_entered.connect(func():
		if item.is_empty():
			return
		var lines := Items.lines(item)
		lines.append_array(extra)
		var p: Player = hud.main.player
		var cur: Dictionary = p.equip.get(item.slot, {})
		if compare and not cur.is_empty() and cur != item:
			lines.append(["— 装備中 —", Color("#7a7266"), 12])
			lines.append_array(Items.lines(cur))
		hud.show_tip(lines))
	mouse_exited.connect(func(): hud.hide_tip())


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit()
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			right_clicked.emit()
		accept_event()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if item.is_empty():
		draw_rect(rect, Color("#0c0a08"))
		draw_rect(rect, Color("#3a3024"), false, 1.0)
		draw_string(Data.ui_font, Vector2(0, size.y / 2 + 5), empty_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, Color("#554a3a"))
		return
	var c: Color = Data.RARITY[item.rarity].color
	draw_rect(rect, c.darkened(0.82))
	draw_rect(rect, c.darkened(0.3), false, 2.0 if item.rarity == 3 else 1.0)
	draw_string_outline(Data.ui_font, Vector2(0, size.y / 2 + 9), Data.SLOT_INFO[item.slot].glyph, HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, 3, Color.BLACK)
	draw_string(Data.ui_font, Vector2(0, size.y / 2 + 9), Data.SLOT_INFO[item.slot].glyph, HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, c)
	if glow:
		draw_rect(rect, Color(1, 0.85, 0.4, 0.12))
