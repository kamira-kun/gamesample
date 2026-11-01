extends SceneTree
## Dev tool: print sizes of dungeon pieces and animation names of characters.
## godot --headless --path . --script res://tools/inspect_assets.gd

const DUNGEON := "res://assets/kaykit/dungeon/Assets/gltf/"
const PIECES := ["wall_half", "torch_mounted", "barrel_small", "box_small", "crates_stacked", "keg", "candle_triple", "floor_tile_small_decorated", "floor_tile_small_weeds_A"]
const CHARS := ["res://assets/kaykit/adventurers/Characters/gltf/Barbarian.glb", "res://assets/kaykit/adventurers/Characters/gltf/Rogue_Hooded.glb", "res://assets/kaykit/skeletons/Characters/gltf/Skeleton_Rogue.glb", "res://assets/kaykit/skeletons/Characters/gltf/Skeleton_Mage.glb",
	"res://assets/kaykit/skeletons/Characters/gltf/Skeleton_Warrior.glb"]


func _init() -> void:
	for n in PIECES:
		var path: String = DUNGEON + n + ".gltf.glb"
		if not ResourceLoader.exists(path):
			path = DUNGEON + n + ".glb"
		var ps: PackedScene = load(path)
		if ps == null:
			print("MISSING ", n)
			continue
		var inst := ps.instantiate()
		print("%-28s %s" % [n, _aabb(inst)])
		inst.free()
	for c in CHARS:
		var inst: Node = (load(c) as PackedScene).instantiate()
		var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		print(c.get_file(), " aabb=", _aabb(inst))
		if ap:
			print("  anims: ", ", ".join(ap.get_animation_list()))
		var sk := inst.find_child("Skeleton3D", true, false) as Skeleton3D
		if sk:
			var bones := []
			for i in sk.get_bone_count():
				bones.append(sk.get_bone_name(i))
			print("  bones: ", ", ".join(bones))
		for ch in inst.find_children("*", "MeshInstance3D", true, false):
			print("  mesh: ", ch.name, " parent=", ch.get_parent().name)
		for ch in inst.find_children("*", "BoneAttachment3D", true, false):
			print("  attach: ", ch.name, " bone=", ch.bone_name, " children=", ch.get_children().map(func(x): return x.name))
		inst.free()
	quit()


func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = mi.get_aabb()
		var x: Transform3D = Transform3D()
		var cur: Node = mi
		while cur != n and cur is Node3D:
			x = (cur as Node3D).transform * x
			cur = cur.get_parent()
		a = x * a
		box = a if first else box.merge(a)
		first = false
	return box
