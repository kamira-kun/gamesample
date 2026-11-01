class_name ItemIcon
extends RefCounted
## Vector icons for equipment bases, drawn on a 32x32 grid and scaled into a rect.

const STEEL := Color("#c3c8cf")
const STEEL_D := Color("#7a818b")
const WOOD := Color("#8a5a32")
const LEATHER := Color("#9a6a3e")
const LEATHER_D := Color("#5e3c22")
const CLOTH := Color("#5f4f9a")
const GOLD := Color("#e0b040")
const DARK := Color("#140e0a")
const LINE := Color(0, 0, 0, 0.85)

# per-base tilt, so weapons lie diagonally like in a bag
const TILT := {"片手剣": -0.785, "短剣": -0.785, "戦斧": -0.4, "大槌": -0.45, "ルーンの杖": -0.4}


## false when the base has no icon (the caller falls back to the slot glyph)
static func draw(ci: CanvasItem, base: String, rect: Rect2, accent: Color) -> bool:
	if not _has(base):
		return false
	var s := minf(rect.size.x, rect.size.y) / 32.0 * 0.82
	ci.draw_set_transform_matrix(Transform2D(TILT.get(base, 0.0), Vector2(s, s), 0.0, rect.get_center()) * Transform2D(0.0, Vector2(-16, -16)))
	match base:
		"片手剣": _sword(ci, accent)
		"短剣": _dagger(ci, accent)
		"戦斧": _axe(ci)
		"大槌": _hammer(ci)
		"ルーンの杖": _staff(ci, accent)
		"革の頭巾": _hood(ci)
		"鉄兜": _helm(ci)
		"布のローブ": _robe(ci)
		"鎖帷子": _chain(ci)
		"板金鎧": _plate(ci)
		"革手袋": _glove(ci, LEATHER, false)
		"鉄の篭手": _glove(ci, STEEL, true)
		"革靴": _boot(ci, LEATHER, false)
		"鉄靴": _boot(ci, STEEL, true)
		"銅の指輪": _ring(ci, Color("#c87848"), Color("#e04a3a"))
		"銀の指輪": _ring(ci, Color("#dde1e8"), Color("#4a8aff"))
		"金の指輪": _ring(ci, GOLD, Color("#eaf6ff"))
		"牙の首飾り": _fang(ci)
		"琥珀の護符": _amber(ci)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	return true


static func _has(base: String) -> bool:
	return base in ["片手剣", "短剣", "戦斧", "大槌", "ルーンの杖", "革の頭巾", "鉄兜", "布のローブ", "鎖帷子", "板金鎧",
		"革手袋", "鉄の篭手", "革靴", "鉄靴", "銅の指輪", "銀の指輪", "金の指輪", "牙の首飾り", "琥珀の護符"]


# =================== primitives ===================
static func _poly(ci: CanvasItem, pts: PackedVector2Array, fill: Color) -> void:
	ci.draw_colored_polygon(pts, fill)
	var loop := pts.duplicate()
	loop.append(pts[0])
	ci.draw_polyline(loop, LINE, 1.2, true)


static func _rect(ci: CanvasItem, a: Vector2, b: Vector2, fill: Color) -> void:
	_poly(ci, PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)]), fill)


static func _dot(ci: CanvasItem, c: Vector2, r: float, fill: Color) -> void:
	ci.draw_circle(c, r + 0.7, LINE, true, -1.0, true)
	ci.draw_circle(c, r, fill, true, -1.0, true)


static func _line(ci: CanvasItem, a: Vector2, b: Vector2, c: Color, w := 1.0) -> void:
	ci.draw_line(a, b, c, w, true)


static func _arc_pts(c: Vector2, r: float, from: float, to: float, n := 12) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		out.append(c + Vector2.from_angle(lerpf(from, to, float(i) / n)) * r)
	return out


static func _v(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, arr.size(), 2):
		out.append(Vector2(arr[i], arr[i + 1]))
	return out


# =================== weapons (drawn upright, tilted by TILT) ===================
static func _sword(ci: CanvasItem, accent: Color) -> void:
	_poly(ci, _v([14, 4, 16, 0.5, 18, 4, 18, 21, 14, 21]), STEEL)
	_line(ci, Vector2(16, 4), Vector2(16, 20), STEEL_D)
	_rect(ci, Vector2(9, 21), Vector2(23, 24), GOLD)
	_rect(ci, Vector2(14.6, 24), Vector2(17.4, 29.5), LEATHER_D)
	_dot(ci, Vector2(16, 30.5), 1.8, accent)


static func _dagger(ci: CanvasItem, accent: Color) -> void:
	_poly(ci, _v([14, 9, 16, 4, 18, 9, 17.6, 21, 14.4, 21]), STEEL)
	_line(ci, Vector2(16, 8), Vector2(16, 20), STEEL_D)
	_poly(ci, _v([10.5, 21, 21.5, 21, 20.5, 23.2, 11.5, 23.2]), STEEL_D)
	_rect(ci, Vector2(14.8, 23.2), Vector2(17.2, 27.5), LEATHER_D)
	_dot(ci, Vector2(16, 28.8), 1.6, accent)


