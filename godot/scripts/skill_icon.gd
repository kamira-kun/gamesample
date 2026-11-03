class_name SkillIcon
extends RefCounted
## Vector icons for skills and support gems, drawn on a 32x32 grid and scaled into a rect.
## A skill icon is a beveled frame tinted by the skill's element with a glowing motif of its own;
## a support gem is a faceted stone in the gem's color, cut by what the gem works on.

const LINE := Color(0, 0, 0, 0.85)
const STEEL_L := Color("#f2f5f8")
const STEEL_D := Color("#5a626c")
const GOLD := Color("#e8b848")
const WOOD := Color("#7a4e2c")
const BONE_L := Color("#f6eedc")
const BONE_D := Color("#a08e70")
const STONE_L := Color("#c8b89c")
const STONE_D := Color("#5e5244")
const FIRE := Color("#ff7a2a")
const ICE_L := Color("#ffffff")
const ICE_D := Color("#3a90d0")

# frame colors per element: background, rim, highlight
const PAL := {
	"fire": [Color("#2c0902"), Color("#d0581e"), Color("#ffb060")],
	"cold": [Color("#04182c"), Color("#3a90cc"), Color("#a8e8ff")],
	"lightning": [Color("#140a30"), Color("#7c5ce0"), Color("#d8c4ff")],
	"chaos": [Color("#13061e"), Color("#7c3cac"), Color("#c090f8")],
	"minion": [Color("#081814"), Color("#5a9a88"), Color("#c0f4e4")],
	"curse": [Color("#1e0619"), Color("#a44a9c"), Color("#f4a0e8")],
	"buff": [Color("#221604"), Color("#c89432"), Color("#ffe490")],
	"aura": [Color("#1a1208"), Color("#d8b060"), Color("#fff0c0")],
	"phys": [Color("#1a130c"), Color("#9c7c50"), Color("#f4dcac")],
}

static var _base := Transform2D.IDENTITY
static var _g := Color.WHITE   # glow: the skill's own color


static func element(sk: Dictionary) -> String:
	for t in ["aura", "fire", "cold", "lightning", "chaos", "minion", "curse", "buff"]:
		if t in sk.tags:
			return t
	return "phys"


static func draw(ci: CanvasItem, id: String, rect: Rect2, dim := false) -> void:
	var sk: Dictionary = Data.SKILLS[id]
	var pal: Array = PAL[element(sk)]
	_begin(ci, rect)
	_g = sk.color
	_frame(ci, pal)
	var outer := _base
	_base = _base * Transform2D(0.0, Vector2(0.9, 0.9), 0.0, Vector2(1.6, 1.6))   # keep glows inside the rim
	_home(ci)
	_motif(ci, id)
	_base = outer
	ci.draw_set_transform_matrix(_base)
	_bevel(ci, pal)
	if dim:
		ci.draw_colored_polygon(_chamfer(1.0, 3.5), Color(0, 0, 0, 0.55))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## a support gem; `socket` draws the dark setting behind it
static func draw_gem(ci: CanvasItem, g: Dictionary, rect: Rect2, socket := true) -> void:
	_begin(ci, rect)
	var col: Color = g.color
	var c := Vector2(16, 16)
	if socket:
		ci.draw_circle(c, 15.5, Color("#0a0806"), true, -1.0, true)
		ci.draw_arc(c, 15.0, 0.0, TAU, 32, Color("#6a5638"), 1.4, true)
	for i in 4:
		ci.draw_circle(c, 14.0 - i * 2.0, Color(col, 0.06 + i * 0.03), true, -1.0, true)
	if g.get("awake", false):   # awakened gems wear a gold halo
		ci.draw_arc(c, 14.6 if socket else 15.4, 0.0, TAU, 32, Data.AWAKE_COLOR, 1.6, true)
	var n := _gem_sides(g)
	var sx := 0.7 if n == 4 else 1.0
	var r := 12.5 if socket else 14.5
	var off := PI / n if n % 2 == 0 and n != 4 else 0.0
	var outer := PackedVector2Array()
	var table := PackedVector2Array()
	for i in n:
		var a := -PI / 2.0 + TAU * i / n + off
		outer.append(c + Vector2(cos(a) * sx, sin(a)) * r)
		table.append(c + Vector2(cos(a) * sx, sin(a)) * r * 0.5 + Vector2(-0.6, -0.6))
	for i in n:
		var j := (i + 1) % n
		var mid := (outer[i] + outer[j]) / 2.0 - c
		var light := 0.5 + 0.5 * cos(mid.angle() + 2.3)   # lit from the upper left
		ci.draw_colored_polygon(PackedVector2Array([outer[i], outer[j], table[j], table[i]]),
			col.darkened(0.55).lerp(col.lightened(0.45), light))
	_shade(ci, table, col.lightened(0.6), col)
	for i in n:
		ci.draw_line(outer[i], table[i], Color(col.darkened(0.6), 0.7), 0.6, true)
	ci.draw_polyline(_loop(table), Color(col.lightened(0.7), 0.8), 0.6, true)
	ci.draw_polyline(_loop(outer), LINE, 1.1, true)
	_sparkle(ci, table[0].lerp(c, 0.2) + Vector2(-2.5, 1.5), 3.2, Color.WHITE)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## the gem's cut tells what it works on
static func _gem_sides(g: Dictionary) -> int:
	for t in g.tags:
		match t:
			"projectile", "movement": return 4
			"aoe": return 6
			"minion", "buff": return 5
			"duration": return 8
			"chain", "curse": return 3
	return 8 if g.has("set") or g.has("mul") and g.mul.keys().any(func(k): return String(k).begins_with("m_")) else 6


## a control that draws a skill or gem icon at its left edge (or centered when `side` is 0); it ignores the mouse
class View extends Control:
	var skill := ""
	var gem := {}
	var dim := false
	var mark := ""     # short text drawn over the icon, e.g. a warning
	var lv := 0        # a gem level drawn small in the corner (shown from Lv 2)
	var side := 0.0
	var pad := 5.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var s := side if side > 0.0 else minf(size.x, size.y)
		var r := Rect2(Vector2(pad, (size.y - s) / 2.0) if side > 0.0 else (size - Vector2(s, s)) / 2.0, Vector2(s, s))
		if skill != "":
			SkillIcon.draw(self, skill, r, dim)
		elif not gem.is_empty():
			SkillIcon.draw_gem(self, gem, r)
			if dim:
				draw_circle(r.get_center(), s * 0.5, Color(0, 0, 0, 0.5))
		if lv > 1:
			var at := r.position + Vector2(0, r.size.y + 1)
			draw_string_outline(Data.ui_font, at, str(lv), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x + 2, 10, 3, Color.BLACK)
			draw_string(Data.ui_font, at, str(lv), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x + 2, 10, Data.GEM_XP_COLOR)
		if mark != "":
			draw_string_outline(Data.ui_font, Vector2(0, size.y * 0.5 + 5), mark, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, 3, Color.BLACK)
			draw_string(Data.ui_font, Vector2(0, size.y * 0.5 + 5), mark, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Color("#ff6060"))


