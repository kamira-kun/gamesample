class_name PassiveTree
## The passive tree: one point per character level after the first, spent on nodes joined to what the character
## already has. Exactly TOTAL nodes, generated from a fixed seed so every run (and every save) sees the same web:
##
## - the three base classes start near the centre, on a hub ring of HUB_N small nodes;
## - LAYERS rings of clusters spread outward. A cluster is a ring of small nodes around a notable (or a jewel socket,
##   or nothing), joined to its neighbours on the same layer and to the nearest cluster one layer in by short bridges;
## - past the last layer, OUTER_SLOTS keystones and large ring sockets (環晶の大台座) close the web.
##
## The circle is split into six zones of 60°: each class's own zone and the three halfway zones that mix two classes
## (灰刃 life/armor/attacks, 燼紋 spells/mana/elements, 灯影 crits/speed/minions). A node's stats come from its zone.
##
## Ring jewels (環晶, see Jewels) socketed in a large socket add their own small ring of nodes past it while they sit
## there (set_rings); those nodes join `nodes()` like the rest and are taken and refunded the same way.
##
## Positions are in tree units around the centre; angles are in degrees clockwise from the right.

const TOTAL := 2000
const SEED := 43043
const R_START := 2.0
const R_HUB := 4.6
const HUB_N := 24
const LAYERS := 7
const LAYER_GAP := 5.4
const CLUSTER_ARC := 6.6      # the space a cluster takes along its layer
const RHO := 1.5              # a cluster ring's radius
const STEP := 1.25            # bridge node spacing
const OUTER_SLOTS := 30
const R_OUTER := R_HUB + LAYER_GAP * LAYERS + 5.0
const RING_OUT := 3.6         # how far past its large socket a ring jewel's ring sits

# where each base class starts (angle), and the colour its part of the tree is drawn in
const SECTORS := {
	"ashblade": {"ang": 210, "color": Color("#e0a860")},
	"sigil": {"ang": 330, "color": Color("#ff8a5a")},
	"lantern": {"ang": 90, "color": Color("#8fd0a0")},
}

# the six zones by floor(angle / 60): their small nodes, the stats (and base values) notables draw two of,
# and the words notable names start with
const ZONES := [
	{"name": "燼紋・灯影の間", "smalls": [{"name": "蝕み", "stats": {"chaos_dmg": 7}}, {"name": "鋭眼", "stats": {"crit": 1}},
		{"name": "元素", "stats": {"fire_dmg": 4, "cold_dmg": 4, "light_dmg": 4}}],
		"notable": {"chaos_dmg": 16, "crit": 2, "crit_multi": 15, "life_on_kill": 3, "inc_dmg": 10},
		"words": ["蝕む", "腐灯", "黒狐", "宵闇", "毒霧", "朽葉", "星蝕", "夜鴉"]},
	{"name": "灯影寄り", "smalls": [{"name": "鋭眼", "stats": {"crit": 1}}, {"name": "疾風", "stats": {"atk_spd": 3}},
		{"name": "軽足", "stats": {"move_spd": 2}}, {"name": "灯霊", "stats": {"ally_dmg": 8}}],
		"notable": {"crit": 2, "atk_spd": 6, "move_spd": 5, "ally_dmg": 18, "ally_life": 15, "crit_multi": 15},
		"words": ["狐火", "影渡り", "灯籠", "月下", "疾駆", "鬼灯", "朧", "灯霊"]},
	{"name": "灯影・灰刃の間", "smalls": [{"name": "燼気", "stats": {"inc_dmg": 5}}, {"name": "生命", "stats": {"life": 15}},
		{"name": "疾風", "stats": {"atk_spd": 3}}],
		"notable": {"inc_dmg": 12, "life_on_kill": 3, "atk_spd": 5, "life": 25, "crit_multi": 12},
		"words": ["灰風", "戦塵", "血煙", "荒野", "狩人", "野火", "鬨声", "落日"]},
	{"name": "灰刃寄り", "smalls": [{"name": "生命", "stats": {"life": 15}}, {"name": "鉄皮", "stats": {"armor": 12}},
		{"name": "膂力", "stats": {"atk_dmg": 6}}, {"name": "再生", "stats": {"life_regen": 1}}],
		"notable": {"life": 30, "armor": 35, "atk_dmg": 15, "life_regen": 2, "dr_pct": 3},
		"words": ["鋼鉄", "灰刃", "不退", "岩肌", "鉄壁", "剛腕", "古傷", "黒鉄"]},
	{"name": "灰刃・燼紋の間", "smalls": [{"name": "心身", "stats": {"life": 8, "mana": 8}}, {"name": "鉄皮", "stats": {"armor": 12}},
		{"name": "魔力", "stats": {"mana": 12}}],
		"notable": {"life": 22, "mana": 22, "armor": 25, "mana_regen": 2, "life_regen": 1.5},
		"words": ["燼鉄", "誓約", "錬磨", "修験", "封印", "鎮魂", "篝火", "祈祷"]},
	{"name": "燼紋寄り", "smalls": [{"name": "魔力", "stats": {"mana": 12}}, {"name": "呪文", "stats": {"spell_dmg": 6}},
		{"name": "詠唱", "stats": {"cast_spd": 3}}, {"name": "元素", "stats": {"fire_dmg": 4, "cold_dmg": 4, "light_dmg": 4}}],
		"notable": {"mana": 28, "spell_dmg": 15, "cast_spd": 5, "fire_dmg": 12, "cold_dmg": 12, "light_dmg": 12, "mana_regen": 2},
		"words": ["燼紋", "魔泉", "星灯", "焔環", "霜華", "雷紋", "三相", "深淵"]},
]
const NOTABLE_ENDS := ["の血潮", "の構え", "の砦", "の意志", "の奔流", "の眼差し", "の絆", "の舞", "の誓い", "の加護", "の極意",
	"の刻印", "の鼓動", "の灯", "の残響", "の律動", "の秘儀", "の境地", "の牙", "の守り", "の息吹", "の導き", "の器", "の焔"]

