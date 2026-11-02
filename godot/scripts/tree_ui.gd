class_name TreeUI
extends BasePanel
## Passive tree (T): spend the point each level gives on nodes joined to what is already taken. Clicking a far node
## takes the shortest way there; right click gives a node back (free) if the rest stays joined to the start.

var points := Label.new()
var reset := Button.new()
var view := TreeView.new()
var summary := VBoxContainer.new()


func _title() -> String:
	return "パッシブツリー"


func _hint() -> String:
	return "レベルが上がるたびにポイントが1つ増える。振り直しは無料"


func _build() -> void:
	var top := HBoxContainer.new()
	body.add_child(top)
	points.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	points.add_theme_font_size_override("font_size", 15)
	points.add_theme_color_override("font_color", Color("#ffe27a"))
	top.add_child(points)
	reset.text = "すべて外す"
	reset.add_theme_font_size_override("font_size", 13)
	reset.pressed.connect(_reset)
	top.add_child(reset)
	body.add_child(sub("左クリック：取得（離れたノードは道筋ごと）　右クリック：外す　ドラッグ：移動　ホイール：拡大・縮小", 12, Color("#8a7a60")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	view.ui = self
	view.custom_minimum_size = Vector2(880, 600)
	view.clip_contents = true
	row.add_child(view)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(230, 0)
	side.add_child(sub("取得したボーナス", 15, Color("#f0d8a0")))
	summary.add_theme_constant_override("separation", 2)
	side.add_child(summary)
	row.add_child(side)


func refresh() -> void:
	if not visible:
		return
	var p: Player = hud.main.player
	points.text = "残りポイント %d　／　取得 %d ノード" % [p.tree_free(), p.tree.size()]
	reset.disabled = p.tree.is_empty()
	clear(summary)
	var ls := PassiveTree.lines(PassiveTree.stats(p.tree))
	if ls.is_empty():
		summary.add_child(sub("まだ何も取得していない", 13, Color("#776a58")))
	for l in ls:
		summary.add_child(sub(l, 13, Color("#e8d8b0")))
	view.queue_redraw()


func open_close() -> void:
	super()
	if visible:
		view.recenter()


## take `id` and whatever joins it to the tree; false if it is out of reach or too far for the points left
func _take(id: String) -> bool:
	var p: Player = hud.main.player
	var path := PassiveTree.path_to(p.tree, p.cls, id)
	if path.is_empty() or path.size() > p.tree_free():
		return false
	p.tree.append_array(path)
	_changed()
	return true


func _refund(id: String) -> bool:
	var p: Player = hud.main.player
	if not PassiveTree.can_refund(p.tree, p.cls, id):
		return false
	p.tree.erase(id)
	_changed()
	return true


func _reset() -> void:
	var p: Player = hud.main.player
	if p.tree.is_empty():
		return
	p.tree.clear()
	_changed()


func _changed() -> void:
	hud.main.player.recalc()
	hud.main.save_game()
	refresh()
	view.show_hover_tip()


## the node tooltip
func tip_lines(id: String) -> Array:
	var p: Player = hud.main.player
	var n := PassiveTree.node(id)
	var col: Color = PassiveTree.SECTORS[n.sector].color
	var kind: String = {"small": "", "notable": "　注目ノード", "keystone": "　キーストーン", "start": "　起点"}[n.kind]
	var out: Array = [[n.name + kind, col.lightened(0.2), 16]]
	for l in PassiveTree.lines(n.stats):
		out.append([l, Color("#e8d8b0"), 14])
	if n.kind == "start":
		out.append(["ここから振り始める" if id == PassiveTree.start_id(p.cls) else "ほかのベースキャラの起点（取得できない）", Color("#a89878"), 13])
	elif id in p.tree:
		out.append(["右クリックで外す" if PassiveTree.can_refund(p.tree, p.cls, id) else "外すとつながりが切れるので、先の方から外す", Color("#a89878"), 13])
	else:
		var path := PassiveTree.path_to(p.tree, p.cls, id)
		if path.size() > p.tree_free():
			out.append(["ポイントが足りない（%d 必要）" % path.size(), Color("#ff8a6a"), 13])
		else:
			out.append(["クリックで取得（%d ポイント）" % path.size(), Color("#ffe27a"), 13])
	return out


## the tree drawn as a pannable, zoomable web
class TreeView extends Control:
	const UNIT := 28.0
	const RADIUS := {"small": 6.5, "notable": 11.0, "keystone": 15.0, "start": 13.0}
	var ui: TreeUI
	var pan := Vector2.ZERO
	var zoom := 1.0
	var hover := ""
	var _press := Vector2.ZERO
	var _pressed := false
	var _dragged := false

	func recenter() -> void:
		zoom = 1.0
		pan = Vector2.ZERO
		queue_redraw()

	func to_screen(p: Vector2) -> Vector2:
		return size / 2.0 + pan + p * UNIT * zoom

	func node_at(m: Vector2) -> String:
		var best := ""
		var bd := INF
		for id in PassiveTree.order():
			var n := PassiveTree.node(id)
			var d := to_screen(n.pos).distance_to(m)
			if d < (RADIUS[n.kind] + 4.0) * maxf(zoom, 0.8) and d < bd:
				best = id
				bd = d
		return best

	func show_hover_tip() -> void:
		if hover != "" and ui.visible:
			ui.hud.show_tip(ui.tip_lines(hover))
		else:
			ui.hud.hide_tip()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton:
			if e.button_index == MOUSE_BUTTON_LEFT:
				if e.pressed:
					_pressed = true
					_dragged = false
					_press = e.position
				else:
					if _pressed and not _dragged and hover != "":
						var p: Player = ui.hud.main.player
						if hover in p.tree:
							ui._refund(hover)
						else:
							ui._take(hover)
					_pressed = false
				accept_event()
			elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
				if hover != "":
					ui._refund(hover)
				accept_event()
			elif e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				var z := clampf(zoom * (1.15 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.6, 2.5)
				# keep the point under the mouse where it is
				var anchor: Vector2 = e.position - size / 2.0 - pan
				pan += anchor - anchor * (z / zoom)
				zoom = z
				queue_redraw()
				accept_event()
		elif e is InputEventMouseMotion:
			if _pressed and (_dragged or e.position.distance_to(_press) > 5.0):
				_dragged = true
				pan += e.relative
				queue_redraw()
			var h := node_at(e.position)
			if h != hover:
				hover = h
				queue_redraw()
			show_hover_tip()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT:
			hover = ""
			_pressed = false
			ui.hud.hide_tip()
			queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#0a0806"))
		var c := to_screen(Vector2.ZERO)
		for r in [PassiveTree.R_INNER, PassiveTree.R_OUTER]:
			draw_arc(c, r * UNIT * zoom, 0, TAU, 96, Color(1, 0.8, 0.5, 0.04), 10.0 * zoom)
		var p: Player = ui.hud.main.player
		var taken := {PassiveTree.start_id(p.cls): true}
		for id in p.tree:
			taken[id] = true
		var preview := {}
		if hover != "" and not taken.has(hover):
			for id in PassiveTree.path_to(p.tree, p.cls, hover):
				preview[id] = true
		var afford := preview.size() <= p.tree_free()
		# links
		for id in PassiveTree.order():
			var n := PassiveTree.node(id)
			for nb in n.links:
				if nb < id:
					continue
				var a := to_screen(n.pos)
				var b := to_screen(PassiveTree.node(nb).pos)
				var col := Color("#3a3024")
				var w := 2.0
				if taken.has(id) and taken.has(nb):
					col = Color("#ffcf6a")
					w = 4.0
				elif (preview.has(id) or taken.has(id)) and (preview.has(nb) or taken.has(nb)):
					col = Color("#fff0b0") if afford else Color("#c86a50")
					w = 3.0
				elif taken.has(id) or taken.has(nb):
					col = Color("#7a6440")
				draw_line(a, b, col, w * zoom, true)
		# nodes
		var font: Font = Data.ui_font
		for id in PassiveTree.order():
			var n := PassiveTree.node(id)
			var at := to_screen(n.pos)
			var r: float = RADIUS[n.kind] * zoom
			var sc: Color = PassiveTree.SECTORS[n.sector].color
			var own := taken.has(id)
			var reach: bool = not own and n.kind != "start" and n.links.any(func(x): return taken.has(x))
			var fill := sc.darkened(0.15) if own else (Color("#2a2016") if reach else Color("#15110c"))
			var rim := Color("#ffe8a0") if own else (sc if reach else Color("#4a3e30"))
			if preview.has(id):
				rim = Color("#fff0b0") if afford else Color("#ff7a5a")
			if id == hover:
				rim = Color.WHITE
			match n.kind:
				"keystone":
					var pts := PackedVector2Array()
					for k in 8:
						pts.append(at + Vector2.from_angle(TAU * k / 8.0 + TAU / 16.0) * r)
					draw_colored_polygon(pts, fill)
					pts.append(pts[0])
					draw_polyline(pts, rim, 2.5 * zoom, true)
				"start":
					var is_mine: bool = n.cls == p.cls
					draw_circle(at, r, Color("#2a1e12") if is_mine else Color("#120e0a"))
					draw_arc(at, r, 0, TAU, 32, sc if is_mine else Color("#4a3e30"), 3.0 * zoom, true)
					var icon: String = Data.base_class(n.cls).icon
					draw_string(font, at + Vector2(-8, 6) * zoom, icon, HORIZONTAL_ALIGNMENT_CENTER, 16 * zoom, int(15 * zoom),
						sc if is_mine else Color("#5a4e40"))
				_:
					draw_circle(at, r, fill)
					draw_arc(at, r, 0, TAU, 24, rim, (2.5 if n.kind == "notable" else 1.6) * zoom, true)
					if n.kind == "notable":
						draw_arc(at, r * 0.6, 0, TAU, 20, rim.darkened(0.3), 1.2 * zoom, true)
			if n.kind in ["notable", "keystone"] and zoom >= 0.8:
				var fs := int(12 * zoom)
				var tw := font.get_string_size(n.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string_outline(font, at + Vector2(-tw / 2.0, r + 14 * zoom), n.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
				draw_string(font, at + Vector2(-tw / 2.0, r + 14 * zoom), n.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					Color("#ffe8b0") if own else Color("#b8a888"))
