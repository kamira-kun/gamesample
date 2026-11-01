extends Node3D
## Game root: builds the dungeon, runs the combat loop and drives the camera.
## Logic works on the flat grid (Vector2 = ground x/z); nodes only mirror it.

const T := Dungeon.T
const CAM_PITCH := 0.96      # ~55 degrees above the ground
const CAM_YAW := PI / 4.0
const CAM_DIST := 36.0

var map: Dungeon
var floor_level := 1
var theme: Dictionary
var player: Player
var enemies: Array[Enemy] = []
var projs: Array = []        # player projectiles
var eprojs: Array = []       # enemy projectiles
var teles: Array = []        # telegraphed circles that resolve after a delay
var hazards: Array = []      # burning ground
var texts: Array = []        # floating damage numbers, drawn by the HUD
var ground: Array = []       # items lying on the floor
var drops: Array = []        # currency lying on the floor
var save_t := 0.0
var smoke := false
var portal: Dictionary = {}
var atlas := Atlas.new()
var area: Dictionary = Data.HIDEOUT   # current atlas node, or the hideout
var run_mods: Array = []
var mod_fx := Atlas.effects([])
var shop := {}
var interacts: Array = []   # hideout objects: {kind, name, pos, r}
var boss: Enemy = null
var flow_t := 0.0
var time := 0.0
var shake := 0.0
var level_root: Node3D
var cam: Camera3D
var cam_target := Vector3.ZERO
var hud: Hud
var mouse_ground := Vector2.ZERO
var lmb := false
var rmb := false
var pressed := {}
var oom_t := -10.0


func _ready() -> void:
	randomize()
	_setup_environment()
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.far = 300.0
	add_child(cam)
	player = Player.new()
	add_child(player)
	hud = Hud.new()
	hud.main = self
	add_child(hud)
	var args := Array(OS.get_cmdline_user_args())
	# dev runs: `--smoke` plays a scripted test, `--view=merchant|device` opens that panel; neither touches the save
	smoke = "--smoke" in args or args.any(func(x): return x.begins_with("--view="))
	var loaded := false if smoke else load_game()
	enter_hideout()
	if loaded:
		hud.message("セーブデータを読み込みました", Color("#e8d8b0"))
	else:
		hud.message("WASDで移動、左クリックで斬撃、右クリックでファイアボール", Color("#e8d8b0"))
	hud.message("I / Tab：インベントリ", Color("#b8a888"))
	for x in args:
		if x.begins_with("--view="):
			var kind: String = x.trim_prefix("--view=")
			if kind in ["merchant", "device"]:
				open_interact(kind)
	if "--smoke" in args:
		_smoke_test()


## automated run used during development: `godot -- --smoke`
func _smoke_test() -> void:
	var p := player
	p.invuln = 1e9
	# hideout: merchant and atlas
	print("SMOKE hideout=%s interacts=%d stock=%d" % [in_hideout(), interacts.size(), shop.items.size()])
	await get_tree().create_timer(0.5).timeout
	p.cur.ember = 2000
	open_interact("merchant")
	await get_tree().create_timer(0.3).timeout
	var pots := p.potions
	hud.shop_ui._buy(shop.items[0])
	hud.shop_ui._buy_potion()
	hud.shop_ui._buy_currency("chaos", Items.currency_price(Data.currency("chaos")))
	print("SMOKE bought bag=%d stock=%d potions+%d chaos=%d ember=%d" % [p.bag.size(), shop.items.size(), p.potions - pots, p.cur.chaos, p.cur.ember])
	hud.shop_ui._sell(0)
	print("SMOKE shop sold bag=%d" % p.bag.size())
	hud.close_panels()
	open_interact("device")
	await get_tree().create_timer(0.4).timeout
	enter_map("wail")
	print("SMOKE locked map ignored=%s" % in_hideout())
	enter_map("ash")
	print("SMOKE entered=%s level=%d atlas_open=%s" % [area.id, floor_level, hud.atlas_ui.visible])
	var e: Enemy = enemies.filter(func(q): return not q.boss)[0]
	p.pos = map.move_circle(e.pos + Vector2(-4, -4), p.r, Vector2.ZERO)
	await get_tree().create_timer(0.3).timeout
	mouse_ground = e.pos
	for id in Data.SKILL_ORDER:
		p.action_t = 0.0
		p.mana = p.s.max_mana
		_try_cast(id)
		await get_tree().create_timer(0.4).timeout
	await get_tree().create_timer(1.5).timeout
	var killed_before := enemies.size()
	hit_enemy(boss, {"dmg": 999999, "crit": false, "type": "phys"})
	print("SMOKE enemies=%d level=%d portal=%s" % [killed_before, p.level, not portal.is_empty()])
	p.pos = portal.pos
	await get_tree().create_timer(0.3).timeout
	print("SMOKE completed hideout=%s cleared=%s bone_unlocked=%s wail_unlocked=%s" % [in_hideout(), atlas.cleared, atlas.is_unlocked(Data.atlas_node("bone")), atlas.is_unlocked(Data.atlas_node("wail"))])
	atlas.mods["wail"] = ["life", "swarm"]
	enter_map("wail")
	print("SMOKE wail level=%d mods=%s enemies=%d rarity=%.2f" % [floor_level, run_mods, enemies.size(), mod_fx.rarity])
	p.invuln = 0.0
	damage_player(1e9)
	await get_tree().create_timer(1.2).timeout
	print("SMOKE dead=%s death_screen=%s" % [p.dead, hud.death.visible])
	retry_floor()
	hud.death.visible = false
	print("SMOKE retry dead=%s life=%d" % [p.dead, p.life])
	# loot, inventory, crafting and save round trip
	for i in 3:
		drop_item(Items.generate(3, 1.0, 1), p.pos)
	_drop_currency("chaos", 2, p.pos)
	_drop_currency("ember", 50, p.pos)
	await get_tree().create_timer(0.6).timeout
	for g in ground.duplicate():
		p.pos = g.pos
		await get_tree().create_timer(0.1).timeout
	print("SMOKE bag=%d chaos=%d ember=%d ground=%d" % [p.bag.size(), p.cur.chaos, p.cur.ember, ground.size()])
	hud.toggle_inventory()
	var mi := p.bag.find(p.bag.filter(func(x): return x.rarity == 1)[0])
	var before: Dictionary = p.bag[mi].mods.duplicate()
	hud.inventory._pick_currency("chaos")
	hud.inventory._on_bag_click(mi)
	print("SMOKE chaos rerolled=%s left=%d" % [before != p.bag[mi].mods or p.bag[mi].mods.size() != before.size(), p.cur.chaos])
	hud.inventory._cancel_craft()
	var slot: String = p.bag[0].slot
	hud.inventory._on_bag_click(0)
	print("SMOKE equipped=%s life=%d" % [p.equip.has(slot), p.s.max_life])
	var e0: int = p.cur.ember
	hud.inventory._on_bag_right(0)
	print("SMOKE sold ember+%d" % (p.cur.ember - e0))
	var it := Items.generate(5, 2.0, 2)
	var back := Items.normalize(JSON.parse_string(JSON.stringify(it)))
	print("SMOKE json roundtrip=%s" % (back == it))
	await get_tree().create_timer(0.5).timeout
	hud.toggle_inventory()
	get_tree().quit()


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.012, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.46, 0.52)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.6, 0.85)
	moon.light_energy = 0.18
	moon.rotation = Vector3(deg_to_rad(-65), deg_to_rad(25), 0)
	add_child(moon)