# keystones: a big change with a big price, four in each zone's stretch of the outer band (in angle order)
const KEYSTONES := [
	{"id": "k_burnout", "name": "燃え尽きる灯", "stats": {"crit_multi": 80, "life_pct": -25}},
	{"id": "k_blightheart", "name": "蝕心", "stats": {"chaos_dmg": 60, "life_pct": -15}},
	{"id": "k_glassstar", "name": "玻璃の星", "stats": {"crit": 8, "crit_multi": 40, "dr_pct": -15}},
	{"id": "k_venomtide", "name": "毒潮の誓い", "stats": {"chaos_dmg": 45, "inc_dmg": 20, "mana_pct": -30}},
	{"id": "k_duskdance", "name": "宵灯の舞踏", "stats": {"atk_spd": 22, "move_spd": 15, "life_pct": -20}},
	{"id": "k_foxpact", "name": "狐火の契り", "stats": {"crit": 10, "inc_dmg": -25}},
	{"id": "k_lanternhost", "name": "百灯の行列", "stats": {"ally_dmg": 60, "ally_life": 40, "atk_dmg": -30, "spell_dmg": -30}},
	{"id": "k_windwalker", "name": "風渡り", "stats": {"move_spd": 25, "dr_pct": -12}},
	{"id": "k_ashstorm", "name": "灰嵐の狂奔", "stats": {"inc_dmg": 45, "dr_pct": -18}},
	{"id": "k_carrion", "name": "屍喰らい", "stats": {"life_on_kill": 15, "life_pct": -15}},
	{"id": "k_warcry", "name": "戦鬨", "stats": {"inc_dmg": 30, "atk_spd": 10, "mana_pct": -40}},
	{"id": "k_lastember", "name": "最後の残り火", "stats": {"inc_dmg": 25, "crit_multi": 30, "life_pct": -20}},
	{"id": "k_ironheart", "name": "灰鉄の心臓", "stats": {"life_pct": 40, "move_spd": -12}},
	{"id": "k_bulwark", "name": "不落の城", "stats": {"armor": 200, "dr_pct": 10, "atk_spd": -15}},
	{"id": "k_berserk", "name": "鬼哭の刃", "stats": {"atk_dmg": 50, "dr_pct": -15}},
	{"id": "k_stoneblood", "name": "岩血", "stats": {"life_regen": 12, "life_pct": 15, "spell_dmg": -40}},
	{"id": "k_ironchant", "name": "鋼の詠唱", "stats": {"armor": 120, "mana_pct": 20, "cast_spd": -18}},
	{"id": "k_twinwick", "name": "二重の灯心", "stats": {"life_pct": 20, "mana_pct": 20, "inc_dmg": -20}},
	{"id": "k_bloodmana", "name": "血と魔の天秤", "stats": {"mana_pct": 50, "life_pct": -25}},
	{"id": "k_steadfast", "name": "不動心", "stats": {"dr_pct": 12, "move_spd": -15}},
	{"id": "k_starlore", "name": "星灯の叡智", "stats": {"mana_pct": 50, "spell_dmg": 45, "atk_dmg": -40}},
	{"id": "k_cinderveil", "name": "燼の帳", "stats": {"fire_dmg": 50, "cold_dmg": -30, "light_dmg": -30}},
	{"id": "k_triad", "name": "三相の極み", "stats": {"fire_dmg": 30, "cold_dmg": 30, "light_dmg": 30, "crit": -4}},
	{"id": "k_quickchant", "name": "早口の呪", "stats": {"cast_spd": 25, "mana_pct": -35}},
]

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

