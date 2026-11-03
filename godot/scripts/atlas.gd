class_name Atlas
extends RefCounted
## Expedition atlas progress: the map items owned, which of the fifty maps are cleared and the best tier,
## the modifiers rolled for each map item, and the effects a run gets from them. Plain data so it saves as JSON.

const STARTER := {"ash:1": 1, "ember:1": 1, "frost:1": 1, "thunder:1": 1, "rot:1": 1}   # a new character's maps, one per element
# area levels of the old ten-node atlas, for saves from before the fifty maps (their best clear becomes the best tier)
const LEGACY_LEVELS := {"ash": 1, "bone": 2, "wail": 3, "ember": 4, "obsidian": 5, "forge": 6, "frost": 7, "cathedral": 8, "grave": 9}

var cleared: Array = []  # map ids cleared at least once, at any tier
var best := 0           # highest tier cleared
var abyss := 0          # Ember Abyss clears from before the fifty maps: kept as atlas passive points
var mods := {}          # map item key -> rolled modifier keys, rolled when first looked at and kept until used
var maps := STARTER.duplicate()   # map items owned: "<map id>:<tier>" -> n (Maps)
var sel := "ash"
var sel_tier := 1
var passives := {}      # passive id -> rank


func is_cleared(id: String) -> bool:
	return id in cleared


func owns(id: String, tier: int) -> bool:
	return int(maps.get(Maps.key(id, tier), 0)) > 0


## the lowest tier of map `id` owned, or 0
func lowest_tier(id: String) -> int:
	var t := Maps.tiers_of(maps, id)
	return t[0] if not t.is_empty() else 0


func roll_mods(tier: int) -> Array:
	var r := Maps.mod_count(tier)
	var pool: Array = Data.MAP_MODS.map(func(m): return m.k)
	pool.shuffle()
	return pool.slice(0, randi_range(r.x, r.y))


## the modifiers the map item `id` at `tier` will bring (rolled once, rerollable with compass shards)
func item_mods(id: String, tier: int) -> Array:
	var k := Maps.key(id, tier)
	if not mods.has(k):
		mods[k] = roll_mods(tier)
	return mods[k]


## use up one map item; its rolled modifiers go with it. Returns the modifiers, or null when not owned
func use_map(id: String, tier: int) -> Variant:
	if not owns(id, tier):
		return null
	var m: Array = item_mods(id, tier).duplicate()
	Maps.add(maps, Maps.key(id, tier), -1)
	mods.erase(Maps.key(id, tier))
	return m


func clear(id: String, tier: int) -> bool:
	var first := not is_cleared(id)
	if first:
		cleared.append(id)
	best = maxi(best, tier)
	return first


## multipliers for enemies and loot from a set of modifier keys
static func effects(keys: Array) -> Dictionary:
	var fx := {"life": 1.0, "dmg": 1.0, "speed": 1.0, "swarm": 1.0, "elite": 1.0, "rarity": 0.0, "quantity": 1.0,
		"gold": 1.0, "xp": 1.0, "legend": 0.0}
	for k in keys:
		var m := Data.map_mod(k)
		for f in ["life", "dmg", "speed", "swarm", "elite"]:
			if m.has(f):
				fx[f] *= m[f]
		fx.rarity += 0.3
		fx.quantity += 0.15
	return fx


## the modifiers' effects plus what the atlas passives add to every run
func map_effects(keys: Array) -> Dictionary:
	var fx := effects(keys)
	fx.gold += val("gold") / 100.0
	fx.rarity += val("find") / 100.0 + keys.size() * val("prowess") / 100.0
	fx.quantity += val("plenty") / 100.0
	fx.legend = val("relic") / 100.0
	fx.swarm *= 1.0 + val("horde") / 100.0
	fx.elite *= 1.0 + val("hunt") / 100.0
	fx.xp += val("train") / 100.0
	return fx


# ---- atlas passives ----
func rank(id: String) -> int:
	return int(passives.get(id, 0))


func val(id: String) -> float:
	return rank(id) * Data.passive(id).per


## one point per map cleared for the first time (plus old Ember Abyss clears)
func points_total() -> int:
	return cleared.size() + abyss


func points_spent() -> int:
	var n := 0
	for id in passives:
		n += int(passives[id])
	return n


func points_free() -> int:
	return points_total() - points_spent()


func passive_unlocked(id: String) -> bool:
	var n := Data.passive(id)
	return n.tier == 0 or rank(n.branch.nodes[n.tier - 1].id) > 0


func reset_price() -> int:
	return points_spent() * 30


## level of the hideout (and its shop): the area level of the highest tier cleared so far
func hideout_level() -> int:
	return maxi(1, Maps.level_of(best))


func to_dict() -> Dictionary:
	return {"cleared": cleared, "best": best, "abyss": abyss, "mods": mods, "maps": maps, "sel": sel, "sel_tier": sel_tier, "passives": passives}


func from_dict(d: Dictionary) -> void:
	cleared = Array(d.get("cleared", [])).filter(func(id): return not Maps.def(str(id)).is_empty())
	abyss = int(d.get("abyss", 0))
	if d.has("best"):
		best = Maps.tier_from(d.best)
	else:   # a save from the ten-node atlas: its deepest clear is the best tier, and it gets a map of each element there
		best = 0
		for id in d.get("cleared", []):
			best = maxi(best, int(LEGACY_LEVELS.get(id, 0)))
		if abyss > 0:
			best = maxi(best, 9 + abyss)
		best = mini(best, Maps.TIER_LIMIT)
	mods = {}
	var md = d.get("mods", {})
	if typeof(md) == TYPE_DICTIONARY:
		for k in md:
			if Maps.valid(str(k)) and typeof(md[k]) == TYPE_ARRAY:
				mods[str(k)] = Array(md[k]).filter(func(x): return not Data.map_mod(str(x)).is_empty())
	if d.has("maps"):
		maps = Maps.normalize(d.maps)
	else:
		maps = {}
		for k in STARTER:
			Maps.add(maps, Maps.key(Maps.parse(k).id, maxi(1, best)))
	sel = str(d.get("sel", "ash"))
	if Maps.def(sel).is_empty():
		sel = "ash"
	sel_tier = Maps.clamp_tier(Maps.tier_from(d.get("sel_tier", 1)))
	passives = {}
	var pd: Dictionary = d.get("passives", {})
	for id in pd:
		var n := Data.passive(id)
		if not n.is_empty():
			passives[id] = clampi(int(pd[id]), 0, n.max)
