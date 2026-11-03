class_name Dungeon
extends RefCounted
## Grid dungeon: rooms joined by corridors, laid out along a map's fixed route (Maps). Gameplay runs on this flat grid;
## positions are Vector2(x, z) in meters, one tile = T meters.

const T := 2.0

var w: int
var h: int
var level: int
var tiles := PackedByteArray()   # 0 = wall, 1 = floor
var blocked := PackedByteArray() # 1 = floor tile occupied by a prop
var noise := PackedByteArray()
var flow := PackedInt32Array()
var seen := PackedByteArray()    # 1 = tile explored, shown on the map overlay (see reveal); a new map starts unexplored
var rooms: Array = []            # Dictionary {x, y, w, h, cx, cy}
var start: Dictionary
var boss_room: Dictionary


func _init(width: int, height: int, lvl: int, layout := "") -> void:
	w = width
	h = height
	level = lvl
	tiles.resize(w * h)
	blocked.resize(w * h)
	noise.resize(w * h)
	for i in noise.size():
		noise[i] = randi() % 256
	flow.resize(w * h)
	seen.resize(w * h)
	if layout == "hideout":
		_make_hideout()
	else:
		_make_route(Maps.def(layout))


func idx(x: int, y: int) -> int:
	return y * w + x


func is_wall(tx: int, ty: int) -> bool:
	return tx < 0 or ty < 0 or tx >= w or ty >= h or tiles[ty * w + tx] == 0 or blocked[ty * w + tx] == 1


func solid_at(p: Vector2) -> bool:
	return is_wall(floori(p.x / T), floori(p.y / T))


func tile_center(tx: int, ty: int) -> Vector2:
	return Vector2(tx * T + T / 2.0, ty * T + T / 2.0)


