class_name LevelBuilder
extends RefCounted
## Dresses a Dungeon grid with KayKit pieces: floor tiles, thin wall panels on
## floor/wall edges, pillars, wall torches and room props.

const WALL_SCALE := 0.55   # KayKit walls are 4 m tall; squash them so the camera sees over
# floor piece picked by the tile's noise value (0-255)
const FLOOR_PIECES := [["floor_tile_small", 196], ["floor_tile_small_broken_A", 218], ["floor_tile_small_broken_B", 236],
	["floor_tile_small_weeds_A", 248], ["floor_tile_small_decorated", 256]]
const PROPS := [["barrel_small", 0.8], ["box_small", 0.8], ["barrel_large", 0.5], ["crates_stacked", 0.6], ["keg", 0.5],
	["box_stacked", 0.4], ["chest", 0.6], ["trunk_medium_A", 0.7]]
const MAX_TORCHES := 16

var map: Dungeon
var theme: Dictionary
var root: Node3D
var batches := {}          # piece name -> Array of Transform3D


static func build(dungeon: Dungeon, level_theme: Dictionary, parent: Node3D) -> void:
	var b := LevelBuilder.new()
	b.map = dungeon
	b.theme = level_theme
	b.root = parent
	b._place_props()       # first, so props block their tiles before walls are laid
	b._floors()
	b._walls()
	b._flush()


func _add(piece_name: String, xf: Transform3D) -> void:
	if not batches.has(piece_name):
		batches[piece_name] = []
	batches[piece_name].append(xf)


func _rock(tx: int, ty: int) -> bool:
	return tx < 0 or ty < 0 or tx >= map.w or ty >= map.h or map.tiles[map.idx(tx, ty)] == 0


func _floors() -> void:
	for ty in map.h:
		for tx in map.w:
			if _rock(tx, ty):
				continue
			var n := map.noise[map.idx(tx, ty)]
			var piece_name: String = FLOOR_PIECES[0][0]
			for fp in FLOOR_PIECES:
				if n < fp[1]:
					piece_name = fp[0]
					break
			var basis := Basis(Vector3.UP, (n % 4) * PI / 2.0)
			_add(piece_name, Transform3D(basis, Vector3(tx * Dungeon.T + 1.0, 0.0, ty * Dungeon.T + 1.0)))


## a wall tile surrounded by floor on all four sides becomes a pillar
func _isolated(tx: int, ty: int) -> bool:
	return _rock(tx, ty) and not _rock(tx + 1, ty) and not _rock(tx - 1, ty) and not _rock(tx, ty + 1) and not _rock(tx, ty - 1)


func _walls() -> void:
	var T := Dungeon.T
	var tall := Basis.from_scale(Vector3(1, WALL_SCALE, 1))
	var side := Basis(Vector3.UP, -PI / 2.0) * tall      # panel running along +Z
	var filler := Basis.from_scale(Vector3(0.5, WALL_SCALE, 1))
	var fillers := {}
	var torch_spots: Array = []
	for ty in map.h:
		for tx in map.w:
			if _rock(tx, ty):
				if _isolated(tx, ty):
					_add("pillar", Transform3D(tall, Vector3(tx * T + 1.0, 0, ty * T + 1.0)))
				continue
			var x0 := tx * T
			var z0 := ty * T
			# panels sit inside the neighbouring wall tile, 1 m thick
			if _rock(tx, ty - 1) and not _isolated(tx, ty - 1):
				_add("wall_half", Transform3D(tall, Vector3(x0, 0, z0 - 0.5)))
				torch_spots.append({"pos": Vector3(x0 + 1.0, 1.25, z0), "rot": 0.0})
			if _rock(tx, ty + 1) and not _isolated(tx, ty + 1):
				_add("wall_half", Transform3D(tall, Vector3(x0, 0, z0 + T + 0.5)))
			if _rock(tx - 1, ty) and not _isolated(tx - 1, ty):
				_add("wall_half", Transform3D(side, Vector3(x0 - 0.5, 0, z0)))
				torch_spots.append({"pos": Vector3(x0, 1.25, z0 + 1.0), "rot": PI / 2.0})
			if _rock(tx + 1, ty) and not _isolated(tx + 1, ty):
				_add("wall_half", Transform3D(side, Vector3(x0 + T + 0.5, 0, z0)))
			# fill the 1 m gap where two panels meet at an inside corner
			for d in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
				if _rock(tx + d.x, ty) and _rock(tx, ty + d.y) and _rock(tx + d.x, ty + d.y):
					var vx := (tx + (1 if d.x > 0 else 0)) * T
					var vz := (ty + (1 if d.y > 0 else 0)) * T
					var c := Vector3(vx + d.x * 0.5, 0, vz + d.y * 0.5)
					if not fillers.has(c):
						fillers[c] = true
						_add("wall_half", Transform3D(filler, c - Vector3(0.5, 0, 0)))
	_torches(torch_spots)