const KIND_NAMES := {"small": "", "notable": "注目ノード", "keystone": "キーストーン", "start": "起点",
	"socket": "燈晶の台座", "ring_socket": "環晶の大台座"}

static var _nodes := {}     # id -> {id, name, kind, ang, pos, stats, links, sector, zone, layer}
static var _order: Array = []
static var _base := 0       # how many nodes the fixed web has (the rest come from socketed ring jewels)
static var _ext: Array = [] # ids added by ring jewels, in order
static var _ring_key := ""  # what set_rings last built, to skip rebuilding the same rings


## every node by id (ring jewel nodes included), built on first use
static func nodes() -> Dictionary:
	if _nodes.is_empty():
		_build()
	return _nodes


static func node(id: String) -> Dictionary:
	return nodes().get(id, {})


## ids in drawing order (the fixed web first, ring jewel nodes last)
static func order() -> Array:
	nodes()
	return _order


## how many nodes the fixed web has, without ring jewels
static func base_count() -> int:
	nodes()
	return _base


static func start_id(cls: String) -> String:
	return "s_" + (cls if SECTORS.has(cls) else Data.DEFAULT_CLASS)


## the zone (0..5) an angle is in
static func zone_of(ang: float) -> int:
	return floori(fposmod(ang, 360.0) / 60.0) % 6


## the class whose start is nearest an angle (its colour colours the node)
static func sector_of(ang: float) -> String:
	var best := ""
	var bd := 999.0
	for k in SECTORS:
		var d := absf(angle_difference(deg_to_rad(ang), deg_to_rad(SECTORS[k].ang)))
		if d < bd - 0.0001:
			best = k
			bd = d
	return best


static func _ang(p: Vector2) -> float:
	return fposmod(rad_to_deg(p.angle()), 360.0)


static func _add(id: String, name: String, kind: String, pos: Vector2, stats: Dictionary, layer: int) -> void:
	var a := _ang(pos)
	_nodes[id] = {"id": id, "name": name, "kind": kind, "ang": a, "pos": pos, "stats": stats, "links": [],
		"sector": sector_of(a), "zone": zone_of(a), "layer": layer}
	_order.append(id)


static func _link(a: String, b: String) -> void:
	if b in _nodes[a].links:
		return
	_nodes[a].links.append(b)
	_nodes[b].links.append(a)


