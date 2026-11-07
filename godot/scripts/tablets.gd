class_name Tablets
## Rune tablets (ルーンタブレット): flat stone pieces of 1 to 6 cells that bosses drop. A character sets them,
## turned in steps of 90 degrees, into the 6x6 tablet board (36 cells at most); every tablet on the board
## gives its stat lines. A tablet's lines grow with its cell count, and crafting at the board carves
## new lines into it (鍛錬の砥石) or recarves them all (混沌の残光).
## A tablet is a plain Dictionary: {uid, shape, ilvl, mods: {stat: value}, placed, x, y, rot}.
## A unique one (#77, UNIQUES) also has `unique`, its name: fixed lines from the table that nothing can carve and an
## `effect` that works while it is on the board. They only drop or come from the exchange, and are remade from the table on loading.

const SIZE := 6
const MAX_OWNED := 40         # plain tablets kept per character; more break down into ember as they are picked up. Uniques don't count: they come on top
const UNIQUE_CHANCE := 0.05   # of the tablets bosses drop
const COLOR := Color("#9ad8e8")

# the shapes, as cells of the unturned piece
const SHAPES := [
	{"id": "mono", "name": "礎の小碑", "cells": [[0, 0]]},
	{"id": "pair", "name": "双子碑", "cells": [[0, 0], [1, 0]]},
	{"id": "line3", "name": "三連碑", "cells": [[0, 0], [1, 0], [2, 0]]},
	{"id": "bend3", "name": "曲がり碑", "cells": [[0, 0], [1, 0], [0, 1]]},
	{"id": "line4", "name": "柱碑", "cells": [[0, 0], [1, 0], [2, 0], [3, 0]]},
	{"id": "square4", "name": "方碑", "cells": [[0, 0], [1, 0], [0, 1], [1, 1]]},
	{"id": "hook4", "name": "鉤碑", "cells": [[0, 0], [0, 1], [0, 2], [1, 2]]},
	{"id": "tee4", "name": "楔碑", "cells": [[0, 0], [1, 0], [2, 0], [1, 1]]},
	{"id": "step4", "name": "段碑", "cells": [[1, 0], [2, 0], [0, 1], [1, 1]]},
	{"id": "cross5", "name": "十字碑", "cells": [[1, 0], [0, 1], [1, 1], [2, 1], [1, 2]]},
	{"id": "hook5", "name": "大鉤碑", "cells": [[0, 0], [0, 1], [0, 2], [0, 3], [1, 3]]},
	{"id": "flag5", "name": "旗碑", "cells": [[0, 0], [1, 0], [0, 1], [1, 1], [0, 2]]},
	{"id": "slab6", "name": "大石碑", "cells": [[0, 0], [1, 0], [2, 0], [0, 1], [1, 1], [2, 1]]},
	{"id": "gate6", "name": "門碑", "cells": [[0, 0], [2, 0], [0, 1], [1, 1], [2, 1], [1, 2]]},
]

# what a tablet's lines can be: `per` is the value each cell adds at item level 0
const MODS := [
	{"k": "life", "per": 5.0},
	{"k": "mana", "per": 4.0},
	{"k": "inc_dmg", "per": 2.0},
	{"k": "spell_dmg", "per": 2.5},
	{"k": "atk_spd", "per": 1.0},
	{"k": "cast_spd", "per": 1.0},
	{"k": "armor", "per": 4.0},
	{"k": "fire_dmg", "per": 2.5},
	{"k": "cold_dmg", "per": 2.5},
	{"k": "light_dmg", "per": 2.5},
	{"k": "crit_multi", "per": 3.0},
	{"k": "life_regen", "per": 0.5},
	{"k": "move_spd", "per": 0.8},
]

# the unique tablets: `tier` is their standing among buyers (Data.UNIQUE_TIERS), `mods` their fixed lines
const UNIQUES := [
	{"name": "不屈の礎", "shape": "square4", "tier": 3, "mods": {"life_pct": 12, "armor": 80}, "flavor": "幾度崩されても、ここから積み直した。"},
	{"name": "三界の柱", "shape": "line4", "tier": 3, "mods": {"fire_dmg": 30, "cold_dmg": 30, "light_dmg": 30}, "flavor": "火と氷と雷が、一本の柱に同居している。"},
	{"name": "灯火の門", "shape": "gate6", "tier": 3, "mods": {"ally_dmg": 45, "ally_life": 30}, "flavor": "門の向こうから、灯の列が絶えず歩いてくる。"},
	{"name": "嵐喰らいの楔", "shape": "tee4", "tier": 3, "effect": "crit_mana", "desc": "クリティカル時にマナを4回復する",
		"mods": {"atk_spd": 10, "cast_spd": 10, "crit_multi": 25}, "flavor": "打ち込まれた嵐は、まだ楔の中で唸っている。"},
]

static var _uid := 0


