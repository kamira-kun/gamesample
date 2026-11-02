class_name Portrait
extends VBoxContainer
## The character picture on the status screen: an image the player loads, or else the heroine herself
## rendered live in her own little world, holding whatever weapon is equipped.
## The loaded image is copied to user:// so it stays on this machine and out of the repository.

const PATH := "user://portrait.png"
const SIZE := Vector2i(220, 300)

var preview := false   # set before adding: only the live heroine, no image to load (the character screen's class preview)

var frame := PanelContainer.new()
var picture := TextureRect.new()
var stage := SubViewportContainer.new()
var view := SubViewport.new()
var doll: Player
var load_btn := Button.new()
var reset_btn := Button.new()
var dialog := FileDialog.new()


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.024, 0.03)
	sb.border_color = Color("#5a4630")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	frame.add_theme_stylebox_override("panel", sb)
	frame.custom_minimum_size = SIZE
	frame.clip_contents = true
	add_child(frame)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	frame.add_child(picture)
	stage.stretch = true
	frame.add_child(stage)
	view.own_world_3d = true
	view.transparent_bg = true
	view.msaa_3d = Viewport.MSAA_4X
	stage.add_child(view)
	_build_stage()
	if preview:
		for n: Node in [load_btn, reset_btn, dialog]:
			n.free()
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	for b: Button in [load_btn, reset_btn]:
		b.add_theme_font_size_override("font_size", 12)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	load_btn.text = "画像を読み込む"
	load_btn.pressed.connect(dialog.popup_centered_ratio.bind(0.6))
	reset_btn.text = "3D表示に戻す"
	reset_btn.pressed.connect(_clear_image)
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.title = "キャラクター画像を選ぶ"
	dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; 画像"])
	dialog.file_selected.connect(_load_image)
	add_child(dialog)
	_show_saved()


## camera, light and the heroine on her own world so the dungeon never shows behind her
func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.58, 0.66)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	view.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.86, 0.7)
	key.light_energy = 1.1
	key.rotation = Vector3(deg_to_rad(-30), deg_to_rad(200), 0)
	view.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.55, 0.65, 1.0)
	rim.light_energy = 0.7
	rim.rotation = Vector3(deg_to_rad(-15), deg_to_rad(20), 0)
	view.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0.1, 1.25, -6.6)   # off-center so the weapon hand stays in frame
	view.add_child(cam)
	cam.look_at(Vector3(0.1, 1.1, 0))
	doll = Player.new()
	doll.face = -PI / 2.0 - 0.3   # facing the camera, the weapon arm turned back a little so long weapons fit
	view.add_child(doll)
	doll.torch.visible = false
	doll.sync_node(0.0, false)
	doll.play("Idle")


## dress the doll in the player's current gear and class colors
func show_player(p: Player) -> void:
	if doll.cls != p.cls:
		doll.set_class(p.cls)
	doll.equip = p.equip
	doll.refresh_gear()


## the heroine as a new character of base class `k`, with its starting weapon
func show_class(k: String) -> void:
	doll.set_class(k, true)


func _show_saved() -> void:
	var tex: Texture2D = null
	if FileAccess.file_exists(PATH):
		var img := Image.load_from_file(PATH)
		if img:
			tex = ImageTexture.create_from_image(img)
	picture.texture = tex
	picture.visible = tex != null
	stage.visible = tex == null
	reset_btn.disabled = tex == null


func _load_image(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return
	img.save_png(PATH)
	_show_saved()


func _clear_image() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	_show_saved()
