class_name Maps
## The fifty expedition maps (5 elements × 10) and the map items (遠征地図) that open them.
## Every map can be run at any tier: the tier is on the map item used to enter, and it sets the area level.
## Each map has its own fixed layout: its rooms sit on a hand-laid route (`route`), and the rest of the
## look (room sizes, ragged edges, pillars, floor tiles, props) comes from a seed fixed per map, so a map
## looks and walks the same on every visit.
## A map item is a stack in a Dictionary "<map id>:<tier>" -> n (Atlas.maps).
## Tiers have no cap (#74): clearing tier N can drop tier N+1, and each tier up makes the monsters stronger by a
## growing step (POWER_STEPS) and pays more for it (more and rarer loot, more ember, and dearer map items).

const TIER_LIMIT := 9999    # not a design cap, only a guard that keeps every number finite (keys and saves above it are clamped)
const OLD_MAX_TIER := 16    # the cap before #74, for tests and docs
const ICON := "◈"
const COLOR := Color("#e8c890")
const GRID := 12            # route points are on a 0..GRID grid
const CELL := 5             # tiles between grid lines
const MARGIN := 5           # tiles from the map edge to grid line 0
const SIZE := 72            # tiles across a map
const BUY_TIER := 1         # the map device sells tier 1 maps of every map, so a run can always start

# the elements: the land a map is in (Data.THEMES has its look, Data.BOSS_ROTATION its boss) and which
# monsters it favours (weight multipliers on the usual pool)
const ELEMENTS := [
	{"k": "phys", "name": "物理", "color": Color("#c9b89a"), "pool": {"ghoul": 1.6, "brute": 1.3}},
	{"k": "fire", "name": "火炎", "color": Color("#ff7a3a"), "pool": {"imp": 1.8, "brute": 1.4}},
	{"k": "cold", "name": "冷気", "color": Color("#7fd4ff"), "pool": {"archer": 1.7, "shaman": 1.4}},
	{"k": "light", "name": "雷", "color": Color("#d9b8ff"), "pool": {"imp": 1.4, "archer": 1.5, "shaman": 1.2}},
	{"k": "chaos", "name": "混沌", "color": Color("#9fe070"), "pool": {"ghoul": 1.4, "shaman": 1.6, "brute": 1.2}},
]

