class_name Jewels
## Jewels for the passive tree, two kinds:
## - 燈晶 (kind "jewel"): sits in a 燈晶の台座 node and gives its lines while that node is taken. Normal, magic or rare
##   with affixes like gear, crafted with the same currencies (変容 → magic, 昇華 → rare, 混沌 recarves, 鍛錬 adds a
##   line, 浄化 wipes, 神秘 rerolls the numbers).
## - 環晶 (kind "ring"): sits in a 環晶の大台座 on the outer band and grows its own small ring of nodes past it
##   (PassiveTree.set_rings). Its size line sets how many small nodes the ring has (the large one also holds a small
##   燈晶の台座), its theme line what they give, and its notables (rolled like affixes) the notables on the ring;
##   its strength line scales the small nodes.
## Both are plain Dictionaries: {uid, kind, base, rarity, ilvl, name, socket, ...}; socket is the node id it sits in, or "".
## A socketed jewel can't be crafted: take it out first (a ring's nodes then go back as points).

const MAX_OWNED := 40         # jewels kept per character; more break down into ember as they are picked up
const COLOR := Color("#ff9ad8")
const RING_COLOR := Color("#b08cff")

# 燈晶 bases: each has one fixed line
const BASES := [
	{"id": "ash", "name": "灰の燈晶", "implicit": {"life": 8}},
	{"id": "cinder", "name": "燼の燈晶", "implicit": {"mana": 8}},
	{"id": "shade", "name": "影の燈晶", "implicit": {"crit": 1}},
]

# 燈晶 affixes: `min`..`max` at item level 0, growing by `sc` per item level
const AFFIXES := [
	{"k": "inc_dmg", "word": "猛き", "min": 4, "max": 8, "sc": 0.03},
	{"k": "life", "word": "頑強な", "min": 6, "max": 14, "sc": 0.05},
	{"k": "mana", "word": "賢明な", "min": 5, "max": 12, "sc": 0.04},
	{"k": "armor", "word": "堅牢な", "min": 6, "max": 14, "sc": 0.06},
	{"k": "crit", "word": "狙い澄ました", "min": 1, "max": 2, "sc": 0.01},
	{"k": "crit_multi", "word": "残忍な", "min": 6, "max": 14, "sc": 0.03},
	{"k": "atk_spd", "word": "迅速な", "min": 2, "max": 5, "sc": 0.01},
	{"k": "cast_spd", "word": "流麗な", "min": 2, "max": 5, "sc": 0.01},
	{"k": "move_spd", "word": "疾風の", "min": 1, "max": 3, "sc": 0.01},
	{"k": "fire_dmg", "word": "燃え盛る", "min": 5, "max": 11, "sc": 0.03},
	{"k": "cold_dmg", "word": "凍てつく", "min": 5, "max": 11, "sc": 0.03},
	{"k": "light_dmg", "word": "轟く", "min": 5, "max": 11, "sc": 0.03},
	{"k": "chaos_dmg", "word": "蝕む", "min": 5, "max": 11, "sc": 0.03},
	{"k": "spell_dmg", "word": "神秘の", "min": 4, "max": 9, "sc": 0.03},
	{"k": "atk_dmg", "word": "武闘の", "min": 4, "max": 9, "sc": 0.03},
	{"k": "ally_dmg", "word": "従える", "min": 6, "max": 12, "sc": 0.03},
	{"k": "ally_life", "word": "護る", "min": 5, "max": 10, "sc": 0.03},
	{"k": "life_on_kill", "word": "貪欲な", "min": 1, "max": 3, "sc": 0.05},
]

# 環晶 sizes: small nodes on the ring, notables it can hold at most, and whether it has a small socket
const SIZES := [
	{"id": "s", "name": "小環晶", "smalls": 4, "notables": 1, "socket": false},
	{"id": "m", "name": "環晶", "smalls": 6, "notables": 2, "socket": false},
	{"id": "l", "name": "大環晶", "smalls": 8, "notables": 3, "socket": true},
]

