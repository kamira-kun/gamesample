class_name TreeUI
extends BasePanel
## Passive tree (T): spend the point each level gives on nodes joined to what is already taken. Clicking a far node
## takes the shortest way there; right click gives a node back (free) if the rest stays joined to the start.
## The side holds the jewels (Jewels): pick one, then click a socket of its kind to set it there (a socket not yet
## taken is taken on the way); right click a filled socket to take the jewel out. Crafting currencies work on the
## picked jewel while it is out of the tree.

const CRAFTS := [["transmute", "変容"], ["ascend", "昇華"], ["chaos", "混沌"], ["whet", "鍛錬"], ["purify", "浄化"], ["divine", "神秘"]]

var points := Label.new()
var search := LineEdit.new()
var reset := Button.new()
var view := TreeView.new()
var summary := VBoxContainer.new()
var jewel_head := Label.new()
var jewel_list := VBoxContainer.new()
var info := Label.new()
var actions := GridContainer.new()
var error := Label.new()
var sel := ""      # uid of the picked jewel
var rev := 0       # bumped whenever the tree or its jewels change, so the view knows its caches are stale


func _title() -> String:
	return "パッシブツリー"


func _hint() -> String:
	return "レベルが上がるたびにポイントが1つ増える。振り直しは無料"


func _build() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	body.add_child(top)
	points.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	points.add_theme_font_size_override("font_size", 15)
	points.add_theme_color_override("font_color", Color("#ffe27a"))
	top.add_child(points)
	search.placeholder_text = "ノード検索（名前・効果）"
	search.custom_minimum_size = Vector2(220, 0)
	search.text_changed.connect(func(_t): view.search_changed())
	top.add_child(search)
	for b in [["起点へ", func(): view.recenter()], ["全体", func(): view.fit_all()]]:
		var bt := Button.new()
		bt.text = b[0]
		bt.add_theme_font_size_override("font_size", 13)
		bt.pressed.connect(b[1])
		top.add_child(bt)
	reset.text = "すべて外す"
	reset.add_theme_font_size_override("font_size", 13)
	reset.pressed.connect(_reset)
	top.add_child(reset)
	body.add_child(sub("左クリック：取得（離れたノードは道筋ごと）　右クリック：外す　ドラッグ：移動　ホイール：拡大・縮小　ジュエルを選んで台座をクリック：はめる",
		12, Color("#8a7a60")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	view.ui = self
	view.custom_minimum_size = Vector2(860, 620)
	view.clip_contents = true
	row.add_child(view)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(300, 0)
	side.add_theme_constant_override("separation", 6)
	row.add_child(side)
	side.add_child(sub("取得したボーナス", 15, Color("#f0d8a0")))
	var ss := ScrollContainer.new()
	ss.custom_minimum_size = Vector2(300, 170)
	ss.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	summary.add_theme_constant_override("separation", 2)
	ss.add_child(summary)
	side.add_child(ss)
	jewel_head.add_theme_font_size_override("font_size", 15)
	jewel_head.add_theme_color_override("font_color", Color("#f0d8a0"))
	side.add_child(jewel_head)
	var js := ScrollContainer.new()
	js.custom_minimum_size = Vector2(300, 200)
	js.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	jewel_list.add_theme_constant_override("separation", 4)
	js.add_child(jewel_list)
	side.add_child(js)
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", Color("#e8dcc0"))
	info.custom_minimum_size = Vector2(300, 0)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(info)
	actions.columns = 3
	actions.add_theme_constant_override("h_separation", 4)
	actions.add_theme_constant_override("v_separation", 4)
	side.add_child(actions)
	error.add_theme_font_size_override("font_size", 12)
	error.add_theme_color_override("font_color", Color("#ff8a70"))
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error.custom_minimum_size = Vector2(300, 0)
	side.add_child(error)


func refresh() -> void:
	if not visible:
		return
	var p: Player = hud.main.player
	points.text = "残りポイント %d　／　取得 %d ノード　（全 %d）" % [p.tree_free(), p.tree.size(), PassiveTree.base_count()]
	reset.disabled = p.tree.is_empty()
	clear(summary)
	var st := PassiveTree.stats(p.tree)
	var js := Jewels.stats(p.jewels, p.tree)
	for k in js:
		st[k] = st.get(k, 0) + js[k]
	var ls := PassiveTree.lines(st)
	if ls.is_empty():
		summary.add_child(sub("まだ何も取得していない", 13, Color("#776a58")))
	for l in ls:
		summary.add_child(sub(l, 13, Color("#e8d8b0")))
	_refresh_jewels(p)
	view.queue_redraw()


func picked() -> Dictionary:
	for j in hud.main.player.jewels:
		if j.uid == sel:
			return j
	return {}


func _refresh_jewels(p: Player) -> void:
	var j := picked()
	if j.is_empty():
		sel = ""
	jewel_head.text = "ジュエル（%d / %d）　台座 %d" % [p.jewels.size(), Jewels.MAX_OWNED, p.jewels.filter(func(x): return x.socket != "").size()]
	clear(jewel_list)
	if p.jewels.is_empty():
		jewel_list.add_child(sub("ジュエルはまだない（敵が落とす）"))
	for x in p.jewels:
		var on: bool = x.uid == sel
		var ring := Jewels.is_ring(x)
		var col: Color = Data.RARITY[int(x.rarity)].color
		var text := "%s %s%s" % ["❂" if ring else "◆", x.name, "　［台座］" if x.socket != "" else ""]
		var card := SkillUI.card(text, Color("#241a26") if on else Color("#12100c"), (Jewels.RING_COLOR if ring else Jewels.COLOR) if on else Color("#3a3024"),
			col, 2 if on else 1)
		card.custom_minimum_size = Vector2(286, 28)
		card.clip_text = true
		card.pressed.connect(pick.bind(x.uid))
		hover(card, Jewels.lines(x))
		jewel_list.add_child(card)
	clear(actions)
	if j.is_empty():
		info.text = "ジュエルを選ぶと、ツリーの台座にはめたりクラフトしたりできます。"
		return
	info.text = "選択中：%s　→ %sをクリックではめる" % [j.name, "環晶の大台座（最外周の六角）" if Jewels.is_ring(j) else "燈晶の台座（ひし形）"]
	if j.socket == "":
		for c in CRAFTS:
			var cd := Data.currency(c[0])
			var b := Button.new()
			b.text = "%s %s %d" % [c[1], cd.icon, p.cur[c[0]]]
			b.add_theme_font_size_override("font_size", 12)
			b.add_theme_color_override("font_color", cd.color)
			b.disabled = p.cur[c[0]] <= 0
			b.tooltip_text = "%s：%s" % [cd.name, cd.desc]
			b.pressed.connect(craft.bind(c[0]))
			actions.add_child(b)
	var off := Button.new()
	off.add_theme_font_size_override("font_size", 12)
	if j.socket != "":
		off.text = "台座から外す"
		off.pressed.connect(unsocket.bind(j.uid))
	else:
		off.text = "砕く（%d）" % Jewels.shard_value(j)
		off.tooltip_text = "砕いて灰燼の欠片 %d にする" % Jewels.shard_value(j)
		off.pressed.connect(shatter)
	actions.add_child(off)


func pick(uid: String) -> void:
	sel = "" if sel == uid else uid
	error.text = ""
	refresh()


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


## give a node back; a jewel sitting in it comes out
func _refund(id: String) -> bool:
	var p: Player = hud.main.player
	if not PassiveTree.can_refund(p.tree, p.cls, id):
		return false
	p.tree.erase(id)
	var j := Jewels.at_socket(p.jewels, id)
	if not j.is_empty():
		j.socket = ""
	_changed()
	return true


func _reset() -> void:
	var p: Player = hud.main.player
	if p.tree.is_empty():
		return
	p.tree.clear()
	for j in p.jewels:
		j.socket = ""
	_changed()


## set jewel `uid` in socket `id` (taking the socket on the way if need be); a jewel already there comes out.
## Returns an error message, or ""
func socket_jewel(uid: String, id: String) -> String:
	var p: Player = hud.main.player
	var j := {}
	for x in p.jewels:
		if x.uid == uid:
			j = x
	var n := PassiveTree.node(id)
	if j.is_empty() or n.is_empty():
		return "はめられない"
	if n.kind != Jewels.socket_kind(j):
		return "環晶は環晶の大台座に、燈晶は燈晶の台座にはめる"
	if j.socket == id:
		return ""
	if not id in p.tree and not _take(id):
		return "台座まで届かない（ポイントが足りない）"
	if j.socket != "":
		unsocket(j.uid)
	var old := Jewels.at_socket(p.jewels, id)
	if not old.is_empty():
		unsocket(old.uid)
	j.socket = id
	_changed()
	return ""


## take a jewel out of the tree; a ring jewel's ring goes with it (its points come back, and a jewel in its
## small socket comes out too)
func unsocket(uid: String) -> void:
	var p: Player = hud.main.player
	for j in p.jewels:
		if j.uid != uid or j.socket == "":
			continue
		if Jewels.is_ring(j):
			var ids := PassiveTree.ring_ids(j.socket)
			p.tree = p.tree.filter(func(t): return not t in ids)
			for x in p.jewels:
				if x.socket in ids:
					x.socket = ""
		j.socket = ""
	_changed()


func craft(k: String) -> void:
	var j := picked()
	var p: Player = hud.main.player
	if j.is_empty() or p.cur[k] <= 0:
		return
	error.text = Jewels.craft(k, j)
	if error.text == "":
		p.cur[k] -= 1
		hud.show_tip(Jewels.lines(j))
		hud.main.save_game()
	refresh()


func shatter() -> void:
	var j := picked()
	if j.is_empty() or j.socket != "":
		return
	var p: Player = hud.main.player
	p.cur.ember += Jewels.shard_value(j)
	p.jewels.erase(j)
	hud.message("%s を砕いた（+%d 灰燼の欠片）" % [j.name, Jewels.shard_value(j)], Color("#ffcf3a"))
	sel = ""
	hud.main.save_game()
	refresh()


func _changed() -> void:
	rev += 1
	hud.main.player.recalc()
	hud.main.save_game()
	refresh()
	view.show_hover_tip()


## a click on node `id`: with a jewel picked and a socket of its kind, set it; otherwise take or give back
func click(id: String) -> void:
	var p: Player = hud.main.player
	var j := picked()
	if not j.is_empty() and PassiveTree.node(id).kind == Jewels.socket_kind(j):
		error.text = socket_jewel(j.uid, id)
		refresh()
	elif id in p.tree:
		_refund(id)
	else:
		_take(id)


func right_click(id: String) -> void:
	var j := Jewels.at_socket(hud.main.player.jewels, id)
	if not j.is_empty():
		unsocket(j.uid)
	else:
		_refund(id)


## the node tooltip
func tip_lines(id: String) -> Array:
	var p: Player = hud.main.player
	var n := PassiveTree.node(id)
	var col: Color = Jewels.RING_COLOR if n.has("ring") else PassiveTree.SECTORS[n.sector].color
	var kind: String = PassiveTree.KIND_NAMES[n.kind]
	var out: Array = [[n.name + ("" if kind == "" or kind == n.name else "　" + kind), col.lightened(0.2), 16]]
	for l in PassiveTree.lines(n.stats):
		out.append([l, Color("#e8d8b0"), 14])
	if n.kind in ["socket", "ring_socket"]:
		var j := Jewels.at_socket(p.jewels, id)
		if j.is_empty():
			out.append(["空き：%sをはめられる" % ("環晶" if n.kind == "ring_socket" else "燈晶"), Color("#a89878"), 13])
		else:
			for l in Jewels.lines(j):
				out.append(l)
			out.append(["右クリックで外す", Color("#a89878"), 13])
	if n.kind == "start":
		out.append(["ここから振り始める" if id == PassiveTree.start_id(p.cls) else "ほかのベースキャラの起点（取得できない）", Color("#a89878"), 13])
	elif id in p.tree:
		out.append(["クリックで外す" if PassiveTree.can_refund(p.tree, p.cls, id) else "外すとつながりが切れるので、先の方から外す", Color("#a89878"), 13])
	else:
		var path := view.preview_path()
		if path.size() > p.tree_free():
			out.append(["ポイントが足りない（%d 必要）" % path.size(), Color("#ff8a6a"), 13])
		else:
			out.append(["クリックで取得（%d ポイント）" % path.size(), Color("#ffe27a"), 13])
	return out


## the tree drawn as a pannable, zoomable web. Only what is on screen is drawn, links go out in a few batched
## calls, and hit tests look in a coarse grid instead of at every node
class TreeView extends Control:
	const UNIT := 28.0
	const RADIUS := {"small": 6.5, "notable": 11.0, "keystone": 15.0, "start": 13.0, "socket": 10.0, "ring_socket": 15.0}
	const CELL := 2.0       # grid cell, in tree units
	const ZOOM_MIN := 0.15
	const ZOOM_MAX := 2.5
	var ui: TreeUI
	var pan := Vector2.ZERO
	var zoom := 1.0
	var hover := ""
	var _press := Vector2.ZERO
	var _pressed := false
	var _dragged := false
	var _grid := {}
	var _grid_for := ""
	var _path: Array = []
	var _path_for := ""
	var _found := {}

	## back to the character's start
	func recenter() -> void:
		zoom = 1.0
		var p: Player = ui.hud.main.player
		pan = -PassiveTree.node(PassiveTree.start_id(p.cls)).pos * UNIT * zoom
		queue_redraw()

	## the whole web in view
	func fit_all() -> void:
		var s := size if size.x > 0 else custom_minimum_size
		zoom = clampf(minf(s.x, s.y) / ((PassiveTree.R_OUTER + 9.0) * 2.0 * UNIT), ZOOM_MIN, ZOOM_MAX)
		pan = Vector2.ZERO
		queue_redraw()

	func to_screen(p: Vector2) -> Vector2:
		return size / 2.0 + pan + p * UNIT * zoom

	func to_tree(m: Vector2) -> Vector2:
		return (m - size / 2.0 - pan) / (UNIT * zoom)

	func _cell(p: Vector2) -> Vector2i:
		return Vector2i(floori(p.x / CELL), floori(p.y / CELL))

	## the hit-test grid, rebuilt when ring jewels change the web
	func grid() -> Dictionary:
		var key := "%d/%s" % [PassiveTree.order().size(), PassiveTree._ring_key]
		if key != _grid_for:
			_grid = {}
			for id in PassiveTree.order():
				var c := _cell(PassiveTree.node(id).pos)
				if not _grid.has(c):
					_grid[c] = []
				_grid[c].append(id)
			_grid_for = key
		return _grid

	func node_at(m: Vector2) -> String:
		var g := grid()
		var t := to_tree(m)
		var c := _cell(t)
		var best := ""
		var bd := INF
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for id in g.get(c + Vector2i(dx, dy), []):
					var n := PassiveTree.node(id)
					var d := to_screen(n.pos).distance_to(m)
					if d < (RADIUS[n.kind] + 4.0) * maxf(zoom, 0.8) and d < bd:
						best = id
						bd = d
		return best

	## the nodes a click on the hovered node would take, cached until the hover or the tree changes
	func preview_path() -> Array:
		var p: Player = ui.hud.main.player
		var key := "%s/%d/%d" % [hover, ui.rev, p.tree.size()]
		if key != _path_for:
			_path = [] if hover == "" or hover in p.tree else PassiveTree.path_to(p.tree, p.cls, hover)
			_path_for = key
		return _path

	func search_changed() -> void:
		_found = {}
		var q := ui.search.text.strip_edges()
		if q != "":
			for id in PassiveTree.order():
				var n := PassiveTree.node(id)
				if q in n.name or PassiveTree.lines(n.stats).any(func(l): return q in l):
					_found[id] = true
		queue_redraw()

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
						ui.click(hover)
					_pressed = false
				accept_event()
			elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
				if hover != "":
					ui.right_click(hover)
				accept_event()
			elif e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				var z := clampf(zoom * (1.15 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), ZOOM_MIN, ZOOM_MAX)
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
		for k in range(1, PassiveTree.LAYERS + 1):
			draw_arc(c, (PassiveTree.R_HUB + PassiveTree.LAYER_GAP * k) * UNIT * zoom, 0, TAU, 128, Color(1, 0.8, 0.5, 0.03), 40.0 * zoom)
		var p: Player = ui.hud.main.player
		var taken := {PassiveTree.start_id(p.cls): true}
		for id in p.tree:
			taken[id] = true
		var reach := {}
		for id in taken:
			for nb in PassiveTree.node(id).links:
				if not taken.has(nb):
					reach[nb] = true
		var preview := {}
		for id in preview_path():
			preview[id] = true
		var afford := preview.size() <= p.tree_free()
		var view := Rect2(Vector2(-40, -40), size + Vector2(80, 80))
		# links, batched by look
		var plain := PackedVector2Array()
		var near := PackedVector2Array()
		var own := PackedVector2Array()
		var path := PackedVector2Array()
		for id in PassiveTree.order():
			var n := PassiveTree.node(id)
			var a := to_screen(n.pos)
			for nb in n.links:
				if nb < id:
					continue
				var b := to_screen(PassiveTree.node(nb).pos)
				if not view.has_point(a) and not view.has_point(b) and not view.intersects(Rect2(a, Vector2.ZERO).expand(b)):
					continue
				var arr := plain
				if taken.has(id) and taken.has(nb):
					arr = own
				elif (preview.has(id) or taken.has(id)) and (preview.has(nb) or taken.has(nb)):
					arr = path
				elif taken.has(id) or taken.has(nb):
					arr = near
				arr.append(a)
				arr.append(b)
		var lw := maxf(1.0, 2.0 * zoom)
		if not plain.is_empty():
			draw_multiline(plain, Color("#3a3024"), lw)
		if not near.is_empty():
			draw_multiline(near, Color("#7a6440"), lw)
		if not own.is_empty():
			draw_multiline(own, Color("#ffcf6a"), maxf(1.5, 4.0 * zoom))
		if not path.is_empty():
			draw_multiline(path, Color("#fff0b0") if afford else Color("#c86a50"), maxf(1.5, 3.0 * zoom))
		# nodes
		var font: Font = Data.ui_font
		var jewel_at := {}
		for j in p.jewels:
			if j.socket != "":
				jewel_at[j.socket] = j
		for id in PassiveTree.order():
			var n := PassiveTree.node(id)
			var at := to_screen(n.pos)
			if not view.has_point(at):
				continue
			var r: float = RADIUS[n.kind] * zoom
			var sc: Color = Jewels.RING_COLOR if n.has("ring") else PassiveTree.SECTORS[n.sector].color
			var mine := taken.has(id)
			var can: bool = reach.has(id) and n.kind != "start"
			var fill := sc.darkened(0.15) if mine else (Color("#2a2016") if can else Color("#15110c"))
			var rim := Color("#ffe8a0") if mine else (sc if can else Color("#4a3e30"))
			if preview.has(id):
				rim = Color("#fff0b0") if afford else Color("#ff7a5a")
			if id == hover:
				rim = Color.WHITE
			if _found.has(id):
				draw_circle(at, r + 6.0 * maxf(zoom, 0.5), Color(1.0, 0.9, 0.3, 0.45))
			var w := maxf(1.0, (2.5 if n.kind != "small" else 1.6) * zoom)
			match n.kind:
				"keystone", "ring_socket":
					var sides := 8 if n.kind == "keystone" else 6
					var pts := PackedVector2Array()
					for k in sides:
						pts.append(at + Vector2.from_angle(TAU * k / sides + TAU / (sides * 2)) * r)
					var jw: Dictionary = jewel_at.get(id, {})
					draw_colored_polygon(pts, Jewels.RING_COLOR.darkened(0.3) if not jw.is_empty() else fill)
					pts.append(pts[0])
					draw_polyline(pts, rim, w)
				"socket":
					var pts := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)])
					var jw: Dictionary = jewel_at.get(id, {})
					draw_colored_polygon(pts, Data.RARITY[int(jw.rarity)].color.darkened(0.2) if not jw.is_empty() else fill)
					pts.append(pts[0])
					draw_polyline(pts, rim, w)
				"start":
					var is_mine: bool = n.cls == p.cls
					draw_circle(at, r, sc if is_mine else Color("#4a3e30"))
					draw_circle(at, maxf(0.5, r - w), Color("#2a1e12") if is_mine else Color("#120e0a"))
					if zoom >= 0.4:
						var icon: String = Data.base_class(n.cls).icon
						draw_string(font, at + Vector2(-8, 6) * zoom, icon, HORIZONTAL_ALIGNMENT_CENTER, 16 * zoom, int(15 * zoom),
							sc if is_mine else Color("#5a4e40"))
				_:
					draw_circle(at, r, rim)
					draw_circle(at, maxf(0.5, r - w), fill)
					if n.kind == "notable" and zoom >= 0.5:
						draw_arc(at, r * 0.6, 0, TAU, 16, rim.darkened(0.3), maxf(1.0, 1.2 * zoom))
			var label: bool = (n.kind in ["notable", "keystone", "ring_socket"] and zoom >= 0.8) or (n.kind == "keystone" and zoom >= 0.4)
			if label:
				var fs := maxi(10, int(12 * zoom))
				var tw := font.get_string_size(n.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var lp := at + Vector2(-tw / 2.0, r + fs + 2.0)
				draw_string_outline(font, lp, n.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
				draw_string(font, lp, n.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#ffe8b0") if mine else Color("#b8a888"))
