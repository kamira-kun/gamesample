class_name Enemy
extends Actor

var type := ""
var t: Dictionary
var life := 10.0
var max_life := 10.0
var dmg := 1.0
var speed := 3.0
var xp := 1.0
var atk_cd := 0.0
var atk_cd_mul := 1.0
var windup := 0.0
var pending: Callable
var frozen := 0.0
var slow := 0.0
var aggro := false
var sees := false
var los_t := 0.0
var wander_t := 0.0
var wandering := 0.0
var act_t := 2.0
var elite: Dictionary = {}
var boss := false
var pack := 0
var dead := false
var display_name := ""


func setup(kind: String, at: Vector2, level: int, pack_id: int, affix: Dictionary = {}) -> void:
	type = kind
	t = Data.ENEMY_TYPES[kind]
	pos = at
	pack = pack_id
	var f := level - 1
	r = t.r
	max_life = t.life * (1.0 + 0.5 * f + 0.05 * f * f)
	dmg = t.dmg * (1.0 + 0.3 * f)
	speed = t.speed * randf_range(0.9, 1.1)
	xp = t.xp * (1.0 + 0.25 * f)
	boss = t.get("boss", false)
	display_name = t.name
	atk_cd = randf_range(0.2, 1.0)
	los_t = randf() * 0.2
	face = randf() * TAU
	if not affix.is_empty():
		elite = affix
		display_name = "%sの%s" % [affix.name, t.name]
		max_life *= 3.0
		r *= 1.25
		xp *= 4.0
		dmg *= 1.25
		match affix.k:
			"swift":
				speed *= 1.5
				atk_cd_mul = 0.65
			"armored":
				max_life *= 1.8
			"frenzied":
				dmg *= 1.5
	life = max_life
	_build()
	if not elite.is_empty():
		model.scale = Vector3.ONE * 1.25


func _build() -> void:
	var c: Color = t.color
	var h: float = t.h
	var eye := Color("#ffda4a")
	match type:
		"imp":
			part(Fx.capsule(0.3, 0.8), c, Vector3(0, 0.45, 0))
			part(Fx.cone(0.08, 0.3), Color("#2a1410"), Vector3(-0.15, 0.95, 0))
			part(Fx.cone(0.08, 0.3), Color("#2a1410"), Vector3(0.15, 0.95, 0))
		"ghoul":
			var body := part(Fx.capsule(0.38, 1.2), c, Vector3(0, 0.65, -0.1))
			body.rotation.x = -0.35
			part(Fx.sphere(0.26), c.darkened(0.2), Vector3(0, 1.2, -0.38))
		"archer":
			part(Fx.capsule(0.26, 1.3), c, Vector3(0, 0.7, 0))
			part(Fx.sphere(0.22), c, Vector3(0, 1.5, 0))
			var bow := TorusMesh.new()
			bow.inner_radius = 0.42
			bow.outer_radius = 0.47
			var b := part(bow, Color("#7a5a30"), Vector3(0.3, 0.9, -0.2))
			b.rotation = Vector3(0, 0, PI / 2)
			eye = Color("#44ffff")
		"brute":
			part(Fx.capsule(0.75, 2.0), c, Vector3(0, 1.0, 0))
			part(Fx.sphere(0.4), c.darkened(0.15), Vector3(0, 1.95, -0.2))
			for sx in [-1, 1]:
				var horn := part(Fx.cone(0.12, 0.5), Color("#d8ccb0"), Vector3(0.28 * sx, 2.3, -0.2))
				horn.rotation.z = -0.5 * sx
				part(Fx.sphere(0.3), c.darkened(0.3), Vector3(0.85 * sx, 1.1, -0.1))
		"shaman":
			part(Fx.capsule(0.3, 1.2), c, Vector3(0, 0.65, 0))
			part(Fx.cone(0.3, 0.5), c.darkened(0.3), Vector3(0, 1.45, 0))
			part(Fx.box(Vector3(0.06, 1.6, 0.06)), Color("#5a4020"), Vector3(0.38, 0.8, -0.1))
			Fx.mesh(model, Fx.sphere(0.12), Fx.mat(Color("#5ad8e8"), 4.0), Vector3(0.38, 1.65, -0.1))
		"boss":
			part(Fx.capsule(1.2, 3.0), c, Vector3(0, 1.5, 0))
			part(Fx.sphere(0.6), c.darkened(0.2), Vector3(0, 3.0, -0.3))
			for sx in [-1, 1]:
				var horn := part(Fx.cone(0.2, 0.9), Color("#d8ccb0"), Vector3(0.45 * sx, 3.5, -0.3))
				horn.rotation.z = -0.6 * sx
				part(Fx.sphere(0.5), c.darkened(0.35), Vector3(1.35 * sx, 1.8, 0))
			eye = Color("#ffff40")
			var glow := OmniLight3D.new()
			glow.light_color = Color("#ff4030")
			glow.light_energy = 1.5
			glow.omni_range = 6.0
			glow.position = Vector3(0, 2.5, 0)
			model.add_child(glow)
	# glowing eyes on the front (-Z)
	var ey := h * 0.82
	var ez := -r * 0.95 if type != "ghoul" else -0.55
	if type == "ghoul":
		ey = 1.25
	elif type == "boss":
		ey = 3.05
		ez = -0.85
	elif type == "brute":
		ey = 2.0
		ez = -0.55
	elif type == "archer" or type == "shaman":
		ey = 1.5
		ez = -0.2
	for sx in [-1, 1]:
		Fx.mesh(model, Fx.sphere(0.045 * (2.0 if boss else 1.0)), Fx.mat(eye, 5.0, true), Vector3(0.09 * sx * (2.5 if boss else 1.0), ey, ez))
	if not elite.is_empty() or boss:
		var aura := Fx.mesh(self, Fx.disc(), Fx.mat(Color(1.0, 0.25, 0.2, 0.35) if boss else Color(0.3, 0.55, 1.0, 0.35), 2.0, true), Vector3(0, 0.03, 0))
		aura.scale = Vector3(r * 1.8, 1, r * 1.8)


func animate(delta: float, moving: bool) -> void:
	sync_node(delta, moving)
	if frozen > 0.0:
		tint(Color("#9fdcff"), 0.7)
	if windup > 0.0:
		model.position.x = randf_range(-0.04, 0.04)
	else:
		model.position.x = 0.0
