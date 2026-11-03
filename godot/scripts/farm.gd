class_name Farm
## Cinder altars (燼火の祭壇): the in-map farming event. Dormant altars sit in a few rooms of every map;
## kindling one (with an optional vow that raises its rewards) calls waves of cinder-touched enemies
## around it, the last wave led by a guardian. Clearing them pays cinder crystals (燼晶), which the
## hideout's cinder forge trades for loot, and renown (位階) that grows the event and opens the forge.
## Progress is per league, kept in Profiles.data.farm[league] next to the league stash; when a season
## ends its crystals and beacons move to standard and standard keeps the higher renown (see `migrate`).

const KEY := "cinder"
const CURRENCY := {"k": KEY, "name": "燼晶", "icon": "❖", "color": Color("#ff6a3a"), "desc": "燼火の祭壇で得られる結晶。隠れ家の燼火の炉で報酬と交換する。"}
const COLOR := Color("#ff6a3a")
const RADIUS := 9.0            # m: waves come in around the altar, and leaving this far (x2) lets it die out
const WAVES := 3
const WAVE_TIME := 14.0        # s: the next wave comes after this even if the last one is still standing
const TRIAL_TIME := 50.0       # s: 灼刻の誓約 — every wave must fall within this
const MAX_RANK := 10

# a vow is chosen when the altar is kindled: harder waves for richer rewards
const VOWS := [
	{"id": "", "name": "誓約なし", "desc": "そのまま点火する。", "rank": 0},
	{"id": "fury", "name": "烈火の誓約", "desc": "敵のライフ・ダメージ +40%\n燼晶 +60%、位階 +1", "rank": 0, "life": 1.4, "dmg": 1.4, "cinder": 1.6, "renown": 1},
	{"id": "horde", "name": "群火の誓約", "desc": "波が1つ増え、最後の波に守り手がもう1体\n燼晶 +40%、報酬アイテム +2", "rank": 1, "waves": 1, "guards": 1, "cinder": 1.4, "items": 2},
	{"id": "trial", "name": "灼刻の誓約", "desc": "%d秒以内にすべての波を倒す（失敗すると報酬なし）\n報酬アイテム +2・レア度 +150%%、位階 +2" % int(TRIAL_TIME), "rank": 2, "timer": TRIAL_TIME, "items": 2, "rarity": 1.5, "renown": 2},
]

# the cinder forge in the hideout: what crystals buy; `rank` is the renown it needs
const OFFERS := [
	{"id": "rare", "name": "燼火の装具", "desc": "エリアレベルのレアアイテム1つ", "cost": 25, "rank": 0},
	{"id": "chaos", "name": "混沌の残光 ×3", "desc": "カレンシー", "cost": 30, "rank": 0},
	{"id": "gem", "name": "未入手のサポートジェム", "desc": "持っていないサポートジェム1つ", "cost": 45, "rank": 1},
	{"id": "beacon", "name": "燼火の導標", "desc": "次に入るマップに祭壇が2つ増える（リーグで共有）", "cost": 20, "rank": 2},
	{"id": "divine", "name": "神秘の核", "desc": "カレンシー", "cost": 60, "rank": 3},
	{"id": "legend", "name": "燼に眠る秘宝", "desc": "レジェンド（ユニーク）アイテム1つ", "cost": 120, "rank": 4},
]


# =================== league state ===================
static func fresh() -> Dictionary:
	return {"cinder": 0, "renown": 0, "lit": 0, "beacons": 0}


## the league's farm progress, made on first use
static func state(league: String, d := Profiles.data) -> Dictionary:
	if typeof(d.get("farm")) != TYPE_DICTIONARY:
		d.farm = {}
	if typeof(d.farm.get(league)) != TYPE_DICTIONARY:
		d.farm[league] = fresh()
	return d.farm[league]


