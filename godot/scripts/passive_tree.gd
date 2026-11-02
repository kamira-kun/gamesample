class_name PassiveTree
## The passive tree: one point per character level after the first, spent on nodes joined to what the character
## already has. Each base class starts from its own point on the inner ring; the web around it leans toward that
## class's play (灰刃 life/armor/attacks, 燼紋 spells/mana/elements, 灯影 crits/speed/minions) and blends into its
## neighbours halfway between. Built in code: two rings of 24 small nodes, twelve spokes of two small nodes and a
## notable, and six keystones past the outer ring.
##
## Positions are in tree units around the centre; angle step i (0..23) is i*15° clockwise from the right.

const STEPS := 24
const R_START := 1.6
const R_INNER := 3.2
const R_SPOKE := [4.4, 5.6]
const R_NOTABLE := 6.8
const R_OUTER := 8.1
const R_KEYSTONE := 9.6

# where each base class starts (angle step), and the colour its part of the tree is drawn in
const SECTORS := {
	"ashblade": {"step": 14, "color": Color("#e0a860")},
	"sigil": {"step": 22, "color": Color("#ff8a5a")},
	"lantern": {"step": 6, "color": Color("#8fd0a0")},
}

# the small nodes of the two rings, cycled through inside each class's part
const RING_SMALLS := {
	"ashblade": [{"name": "生命", "stats": {"life": 15}}, {"name": "鉄皮", "stats": {"armor": 12}},
		{"name": "膂力", "stats": {"atk_dmg": 6}}, {"name": "再生", "stats": {"life_regen": 1}}],
	"sigil": [{"name": "魔力", "stats": {"mana": 12}}, {"name": "呪文", "stats": {"spell_dmg": 6}},
		{"name": "詠唱", "stats": {"cast_spd": 3}}, {"name": "元素", "stats": {"fire_dmg": 4, "cold_dmg": 4, "light_dmg": 4}}],
	"lantern": [{"name": "鋭眼", "stats": {"crit": 1}}, {"name": "疾風", "stats": {"atk_spd": 3}},
		{"name": "軽足", "stats": {"move_spd": 2}}, {"name": "灯霊", "stats": {"ally_dmg": 8}}],
}

# the twelve spokes by angle step: their two small nodes and the notable at the end. Steps 18, 2 and 10 sit
# halfway between two classes and mix them
const SPOKES := {
	12: {"small": {"name": "生命", "stats": {"life": 15}}, "id": "n_blood", "name": "鋼鉄の血潮", "stats": {"life": 35, "life_regen": 2}},
	14: {"small": {"name": "膂力", "stats": {"atk_dmg": 6}}, "id": "n_stance", "name": "灰刃の構え", "stats": {"atk_dmg": 18, "armor": 20}},
	16: {"small": {"name": "鉄皮", "stats": {"armor": 12}}, "id": "n_bastion", "name": "不退の砦", "stats": {"armor": 40, "dr_pct": 4}},
	18: {"small": {"name": "心身", "stats": {"life": 8, "mana": 8}}, "id": "n_will", "name": "燼鉄の意志", "stats": {"life": 25, "mana": 25}},
	20: {"small": {"name": "魔力", "stats": {"mana": 12}}, "id": "n_wellspring", "name": "深き魔泉", "stats": {"mana": 35, "mana_regen": 2}},
	22: {"small": {"name": "呪文", "stats": {"spell_dmg": 6}}, "id": "n_torrent", "name": "燼紋の奔流", "stats": {"spell_dmg": 18, "cast_spd": 6}},
	0: {"small": {"name": "元素", "stats": {"fire_dmg": 4, "cold_dmg": 4, "light_dmg": 4}}, "id": "n_tricolor", "name": "三相の灯火", "stats": {"fire_dmg": 14, "cold_dmg": 14, "light_dmg": 14}},
	2: {"small": {"name": "蝕み", "stats": {"chaos_dmg": 7}}, "id": "n_blight", "name": "蝕む灯", "stats": {"chaos_dmg": 20, "life_on_kill": 4}},
	4: {"small": {"name": "鋭眼", "stats": {"crit": 1}}, "id": "n_foxfire", "name": "狐火の眼差し", "stats": {"crit": 3, "crit_multi": 20}},
	6: {"small": {"name": "疾風", "stats": {"atk_spd": 3}}, "id": "n_shadowstep", "name": "影渡り", "stats": {"move_spd": 6, "atk_spd": 7}},
	8: {"small": {"name": "灯霊", "stats": {"ally_dmg": 8}}, "id": "n_spiritbond", "name": "灯霊の絆", "stats": {"ally_dmg": 22, "ally_life": 20}},
	10: {"small": {"name": "燼気", "stats": {"inc_dmg": 5}}, "id": "n_ashwind", "name": "戦場の灰風", "stats": {"inc_dmg": 12, "life_on_kill": 3}},
}