## mark the tiles whose centre is within `radius` meters of `p` explored; returns the indices newly explored
func reveal(p: Vector2, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r := ceili(radius / T)
	var c := Vector2i(floori(p.x / T), floori(p.y / T))
	for ty in range(maxi(0, c.y - r), mini(h, c.y + r + 1)):
		for tx in range(maxi(0, c.x - r), mini(w, c.x + r + 1)):
			var i := ty * w + tx
			if seen[i] == 0 and tile_center(tx, ty).distance_squared_to(p) <= radius * radius:
				seen[i] = 1
				out.append(i)
	return out


func seen_at(p: Vector2) -> bool:
	var tx := floori(p.x / T)
	var ty := floori(p.y / T)
	return tx >= 0 and ty >= 0 and tx < w and ty < h and seen[ty * w + tx] == 1


func _carve(x: int, y: int) -> void:
	if x > 0 and y > 0 and x < w - 1 and y < h - 1:
		tiles[y * w + x] = 1


## a single hand-laid hall with four pillars
func _make_hideout() -> void:
	var r := {"x": 6, "y": 6, "w": 15, "h": 13}
	r.cx = r.x + r.w / 2
	r.cy = r.y + r.h / 2
	for yy in range(r.y, r.y + r.h):
		for xx in range(r.x, r.x + r.w):
			_carve(xx, yy)
	for pp in [Vector2i(r.x + 2, r.y + 2), Vector2i(r.x + r.w - 3, r.y + 2), Vector2i(r.x + 2, r.y + r.h - 3), Vector2i(r.x + r.w - 3, r.y + r.h - 3)]:
		tiles[idx(pp.x, pp.y)] = 0
	rooms.append(r)
	start = r
	boss_room = r


## a map's fixed layout (Maps): a room on every route point, corridors along the route's chains; sizes, ragged
## edges and pillars come from the RNG, which the caller seeds per map (see Main.spawn_floor)
func _make_route(m: Dictionary) -> void:
	var cw := randi_range(2, 3)
	var pts := Maps.points(m)
	for i in pts.size():
		var c := Maps.tile_of(pts[i])
		var boss := i == pts.size() - 1
		var rw := randi_range(9, 10) if boss else (randi_range(6, 7) if i == 0 else randi_range(4, 7))
		var rh := randi_range(9, 10) if boss else (randi_range(6, 7) if i == 0 else randi_range(4, 7))
		var r := {"x": c.x - rw / 2, "y": c.y - rh / 2, "w": rw, "h": rh, "cx": c.x, "cy": c.y}
		rooms.append(r)
		for yy in range(r.y, r.y + r.h):
			for xx in range(r.x, r.x + r.w):
				_carve(xx, yy)
	for ch in Maps.chains(m):
		for j in range(1, ch.size()):
			_tunnel(Maps.tile_of(ch[j - 1]), Maps.tile_of(ch[j]), cw)

	for r in rooms:
		# ragged edges so rooms don't look like boxes
		for n in 6:
			var side := randi_range(0, 3)
			var x: int = randi_range(r.x, r.x + r.w - 1) if side < 2 else (r.x - 1 if side == 2 else r.x + r.w)
			var y: int = randi_range(r.y, r.y + r.h - 1) if side >= 2 else (r.y - 1 if side == 0 else r.y + r.h)
			_carve(x, y)
		# pillars in big rooms
		if r.w >= 9 and r.h >= 9 and randf() < 0.6:
			for pp in [Vector2i(r.x + 2, r.y + 2), Vector2i(r.x + r.w - 3, r.y + 2), Vector2i(r.x + 2, r.y + r.h - 3), Vector2i(r.x + r.w - 3, r.y + r.h - 3)]:
				tiles[idx(pp.x, pp.y)] = 0

	start = rooms[0]
	boss_room = rooms[-1]


## a straight corridor `cw` tiles wide from tile a to tile b (diagonals one tile wider, so they stay walkable)
func _tunnel(a: Vector2i, b: Vector2i, cw: int) -> void:
	var d := b - a
	var steps := maxi(absi(d.x), absi(d.y))
	var wide := cw + (1 if d.x != 0 and d.y != 0 else 0)
	for s in steps + 1:
		var p := Vector2(a).lerp(Vector2(b), float(s) / maxi(steps, 1)).round()
		for yy in wide:
			for xx in wide:
				_carve(int(p.x) - wide / 2 + xx, int(p.y) - wide / 2 + yy)


func random_floor_in(room: Dictionary) -> Vector2:
	for i in 40:
		var tx := randi_range(room.x + 1, room.x + room.w - 2)
		var ty := randi_range(room.y + 1, room.y + room.h - 2)
		if not is_wall(tx, ty):
			return tile_center(tx, ty)
	return tile_center(room.cx, room.cy)


## BFS distance field from a position; enemies walk downhill on it
func compute_flow(p: Vector2, max_d := 45) -> void:
	flow.fill(-1)
	var sx := floori(p.x / T)
	var sy := floori(p.y / T)
	if is_wall(sx, sy):
		return
	var queue := PackedInt32Array([idx(sx, sy)])
	flow[idx(sx, sy)] = 0
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var d := flow[c]
		if d >= max_d:
			continue
		var cx := c % w
		var cy := c / w
		for nb in [Vector2i(cx + 1, cy), Vector2i(cx - 1, cy), Vector2i(cx, cy + 1), Vector2i(cx, cy - 1)]:
			if is_wall(nb.x, nb.y):
				continue
			var ni := idx(nb.x, nb.y)
			if flow[ni] != -1:
				continue
			flow[ni] = d + 1
			queue.append(ni)


## next tile center toward the flow source, or Vector2.INF when there is none
func flow_next(p: Vector2) -> Vector2:
	var tx := floori(p.x / T)
	var ty := floori(p.y / T)
	if is_wall(tx, ty):
		return Vector2.INF
	var cur := flow[idx(tx, ty)]
	if cur < 0:
		return Vector2.INF
	var best := cur
	var bx := tx
	var by := ty
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := tx + dx
			var ny := ty + dy
			if is_wall(nx, ny):
				continue
			if dx != 0 and dy != 0 and (is_wall(tx + dx, ty) or is_wall(tx, ty + dy)):
				continue
			var v := flow[idx(nx, ny)]
			if v >= 0 and v < best:
				best = v
				bx = nx
				by = ny
	if bx == tx and by == ty:
		return Vector2.INF
	return tile_center(bx, by)


func los(a: Vector2, b: Vector2) -> bool:
	var steps := ceili(a.distance_to(b) / (T / 3.0))
	for i in range(1, steps):
		if solid_at(a.lerp(b, float(i) / steps)):
			return false
	return true


## samples the circle's bounding square at most a tile apart, so a big body (a boss) can't straddle a lone wall or prop tile
func circle_hits(p: Vector2, r: float) -> bool:
	var n := maxi(1, ceili(2.0 * r / T))
	for i in n + 1:
		for j in n + 1:
			if solid_at(p + Vector2(-r + 2.0 * r * i / n, -r + 2.0 * r * j / n)):
				return true
	return false


## slide a circle along the walls; returns the new position
func move_circle(p: Vector2, r: float, delta: Vector2) -> Vector2:
	if not circle_hits(Vector2(p.x + delta.x, p.y), r):
		p.x += delta.x
	if not circle_hits(Vector2(p.x, p.y + delta.y), r):
		p.y += delta.y
	return p