# `route`: chains of grid points "x,y" joined by corridors, chains split by "|"; rooms sit on the points (a point
# shared by two chains is one room). The first chain is the main road: its first point is the entrance, its
# last the boss room; the other chains are side roads and loops.
const LIST := [
	# ---- 物理: 朽ちた地下墓所 ----
	{"id": "ash", "name": "灰の入口", "elem": 0, "shape": "一本道", "desc": "深淵へ続く最初の階段。まっすぐな大回廊に小部屋がひとつ。",
		"route": "0,6 3,6 6,6 9,6 12,6|6,6 6,2"},
	{"id": "bone", "name": "骨の回廊", "elem": 0, "shape": "S字", "desc": "無数の骨が積み上げられた、うねる細い通路。",
		"route": "1,11 5,11 9,11 11,8 8,6 4,6 1,4 3,1 7,1 11,1"},
	{"id": "wail", "name": "嘆きの納骨堂", "elem": 0, "shape": "環と中心", "desc": "環状の納骨堂。番人は中央の玄室で待つ。",
		"route": "6,12 6,10 2,9 1,5 3,2 6,1 6,5|6,1 9,2 11,5 10,9 6,10"},
	{"id": "hush", "name": "沈黙の霊廟", "elem": 0, "shape": "U字", "desc": "片側を降りきって、もう片側を登る霊廟。",
		"route": "1,1 1,4 1,7 1,10 4,11 8,11 11,10 11,7 11,4 11,1"},
	{"id": "chain", "name": "鎖の牢獄", "elem": 0, "shape": "櫛", "desc": "長い廊下から独房が櫛の歯のように垂れ下がる。",
		"route": "0,2 3,2 6,2 9,2 12,2 12,6 12,10|3,2 3,6 3,10|6,2 6,7|9,2 9,10"},
	{"id": "chapel", "name": "崩れた礼拝堂", "elem": 0, "shape": "十字", "desc": "十字に組まれた礼拝堂。両翼は崩れかけている。",
		"route": "6,12 6,9 6,6 6,3 6,0|0,6 3,6 6,6 9,6 12,6"},
	{"id": "throne", "name": "骸骨王の階段", "elem": 0, "shape": "階段", "desc": "骸骨王の玉座へ一段ずつ折れて登る大階段。",
		"route": "0,12 2,12 2,10 4,10 4,8 6,8 6,6 8,6 8,4 10,4 10,2 12,2 12,0"},
	{"id": "keeper", "name": "墓守の迷い道", "elem": 0, "shape": "雷文", "desc": "行きつ戻りつ折れ曲がる、墓守の巡回路。",
		"route": "0,11 3,11 3,7 6,7 6,11 9,11 9,7 12,7 12,2 8,2 4,2 0,2"},
	{"id": "dusk", "name": "黄昏の地下聖堂", "elem": 0, "shape": "H字", "desc": "二本の側廊を一本の橋廊がつなぐ地下聖堂。",
		"route": "1,12 1,9 1,6 6,6 11,6 11,3 11,0|1,6 1,3 1,0|11,6 11,9 11,12"},
	{"id": "pit", "name": "千骨の大穴", "elem": 0, "shape": "角渦", "desc": "外周から内へ内へと巻いて降りる大穴。",
		"route": "0,12 0,6 0,0 6,0 12,0 12,6 12,12 7,12 3,12 3,7 3,3 9,3 9,9 6,9 6,6"},
	# ---- 火炎: 溶岩の洞窟 ----
	{"id": "ember", "name": "燻る坑道", "elem": 1, "shape": "W字", "desc": "地熱で焼けた岩が赤く光る、上下に折れる廃坑。",
		"route": "0,1 1,6 3,11 5,7 6,3 7,7 9,11 11,6 12,1"},
	{"id": "obsidian", "name": "黒曜の裂け目", "elem": 1, "shape": "V字", "desc": "谷底まで下って、反対の崖を登り返す黒曜の谷。",
		"route": "0,0 2,4 4,8 6,11 8,8 10,4 12,0"},
	{"id": "forge", "name": "溶鉄の炉心", "elem": 1, "shape": "Y字", "desc": "一本の坑道が二つに分かれる。巨像は左の炉にいる。",
		"route": "6,12 6,9 6,6 3,3 1,0|6,6 9,3 11,0"},
	{"id": "crater", "name": "火口への登攀", "elem": 1, "shape": "三角", "desc": "火口の頂へ、左右どちらの斜面からでも登れる。",
		"route": "6,12 1,12 3,8 5,4 6,1|6,12 11,12 9,8 7,4 6,1"},
	{"id": "river", "name": "灼熱の大河", "elem": 1, "shape": "波", "desc": "溶岩の大河に沿って大きく波打つ岸辺の道。",
		"route": "0,6 2,2 4,2 6,6 8,10 10,10 12,6"},
	{"id": "altar", "name": "熔岩溜まりの祭壇", "elem": 1, "shape": "8の字", "desc": "二つの溶岩溜まりを8の字に巡る祭壇。",
		"route": "6,12 3,9 6,6 3,3 6,0|6,12 9,9 6,6 9,3 6,0"},
	{"id": "smithy", "name": "煤けた鍛冶街", "elem": 1, "shape": "梯子", "desc": "二本の大通りを横道がはしごのようにつなぐ廃れた鍛冶街。",
		"route": "3,12 3,8 3,4 3,0 9,0|9,0 9,4 9,8 9,12 3,12|3,8 9,8|3,4 9,4"},
	{"id": "gate", "name": "炎獄の門", "elem": 1, "shape": "Ω字", "desc": "門をくぐると大きく弧を描いて、反対側の門へ抜ける。",
		"route": "0,12 3,12 2,8 2,4 6,1 10,4 10,8 9,12 12,12"},
	{"id": "quarry", "name": "赤熱の採掘場", "elem": 1, "shape": "樹", "desc": "掘り進むたびに枝分かれした、根のような採掘跡。",
		"route": "6,12 6,9 3,6 1,3 0,0|6,9 9,6 11,3 12,0|3,6 4,2|9,6 8,2"},
	{"id": "cinder", "name": "灰燼の王座", "elem": 1, "shape": "矢印", "desc": "まっすぐな参道の先、矢じりのように広がる王座の間。",
		"route": "6,12 6,9 6,6 6,3 6,0|6,0 3,3|6,0 9,3"},
	# ---- 冷気: 凍てつく聖堂 ----
	{"id": "frost", "name": "凍てつく参道", "elem": 2, "shape": "九十九折", "desc": "氷に閉ざされた巡礼路。三段に折り返して進む。",
		"route": "0,1 4,1 8,1 12,1 12,6 8,6 4,6 0,6 0,11 4,11 8,11 12,11"},
	{"id": "cathedral", "name": "霜の大聖堂", "elem": 2, "shape": "T字", "desc": "長い身廊の奥、左右に分かれる翼廊。魔女は左の奥に。",
		"route": "6,12 6,9 6,5 6,1 2,1|6,1 10,1"},
	{"id": "grave", "name": "氷霧の墓標", "elem": 2, "shape": "格子", "desc": "墓標が碁盤の目に並ぶ丘。どの道からでも奥へ行ける。",
		"route": "1,11 6,11 6,6 6,1 11,1|1,11 1,6 1,1 6,1|1,6 6,6 11,6 11,11 6,11|11,6 11,1"},
	{"id": "glacier", "name": "氷河の裂溝", "elem": 2, "shape": "N字", "desc": "裂溝を登り、斜めに滑り降り、また登る。",
		"route": "1,12 1,8 1,4 1,0 4,4 8,8 11,12 11,8 11,4 11,0"},
	{"id": "silver", "name": "白銀の砂時計", "elem": 2, "shape": "砂時計", "desc": "上下の広間が中央の一点でだけつながる。",
		"route": "1,12 6,12 11,12 8,9 6,6 4,3 1,0 6,0 11,0|1,12 4,9 6,6 8,3 11,0"},
	{"id": "lake", "name": "凍結湖の岸辺", "elem": 2, "shape": "C字", "desc": "凍った湖をぐるりと半周する岸辺の道。",
		"route": "11,0 6,0 2,2 0,6 2,10 6,12 11,12"},
	{"id": "giant", "name": "霜巨人の足跡", "elem": 2, "shape": "X字", "desc": "二筋の巨大な足跡が中央で交わる雪原。",
		"route": "0,12 3,9 6,6 9,3 12,0|0,0 3,3 6,6 9,9 12,12"},
	{"id": "crystal", "name": "氷晶の双環", "elem": 2, "shape": "連環", "desc": "菱形の氷晶が二つ連なる。どちらの縁を通ってもよい。",
		"route": "0,6 3,3 6,6 9,3 12,6|0,6 3,9 6,6 9,9 12,6"},
	{"id": "spire", "name": "吹雪の尖塔", "elem": 2, "shape": "稲妻折れ", "desc": "吹雪の中を左右に大きく振られながら登る尖塔。",
		"route": "6,12 2,10 10,8 2,6 10,4 2,2 6,0"},
	{"id": "permafrost", "name": "永久凍土の墓所", "elem": 2, "shape": "鍵", "desc": "鍵の形に掘られた墓所。軸をたどって輪の墓室へ。",
		"route": "12,5 9,5 6,5 3,2 0,5 3,8|3,8 6,5|12,5 12,9|9,5 9,9"},
	# ---- 雷: 雷鳴の遺跡 ----
	{"id": "thunder", "name": "雷鳴の遺跡", "elem": 3, "shape": "稲妻", "desc": "落雷が刻んだ裂け目そのものが道になった遺跡。",
		"route": "10,0 6,3 3,6 8,6 5,9 1,12"},
	{"id": "ridge", "name": "稲妻の尾根", "elem": 3, "shape": "鋸歯", "desc": "登っては垂直に落ちる、鋸の歯のような尾根。",
		"route": "0,9 4,3 4,9 8,3 8,9 12,3"},
	{"id": "ring", "name": "帯電した環状路", "elem": 3, "shape": "照準", "desc": "環状路を十字の通路が貫く。中心は帯電している。",
		"route": "6,12 6,9 6,6 6,3 6,0|6,12 2,10 0,6 2,2 6,0|6,12 10,10 12,6 10,2 6,0|0,6 3,6 6,6 9,6 12,6"},
	{"id": "tower", "name": "雷霆の塔", "elem": 3, "shape": "円渦", "desc": "塔の内壁に沿って渦を描き、中心の避雷室へ至る。",
		"route": "6,12 1,10 0,5 3,1 8,0 11,3 11,8 8,10 4,9 3,5 6,3 8,5 6,6"},
	{"id": "storm", "name": "嵐の放電路", "elem": 3, "shape": "星", "desc": "中央の放電塔から五方へ伸びる通路。",
		"route": "2,12 4,9 6,6 6,3 6,0|6,6 9,6 12,5|6,6 8,9 10,12|6,6 3,6 0,5"},
	{"id": "rods", "name": "避雷針の森", "elem": 3, "shape": "魚の骨", "desc": "一本の背骨の両側に、避雷針の立つ小道が並ぶ。",
		"route": "0,6 3,6 6,6 9,6 12,6|3,6 3,2|3,6 3,10|6,6 6,2|6,6 6,10|9,6 9,2|9,6 9,10"},
	{"id": "flash", "name": "雷光の階", "elem": 3, "shape": "M字", "desc": "二つの峰を越えて、反対の崖下へ降りる。",
		"route": "0,12 0,6 0,0 3,4 6,8 9,4 12,0 12,6 12,12"},
	{"id": "strike", "name": "落雷の円環", "elem": 3, "shape": "五角", "desc": "五角に並ぶ雷柱。頂の雷柱へは左右どちらからでも。",
		"route": "3,10 1,4 6,0|3,10 9,10 11,4 6,0"},
	{"id": "static", "name": "静電の回廊", "elem": 3, "shape": "Z字", "desc": "上の回廊から斜めに下の回廊へ抜ける。",
		"route": "0,1 4,1 8,1 12,1 8,5 4,8 0,11 4,11 8,11 12,11"},
	{"id": "heaven", "name": "天雷の祭壇", "elem": 3, "shape": "三叉", "desc": "柄から三つの穂先へ分かれる祭壇。王は左の穂先に。",
		"route": "6,12 6,9 6,6 2,6 2,2|6,6 6,2|6,6 10,6 10,2"},
	# ---- 混沌: 腐蝕の沼窟 ----
	{"id": "rot", "name": "腐蝕の沼窟", "elem": 4, "shape": "J字", "desc": "まっすぐ降りて、底で大きく鉤のように曲がる沼窟。",
		"route": "10,0 10,4 10,8 8,11 4,12 1,10 1,7"},
	{"id": "miasma", "name": "瘴気の森", "elem": 4, "shape": "根", "desc": "瘴気を吸った大樹の根が四方へ這う。",
		"route": "6,0 6,3 4,6 2,9 0,12|6,3 9,5 11,8 12,12|4,6 6,9 7,12|9,5 12,3"},
	{"id": "viper", "name": "毒蛇の巣", "elem": 4, "shape": "蛇行", "desc": "蛇の這った跡のようにくねる巣穴。",
		"route": "1,0 5,1 7,3 6,6 3,8 3,11 6,12 10,11 12,9"},
	{"id": "carrion", "name": "腐肉の祭壇", "elem": 4, "shape": "錨", "desc": "錨の形の祭壇。横木と左右の爪に分かれる。",
		"route": "6,0 6,3 6,6 6,9 6,12 3,11 0,8|6,12 9,11 12,8|3,3 6,3 9,3"},
	{"id": "void", "name": "混沌の虚孔", "elem": 4, "shape": "鉤爪", "desc": "掌から三本の爪が伸びる。主は中指の先に。",
		"route": "6,12 6,9 6,6 7,3 9,0|6,9 3,7 1,4 1,1|6,9 9,7 12,5 12,2"},
	{"id": "root", "name": "腐れ根の洞", "elem": 4, "shape": "菱形", "desc": "菱形に絡んだ根の洞。左右どちらの縁でも奥へ。",
		"route": "6,12 3,9 0,6 3,3 6,0|6,12 9,9 12,6 9,3 6,0"},
	{"id": "gut", "name": "蠢く臓腑", "elem": 4, "shape": "腸", "desc": "臓腑のように細かく折れ曲がる、長い一本道。",
		"route": "0,0 0,5 4,5 4,0 8,0 8,5 12,5 12,12 8,12 8,8 4,8 4,12 0,12"},
	{"id": "cauldron", "name": "瘴毒の大釜", "elem": 4, "shape": "日輪", "desc": "大釜を囲む環から、四方へ通路が突き出す。",
		"route": "6,12 6,10 2,6 6,2 6,0|6,10 10,6 6,2|2,6 0,6|10,6 12,6"},
	{"id": "sea", "name": "終焉の腐海", "elem": 4, "shape": "L字", "desc": "腐海の縁を降り、底を真横に渡る。",
		"route": "0,0 0,4 0,8 0,12 4,12 8,12 12,12|0,8 3,8"},
	{"id": "chaos", "name": "混沌の玉座", "elem": 4, "shape": "二重アーチ", "desc": "外のアーチを巡り、内のアーチをくぐって玉座へ戻る。",
		"route": "0,12 0,6 3,1 9,1 12,6 12,12 8,12 8,8 6,6|0,12 4,12 4,8 6,6"},
]


