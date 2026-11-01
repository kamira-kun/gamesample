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
var invuln := 0.0
var aim := 0.0
var dash := {}
var dead := false
var potions := 3
var potion_prog := 0
var torch: OmniLight3D
var act_left := 0.0          # time the current one-shot animation still owns the body


func _ready() -> void:
	r = 0.45
	use_rig(Assets.ADVENTURERS + "Knight.glb", 1.0, ["1H_Sword", "Round_Shield"])
	torch = OmniLight3D.new()
	torch.position = Vector3(0, 3.2, 0)
	torch.omni_range = 15.0
	torch.light_energy = 2.2
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


## play an attack/cast clip that holds for `hold` seconds before locomotion resumes
func act(clip: String, speed: float, hold: float) -> void:
	play(clip, speed, true, 0.05)
	act_left = hold


func animate(delta: float, moving: bool) -> void:
	face = aim
	sync_node(delta, moving)
	act_left -= delta
	if dead:
		play("Death_A", 1.0, false, 0.1)
	elif not dash.is_empty():
		play("Dodge_Forward", 2.0)
	elif act_left > 0.0:
		pass
	elif moving:
		play("Running_A", 1.2)
	else:
		play("Idle")