## torches only on wall faces that look toward the camera (north and west walls of a room)
func _torches(spots: Array) -> void:
	spots.shuffle()
	var placed: Array[Vector3] = []
	for s in spots:
		if placed.size() >= MAX_TORCHES:
			break
		var far := true
		for q in placed:
			if q.distance_to(s.pos) < 12.0:
				far = false
				break
		if not far:
			continue
		placed.append(s.pos)
		var torch := Assets.piece("torch_mounted")
		torch.position = s.pos
		torch.rotation.y = s.rot
		root.add_child(torch)
		var light := OmniLight3D.new()
		light.light_color = theme.torch
		light.light_energy = 1.4
		light.omni_range = 8.0
		light.position = s.pos + Vector3(0, 0.6, 0) + Vector3(sin(s.rot), 0, cos(s.rot)) * 0.6
		root.add_child(light)
		var flame := CPUParticles3D.new()
		flame.amount = 10
		flame.lifetime = 0.5
		flame.mesh = Fx.sphere(0.05)
		flame.material_override = Fx.mat(Color("#ffb050"), 6.0, true)
		flame.direction = Vector3.UP
		flame.spread = 15.0
		flame.gravity = Vector3(0, 2.0, 0)
		flame.initial_velocity_min = 0.3
		flame.initial_velocity_max = 0.8
		flame.position = light.position - Vector3(0, 0.15, 0)
		root.add_child(flame)


## a few props along the inner walls of each room; their tiles become blocked
func _place_props() -> void:
	for room in map.rooms:
		if room == map.start:
			continue
		var count := randi_range(2, 5)
		for k in 20:
			if count <= 0:
				break
			var tx := randi_range(room.x, room.x + room.w - 1)
			var ty := randi_range(room.y, room.y + room.h - 1)
			var edge := _rock(tx + 1, ty) or _rock(tx - 1, ty) or _rock(tx, ty + 1) or _rock(tx, ty - 1)
			if _rock(tx, ty) or not edge or map.blocked[map.idx(tx, ty)] == 1:
				continue
			# never plug a one-tile passage
			if (_rock(tx + 1, ty) and _rock(tx - 1, ty)) or (_rock(tx, ty + 1) and _rock(tx, ty - 1)):
				continue
			var pr: Array = PROPS.pick_random()
			var node := Assets.piece(pr[0])
			node.scale = Vector3.ONE * pr[1]
			node.rotation.y = randf() * TAU
			node.position = Vector3(tx * Dungeon.T + 1.0, 0, ty * Dungeon.T + 1.0)
			root.add_child(node)
			map.blocked[map.idx(tx, ty)] = 1
			count -= 1


func _flush() -> void:
	var tint: Color = theme.tint
	for piece_name in batches:
		var info := Assets.piece_mesh(piece_name)
		var xfs: Array = batches[piece_name]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = info.mesh
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i] * info.xform)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if tint != Color.WHITE:
			var m := (info.mesh as Mesh).surface_get_material(0)
			if m is StandardMaterial3D:
				var tinted := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				tinted.albedo_color = tint
				mmi.material_override = tinted
		root.add_child(mmi)