static func def(id: String) -> Dictionary:
	for m in LIST:
		if m.id == id:
			return m
	return {}


static func element(m: Dictionary) -> Dictionary:
	return ELEMENTS[m.elem]


## the route as chains of grid points
static func chains(m: Dictionary) -> Array:
	var out := []
	for ch in str(m.route).split("|"):
		var pts := []
		for p in ch.split(" ", false):
			var xy := p.split(",")
			pts.append(Vector2i(int(xy[0]), int(xy[1])))
		out.append(pts)
	return out


## each room's grid point once, the entrance first and the boss room last
static func points(m: Dictionary) -> Array:
	var ch := chains(m)
	var boss: Vector2i = ch[0][-1]
	var out := []
	for c in ch:
		for p in c:
			if p != boss and not p in out:
				out.append(p)
	out.append(boss)
	return out


static func tile_of(p: Vector2i) -> Vector2i:
	return Vector2i(MARGIN + p.x * CELL, MARGIN + p.y * CELL)


## the seed every random choice of a map's look is drawn from
static func layout_seed(id: String) -> int:
	return hash("emberfall-map-" + id)


# =================== map items ===================
static func key(id: String, tier: int) -> String:
	return "%s:%d" % [id, tier]


## {id, tier, def} for a key, or {} when it names no map item
static func parse(k: String) -> Dictionary:
	var i := k.rfind(":")
	if i < 0:
		return {}
	var m := def(k.left(i))
	var t := int(k.substr(i + 1))
	if m.is_empty() or t < 1 or t > TIER_LIMIT or str(t) != k.substr(i + 1):
		return {}
	return {"id": m.id, "tier": t, "def": m}