static func shape(id: String) -> Dictionary:
	for s in SHAPES:
		if s.id == id:
			return s
	return {}


static func mod_def(k: String) -> Dictionary:
	for m in MODS:
		if m.k == k:
			return m
	return {}


static func cell_count(t: Dictionary) -> int:
	return shape(t.shape).cells.size()


## how many lines a tablet can carry: 1 for one cell, up to 3 for five or six
static func max_mods(t: Dictionary) -> int:
	return clampi(ceili(cell_count(t) / 2.0), 1, 3)


static func name_of(t: Dictionary) -> String:
	if is_unique(t):
		return t.unique
	return ("無地の" if t.mods.is_empty() else "") + shape(t.shape).name


static func is_unique(t: Dictionary) -> bool:
	return t.has("unique")


## a unique of the table by name ({} if there is none)
static func unique_def(name: String) -> Dictionary:
	for u in UNIQUES:
		if u.name == name:
			return u
	return {}


## the color a tablet shows in: a unique one's is the unique rarity's
static func color_of(t: Dictionary) -> Color:
	return Data.RARITY[3].color if is_unique(t) else COLOR


# =================== making ===================
## a new tablet of item level `ilvl`; bosses drop them with a line half the time, the rest blank to carve
static func generate(ilvl: int, shape_id := "", lines := -1) -> Dictionary:
	_uid += 1
	var t := {"uid": "t%d_%d" % [Time.get_ticks_msec(), _uid], "shape": shape_id if shape_id != "" else SHAPES.pick_random().id,
		"ilvl": ilvl, "mods": {}, "placed": false, "x": 0, "y": 0, "rot": 0}
	add_mods(t, lines if lines >= 0 else (1 if randf() < 0.5 else 0))
	return t


## a new unique tablet from the table
static func generate_unique(name: String, ilvl: int) -> Dictionary:
	var u := unique_def(name)
	_uid += 1
	return {"uid": "t%d_%d" % [Time.get_ticks_msec(), _uid], "unique": u.name, "shape": u.shape, "ilvl": ilvl, "mods": u.mods.duplicate(),
		"placed": false, "x": 0, "y": 0, "rot": 0}


## what a boss drops: now and then a unique, else a rolled one
static func drop(ilvl: int, chance := UNIQUE_CHANCE) -> Dictionary:
	return generate_unique(UNIQUES.pick_random().name, ilvl) if randf() < chance else generate(ilvl)


static func roll_value(t: Dictionary, k: String) -> int:
	return value_at(t, k, randf_range(0.8, 1.2))


## the line's value with its random factor at `f` (0.8..1.2); ModRange reads the range from it
static func value_at(t: Dictionary, k: String, f: float) -> int:
	return maxi(1, roundi(mod_def(k).per * cell_count(t) * (1.0 + t.ilvl * 0.06) * f))


static func add_mods(t: Dictionary, n: int) -> void:
	var pool := MODS.filter(func(m): return not t.mods.has(m.k))
	pool.shuffle()
	for i in mini(n, mini(pool.size(), max_mods(t) - t.mods.size())):
		t.mods[pool[i].k] = roll_value(t, pool[i].k)


## carve with a currency at the board; returns an error message, or "" on success
static func craft(k: String, t: Dictionary) -> String:
	if is_unique(t):
		return "ユニークのルーンタブレットには使えません"
	match k:
		"whet":
			if t.mods.size() >= max_mods(t):
				return "このルーンタブレットにはもう刻めない（最大 %d 行）" % max_mods(t)
			add_mods(t, 1)
		"chaos":
			var n := maxi(1, t.mods.size())
			t.mods = {}
			add_mods(t, n)
		"divine":
			if t.mods.is_empty():
				return "刻まれた能力のあるルーンタブレットにのみ使えます"
			for key in t.mods.keys():
				t.mods[key] = roll_value(t, key)
		_:
			return "このカレンシーはルーンタブレットに使えません"
	return ""


## what breaking a tablet down pays in ember shards
static func shard_value(t: Dictionary) -> int:
	return (4 + t.ilvl * 2) * cell_count(t) + t.mods.size() * 10


# =================== the board ===================
## the cells a tablet covers turned `rot` quarter turns clockwise, moved so the top-left one is at 0,0
static func turned(shape_id: String, rot: int) -> Array:
	var cells: Array = shape(shape_id).cells.map(func(c): return Vector2i(c[0], c[1]))
	for i in posmod(rot, 4):
		cells = cells.map(func(c): return Vector2i(-c.y, c.x))
	var lo := Vector2i(cells.map(func(c): return c.x).min(), cells.map(func(c): return c.y).min())
	return cells.map(func(c): return c - lo)


## the board cells of tablet `t` if it sat at x, y with turn `rot`
static func cells_at(t: Dictionary, x: int, y: int, rot: int) -> Array:
	return turned(t.shape, rot).map(func(c): return c + Vector2i(x, y))


