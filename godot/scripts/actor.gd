class_name Actor
extends Node3D
## Shared visuals for anything that walks on the dungeon grid.
## Gameplay position lives in `pos` (Vector2 on the ground); the node follows it.
## An actor is drawn either with an animated KayKit rig or with primitive parts.

var pos := Vector2.ZERO
var r := 0.5
var face := 0.0          # ground-plane angle the actor looks toward
var hit_t := 0.0
var flash_mat: StandardMaterial3D = null   # overrides the shared hit flash (the player's is dimmer, set by the option)
var dead := false
var walk_t := 0.0
var frosted := false
var model := Node3D.new()
# primitive parts
var body_mats: Array[StandardMaterial3D] = []
var base_colors: Array[Color] = []
# animated rig
var rig: Node3D
var anim: AnimationPlayer
var cur_anim := ""
var rig_meshes: Array[MeshInstance3D] = []
var _overlay := -1

static var _flash_mat: StandardMaterial3D
static var _frost_mat: StandardMaterial3D


func _init() -> void:
	add_child(model)


## a body part whose color flashes white on hit
func part(m: Mesh, color: Color, at: Vector3, emission := 0.0) -> MeshInstance3D:
	var material := Fx.mat(color, emission)
	if emission <= 0.0:
		body_mats.append(material)
		base_colors.append(color)
	return Fx.mesh(model, m, material, at)


## attach a KayKit character; `keep` names the hand-held meshes to show, `weapon` adds a separate glTF to the right hand
func use_rig(path: String, scale_by: float, keep: Array = [], weapon := "") -> void:
	rig = Assets.character(path)
	rig.scale = Vector3.ONE * scale_by
	rig.rotation.y = PI          # KayKit faces +Z, our models face -Z
	model.add_child(rig)
	anim = rig.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		if String(mi.get_parent().name).begins_with("handslot") and not (String(mi.name) in keep):
			mi.visible = false
			continue
		rig_meshes.append(mi)
	if weapon != "":
		var skel := rig.find_child("Skeleton3D", true, false) as Skeleton3D
		var att := BoneAttachment3D.new()
		att.bone_name = "handslot.r"
		skel.add_child(att)
		var gear := Assets.scene(weapon).instantiate()
		att.add_child(gear)
		for mi in gear.find_children("*", "MeshInstance3D", true, false):
			rig_meshes.append(mi)
	for mi in rig_meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func play(clip: String, speed := 1.0, restart := false, blend := 0.12) -> void:
	if anim == null or not anim.has_animation(clip):
		return
	if clip == cur_anim and not restart:
		return
	cur_anim = clip
	anim.play(clip, blend, speed)
	if restart:
		anim.seek(0.0, true)


func sync_node(delta: float, moving: bool) -> void:
	position = Vector3(pos.x, 0, pos.y)
	# models are built facing -Z
	model.rotation.y = atan2(-cos(face), -sin(face))
	hit_t -= delta
	if rig:
		var want := 1 if hit_t > 0.0 else (2 if frosted else 0)
		if want != _overlay:
			_overlay = want
			var m: Material = null
			if want == 1:
				m = flash_mat if flash_mat else _overlay_mat(true)
			elif want == 2:
				m = _overlay_mat(false)
			for mi in rig_meshes:
				mi.material_overlay = m
		return
	if moving:
		walk_t += delta
		model.position.y = absf(sin(walk_t * 12.0)) * 0.06
	else:
		model.position.y = lerpf(model.position.y, 0.0, delta * 10.0)
	var flash := hit_t > 0.0
	for i in body_mats.size():
		body_mats[i].albedo_color = base_colors[i].lerp(Color.WHITE, flash_mat.albedo_color.a if flash_mat else 1.0) if flash else (base_colors[i].lerp(Color("#9fdcff"), 0.7) if frosted else base_colors[i])


static func _overlay_mat(flash: bool) -> StandardMaterial3D:
	if _flash_mat == null:
		_flash_mat = Fx.mat(Color(1, 1, 1, 0.55), 0.0, true)
		_frost_mat = Fx.mat(Color(0.55, 0.85, 1.0, 0.45), 0.0, true)
	return _flash_mat if flash else _frost_mat