## put an icon at the left of a button and move its text past it
static func attach(b: Button, view: View, s: float) -> View:
	view.side = s
	b.add_child(view)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := b.get_theme_stylebox(st)
		if sb:
			sb.content_margin_left = s + view.pad + 6.0
	return view


static func _begin(ci: CanvasItem, rect: Rect2) -> void:
	var s := minf(rect.size.x, rect.size.y) / 32.0
	_base = Transform2D(0.0, Vector2(s, s), 0.0, rect.get_center()) * Transform2D(0.0, Vector2(-16, -16))
	ci.draw_set_transform_matrix(_base)


# =================== frame ===================
static func _chamfer(i: float, c: float) -> PackedVector2Array:
	var e := 32.0 - i
	return _pts([i + c, i, e - c, i, e, i + c, e, e - c, e - c, e, i + c, e, i, e - c, i, i + c])


static func _frame(ci: CanvasItem, pal: Array) -> void:
	ci.draw_colored_polygon(_chamfer(0.0, 4.5), Color("#080604"))
	ci.draw_colored_polygon(_chamfer(1.5, 3.5), pal[0])
	for i in 9:   # radial glow behind the motif
		var k := float(i) / 8.0
		ci.draw_circle(Vector2(16, 16), lerpf(14.0, 3.0, k), Color(pal[1], 0.09 + 0.05 * k), true, -1.0, true)
	var floor_pts := _pts([2, 20, 30, 20, 30, 27, 27, 30, 5, 30, 2, 27])
	ci.draw_polygon(floor_pts, PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.4),
		Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.4)]))


static func _bevel(ci: CanvasItem, pal: Array) -> void:
	var gloss := _pts([5, 2.6, 27, 2.6, 29.4, 5, 29.4, 9, 2.6, 13, 2.6, 5])
	ci.draw_polygon(gloss, PackedColorArray([Color(1, 1, 1, 0.13), Color(1, 1, 1, 0.13), Color(1, 1, 1, 0.1),
		Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.1)]))
	ci.draw_polyline(_loop(_chamfer(0.5, 4.2)), Color.BLACK, 1.0, true)
	ci.draw_polyline(_loop(_chamfer(1.5, 3.5)), pal[1], 1.5, true)
	ci.draw_polyline(_loop(_chamfer(2.6, 3.0)), Color(pal[2], 0.3), 0.6, true)
	# lit top-left edge, shaded bottom-right edge
	ci.draw_polyline(_pts([1.6, 26, 1.6, 5, 5, 1.6, 26, 1.6]), Color(pal[2], 0.55), 0.7, true)
	ci.draw_polyline(_pts([30.4, 6, 30.4, 27, 27, 30.4, 6, 30.4]), Color(0, 0, 0, 0.5), 0.7, true)
	for p in [Vector2(3.4, 3.4), Vector2(28.6, 3.4), Vector2(3.4, 28.6), Vector2(28.6, 28.6)]:
		_diamond(ci, p, 1.3, pal[2])


# =================== primitives (in the current local space) ===================
static func _pts(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, a.size(), 2):
		out.append(Vector2(a[i], a[i + 1]))
	return out


static func _loop(pts: PackedVector2Array) -> PackedVector2Array:
	var l := pts.duplicate()
	l.append(pts[0])
	return l


static func _arc(c: Vector2, r: float, from: float, to: float, n := 16) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		out.append(c + Vector2.from_angle(lerpf(from, to, float(i) / n)) * r)
	return out


static func _at(ci: CanvasItem, pos: Vector2, rot := 0.0, sc := 1.0) -> void:
	ci.draw_set_transform_matrix(_base * Transform2D(rot, Vector2(sc, sc), 0.0, pos))


static func _home(ci: CanvasItem) -> void:
	ci.draw_set_transform_matrix(_base)


## vertical gradient fill (local y)
static func _shade(ci: CanvasItem, pts: PackedVector2Array, top: Color, bot: Color) -> void:
	var y0 := INF
	var y1 := -INF
	for p in pts:
		y0 = minf(y0, p.y)
		y1 = maxf(y1, p.y)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(top.lerp(bot, (p.y - y0) / maxf(y1 - y0, 0.001)))
	ci.draw_polygon(pts, cols)


static func _metal(ci: CanvasItem, pts: PackedVector2Array, light := STEEL_L, dark := STEEL_D) -> void:
	_shade(ci, pts, light, dark)
	ci.draw_polyline(_loop(pts), LINE, 0.9, true)


## a glowing shape: halo, hot-white to colored fill, thin colored rim
static func _energy(ci: CanvasItem, pts: PackedVector2Array, col := _g) -> void:
	var l := _loop(pts)
	ci.draw_polyline(l, Color(col, 0.16 * col.a), 3.8, true)
	ci.draw_polyline(l, Color(col, 0.4 * col.a), 1.9, true)
	_shade(ci, pts, Color(col.lerp(Color.WHITE, 0.8), col.a), col)
	ci.draw_polyline(l, Color(col.darkened(0.35), col.a), 0.6, true)


static func _glow_line(ci: CanvasItem, pts: PackedVector2Array, w := 1.2, col := _g) -> void:
	ci.draw_polyline(pts, Color(col, 0.16 * col.a), w * 3.4, true)
	ci.draw_polyline(pts, Color(col, 0.42 * col.a), w * 1.9, true)
	ci.draw_polyline(pts, Color(col.lerp(Color.WHITE, 0.72), col.a), w, true)


static func _glow_segs(ci: CanvasItem, segs: PackedVector2Array, w := 1.0, col := _g) -> void:
	ci.draw_multiline(segs, Color(col, 0.16), w * 3.4, true)
	ci.draw_multiline(segs, Color(col, 0.42), w * 1.9, true)
	ci.draw_multiline(segs, col.lerp(Color.WHITE, 0.72), w, true)


static func _orb(ci: CanvasItem, c: Vector2, r: float, col := _g) -> void:
	for i in 4:
		ci.draw_circle(c, r * (2.0 - i * 0.22), Color(col, 0.07 + i * 0.04), true, -1.0, true)
	ci.draw_circle(c, r + 0.5, col.darkened(0.4), true, -1.0, true)
	ci.draw_circle(c, r, col, true, -1.0, true)
	ci.draw_circle(c, r * 0.72, col.lerp(Color.WHITE, 0.5), true, -1.0, true)
	ci.draw_circle(c, r * 0.42, col.lerp(Color.WHITE, 0.9), true, -1.0, true)
	ci.draw_circle(c + Vector2(-r, -r) * 0.38, r * 0.2, Color(1, 1, 1, 0.85), true, -1.0, true)


static func _diamond(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)


## a four-pointed glint
static func _sparkle(ci: CanvasItem, c: Vector2, r: float, col := Color.WHITE) -> void:
	var q := r * 0.22
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(q, -q), c + Vector2(r, 0), c + Vector2(q, q),
		c + Vector2(0, r), c + Vector2(-q, q), c + Vector2(-r, 0), c + Vector2(-q, -q)])
	ci.draw_circle(c, r * 0.6, Color(col, 0.25), true, -1.0, true)
	ci.draw_colored_polygon(pts, col)