# ---- building ----
## the layout before nodes: each cluster's layer, place, ring size, centre kind and ring turn. Ring sizes are the
## knob that makes the total come out at exactly TOTAL (bridges depend only on cluster centres)
static func _plan(rng: RandomNumberGenerator) -> Array:
	var plan := []
	for k in range(1, LAYERS + 1):
		var r := R_HUB + LAYER_GAP * k
		var n := floori(TAU * r / CLUSTER_ARC)
		var off := rng.randf() * TAU / n
		for c in n:
			var a := off + TAU * c / n
			var centre := "notable"
			if k >= 2 and c % 7 == 3:
				centre = "socket"
			elif rng.randf() < 0.18:
				centre = ""
			plan.append({"k": k, "c": c, "pos": Vector2.from_angle(a) * r, "n": rng.randi_range(6, 8), "centre": centre,
				"rot": rng.randf() * TAU, "small": rng.randi(), "stats": rng.randi()})
	return plan


static func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var plan := _plan(rng)
	_make(plan)
	# nudge ring sizes, spread around the web, until the count is exact
	var diff := TOTAL - _nodes.size()
	var i := 0
	while diff != 0 and i < plan.size() * 4:
		var cl: Dictionary = plan[(i * 37) % plan.size()]
		var want: int = cl.n + signi(diff)
		if want >= 5 and want <= 9:
			cl.n = want
			diff -= signi(diff)
		i += 1
	_make(plan)
	_base = _nodes.size()
	assert(_base == TOTAL, "passive tree has %d nodes" % _base)


## the ring node of a cluster that faces point `to`
static func _facing(cl: Dictionary, to: Vector2) -> String:
	var want: float = (to - cl.pos).angle()
	var best := 0
	var bd := 99.0
	for j in cl.n:
		var d := absf(angle_difference(cl.rot + TAU * j / cl.n, want))
		if d < bd:
			bd = d
			best = j
	return "c%d_%d_%d" % [cl.k, cl.c, best]


## small nodes in a straight line from `a` to `b`, `count` of them; the zone's smalls take turns
static func _bridge(prefix: String, a: String, b: String, count: int) -> void:
	var pa: Vector2 = _nodes[a].pos
	var pb: Vector2 = _nodes[b].pos
	var prev := a
	for j in count:
		var p := pa.lerp(pb, (j + 1.0) / (count + 1.0))
		var z: Dictionary = ZONES[zone_of(_ang(p))]
		var sm: Dictionary = z.smalls[posmod(j + prefix.hash(), z.smalls.size())]
		var id := "%s_%d" % [prefix, j]
		_add(id, sm.name, "small", p, sm.stats, 0)
		_link(prev, id)
		prev = id
	_link(prev, b)


static func _gap_count(gap: float) -> int:
	return maxi(0, floori(gap / STEP))