# =================== input ===================
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			lmb = e.pressed
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			rmb = e.pressed
	elif e is InputEventKey and e.pressed and not e.echo:
		pressed[e.physical_keycode] = true


func _update_mouse() -> void:
	var mp := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	if absf(dir.y) > 0.001:
		var hit := from + dir * (-from.y / dir.y)
		mouse_ground = Vector2(hit.x, hit.z)


static func to3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


# =================== level ===================
## clear the world and drop the player at the new map's start room
func _reset_world(new_map: Dungeon, new_theme: Dictionary) -> void:
	if level_root:
		level_root.queue_free()
	for list in [projs, eprojs, teles, hazards, texts, ground, drops, interacts]:
		list.clear()
	enemies.clear()
	portal = {}
	boss = null
	level_root = Node3D.new()
	add_child(level_root)
	map = new_map
	theme = new_theme
	LevelBuilder.build(map, theme, level_root)
	player.pos = map.tile_center(map.start.cx, map.start.cy)
	player.dead = false
	player.dash = {}
	player.recalc(true)
	player.torch.light_color = theme.torch
	cam_target = to3(player.pos)
	hud.set_boss(null)
	hud.close_panels()


func in_hideout() -> bool:
	return area.get("hideout", false)


func spawn_floor() -> void:
	_reset_world(Dungeon.new(72, 72, floor_level), Data.THEMES[atlas.node_theme(area)])
	_spawn_enemies()
	hud.message("%s — エリアレベル %d" % [area.name, floor_level], Color("#e8d8b0"))
	for k in run_mods:
		hud.message("◆ " + Data.map_mod(k).name, Color("#ff9a7a"))
	save_game()


# =================== hideout and atlas ===================
## a safe hall between runs: the only place with the merchant, and where maps are chosen
func enter_hideout() -> void:
	area = Data.HIDEOUT
	floor_level = atlas.hideout_level()
	run_mods = []
	mod_fx = Atlas.effects([])
	_reset_world(Dungeon.new(28, 26, 1, "hideout"), Data.HIDEOUT_THEME)
	var r := map.start
	var c := map.tile_center(r.cx, r.cy)
	player.pos = c + Vector2(0, 3 * T)
	cam_target = to3(player.pos)
	_dress_hideout(r)
	interacts.append({"kind": "device", "name": "遠征図の祭壇", "pos": c + Vector2(0, -2.5 * T), "r": 1.6})
	interacts.append({"kind": "merchant", "name": "商人", "pos": c + Vector2(-4 * T, 0), "r": 1.0})
	_build_device(interacts[0].pos)
	var merchant := Actor.new()
	merchant.pos = interacts[1].pos
	merchant.face = 0.0
	level_root.add_child(merchant)
	merchant.use_rig(Assets.ADVENTURERS + "Rogue_Hooded.glb", 1.0)
	merchant.sync_node(0.0, false)
	merchant.play("Idle")
	for o in interacts:
		var t := Vector2i(floori(o.pos.x / T), floori(o.pos.y / T))
		map.blocked[map.idx(t.x, t.y)] = 1
	if shop.is_empty() or shop.level != floor_level:
		shop = Items.gen_shop(floor_level)
	hud.message("隠れ家 — 遠征図の祭壇で行き先を選ぼう", Color("#e8d8b0"))
	save_game()


## furniture along the hideout walls (blocking their tiles) and braziers in the corners
func _dress_hideout(r: Dictionary) -> void:
	var decor := [["table_long_decorated_A", r.x + 3, r.y, 0.0], ["shelf_large", r.x + r.w - 4, r.y, 0.0],
		["chest_gold", r.x + r.w - 1, r.y + 6, -PI / 2], ["barrel_large_decorated", r.x + r.w - 1, r.y + r.h - 1, 0.0],
		["crates_stacked", r.x, r.y + r.h - 1, 0.5], ["keg_decorated", r.x, r.y + 2, PI / 2], ["table_small_decorated_A", r.x + 2, r.cy, 0.0]]
	for d in decor:
		var node := Assets.piece(d[0])
		node.position = to3(map.tile_center(d[1], d[2]))
		node.rotation.y = d[3]
		level_root.add_child(node)
		map.blocked[map.idx(d[1], d[2])] = 1
	for corner in [Vector2i(r.x + 1, r.y + 1), Vector2i(r.x + r.w - 2, r.y + 1), Vector2i(r.x + 1, r.y + r.h - 2), Vector2i(r.x + r.w - 2, r.y + r.h - 2)]:
		var at := map.tile_center(corner.x, corner.y)
		var torch := Assets.piece("torch_lit")
		torch.position = to3(at)
		torch.scale = Vector3.ONE * 1.6
		level_root.add_child(torch)
		var light := OmniLight3D.new()
		light.light_color = Color("#ffb070")
		light.light_energy = 1.8
		light.omni_range = 9.0
		light.position = to3(at, 2.2)
		level_root.add_child(light)
		map.blocked[map.idx(corner.x, corner.y)] = 1


## the atlas device: a stone plinth with a floating, slowly turning ring
func _build_device(at: Vector2) -> void:
	var root := Node3D.new()
	root.position = to3(at)
	level_root.add_child(root)
	var plinth := CylinderMesh.new()
	plinth.top_radius = 1.1
	plinth.bottom_radius = 1.4
	plinth.height = 0.6
	Fx.mesh(root, plinth, Fx.mat(Color("#4a4038")), Vector3(0, 0.3, 0))
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.75
	ring_mesh.outer_radius = 0.9
	var ring := Fx.mesh(root, ring_mesh, Fx.mat(Color("#ffc870"), 4.0, true), Vector3(0, 2.0, 0))
	ring.rotation.x = PI / 2
	var orb := Fx.mesh(root, Fx.sphere(0.3), Fx.mat(Color("#ffe0a0"), 6.0, true), Vector3(0, 2.0, 0))
	var light := OmniLight3D.new()
	light.light_color = Color("#ffc070")
	light.light_energy = 2.5
	light.omni_range = 8.0
	light.position.y = 2.0
	root.add_child(light)
	var tw := ring.create_tween().set_loops()
	tw.tween_property(ring, "rotation:y", TAU, 6.0).as_relative()
	var bob := orb.create_tween().set_loops()
	bob.tween_property(orb, "position:y", 2.3, 1.2).set_trans(Tween.TRANS_SINE)
	bob.tween_property(orb, "position:y", 1.9, 1.2).set_trans(Tween.TRANS_SINE)