static func _star(ci: CanvasItem, c: Vector2, r1: float, r2: float, n: int, col := _g, rot := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in n * 2:
		pts.append(c + Vector2.from_angle(rot - PI / 2.0 + PI * i / n) * (r1 if i % 2 == 0 else r2))
	_energy(ci, pts, col)


## a tapered sickle of light from angle `from` to `to`
static func _crescent(ci: CanvasItem, c: Vector2, r: float, from: float, to: float, thick: float, col := _g) -> void:
	var n := 18
	var pts := _arc(c, r, from, to, n)
	for i in range(n - 1, 0, -1):
		var t := float(i) / n
		pts.append(c + Vector2.from_angle(lerpf(from, to, t)) * (r - thick * sin(t * PI)))
	_energy(ci, pts, col)


static func _bolt(ci: CanvasItem, a: Vector2, b: Vector2, w := 1.3, jag := 2.2, col := _g) -> void:
	var dir := b - a
	var perp := dir.orthogonal().normalized()
	var k := [0.0, 1.0, -0.8, 0.9, -1.0, 0.6, 0.0]
	var pts := PackedVector2Array()
	for i in k.size():
		pts.append(a + dir * (float(i) / (k.size() - 1)) + perp * jag * k[i])
	_glow_line(ci, pts, w, col)


## a crystal or blade-head kite from base `a` to tip `b`
static func _shard(ci: CanvasItem, a: Vector2, b: Vector2, w: float, col := _g, metal := false) -> void:
	var dir := b - a
	var perp := dir.orthogonal().normalized() * w
	var m := a + dir * 0.32
	var pts := PackedVector2Array([a, m + perp, b, m - perp])
	if metal:
		_metal(ci, pts)
	else:
		_energy(ci, pts, col)
	ci.draw_line(a.lerp(b, 0.1), b, Color(1, 1, 1, 0.55), 0.5, true)


static func _snowflake(ci: CanvasItem, c: Vector2, r: float, col := _g) -> void:
	var segs := PackedVector2Array()
	for k in 6:
		var a := k * TAU / 6.0 - PI / 2.0
		var d := Vector2.from_angle(a)
		segs.append_array([c, c + d * r])
		for f in [0.5, 0.75]:
			var p: Vector2 = c + d * r * f
			var l := r * (0.32 if f == 0.5 else 0.2)
			segs.append_array([p, p + Vector2.from_angle(a + 0.8) * l, p, p + Vector2.from_angle(a - 0.8) * l])
	_glow_segs(ci, segs, maxf(r * 0.1, 0.8), col)
	_diamond(ci, c, r * 0.22, Color.WHITE)


static func _waves(ci: CanvasItem, c: Vector2, radii: Array, from: float, to: float, col := _g) -> void:
	for i in radii.size():
		var pts := _arc(c, radii[i], from, to, 14)
		_glow_line(ci, pts, 1.1 - i * 0.2, Color(col, 1.0 - i * 0.25))


static func _spiral(ci: CanvasItem, c: Vector2, r: float, turns: float, w := 1.2, col := _g, rot := 0.0) -> void:
	var pts := PackedVector2Array()
	var n := int(turns * 24)
	for i in n + 1:
		var t := float(i) / n
		pts.append(c + Vector2.from_angle(rot + t * turns * TAU) * r * (0.12 + 0.88 * t))
	_glow_line(ci, pts, w, col)


static func _flame(ci: CanvasItem, pos: Vector2, s := 1.0, rot := 0.0, col := FIRE) -> void:
	_at(ci, pos, rot, s)
	_energy(ci, _pts([0, 8, -5, 5, -6.5, 0, -5, -5, -3.5, -2.5, -2.5, -8, 0, -4.5, 1.5, -11, 3.5, -4, 5, -6.5, 6.5, -1, 5.5, 5]), col)
	_shade(ci, _pts([0, 7, -3, 4.5, -3.8, 1, -2, -2, -1, -5, 0.5, -2, 2, -5.5, 3.5, 0, 3, 4.5]), Color("#fffbe0"), col.lerp(Color("#ffd040"), 0.6))
	_home(ci)


static func _drop(ci: CanvasItem, c: Vector2, s: float, col := _g) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -4.2) * s])
	pts.append_array(_arc(c + Vector2(0, 0.8) * s, 2.5 * s, -0.25, PI + 0.25, 10))
	_energy(ci, pts, col)


static func _sword(ci: CanvasItem, pos: Vector2, rot := 0.0, s := 1.0, light := STEEL_L, dark := STEEL_D) -> void:
	_at(ci, pos, rot, s)
	_shade(ci, _pts([0, -13, -1.7, -9, -1.7, 4, 0, 4]), light, light.lerp(dark, 0.4))
	_shade(ci, _pts([0, -13, 0, 4, 1.7, 4, 1.7, -9]), light.lerp(dark, 0.45), dark)
	ci.draw_polyline(_loop(_pts([0, -13, 1.7, -9, 1.7, 4, -1.7, 4, -1.7, -9])), LINE, 0.9, true)
	_metal(ci, _pts([-5, 4, -4, 3.4, 4, 3.4, 5, 4, 4, 5.8, -4, 5.8]), Color("#fff0a0"), Color("#9a6a18"))
	_metal(ci, _pts([-0.9, 5.8, 0.9, 5.8, 0.9, 10, -0.9, 10]), Color("#8a5a3a"), Color("#3a2010"))
	ci.draw_circle(Vector2(0, 11), 1.6, LINE, true, -1.0, true)
	ci.draw_circle(Vector2(0, 11), 1.1, GOLD, true, -1.0, true)
	_home(ci)


static func _hammer(ci: CanvasItem, pos: Vector2, rot := 0.0, s := 1.0, light := STEEL_L, dark := STEEL_D) -> void:
	_at(ci, pos, rot, s)
	_metal(ci, _pts([-1, -4, 1, -4, 1, 12, -1, 12]), Color("#a87048"), Color("#4a2810"))
	_metal(ci, _pts([-7, -10, 7, -10, 7.6, -6.5, 7, -3, -7, -3, -7.6, -6.5]), light, dark)
	ci.draw_line(Vector2(-7, -6.5), Vector2(7, -6.5), Color(1, 1, 1, 0.35), 0.6, true)
	_metal(ci, _pts([-1.8, -11, 1.8, -11, 1.8, -2, -1.8, -2]), Color("#fff0a0"), Color("#9a6a18"))
	_home(ci)


static func _axe(ci: CanvasItem, pos: Vector2, rot := 0.0, s := 1.0, light := STEEL_L, dark := STEEL_D) -> void:
	_at(ci, pos, rot, s)
	_metal(ci, _pts([-0.9, -11, 0.9, -11, 0.9, 12, -0.9, 12]), Color("#a87048"), Color("#4a2810"))
	_metal(ci, _pts([0.5, -9, 5, -12.5, 8.5, -6, 5, 0.5, 0.5, -3]), light, dark)
	ci.draw_polyline(_pts([5.4, -11.6, 7.8, -6, 5.4, -0.4]), Color(1, 1, 1, 0.7), 0.6, true)
	_metal(ci, _pts([-5, -9, -0.5, -8, -0.5, -4, -5, -3, -3.6, -6]), light, dark)
	_home(ci)