static func valid(k: String) -> bool:
	return not parse(k).is_empty()


static func name_of(k: String) -> String:
	var c := parse(k)
	return "%sの地図（T%d）" % [c.def.name, c.tier] if not c.is_empty() else k


static func color_of(k: String) -> Color:
	var c := parse(k)
	return element(c.def).color if not c.is_empty() else COLOR


## the area level a tier gives
static func level_of(tier: int) -> int:
	return clamp_tier(tier)


static func clamp_tier(tier: int) -> int:
	return clampi(tier, 1, TIER_LIMIT)


## a tier (or best tier) read from a save: 0..TIER_LIMIT, a huge or broken number clamped before it becomes an int
static func tier_from(v) -> int:
	var f := float(v) if (v is int or v is float or v is String) else 0.0
	if is_nan(f):
		return 0
	return int(clampf(f, 0.0, TIER_LIMIT))


# =================== tier scaling (#74) ===================
# On top of the area level, each tier multiplies monster life by a step that grows with depth: the first steps are
# gentle so the early tiers play as before, the deep ones are steep. Damage takes POWER_DMG of the same growth.
const POWER_STEPS := [[5, 1.04], [15, 1.08], [30, 1.12], [TIER_LIMIT, 1.15]]   # [up to tier, × per tier]
const POWER_DMG := 0.6
const POWER_MAX := 1e15     # clamp: past ~T250 the power stops growing (the area level still does)
const GOLD_SHARE := 0.5     # ember drops grow with power ^ this
const QUANTITY_PER_TIER := 0.025   # item quantity +2.5% per tier over 1, up to QUANTITY_MAX
const QUANTITY_MAX := 3.0
const RARITY_PER_TIER := 0.02      # item rarity +2% per tier over 1, up to RARITY_MAX
const RARITY_MAX := 2.0
const CROWD_LEVEL := 24     # pack sizes, ambushes, altar waves and the elite chance stop growing at this area level