## click (or press B) near the merchant or the atlas device; returns true when one opened
func _update_interact() -> bool:
	for o in interacts:
		var near: bool = player.pos.distance_to(o.pos) < 4.0 and pressed.has(KEY_B)
		var clicked: bool = lmb and mouse_ground.distance_to(o.pos) < o.r + 0.6 and player.pos.distance_to(o.pos) < 14.0
		if not near and not clicked:
			continue
		lmb = false
		open_interact(o.kind)
		return true
	return false


func open_interact(kind: String) -> void:
	if kind == "merchant":
		hud.shop_ui.open_close()
	else:
		hud.atlas_ui.open_close()


func enter_map(id: String) -> void:
	var n := Data.atlas_node(id)
	if n.is_empty() or not atlas.is_unlocked(n):
		return
	area = n
	floor_level = atlas.node_level(n)
	run_mods = atlas.node_mods(n).duplicate()
	mod_fx = Atlas.effects(run_mods)
	spawn_floor()


func complete_map() -> void:
	var n := area
	var was_cleared := atlas.is_cleared(n)
	if not was_cleared:
		atlas.cleared.append(n.id)
	var newly: Array = n.links.filter(func(id): return not atlas.is_cleared(Data.atlas_node(id))).map(func(id): return Data.atlas_node(id).name)
	if n.get("endless", false):
		atlas.abyss += 1
	atlas.mods.erase(n.id)
	shop = {}   # the merchant restocks after every run
	enter_hideout()
	hud.message("%s を踏破した！" % n.name, Color("#ffd36a"))
	if not newly.is_empty():
		hud.message("新たな地点が開放：%s" % "、".join(newly), Color("#e8d8b0"))
	if n.get("endless", false):
		hud.message("残り火の深淵が Lv %d に深まった" % atlas.node_level(n), Color("#b48cff"))


func abandon_map() -> void:
	enter_hideout()
	hud.message("隠れ家に帰還した", Color("#e8d8b0"))


func _spawn_enemies() -> void:
	var f := floor_level
	var pool := [{"k": "imp", "w": 3.0}, {"k": "ghoul", "w": 4.0}, {"k": "archer", "w": 2.0},
		{"k": "brute", "w": 1.5 if f >= 2 else 0.4}, {"k": "shaman", "w": 1.5 if f >= 2 else 0.5}]
	var pack_id := 0
	for room in map.rooms:
		if room == map.start:
			continue
		pack_id += 1
		if room == map.boss_room:
			boss = _make_enemy("boss", map.tile_center(room.cx, room.cy), pack_id)
			boss.max_life *= 1.0 + 0.12 * (f - 1)
			boss.life = boss.max_life
			for i in 4:
				_make_enemy("ghoul", map.random_floor_in(room), pack_id)
			continue
		var packs := clampi(roundi(room.w * room.h / 25.0 * mod_fx.swarm), 2, 7)
		for k in packs:
			pack_id += 1
			_spawn_pack(map.random_floor_in(room), pack_id, roundi((randi_range(4, 8) + f / 2) * mod_fx.swarm), pool)


static func _weighted(list: Array) -> Dictionary:
	var total := 0.0
	for e in list:
		total += e.w
	var roll := randf() * total
	for e in list:
		roll -= e.w
		if roll <= 0.0:
			return e
	return list[-1]


func _spawn_pack(c: Vector2, pack_id: int, n: int, pool: Array) -> void:
	var main_kind: String = _weighted(pool).k
	if randf() < (0.13 + floor_level * 0.01) * mod_fx.elite:
		_make_enemy(main_kind, c, pack_id, Data.ELITE_AFFIXES.pick_random())
	for i in n:
		var kind: String = main_kind if randf() < 0.7 else _weighted(pool).k
		var at := c + Vector2(randf_range(-2.5, 2.5), randf_range(-2.5, 2.5))
		if map.circle_hits(at, Data.ENEMY_TYPES[kind].r):
			at = c
		_make_enemy(kind, at, pack_id)


func _make_enemy(kind: String, at: Vector2, pack_id: int, affix: Dictionary = {}) -> Enemy:
	var e := Enemy.new()
	level_root.add_child(e)
	e.setup(kind, at, floor_level, pack_id, affix)
	e.max_life *= mod_fx.life
	e.life = e.max_life
	e.dmg *= mod_fx.dmg
	e.speed *= mod_fx.speed
	e.sync_node(0.0, false)
	enemies.append(e)
	return e


# =================== main loop ===================
func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_update_mouse()
	if (pressed.has(KEY_I) or pressed.has(KEY_TAB)) and not hud.atlas_ui.visible:
		if hud.shop_ui.visible:
			hud.shop_ui.open_close()
		hud.toggle_inventory()
	if pressed.has(KEY_ESCAPE):
		hud.close_panels()
	if not hud.blocking() and in_hideout():
		_update_interact()
	if not hud.blocking() and pressed.has(KEY_T) and not in_hideout() and not player.dead:
		abandon_map()
	if not hud.blocking():
		time += delta
		_update_player(delta)
		flow_t -= delta
		if flow_t <= 0.0:
			flow_t = 0.25
			map.compute_flow(player.pos)
		for e in enemies:
			var d2 := e.pos.distance_squared_to(player.pos)
			if not e.dead and d2 < 60.0 * 60.0:
				_update_enemy(e, delta)
			if not e.dead:
				e.animate(delta, e.aggro and e.windup <= 0.0 and e.frozen <= 0.0, d2 < 45.0 * 45.0)
		_separate_enemies()
		_remove_dead()
		_update_projectiles(delta)
		_update_eprojs(delta)
		_update_teles(delta)
		_update_hazards(delta)
		_update_loot(delta)
		_update_portal(delta)
		save_t += delta
		if save_t > 20.0 and not player.dead:
			save_t = 0.0
			save_game()
		for tx in texts:
			tx.t += delta
			tx.z += delta * 1.6
		texts = texts.filter(func(tx): return tx.t < 0.9)
	_update_camera(delta)
	hud.refresh()
	pressed.clear()
	lmb = lmb and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	rmb = rmb and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)


