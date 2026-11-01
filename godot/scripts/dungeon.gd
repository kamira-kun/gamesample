class_name Dungeon
extends RefCounted
## Grid dungeon: rooms joined by corridors. Gameplay runs on this flat grid;
## positions are Vector2(x, z) in meters, one tile = T meters.

const T := 2.0

var w: int
var h: int
var level: int
var tiles := PackedByteArray()   # 0 = wall, 1 = floor
var blocked := PackedByteArray() # 1 = floor tile occupied by a prop
var noise := PackedByteArray()
var flow := PackedInt32Array()
var rooms: Array = []            # Dictionary {x, y, w, h, cx, cy}
var start: Dictionary
var boss_room: Dictionary


func _init(width: int, height: int, lvl: int) -> void:
	w = width
	h = height
	level = lvl
	tiles.resize(w * h)
	blocked.resize(w * h)
	noise.resize(w * h)
	for i in noise.size():
		noise[i] = randi() % 256
	flow.resize(w * h)
	_generate()


func idx(x: int, y: int) -> int:
	return y * w + x


func is_wall(tx: int, ty: int) -> bool:
	return tx < 0 or ty < 0 or tx >= w or ty >= h or tiles[ty * w + tx] == 0 or blocked[ty * w + tx] == 1


func solid_at(p: Vector2) -> bool:
	return is_wall(floori(p.x / T), floori(p.y / T))


func tile_center(tx: int, ty: int) -> Vector2:
	return Vector2(tx * T + T / 2.0, ty * T + T / 2.0)


func _carve(x: int, y: int) -> void:
	if x > 0 and y > 0 and x < w - 1 and y < h - 1:
		tiles[y * w + x] = 1


func _generate() -> void:
	var target := 9 + mini(6, level / 2)
	var attempts := 0
	while attempts < 500 and rooms.size() < target:
		attempts += 1
		var rw := randi_range(7, 13)
		var rh := randi_range(6, 11)
		var x := randi_range(2, w - rw - 3)
		var y := randi_range(2, h - rh - 3)
		var overlap := false
		for o in rooms:
			if x < o.x + o.w + 3 and x + rw + 3 > o.x and y < o.y + o.h + 3 and y + rh + 3 > o.y:
				overlap = true
				break
		if overlap:
			continue
		rooms.append({"x": x, "y": y, "w": rw, "h": rh, "cx": x + rw / 2, "cy": y + rh / 2})
		for yy in range(y, y + rh):
			for xx in range(x, x + rw):
				_carve(xx, yy)

	# connect every room to its nearest earlier room, then add a couple of loops
	for i in range(1, rooms.size()):
		var best := 0
		var bd := INF
		for j in i:
			var d := Vector2(rooms[i].cx, rooms[i].cy).distance_squared_to(Vector2(rooms[j].cx, rooms[j].cy))
			if d < bd:
				bd = d
				best = j
		_corridor(rooms[i], rooms[best])
	for k in 2:
		_corridor(rooms.pick_random(), rooms.pick_random())

	for r in rooms:
		# ragged edges so rooms don't look like boxes
		for n in 6:
			var side := randi_range(0, 3)
			var x: int = randi_range(r.x, r.x + r.w - 1) if side < 2 else (r.x - 1 if side == 2 else r.x + r.w)
			var y: int = randi_range(r.y, r.y + r.h - 1) if side >= 2 else (r.y - 1 if side == 0 else r.y + r.h)
			_carve(x, y)
		# pillars in big rooms
		if r.w >= 10 and r.h >= 9 and randf() < 0.6:
			for pp in [Vector2i(r.x + 2, r.y + 2), Vector2i(r.x + r.w - 3, r.y + 2), Vector2i(r.x + 2, r.y + r.h - 3), Vector2i(r.x + r.w - 3, r.y + r.h - 3)]:
				tiles[idx(pp.x, pp.y)] = 0

	start = rooms[0]
	compute_flow(tile_center(start.cx, start.cy), 9999)
	boss_room = rooms[1]
	var far := -1
	for r in rooms.slice(1):
		var d := flow[idx(r.cx, r.cy)]
		if d > far:
			far = d
			boss_room = r


func _corridor(a: Dictionary, b: Dictionary) -> void:
	var cw := randi_range(2, 3)
	if randf() < 0.5:
		_hline(a.cx, b.cx, a.cy, cw)
		_vline(a.cy, b.cy, b.cx, cw)
	else:
		_vline(a.cy, b.cy, a.cx, cw)
		_hline(a.cx, b.cx, b.cy, cw)


func _hline(x0: int, x1: int, y: int, cw: int) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + cw):
		for k in cw:
			_carve(x, y + k)


func _vline(y0: int, y1: int, x: int, cw: int) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + cw):
		for k in cw:
			_carve(x + k, y)


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


func circle_hits(p: Vector2, r: float) -> bool:
	return solid_at(p + Vector2(-r, -r)) or solid_at(p + Vector2(r, -r)) or solid_at(p + Vector2(-r, r)) or solid_at(p + Vector2(r, r))


## slide a circle along the walls; returns the new position
func move_circle(p: Vector2, r: float, delta: Vector2) -> Vector2:
	if not circle_hits(Vector2(p.x + delta.x, p.y), r):
		p.x += delta.x
	if not circle_hits(Vector2(p.x, p.y + delta.y), r):
		p.y += delta.y
	return p
