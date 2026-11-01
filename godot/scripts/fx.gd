class_name Fx
extends RefCounted
## Small helpers that build placeholder meshes, materials and one-shot effects in code.


static func mat(color: Color, emission := 0.0, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func mesh(parent: Node3D, m: Mesh, material: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	parent.add_child(mi)
	return mi


static func sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return s


static func capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	return c


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func cone(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 10
	return c


## flat disc lying on the ground, radius 1 (scale it)
static func disc() -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 1.0
	c.bottom_radius = 1.0
	c.height = 0.02
	c.radial_segments = 48
	return c


## flat ring band on the ground between r0 and r1, from angle a0 to a1 (ground-plane angles)
static func arc_mesh(r0: float, r1: float, a0: float, a1: float, segs := 24) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs:
		var t0 := lerpf(a0, a1, float(i) / segs)
		var t1 := lerpf(a0, a1, float(i + 1) / segs)
		var p00 := Vector3(cos(t0) * r0, 0, sin(t0) * r0)
		var p01 := Vector3(cos(t0) * r1, 0, sin(t0) * r1)
		var p10 := Vector3(cos(t1) * r0, 0, sin(t1) * r0)
		var p11 := Vector3(cos(t1) * r1, 0, sin(t1) * r1)
		for v in [p00, p01, p11, p00, p11, p10]:
			st.add_vertex(v)
	return st.commit()


## fade a material's alpha (and optionally grow the node), then free it
static func fade_out(node: Node3D, m: StandardMaterial3D, dur: float, grow := Vector3.ZERO) -> void:
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tw := node.create_tween().set_parallel(true)
	tw.tween_property(m, "albedo_color:a", 0.0, dur)
	if grow != Vector3.ZERO:
		tw.tween_property(node, "scale", grow, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(node.queue_free)


## expanding glowing ring on the ground
static func ring(parent: Node3D, pos: Vector3, radius: float, color: Color, dur := 0.4, filled := true) -> void:
	var root := Node3D.new()
	root.position = pos + Vector3(0, 0.06, 0)
	root.scale = Vector3(radius * 0.2, 1, radius * 0.2)
	parent.add_child(root)
	var m := mat(Color(color, 0.9), 3.0, true)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh(root, arc_mesh(0.88, 1.0, 0, TAU, 48), m)
	if filled:
		var mf := mat(Color(color, 0.25), 1.5, true)
		mf.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mesh(root, disc(), mf)
		fade_out(root, mf, dur)
	fade_out(root, m, dur, Vector3(radius, 1, radius))


## burst of glowing sparks
static func burst(parent: Node3D, pos: Vector3, n: int, color: Color, speed: float, life := 0.6, gravity := -6.0) -> void:
	var p := CPUParticles3D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = maxi(n, 1)
	p.lifetime = life
	p.mesh = sphere(0.06)
	var m := mat(color, 4.0, true)
	p.material_override = m
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.3
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	parent.add_child(p)
	p.emitting = true
	p.get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


## jagged lightning between two points
static func bolt(parent: Node3D, a: Vector3, b: Vector3, color := Color("#d9c2ff"), dur := 0.22) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	var m := mat(color, 6.0, true)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var prev := a
	var segs := 7
	for i in range(1, segs + 1):
		var t := float(i) / segs
		var q := a.lerp(b, t)
		if i < segs:
			q += Vector3(randf_range(-0.4, 0.4), randf_range(-0.3, 0.3), randf_range(-0.4, 0.4))
		var seg := MeshInstance3D.new()
		var seg_len := prev.distance_to(q)
		seg.mesh = box(Vector3(0.07, 0.07, seg_len))
		seg.material_override = m
		root.add_child(seg)
		seg.global_position = (prev + q) / 2.0
		if seg_len > 0.01:
			seg.look_at(q, Vector3.UP if absf((q - prev).normalized().y) < 0.99 else Vector3.RIGHT)
		prev = q
	fade_out(root, m, dur)