func _update_camera(delta: float) -> void:
	cam_target = cam_target.lerp(to3(player.pos), minf(1.0, delta * 8.0))
	var off := Vector3(cos(CAM_PITCH) * sin(CAM_YAW), sin(CAM_PITCH), cos(CAM_PITCH) * cos(CAM_YAW)) * CAM_DIST
	var jitter := Vector3(randf_range(-shake, shake), 0, randf_range(-shake, shake)) * 0.04
	cam.position = cam_target + off + jitter
	cam.look_at(cam_target + jitter, Vector3.UP)
	shake = maxf(0.0, shake - delta * 30.0)


func _remove_dead() -> void:
	for e in enemies:
		if e.dead:
			e.die()
	enemies = enemies.filter(func(e): return not e.dead)


# =================== player ===================
func _update_player(delta: float) -> void:
	var p := player
	if p.dead:
		p.animate(delta, false)
		return
	var s := p.s
	p.life = minf(s.max_life, p.life + s.life_regen * delta)
	p.mana = minf(s.max_mana, p.mana + s.mana_regen * delta)
	for k in p.cds.keys():
		p.cds[k] -= delta
	p.action_t -= delta
	p.swing_t -= delta
	p.invuln -= delta
	p.aim = (mouse_ground - p.pos).angle()
	if not p.dash.is_empty():
		_update_dash(delta)
		p.animate(delta, true)
		return

	var mv := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): mv.y -= 1
	if Input.is_physical_key_pressed(KEY_S): mv.y += 1
	if Input.is_physical_key_pressed(KEY_A): mv.x -= 1
	if Input.is_physical_key_pressed(KEY_D): mv.x += 1
	var moving := mv != Vector2.ZERO
	if moving:
		# keys move along the screen axes; turn that into a ground direction via the camera
		var fwd := -cam.global_transform.basis.z
		var right := cam.global_transform.basis.x
		fwd.y = 0
		right.y = 0
		var d3 := (right.normalized() * mv.x - fwd.normalized() * mv.y).normalized()
		var sp: float = s.move_speed * (0.5 if p.action_t > 0.0 else 1.0)
		p.pos = map.move_circle(p.pos, p.r, Vector2(d3.x, d3.z) * sp * delta)
	if lmb: _try_cast("slash")
	if rmb: _try_cast("fireball")
	if Input.is_physical_key_pressed(KEY_Q): _try_cast("nova")
	if Input.is_physical_key_pressed(KEY_E): _try_cast("chain")
	if Input.is_physical_key_pressed(KEY_R): _try_cast("meteor")
	if pressed.has(KEY_SPACE): _try_cast("dash")
	if pressed.has(KEY_F): _use_potion()
	p.animate(delta, moving)


func _use_potion() -> void:
	var p := player
	if p.potions <= 0:
		hud.message("回復薬がない", Color("#ff8080"))
		return
	if p.life >= p.s.max_life:
		return
	p.potions -= 1
	var heal: float = p.s.max_life * 0.5
	p.life = minf(p.s.max_life, p.life + heal)
	Fx.burst(level_root, to3(p.pos, 1.0), 20, Color("#ff5a5a"), 4.0)
	add_text(p.pos, "+%d" % heal, Color("#66ff66"), 20)


func damage_player(amount: float) -> void:
	var p := player
	if p.dead or p.invuln > 0.0:
		return
	var d := maxi(1, roundi(amount * (1.0 - p.s.dr)))
	p.life -= d
	p.hit_t = 0.15
	add_text(p.pos, str(d), Color("#ff5050"), 18)
	shake = maxf(shake, 4.0)
	hud.flash()
	if p.effects.has("nova_on_hit") and randf() < 0.2:
		_cast_nova(true)
	if p.life <= 0.0:
		p.life = 0.0
		p.dead = true
		Fx.burst(level_root, to3(p.pos, 1.0), 40, Color("#a01010"), 5.0)
		get_tree().create_timer(0.9).timeout.connect(hud.show_death)


func retry_floor() -> void:
	player.xp = int(player.xp * 0.7)
	if in_hideout():
		enter_hideout()
	else:
		spawn_floor()


func gain_xp(v: int) -> void:
	var p := player
	p.xp += v
	while p.xp >= Data.xp_need(p.level):
		p.xp -= Data.xp_need(p.level)
		p.level += 1
		p.recalc(true)
		add_text(p.pos, "LEVEL UP!", Color("#ffe27a"), 28)
		Fx.ring(level_root, to3(p.pos), 5.0, Color("#ffe27a"), 0.6, false)
		Fx.burst(level_root, to3(p.pos, 1.0), 40, Color("#ffe27a"), 6.0)
		hud.message("レベル %d に到達！" % p.level, Color("#ffe27a"))


# =================== combat ===================
func roll_damage(coef: float, type: String, spell := false) -> Dictionary:
	var s := player.s
	var d: float = randf_range(s.dmg_min, s.dmg_max) * coef
	var elem: float = {"fire": s.fire_dmg, "cold": s.cold_dmg, "light": s.light_dmg}.get(type, 0)
	d *= 1.0 + (s.inc_dmg + (s.spell_dmg if spell else 0) + elem) / 100.0
	var crit: bool = randf() * 100.0 < s.crit
	if crit:
		d *= s.crit_multi / 100.0
	return {"dmg": maxi(1, roundi(d)), "crit": crit, "type": type}


func hit_enemy(e: Enemy, hit: Dictionary, freeze := 0.0) -> void:
	if e.dead:
		return
	e.life -= hit.dmg
	e.hit_t = 0.12
	if not e.aggro:
		_alert_pack(e)
	add_text(e.pos, str(hit.dmg) + ("!" if hit.crit else ""), Color("#ffe040") if hit.crit else Data.DMG_COLORS[hit.type], 26 if hit.crit else 18)
	if freeze > 0.0:
		if e.boss:
			e.slow = maxf(e.slow, freeze)
		else:
			e.frozen = maxf(e.frozen, freeze)
	if e.life <= 0.0:
		_kill_enemy(e)


