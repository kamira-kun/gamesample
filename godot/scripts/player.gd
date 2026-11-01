class_name Player
extends Actor

var level := 1
var xp := 0
var life := 100.0
var mana := 60.0
var s := {}                 # derived stats
var cds := {}
var action_t := 0.0
var swing_t := 0.0
var swing_dir := 0.0
var invuln := 0.0
var aim := 0.0
var dash := {}
var dead := false
var potions := 3
var potion_prog := 0
var sword_pivot := Node3D.new()
var torch: OmniLight3D


func _ready() -> void:
	r = 0.45
	part(Fx.capsule(0.32, 1.3), Color("#3c4f6e"), Vector3(0, 0.75, 0))
	part(Fx.box(Vector3(0.5, 0.55, 0.12)), Color("#6a1e22"), Vector3(0, 0.95, 0.22))      # cape
	part(Fx.sphere(0.2), Color("#c9a98a"), Vector3(0, 1.6, 0))                               # head
	part(Fx.box(Vector3(0.44, 0.12, 0.34)), Color("#8a7a5a"), Vector3(0, 1.05, 0))          # belt / pauldrons
	model.add_child(sword_pivot)
	sword_pivot.position = Vector3(0.32, 0.95, 0)
	var blade := Fx.mesh(sword_pivot, Fx.box(Vector3(0.06, 0.04, 1.0)), Fx.mat(Color("#d8d8e0"), 0.4), Vector3(0, 0, -0.55))
	blade.name = "Blade"
	Fx.mesh(sword_pivot, Fx.box(Vector3(0.24, 0.06, 0.06)), Fx.mat(Color("#b08a40")), Vector3(0, 0, -0.06))
	torch = OmniLight3D.new()
	torch.position = Vector3(0, 3.2, 0)
	torch.omni_range = 15.0
	torch.light_energy = 2.4
	torch.shadow_enabled = true
	add_child(torch)
	recalc(true)


func recalc(full := false) -> void:
	var L := level
	var old_l: float = life / s.max_life if s else 1.0
	var old_m: float = mana / s.max_mana if s else 1.0
	s = {
		"max_life": 90.0 + L * 12, "max_mana": 60.0 + L * 5, "life_regen": 1.5 + L * 0.25, "mana_regen": 5.0 + L * 0.3,
		"dmg_min": 6.0 + L, "dmg_max": 11.0 + L * 2, "crit": 5.0, "crit_multi": 150.0,
		"attack_rate": 1.5, "cast_speed": 0.0, "move_speed": 8.5, "dr": 0.0,
	}
	life = s.max_life if full else s.max_life * old_l
	mana = s.max_mana if full else s.max_mana * old_m


func animate(delta: float, moving: bool) -> void:
	face = aim
	sync_node(delta, moving)
	# sword swings across the front while attacking
	var a := 0.0
	if swing_t > 0.0:
		a = lerpf(1.3, -1.3, 1.0 - swing_t / 0.2)
	sword_pivot.rotation.y = a
	model.visible = not (invuln > 0.0 and not dash.is_empty() and int(Time.get_ticks_msec() / 50) % 2 == 0)
