class_name MapOverlay
extends Control
## The map overlay (M by default): the explored part of the current map drawn over the game, centred on the
## player and turned to match the camera, with the player and the places found so far (exit portal, map device,
## merchant, stash, exchange, forge, training dummy, cinder altars, sealed monolith).
## Tiles are explored around the player as they move (Dungeon.seen, kept on the map so a new map starts blank).
## The picture is an Image with one pixel per tile: only newly explored pixels are written, and the texture is
## re-uploaded only when some were. Transparency and zoom come from Settings and apply as they change.

const T := Dungeon.T
const REVEAL := 17.0             # meters around the player explored
const CAM_YAW := PI / 4.0       # as main.gd's camera
const PX_PER_METER := 4.0        # at 100% zoom
const FLOOR := Color(0.6, 0.53, 0.42, 0.6)
const EDGE := Color(0.96, 0.82, 0.56, 0.95)
const BACKDROP := Color(0.0, 0.0, 0.0, 0.3)
const NO_TILE := Vector2i(-100000, 0)
const POIS := {
	"portal": ["出口", Color("#9ad0ff")],
	"device": ["遠征図の祭壇", Color("#c890ff")],
	"merchant": ["商人", Color("#ffd36a")],
	"stash": ["スタッシュ", Color("#e8c890")],
	"exchange": ["取引所", Color("#c070ff")],
	"forge": ["燼火の炉", Color("#ff9a50")],
	"dummy": ["燼藁のカカシ", Color("#d8b070")],
	"altar": ["燼火の祭壇", Color("#ff7a3a")],
	"seal": ["刻紋の封碑", Color("#7ae0c8")],
}

var hud: Hud
var map: Dungeon          # the map the picture is of; another one starts a new picture
var img: Image
var tex: ImageTexture
var last_tile := NO_TILE
var uploads := 0          # texture updates so far (the smoke test checks standing still costs none)


func _ready() -> void:
	visible = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	apply_settings()


func toggle() -> void:
	visible = not visible
	queue_redraw()


func apply_settings() -> void:
	modulate.a = Settings.map_opacity()
	queue_redraw()


## screen pixels per meter at the current zoom
func scale_px() -> float:
	return PX_PER_METER * Settings.map_zoom / 100.0


## explore around `pos` on `m` (called every frame; does work only when the player enters another tile)
func track(m: Dungeon, pos: Vector2) -> void:
	if m != map:
		map = m
		img = Image.create(m.w, m.h, false, Image.FORMAT_RGBA8)
		for i in m.seen.size():
			if m.seen[i] == 1:
				_paint(i)
		tex = ImageTexture.create_from_image(img)
		last_tile = NO_TILE
	var t := Vector2i(floori(pos.x / T), floori(pos.y / T))
	if t == last_tile:
		return
	last_tile = t
	var fresh := m.reveal(pos, REVEAL)
	if fresh.is_empty():
		return
	for i in fresh:
		_paint(i)
	tex.update(img)
	uploads += 1


## floor tiles are filled; a wall shows only as the edge of the floor it borders
func _paint(i: int) -> void:
	var x := i % map.w
	var y := i / map.w
	if map.tiles[i] == 1:
		img.set_pixel(x, y, FLOOR)
		return
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var nx: int = x + dx
			var ny: int = y + dy
			if nx >= 0 and ny >= 0 and nx < map.w and ny < map.h and map.tiles[ny * map.w + nx] == 1:
				img.set_pixel(x, y, EDGE)
				return


## the places to mark that the player has explored: [{kind, name, pos}]
func pois() -> Array:
	var m = hud.main
	var out := []
	if not m.portal.is_empty():
		out.append({"kind": "portal", "pos": m.portal.pos})
	for o in m.interacts:
		if POIS.has(o.kind):
			out.append({"kind": o.kind, "pos": o.pos})
	return out.filter(func(q): return map != null and map.seen_at(q.pos))


## world (x, z) to screen: centred on the player, turned 45 degrees like the camera so "up" is up on screen
func to_screen(p: Vector2) -> Vector2:
	return xform() * p


func xform() -> Transform2D:
	var s := scale_px()
	return Transform2D(CAM_YAW, Vector2(s, s), 0.0, size / 2.0) * Transform2D(0.0, -hud.main.player.pos)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if map == null or tex == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), BACKDROP)
	draw_set_transform_matrix(xform())
	draw_texture_rect(tex, Rect2(0, 0, map.w * T, map.h * T), false)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	for q in pois():
		var at := to_screen(q.pos)
		var info: Array = POIS[q.kind]
		draw_circle(at, 7.0, Color(0, 0, 0, 0.8))
		draw_circle(at, 5.0, info[1])
		draw_string_outline(Data.ui_font, at + Vector2(-80, -10), info[0], HORIZONTAL_ALIGNMENT_CENTER, 160, 13, 3, Color.BLACK)
		draw_string(Data.ui_font, at + Vector2(-80, -10), info[0], HORIZONTAL_ALIGNMENT_CENTER, 160, 13, info[1])
	# the player: an arrow pointing the way they face
	var p = hud.main.player
	var c := to_screen(p.pos)
	var f: Vector2 = (to_screen(p.pos + Vector2.from_angle(p.face)) - c).normalized()
	draw_arc(c, 13.0, 0.0, TAU, 32, Color("#fff4d0", 0.7), 2.0)
	var pts := PackedVector2Array([c + f * 12.0, c + f.rotated(2.4) * 9.0, c - f * 4.0, c + f.rotated(-2.4) * 9.0])
	draw_colored_polygon(pts, Color("#fff4d0"))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.9), 2.0)