func enemies_in_radius(c: Vector2, rad: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in enemies:
		if not e.dead and e.pos.distance_to(c) < rad + e.r:
			out.append(e)
	return out


func _kill_enemy(e: Enemy) -> void:
	e.dead = true
	var p := player
	gain_xp(roundi(e.xp))
	p.life = minf(p.s.max_life, p.life + p.s.life_on_kill + (p.s.max_life * 0.03 if p.effects.has("kill_heal") else 0.0))
	_drop_loot(e)
	p.potion_prog += 1
	if p.potion_prog >= 14:
		p.potion_prog = 0
		if p.potions < Player.MAX_POTIONS:
			p.potions += 1
			add_text(p.pos, "回復薬 +1", Color("#ff7070"), 16)
	Fx.burst(level_root, to3(e.pos, 0.8), 60 if e.boss else 12, e.t.color, 8.0 if e.boss else 5.0)
	if e.elite.get("k", "") == "volatile":
		var at := e.pos
		var dmg := e.dmg * 1.5
		add_tele(at, 3.2, 0.8, true, func():
			_explosion(at, 3.2, Color("#ff7840"))
			if player.pos.distance_to(at) < 3.2 + player.r:
				damage_player(dmg))
	if e.boss:
		boss = null
		hud.set_boss(null)
		_open_portal(e.pos)
		hud.message("%sを討伐した！ ポータルで隠れ家に帰還できる" % e.display_name, Color("#ff9a4a"))


func _explosion(at: Vector2, rad: float, color: Color) -> void:
	Fx.ring(level_root, to3(at), rad, color, 0.35)
	Fx.burst(level_root, to3(at, 0.5), int(rad * 8), color, rad * 3.0)
	shake = maxf(shake, rad * 2.5)


func add_text(at: Vector2, text: String, color: Color, size := 18) -> void:
	texts.append({"pos": to3(at + Vector2(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4)), 1.8), "str": text, "color": color, "size": size, "t": 0.0, "z": 0.0})


func add_tele(at: Vector2, rad: float, dur: float, hostile: bool, on_done: Callable) -> void:
	var c := Color(1.0, 0.2, 0.15) if hostile else Color(1.0, 0.6, 0.15)
	var root := Node3D.new()
	root.position = to3(at, 0.04)
	level_root.add_child(root)
	var outer := Fx.mesh(root, Fx.disc(), Fx.mat(Color(c, 0.18), 1.0, true))
	outer.scale = Vector3(rad, 1, rad)
	Fx.mesh(root, Fx.arc_mesh(rad - 0.08, rad, 0, TAU, 48), Fx.mat(Color(c, 0.85), 2.0, true), Vector3(0, 0.01, 0))
	var inner := Fx.mesh(root, Fx.disc(), Fx.mat(Color(c, 0.3), 1.5, true), Vector3(0, 0.02, 0))
	inner.scale = Vector3(0.01, 1, 0.01)
	teles.append({"node": root, "inner": inner, "r": rad, "t": 0.0, "max": dur, "done": on_done})


func _update_teles(delta: float) -> void:
	for tl in teles:
		tl.t += delta
		var k := minf(1.0, tl.t / tl.max)
		tl.inner.scale = Vector3(tl.r * k + 0.01, 1, tl.r * k + 0.01)
		if tl.t >= tl.max:
			tl.node.queue_free()
			tl.done.call()
	teles = teles.filter(func(tl): return tl.t < tl.max)


# =================== skills ===================
func _try_cast(id: String) -> void:
	var p := player
	var sk: Dictionary = Data.SKILLS[id]
	if p.action_t > 0.0 and id != "dash":
		return
	if p.cds.get(id, 0.0) > 0.0:
		return
	if p.mana < sk.mana:
		if time - oom_t > 1.2:
			oom_t = time
			hud.message("マナが足りない", Color("#7fa8ff"))
		return
	if id == "chain" and _chain_target(p.pos) == null:
		return
	p.mana -= sk.mana
	if sk.cd > 0.0:
		p.cds[id] = sk.cd * (1.0 - p.s.cdr / 100.0)
	if sk.get("attack", false):
		p.action_t = 1.0 / p.s.attack_rate
	elif sk.has("cast"):
		p.action_t = sk.cast / (1.0 + p.s.cast_spd / 100.0)
	call("_cast_" + id)


func _cast_slash() -> void:
	var p := player
	var reach := 3.2
	p.swing_t = 0.2
	p.act("1H_Melee_Attack_Slice_Horizontal", 2.2, p.action_t)
	for e in enemies:
		if e.dead:
			continue
		var d := e.pos.distance_to(p.pos)
		if d > reach + e.r:
			continue
		if absf(angle_difference(p.aim, (e.pos - p.pos).angle())) > 1.15 and d > e.r + p.r:
			continue
		hit_enemy(e, roll_damage(1.0, "phys"))
	var arc := MeshInstance3D.new()
	arc.mesh = Fx.arc_mesh(1.0, reach, p.aim - 1.1, p.aim + 1.1)
	var m := Fx.mat(Color(1.0, 0.94, 0.82, 0.7), 2.0, true)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	arc.material_override = m
	arc.position = to3(p.pos, 0.9)
	level_root.add_child(arc)
	Fx.fade_out(arc, m, 0.18)
	if p.effects.has("slash_wave"):
		var wave := MeshInstance3D.new()
		wave.mesh = Fx.arc_mesh(0.6, 1.4, -0.9, 0.9)
		var wm := Fx.mat(Color(1.0, 0.9, 0.7, 0.8), 3.0, true)
		wm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		wm.cull_mode = BaseMaterial3D.CULL_DISABLED
		wave.material_override = wm
		wave.rotation.y = -p.aim
		level_root.add_child(wave)
		projs.append({"node": wave, "kind": "wave", "pos": p.pos, "vel": Vector2.from_angle(p.aim) * 26.0, "r": 1.0, "t": 0.0, "max": 0.55, "hit": {}})


func _cast_fireball() -> void:
	var p := player
	p.act("Spellcast_Shoot", 2.0, p.action_t)
	for da in ([-0.22, 0.0, 0.22] if p.effects.has("fireball_multi") else [0.0]):
		var dir := Vector2.from_angle(p.aim + da)
		var root := Node3D.new()
		root.position = to3(p.pos + dir * 0.6, 1.0)
		level_root.add_child(root)
		Fx.mesh(root, Fx.sphere(0.28), Fx.mat(Color("#ffa040"), 6.0, true))
		var light := OmniLight3D.new()
		light.light_color = Color("#ff8a30")
		light.light_energy = 2.0
		light.omni_range = 6.0
		root.add_child(light)
		projs.append({"node": root, "kind": "fireball", "pos": p.pos + dir * 0.6, "vel": dir * 24.0, "r": 0.3, "t": 0.0, "max": 1.4})


func _cast_nova(free := false) -> void:
	var p := player
	if not free:
		p.act("Spellcast_Raise", 2.2, 0.35)
	var rad := 8.0
	Fx.ring(level_root, to3(p.pos), rad, Color("#8cdcff"), 0.4)
	Fx.burst(level_root, to3(p.pos, 0.6), 50, Color("#aee8ff"), 14.0, 0.5, 0.0)
	for e in enemies_in_radius(p.pos, rad):
		hit_enemy(e, roll_damage(0.8 if free else 1.3, "cold", true), 1.8)


func _chain_target(from: Vector2) -> Variant:
	var best: Enemy = null
	var bd := INF
	for e in enemies:
		if e.dead or e.pos.distance_to(from) > 18.0:
			continue
		var d := e.pos.distance_squared_to(mouse_ground)
		if d < bd and map.los(from, e.pos):
			bd = d
			best = e
	return best


