class_name Items
extends RefCounted
## Item generation, currency crafting and pricing. Items are plain Dictionaries so they save as JSON.

static var _uid := 0


static func roll_rarity(boost: float) -> int:
	var w: Array[float] = [Data.RARITY[0].w, Data.RARITY[1].w * (1.0 + boost), Data.RARITY[2].w * (1.0 + boost * 2.0), Data.RARITY[3].w * (1.0 + boost * 3.0)]
	var roll := randf() * (w[0] + w[1] + w[2] + w[3])
	for i in 4:
		roll -= w[i]
		if roll <= 0.0:
			return i
	return 0


static func generate(ilvl: int, boost := 0.0, force_rarity := -1, force_slot := "") -> Dictionary:
	var rarity := force_rarity if force_rarity >= 0 else roll_rarity(boost)
	var slot: String = force_slot if force_slot != "" else Data.SLOTS.pick_random()
	var legend := {}
	var base: Dictionary
	if rarity == 3:
		var pool := Data.LEGENDARY.filter(func(l): return force_slot == "" or l.slot == force_slot)
		legend = pool.pick_random()
		slot = legend.slot
		var bases: Array = Data.BASES[slot]
		base = bases[mini(legend.base, bases.size() - 1)]
	else:
		base = Data.BASES[slot].pick_random()
	_uid += 1
	var it := {"uid": "%d_%d" % [Time.get_ticks_msec(), _uid], "slot": slot, "base": base.name, "rarity": rarity, "ilvl": ilvl,
		"mods": {}, "implicit": base.get("implicit", {}).duplicate()}
	var grow := 1.0 + ilvl * 0.22
	if slot == "weapon":
		var boost_l := 1.25 if rarity == 3 else 1.0
		it.min = roundi(base.min * grow * boost_l)
		it.max = roundi(base.max * grow * boost_l)
		it.aps = base.aps
	if base.has("armor"):
		it.armor = roundi(base.armor * (1.0 + ilvl * 0.2))
	add_affixes(it, randi_range(Data.RARITY[rarity].aff[0], Data.RARITY[rarity].aff[1]))
	if rarity == 3:
		it.name = legend.name
		it.effect = legend.effect
		it.desc = legend.desc
	else:
		name_item(it)
	return it


static func roll_value(it: Dictionary, a: Dictionary) -> int:
	var v: float = (a.min + randf() * (a.max - a.min)) * (1.0 + it.ilvl * a.sc) * (1.2 if it.rarity == 3 else 1.0)
	return maxi(1, roundi(v))


static func add_affixes(it: Dictionary, n: int) -> void:
	var pool := Data.AFFIXES.filter(func(a): return it.slot in a.slots and not it.mods.has(a.k))
	pool.shuffle()
	for i in mini(n, pool.size()):
		it.mods[pool[i].k] = roll_value(it, pool[i])


static func name_item(it: Dictionary) -> void:
	match int(it.rarity):
		0:
			it.name = it.base
		1:
			var first: String = it.mods.keys()[0] if not it.mods.is_empty() else ""
			it.name = (Data.affix(first).word if first != "" else "") + it.base
		2:
			it.name = Data.RARE_A.pick_random() + Data.RARE_B.pick_random()


# =================== crafting ===================
static func affix_count(it: Dictionary) -> int:
	return it.mods.size()


## apply a currency; returns an error message, or "" on success
static func craft(k: String, it: Dictionary) -> String:
	var r := int(it.rarity)
	match k:
		"transmute":
			if r != 0: return "ノーマルアイテムにのみ使えます"
			it.rarity = 1
			add_affixes(it, randi_range(1, 2))
			name_item(it)
		"ascend":
			if r != 1: return "マジックアイテムにのみ使えます"
			it.rarity = 2
			add_affixes(it, randi_range(3, 4) - affix_count(it))
			name_item(it)
		"chaos":
			if r != 1 and r != 2: return "マジック・レアアイテムにのみ使えます"
			it.mods = {}
			add_affixes(it, randi_range(Data.RARITY[r].aff[0], Data.RARITY[r].aff[1]))
			name_item(it)
		"whet":
			if r != 1 and r != 2: return "マジック・レアアイテムにのみ使えます"
			if affix_count(it) >= Data.RARITY[r].aff[1]: return "これ以上オプションを追加できません"
			var before := affix_count(it)
			add_affixes(it, 1)
			if affix_count(it) == before: return "追加できるオプションがありません"
		"purify":
			if r != 1 and r != 2: return "マジック・レアアイテムにのみ使えます"
			it.rarity = 0
			it.mods = {}
			name_item(it)
		"divine":
			if affix_count(it) == 0: return "オプションのあるアイテムにのみ使えます"
			for key in it.mods.keys():
				it.mods[key] = roll_value(it, Data.affix(key))
		_:
			return "このカレンシーはアイテムに使えません"
	return ""


static func sell_price(it: Dictionary) -> int:
	return roundi((3 + it.ilvl * 2) * (1 + it.rarity * 2))


## tooltip lines: [text, color, size]
static func lines(it: Dictionary) -> Array:
	var out := []
	var rc: Color = Data.RARITY[it.rarity].color
	out.append([it.name, rc, 18])
	out.append(["%s %s" % [Data.RARITY[it.rarity].name, Data.SLOT_INFO[it.slot].name] + ("（%s）" % it.base if it.rarity >= 2 else ""), Color("#9a9080"), 13])
	out.append(["アイテムレベル %d" % it.ilvl, Color("#7a7266"), 13])
	if it.slot == "weapon":
		var f: int = it.mods.get("flat_dmg", 0)
		out.append(["ダメージ %d–%d" % [it.min + f, it.max + f], Color.WHITE, 14])
		out.append(["攻撃/秒 %.2f" % it.aps, Color.WHITE, 14])
	if it.has("armor"):
		out.append(["アーマー %d" % it.armor, Color.WHITE, 14])
	for k in it.implicit:
		out.append([Data.affix(k).fmt % it.implicit[k], Color("#b8b0a0"), 14])
	for k in it.mods:
		out.append([Data.affix(k).fmt % it.mods[k], Color("#8fb4ff"), 14])
	if it.has("desc"):
		out.append([it.desc, Color("#ff9a4a"), 14])
	return out


## JSON turns every number into a float; put the integer fields back
static func normalize(it: Dictionary) -> Dictionary:
	for k in ["rarity", "ilvl", "min", "max", "armor"]:
		if it.has(k):
			it[k] = int(it[k])
	for src in ["mods", "implicit"]:
		var d: Dictionary = it.get(src, {})
		for k in d:
			d[k] = int(d[k])
	return it
