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


static func generate(ilvl: int, boost := 0.0, force_rarity := -1, force_slot := "", force_unique := "", force_base := "") -> Dictionary:
	var rarity := force_rarity if force_rarity >= 0 else roll_rarity(boost)
	var slot: String = force_slot if force_slot != "" else Data.SLOTS.pick_random()
	var legend := {}
	var base: Dictionary
	if rarity == 3:
		var pool := Data.LEGENDARY.filter(func(l): return (force_slot == "" or l.slot == force_slot) and (force_unique == "" or l.name == force_unique) 			and (force_base == "" or base_name(l.slot, l.base) == force_base))
		legend = pick_legend(pool)
		slot = legend.slot
		var bases: Array = Data.BASES[slot]
		base = bases[mini(legend.base, bases.size() - 1)]
	else:
		var named: Array = Data.BASES[slot].filter(func(b): return b.name == force_base)
		base = named[0] if not named.is_empty() else Data.BASES[slot].pick_random()
	_uid += 1
	var it := {"uid": "%d_%d" % [Time.get_ticks_msec(), _uid], "slot": slot, "base": base.name, "rarity": rarity, "ilvl": ilvl,
		"mods": {}, "implicit": base.get("implicit", {}).duplicate()}
	var grow := 1.0 + ilvl * 0.22
	if rarity == 3:
		it.name = legend.name
	if slot == "weapon":
		var boost_l := 1.25 * Data.unique_pow(legend.name) if rarity == 3 else 1.0
		it.min = roundi(base.min * grow * boost_l)
		it.max = roundi(base.max * grow * boost_l)
		it.aps = base.aps
	if base.has("armor"):
		it.armor = roundi(base.armor * (1.0 + ilvl * 0.2))
	if legend.has("mods"):
		for k in legend.mods:
			it.mods[k] = roll_fixed(it, k, legend.mods[k])
	else:
		add_affixes(it, randi_range(Data.RARITY[rarity].aff[0], Data.RARITY[rarity].aff[1]))
	if rarity == 3:
		for k in ["effect", "desc", "flavor"]:
			if legend.has(k):
				it[k] = legend[k]
	else:
		name_item(it)
	return it


## the name of base `i` of the slot (a unique's `base` index, clamped like generate does)
static func base_name(slot: String, i: int) -> String:
	var bases: Array = Data.BASES[slot]
	return bases[mini(i, bases.size() - 1)].name


## one unique from the pool, the rarer tiers less often (Data.UNIQUE_TIERS weights)
static func pick_legend(pool: Array) -> Dictionary:
	var total := 0.0
	for l in pool:
		total += Data.unique_weight(l.name)
	var roll := randf() * total
	for l in pool:
		roll -= Data.unique_weight(l.name)
		if roll <= 0.0:
			return l
	return pool.back()


static func roll_value(it: Dictionary, a: Dictionary) -> int:
	return value_at(it, a, randf())


## the affix value at `t` of the way from its least (0) to its most (1); ModRange reads the range from it
static func value_at(it: Dictionary, a: Dictionary, t: float) -> int:
	var v: float = (a.min + t * (a.max - a.min)) * (1.0 + it.ilvl * a.sc) * (1.2 * Data.unique_pow(it.name) if it.rarity == 3 else 1.0)
	return maxi(1, roundi(v))


## a unique's own stat line: its [min, max] (negative for a drawback) grown with item level like the affix,
## the positive ones scaled by the unique's tier
static func roll_fixed(it: Dictionary, k: String, r: Array) -> int:
	return fixed_at(it, k, r, randf())


static func fixed_at(it: Dictionary, k: String, r: Array, t: float) -> int:
	var v: float = (r[0] + t * (r[1] - r[0])) * (1.0 + it.ilvl * Data.affix(k).sc)
	if r[0] > 0:
		v *= Data.unique_pow(it.name)
	return roundi(v) if roundi(v) != 0 else signi(r[0])