## the monster life multiplier of a tier (1 at T1)
static func power(tier: int) -> float:
	var t := clamp_tier(tier)
	var lg := 0.0
	var from := 1
	for st in POWER_STEPS:
		var n := clampi(mini(t, st[0]) - from, 0, TIER_LIMIT)
		lg += n * log(float(st[1]))
		from = maxi(from, st[0])
	return POWER_MAX if lg >= log(POWER_MAX) else minf(exp(lg), POWER_MAX)


static func life_mult(tier: int) -> float:
	return power(tier)


static func dmg_mult(tier: int) -> float:
	return pow(power(tier), POWER_DMG)


static func gold_mult(tier: int) -> float:
	return pow(power(tier), GOLD_SHARE)


## extra item quantity (a multiplier on the drop chances and counts) and item rarity a tier gives
static func quantity_bonus(tier: int) -> float:
	return minf(QUANTITY_PER_TIER * (clamp_tier(tier) - 1), QUANTITY_MAX)


static func rarity_bonus(tier: int) -> float:
	return minf(RARITY_PER_TIER * (clamp_tier(tier) - 1), RARITY_MAX)


## a run's effects (Atlas.map_effects, Charms.apply) with what its tier adds: monster life and damage, ember,
## item quantity and rarity
static func apply_tier(fx: Dictionary, tier: int) -> Dictionary:
	fx.life = fx.get("life", 1.0) * life_mult(tier)
	fx.dmg = fx.get("dmg", 1.0) * dmg_mult(tier)
	fx.gold = fx.get("gold", 1.0) * gold_mult(tier)
	fx.quantity = fx.get("quantity", 1.0) + quantity_bonus(tier)
	fx.rarity = fx.get("rarity", 0.0) + rarity_bonus(tier)
	fx.tier = clamp_tier(tier)
	return fx