static func _axe(ci: CanvasItem) -> void:
	_rect(ci, Vector2(14.8, 4), Vector2(17.2, 31), WOOD)
	_poly(ci, _v([15, 7, 11, 8.5, 15, 10.5]), STEEL_D)
	_poly(ci, _v([17, 5.5, 22, 3.5, 26.5, 1.5, 28.5, 8.5, 26.5, 16, 22, 13.5, 17, 12]), STEEL)
	_line(ci, Vector2(26.8, 3), Vector2(27.2, 14.5), Color.WHITE.darkened(0.05), 1.2)
	_rect(ci, Vector2(14.4, 26), Vector2(17.6, 29), LEATHER_D)


static func _hammer(ci: CanvasItem) -> void:
	_rect(ci, Vector2(14.8, 10), Vector2(17.2, 31), WOOD)
	_rect(ci, Vector2(6, 2.5), Vector2(26, 11.5), STEEL)
	_rect(ci, Vector2(9.5, 2.5), Vector2(11.5, 11.5), STEEL_D)
	_rect(ci, Vector2(20.5, 2.5), Vector2(22.5, 11.5), STEEL_D)
	_line(ci, Vector2(6.8, 4), Vector2(25.2, 4), Color.WHITE, 1.0)
	_rect(ci, Vector2(14.4, 25), Vector2(17.6, 29), LEATHER_D)


static func _staff(ci: CanvasItem, accent: Color) -> void:
	_poly(ci, _v([15, 9, 17, 9, 17.4, 31, 14.6, 31]), WOOD)
	for y in [14.0, 19.0, 24.0]:
		_line(ci, Vector2(15, y), Vector2(17, y + 1.5), accent, 1.0)
	ci.draw_circle(Vector2(16, 6), 7.0, Color(accent, 0.22), true, -1.0, true)
	_poly(ci, _v([13, 11, 11, 6, 12.5, 2, 13.8, 6, 15, 9]), WOOD)
	_poly(ci, _v([19, 11, 21, 6, 19.5, 2, 18.2, 6, 17, 9]), WOOD)
	_dot(ci, Vector2(16, 6), 3.6, accent)
	ci.draw_circle(Vector2(14.8, 4.8), 1.0, Color(1, 1, 1, 0.8), true, -1.0, true)


# =================== armor ===================
static func _hood(ci: CanvasItem) -> void:
	_poly(ci, _v([6, 29, 5, 18, 8, 9, 16, 3, 24, 9, 27, 18, 26, 29]), LEATHER)
	_poly(ci, _v([11, 29, 10, 20, 13, 14, 16, 13, 19, 14, 22, 20, 21, 29]), DARK)
	for y in [7.0, 10.0]:
		_line(ci, Vector2(16 - y * 0.6, 4 + y), Vector2(16 - y * 0.6 - 1.5, 6 + y), LEATHER_D)
	_line(ci, Vector2(16, 4), Vector2(16, 12.5), LEATHER_D)


static func _helm(ci: CanvasItem) -> void:
	var pts := _arc_pts(Vector2(16, 17), 10.5, PI, TAU)
	pts.append_array(_v([26.5, 28, 19.5, 28, 18.5, 22, 13.5, 22, 12.5, 28, 5.5, 28]))
	_poly(ci, pts, STEEL)
	_poly(ci, _v([8.5, 16, 23.5, 16, 23.5, 19, 17.5, 19, 17.5, 26, 14.5, 26, 14.5, 19, 8.5, 19]), DARK)
	_line(ci, Vector2(16, 7), Vector2(16, 15), Color.WHITE, 1.4)
	for x in [8.0, 24.0]:
		_dot(ci, Vector2(x, 23), 0.8, STEEL_D)


static func _torso(sleeve: float) -> PackedVector2Array:
	return _v([11, 3, 21, 3, 25, 6, 29, 6 + sleeve, 25.5, 8 + sleeve, 23.5, 11, 24, 30, 8, 30, 8.5, 11, 6.5, 8 + sleeve, 3, 6 + sleeve, 7, 6])


static func _robe(ci: CanvasItem) -> void:
	_poly(ci, _torso(8), CLOTH)
	_poly(ci, _v([12.5, 3, 16, 10, 19.5, 3]), DARK)
	_line(ci, Vector2(16, 10), Vector2(16, 29.5), CLOTH.lightened(0.3), 1.4)
	_rect(ci, Vector2(8.6, 15), Vector2(23.6, 17.4), GOLD)


static func _chain(ci: CanvasItem) -> void:
	var body := _torso(4)
	_poly(ci, body, STEEL_D)
	for row in 9:
		for x in range(5, 29, 3):
			var p := Vector2(x + (1.5 if row % 2 == 0 else 0.0), 5 + row * 3)
			if Geometry2D.is_point_in_polygon(p, body):
				ci.draw_arc(p, 1.1, 0, TAU, 8, STEEL.lightened(0.1), 0.7, true)
	_poly(ci, _v([13, 3, 16, 6.5, 19, 3]), DARK)


