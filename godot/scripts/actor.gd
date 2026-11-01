class_name Actor
extends Node3D
## Shared visual bits for anything that walks on the dungeon grid.
## Gameplay position lives in `pos` (Vector2 on the ground); the node follows it.

var pos := Vector2.ZERO
var r := 0.5
var face := 0.0          # ground-plane angle the actor looks toward
var hit_t := 0.0
var walk_t := 0.0
var body_mats: Array[StandardMaterial3D] = []
var base_colors: Array[Color] = []
var model := Node3D.new()


func _init() -> void:
	add_child(model)


## a body part whose color flashes white on hit
func part(m: Mesh, color: Color, at: Vector3, emission := 0.0) -> MeshInstance3D:
	var material := Fx.mat(color, emission)
	if emission <= 0.0:
		body_mats.append(material)
		base_colors.append(color)
	return Fx.mesh(model, m, material, at)


func sync_node(delta: float, moving: bool) -> void:
	position = Vector3(pos.x, 0, pos.y)
	# models are built facing -Z
	model.rotation.y = atan2(-cos(face), -sin(face))
	if moving:
		walk_t += delta
		model.position.y = absf(sin(walk_t * 12.0)) * 0.06
	else:
		model.position.y = lerpf(model.position.y, 0.0, delta * 10.0)
	hit_t -= delta
	var flash := hit_t > 0.0
	for i in body_mats.size():
		body_mats[i].albedo_color = Color.WHITE if flash else base_colors[i]


func tint(color: Color, amount: float) -> void:
	for i in body_mats.size():
		body_mats[i].albedo_color = base_colors[i].lerp(color, amount)