# 環晶 themes: what the ring's small nodes give (before the strength line), and the notables the jewel can roll
const THEMES := [
	{"id": "blade", "name": "刃鳴りの環", "small": {"name": "刃鳴り", "stats": {"atk_dmg": 7}}, "notables": [
		{"id": "rn_edge", "name": "研ぎ澄ます刃", "stats": {"atk_dmg": 18, "crit": 1}},
		{"id": "rn_flurry", "name": "乱れ斬り", "stats": {"atk_spd": 8, "atk_dmg": 8}},
		{"id": "rn_reaper", "name": "刈り手の作法", "stats": {"life_on_kill": 6, "atk_dmg": 10}},
		{"id": "rn_duelist", "name": "一騎の誉れ", "stats": {"crit_multi": 25, "atk_dmg": 8}}]},
	{"id": "ward", "name": "鉄壁の環", "small": {"name": "鉄壁", "stats": {"armor": 14}}, "notables": [
		{"id": "rn_rampart", "name": "城壁の如く", "stats": {"armor": 60, "dr_pct": 2}},
		{"id": "rn_scar", "name": "古傷の誇り", "stats": {"life": 35, "armor": 20}},
		{"id": "rn_anvil", "name": "鉄床の心", "stats": {"dr_pct": 4, "life_regen": 1.5}},
		{"id": "rn_bastion", "name": "最後の砦", "stats": {"life_pct": 6, "armor": 30}}]},
	{"id": "flame", "name": "業火の環", "small": {"name": "業火", "stats": {"fire_dmg": 7}}, "notables": [
		{"id": "rn_pyre", "name": "火葬の薪", "stats": {"fire_dmg": 22}},
		{"id": "rn_cinders", "name": "舞い散る火の粉", "stats": {"fire_dmg": 12, "cast_spd": 4}},
		{"id": "rn_forge", "name": "炉心の熱", "stats": {"fire_dmg": 12, "atk_dmg": 10}},
		{"id": "rn_wildfire", "name": "燎原の火", "stats": {"fire_dmg": 14, "inc_dmg": 6}}]},
	{"id": "frost", "name": "霜夜の環", "small": {"name": "霜夜", "stats": {"cold_dmg": 7}}, "notables": [
		{"id": "rn_rime", "name": "樹氷の森", "stats": {"cold_dmg": 22}},
		{"id": "rn_stillness", "name": "凍てる静寂", "stats": {"cold_dmg": 12, "mana": 25}},
		{"id": "rn_shard", "name": "氷片の嵐", "stats": {"cold_dmg": 12, "crit": 1}},
		{"id": "rn_winter", "name": "冬籠り", "stats": {"cold_dmg": 10, "armor": 30}}]},
	{"id": "storm", "name": "雷鳴の環", "small": {"name": "雷鳴", "stats": {"light_dmg": 7}}, "notables": [
		{"id": "rn_thunder", "name": "遠雷", "stats": {"light_dmg": 22}},
		{"id": "rn_static", "name": "帯電する肌", "stats": {"light_dmg": 12, "atk_spd": 4}},
		{"id": "rn_bolt", "name": "一閃の稲妻", "stats": {"light_dmg": 12, "crit_multi": 15}},
		{"id": "rn_gale", "name": "嵐の申し子", "stats": {"light_dmg": 10, "move_spd": 4}}]},
	{"id": "spirit", "name": "灯霊の環", "small": {"name": "灯霊", "stats": {"ally_dmg": 9}}, "notables": [
		{"id": "rn_host", "name": "灯の行列", "stats": {"ally_dmg": 25}},
		{"id": "rn_ward", "name": "灯霊の守護", "stats": {"ally_life": 25, "ally_dmg": 8}},
		{"id": "rn_bond", "name": "結ばれた灯", "stats": {"ally_dmg": 12, "life": 20}},
		{"id": "rn_choir", "name": "鬼火の合唱", "stats": {"ally_dmg": 14, "cast_spd": 4}}]},
	{"id": "vital", "name": "命脈の環", "small": {"name": "命脈", "stats": {"life": 12}}, "notables": [
		{"id": "rn_heart", "name": "脈打つ心臓", "stats": {"life_pct": 8}},
		{"id": "rn_spring", "name": "湧き出る生気", "stats": {"life_regen": 3, "life": 20}},
		{"id": "rn_feast", "name": "饗宴", "stats": {"life_on_kill": 8, "life": 15}},
		{"id": "rn_marrow", "name": "骨髄の力", "stats": {"life": 40}}]},
	{"id": "arcane", "name": "秘儀の環", "small": {"name": "秘儀", "stats": {"spell_dmg": 7}}, "notables": [
		{"id": "rn_tome", "name": "禁書の頁", "stats": {"spell_dmg": 20, "mana": 15}},
		{"id": "rn_chant", "name": "重ねる詠唱", "stats": {"cast_spd": 8, "spell_dmg": 8}},
		{"id": "rn_well", "name": "尽きぬ魔泉", "stats": {"mana_pct": 8, "mana_regen": 2}},
		{"id": "rn_sigil", "name": "燼紋の継承", "stats": {"spell_dmg": 12, "fire_dmg": 6, "cold_dmg": 6, "light_dmg": 6}}]},
]

static var _uid := 0