static func _skull(ci: CanvasItem, c: Vector2, s: float, eye := _g) -> void:
	_at(ci, c, 0.0, s)
	_metal(ci, _pts([-3.6, 2.5, 3.6, 2.5, 3.2, 6.6, -3.2, 6.6]), BONE_L, BONE_D)
	var head := _arc(Vector2(0, -1), 6.2, PI * 0.78, PI * 2.22, 24)
	_metal(ci, head, BONE_L, BONE_D)
	for x in [-2.4, 2.4]:
		ci.draw_circle(Vector2(x, 0), 1.9, Color("#120a06"), true, -1.0, true)
		ci.draw_circle(Vector2(x, 0.1), 1.0, Color(eye, 0.6), true, -1.0, true)
		ci.draw_circle(Vector2(x, 0.1), 0.5, eye.lerp(Color.WHITE, 0.6), true, -1.0, true)
	ci.draw_colored_polygon(_pts([0, 2, 0.9, 3.8, -0.9, 3.8]), Color("#120a06"))
	for x in [-1.6, 0.0, 1.6]:
		ci.draw_line(Vector2(x, 4.8), Vector2(x, 6.6), LINE, 0.5, true)
	_home(ci)


static func _cloud(ci: CanvasItem, c: Vector2, s: float, top: Color, bot: Color) -> void:
	var blobs := [Vector3(-5.5, 1.5, 3.6), Vector3(-1.5, -1.5, 4.6), Vector3(3.5, -0.5, 4.0), Vector3(6.5, 2.0, 3.0), Vector3(0.5, 2.5, 3.6)]
	for b in blobs:
		ci.draw_circle(c + Vector2(b.x, b.y) * s, (b.z + 0.7) * s, LINE, true, -1.0, true)
	for b in blobs:
		ci.draw_circle(c + Vector2(b.x, b.y) * s, b.z * s, bot, true, -1.0, true)
	for b in blobs:
		ci.draw_circle(c + Vector2(b.x, b.y - 0.9) * s, (b.z - 0.9) * s, top, true, -1.0, true)


static func _rock(ci: CanvasItem, c: Vector2, s: float, light := STONE_L, dark := STONE_D) -> void:
	_at(ci, c, 0.0, s)
	_metal(ci, _pts([-5, -3, -1, -6, 4, -5, 6, -1, 4, 4, -2, 5, -6, 2]), light, dark)
	ci.draw_polyline(_pts([-1, -6, 0, -1, 6, -1]), Color(0, 0, 0, 0.35), 0.6, true)
	ci.draw_line(Vector2(0, -1), Vector2(-2, 5), Color(0, 0, 0, 0.35), 0.6, true)
	_home(ci)


static func _shield(ci: CanvasItem, c: Vector2, s: float, light := STEEL_L, dark := STEEL_D) -> void:
	_at(ci, c, 0.0, s)
	_metal(ci, _pts([-6.5, -7, 0, -8.2, 6.5, -7, 6.2, 0, 0, 8.5, -6.2, 0]), light, dark)
	ci.draw_polyline(_loop(_pts([-5, -5.8, 0, -6.8, 5, -5.8, 4.8, -0.4, 0, 6.5, -4.8, -0.4])), Color(GOLD, 0.9), 0.8, true)
	ci.draw_circle(Vector2(0, -1), 2.0, LINE, true, -1.0, true)
	ci.draw_circle(Vector2(0, -1), 1.5, GOLD, true, -1.0, true)
	_home(ci)


static func _ghost(ci: CanvasItem, c: Vector2, s: float, col := _g) -> void:
	_at(ci, c, 0.0, s)
	var pts := _arc(Vector2(0, -1), 5.0, PI, TAU, 14)
	pts.append_array(_pts([5, 6, 3.3, 4.6, 1.7, 7, 0, 5, -1.7, 7, -3.3, 4.6, -5, 6]))
	_energy(ci, pts, col)
	for x in [-1.8, 1.8]:
		ci.draw_circle(Vector2(x, -1), 1.1, Color("#100818", col.a), true, -1.0, true)
	ci.draw_circle(Vector2(0, 2.2), 0.9, Color("#100818", col.a), true, -1.0, true)
	_home(ci)


static func _heart(ci: CanvasItem, c: Vector2, s: float, light: Color, dark: Color) -> void:
	var pts := PackedVector2Array()
	for i in 32:
		var t := TAU * i / 32.0
		pts.append(c + Vector2(16.0 * pow(sin(t), 3), -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))) * s / 17.0 * 9.0)
	_metal(ci, pts, light, dark)


static func _ground(ci: CanvasItem, y: float, col := Color("#3a2c1e")) -> void:
	_shade(ci, _pts([2.5, y, 29.5, y, 29.5, 27.5, 27.5, 29.5, 4.5, 29.5, 2.5, 27.5]), col, col.darkened(0.6))
	ci.draw_line(Vector2(2.5, y), Vector2(29.5, y), col.lightened(0.3), 0.8, true)


static func _crack(ci: CanvasItem, pts: PackedVector2Array, col: Color, w := 1.4) -> void:
	ci.draw_polyline(pts, Color(0, 0, 0, 0.8), w + 1.0, true)
	_glow_line(ci, pts, w * 0.6, col)


static func _ellipse(c: Vector2, rx: float, ry: float, n := 20) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out