static func _plate(ci: CanvasItem) -> void:
	_dot(ci, Vector2(7, 9), 4.5, STEEL_D)
	_dot(ci, Vector2(25, 9), 4.5, STEEL_D)
	_poly(ci, _v([9, 5, 13, 4, 16, 7, 19, 4, 23, 5, 24, 14, 22, 27, 16, 29.5, 10, 27, 8, 14]), STEEL)
	_line(ci, Vector2(16, 8), Vector2(16, 28.5), Color.WHITE, 1.3)
	_line(ci, Vector2(9.2, 18), Vector2(22.8, 18), STEEL_D, 1.1)
	_line(ci, Vector2(10.6, 23), Vector2(21.4, 23), STEEL_D, 1.1)


static func _glove(ci: CanvasItem, col: Color, iron: bool) -> void:
	for i in 4:
		var x := 9.2 + i * 3.45
		var top := 5.0 if i == 1 or i == 2 else 7.0
		_poly(ci, _v([x, 15, x, top + 1.5, x + 1.6, top, x + 3.2, top + 1.5, x + 3.2, 15]), col)
		if iron:
			_line(ci, Vector2(x + 0.4, top + 4.5), Vector2(x + 2.8, top + 4.5), STEEL_D)
	_poly(ci, _v([9.5, 17, 5.5, 12.5, 3.5, 14.5, 8, 23]), col)
	_poly(ci, _v([9, 14, 23, 14, 23, 24, 21, 28, 11, 28, 9, 24]), col)
	if iron:
		_rect(ci, Vector2(9, 14), Vector2(23, 17), STEEL_D)
		_poly(ci, _v([9.5, 26, 22.5, 26, 25, 31, 7, 31]), STEEL_D)
	else:
		_rect(ci, Vector2(10, 26), Vector2(22, 31), LEATHER_D)


static func _boot(ci: CanvasItem, col: Color, iron: bool) -> void:
	_poly(ci, _v([10, 3, 20, 3, 20, 18, 26, 20, 29, 24, 29, 28, 9, 28, 9.5, 18]), col)
	_rect(ci, Vector2(8.6, 27.5), Vector2(29.4, 30.5), DARK.lightened(0.15))
	if iron:
		_rect(ci, Vector2(9.5, 3), Vector2(20.5, 6.5), STEEL_D)
		_poly(ci, _v([21, 19.5, 26, 20, 29, 24, 29, 27.5, 22, 27.5]), STEEL_D)
		_line(ci, Vector2(10, 12), Vector2(20, 12), STEEL_D, 1.1)
	else:
		_rect(ci, Vector2(9.5, 3), Vector2(20.5, 6.5), LEATHER_D)
		for y in [10.0, 13.5, 17.0]:
			_line(ci, Vector2(17, y), Vector2(20.5, y + 1.2), Color("#e8d8b8"), 0.9)


# =================== jewelry ===================
static func _ring(ci: CanvasItem, metal: Color, gem: Color) -> void:
	var c := Vector2(16, 19)
	ci.draw_arc(c, 8.0, 0, TAU, 32, LINE, 5.8, true)
	ci.draw_arc(c, 8.0, 0, TAU, 32, metal, 3.6, true)
	ci.draw_arc(c, 8.6, PI * 1.1, PI * 1.6, 8, Color(1, 1, 1, 0.6), 1.0, true)
	_poly(ci, _v([12.5, 11, 19.5, 11, 18.5, 13.5, 13.5, 13.5]), metal.darkened(0.25))
	_poly(ci, _v([16, 3, 20.5, 7.5, 16, 12, 11.5, 7.5]), gem)
	_poly(ci, _v([16, 4.5, 18, 7, 16, 7.5]), Color(1, 1, 1, 0.55))


static func _cord(ci: CanvasItem, end: Vector2) -> void:
	var pts := PackedVector2Array()
	for i in 17:
		var t := float(i) / 16.0
		pts.append(Vector2(lerpf(5, 27, t), 2 + sin(t * PI) * (end.y - 2)))
	for i in pts.size():
		ci.draw_circle(pts[i], 0.9, GOLD.darkened(0.2) if i % 2 else GOLD, true, -1.0, true)


static func _fang(ci: CanvasItem) -> void:
	_cord(ci, Vector2(16, 15))
	for x in [12.0, 20.0]:
		_dot(ci, Vector2(x, 14.2), 1.2, Color("#a03828"))
	_poly(ci, _v([13.5, 15.5, 18.5, 15.5, 19.5, 21, 17.5, 27, 15, 30, 15.5, 23]), Color("#efe6cf"))
	_line(ci, Vector2(17.2, 17), Vector2(16.4, 26), Color("#b8ac90"), 1.0)


static func _amber(ci: CanvasItem) -> void:
	_cord(ci, Vector2(16, 15))
	_dot(ci, Vector2(16, 22), 7.0, GOLD)
	_dot(ci, Vector2(16, 22), 5.0, Color("#e08a1c"))
	ci.draw_circle(Vector2(16, 22), 3.0, Color("#ffc050"), true, -1.0, true)
	ci.draw_circle(Vector2(14, 20), 1.2, Color(1, 1, 1, 0.75), true, -1.0, true)
