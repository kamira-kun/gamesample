class_name Keybinds
## The player's key and mouse bindings, as InputMap actions. Each action has two binding slots
## (a binding is {"key": physical keycode} or {"mouse": button index}, {} when empty).
## Bindings are a user setting, not part of a character: they live in their own file, read at startup.
## Esc is fixed (close panels / pause / cancel a rebind) and never part of these actions.

const PATH := "user://emberfall_settings.cfg"
const SLOTS := 2

# in display order; `group` heads a section of the key config panel
const ACTIONS := [
	{"id": "move_up", "name": "上へ移動", "group": "移動", "keys": [{"key": KEY_W}]},
	{"id": "move_down", "name": "下へ移動", "group": "移動", "keys": [{"key": KEY_S}]},
	{"id": "move_left", "name": "左へ移動", "group": "移動", "keys": [{"key": KEY_A}]},
	{"id": "move_right", "name": "右へ移動", "group": "移動", "keys": [{"key": KEY_D}]},
	{"id": "skill_1", "name": "スキルスロット 1", "group": "スキル", "keys": [{"mouse": MOUSE_BUTTON_LEFT}]},
	{"id": "skill_2", "name": "スキルスロット 2", "group": "スキル", "keys": [{"mouse": MOUSE_BUTTON_RIGHT}]},
	{"id": "skill_3", "name": "スキルスロット 3", "group": "スキル", "keys": [{"key": KEY_Q}]},
	{"id": "skill_4", "name": "スキルスロット 4", "group": "スキル", "keys": [{"key": KEY_E}]},
	{"id": "skill_5", "name": "スキルスロット 5", "group": "スキル", "keys": [{"key": KEY_R}]},
	{"id": "skill_6", "name": "スキルスロット 6", "group": "スキル", "keys": [{"key": KEY_SPACE}]},
	{"id": "potion", "name": "回復薬", "group": "行動", "keys": [{"key": KEY_F}]},
	{"id": "interact", "name": "祭壇・商人・スタッシュを使う", "group": "行動", "keys": [{"key": KEY_B}]},
	{"id": "inventory", "name": "インベントリ", "group": "画面", "keys": [{"key": KEY_I}, {"key": KEY_TAB}]},
	{"id": "skills", "name": "スキルとサポートジェム", "group": "画面", "keys": [{"key": KEY_K}]},
	{"id": "talents", "name": "パッシブツリー", "group": "画面", "keys": [{"key": KEY_T}]},
	{"id": "ascendancy", "name": "アセンダンシー", "group": "画面", "keys": [{"key": KEY_U}]},
	{"id": "status", "name": "ステータス", "group": "画面", "keys": [{"key": KEY_C}]},
	{"id": "filter", "name": "ルートフィルタ", "group": "画面", "keys": [{"key": KEY_L}]},
	{"id": "passives", "name": "遠征パッシブ", "group": "画面", "keys": [{"key": KEY_P}]},
	{"id": "tablets", "name": "石板盤", "group": "画面", "keys": [{"key": KEY_G}]},
	{"id": "map", "name": "マップ（オーバーレイ）", "group": "画面", "keys": [{"key": KEY_M}]},
	{"id": "keyconfig", "name": "キー設定", "group": "画面", "keys": [{"key": KEY_O}]},
]
const MOUSE_NAMES := {MOUSE_BUTTON_LEFT: ["LMB", "左クリック"], MOUSE_BUTTON_RIGHT: ["RMB", "右クリック"],
	MOUSE_BUTTON_MIDDLE: ["MMB", "中クリック"], MOUSE_BUTTON_XBUTTON1: ["MB4", "マウス4"], MOUSE_BUTTON_XBUTTON2: ["MB5", "マウス5"]}
const SHORT_KEYS := {"Space": "SPC", "Tab": "TAB", "Shift": "SHFT", "Ctrl": "CTRL", "Alt": "ALT", "Enter": "ENT", "Backspace": "BS"}

static var binds := {}   # action id -> Array of SLOTS bindings


static func ids() -> Array:
	return ACTIONS.map(func(a): return a.id)


static func action(id: String) -> Dictionary:
	for a in ACTIONS:
		if a.id == id:
			return a
	return {}


static func skill_action(slot: int) -> String:
	return "skill_%d" % (slot + 1)


static func defaults() -> Dictionary:
	var d := {}
	for a in ACTIONS:
		var row: Array = a.keys.duplicate(true)
		row.resize(SLOTS)
		d[a.id] = row.map(func(b): return b if b != null else {})
	return d


static func reset() -> void:
	binds = defaults()
	apply()


## push the bindings into the InputMap (creating the actions on first use)
static func apply() -> void:
	if binds.is_empty():
		binds = defaults()
	for id in ids():
		if not InputMap.has_action(id):
			InputMap.add_action(id)
		InputMap.action_erase_events(id)
		for b in binds[id]:
			var ev := to_event(b)
			if ev:
				InputMap.action_add_event(id, ev)