## fill in anything an older or hand-edited file lacks (JSON turns ints into floats)
static func normalize(d: Dictionary) -> void:
	if typeof(d.get("farm")) != TYPE_DICTIONARY:
		d.farm = {}
	for lg in d.farm.keys():
		var f = d.farm[lg]
		if typeof(f) != TYPE_DICTIONARY:
			d.farm.erase(lg)
			continue
		var base := fresh()
		for k in base:
			base[k] = maxi(0, int(f.get(k, 0)))
		d.farm[lg] = base


## a finished season's crystals and beacons join standard's; standard keeps whichever renown is higher
static func migrate(d: Dictionary, today: String) -> Array:
	var notes := []
	if typeof(d.get("farm")) != TYPE_DICTIONARY:
		return notes
	for lg in d.farm.keys():
		if lg == Profiles.STANDARD or Data.season_running(lg, today):
			continue
		var f: Dictionary = d.farm[lg]
		var std := state(Profiles.STANDARD, d)
		std.cinder += f.cinder
		std.beacons += f.beacons
		std.lit += f.lit
		std.renown = maxi(std.renown, f.renown)
		d.farm.erase(lg)
		if f.cinder > 0 or f.renown > 0:
			notes.append("%s の燼晶 %d 個と燼火の位階をスタンダードに引き継ぎました" % [Data.season(lg).get("name", lg), f.cinder])
	return notes


# =================== renown ===================
## renown points needed to reach `rank` (3, 9, 18, 30, ...)
static func rank_need(rank: int) -> int:
	return 3 * rank * (rank + 1) / 2


static func rank(f: Dictionary) -> int:
	var r := 0
	while r < MAX_RANK and f.renown >= rank_need(r + 1):
		r += 1
	return r


## the share of a map's altars that comes as a second altar, and the crystal bonus, grow with renown
static func extra_altar_chance(f: Dictionary) -> float:
	return minf(0.6, 0.12 * rank(f))


static func cinder_mult(f: Dictionary) -> float:
	return 1.0 + 0.05 * rank(f)


## how many altars a new map gets; uses up the league's beacons
static func altars_for_map(f: Dictionary, roll := randf()) -> int:
	var n := 1 + (1 if roll < extra_altar_chance(f) else 0)
	if f.beacons > 0:
		f.beacons -= 1
		n += 2
	return n


static func vow(id: String) -> Dictionary:
	for v in VOWS:
		if v.id == id:
			return v
	return VOWS[0]


static func offer(id: String) -> Dictionary:
	for o in OFFERS:
		if o.id == id:
			return o
	return {}


# =================== one altar ===================
## the waves of an altar kindled with `vow_id` at area level `level`: [{kind, n}] per wave plus the guardians
static func plan(level: int, vow_id: String) -> Dictionary:
	var v := vow(vow_id)
	var waves := []
	for i in WAVES + int(v.get("waves", 0)):
		waves.append(5 + Maps.crowd(level) / 2 + i * 2)
	return {"waves": waves, "guards": 1 + int(v.get("guards", 0)), "timer": float(v.get("timer", 0.0))}


## what clearing an altar pays: crystals, item count and rarity boost, renown
static func reward(level: int, vow_id: String, f: Dictionary) -> Dictionary:
	var v := vow(vow_id)
	return {"cinder": roundi((10 + level * 3) * float(v.get("cinder", 1.0)) * cinder_mult(f)),
		"items": 2 + int(v.get("items", 0)), "rarity": 1.0 + float(v.get("rarity", 0.0)),
		"renown": 1 + int(v.get("renown", 0))}


## credit a cleared altar to the league; returns true when the renown rank went up
static func credit(f: Dictionary, renown: int) -> bool:
	var r0 := rank(f)
	f.renown += renown
	f.lit += 1
	return rank(f) > r0


## spend crystals at the forge; "" when it went through, else why not
static func buy(f: Dictionary, id: String) -> String:
	var o := offer(id)
	if o.is_empty():
		return "その品はない"
	if rank(f) < o.rank:
		return "燼火の位階 %d が必要" % o.rank
	if f.cinder < o.cost:
		return "燼晶が足りない（%d 必要）" % o.cost
	f.cinder -= o.cost
	return ""