## `n` new affixes the slot allows, none it has already, the rarer ones (Data.AFFIXES `w`) less often
static func add_affixes(it: Dictionary, n: int) -> void:
	var pool := Data.AFFIXES.filter(func(a): return it.slot in a.slots and not it.mods.has(a.k))
	for i in mini(n, pool.size()):
		var total := 0.0
		for a in pool:
			total += a.w
		var roll := randf() * total
		var pick: Dictionary = pool.back()
		for a in pool:
			roll -= a.w
			if roll <= 0.0:
				pick = a
				break
		pool.erase(pick)
		it.mods[pick.k] = roll_value(it, pick)


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
			it.erase("special")
			name_item(it)
		"divine":
			if affix_count(it) == 0: return "オプションのあるアイテムにのみ使えます"
			var fixed: Dictionary = Data.legend(it.name).get("mods", {}) if r == 3 else {}
			for key in it.mods.keys():
				it.mods[key] = roll_fixed(it, key, fixed[key]) if fixed.has(key) else roll_value(it, Data.affix(key))
		"brand":
			if r != 2: return "レアアイテムにのみ使えます"
			brand(it)
		_:
			return "このカレンシーはアイテムに使えません"
	return ""


## carve a special modifier into a rare item, never the one it already has; it grows with item level like an affix
static func brand(it: Dictionary, k := "") -> void:
	var old: String = it.get("special", {}).get("k", "")
	var pool := Data.SPECIAL_MODS.filter(func(m): return m.k != old)
	var m: Dictionary = Data.special_mod(k) if k != "" else pool.pick_random()
	it.special = {"k": m.k, "v": special_at(it, m, randf())}


static func special_at(it: Dictionary, m: Dictionary, t: float) -> int:
	return maxi(1, roundi((m.min + t * (m.max - m.min)) * (1.0 + it.ilvl * m.sc)))


## the stats a special modifier gives
static func special_stats(it: Dictionary) -> Dictionary:
	var out := {}
	var sp: Dictionary = it.get("special", {})
	var m := Data.special_mod(sp.get("k", ""))
	for k in m.get("stats", {}):
		out[k] = m.stats[k] * int(sp.v)
	return out


static func sell_price(it: Dictionary) -> int:
	var tier := pow(2.0, Data.unique_tier(it.name)) if int(it.rarity) == 3 else 1.0
	return roundi((3 + it.ilvl * 2) * (1 + it.rarity * 2) * tier)


# =================== merchant ===================
const EMBER_PER_CHAOS := 250
static var discount := 1.0     # from the "merchant's favor" atlas passive


## what the merchant asks for a piece of gear: the sell price five times over, times the shop's price knob and
## a little more for every line; never under twice the sell price however far it is haggled down
static func buy_price(it: Dictionary) -> int:
	var lines_mult := 1.0 + 0.12 * affix_count(it)
	return maxi(sell_price(it) * 2, roundi(sell_price(it) * 5 * Data.SHOP_PRICE * lines_mult * discount))


static func potion_price(level: int) -> int:
	return roundi((15 + level * 8) * discount)


static func reroll_price(level: int) -> int:
	return 60 + level * 30


## the merchant's fixed currency price, the ceiling over the exchange: 250 ember a chaos at the league's rates
static func currency_price(c: Dictionary, league: String) -> int:
	return roundi(Market.price(league, c.k) * EMBER_PER_CHAOS * discount)


## a skill gem or support gem from the merchant: dearer the more level it needs
static func gem_price(lvl: int) -> int:
	return roundi((300 + 45 * lvl) * discount)


## a rune tablet: dearer with its size, level and carved lines; never under twice what breaking it pays
static func tablet_price(t: Dictionary) -> int:
	var v := Tablets.shard_value(t)
	return maxi(v * 2, roundi(v * 4 * Data.SHOP_PRICE * (1.0 + 0.25 * t.mods.size()) * discount))


## a ジュエル or リングジュエル: dearer with its rarity, level and lines (a リングジュエル's notables); never under twice what breaking it pays
static func jewel_price(j: Dictionary) -> int:
	var v := Jewels.shard_value(j)
	var n: int = j.notables.size() if Jewels.is_ring(j) else j.mods.size()
	return maxi(v * 2, roundi(v * 4 * Data.SHOP_PRICE * (1.0 + 0.15 * n) * discount))


## an ember shell: its base value (higher with the tier) times the shop's price knob
static func charm_price(id: String) -> int:
	return roundi(Charms.value(id) * Data.SHOP_PRICE * discount)


## the merchant's stock, a little above the hideout level: SHOP_GEAR_PER_SLOT pieces of every slot in every rarity,
## plus rune tablets, ジュエル and リングジュエル, and ember shells {id: count} in a mix of tiers
static func gen_shop(level: int) -> Dictionary:
	var stock := []
	var w: Array = Data.SHOP_GEAR_RARITY
	var total: float = w.reduce(func(a, b): return a + b, 0.0)
	for slot in Data.SLOTS:
		for i in Data.SHOP_GEAR_PER_SLOT:
			var roll := randf() * total
			var r := 0
			while r < 3 and roll > w[r]:
				roll -= w[r]
				r += 1
			stock.append(generate(level + randi_range(0, 2), 1.0, r, slot))
	var shop := {"level": level, "items": stock}
	shop.merge(gen_wares(level), true)
	return shop


