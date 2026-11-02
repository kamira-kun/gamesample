class_name Tablets
## Rune tablets (刻碑の石板): flat stone pieces of 1 to 6 cells that bosses drop. A character sets them,
## turned in steps of 90 degrees, into the 6x6 tablet board (36 cells at most); every tablet on the board
## gives its stat lines. A tablet's lines grow with its cell count, and crafting at the board carves
## new lines into it (鍛錬の砥石) or recarves them all (混沌の残光).
## A tablet is a plain Dictionary: {uid, shape, ilvl, mods: {stat: value}, placed, x, y, rot}.

const SIZE := 6
const MAX_OWNED := 40         # tablets kept per character; more break down into ember as they are picked up
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
	return ("無地の" if t.mods.is_empty() else "") + shape(t.shape).name


# =================== making ===================
## a new tablet of item level `ilvl`; bosses drop them with a line half the time, the rest blank to carve
static func generate(ilvl: int, shape_id := "", lines := -1) -> Dictionary:
	_uid += 1
	var t := {"uid": "t%d_%d" % [Time.get_ticks_msec(), _uid], "shape": shape_id if shape_id != "" else SHAPES.pick_random().id,
		"ilvl": ilvl, "mods": {}, "placed": false, "x": 0, "y": 0, "rot": 0}
	add_mods(t, lines if lines >= 0 else (1 if randf() < 0.5 else 0))
	return t


static func roll_value(t: Dictionary, k: String) -> int:
	var v: float = mod_def(k).per * cell_count(t) * (1.0 + t.ilvl * 0.06) * randf_range(0.8, 1.2)
	return maxi(1, roundi(v))


static func add_mods(t: Dictionary, n: int) -> void:
	var pool := MODS.filter(func(m): return not t.mods.has(m.k))
	pool.shuffle()
	for i in mini(n, mini(pool.size(), max_mods(t) - t.mods.size())):
		t.mods[pool[i].k] = roll_value(t, pool[i].k)


## carve with a currency at the board; returns an error message, or "" on success
static func craft(k: String, t: Dictionary) -> String:
	match k:
		"whet":
			if t.mods.size() >= max_mods(t):
				return "この石板にはもう刻めない（最大 %d 行）" % max_mods(t)
			add_mods(t, 1)
		"chaos":
			var n := maxi(1, t.mods.size())
			t.mods = {}
			add_mods(t, n)
		"divine":
			if t.mods.is_empty():
				return "刻まれた能力のある石板にのみ使えます"
			for key in t.mods.keys():
				t.mods[key] = roll_value(t, key)
		_:
			return "このカレンシーは石板に使えません"
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
			return "ほかの石板と重なる"
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
				st[k] = st.get(k, 0) + t.mods[k]
	return st


static func lines(t: Dictionary) -> Array:
	var out := [[name_of(t), COLOR, 17], ["石板（%dマス）　アイテムレベル %d" % [cell_count(t), t.ilvl], Color("#9a9080"), 13]]
	for k in t.mods:
		out.append([Data.affix(k).fmt % t.mods[k], Color("#8fd8ff"), 14])
	if t.mods.size() < max_mods(t):
		out.append(["あと %d 行刻める（鍛錬の砥石）" % (max_mods(t) - t.mods.size()), Color("#7a7266"), 12])
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
		if t.uid == "" or out.any(func(o): return o.uid == t.uid):
			_uid += 1
			t.uid = "t_load_%d" % _uid
		var mods = r.get("mods", {})
		if typeof(mods) == TYPE_DICTIONARY:
			for k in mods:
				if not mod_def(str(k)).is_empty() and t.mods.size() < max_mods(t):
					t.mods[str(k)] = int(mods[k])
		if bool(r.get("placed", false)):
			place(out, t, int(r.get("x", 0)), int(r.get("y", 0)), int(r.get("rot", 0)))
		out.append(t)
	return out.slice(0, MAX_OWNED)