static func base(id: String) -> Dictionary:
	for b in BASES:
		if b.id == id:
			return b
	return {}


static func affix(k: String) -> Dictionary:
	for a in AFFIXES:
		if a.k == k:
			return a
	return {}


static func size_def(id: String) -> Dictionary:
	for s in SIZES:
		if s.id == id:
			return s
	return {}


static func theme(id: String) -> Dictionary:
	for t in THEMES:
		if t.id == id:
			return t
	return {}


static func ring_notable(id: String) -> Dictionary:
	for t in THEMES:
		for n in t.notables:
			if n.id == id:
				return n
	return {}


static func is_ring(j: Dictionary) -> bool:
	return j.get("kind", "") == "ring"


# =================== making ===================
## a new 燈晶 of item level `ilvl` (rarity rolled like gear unless forced, never a unique)
static func generate(ilvl: int, force_rarity := -1, base_id := "") -> Dictionary:
	_uid += 1
	var r := force_rarity if force_rarity >= 0 else mini(2, Items.roll_rarity(0.5))
	var b: Dictionary = base(base_id) if base_id != "" else BASES.pick_random()
	var j := {"uid": "j%d_%d" % [Time.get_ticks_msec(), _uid], "kind": "jewel", "base": b.id, "rarity": r, "ilvl": ilvl,
		"name": "", "socket": "", "mods": {}}
	add_affixes(j, randi_range(Data.RARITY[r].aff[0], Data.RARITY[r].aff[1]))
	name_jewel(j)
	return j


## a new 環晶: size and theme rolled unless given, magic or rare
static func generate_ring(ilvl: int, force_rarity := -1, size_id := "", theme_id := "") -> Dictionary:
	_uid += 1
	var r := force_rarity if force_rarity >= 0 else (2 if randf() < 0.3 else 1)
	var j := {"uid": "r%d_%d" % [Time.get_ticks_msec(), _uid], "kind": "ring", "base": size_id if size_id != "" else SIZES.pick_random().id,
		"rarity": r, "ilvl": ilvl, "name": "", "socket": "", "theme": theme_id if theme_id != "" else THEMES.pick_random().id,
		"power": 0, "notables": []}
	roll_power(j)
	add_notables(j, notables_range(j)[1] if r == 2 else notables_range(j)[0])
	name_jewel(j)
	return j


static func roll_value(j: Dictionary, a: Dictionary) -> int:
	return value_at(j, a, randf())


## the affix value at `t` of the way from its least (0) to its most (1); ModRange reads the range from it
static func value_at(j: Dictionary, a: Dictionary, t: float) -> int:
	return maxi(1, roundi((a.min + t * (a.max - a.min)) * (1.0 + j.ilvl * a.sc)))


static func add_affixes(j: Dictionary, n: int) -> void:
	var pool := AFFIXES.filter(func(a): return not j.mods.has(a.k))
	pool.shuffle()
	for i in mini(n, pool.size()):
		j.mods[pool[i].k] = roll_value(j, pool[i])


## how many notables a ring jewel of its rarity holds: [least, most]
static func notables_range(j: Dictionary) -> Array:
	var most: int = size_def(j.base).notables
	match int(j.rarity):
		0:
			return [0, 0]
		1:
			return [1, 1]
		_:
			return [mini(2, most), most]


static func add_notables(j: Dictionary, n: int) -> void:
	var pool: Array = theme(j.theme).notables.filter(func(x): return not x.id in j.notables)
	pool.shuffle()
	for i in mini(n - j.notables.size(), pool.size()):
		j.notables.append(pool[i].id)


## the strength line: how much stronger than the theme's base the small nodes are (%)
static func roll_power(j: Dictionary) -> void:
	j.power = power_at(j, randf_range(0.0, 20.0))


static func power_at(j: Dictionary, roll: float) -> int:
	return roundi(roll + j.ilvl * 0.6)


static func name_jewel(j: Dictionary) -> void:
	var bn: String = size_def(j.base).name if is_ring(j) else base(j.base).name
	match int(j.rarity):
		0:
			j.name = bn
		1:
			if is_ring(j):
				j.name = theme(j.theme).name.trim_suffix("の環") + "の" + bn
			else:
				var first: String = j.mods.keys()[0] if not j.mods.is_empty() else ""
				j.name = (affix(first).word if first != "" else "") + bn
		_:
			j.name = Data.RARE_A.pick_random() + Data.RARE_B.pick_random()


