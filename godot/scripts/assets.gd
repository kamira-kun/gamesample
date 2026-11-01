class_name Assets
extends RefCounted
## Paths and loaders for the KayKit CC0 art (godot/assets/kaykit).

const DUNGEON := "res://assets/kaykit/dungeon/Assets/gltf/"
const ADVENTURERS := "res://assets/kaykit/adventurers/Characters/gltf/"
const SKELETONS := "res://assets/kaykit/skeletons/Characters/gltf/"
const SKELETON_GEAR := "res://assets/kaykit/skeletons/Assets/gltf/"
# clips that should repeat (glTF imports them as one-shots)
const LOOPS := ["Idle", "Idle_B", "Idle_Combat", "Running_A", "Running_B", "Running_C", "Walking_A", "Walking_B",
	"Walking_C", "Walking_D_Skeletons", "Spellcasting", "2H_Melee_Idle", "Unarmed_Idle"]

static var _scenes := {}
static var _meshes := {}


static func scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


static func piece_path(piece_name: String) -> String:
	var p := DUNGEON + piece_name + ".gltf.glb"
	return p if ResourceLoader.exists(p) else DUNGEON + piece_name + ".glb"


static func piece(piece_name: String) -> Node3D:
	return scene(piece_path(piece_name)).instantiate()


## the mesh of a dungeon piece plus its transform inside the glTF scene, for multimeshes
static func piece_mesh(piece_name: String) -> Dictionary:
	if not _meshes.has(piece_name):
		var inst := piece(piece_name)
		var mi := inst.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var xf := Transform3D()
		var cur: Node = mi
		while cur != inst:
			xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		_meshes[piece_name] = {"mesh": mi.mesh, "xform": xf}
		inst.free()
	return _meshes[piece_name]


static func character(path: String) -> Node3D:
	var inst := scene(path).instantiate() as Node3D
	var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap:
		for clip in LOOPS:
			if ap.has_animation(clip):
				ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	return inst