static func to_event(b: Dictionary) -> InputEvent:
	if b.has("key"):
		var k := InputEventKey.new()
		k.physical_keycode = int(b.key)
		return k
	if b.has("mouse"):
		var m := InputEventMouseButton.new()
		m.button_index = int(b.mouse)
		return m
	return null


## the binding a press would make, or {} for input that can't be bound (Esc, the wheel, motion, releases)
static func from_event(e: InputEvent) -> Dictionary:
	if e is InputEventKey and e.pressed and not e.echo:
		var k: int = e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
		if k == KEY_NONE or k == KEY_ESCAPE:
			return {}
		return {"key": k}
	if e is InputEventMouseButton and e.pressed and MOUSE_NAMES.has(e.button_index):
		return {"mouse": e.button_index}
	return {}


static func same(a: Dictionary, b: Dictionary) -> bool:
	return not a.is_empty() and a.get("key", -1) == b.get("key", -1) and a.get("mouse", -1) == b.get("mouse", -1)


## where else `b` is bound, as [action id, slot], or [] when nowhere
static func find(b: Dictionary, skip_id := "", skip_slot := -1) -> Array:
	for id in ids():
		for i in SLOTS:
			if (id != skip_id or i != skip_slot) and same(binds[id][i], b):
				return [id, i]
	return []


## bind `b` to slot `slot` of `id`. A binding already used elsewhere is swapped: that action gets
## what this slot had before. Returns the action that lost the binding ("" when there was none).
static func assign(id: String, slot: int, b: Dictionary) -> String:
	var old: Dictionary = binds[id][slot]
	var other := [] if b.is_empty() else find(b, id, slot)
	binds[id][slot] = b
	if not other.is_empty():
		binds[other[0]][other[1]] = {} if other[0] == id else old
		# an action holding the same thing twice is just one binding
		if same(binds[other[0]][1 - other[1]], binds[other[0]][other[1]]):
			binds[other[0]][other[1]] = {}
	apply()
	return "" if other.is_empty() else other[0]


## groups of [action id, slot] that share one binding (a hand-edited file can hold these; assign never makes them)
static func conflicts() -> Array:
	var seen := {}
	for id in ids():
		for i in SLOTS:
			var b: Dictionary = binds[id][i]
			if b.is_empty():
				continue
			var k := label_of(b)
			seen[k] = seen.get(k, []) + [[id, i]]
	return seen.values().filter(func(v): return v.size() > 1)


static func conflicted(id: String, slot: int) -> bool:
	return conflicts().any(func(g): return g.has([id, slot]))


static func label_of(b: Dictionary, short := false) -> String:
	if b.has("mouse"):
		return MOUSE_NAMES.get(int(b.mouse), ["M%d" % b.mouse, "マウス%d" % b.mouse])[0 if short else 1]
	if b.has("key"):
		var s := OS.get_keycode_string(int(b.key))
		return SHORT_KEYS.get(s, s.to_upper() if s.length() <= 4 else s.left(4).to_upper()) if short else s
	return ""


## the bindings of an action for text, e.g. "I / Tab" ("未設定" when none)
static func text(id: String) -> String:
	if binds.is_empty():
		apply()
	var parts := PackedStringArray()
	for b in binds[id]:
		if not b.is_empty():
			parts.append(label_of(b))
	return " / ".join(parts) if not parts.is_empty() else "未設定"


## the first binding, short enough for a skill slot corner
static func short(id: String) -> String:
	if binds.is_empty():
		apply()
	for b in binds[id]:
		if not b.is_empty():
			return label_of(b, true)
	return "—"


static func save(path := PATH) -> void:
	var cf := ConfigFile.new()
	cf.load(path)   # keep any other settings already in the file
	for id in ids():
		cf.set_value("keys", id, binds[id])
	cf.save(path)


## read the bindings (unknown or broken entries fall back to the defaults) and apply them
static func load_file(path := PATH) -> void:
	binds = defaults()
	var cf := ConfigFile.new()
	if cf.load(path) == OK:
		for id in ids():
			var row = cf.get_value("keys", id, null)
			if typeof(row) != TYPE_ARRAY or row.size() != SLOTS:
				continue
			binds[id] = Array(row).map(func(b): return _clean(b))
	apply()


static func _clean(b) -> Dictionary:
	if typeof(b) != TYPE_DICTIONARY:
		return {}
	if b.has("key") and int(b.key) not in [KEY_NONE, KEY_ESCAPE]:
		return {"key": int(b.key)}
	if b.has("mouse") and MOUSE_NAMES.has(int(b.mouse)):
		return {"mouse": int(b.mouse)}
	return {}