# =================== crafting ===================
## apply a crafting currency, the way it works on gear; returns an error message, or "" on success
static func craft(k: String, j: Dictionary) -> String:
	if j.socket != "":
		return "台座から外してから使う"
	var r := int(j.rarity)
	var ring := is_ring(j)
	match k:
		"transmute":
			if r != 0: return "ノーマルにのみ使えます"
			j.rarity = 1
			if ring:
				add_notables(j, 1)
			else:
				add_affixes(j, randi_range(1, 2))
			name_jewel(j)
		"ascend":
			if r != 1: return "マジックにのみ使えます"
			j.rarity = 2
			if ring:
				add_notables(j, notables_range(j)[1])
			else:
				add_affixes(j, randi_range(3, 4) - j.mods.size())
			name_jewel(j)
		"chaos":
			if r != 1 and r != 2: return "マジック・レアにのみ使えます"
			if ring:
				var n: int = j.notables.size()
				j.theme = THEMES.filter(func(t): return t.id != j.theme).pick_random().id
				j.notables = []
				add_notables(j, n)
			else:
				j.mods = {}
				add_affixes(j, randi_range(Data.RARITY[r].aff[0], Data.RARITY[r].aff[1]))
			name_jewel(j)
		"whet":
			if r != 1 and r != 2: return "マジック・レアにのみ使えます"
			var before: int = j.notables.size() if ring else j.mods.size()
			var most: int = notables_range(j)[1] if ring else Data.RARITY[r].aff[1]
			if before >= most: return "これ以上オプションを追加できません"
			if ring:
				add_notables(j, before + 1)
			else:
				add_affixes(j, 1)
			if (j.notables.size() if ring else j.mods.size()) == before: return "追加できるオプションがありません"
		"purify":
			if r != 1 and r != 2: return "マジック・レアにのみ使えます"
			j.rarity = 0
			if ring:
				j.notables = []
			else:
				j.mods = {}
			name_jewel(j)
		"divine":
			if ring:
				roll_power(j)
			else:
				if j.mods.is_empty(): return "オプションのある燈晶にのみ使えます"
				for key in j.mods.keys():
					j.mods[key] = roll_value(j, affix(key))
		_:
			return "このカレンシーはジュエルに使えません"
	return ""


# =================== in the tree ===================
## what a ring jewel's ring is made of, in ring order from the node next to the socket:
## [{kind, name, stats}], small nodes with the notables spread between them and the small socket opposite the entry
static func ring_plan(j: Dictionary) -> Array:
	var sd := size_def(j.base)
	var th := theme(j.theme)
	var n: int = sd.smalls + j.notables.size() + (1 if sd.socket else 0)
	var kinds := []
	kinds.resize(n)
	kinds.fill("small")
	if sd.socket:
		kinds[n / 2] = "socket"
	for i in j.notables.size():
		var at := roundi((i + 1.0) * n / (j.notables.size() + 1.0)) % n
		while kinds[at] != "small" or at == 0:
			at = (at + 1) % n
		kinds[at] = j.notables[i]
	var sc := 1.0 + int(j.power) / 100.0
	var out := []
	for k in kinds:
		if k == "small":
			var st := {}
			for s in th.small.stats:
				st[s] = roundi(th.small.stats[s] * sc)
			out.append({"kind": "small", "name": th.small.name, "stats": st})
		elif k == "socket":
			out.append({"kind": "socket", "name": "燈晶の小台座", "stats": {}})
		else:
			var nd := ring_notable(k)
			out.append({"kind": "notable", "name": nd.name, "stats": nd.stats})
	return out


## what makes two ring jewels grow the same ring
static func ring_key(j: Dictionary) -> String:
	return "%s/%s/%d/%s" % [j.base, j.theme, int(j.power), ",".join(PackedStringArray(j.notables))]


## the stats of the 燈晶 sitting in taken sockets (a ring jewel's stats come through its ring's nodes instead)
static func stats(list: Array, tree: Array) -> Dictionary:
	var st := {}
	for j in list:
		if is_ring(j) or j.socket == "" or not j.socket in tree:
			continue
		for src in [base(j.base).implicit, j.mods]:
			for k in src:
				Data.add_stat(st, k, src[k])
	return st


## the socketed ring jewels as PassiveTree.set_rings takes them
static func rings_in(list: Array) -> Array:
	return list.filter(func(j): return is_ring(j) and j.socket != "").map(func(j): return {"socket": j.socket, "jewel": j})


static func at_socket(list: Array, socket: String) -> Dictionary:
	for j in list:
		if j.socket == socket:
			return j
	return {}


## which socket kind takes this jewel
static func socket_kind(j: Dictionary) -> String:
	return "ring_socket" if is_ring(j) else "socket"