## an area level as far as crowd sizes go
static func crowd(level: int) -> int:
	return clampi(level, 1, CROWD_LEVEL)


static func add(owned: Dictionary, k: String, n := 1) -> void:
	if not valid(k) or n == 0:
		return
	var left := int(owned.get(k, 0)) + n
	if left > 0:
		owned[k] = left
	else:
		owned.erase(k)


static func count(owned: Dictionary) -> int:
	var n := 0
	for k in owned:
		n += int(owned[k])
	return n


## the tiers of map `id` held in `owned`, lowest first
static func tiers_of(owned: Dictionary, id: String) -> Array:
	var out := []
	for k in owned:
		var c := parse(k)
		if not c.is_empty() and c.id == id and int(owned[k]) > 0:
			out.append(c.tier)
	out.sort()
	return out


## only valid keys with positive whole counts
static func normalize(d) -> Dictionary:
	var out := {}
	if typeof(d) != TYPE_DICTIONARY:
		return out
	for k in d:
		var v = d[k]
		if valid(str(k)) and (v is int or v is float) and int(v) > 0:
			out[str(k)] = int(v)
	return out


## how many modifiers a map of this tier rolls
static func mod_count(tier: int) -> Vector2i:
	if tier >= 11:
		return Vector2i(2, 3)
	if tier >= 6:
		return Vector2i(1, 2)
	if tier >= 3:
		return Vector2i(0, 1)
	return Vector2i(0, 0)


