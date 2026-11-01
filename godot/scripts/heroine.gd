class_name Heroine
extends RefCounted
## Dresses the Knight rig as the player's heroine: the Rogue's head with a softened face (no nose,
## bigger blue eyes), pink bob hair with an ahoge, round glasses, and the armor recolored navy and silver.

const HAIR := Color("#f59ac3")
const EYES_TOP := Color("#7fb2ff")
const EYES_BOTTOM := Color("#1f3388")
const SKIN := Color("#fbd3bd")
const ARMOR := Color("#2f3f8c")
const ARMOR_DARK := Color("#1d2656")
const TRIM := Color("#d3d8e2")
const FRAME := Color("#6e5b78")

static var _head_mesh: ArrayMesh
static var _head_skin: Skin
static var _head_mat: StandardMaterial3D
static var _body_mat: StandardMaterial3D


static func dress(a: Actor) -> void:
	var skel := a.rig.find_child("Skeleton3D", true, false) as Skeleton3D
	_build()
	a.rig.find_child("Knight_Cape", true, false).visible = false
	a.rig.find_child("Knight_Helmet", true, false).visible = false
	for mi in a.rig_meshes:
		if String(mi.name).begins_with("Knight_"):
			mi.material_override = _body_mat
	var head := a.rig.find_child("Knight_Head", true, false) as MeshInstance3D
	head.mesh = _head_mesh
	head.skin = _head_skin
	head.material_override = _head_mat
	# accessories ride the head bone; positions below are in rig space (the face looks toward +Z)
	var att := BoneAttachment3D.new()
	att.bone_name = "head"
	skel.add_child(att)
	var to_bone := skel.get_bone_global_rest(skel.find_bone("head")).affine_inverse()
	var frame := Fx.mat(FRAME)
	frame.metallic = 0.6
	frame.roughness = 0.35
	var hair := Fx.mat(HAIR)
	var parts: Array[MeshInstance3D] = []
	for sx in [-1.0, 1.0]:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.118
		ring.outer_radius = 0.138
		ring.rings = 24
		ring.ring_segments = 6
		parts.append(_part(att, to_bone, ring, frame, Vector3(sx * 0.205, 1.61, 0.47), Vector3(PI / 2, 0, 0)))
		parts.append(_part(att, to_bone, Fx.box(Vector3(0.022, 0.022, 0.42)), frame, Vector3(sx * 0.4, 1.63, 0.25), Vector3(0, -sx * 0.34, 0)))
		# anime highlight in each eye
		parts.append(_part(att, to_bone, Fx.sphere(0.026), Fx.mat(Color.WHITE, 0.6), Vector3(sx * 0.205 - 0.035, 1.645, 0.452), Vector3.ZERO))
	parts.append(_part(att, to_bone, Fx.box(Vector3(0.14, 0.022, 0.022)), frame, Vector3(0, 1.635, 0.475), Vector3.ZERO))
	for sx in [-1.0, 1.0]:
		var blush := _part(att, to_bone, Fx.sphere(0.06), Fx.mat(Color(1.0, 0.55, 0.65, 0.55)), Vector3(sx * 0.27, 1.47, 0.39), Vector3(0, sx * 0.45, 0))
		blush.scale = Vector3(1.3, 0.55, 0.25)
		parts.append(blush)
	# ahoge: a strand that springs up from the crown and curls forward
	var curl := [Vector3(0, 2.12, 0.0), Vector3(0, 2.25, 0.02), Vector3(0, 2.33, 0.09), Vector3(0, 2.35, 0.18)]
	for i in curl.size() - 1:
		var d: Vector3 = curl[i + 1] - curl[i]
		var r := 0.04 - i * 0.008
		parts.append(_part(att, to_bone, Fx.capsule(r, d.length() + r * 2.0), hair, (curl[i] + curl[i + 1]) / 2.0, Vector3(atan2(d.z, d.y), 0, 0)))
	for mi in parts:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		a.rig_meshes.append(mi)