## what breaking a jewel down pays in ember shards
static func shard_value(j: Dictionary) -> int:
	return (6 + j.ilvl * 2) * (1 + int(j.rarity)) + (8 if is_ring(j) else 0)


## tooltip lines: [text, color, size]
static func lines(j: Dictionary) -> Array:
	var rc: Color = Data.RARITY[int(j.rarity)].color
	var out := [[j.name, rc, 17]]
	if is_ring(j):
		var sd := size_def(j.base)
		var th := theme(j.theme)
		out.append(["%s 環晶（%s）　アイテムレベル %d" % [Data.RARITY[int(j.rarity)].name, sd.name, j.ilvl], Color("#9a9080"), 13])
		out.append(["環の大きさ：小ノード %d%s" % [sd.smalls, "・燈晶の小台座 1" if sd.socket else ""], RING_COLOR, 14])
		var st := {}
		for s in th.small.stats:
			st[s] = roundi(th.small.stats[s] * (1.0 + int(j.power) / 100.0))
		out.append(["%s：小ノードは %s" % [th.name, "、".join(PackedStringArray(PassiveTree.lines(st)))], RING_COLOR, 14])
		out.append(ModRange.line("環の強さ +%d%%" % int(j.power), Color("#8fb4ff"), 14, ModRange.ring_power(j)))
		for id in j.notables:
			var nd := ring_notable(id)
			out.append(["◆ %s：%s" % [nd.name, "、".join(PackedStringArray(PassiveTree.lines(nd.stats)))], Color("#8fb4ff"), 14])
		if j.notables.size() < notables_range(j)[1]:
			out.append(["注目ノードをあと %d つ足せる（鍛錬の砥石）" % (notables_range(j)[1] - j.notables.size()), Color("#7a7266"), 12])
		out.append(["環晶の大台座に入れると、その先に環が伸びる", Color("#a89878"), 12])
	else:
		var b := base(j.base)
		out.append(["%s 燈晶（%s）　アイテムレベル %d" % [Data.RARITY[int(j.rarity)].name, b.name, j.ilvl], Color("#9a9080"), 13])
		for l in PassiveTree.lines(b.implicit):
			out.append(ModRange.fixed(l, Color("#b8b0a0"), 14))
		for k in PassiveTree.FMT.keys().filter(func(q): return j.mods.has(q)):   # the order PassiveTree.lines gives
			for l in PassiveTree.lines({k: j.mods[k]}):
				out.append(ModRange.line(l, Color("#8fb4ff"), 14, ModRange.jewel(j, k)))
		out.append(["燈晶の台座に入れ、その台座を取得している間だけ効く", Color("#a89878"), 12])
	out.append(["台座に入っている" if j.socket != "" else "台座に入っていない", Color("#b8a888"), 12])
	return out


## JSON turns numbers into floats, and a hand-edited file may hold anything: keep the jewels that make sense,
## field order as generate makes them so a save round-trips unchanged. Sockets are checked later (Player.fix_jewels)
static func normalize(raw) -> Array:
	var out := []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for r in raw:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var ring := str(r.get("kind", "")) == "ring"
		var bid := str(r.get("base", ""))
		if (ring and size_def(bid).is_empty()) or (not ring and base(bid).is_empty()):
			continue
		var j := {"uid": str(r.get("uid", "")), "kind": "ring" if ring else "jewel", "base": bid, "rarity": clampi(int(r.get("rarity", 0)), 0, 2),
			"ilvl": maxi(1, int(r.get("ilvl", 1))), "name": str(r.get("name", "")), "socket": str(r.get("socket", ""))}
		if j.uid == "" or out.any(func(o): return o.uid == j.uid):
			_uid += 1
			j.uid = "j_load_%d" % _uid
		if ring:
			var th := str(r.get("theme", ""))
			j.theme = th if not theme(th).is_empty() else THEMES[0].id
			j.power = clampi(int(r.get("power", 0)), 0, 200)
			j.notables = []
			var nl = r.get("notables", [])
			if typeof(nl) == TYPE_ARRAY:
				for id in nl:
					var known: bool = theme(j.theme).notables.any(func(x): return x.id == str(id))
					if known and not str(id) in j.notables and j.notables.size() < notables_range(j)[1]:
						j.notables.append(str(id))
		else:
			j.mods = {}
			var mods = r.get("mods", {})
			if typeof(mods) == TYPE_DICTIONARY:
				for k in mods:
					if not affix(str(k)).is_empty() and j.mods.size() < Data.RARITY[j.rarity].aff[1]:
						j.mods[str(k)] = int(mods[k])
		if j.name == "":
			name_jewel(j)
		out.append(j)
	return out.slice(0, MAX_OWNED)
