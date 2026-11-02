class_name Ally
extends Actor
## Something fighting for the player that enemies can attack: a summoned skeleton or a skill totem.

var kind := "minion"         # "minion" | "totem"
var life := 50.0
var max_life := 50.0
var sup: Dictionary          # support modifiers of the skill that made it
# minion
var target: Enemy = null
var atk_cd := 0.4
var scan_t := 0.0
var swing_t := 0.0
var coef := 0.55             # damage of each swing, as a multiple of the player's damage
# totem
var skill := ""
var t := 0.0
var max_t := 10.0
var cast_t := 0.4
var casts := 0                # times it has cast its skill
var orb: MeshInstance3D
var trap := false            # a trap from a support gem: springs once when an enemy comes close


func setup_minion(at: Vector2, hp: float, s: Dictionary, tint := Color(0.5, 1.0, 0.6)) -> void:
	kind = "minion"
	max_t = 0.0
	pos = at
	r = 0.45
	life = hp
	max_life = hp
	sup = s
	use_rig(Assets.SKELETONS + "Skeleton_Warrior.glb", 0.75, [], Assets.SKELETON_GEAR + "Skeleton_Blade.gltf")
	# a pale green ring tells them apart from hostile skeletons
	var ring := Fx.mesh(self, Fx.disc(), Fx.mat(Color(tint, 0.3), 2.0, true), Vector3(0, 0.03, 0))
	ring.scale = Vector3(0.7, 1, 0.7)
	play("Spawn_Ground_Skeletons", 1.6, true, 0.0)


func setup_totem(at: Vector2, id: String, hp: float, s: Dictionary) -> void:
	kind = "totem"
	pos = at
	r = 0.5
	life = hp
	max_life = hp
	sup = s
	skill = id
	var col: Color = Data.SKILLS[id].color
	part(Fx.cone(0.32, 0.5), Color("#4a3624"), Vector3(0, 0.25, 0))
	part(Fx.box(Vector3(0.3, 1.5, 0.3)), Color("#8a6038"), Vector3(0, 1.1, 0))
	part(Fx.box(Vector3(0.6, 0.18, 0.18)), Color("#6a4628"), Vector3(0, 1.55, 0))
	orb = Fx.mesh(model, Fx.sphere(0.2), Fx.mat(col, 5.0, true), Vector3(0, 2.15, 0))
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 1.4
	light.omni_range = 6.0
	light.position.y = 2.2
	model.add_child(light)


func animate(delta: float, moving: bool) -> void:
	sync_node(delta, moving)
	if kind == "totem":
		orb.position.y = 2.15 + sin(t * 4.0) * 0.08
		return
	swing_t -= delta
	if cur_anim == "Spawn_Ground_Skeletons" and anim.is_playing():
		return
	if swing_t > 0.0:
		play("1H_Melee_Attack_Chop", 1.6)
	elif cur_anim == "1H_Melee_Attack_Chop" and anim.is_playing():
		return
	elif moving:
		play("Running_A", 1.1)
	else:
		play("Idle_Combat" if target else "Idle")
