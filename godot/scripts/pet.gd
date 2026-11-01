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
var tail: Node3D
var lantern: MeshInstance3D


func _ready() -> void:
	r = 0.36
	var fur := Color("#e07a2c")
	var cream := Color("#f4e2c4")
	part(Fx.box(Vector3(0.36, 0.3, 0.7)), fur, Vector3(0, 0.42, 0))
	part(Fx.box(Vector3(0.3, 0.12, 0.5)), cream, Vector3(0, 0.3, -0.04))
	for x in [-0.12, 0.12]:
		for z in [-0.24, 0.24]:
			part(Fx.box(Vector3(0.09, 0.3, 0.09)), Color("#3a2416"), Vector3(x, 0.15, z))
	part(Fx.box(Vector3(0.32, 0.28, 0.3)), fur, Vector3(0, 0.66, -0.42))
	part(Fx.box(Vector3(0.14, 0.12, 0.2)), cream, Vector3(0, 0.6, -0.62))
	part(Fx.box(Vector3(0.06, 0.06, 0.06)), Color("#1a1010"), Vector3(0, 0.64, -0.73))
	for x in [-0.1, 0.1]:
		part(Fx.cone(0.07, 0.2), fur, Vector3(x, 0.88, -0.4))
		Fx.mesh(model, Fx.sphere(0.03), Fx.mat(Color("#ffe27a"), 4.0, true), Vector3(x * 0.8, 0.7, -0.58))
	# a bushy tail carrying the lantern
	tail = Node3D.new()
	tail.position = Vector3(0, 0.5, 0.34)
	model.add_child(tail)
	var t1 := Fx.mesh(tail, Fx.capsule(0.12, 0.6), Fx.mat(fur), Vector3(0, 0.2, 0.16))
	t1.rotation.x = 0.9
	Fx.mesh(tail, Fx.sphere(0.12), Fx.mat(cream), Vector3(0, 0.4, 0.36))
	lantern = Fx.mesh(tail, Fx.sphere(0.1), Fx.mat(Color("#ffd36a"), 6.0, true), Vector3(0, 0.62, 0.38))
	var light := OmniLight3D.new()
	light.light_color = Color("#ffc870")
	light.light_energy = 1.2
	light.omni_range = 5.0
	light.position = Vector3(0, 0.62, 0.38)
	tail.add_child(light)


func animate(delta: float) -> void:
	sync_node(delta, moving)
	walk_t += delta
	tail.rotation.y = sin(walk_t * (9.0 if moving else 3.0)) * 0.35
	lantern.position.y = 0.62 + sin(walk_t * 5.0) * 0.03
