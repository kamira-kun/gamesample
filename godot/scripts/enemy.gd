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
var shock := 0.0            # ascendancy "shock": takes more damage while > 0
var burn_t := 0.0           # ascendancy "ignite": seconds of burning left
var burn_dps := 0.0
var burn_acc := 0.0         # burn damage not yet shown as a number
var burn_show := 0.0
var bleed_t := 0.0
var bleed_dps := 0.0
var poison_t := 0.0
var poison_dps := 0.0          # poison doses add up
var vuln := 0.0             # curses: extra damage taken while vuln_t > 0
var vuln_t := 0.0
var stun := 0.0
var aggro := false
var sees := false
var los_t := 0.0
var wander_t := 0.0
var wandering := 0.0
var act_t := 2.0
var elite: Dictionary = {}
var boss := false
var pack := 0
var display_name := ""
var aura: MeshInstance3D
var winding := false
var tgt: Actor = null       # who it is fighting: the player, a minion or a totem
var tgt_t := 0.0
var charge := {}            # colossus: the charge in progress
var enraged := false        # bosses below half life

# KayKit rigs per monster type (imps keep their primitive look)
const RIGS := {
	"ghoul": {"path": "res://assets/kaykit/skeletons/Characters/gltf/Skeleton_Minion.glb", "scale": 0.85, "weapon": "res://assets/kaykit/skeletons/Assets/gltf/Skeleton_Blade.gltf", "run": "Walking_D_Skeletons", "run_speed": 1.3, "attack": "1H_Melee_Attack_Chop"},
	"archer": {"path": "res://assets/kaykit/skeletons/Characters/gltf/Skeleton_Rogue.glb", "scale": 0.85, "weapon": "res://assets/kaykit/skeletons/Assets/gltf/Skeleton_Crossbow.gltf", "run": "Running_A", "attack": "1H_Ranged_Shoot"},
	"shaman": {"path": "res://assets/kaykit/skeletons/Characters/gltf/Skeleton_Mage.glb", "scale": 0.85, "weapon": "res://assets/kaykit/skeletons/Assets/gltf/Skeleton_Staff.gltf", "run": "Walking_B", "attack": "Spellcast_Long", "atk_speed": 1.0},
	"brute": {"path": "res://assets/kaykit/skeletons/Characters/gltf/Skeleton_Warrior.glb", "scale": 1.3, "weapon": "res://assets/kaykit/skeletons/Assets/gltf/Skeleton_Axe.gltf", "run": "Walking_D_Skeletons", "attack": "1H_Melee_Attack_Jump_Chop", "atk_speed": 1.0},
	"boss": {"path": "res://assets/kaykit/adventurers/Characters/gltf/Barbarian.glb", "scale": 1.9, "keep": ["2H_Axe", "Barbarian_Round_Shield"], "run": "Walking_C", "attack": "2H_Melee_Attack_Chop", "atk_speed": 1.0},
	"colossus": {"path": "res://assets/kaykit/skeletons/Characters/gltf/Skeleton_Warrior.glb", "scale": 2.4, "weapon": "res://assets/kaykit/skeletons/Assets/gltf/Skeleton_Axe.gltf", "run": "Walking_D_Skeletons", "attack": "1H_Melee_Attack_Jump_Chop", "atk_speed": 1.0, "glow": Color("#ff7a30")},
	"witch": {"path": "res://assets/kaykit/adventurers/Characters/gltf/Mage.glb", "scale": 1.5, "keep": ["2H_Staff"], "run": "Running_B", "attack": "Spellcast_Shoot", "atk_speed": 1.2, "glow": Color("#8fdcff")},
}


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
	if RIGS.has(type):
		var rc: Dictionary = RIGS[type]
		use_rig(rc.path, rc.scale, rc.get("keep", []), rc.get("weapon", ""))
		play("Idle")
		anim.seek(randf() * 2.0, true)   # don't let a whole pack idle in sync
		if boss:
			var glow := OmniLight3D.new()
			glow.light_color = rc.get("glow", Color("#ff4030"))
			glow.light_energy = 1.5
			glow.omni_range = 7.0
			glow.position = Vector3(0, 3.0, 0)
			model.add_child(glow)
	else:
		# imps have no KayKit counterpart yet: a small horned devil with glowing eyes
		var c: Color = t.color
		part(Fx.capsule(0.3, 0.8), c, Vector3(0, 0.45, 0))
		part(Fx.cone(0.08, 0.3), Color("#2a1410"), Vector3(-0.15, 0.95, 0))
		part(Fx.cone(0.08, 0.3), Color("#2a1410"), Vector3(0.15, 0.95, 0))
		for sx in [-1, 1]:
			Fx.mesh(model, Fx.sphere(0.045), Fx.mat(Color("#ffda4a"), 5.0, true), Vector3(0.09 * sx, 0.8, -r * 0.95))
	if not elite.is_empty() or boss:
		var ac: Color = Color(1.0, 0.25, 0.2) if boss else Color(0.3, 0.55, 1.0)
		if boss and RIGS[type].has("glow"):
			ac = RIGS[type].glow
		aura = Fx.mesh(self, Fx.disc(), Fx.mat(Color(ac, 0.35), 2.0, true), Vector3(0, 0.03, 0))
		aura.scale = Vector3(r * 1.8, 1, r * 1.8)


func animate(delta: float, moving: bool, near := true) -> void:
	frosted = frozen > 0.0
	sync_node(delta, moving)
	if anim == null:
		model.position.x = randf_range(-0.04, 0.04) if windup > 0.0 else 0.0
		return
	anim.active = near
	if not near:
		return
	anim.speed_scale = 0.0 if frosted else 1.0
	var rc: Dictionary = RIGS[type]
	if windup > 0.0:
		if not winding:
			winding = true
			play(rc.attack, rc.get("atk_speed", 1.3), true, 0.05)
	else:
		winding = false
		if cur_anim == rc.attack and anim.is_playing():
			return       # let the swing finish
		if moving:
			play(rc.run, rc.get("run_speed", 1.0))
		else:
			play("Idle_Combat" if aggro else "Idle")


## fall over, then disappear
func die() -> void:
	if aura:
		aura.queue_free()
	if anim:
		anim.speed_scale = 1.0
		play("Death_A", 1.3, true, 0.05)
		get_tree().create_timer(2.0).timeout.connect(queue_free)
	else:
		queue_free()