## worth in ember shards (the map device's price for BUY_TIER, the exchange's base price). It follows the ember a run
## of the tier brings in (area level × gold_mult), and more on top the deeper it is (× (1 + VALUE_GROWTH × (tier - 1))),
## so it rises every tier and stays a sane int up to TIER_LIMIT
const VALUE_BASE := 40.0
const VALUE_GROWTH := 0.15
const SELL_SHARE := 0.4     # the map device buys a map item back for this share of its value
static func value(tier: int) -> int:
	var t := clamp_tier(tier)
	return roundi(VALUE_BASE * t * gold_mult(t) * (1.0 + VALUE_GROWTH * (t - 1)))


## what the map device pays for one map item of `tier`
static func sell_price(tier: int) -> int:
	return maxi(1, roundi(value(tier) * SELL_SHARE))


static func drop_chance(boss: bool, elite: bool) -> float:
	return 1.0 if boss else (0.1 if elite else 0.008)


## a dropped map: any of the fifty, around the tier of the map it fell in (a boss drops a step or two higher more often)
static func roll(tier: int, boss := false, elite := false) -> String:
	var r := randf()
	var d := 0
	if boss:
		d = 2 if r < 0.1 else (1 if r < 0.45 else 0)
	elif elite:
		d = 1 if r < 0.25 else (-1 if r < 0.35 else 0)
	else:
		d = 1 if r < 0.1 else (-1 if r < 0.35 else 0)
	return key(LIST.pick_random().id, clamp_tier(tier + d))


## a multiplier for the UI: "×2.83", "×41.5", "×1,234"
static func mult_text(x: float) -> String:
	if not is_finite(x):
		return "×∞"
	if x < 10.0:
		return "×%.2f" % x
	if x < 100.0:
		return "×%.1f" % x
	return "×" + num(roundi(minf(x, POWER_MAX)))


## what a tier does, for the map device and the tooltips
static func tier_lines(tier: int) -> Array:
	var t := clamp_tier(tier)
	return [["Tier %d　・　エリアレベル %d" % [t, level_of(t)], Color("#f0d8a0"), 15],
		["モンスターのライフ %s　ダメージ %s" % [mult_text(life_mult(t)), mult_text(dmg_mult(t))], Color("#ff9a7a"), 13],
		["アイテム数量 +%d%%　レア度 +%d%%　灰燼の欠片 %s" % [roundi(quantity_bonus(t) * 100), roundi(rarity_bonus(t) * 100), mult_text(gold_mult(t))],
			Color("#8fd18f"), 13],
		["価値 ◆ %s（地図装置の買取 ◆ %s）" % [num(value(t)), num(sell_price(t))], Color("#f0e0c0"), 13]]


## a map item's tooltip
static func lines(k: String) -> Array:
	var c := parse(k)
	if c.is_empty():
		return [[k, COLOR, 16]]
	var el := element(c.def)
	var out := [[name_of(k), el.color, 16], ["%s属性　・　%s" % [el.name, c.def.shape], Color("#a89878"), 13]]
	out.append_array(tier_lines(c.tier))
	return out


## a whole number with thousands separators ("1,234,567"), for the big values of deep tiers
static func num(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out
