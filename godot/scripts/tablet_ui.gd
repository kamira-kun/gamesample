class_name TabletUI
extends BasePanel
## The tablet board (see Tablets): the 6x6 board on the left, the tablets owned on the right.
## Pick a tablet, turn it (R or the button) and click a cell to set it there with its top-left at that cell;
## click a tablet on the board to pick it up again, right-click it to take it off. Crafting currencies carve
## the picked tablet's lines, and one-line crafting (LineCraft) works on a single line of it.

const CELL := 50.0
const CRAFTS := [["whet", "刻む"], ["chaos", "刻み直す"], ["divine", "数値を振り直す"]]

var board := Board.new()
var used := Label.new()
var totals := Label.new()
var list := GridContainer.new()
var info := Label.new()
var actions := HBoxContainer.new()
var confirm_shatter := ""   # uid of the unique that the next press of 砕く breaks
var error := Label.new()
var line_box := LineCraft.Box.new()
var sel := ""             # uid of the picked tablet
var rot := 0              # the turn the picked tablet is set with


func _title() -> String:
	return "タブレット盤"


func _hint() -> String:
	return "ルーンタブレットを選んでマスをクリックで設置　R：回転　盤のルーンタブレットをクリック：選ぶ　右クリック：外す"


func _build() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	body.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	board.ui = self
	board.custom_minimum_size = Vector2.ONE * CELL * Tablets.SIZE
	left.add_child(board)
	used.add_theme_font_size_override("font_size", 14)
	used.add_theme_color_override("font_color", Tablets.COLOR)
	left.add_child(used)
	totals.add_theme_font_size_override("font_size", 13)
	totals.add_theme_color_override("font_color", Color("#8fd8ff"))
	totals.custom_minimum_size = Vector2(CELL * Tablets.SIZE, 0)
	totals.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(totals)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	right.add_child(sub("所持しているルーンタブレット"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 230)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	list.columns = 2
	list.add_theme_constant_override("h_separation", 6)
	list.add_theme_constant_override("v_separation", 6)
	scroll.add_child(list)
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", Color("#e8dcc0"))
	info.custom_minimum_size = Vector2(400, 0)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(info)
	actions.add_theme_constant_override("separation", 6)
	right.add_child(actions)
	error.add_theme_font_size_override("font_size", 13)
	error.add_theme_color_override("font_color", Color("#ff8a70"))
	right.add_child(error)
	line_box.crafted.connect(_on_line_crafted)
	right.add_child(line_box)


func tablets() -> Array:
	return hud.main.player.tablets


func picked() -> Dictionary:
	for t in tablets():
		if t.uid == sel:
			return t
	return {}


const TINTS := [Color("#5a7fd0"), Color("#c0607e"), Color("#d08a40"), Color("#52a86c"), Color("#9468d0"), Color("#bfae4c"), Color("#44aeb8"), Color("#cc6450")]


## a color per tablet by its place in the list, so neighbours on the board read apart
func tint(t: Dictionary) -> Color:
	return TINTS[maxi(0, tablets().find(t)) % TINTS.size()]


func refresh() -> void:
	if not visible:
		return
	var p: Player = hud.main.player
	var t := picked()
	if t.is_empty():
		sel = ""
	used.text = "使用マス %d / %d　　置いたルーンタブレット %d　所持 %d / %d" % [Tablets.used_cells(p.tablets), Tablets.SIZE * Tablets.SIZE,
		p.tablets.filter(func(x): return x.placed).size(), p.tablets.size(), Tablets.MAX_OWNED]
	var st := Tablets.stats(p.tablets)
	totals.text = "盤の能力：" + ("なし" if st.is_empty() else "、".join(PackedStringArray(st.keys().map(func(k): return Data.affix(k).fmt % st[k]))))
	clear(list)
	if p.tablets.is_empty():
		list.add_child(sub("ルーンタブレットはまだない（ボスが落とす）"))
	for x in p.tablets:
		var on: bool = x.uid == sel
		var mods := "、".join(PackedStringArray(x.mods.keys().map(func(k): return Data.affix(k).fmt % x.mods[k])))
		var text := "%s（%dマス）%s\n%s" % [Tablets.name_of(x), Tablets.cell_count(x), "　設置中" if x.placed else "", mods if mods != "" else "能力なし"]
		var card := SkillUI.card(text, Color("#0e2026") if on else Color("#12100c"), Tablets.color_of(x) if on else (tint(x) if x.placed else Color("#3a3024")),
			Tablets.color_of(x) if Tablets.is_unique(x) else (Color("#e8f4f8") if on else Color("#c8c0b0")), 2 if on else 1)
		card.custom_minimum_size = Vector2(196, 52)
		card.clip_text = true
		card.pressed.connect(pick.bind(x.uid))
		hover(card, Tablets.lines(x))
		list.add_child(card)
	clear(actions)
	if t.is_empty():
		info.text = "ルーンタブレットを選ぶと、ここで能力を刻めます。"
	else:
		info.text = "選択中：%s　向き %d°　（%s）" % [Tablets.name_of(t), rot * 90, "ユニーク・刻めない" if Tablets.is_unique(t) else "%d / %d 行" % [t.mods.size(), Tablets.max_mods(t)]]
		var turn := Button.new()
		turn.text = "回転 (R)"
		turn.pressed.connect(turn_picked)
		actions.add_child(turn)
		for c in [] if Tablets.is_unique(t) else CRAFTS:
			var cd := Data.currency(c[0])
			var b := Button.new()
			b.text = "%s %s %d" % [c[1], cd.icon, p.cur[c[0]]]
			b.add_theme_color_override("font_color", cd.color)
			b.disabled = p.cur[c[0]] <= 0
			b.tooltip_text = "%sを1つ使う" % cd.name
			b.pressed.connect(craft.bind(c[0]))
			actions.add_child(b)
		var off := Button.new()
		off.text = "外す" if t.placed else ("本当に砕く？" if confirm_shatter == t.uid else "砕く")
		off.tooltip_text = "盤から外す" if t.placed else "砕いて灰燼の欠片 %d にする" % Tablets.shard_value(t)
		off.pressed.connect(take_off.bind(t.uid) if t.placed else shatter)
		actions.add_child(off)
	line_box.show_for(p, {} if Tablets.is_unique(t) else t)
	board.queue_redraw()


func pick(uid: String) -> void:
	sel = "" if sel == uid else uid
	var t := picked()
	rot = int(t.get("rot", 0))
	error.text = ""
	refresh()


## turn the picked tablet; one already on the board turns where it lies if it still fits
func turn_picked() -> void:
	var t := picked()
	if t.is_empty():
		return
	rot = (rot + 1) % 4
	if t.placed and Tablets.place(tablets(), t, t.x, t.y, rot) == "":
		changed()
	refresh()


## set the picked tablet at cell `c` (its top-left there); a click on another tablet picks that one instead
func click_cell(c: Vector2i) -> void:
	var occ := Tablets.occupancy(tablets())
	var t := picked()
	if t.is_empty() or (occ.has(c) and occ[c] != sel):
		if occ.has(c):
			pick(occ[c])
		return
	if occ.get(c, "") == sel and t.placed and rot == t.rot:
		sel = ""
		refresh()
		return
	var err := Tablets.place(tablets(), t, c.x, c.y, rot)
	error.text = err
	if err == "":
		changed()
	refresh()


func right_cell(c: Vector2i) -> void:
	var occ := Tablets.occupancy(tablets())
	if occ.has(c):
		take_off(occ[c])
	elif sel != "":
		sel = ""
		refresh()


func take_off(uid: String) -> void:
	for t in tablets():
		if t.uid == uid:
			t.placed = false
	changed()
	refresh()


func shatter() -> void:
	var t := picked()
	if t.is_empty() or t.placed:
		return
	if Tablets.is_unique(t) and confirm_shatter != t.uid:   # a unique takes a second press
		confirm_shatter = t.uid
		refresh()
		return
	confirm_shatter = ""
	var p: Player = hud.main.player
	p.cur.ember += Tablets.shard_value(t)
	p.tablets.erase(t)
	hud.message("%s を砕いた（+%d 灰燼の欠片）" % [Tablets.name_of(t), Tablets.shard_value(t)], Color("#ffcf3a"))
	sel = ""
	refresh()


func craft(k: String) -> void:
	var t := picked()
	var p: Player = hud.main.player
	if t.is_empty() or p.cur[k] <= 0:
		return
	error.text = Tablets.craft(k, t)
	if error.text == "":
		p.cur[k] -= 1
		changed()
		hud.show_tip(Tablets.lines(t))
	refresh()


func _on_line_crafted() -> void:
	changed()
	hud.show_tip(Tablets.lines(line_box.target))
	refresh()


## the board changed: the stats follow
func changed() -> void:
	hud.main.player.recalc()
	hud.refresh_inventory()


func _input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_R:
		turn_picked()
		get_viewport().set_input_as_handled()


## the 6x6 board: placed tablets in their colors, and where the picked one would go under the mouse
class Board extends Control:
	var ui: TabletUI
	var hover := Vector2i(-1, -1)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseMotion:
			var c := _cell(e.position)
			if c != hover:
				hover = c
				_tip()
				queue_redraw()
		elif e is InputEventMouseButton and e.pressed:
			var c := _cell(e.position)
			if c.x < 0:
				return
			if e.button_index == MOUSE_BUTTON_LEFT:
				ui.click_cell(c)
			elif e.button_index == MOUSE_BUTTON_RIGHT:
				ui.right_cell(c)
			accept_event()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT:
			hover = Vector2i(-1, -1)
			ui.hud.hide_tip()
			queue_redraw()

	func _cell(at: Vector2) -> Vector2i:
		var c := Vector2i(floori(at.x / TabletUI.CELL), floori(at.y / TabletUI.CELL))
		return c if c.x >= 0 and c.y >= 0 and c.x < Tablets.SIZE and c.y < Tablets.SIZE else Vector2i(-1, -1)

	## the tablet under the mouse shows its lines, unless one is being set
	func _tip() -> void:
		var occ := Tablets.occupancy(ui.tablets())
		if ui.sel == "" and occ.has(hover):
			for t in ui.tablets():
				if t.uid == occ[hover]:
					ui.hud.show_tip(Tablets.lines(t))
		else:
			ui.hud.hide_tip()

	func _rect(c: Vector2i, inset := 2.0) -> Rect2:
		return Rect2(Vector2(c) * TabletUI.CELL + Vector2.ONE * inset, Vector2.ONE * (TabletUI.CELL - inset * 2))

	func _draw() -> void:
		var s := TabletUI.CELL
		for y in Tablets.SIZE:
			for x in Tablets.SIZE:
				draw_rect(_rect(Vector2i(x, y)), Color("#16130f"))
				draw_rect(_rect(Vector2i(x, y)), Color("#3a3226"), false, 1.0)
		for t in ui.tablets():
			if not t.placed:
				continue
			var col := ui.tint(t)
			var cells := Tablets.cells_at(t, t.x, t.y, t.rot)
			for c in cells:
				draw_rect(_rect(c, 3.0), col.darkened(0.35))
				draw_rect(_rect(c, 3.0), Tablets.COLOR if t.uid == ui.sel else col.lightened(0.2), false, 2.0 if t.uid == ui.sel else 1.0)
				# runes: a small mark per carved line, on the first cell
			var first: Vector2i = cells[0]
			for i in t.mods.size():
				draw_circle(Vector2(first) * s + Vector2(12 + i * 10, 12), 3.0, Color("#e8fbff"))
		var t := ui.picked()
		if not t.is_empty() and hover.x >= 0:
			var ok := Tablets.fit(ui.tablets(), t, hover.x, hover.y, ui.rot) == ""
			for c in Tablets.cells_at(t, hover.x, hover.y, ui.rot):
				if c.x < Tablets.SIZE and c.y < Tablets.SIZE:
					draw_rect(_rect(c, 4.0), Color(0.4, 1.0, 0.8, 0.35) if ok else Color(1.0, 0.3, 0.25, 0.35))