# keystones: a strong change with a price, one past the outer ring at each class's step and each halfway step
const KEYSTONES := {
	14: {"id": "k_ironheart", "name": "灰鉄の心臓", "stats": {"life_pct": 25, "move_spd": -6}},
	18: {"id": "k_ironchant", "name": "鋼の詠唱", "stats": {"armor": 70, "mana_pct": 10, "cast_spd": -10}},
	22: {"id": "k_starlore", "name": "星灯の叡智", "stats": {"mana_pct": 30, "spell_dmg": 25, "atk_dmg": -20}},
	2: {"id": "k_burnout", "name": "燃え尽きる灯", "stats": {"crit_multi": 45, "life_pct": -15}},
	6: {"id": "k_duskdance", "name": "宵灯の舞踏", "stats": {"atk_spd": 12, "move_spd": 10, "life_pct": -10}},
	10: {"id": "k_ashstorm", "name": "灰嵐の狂奔", "stats": {"inc_dmg": 28, "dr_pct": -10}},
}

# how each stat a node can give reads; {v} is the signed value
const FMT := {
	"life": "最大ライフ {v}", "mana": "最大マナ {v}", "life_pct": "最大ライフ {v}%", "mana_pct": "最大マナ {v}%",
	"life_regen": "ライフ回復 {v}/秒", "mana_regen": "マナ回復 {v}/秒", "armor": "アーマー {v}",
	"inc_dmg": "ダメージ {v}%", "atk_dmg": "攻撃ダメージ {v}%", "spell_dmg": "スペルダメージ {v}%",
	"fire_dmg": "火炎ダメージ {v}%", "cold_dmg": "冷気ダメージ {v}%", "light_dmg": "雷ダメージ {v}%", "chaos_dmg": "混沌ダメージ {v}%",
	"crit": "クリティカル率 {v}%", "crit_multi": "クリティカルダメージ {v}%", "atk_spd": "攻撃速度 {v}%",
	"cast_spd": "詠唱速度 {v}%", "move_spd": "移動速度 {v}%", "ally_dmg": "ミニオン・トーテムのダメージ {v}%",
	"ally_life": "ミニオン・トーテムのライフ {v}%", "life_on_kill": "撃破時ライフ {v}",
	"dr_pct": "受けるダメージ {v}%",   # shown negated: dr_pct 4 is "-4%"
}

static var _nodes := {}     # id -> {id, name, kind, step, pos, stats, links, sector, cls}
static var _order: Array = []


## every node by id, built on first use
static func nodes() -> Dictionary:
	if _nodes.is_empty():
		_build()
	return _nodes


static func node(id: String) -> Dictionary:
	return nodes().get(id, {})


## ids in drawing order (rings first, keystones last)
static func order() -> Array:
	nodes()
	return _order


static func start_id(cls: String) -> String:
	return "s_" + (cls if SECTORS.has(cls) else Data.DEFAULT_CLASS)


## the class whose part of the tree step `i` is in, and how many steps from its start (-4..4)
static func sector_of(i: int) -> Array:
	var best := ""
	var bd := 99
	for k in SECTORS:
		var d := posmod(i - SECTORS[k].step + STEPS / 2, STEPS) - STEPS / 2
		if absi(d) < absi(bd) or (absi(d) == absi(bd) and d < bd):
			best = k
			bd = d
	return [best, bd]


static func _pos(i: int, r: float) -> Vector2:
	return Vector2.from_angle(deg_to_rad(i * 15.0)) * r


static func _add(id: String, name: String, kind: String, i: int, r: float, stats: Dictionary) -> void:
	var sc: Array = sector_of(i)
	_nodes[id] = {"id": id, "name": name, "kind": kind, "step": i, "pos": _pos(i, r), "stats": stats, "links": [], "sector": sc[0]}
	_order.append(id)


static func _link(a: String, b: String) -> void:
	_nodes[a].links.append(b)
	_nodes[b].links.append(a)


## a ring's small node at step i: halfway steps take the mixing spoke's small node, the rest cycle the class's list
static func _ring_small(i: int, ring: int) -> Dictionary:
	var sc: Array = sector_of(i)
	if absi(sc[1]) == 4:
		return SPOKES[i].small
	var l: Array = RING_SMALLS[sc[0]]
	return l[posmod(sc[1] + ring * 2, l.size())]


