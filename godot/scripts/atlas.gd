class_name Atlas
extends RefCounted
## Expedition atlas progress: which map nodes are cleared or unlocked, their rolled
## modifiers, and the effects a run gets from them. Plain data so it saves as JSON.

var cleared: Array = []
var abyss := 0          # Ember Abyss clears; each one deepens it
var mods := {}          # node id -> rolled modifier keys
var sel := "ash"
var passives := {}      # passive id -> rank


func node_level(n: Dictionary) -> int:
	return n.level + abyss if n.get("endless", false) else n.level


func node_theme(n: Dictionary) -> int:
	return abyss % Data.THEMES.size() if n.get("endless", false) else n.theme


func is_cleared(n: Dictionary) -> bool:
	return n.id in cleared


func is_unlocked(n: Dictionary) -> bool:
	if n.id == "ash" or is_cleared(n):
		return true
	for o in Data.ATLAS_NODES:
		if is_cleared(o) and n.id in o.links:
			return true
	return false


func roll_mods(n: Dictionary) -> Array:
	var L := node_level(n)
	var count := randi_range(2, 3) if n.get("endless", false) else (randi_range(1, 2) if L >= 6 else (randi_range(0, 1) if L >= 3 else 0))
	var pool: Array = Data.MAP_MODS.map(func(m): return m.k)
	pool.shuffle()
	return pool.slice(0, count)


func node_mods(n: Dictionary) -> Array:
	if not mods.has(n.id):
		mods[n.id] = roll_mods(n)
	return mods[n.id]


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


## level of the hideout (and its shop): the highest map cleared so far
func hideout_level() -> int:
	var best := 1
	for n in Data.ATLAS_NODES:
		if is_cleared(n):
			best = maxi(best, node_level(n))
	return best


func to_dict() -> Dictionary:
	return {"cleared": cleared, "abyss": abyss, "mods": mods, "sel": sel, "passives": passives}


func from_dict(d: Dictionary) -> void:
	cleared = d.get("cleared", [])
	abyss = int(d.get("abyss", 0))
	mods = d.get("mods", {})
	sel = d.get("sel", "ash")
	passives = {}
	var pd: Dictionary = d.get("passives", {})
	for id in pd:
		var n := Data.passive(id)
		if not n.is_empty():
			passives[id] = clampi(int(pd[id]), 0, n.max)