func _cast_chain() -> void:
	player.act("Spellcast_Shoot", 2.0, player.action_t)
	var target: Variant = _chain_target(player.pos)
	var hit := {}
	var src := to3(player.pos, 1.2)
	var n := 5 + (4 if player.effects.has("chain_plus") else 0)
	while target != null and n > 0:
		n -= 1
		var e: Enemy = target
		hit[e] = true
		var dst := to3(e.pos, 1.0)
		Fx.bolt(level_root, src, dst)
		Fx.burst(level_root, dst, 6, Color("#d9c2ff"), 4.0)
		hit_enemy(e, roll_damage(1.15, "light", true))
		src = dst
		target = null
		var bd := 9.0 * 9.0
		for o in enemies:
			if o.dead or hit.has(o):
				continue
			var d := o.pos.distance_squared_to(e.pos)
			if d < bd and map.los(e.pos, o.pos):
				bd = d
				target = o


func _cast_meteor() -> void:
	var p := player
	p.act("Spellcast_Long", 2.0, 0.5)
	var to := mouse_ground - p.pos
	var at := p.pos + to.limit_length(20.0)
	_drop_meteor(at, 0.75)
	if p.effects.has("meteor_shower"):
		_drop_meteor(at + Vector2(randf_range(-5, 5), randf_range(-5, 5)), 1.0)
		_drop_meteor(at + Vector2(randf_range(-5, 5), randf_range(-5, 5)), 1.25)


func _drop_meteor(at: Vector2, delay: float) -> void:
	var rad := 4.6
	add_tele(at, rad, delay, false, func():
		_explosion(at, rad, Color("#ff6e28"))
		for e in enemies_in_radius(at, rad):
			hit_enemy(e, roll_damage(3.6, "fire", true))
		_add_hazard(at, rad * 0.83, 3.5))


func _cast_dash() -> void:
	var p := player
	var to := mouse_ground - p.pos
	p.dash = {"dir": to.normalized() if to.length() > 0.01 else Vector2.from_angle(p.aim), "left": clampf(to.length(), 5.0, 11.0), "hit": {}}
	p.invuln = 0.3


func _update_dash(delta: float) -> void:
	var p := player
	var d := p.dash
	var step := minf(d.left, 60.0 * delta)
	d.left -= step
	while step > 0.0:
		var sub := minf(0.3, step)
		step -= sub
		var before := p.pos
		p.pos = map.move_circle(p.pos, p.r, d.dir * sub)
		if before.distance_to(p.pos) < 0.01:
			d.left = 0.0
			break
	for e in enemies:
		if e.dead or d.hit.has(e) or e.pos.distance_to(p.pos) > e.r + p.r + 0.6:
			continue
		d.hit[e] = true
		hit_enemy(e, roll_damage(0.9, "phys"))
	Fx.burst(level_root, to3(p.pos, 0.8), 3, Color("#8c78ff"), 1.0, 0.3, 0.0)
	if d.left <= 0.0:
		p.dash = {}
		if p.effects.has("dash_nova"):
			_cast_nova(true)


func _add_hazard(at: Vector2, rad: float, dur: float) -> void:
	var root := Node3D.new()
	root.position = to3(at, 0.05)
	level_root.add_child(root)
	var disc := Fx.mesh(root, Fx.disc(), Fx.mat(Color(1.0, 0.35, 0.08, 0.45), 2.5, true))
	disc.scale = Vector3(rad, 1, rad)
	var fire := CPUParticles3D.new()
	fire.amount = 40
	fire.lifetime = 0.7
	fire.mesh = Fx.sphere(0.08)
	fire.material_override = Fx.mat(Color("#ff8a30"), 5.0, true)
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = rad * 0.8
	fire.scale = Vector3(1, 0.05, 1)
	fire.direction = Vector3.UP
	fire.gravity = Vector3(0, 40, 0)
	fire.initial_velocity_min = 0.5
	fire.initial_velocity_max = 1.5
	root.add_child(fire)
	var light := OmniLight3D.new()
	light.light_color = Color("#ff7a30")
	light.light_energy = 2.0
	light.omni_range = rad * 2.0
	light.position.y = 1.0
	root.add_child(light)
	hazards.append({"node": root, "pos": at, "r": rad, "t": 0.0, "max": dur, "tick": 0.0})


func _update_hazards(delta: float) -> void:
	for hz in hazards:
		hz.t += delta
		hz.tick -= delta
		if hz.tick <= 0.0:
			hz.tick = 0.5
			for e in enemies_in_radius(hz.pos, hz.r):
				hit_enemy(e, roll_damage(0.35, "fire", true))
		if hz.t >= hz.max:
			hz.node.queue_free()
	hazards = hazards.filter(func(hz): return hz.t < hz.max)


func _update_projectiles(delta: float) -> void:
	for pr in projs:
		pr.t += delta
		pr.pos += pr.vel * delta
		pr.node.position = to3(pr.pos, 1.0)
		if pr.kind == "wave":
			for e in enemies:
				if not e.dead and not pr.hit.has(e) and e.pos.distance_to(pr.pos) < e.r + pr.r:
					pr.hit[e] = true
					hit_enemy(e, roll_damage(0.7, "phys"))
			if pr.t > pr.max or map.solid_at(pr.pos):
				pr.t = pr.max + 1.0
				pr.node.queue_free()
			continue
		var boom: bool = pr.t > pr.max or map.solid_at(pr.pos)
		if not boom:
			for e in enemies:
				if not e.dead and e.pos.distance_to(pr.pos) < e.r + pr.r:
					boom = true
					break
		if boom:
			pr.t = pr.max + 1.0
			pr.node.queue_free()
			_explosion(pr.pos, 2.8, Color("#ff8c32"))
			for e in enemies_in_radius(pr.pos, 2.8):
				hit_enemy(e, roll_damage(1.5, "fire", true))
	projs = projs.filter(func(pr): return pr.t <= pr.max)


# =================== enemies ===================
func _alert_pack(e: Enemy) -> void:
	e.aggro = true
	for o in enemies:
		if o.pack == e.pack and not o.aggro and o.pos.distance_to(e.pos) < 20.0:
			o.aggro = true