static func _make(plan: Array) -> void:
	_nodes = {}
	_order = []
	_ext = []
	_ring_key = ""
	var names := _notable_names()
	var used_names := {}
	# the hub and the starts
	for i in HUB_N:
		var p := Vector2.from_angle(TAU * i / HUB_N) * R_HUB
		var sm: Dictionary = ZONES[zone_of(_ang(p))].smalls[i % 2]
		_add("h%d" % i, sm.name, "small", p, sm.stats, 0)
	for i in HUB_N:
		_link("h%d" % i, "h%d" % ((i + 1) % HUB_N))
	for k in SECTORS:
		var a: float = SECTORS[k].ang
		_add(start_id(k), Data.base_class(k).name + "の起点", "start", Vector2.from_angle(deg_to_rad(a)) * R_START, {}, 0)
		_nodes[start_id(k)].cls = k
		var near := range(HUB_N)
		near.sort_custom(func(x, y): return _nodes["h%d" % x].pos.distance_to(_nodes[start_id(k)].pos) < _nodes["h%d" % y].pos.distance_to(_nodes[start_id(k)].pos))
		for h in near.slice(0, 3):
			_link(start_id(k), "h%d" % h)
	# clusters
	var by_layer := {}
	for cl in plan:
		if not by_layer.has(cl.k):
			by_layer[cl.k] = []
		by_layer[cl.k].append(cl)
		var z: int = zone_of(_ang(cl.pos))
		var zd: Dictionary = ZONES[z]
		var sm: Dictionary = zd.smalls[cl.small % zd.smalls.size()]
		for j in cl.n:
			_add("c%d_%d_%d" % [cl.k, cl.c, j], sm.name, "small", cl.pos + Vector2.from_angle(cl.rot + TAU * j / cl.n) * RHO, sm.stats, cl.k)
		for j in cl.n:
			_link("c%d_%d_%d" % [cl.k, cl.c, j], "c%d_%d_%d" % [cl.k, cl.c, (j + 1) % cl.n])
		var cid := "c%d_%d" % [cl.k, cl.c]
		if cl.centre == "notable":
			var nm: String = names[z].pop_back()
			while used_names.has(nm):
				nm = names[z].pop_back()
			used_names[nm] = true
			_add(cid, nm, "notable", cl.pos, _notable_stats(z, cl.k, cl.stats), cl.k)
		elif cl.centre == "socket":
			_add(cid, KIND_NAMES.socket, "socket", cl.pos, {}, cl.k)
		if cl.centre != "":
			_link(cid, "c%d_%d_0" % [cl.k, cl.c])
			_link(cid, "c%d_%d_%d" % [cl.k, cl.c, cl.n / 2])
	# bridges: along each layer, and one inward from every cluster
	for k in by_layer:
		var row: Array = by_layer[k]
		for i in row.size():
			var a: Dictionary = row[i]
			var b: Dictionary = row[(i + 1) % row.size()]
			_bridge("b%d_%d" % [k, i], _facing(a, b.pos), _facing(b, a.pos), _gap_count(a.pos.distance_to(b.pos) - RHO * 2.0))
			var into := ""
			var gap := 0.0
			if k == 1:
				var h := posmod(roundi(_ang(a.pos) / 360.0 * HUB_N), HUB_N)
				into = "h%d" % h
				gap = a.pos.distance_to(_nodes[into].pos) - RHO
			else:
				var par: Dictionary = by_layer[k - 1][0]
				for q in by_layer[k - 1]:
					if absf(angle_difference(q.pos.angle(), a.pos.angle())) < absf(angle_difference(par.pos.angle(), a.pos.angle())):
						par = q
				into = _facing(par, a.pos)
				gap = a.pos.distance_to(par.pos) - RHO * 2.0
			_bridge("i%d_%d" % [k, i], _facing(a, Vector2.ZERO if k == 1 else _nodes[into].pos), into, _gap_count(gap))
	# the outer band: keystones, and a large ring socket at the middle of each zone's stretch
	var outer: Array = by_layer[LAYERS]
	var ks := 0
	for i in OUTER_SLOTS:
		var a := deg_to_rad(i * 360.0 / OUTER_SLOTS + 360.0 / OUTER_SLOTS / 2.0)
		var p := Vector2.from_angle(a) * R_OUTER
		var id := ""
		if i % 5 == 2:
			id = "R%d" % (i / 5)
			_add(id, KIND_NAMES.ring_socket, "ring_socket", p, {}, LAYERS + 1)
		else:
			var kd: Dictionary = KEYSTONES[ks]
			ks += 1
			id = kd.id
			_add(id, kd.name, "keystone", p, kd.stats, LAYERS + 1)
		var near: Dictionary = outer[0]
		for q in outer:
			if q.pos.distance_to(p) < near.pos.distance_to(p):
				near = q
		_bridge("o%d" % i, _facing(near, p), id, _gap_count(near.pos.distance_to(p) - RHO - 0.6))