## board cell -> uid of the placed tablet on it
static func occupancy(list: Array) -> Dictionary:
	var occ := {}
	for t in list:
		if t.placed:
			for c in cells_at(t, t.x, t.y, t.rot):
				occ[c] = t.uid
	return occ


## "" when tablet `t` fits at x, y turned `rot` (it may cover its own old spot), else why not
static func fit(list: Array, t: Dictionary, x: int, y: int, rot: int) -> String:
	var occ := occupancy(list)
	for c in cells_at(t, x, y, rot):
		if c.x < 0 or c.y < 0 or c.x >= SIZE or c.y >= SIZE:
			return "盤からはみ出す"
		if occ.has(c) and occ[c] != t.uid:
			return "ほかのルーンタブレットと重なる"
	return ""


static func place(list: Array, t: Dictionary, x: int, y: int, rot: int) -> String:
	var err := fit(list, t, x, y, rot)
	if err != "":
		return err
	t.placed = true
	t.x = x
	t.y = y
	t.rot = posmod(rot, 4)
	return ""


static func used_cells(list: Array) -> int:
	return occupancy(list).size()


## the stats of every tablet on the board
static func stats(list: Array) -> Dictionary:
	var st := {}
	for t in list:
		if t.placed:
			for k in t.mods:
				Data.add_stat(st, k, t.mods[k])
	return st


## the names of the unique tablets on the board
static func unique_names(list: Array) -> Array:
	return list.filter(func(t): return t.placed and is_unique(t)).map(func(t): return t.unique)


## the effect keys the unique tablets on the board grant (Player.effects)
static func effects(list: Array) -> Array:
	return unique_names(list).map(func(n): return unique_def(n).get("effect", "")).filter(func(k): return k != "")


static func lines(t: Dictionary) -> Array:
	var out := [[name_of(t), color_of(t), 17]]
	var u := unique_def(t.get("unique", ""))
	if not u.is_empty():
		var tier: Dictionary = Data.UNIQUE_TIERS[u.tier]
		out.append(["希少度：%s" % tier.name, tier.color, 13])
	out.append(["%sルーンタブレット（%dマス）　アイテムレベル %d" % ["レジェンド " if is_unique(t) else "", cell_count(t), t.ilvl], Color("#9a9080"), 13])
	for k in t.mods:
		out.append(ModRange.line(Data.affix(k).fmt % t.mods[k], Color("#8fd8ff"), 14, ModRange.tablet(t, k)))
	if t.mods.size() < max_mods(t) and not is_unique(t):
		out.append(["あと %d 行刻める（鍛錬の砥石）" % (max_mods(t) - t.mods.size()), Color("#7a7266"), 12])
	if u.has("desc"):
		out.append([u.desc, Color("#ff9a4a"), 14])
	if not u.is_empty():
		out.append_array(Data.combo_lines(t.unique))
		out.append([u.flavor, Color("#a08a6a"), 12])
	out.append(["盤に置いている" if t.placed else "盤に置いていない", Color("#b8a888"), 12])
	return out


## JSON turns numbers into floats, and a hand-edited file may hold anything: keep the tablets that make sense,
## and take off the board any that no longer fit where they were
static func normalize(raw) -> Array:
	var out := []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for r in raw:
		if typeof(r) != TYPE_DICTIONARY or shape(str(r.get("shape", ""))).is_empty():
			continue
		var t := {"uid": str(r.get("uid", "")), "shape": str(r.shape), "ilvl": maxi(1, int(r.get("ilvl", 1))), "mods": {},
			"placed": false, "x": 0, "y": 0, "rot": 0}
		# a unique comes back from the table; one the table no longer has stays as a plain tablet
		if not unique_def(str(r.get("unique", ""))).is_empty():
			var keep: String = t.uid
			t = generate_unique(str(r.unique), t.ilvl)
			t.uid = keep
		if t.uid == "" or out.any(func(o): return o.uid == t.uid):
			_uid += 1
			t.uid = "t_load_%d" % _uid
		var mods = r.get("mods", {}) if not is_unique(t) else {}
		if typeof(mods) == TYPE_DICTIONARY:
			for k in mods:
				if not mod_def(str(k)).is_empty() and t.mods.size() < max_mods(t):
					t.mods[str(k)] = int(mods[k])
		if bool(r.get("placed", false)):
			place(out, t, int(r.get("x", 0)), int(r.get("y", 0)), int(r.get("rot", 0)))
		out.append(t)
	return Jewels.keep_owned(out, MAX_OWNED, is_unique)


## how many of `list` count against MAX_OWNED
static func plain_count(list: Array) -> int:
	return list.filter(func(x): return not is_unique(x)).size()


## true when `list` has no room for `t` (it always has for a unique)
static func is_full(list: Array, t: Dictionary) -> bool:
	return not is_unique(t) and plain_count(list) >= MAX_OWNED
