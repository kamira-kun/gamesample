class_name Pet
extends Actor
## The lantern fox: roams around the player and fetches loot lying nearby.

const NAME := "灯り狐"

var target: Dictionary = {}    # the ground item or currency it is fetching
var scan_t := 0.0
var wander_t := 0.0
var home := Vector2.INF        # where it idles, relative to the player
var stuck_t := 0.0
var moving := false
var lantern: MeshInstance3D


func _ready() -> void:
	r = 0.36
	use_rig(Assets.QUATERNIUS + "Fox.glb", 0.3)
	play("Idle")
	# a lantern hanging from the tip of its bushy tail
	var skel := rig.find_child("Skeleton3D", true, false) as Skeleton3D
	var att := BoneAttachment3D.new()
	att.bone_name = "Tail6"
	skel.add_child(att)
	var hold := Node3D.new()           # keeps the lantern at world size
	hold.scale = Vector3.ONE / skel.global_basis.get_scale()    # the armature is scaled up 100x
	att.add_child(hold)
	lantern = Fx.mesh(hold, Fx.sphere(0.1), Fx.mat(Color("#ffd36a"), 6.0, true), Vector3.ZERO)
	var light := OmniLight3D.new()
	light.light_color = Color("#ffc870")
	light.light_energy = 1.2
	light.omni_range = 5.0
	hold.add_child(light)


func animate(delta: float) -> void:
	sync_node(delta, moving)
	walk_t += delta
	play("Gallop" if moving else "Idle", 1.4 if moving else 1.0)
	lantern.position.y = sin(walk_t * 5.0) * 0.03