static func _part(parent: Node3D, to_bone: Transform3D, m: Mesh, material: Material, at: Vector3, rot: Vector3) -> MeshInstance3D:
	var mi := Fx.mesh(parent, m, material)
	mi.transform = to_bone * Transform3D(Basis.from_euler(rot), at)
	return mi


static func _build() -> void:
	if _head_mesh:
		return
	var knight := Assets.scene(Assets.ADVENTURERS + "Knight.glb").instantiate()
	var km := (knight.find_child("Knight_Body", true, false) as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
	_body_mat = km.duplicate()
	_body_mat.albedo_texture = _recolor(km.albedo_texture, {
		Vector2i(3, 0): ARMOR, Vector2i(7, 1): ARMOR_DARK, Vector2i(6, 0): TRIM, Vector2i(0, 1): Color("#fff6e0"),
	}, {})
	knight.free()
	var rogue := Assets.scene(Assets.ADVENTURERS + "Rogue.glb").instantiate()
	var rh := rogue.find_child("Rogue_Head", true, false) as MeshInstance3D
	_head_skin = rh.skin
	var rm := rh.mesh.surface_get_material(0) as StandardMaterial3D
	_head_mat = rm.duplicate()
	_head_mat.albedo_texture = _recolor(rm.albedo_texture, {Vector2i(0, 0): SKIN, Vector2i(1, 0): HAIR}, {Vector2i(2, 0): [EYES_TOP, EYES_BOTTOM]})
	_head_mesh = _soften_face(rh.mesh)
	rogue.free()


## the Rogue head with the nose pressed flat, the eyes enlarged and the brows lifted to make room
static func _soften_face(src: Mesh) -> ArrayMesh:
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for k in verts.size():
		var v := verts[k]
		var tile := Vector2i(int(uvs[k].x * 8.0), int(uvs[k].y * 4.0))
		if tile == Vector2i(0, 0) and absf(v.x) < 0.12 and v.y > 1.37 and v.y < 1.54 and v.z > 0.4:
			v.z = minf(v.z, 0.44 + (v.z - 0.44) * 0.15)
			normals[k] = Vector3(0, 0.15, 1).normalized()
		elif tile == Vector2i(2, 0):
			var c := Vector2(signf(v.x) * 0.205, 1.606)
			v.x = c.x + (v.x - c.x) * 1.12
			v.y = c.y + (v.y - c.y) * 1.35
		elif tile == Vector2i(1, 0) and absf(v.x) < 0.32 and v.y > 1.68 and v.y < 1.8 and v.z > 0.355:
			v.y += 0.04
		verts[k] = v
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, src.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	return out


## repaint tiles of a KayKit 8x4 palette texture: `tint` keeps each tile's shading under a new color,
## `grad` paints a fresh top-to-bottom gradient (for near-black tiles that have no shading to keep)
static func _recolor(tex: Texture2D, tint: Dictionary, grad: Dictionary) -> ImageTexture:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	var tw := img.get_width() / 8
	var th := img.get_height() / 4
	for t: Vector2i in tint:
		var mean := 0.0
		for y in th:
			for x in tw:
				mean += img.get_pixel(t.x * tw + x, t.y * th + y).get_luminance()
		mean = maxf(mean / (tw * th), 0.01)
		var c: Color = tint[t]
		for y in th:
			for x in tw:
				var p := img.get_pixel(t.x * tw + x, t.y * th + y)
				var l := 1.0 + (p.get_luminance() / mean - 1.0) * 0.6
				img.set_pixel(t.x * tw + x, t.y * th + y, Color(minf(c.r * l, 1.0), minf(c.g * l, 1.0), minf(c.b * l, 1.0)))
	for t: Vector2i in grad:
		for y in th:
			var c: Color = grad[t][0].lerp(grad[t][1], float(y) / th)
			for x in tw:
				img.set_pixel(t.x * tw + x, t.y * th + y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