## the merchant's tablets, jewels and ember shells
static func gen_wares(level: int) -> Dictionary:
	var tablets := []
	for i in Data.SHOP_TABLETS:
		tablets.append(Tablets.generate(level + randi_range(0, 2), "", randi_range(0, 2)))
	var jewels := []
	for i in Data.SHOP_JEWELS:
		jewels.append(Jewels.generate(level + randi_range(0, 2), 1 + int(randf() < 0.4)))
	for i in Data.SHOP_RINGS:
		jewels.append(Jewels.generate_ring(level + randi_range(0, 2)))
	var charms := {}
	for i in Data.SHOP_CHARMS:
		Charms.add(charms, Charms.roll(level + 10))
	return {"tablets": tablets, "jewels": jewels, "charms": charms}


## tooltip lines: [text, color, size]
static func lines(it: Dictionary) -> Array:
	var out := []
	var rc: Color = Data.RARITY[it.rarity].color
	out.append([it.name, rc, 18])
	if int(it.rarity) == 3:
		var t: Dictionary = Data.UNIQUE_TIERS[Data.unique_tier(it.name)]
		out.append(["希少度：%s" % t.name, t.color, 13])
	out.append(["%s %s" % [Data.RARITY[it.rarity].name, Data.SLOT_INFO[it.slot].name] + ("（%s）" % it.base if it.rarity >= 2 else ""), Color("#9a9080"), 13])
	out.append(["アイテムレベル %d" % it.ilvl, Color("#7a7266"), 13])
	if it.slot == "weapon":
		var f: int = it.mods.get("flat_dmg", 0)
		var dmg := "ダメージ %d–%d" % [it.min + f, it.max + f]
		var fr := ModRange.item(it, "flat_dmg") if it.mods.has("flat_dmg") else {}
		# two numbers that each roll with the flat damage line: [a–b]–[c–d]
		out.append([dmg, Color.WHITE, 14, dmg + ("  [%d–%d]–[%d–%d]" % [it.min + fr.lo, it.min + fr.hi, it.max + fr.lo, it.max + fr.hi] if not fr.is_empty() and fr.lo != fr.hi else "")])
		out.append(["攻撃/秒 %.2f" % it.aps, Color.WHITE, 14])
	if it.has("armor"):
		out.append(["アーマー %d" % it.armor, Color.WHITE, 14])
	for k in it.implicit:
		out.append(ModRange.fixed(Data.affix(k).fmt % it.implicit[k], Color("#b8b0a0"), 14))
	for k in it.mods:
		var v: int = it.mods[k]
		out.append(ModRange.line((Data.affix(k).fmt % v).replace("+-", "-"), Color("#8fb4ff") if v >= 0 else Color("#ff7a6a"), 14, ModRange.item(it, k)))
	if it.has("special"):
		var m := Data.special_mod(it.special.k)
		out.append(ModRange.line("✠ %s：%s" % [m.name, m.fmt % it.special.v], Data.currency("brand").color, 14, ModRange.special(it)))
	if it.has("desc"):
		out.append([it.desc, Color("#ff9a4a"), 14])
	if it.has("flavor"):
		out.append([it.flavor, Color("#a08a6a"), 12])
	return out


## JSON turns every number into a float; put the integer fields back
static func normalize(it: Dictionary) -> Dictionary:
	for k in ["rarity", "ilvl", "min", "max", "armor"]:
		if it.has(k):
			it[k] = int(it[k])
	for src in ["mods", "implicit"]:
		var d: Dictionary = it.get(src, {})
		# a line whose affix no longer exists (an older version's) has no text or range to show: drop it
		for k in d.keys():
			if Data.affix(str(k)).is_empty():
				d.erase(k)
			else:
				d[k] = int(d[k])
	if it.has("special"):
		if typeof(it.special) == TYPE_DICTIONARY and not Data.special_mod(str(it.special.get("k", ""))).is_empty():
			it.special = {"k": str(it.special.k), "v": int(it.special.get("v", 1))}
		else:
			it.erase("special")
	return it