static func _chevron(ci: CanvasItem, x: float, y: float, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for p in _pts([-3, -8, 4, 0, -3, 8, -6, 8, 1, 0, -6, -8]):
		pts.append(Vector2(x, y) + p * s)
	_energy(ci, pts, col)


# =================== skill motifs ===================
static func _motif(ci: CanvasItem, id: String) -> void:
	var c := Vector2(16, 16)
	match id:
		"slash":
			_crescent(ci, Vector2(17, 18), 11.5, -2.7, 0.15, 3.4)
			_sword(ci, Vector2(14, 18), 0.785, 0.95)
		"whirl":
			for k in 3:
				_crescent(ci, c, 11.5, k * TAU / 3.0, k * TAU / 3.0 + 1.8, 2.8)
			_sword(ci, Vector2(16, 17), 0.785, 0.6)
		"fireball":
			_flame(ci, Vector2(13, 13), 1.25, -0.785)
			_orb(ci, Vector2(19, 19), 5.5, Color("#ff8a30"))
		"ice_spear":
			_glow_line(ci, _pts([4, 20, 11, 13]), 0.7)
			_glow_line(ci, _pts([12, 28, 19, 21]), 0.7)
			_shard(ci, Vector2(6, 26), Vector2(27.5, 4.5), 3.4)
			_sparkle(ci, Vector2(27, 5), 3.5)
		"nova":
			_waves(ci, c, [12.5, 9.8], 0.0, TAU)
			_snowflake(ci, c, 9.5)
		"chain":
			_bolt(ci, Vector2(6, 24), Vector2(16, 8), 1.3, 1.8)
			_bolt(ci, Vector2(16, 8), Vector2(26, 23), 1.3, 1.8)
			for p in [Vector2(6, 24), Vector2(16, 8), Vector2(26, 23)]:
				_orb(ci, p, 2.4)
		"storm":
			_bolt(ci, Vector2(12, 14), Vector2(9, 28), 1.3, 1.6)
			_bolt(ci, Vector2(21, 14), Vector2(23, 27), 1.1, 1.4)
			_cloud(ci, Vector2(16, 10), 1.15, Color("#a89ad8"), Color("#4a3e80"))
		"meteor":
			_flame(ci, Vector2(12.5, 12.5), 1.35, -0.785, Color("#ff5a20"))
			_rock(ci, Vector2(20, 20), 0.95, Color("#d08050"), Color("#4a1e10"))
			_crack(ci, _pts([16, 18, 20, 20, 23, 18]), Color("#ffb040"), 0.9)
		"dash":
			_glow_line(ci, _pts([3, 12, 9, 12]), 0.6)
			_glow_line(ci, _pts([2, 20, 8, 20]), 0.6)
			_chevron(ci, 10, 16, 1.0, Color(_g, 0.35))
			_chevron(ci, 16, 16, 1.0, Color(_g, 0.65))
			_chevron(ci, 22.5, 16, 1.05, _g)
		"skeleton":
			_skull(ci, Vector2(16, 15), 1.5, Color("#80ffb0"))
		"heavy_strike":
			_star(ci, Vector2(11, 22), 7.5, 3.0, 8, Color("#ffd890"))
			_hammer(ci, Vector2(19.5, 12.5), -2.356, 1.0)
		"wide_cleave":
			_crescent(ci, Vector2(16, 26), 14.0, -2.95, -0.2, 4.2)
			_axe(ci, Vector2(17, 20), 0.35, 0.8)
		"thrust":
			_glow_line(ci, _pts([7, 18, 13, 12]), 0.7)
			_glow_line(ci, _pts([14, 26, 20, 20]), 0.7)
			ci.draw_line(Vector2(5, 27), Vector2(21.5, 10.5), LINE, 2.6, true)
			ci.draw_line(Vector2(5, 27), Vector2(21.5, 10.5), Color("#9a6a40"), 1.5, true)
			_shard(ci, Vector2(20.5, 11.5), Vector2(28.5, 3.5), 2.4, _g, true)
			_sparkle(ci, Vector2(28, 4), 3.0, _g.lerp(Color.WHITE, 0.6))
		"ground_slam":
			_ground(ci, 22)
			_crack(ci, _pts([16, 22, 13, 25, 14, 29]), Color("#ffb060"), 1.0)
			_crack(ci, _pts([16, 22, 20, 26, 24, 27]), Color("#ffb060"), 1.0)
			_waves(ci, Vector2(16, 22), [8.0, 12.0], PI + 0.2, TAU - 0.2)
			_rock(ci, Vector2(6.5, 16), 0.38)
			_rock(ci, Vector2(26, 15), 0.42)
			_hammer(ci, Vector2(16, 12), PI, 0.85)
		"flame_strike":
			_flame(ci, Vector2(16, 16), 1.35)
			_sword(ci, Vector2(16, 18), 0.785, 0.95, Color("#fff4c8"), Color("#c04a18"))
		"frost_blade":
			_shard(ci, Vector2(21, 8), Vector2(28, 4), 1.4)
			_shard(ci, Vector2(23, 13), Vector2(29.5, 12.5), 1.2)
			_shard(ci, Vector2(10, 7), Vector2(7, 3), 1.1)
			_sword(ci, Vector2(15, 17), 0.785, 1.0, ICE_L, ICE_D)
			_sparkle(ci, Vector2(24, 21), 2.5)
		"thunder_strike":
			_bolt(ci, Vector2(26, 4), Vector2(7, 28), 1.6, 2.6)
			_sword(ci, Vector2(17, 17), -0.785, 0.95)
			_sparkle(ci, Vector2(9.5, 8.5), 3.0, _g.lerp(Color.WHITE, 0.5))
		"venom_strike":
			_orb(ci, Vector2(16, 13), 3.0, Color(_g, 0.5))
			_metal(ci, _pts([5, 5, 13, 5, 12, 12, 10.5, 19, 9, 24, 8, 15]), BONE_L, BONE_D)
			_metal(ci, _pts([19, 5, 27, 5, 24, 15, 23, 24, 21.5, 19, 20, 12]), BONE_L, BONE_D)
			ci.draw_line(Vector2(4.5, 5), Vector2(27.5, 5), Color("#7a1a28"), 2.2, true)
			_drop(ci, Vector2(9, 27), 0.9)
			_drop(ci, Vector2(23, 27.5), 0.75)
		"double_slash":
			_crescent(ci, Vector2(4, 30), 22.0, -1.5, -0.1, 3.2)
			_crescent(ci, Vector2(28, 30), 22.0, -3.04, -1.64, 3.2)
			_sparkle(ci, Vector2(16, 13), 4.5)
		"blade_tempest":
			_spiral(ci, c, 12.0, 1.3, 0.9)
			for k in 6:
				var a := k * TAU / 6.0
				_sword(ci, c + Vector2.from_angle(a) * 9.5, a + PI, 0.36)
			_orb(ci, c, 2.2)
		"earthquake":
			_ground(ci, 17)
			_crack(ci, _pts([3, 21, 9, 19, 12, 24, 17, 20, 21, 25, 25, 21, 29, 23]), Color("#ffb060"), 1.6)
			_crack(ci, _pts([12, 24, 11, 29]), Color("#ffb060"), 1.0)
			_rock(ci, Vector2(9, 11), 0.6)
			_rock(ci, Vector2(22.5, 9), 0.5)
			_rock(ci, Vector2(16, 5), 0.3)
		"shield_bash":
			var segs := PackedVector2Array()
			for k in 5:
				var a := -0.9 + k * 0.45
				segs.append_array([Vector2(23, 16) + Vector2.from_angle(a) * 3.5, Vector2(23, 16) + Vector2.from_angle(a) * 7.5])
			_glow_segs(ci, segs, 0.9, Color("#ffe0a0"))
			_shield(ci, Vector2(14, 16), 1.4)
		"glacial_hammer":
			_snowflake(ci, Vector2(9, 24), 5.0)
			_hammer(ci, Vector2(17.5, 16), 0.6, 1.15, ICE_L, ICE_D)
			_sparkle(ci, Vector2(26, 8), 3.0)
		"throw_knives":
			for k in 3:
				var rot := 0.35 + k * 0.42
				var d := Vector2(sin(rot), -cos(rot))
				_glow_line(ci, PackedVector2Array([Vector2(9, 23) - d * 2.0, Vector2(9, 23) + d * 6.0]), 0.6, Color("#e0e8ff"))
				_sword(ci, Vector2(9, 23) + d * 11.0, rot, 0.52)
		"blade_rain":
			for p in [Vector2(8, 14), Vector2(16, 18), Vector2(24, 12)]:
				_glow_line(ci, PackedVector2Array([p + Vector2(0, -12), p + Vector2(0, -6)]), 0.7, Color("#e0e8ff"))
				_sword(ci, p, PI, 0.6)
			_ground(ci, 27)
		"frost_axe":
			_waves(ci, c, [13.0], -0.4, 2.4)
			_waves(ci, c, [13.0], 2.75, 5.55)
			_axe(ci, Vector2(16, 17), 0.5, 1.05, ICE_L, ICE_D)
			_sparkle(ci, Vector2(6, 8), 2.5)
		"punch_wave":
			_waves(ci, Vector2(13, 16), [9.5, 12.5, 15.5], -0.9, 0.9)
			_at(ci, Vector2(11, 16), 0.0, 1.1)
			_metal(ci, _pts([-5, -4, 4, -4, 5.5, 0, 4, 5, -5, 5]), Color("#f0c8a0"), Color("#8a5838"))
			for y in [-2.5, 0.0, 2.5]:
				ci.draw_line(Vector2(1.5, y), Vector2(5.0, y), LINE, 0.5, true)
			_metal(ci, _pts([-5, 1, 0, 1.5, 0, 3.2, -5, 3.5]), Color("#e8b890"), Color("#9a6040"))
			_metal(ci, _pts([-9, -3.5, -5, -3.5, -5, 4.5, -9, 4.5]), Color("#c08848"), Color("#5a3818"))
			_home(ci)
		"firebolt":
			_flame(ci, Vector2(12, 20), 0.95, -2.356)
			_glow_line(ci, _pts([5, 27, 21, 11]), 1.0, FIRE)
			_shard(ci, Vector2(20, 12), Vector2(28, 4), 2.6, Color("#ffa040"))
		"frost_bolt":
			_glow_line(ci, _pts([4, 26, 13, 18]), 0.9)
			_glow_line(ci, _pts([7, 29, 14, 22]), 0.6)
			for k in 6:
				var a := k * TAU / 6.0 - 0.3
				_shard(ci, Vector2(19, 13) + Vector2.from_angle(a) * 4.0, Vector2(19, 13) + Vector2.from_angle(a) * 10.0, 1.4)
			_orb(ci, Vector2(19, 13), 4.6)
		"sparks":
			_bolt(ci, Vector2(5, 22), Vector2(13, 11), 0.9, 1.2)
			_bolt(ci, Vector2(13, 11), Vector2(22, 17), 0.9, 1.2)
			_bolt(ci, Vector2(14, 26), Vector2(27, 24), 0.9, 1.2)
			for p in [Vector2(13, 11), Vector2(22, 17), Vector2(27, 24), Vector2(25, 7)]:
				_sparkle(ci, p, 3.4, _g.lerp(Color.WHITE, 0.4))
		"ball_thunder":
			for k in 6:
				var a := k * TAU / 6.0 + 0.3
				_bolt(ci, c + Vector2.from_angle(a) * 5.0, c + Vector2.from_angle(a + 0.3) * 13.0, 0.8, 1.0)
			_orb(ci, c, 6.5)
		"void_bolt":
			_glow_line(ci, _pts([3, 28, 12, 19]), 1.0)
			_spiral(ci, Vector2(19, 13), 10.0, 1.6, 1.0, _g, 0.0)
			ci.draw_circle(Vector2(19, 13), 4.6, Color(_g, 0.6), true, -1.0, true)
			ci.draw_circle(Vector2(19, 13), 3.6, Color("#06020c"), true, -1.0, true)
			ci.draw_arc(Vector2(19, 13), 3.8, 0.0, TAU, 24, _g.lerp(Color.WHITE, 0.5), 0.6, true)
		"flame_jet":
			_orb(ci, Vector2(5, 27), 2.4, FIRE)
			_flame(ci, Vector2(9.5, 22.5), 0.6, 0.785)
			_flame(ci, Vector2(14.5, 17.5), 0.9, 0.785)
			_flame(ci, Vector2(20.5, 11.5), 1.15, 0.785)
		"ice_shards":
			_shard(ci, Vector2(9, 25), Vector2(10, 3.5), 2.4)
			_shard(ci, Vector2(9, 25), Vector2(28.5, 21), 2.4)
			_shard(ci, Vector2(9, 25), Vector2(25, 8), 2.8)
			_orb(ci, Vector2(8.5, 25.5), 2.0)
		"lightning_lance":
			_bolt(ci, Vector2(3, 29), Vector2(23, 9), 1.6, 1.4)
			_shard(ci, Vector2(21.5, 10.5), Vector2(29, 3), 2.8)
			_sparkle(ci, Vector2(28.5, 3.5), 3.5)
		"soul_wisps":
			for p in [Vector2(10, 13), Vector2(23, 10), Vector2(16, 23)]:
				_flame(ci, p, 0.62, 0.0, _g)
				ci.draw_circle(p + Vector2(0, 1.5), 1.2, Color("#ffffff"), true, -1.0, true)
		"fire_wheel":
			var segs := PackedVector2Array()
			for k in 6:
				var a := k * TAU / 6.0
				segs.append_array([c + Vector2.from_angle(a) * 2.5, c + Vector2.from_angle(a) * 8.5])
			_glow_segs(ci, segs, 0.9, FIRE)
			for k in 8:
				var a := k * TAU / 8.0
				_flame(ci, c + Vector2.from_angle(a) * 10.0, 0.42, a + PI / 2.0)
			_glow_line(ci, _arc(c, 9.0, 0.0, TAU, 32), 1.6, FIRE)
			_orb(ci, c, 2.6, FIRE)
		"comet":
			_glow_line(ci, _pts([3, 3, 18, 18]), 3.0, Color(_g, 0.5))
			_glow_line(ci, _pts([8, 4, 18, 17]), 1.0)
			_glow_line(ci, _pts([4, 9, 17, 18]), 1.0)
			for k in 5:
				var a := k * TAU / 5.0 + 0.6
				_shard(ci, Vector2(20, 20) + Vector2.from_angle(a) * 3.5, Vector2(20, 20) + Vector2.from_angle(a) * 8.0, 1.3)
			_orb(ci, Vector2(20, 20), 4.6)
			_sparkle(ci, Vector2(8, 15), 2.0)
			_sparkle(ci, Vector2(14, 6), 2.0)
		"flame_nova":
			_glow_line(ci, _arc(c, 12.5, 0.0, TAU, 32), 0.9, FIRE)
			for k in 8:
				var a := k * TAU / 8.0
				_flame(ci, c + Vector2.from_angle(a) * 9.0, 0.55, a + PI / 2.0)
			_orb(ci, c, 3.8, FIRE)
		"shock_nova":
			_glow_line(ci, _arc(c, 12.0, 0.0, TAU, 32), 1.2)
			for k in 8:
				var a := k * TAU / 8.0
				_bolt(ci, c + Vector2.from_angle(a) * 4.0, c + Vector2.from_angle(a) * 12.0, 0.8, 0.9)
			_orb(ci, c, 3.6)
		"ice_pillars":
			_ground(ci, 26, Color("#2a3a4a"))
			_energy(ci, _pts([4, 27, 8.5, 9, 13, 27]))
			_energy(ci, _pts([19, 27, 24, 11, 28.5, 27]))
			_energy(ci, _pts([10, 27, 16, 2.5, 22, 27]))
			ci.draw_line(Vector2(16, 4), Vector2(16, 26), Color(1, 1, 1, 0.55), 0.6, true)
			_sparkle(ci, Vector2(16, 3), 3.0)
		"fire_rain":
			for p in [Vector2(9, 10), Vector2(21, 7), Vector2(14, 19), Vector2(25, 19)]:
				_flame(ci, p + Vector2(1.5, -1.5), 0.48, 0.6)
				_orb(ci, p + Vector2(-0.8, 0.8), 1.9, FIRE)
			_ground(ci, 27, Color("#4a2010"))
		"blizzard":
			_cloud(ci, Vector2(16, 9), 1.15, Color("#e8f6ff"), Color("#6a90b0"))
			_glow_segs(ci, _pts([8, 16, 5, 22, 15, 17, 12, 24, 23, 16, 20, 22]), 0.6)
			_snowflake(ci, Vector2(9, 25), 3.2)
			_snowflake(ci, Vector2(20, 26), 3.6)
			_snowflake(ci, Vector2(26, 20), 2.6)
		"thunderbolt":
			_waves(ci, Vector2(13, 27), [5.0, 8.5], PI + 0.3, TAU - 0.3)
			_bolt(ci, Vector2(19, 1.5), Vector2(13, 26), 2.3, 3.0)
			_star(ci, Vector2(13, 26), 5.0, 1.8, 6)
		"miasma":
			for p in [Vector3(9, 24, 1.6), Vector3(15, 27, 1.1), Vector3(22, 24, 1.9), Vector3(26, 28, 1.0)]:
				ci.draw_circle(Vector2(p.x, p.y), p.z, Color(_g, 0.35), true, -1.0, true)
				ci.draw_arc(Vector2(p.x, p.y), p.z, 0.0, TAU, 12, _g.lerp(Color.WHITE, 0.4), 0.5, true)
			_cloud(ci, Vector2(16, 13), 1.25, Color("#b8e080"), Color("#3c6020"))
			_skull(ci, Vector2(16, 14), 0.45, Color("#c8ff60"))
			_drop(ci, Vector2(11, 20), 0.6)
		"fissure":
			_ground(ci, 10, Color("#3a2216"))
			_crack(ci, _pts([4, 28, 9, 23, 8, 19, 14, 16, 15, 13, 21, 12, 27, 10]), Color("#ff6a20"), 2.4)
			for p in [Vector2(12, 11), Vector2(20, 7), Vector2(25, 15), Vector2(7, 16)]:
				_orb(ci, p, 0.9, Color("#ffa040"))
		"frost_vortex":
			_spiral(ci, c, 13.0, 2.2, 1.2, _g, 0.0)
			_spiral(ci, c, 9.0, 1.8, 0.8, _g, PI)
			_orb(ci, c, 2.8)
			_sparkle(ci, Vector2(6, 7), 2.4)
			_sparkle(ci, Vector2(26, 25), 2.4)
		"doom":
			_glow_line(ci, _arc(c, 12.5, 0.0, TAU, 40), 0.9)
			_glow_line(ci, _arc(c, 9.5, 0.0, TAU, 40), 0.6)
			var segs := PackedVector2Array()
			for k in 12:
				var a := k * TAU / 12.0
				segs.append_array([c + Vector2.from_angle(a) * 9.8, c + Vector2.from_angle(a) * 12.2])
			_glow_segs(ci, segs, 0.6)
			var eye := PackedVector2Array()
			eye.append_array(_arc(Vector2(16, 22), 10.0, -2.3, -0.84, 10))
			eye.append_array(_arc(Vector2(16, 10), 10.0, 0.84, 2.3, 10))
			_shade(ci, eye, Color("#ffe8ff"), Color("#c090e0"))
			ci.draw_polyline(_loop(eye), LINE, 0.9, true)
			ci.draw_circle(c, 3.4, _g.darkened(0.3), true, -1.0, true)
			ci.draw_circle(c, 3.4, Color("#ff3050"), false, 0.7, true)
			_metal(ci, _pts([16, 13, 16.9, 16, 16, 19, 15.1, 16]), Color("#200010"), Color("#000000"))
		"hex_frail":
			_glow_line(ci, _arc(c, 12.0, 0.0, TAU, 40), 0.9)
			var tri := PackedVector2Array()
			for k in 3:
				tri.append(c + Vector2.from_angle(PI / 2.0 + k * TAU / 3.0) * 12.0)
			_glow_line(ci, _loop(tri), 0.7)
			_heart(ci, Vector2(16, 15), 0.7, Color("#ffa0d0"), Color("#802050"))
			ci.draw_polyline(_pts([16, 10.5, 14.5, 13.5, 17, 15.5, 15, 19.5]), Color("#200010"), 1.0, true)
		"hex_mire":
			var pud := _ellipse(Vector2(16, 24), 13.0, 5.0)
			_shade(ci, pud, Color("#6a8a50"), Color("#2a3a1a"))
			ci.draw_polyline(_loop(pud), Color(_g, 0.8), 0.8, true)
			_glow_line(ci, _pts([9, 24, 8, 19, 10, 15, 9, 11]), 0.9)
			_glow_line(ci, _pts([16, 23, 17, 17, 15, 12, 16, 8]), 1.0)
			_glow_line(ci, _pts([23, 24, 24, 19, 22, 15, 23, 12]), 0.9)
			_chevron(ci, 16, 4, 0.45, _g)
			for p in [Vector2(12, 25), Vector2(20, 23), Vector2(25, 26)]:
				ci.draw_arc(p, 1.2, 0.0, TAU, 12, Color("#c0e0a0"), 0.5, true)
		"war_cry":
			_waves(ci, Vector2(18, 15), [6.0, 9.5, 13.0], -0.85, 0.85)
			var horn := PackedVector2Array()
			var back := PackedVector2Array()
			for i in 13:
				var t := float(i) / 12.0
				var p := Vector2(4, 24).lerp(Vector2(8, 11), t).lerp(Vector2(8, 11).lerp(Vector2(19, 15), t), t)
				var w := lerpf(0.5, 4.2, t * t)
				horn.append(p + Vector2(0, -w))
				back.insert(0, p + Vector2(0, w))
			horn.append_array(back)
			_metal(ci, horn, Color("#fff0d0"), Color("#9a7040"))
			for t in [0.45, 0.75]:
				var p := Vector2(4, 24).lerp(Vector2(8, 11), t).lerp(Vector2(8, 11).lerp(Vector2(19, 15), t), t)
				ci.draw_line(p + Vector2(0, -3), p + Vector2(0, 3), GOLD, 1.2, true)
		"tailwind":
			_glow_line(ci, _arc(Vector2(14, 30), 16.0, -2.4, -1.0), 1.4)
			_glow_line(ci, _arc(Vector2(16, 34), 14.0, -2.2, -1.2), 1.0)
			_glow_line(ci, _arc(Vector2(12, 26), 18.0, -2.0, -1.35), 0.7)
			_at(ci, Vector2(23, 10), 0.7, 1.0)
			_energy(ci, _pts([0, -6, 2.6, -1, 1.6, 4, 0, 6, -1.6, 4, -2.6, -1]))
			ci.draw_line(Vector2(0, -5), Vector2(0, 6), Color(1, 1, 1, 0.6), 0.5, true)
			_home(ci)
		"stone_skin":
			_shield(ci, c, 1.6, STONE_L, STONE_D)
			ci.draw_polyline(_pts([10, 8, 13, 13, 11, 18]), Color(0, 0, 0, 0.5), 0.7, true)
			ci.draw_polyline(_pts([22, 9, 19, 12, 21, 17]), Color(0, 0, 0, 0.5), 0.7, true)
			_star(ci, Vector2(16, 14.4), 4.0, 1.6, 4, GOLD)
		"blood_rage":
			_flame(ci, Vector2(16, 13.5), 1.25, 0.0, Color("#e02020"))
			_heart(ci, Vector2(16, 18), 0.95, Color("#ff7070"), Color("#700808"))
			ci.draw_circle(Vector2(13, 16), 1.2, Color(1, 1, 1, 0.6), true, -1.0, true)
			_drop(ci, Vector2(16, 28.5), 0.55, Color("#ff3030"))
		"arcane_surge":
			_glow_line(ci, _loop(_ellipse(c, 13.0, 4.5, 28)), 0.7)
			_energy(ci, _pts([16, 3, 21.5, 14, 16, 29, 10.5, 14]))
			ci.draw_polyline(_pts([10.5, 14, 16, 16, 21.5, 14]), Color(1, 1, 1, 0.6), 0.6, true)
			ci.draw_line(Vector2(16, 3), Vector2(16, 29), Color(1, 1, 1, 0.4), 0.5, true)
			_sparkle(ci, Vector2(6, 7), 2.8)
			_sparkle(ci, Vector2(26, 24), 2.4)
		"stone_golem":
			_at(ci, c, 0.0, 1.35)
			_metal(ci, _pts([-6, -7, 6, -7, 7.5, 0, 5.5, 7, -5.5, 7, -7.5, 0]), STONE_L, STONE_D)
			_metal(ci, _pts([-6.5, -3.5, 6.5, -3.5, 6.5, -1.5, -6.5, -1.5]), Color("#a89880"), Color("#4a4034"))
			for x in [-3.0, 3.0]:
				_energy(ci, _pts([x - 1.6, -0.8, x + 1.6, -0.8, x + 1.2, 1.0, x - 1.2, 1.0]), Color("#80f0d0"))
			_metal(ci, _pts([-3.5, 3.5, 3.5, 3.5, 3, 5.5, -3, 5.5]), Color("#3a3028"), Color("#1a1410"))
			ci.draw_polyline(_pts([2, -7, 1, -5, 3, -3.5]), Color(0, 0, 0, 0.5), 0.5, true)
			_home(ci)
		"spirit_wolves":
			_at(ci, Vector2(16, 17), 0.0, 1.45)
			_energy(ci, _pts([-6.5, 6, -6.5, -1, -5.5, -8.5, -3, -4, -1, -8.5, 1, -3, 5, -1, 8.5, 1.5, 7.5, 3.5, 3, 3.5, 1, 7, -3, 7]))
			ci.draw_circle(Vector2(1.5, -1), 0.9, Color("#ffffff"), true, -1.0, true)
			ci.draw_circle(Vector2(8, 1.5), 0.7, Color("#102030"), true, -1.0, true)
			ci.draw_line(Vector2(3.5, 3.5), Vector2(6.5, 3.5), Color("#102030"), 0.4, true)
			_home(ci)
		"phantom_host":
			_ghost(ci, Vector2(8.5, 12), 0.9, Color(_g, 0.55))
			_ghost(ci, Vector2(23.5, 12), 0.9, Color(_g, 0.55))
			_ghost(ci, Vector2(16, 17), 1.35)
		"blink":
			ci.draw_arc(Vector2(8, 23), 4.5, 0.0, TAU, 24, Color(_g, 0.45), 0.8, true)
			ci.draw_circle(Vector2(8, 23), 4.0, Color(_g, 0.15), true, -1.0, true)
			var dash := PackedVector2Array()
			for k in 4:
				var t := 0.18 + k * 0.17
				dash.append_array([Vector2(8, 23).lerp(Vector2(24, 9), t), Vector2(8, 23).lerp(Vector2(24, 9), t + 0.09)])
			_glow_segs(ci, dash, 0.9)
			_star(ci, Vector2(24, 9), 6.5, 2.0, 4)
			_bolt(ci, Vector2(24, 9), Vector2(28, 19), 0.6, 0.8)
		"leap_slam":
			var path := _arc(Vector2(15, 27), 12.0, PI + 0.25, TAU - 0.75, 14)
			var dashes := PackedVector2Array()
			for i in range(0, path.size() - 1, 2):
				dashes.append_array([path[i], path[i + 1]])
			_glow_segs(ci, dashes, 0.8)
			_ground(ci, 26)
			_star(ci, Vector2(24, 25), 5.5, 2.0, 6, Color("#ffd890"))
			_sword(ci, Vector2(24, 15), PI, 0.62)
		# auras: a dashed halo around the motif, like the ring they leave on the ground
		"hearth_ward", "ember_heart", "frost_veil", "gale_hymn", "crimson_pact":
			var halo := PackedVector2Array()
			for k in 10:
				var a := TAU * k / 10.0
				halo.append_array([c + Vector2.from_angle(a) * 13.0, c + Vector2.from_angle(a + 0.38) * 13.0])
			_glow_segs(ci, halo, 0.8)
			match id:
				"hearth_ward":
					_shield(ci, Vector2(16, 17), 1.05, Color("#f0d8a0"), Color("#7a5a30"))
					_flame(ci, Vector2(16, 16.5), 0.62, 0.0, Color("#ffb050"))
				"ember_heart":
					_heart(ci, Vector2(16, 17), 0.9, Color("#ff9a60"), Color("#701a08"))
					_flame(ci, Vector2(16, 10), 0.55, 0.0)
					_sparkle(ci, Vector2(22, 9), 2.2)
				"frost_veil":
					_waves(ci, c, [8.5], PI + 0.3, TAU - 0.3)
					_snowflake(ci, Vector2(16, 18), 6.0)
				"gale_hymn":
					_spiral(ci, c, 9.0, 1.6, 1.1)
					_chevron(ci, 18, 16, 0.55, _g)
				"crimson_pact":
					_drop(ci, Vector2(16, 15), 1.0, Color("#ff3040"))
					_star(ci, Vector2(16, 24.5), 3.6, 1.4, 4, Color("#ffd0d0"))
		_:
			_orb(ci, c, 7.0)