func _update_enemy(e: Enemy, delta: float) -> void:
	var p := player
	e.atk_cd -= delta
	e.slow -= delta
	if e.frozen > 0.0:
		e.frozen -= delta
		return
	var d := e.pos.distance_to(p.pos)
	e.los_t -= delta
	if e.los_t <= 0.0:
		e.los_t = 0.2 + randf() * 0.1
		e.sees = d < 30.0 and map.los(e.pos, p.pos)
	if not e.aggro:
		if (d < 15.0 or (e.boss and d < 20.0)) and e.sees:
			_alert_pack(e)
		else:
			e.wander_t -= delta
			if e.wander_t < 0.0:
				e.wander_t = randf_range(1.5, 4.0)
				e.face = randf() * TAU
				e.wandering = randf_range(0.3, 0.9)
			if e.wandering > 0.0:
				e.wandering -= delta
				e.pos = map.move_circle(e.pos, e.r, Vector2.from_angle(e.face) * e.speed * 0.3 * delta)
			return
	if p.dead:
		return
	if e.windup > 0.0:
		e.windup -= delta
		if e.windup <= 0.0 and e.pending.is_valid():
			var fn := e.pending
			e.pending = Callable()
			fn.call()
		return
	if e.boss:
		_update_boss(e, delta, d)
		return
	var t := e.t
	var move := true
	if t.get("ranged", false) or t.get("caster", false):
		if d < t.range and e.sees:
			move = false
			if t.get("ranged", false) and d < 5.0:
				e.pos = map.move_circle(e.pos, e.r, (e.pos - p.pos).normalized() * e.speed * 0.7 * delta)
			if e.atk_cd <= 0.0:
				_start_attack(e)
	elif d < t.atk_range + e.r + p.r:
		move = false
		if e.atk_cd <= 0.0:
			_start_attack(e)
	if move:
		_chase(e, delta)
	e.face = (p.pos - e.pos).angle()


func _chase(e: Enemy, delta: float) -> void:
	var target := player.pos
	if not e.sees:
		target = map.flow_next(e.pos)
		if target.x == INF:
			return
	var dir := (target - e.pos).normalized()
	e.pos = map.move_circle(e.pos, e.r, dir * e.speed * (0.5 if e.slow > 0.0 else 1.0) * delta)


func _start_attack(e: Enemy) -> void:
	var t := e.t
	var p := player
	e.atk_cd = t.atk_cd * e.atk_cd_mul
	e.windup = t.windup
	if t.get("ranged", false):
		e.pending = func():
			if not e.dead:
				_enemy_shot(e.pos, (p.pos - e.pos).angle(), 16.0, e.dmg, Color("#e8e0b0"))
	elif t.get("caster", false):
		var at := p.pos
		var dmg := e.dmg
		add_tele(at, 2.6, t.windup + 0.15, true, func():
			_explosion(at, 2.6, Color("#5adcf0"))
			if p.pos.distance_to(at) < 2.6 + p.r:
				damage_player(dmg))
		e.pending = func(): pass
	elif t.has("aoe"):
		var rad: float = t.aoe
		add_tele(e.pos, rad, t.windup, true, func():
			if e.dead or e.frozen > 0.0:
				return
			_explosion(e.pos, rad, Color("#c88cff"))
			if p.pos.distance_to(e.pos) < rad + p.r:
				damage_player(e.dmg))
		e.pending = func(): pass
	else:
		e.pending = func():
			if not e.dead and p.pos.distance_to(e.pos) < t.atk_range + e.r + p.r + 0.5:
				damage_player(e.dmg)


func _enemy_shot(from: Vector2, angle: float, speed: float, dmg: float, color: Color) -> void:
	var node := Fx.mesh(level_root, Fx.sphere(0.2), Fx.mat(color, 5.0, true), to3(from, 1.0))
	eprojs.append({"node": node, "pos": from, "vel": Vector2.from_angle(angle) * speed, "r": 0.25, "dmg": dmg, "t": 0.0, "max": 3.0})


func _update_eprojs(delta: float) -> void:
	var p := player
	for pr in eprojs:
		pr.t += delta
		pr.pos += pr.vel * delta
		pr.node.position = to3(pr.pos, 1.0)
		var gone: bool = pr.t > pr.max or map.solid_at(pr.pos)
		if not gone and not p.dead and p.invuln <= 0.0 and pr.pos.distance_to(p.pos) < pr.r + p.r:
			gone = true
			damage_player(pr.dmg)
		if gone:
			pr.t = pr.max + 1.0
			pr.node.queue_free()
	eprojs = eprojs.filter(func(pr): return pr.t <= pr.max)


func _update_boss(e: Enemy, delta: float, d: float) -> void:
	var p := player
	if hud.boss != e:
		hud.set_boss(e)
		hud.message("%s が目覚めた！" % e.display_name, Color("#ff6040"))
	var enraged := e.life < e.max_life * 0.5
	e.act_t -= delta
	if e.act_t <= 0.0:
		e.act_t = 2.2 if enraged else 3.0
		var roll := randf()
		if d < 9.0 and roll < 0.45:
			e.windup = 1.0
			e.pending = func(): pass
			add_tele(e.pos, 7.0, 1.0, true, func():
				if e.dead:
					return
				_explosion(e.pos, 7.0, Color("#ff4632"))
				if p.pos.distance_to(e.pos) < 7.0 + p.r:
					damage_player(e.dmg * 1.7))
		elif roll < 0.8:
			e.windup = 0.7
			e.pending = func():
				var n := 26 if enraged else 18
				var off := randf() * TAU
				for i in n:
					_enemy_shot(e.pos, off + float(i) / n * TAU, 10.0, e.dmg * 0.8, Color("#ff5040"))
			Fx.burst(level_root, to3(e.pos, 1.5), 20, Color("#ff4030"), 6.0)
		else:
			e.windup = 0.6
			e.pending = func():
				for i in (6 if enraged else 4):
					var at := e.pos + Vector2.from_angle(randf() * TAU) * 2.8
					if not map.circle_hits(at, 0.45):
						var m := _make_enemy("imp", at, e.pack)
						m.aggro = true
						Fx.burst(level_root, to3(at, 0.5), 10, Color("#c4523a"), 4.0)
		return
	if d > e.r + p.r + 1.2:
		_chase(e, delta)
	elif e.atk_cd <= 0.0:
		e.atk_cd = 1.6
		e.windup = 0.4
		e.pending = func():
			if p.pos.distance_to(e.pos) < e.r + p.r + 1.6:
				damage_player(e.dmg)
	e.face = (p.pos - e.pos).angle()


func _separate_enemies() -> void:
	var p := player
	var n := enemies.size()
	for i in n:
		var a := enemies[i]
		if a.dead or not a.aggro:
			continue
		for j in range(i + 1, n):
			var b := enemies[j]
			if b.dead:
				continue
			var diff := b.pos - a.pos
			var rr := a.r + b.r
			var d2 := diff.length_squared()
			if d2 >= rr * rr or d2 == 0.0:
				continue
			var dd := sqrt(d2)
			var push := diff / dd * (rr - dd) / 2.0
			a.pos = map.move_circle(a.pos, a.r, -push)
			b.pos = map.move_circle(b.pos, b.r, push)
		var dp := a.pos - p.pos
		var pr := a.r + p.r
		if dp.length_squared() < pr * pr and dp.length_squared() > 0.0:
			var dl := dp.length()
			a.pos = map.move_circle(a.pos, a.r, dp / dl * (pr - dl))