## every zone's possible notable names, shuffled the same way each run
static func _notable_names() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1
	var out := []
	for z in ZONES:
		var l := []
		for w in z.words:
			for e in NOTABLE_ENDS:
				l.append(w + e)
		for i in range(l.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = l[i]
			l[i] = l[j]
			l[j] = t
		out.append(l)
	return out


## two of the zone's notable stats, a little stronger the farther out the layer
static func _notable_stats(z: int, layer: int, roll: int) -> Dictionary:
	var pool: Dictionary = ZONES[z].notable
	var keys := pool.keys()
	var a: String = keys[roll % keys.size()]
	var b: String = keys[(roll / keys.size() + 1 + roll % keys.size()) % keys.size()]
	if b == a:
		b = keys[(keys.find(a) + 1) % keys.size()]
	var sc := 1.0 + 0.12 * (layer - 1)
	var out := {}
	for k in [a, b]:
		var v: float = pool[k] * sc
		out[k] = roundi(v) if pool[k] >= 5 else snappedf(v, 0.5)
	return out


# ---- ring jewels ----
## make the tree carry the rings of these socketed ring jewels: [{socket: large socket id, jewel: ring jewel}].
## The old rings' nodes leave first; ids are "x<socket>_<n>", so the same jewel in the same socket gives the same ids
static func set_rings(rings: Array) -> void:
	nodes()
	var key := JSON.stringify(rings.map(func(r): return [r.socket, Jewels.ring_key(r.jewel)]))
	if key == _ring_key:
		return
	for id in _ext:
		for nb in _nodes[id].links:
			if _nodes.has(nb) and not nb in _ext:
				_nodes[nb].links.erase(id)
		_nodes.erase(id)
	_order.resize(_base)
	_ext = []
	for r in rings:
		var s: Dictionary = node(r.socket)
		if s.get("kind", "") != "ring_socket":
			continue
		var plan := Jewels.ring_plan(r.jewel)
		var n: int = plan.size()
		var dir: Vector2 = s.pos.normalized()
		var rr := 1.2 + n * 0.14
		var centre: Vector2 = s.pos + dir * (RING_OUT + rr - 1.6)
		var back: float = (s.pos - centre).angle()
		for j in n:
			var m: Dictionary = plan[j]
			var id := "x%s_%d" % [r.socket, j]
			_nodes[id] = {"id": id, "name": m.name, "kind": m.kind, "ang": s.ang, "pos": centre + Vector2.from_angle(back + TAU * j / n) * rr,
				"stats": m.stats, "links": [], "sector": s.sector, "zone": s.zone, "layer": LAYERS + 2, "ring": r.socket}
			_order.append(id)
			_ext.append(id)
		for j in n:
			_link("x%s_%d" % [r.socket, j], "x%s_%d" % [r.socket, (j + 1) % n])
		_link(r.socket, "x%s_0" % r.socket)
	_ring_key = key


## the ids a ring jewel in large socket `socket` adds
static func ring_ids(socket: String) -> Array:
	return _ext.filter(func(id): return _nodes[id].ring == socket)


# ---- allocation ----
## a node that can never be taken: another class's start
static func _blocked(id: String, cls: String) -> bool:
	return node(id).kind == "start" and id != start_id(cls)


## the fewest new nodes that join `id` to what `tree` (allocated ids) already holds, ending with `id`;
## [] if it is taken already or cannot be reached
static func path_to(tree: Array, cls: String, id: String) -> Array:
	if node(id).is_empty() or id in tree or _blocked(id, cls) or id == start_id(cls):
		return []
	var have := {start_id(cls): true}
	for t in tree:
		have[t] = true
	var came := {}
	var queue: Array = have.keys()
	for q in queue:
		came[q] = ""
	var head := 0
	while head < queue.size():
		var cur: String = queue[head]
		head += 1
		for nb in _nodes[cur].links:
			if came.has(nb) or _blocked(nb, cls):
				continue
			came[nb] = cur
			if nb == id:
				var path := [id]
				var back: String = cur
				while not have.has(back):
					path.push_front(back)
					back = came[back]
				return path
			queue.append(nb)
	return []


## the allocated nodes still joined to the class's start through allocated nodes
static func connected(tree: Array, cls: String) -> Array:
	nodes()
	var inside := {}
	for t in tree:
		inside[t] = true
	var seen := {start_id(cls): true}
	var queue: Array = [start_id(cls)]
	var head := 0
	while head < queue.size():
		for nb in _nodes[queue[head]].links:
			if not seen.has(nb) and inside.has(nb):
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
	var seen := {}
	if typeof(raw) == TYPE_ARRAY:
		for x in raw:
			var id := str(x)
			if nodes().has(id) and node(id).kind != "start" and not seen.has(id):
				t.append(id)
				seen[id] = true
	t = connected(t, cls)
	while t.size() > points:
		# leaves (nodes nothing else hangs from) are the ones that can go; the farthest of them first
		var far := t.duplicate()
		far.sort_custom(func(a, b): return node(a).pos.length() > node(b).pos.length())
		for id in far:
			if can_refund(t, cls, id):
				t.erase(id)
				break
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