static func _build() -> void:
	for ring in 2:
		var pre := "a" if ring == 0 else "b"
		for i in STEPS:
			var sm := _ring_small(i, ring)
			_add("%s%d" % [pre, i], sm.name, "small", i, R_INNER if ring == 0 else R_OUTER, sm.stats)
		for i in STEPS:
			_link("%s%d" % [pre, i], "%s%d" % [pre, (i + 1) % STEPS])
	for i in SPOKES:
		var sp: Dictionary = SPOKES[i]
		var prev := "a%d" % i
		for j in R_SPOKE.size():
			var id := "p%d_%d" % [i, j]
			_add(id, sp.small.name, "small", i, R_SPOKE[j], sp.small.stats)
			_link(prev, id)
			prev = id
		_add(sp.id, sp.name, "notable", i, R_NOTABLE, sp.stats)
		_link(prev, sp.id)
		_link(sp.id, "b%d" % i)
	for i in KEYSTONES:
		var ks: Dictionary = KEYSTONES[i]
		_add(ks.id, ks.name, "keystone", i, R_KEYSTONE, ks.stats)
		_link("b%d" % i, ks.id)
	for k in SECTORS:
		var st: int = SECTORS[k].step
		_add(start_id(k), Data.base_class(k).name + "の起点", "start", st, R_START, {})
		_nodes[start_id(k)].cls = k
		for d in [-1, 0, 1]:
			_link(start_id(k), "a%d" % posmod(st + d, STEPS))


# ---- allocation ----
## a node that can never be taken: another class's start
static func _blocked(id: String, cls: String) -> bool:
	return node(id).kind == "start" and id != start_id(cls)


## the fewest new nodes that join `id` to what `tree` (allocated ids) already holds, ending with `id`;
## [] if it is taken already or cannot be reached
static func path_to(tree: Array, cls: String, id: String) -> Array:
	if node(id).is_empty() or id in tree or _blocked(id, cls) or id == start_id(cls):
		return []
	var came := {}
	var queue: Array = [start_id(cls)]
	for t in tree:
		queue.append(t)
	for q in queue:
		came[q] = ""
	var head := 0
	while head < queue.size():
		var cur: String = queue[head]
		head += 1
		for nb in node(cur).links:
			if came.has(nb) or _blocked(nb, cls):
				continue
			came[nb] = cur
			if nb == id:
				var path := [id]
				var back: String = cur
				while not (back in tree or back == start_id(cls)):
					path.push_front(back)
					back = came[back]
				return path
			queue.append(nb)
	return []


## the allocated nodes still joined to the class's start through allocated nodes
static func connected(tree: Array, cls: String) -> Array:
	var seen := {start_id(cls): true}
	var queue: Array = [start_id(cls)]
	var head := 0
	while head < queue.size():
		for nb in node(queue[head]).links:
			if not seen.has(nb) and nb in tree:
				seen[nb] = true
				queue.append(nb)
		head += 1
	return tree.filter(func(t): return seen.has(t))


## an allocated node can go back if everything else stays joined to the start without it
static func can_refund(tree: Array, cls: String, id: String) -> bool:
	if not id in tree:
		return false
	var rest := tree.filter(func(t): return t != id)
	return connected(rest, cls).size() == rest.size()


## a saved tree made safe: known nodes only, no duplicates or other classes' starts, joined to the start,
## and no more than `points` of them (the farthest from the start go first)
static func sanitize(raw, cls: String, points: int) -> Array:
	var t: Array = []
	if typeof(raw) == TYPE_ARRAY:
		for x in raw:
			var id := str(x)
			if nodes().has(id) and node(id).kind != "start" and not id in t:
				t.append(id)
	t = connected(t, cls)
	while t.size() > points:
		var drop := ""
		for id in t:
			if can_refund(t, cls, id) and (drop == "" or node(id).pos.length() > node(drop).pos.length()):
				drop = id
		t.erase(drop)
	return t


## the stats the allocated nodes add up to
static func stats(tree: Array) -> Dictionary:
	var st := {}
	for id in tree:
		var n := node(id)
		for k in n.get("stats", {}):
			st[k] = st.get(k, 0) + n.stats[k]
	return st


## readable lines for a stat dictionary, in FMT's order
static func lines(st: Dictionary) -> Array:
	var out: Array = []
	for k in FMT:
		if st.has(k) and st[k] != 0:
			var v: float = -st[k] if k == "dr_pct" else st[k]
			var num := ("%.1f" % absf(v)).trim_suffix(".0")
			out.append(FMT[k].replace("{v}", ("+" if v > 0 else "-") + num))
	return out