# =================== portal ===================
func _open_portal(at: Vector2) -> void:
	var root := Node3D.new()
	root.position = to3(at)
	level_root.add_child(root)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.9
	ring_mesh.outer_radius = 1.1
	var ring := Fx.mesh(root, ring_mesh, Fx.mat(Color("#9a70ff"), 5.0, true), Vector3(0, 1.4, 0))
	ring.rotation.x = PI / 2
	ring.rotation.y = CAM_YAW
	var light := OmniLight3D.new()
	light.light_color = Color("#a080ff")
	light.light_energy = 3.0
	light.omni_range = 8.0
	light.position.y = 1.5
	root.add_child(light)
	portal = {"node": root, "pos": at, "ring": ring}


func _update_portal(delta: float) -> void:
	if portal.is_empty():
		return
	portal.ring.rotate_object_local(Vector3.UP, delta * 2.0)
	if not player.dead and player.pos.distance_to(portal.pos) < 1.3:
		complete_map()


# =================== loot ===================
func _drop_loot(e: Enemy) -> void:
	var ilvl := floor_level + (1 if not e.elite.is_empty() else 0) + (2 if e.boss else 0)
	var n := 0
	var boost: float = mod_fx.rarity
	if e.boss:
		n = 4
		boost += 2.5
	elif not e.elite.is_empty():
		n = randi_range(1, 2)
		boost += 1.2
	elif randf() < 0.13 * mod_fx.quantity:
		n = 1
	for i in n:
		var force := (3 if randf() < 0.35 else 2) if e.boss and i == 0 else -1
		drop_item(Items.generate(ilvl, boost, force), e.pos)
	if randf() < (1.0 if e.boss or not e.elite.is_empty() else 0.25):
		for i in (6 if e.boss else 3 if not e.elite.is_empty() else 1):
			_drop_currency("ember", roundi(randf_range(2, 6) * floor_level * (2 if not e.elite.is_empty() else 1)), e.pos)
	var cn := randi_range(3, 5) if e.boss else (randi_range(1, 2) if not e.elite.is_empty() and randf() < 0.5 else (1 if randf() < 0.035 else 0))
	for i in cn:
		_drop_currency(_weighted(Data.CURRENCIES.filter(func(c): return c.w > 0.0)).k, 1, e.pos)


func _scatter(at: Vector2) -> Vector2:
	var p := at + Vector2.from_angle(randf() * TAU) * randf_range(0.4, 1.8)
	return at if map.solid_at(p) else p


func drop_item(it: Dictionary, at: Vector2) -> void:
	var pos := _scatter(at)
	var col: Color = Data.RARITY[it.rarity].color
	var root := Node3D.new()
	root.position = to3(pos)
	level_root.add_child(root)
	var gem := Fx.mesh(root, Fx.box(Vector3(0.35, 0.35, 0.35)), Fx.mat(col, 1.5), Vector3(0, 0.3, 0))
	gem.rotation = Vector3(0.6, 0.4, 0.6)
	if it.rarity >= 2:
		var beam := CylinderMesh.new()
		beam.top_radius = 0.05
		beam.bottom_radius = 0.12
		beam.height = 4.0
		var bm := Fx.mat(Color(col, 0.35), 3.0, true)
		bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		Fx.mesh(root, beam, bm, Vector3(0, 2.0, 0))
		var light := OmniLight3D.new()
		light.light_color = col
		light.light_energy = 1.0
		light.omni_range = 3.0
		light.position.y = 0.6
		root.add_child(light)
	ground.append({"item": it, "pos": pos, "node": root, "gem": gem})


func _drop_currency(k: String, n: int, at: Vector2) -> void:
	if n <= 0:
		return
	var c := Data.currency(k)
	var pos := _scatter(at)
	var shard := SphereMesh.new()
	shard.radius = 0.14 if k == "ember" else 0.2
	shard.height = shard.radius * 2.6
	shard.radial_segments = 4
	shard.rings = 1
	var node := Fx.mesh(level_root, shard, Fx.mat(c.color, 3.0), to3(pos, 0.3))
	drops.append({"k": k, "n": n, "pos": pos, "node": node})


func _update_loot(delta: float) -> void:
	var p := player
	if p.dead:
		return
	for g in ground:
		g.gem.rotate_y(delta * 1.5)
		if g.pos.distance_to(p.pos) > 1.3:
			continue
		if p.bag.size() >= Player.BAG_SIZE:
			if time - g.get("full_t", -9.0) > 2.0:
				g.full_t = time
				hud.message("インベントリが一杯です（I）", Color("#ff8080"))
			continue
		p.bag.append(g.item)
		g.taken = true
		g.node.queue_free()
		hud.message("%s を拾った" % g.item.name, Data.RARITY[g.item.rarity].color)
		hud.refresh_inventory()
	ground = ground.filter(func(g): return not g.get("taken", false))
	for d in drops:
		d.node.rotate_y(delta * 3.0)
		var dist: float = d.pos.distance_to(p.pos)
		if dist < 4.5:
			d.pos = d.pos.move_toward(p.pos, delta * 14.0)
			d.node.position = to3(d.pos, 0.3)
		if dist < 0.8:
			d.taken = true
			d.node.queue_free()
			p.cur[d.k] += d.n
			if d.k != "ember":
				var c := Data.currency(d.k)
				hud.message("%s を拾った" % c.name, c.color)
	drops = drops.filter(func(d): return not d.get("taken", false))


# =================== save ===================
const SAVE_PATH := "user://emberfall_save.json"


func save_game() -> void:
	if smoke:
		return
	var p := player
	var data := {"floor": floor_level, "level": p.level, "xp": p.xp, "potions": p.potions,
		"equip": p.equip, "bag": p.bag, "cur": p.cur, "atlas": atlas.to_dict(), "shop": shop}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var p := player
	floor_level = int(data.get("floor", 1))
	p.level = int(data.get("level", 1))
	p.xp = int(data.get("xp", 0))
	p.potions = int(data.get("potions", 3))
	p.equip = {}
	for slot in data.get("equip", {}):
		p.equip[slot] = Items.normalize(data.equip[slot])
	p.bag = data.get("bag", []).map(func(it): return Items.normalize(it))
	for k in data.get("cur", {}):
		p.cur[k] = int(data.cur[k])
	atlas.from_dict(data.get("atlas", {}))
	var sd: Dictionary = data.get("shop", {})
	if sd.has("items"):
		shop = {"level": int(sd.level), "items": sd.items.map(func(it): return Items.normalize(it))}
	p.recalc(true)
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
