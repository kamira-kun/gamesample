class_name Settings
## Options that aren't key bindings: the map overlay's transparency and zoom, and how strong the feedback of the
## player taking a hit is (red vignette, low-life throb, camera shake, sprite flash; 0 turns them off). Like the bindings they are a user
## setting, not part of a character, and live in the same file (Keybinds.PATH) under [options].
## Dev runs set `path` to "" so they never touch the player's file.

const TRANSPARENCY := [0, 90]    # percent, the slider's range
const ZOOM := [50, 300]          # percent
const HURT_FX := [0, 100]        # percent
const DEFAULTS := {"map_transparency": 40, "map_zoom": 100, "hurt_fx": 50}

static var path := Keybinds.PATH
static var map_transparency: int = DEFAULTS.map_transparency
static var map_zoom: int = DEFAULTS.map_zoom
static var hurt_fx: int = DEFAULTS.hurt_fx


## how opaque the map overlay is drawn (0..1)
static func map_opacity() -> float:
	return 1.0 - map_transparency / 100.0


## how strong the hit-taken feedback is drawn (0..1)
static func hurt_fx_scale() -> float:
	return hurt_fx / 100.0


static func set_transparency(v: int) -> void:
	map_transparency = clampi(v, TRANSPARENCY[0], TRANSPARENCY[1])
	save()


static func set_zoom(v: int) -> void:
	map_zoom = clampi(v, ZOOM[0], ZOOM[1])
	save()


static func set_hurt_fx(v: int) -> void:
	hurt_fx = clampi(v, HURT_FX[0], HURT_FX[1])
	save()


static func reset() -> void:
	map_transparency = DEFAULTS.map_transparency
	map_zoom = DEFAULTS.map_zoom
	hurt_fx = DEFAULTS.hurt_fx


static func save(p := path) -> void:
	if p == "":
		return
	var cf := ConfigFile.new()
	cf.load(p)   # keep the key bindings already in the file
	cf.set_value("options", "map_transparency", map_transparency)
	cf.set_value("options", "map_zoom", map_zoom)
	cf.set_value("options", "hurt_fx", hurt_fx)
	cf.save(p)


## read the options (missing or broken entries fall back to the defaults, out-of-range ones are clamped)
static func load_file(p := path) -> void:
	reset()
	var cf := ConfigFile.new()
	if cf.load(p) != OK:
		return
	var t = cf.get_value("options", "map_transparency", null)
	if typeof(t) in [TYPE_INT, TYPE_FLOAT]:
		map_transparency = clampi(int(t), TRANSPARENCY[0], TRANSPARENCY[1])
	var z = cf.get_value("options", "map_zoom", null)
	if typeof(z) in [TYPE_INT, TYPE_FLOAT]:
		map_zoom = clampi(int(z), ZOOM[0], ZOOM[1])
	var h = cf.get_value("options", "hurt_fx", null)
	if typeof(h) in [TYPE_INT, TYPE_FLOAT]:
		hurt_fx = clampi(int(h), HURT_FX[0], HURT_FX[1])
