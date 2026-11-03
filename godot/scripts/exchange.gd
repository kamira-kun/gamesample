class_name Exchange
## The exchange's listing search (#65). Nothing is listed until the player searches; then up to RESULTS listings
## that fit the search are made on the spot: gear, rune tablets, ジュエル, リングジュエル, ember shells, gems, currency
## and map items (#74: priced off Maps.value, so a deeper tier costs more; a map search's `ilvl` is the lowest tier).
## The asked-for lines, base and unique are forced, each line rolled at or over its asked minimum, the rest random.
## A search is seeded by itself, the league, the market tick and the refresh count, so the same search shows the
## same listings until a map is completed or the player asks for fresh ones.
##
## Prices are in chaos (✺), plus the exchange's ember fee (Market.fee):
##   worth × PREMIUM × seller (0.9..1.25) × constraints
## where constraints is the product of the plain filters (base, unique, rarity, slot, item level) and, for the i-th
## asked line, (1 + MOD_BASE × rarity × (1 + QUALITY × q)) × (1 + MOD_STACK × i): `rarity` is how much rarer the line
## is than an average one (affix weight `w`; 刻紋 lines are SPECIAL_RARITY), `q` how far up its range the minimum asks.
## Never under RESALE_GUARD × what selling it back pays, so buying to resell always loses.
##
## A query is a Dictionary: {cat, slot, rarity (-1 any), base (name), unique (name), mods [{k, min}], ilvl (min, 0 any),
## price_min, price_max (0 none)}. A listing: {kind, item (gear/tablet/jewel/ring Dictionary), id (charm/gem/currency
## key), n (count), price, fee, key}.
## Awakened support gems (#63) are listed under gems; an open gem search shows AWAKE_OPEN of them.
## Gem listings carry a gem level `glv` (#68): mostly Lv 1, a few higher; the query's `glv` (0 any) asks for at least it.

const RESULTS := 12
const MAX_MODS := 3
const PREMIUM := 3.0
const MOD_BASE := 0.45
const MOD_STACK := 0.25          # each further asked line costs this much more again
const QUALITY := 1.5
const SPECIAL_RARITY := 5.0
const RARITY_CLAMP := [0.5, 4.0]
const PICK := {"slot": 0.05, "base": 0.15, "rarity": 0.1, "unique": 0.25}
const ILVL_STEP := 0.02          # × per item level asked over the hideout level
const ILVL_SPREAD := 6           # listings are made at the item level asked (or the hideout's) up to this much over
const RESALE_GUARD := 2.0
const ATTEMPTS := 6              # candidates made per listing shown, before the price filter gives up
const CATEGORIES := [["gear", "装備"], ["tablet", "ルーンタブレット"], ["jewel", "ジュエル"], ["ring", "リングジュエル"], ["charm", "コンパス"], ["gem", "ジェム"], ["currency", "カレンシー"], ["map", "遠征地図"]]
const CURRENCY_LOTS := [1, 3, 5, 10, 20]
const CHARM_LOTS := [1, 2, 3]
const AWAKE_OPEN := 2             # awakened gems among an open gem search's listings (any one can be searched by name)
const GEM_LV_ODDS := 0.15         # gem listings above Lv 1 when no gem level is asked for (Lv 2..GEM_LV_TOP)
const GEM_LV_TOP := 6
const GEM_LV_SPREAD := 2          # a listing asked for at least Lv N is Lv N..N+this
const GEM_LV_WORTH := 0.3         # each gem level over 1 adds this share of the gem's worth
const MAP_SPREAD := 3             # a map listing is at the tier asked (or a little under the best cleared) up to this much over
const SP := "sp:"                # mod keys of 刻紋 (special) lines in a query

static var sold := {}            # listing keys bought already, so a search made again doesn't list them twice
static var price_league := ""    # the league the search being made prices currency in


static func empty_query() -> Dictionary:
	return {"cat": "gear", "slot": "", "rarity": -1, "base": "", "unique": "", "mods": [], "ilvl": 0, "glv": 0, "price_min": 0, "price_max": 0}


# =================== what can be asked for ===================
## the base names a category lists in its base filter (gear: of the slot, or all)
static func base_names(cat: String, slot := "") -> Array:
	match cat:
		"gear":
			var out := []
			for s in Data.SLOTS:
				if slot == "" or s == slot:
					out.append_array(Data.BASES[s].map(func(b): return b.name))
			return out
		"tablet":
			return Tablets.SHAPES.map(func(s): return s.name)
		"jewel":
			return Jewels.BASES.map(func(b): return b.name)
		"ring":
			return Jewels.SIZES.map(func(s): return s.name)
		"charm":
			return Charms.all_ids().map(func(id): return Charms.name_of(id))
		"gem":
			var out := []
			for id in Data.SKILL_ORDER:
				out.append(Data.SKILLS[id].name)
			for g in Data.all_supports():
				out.append(g.name)
			return out
		"currency":
			return currency_keys().map(func(k): return Data.currency(k).name)
		"map":
			return Maps.LIST.map(func(m): return m.name)
	return []


## the stat lines a category can be searched by (gear: those the slot can roll, then the 刻紋 lines)
static func mod_keys(cat: String, slot := "") -> Array:
	match cat:
		"gear":
			var out: Array = Data.AFFIXES.filter(func(a): return not a.slots.is_empty() and (slot == "" or slot in a.slots)).map(func(a): return a.k)
			out.append_array(Data.SPECIAL_MODS.map(func(m): return SP + m.k))
			return out
		"tablet":
			return Tablets.MODS.map(func(m): return m.k)
		"jewel":
			return Jewels.AFFIXES.map(func(a): return a.k)
	return []


static func mod_name(k: String) -> String:
	if k.begins_with(SP):
		var m := Data.special_mod(k.trim_prefix(SP))
		return "✠%s（%s）" % [m.name, DataDocs._stat_name(m.fmt)]
	var a := Data.affix(k)
	if not a.is_empty():
		return DataDocs._stat_name(a.fmt)
	return str(PassiveTree.FMT.get(k, k)).replace(" {v}%", "").replace(" {v}/秒", "回復").replace(" {v}", "")


## unique names holding `text`, the rarer tiers first, at most `limit`
static func unique_matches(text: String, limit := 8) -> Array:
	var t := text.strip_edges()
	if t == "":
		return []
	var hits := Data.LEGENDARY.filter(func(l): return t in l.name).map(func(l): return l.name)
	hits.sort_custom(func(a, b): return Data.unique_tier(a) > Data.unique_tier(b))
	return hits.slice(0, limit)


static func currency_keys() -> Array:
	return Market.keys() + ["brand"]


## how much rarer a line is than an average one: 1 for an average gear affix, more for a rarer one
static func mod_rarity(k: String) -> float:
	if k.begins_with(SP):
		return SPECIAL_RARITY
	var a := Data.affix(k)
	if a.is_empty() or a.get("w", 0) <= 0:
		return 1.0
	var rolled := Data.AFFIXES.filter(func(x): return x.get("w", 0) > 0)
	var avg: float = rolled.reduce(func(s, x): return s + x.w, 0.0) / rolled.size()
	return clampf(avg / a.w, RARITY_CLAMP[0], RARITY_CLAMP[1])


# =================== searching ===================
## the listings for a query: {items: [listing], error: ""}; an error (why nothing can fit) leaves items empty
static func search(q: Dictionary, league: String, level: int, refresh := 0) -> Dictionary:
	q = _clean(q)
	var err := check(q, level)
	if err != "":
		return {"items": [], "error": err}
	price_league = league
	var key := "%s|%s|%d|%d" % [JSON.stringify(q, "", true), league, int(Market.state(league).get("tick", 0)), refresh]
	seed(key.hash())
	var out := []
	var tries := 0
	var lo := float(q.price_min)
	var hi := float(q.price_max) if q.price_max > 0 else INF
	var lots := _lots(q)
	while out.size() < RESULTS and tries < RESULTS * ATTEMPTS:
		tries += 1
		var l := _make(q, level, lots, tries)
		if l.is_empty():
			if q.cat in ["charm", "gem", "currency", "map"]:
				break   # the fixed list ran out
			continue    # a line couldn't reach its minimum at this item level
		if l.price < lo or l.price > hi:
			continue
		l.key = "%d:%d" % [key.hash(), tries]
		l.sold = sold.has(l.key)
		out.append(l)
	randomize()
	if out.is_empty():
		var why := "条件に合う出品が見つかりませんでした"
		if lo > 0.0 or hi < INF:
			why = "価格 ✺ %d〜%s に合う出品が見つかりませんでした（価格の条件をゆるめてください）" % [int(lo), "" if hi == INF else str(int(hi))]
		return {"items": [], "error": why}
	return {"items": out, "error": ""}


static func _clean(q: Dictionary) -> Dictionary:
	var c := empty_query()
	c.merge(q, true)
	var mods := {}
	for m in c.mods:
		var k := str(m.get("k", ""))
		if k != "":
			mods[k] = maxi(int(mods.get(k, 0)), int(m.get("min", 0)))
	c.mods = mods.keys().map(func(k): return {"k": k, "min": mods[k]})
	c.rarity = int(c.rarity)
	c.ilvl = maxi(0, int(c.ilvl))
	c.glv = clampi(int(c.glv), 0, Data.GEM_MAX_LV)
	c.price_min = maxi(0, int(c.price_min))
	c.price_max = maxi(0, int(c.price_max))
	return c


## why the query can't be met by anything, or ""
static func check(q: Dictionary, level := 1) -> String:
	q = _clean(q)
	if q.mods.size() > MAX_MODS:
		return "オプションの条件は %d つまでです" % MAX_MODS
	if q.price_max > 0 and q.price_max < q.price_min:
		return "価格の上限が下限より低くなっています"
	if not q.mods.is_empty() and not q.cat in ["gear", "tablet", "jewel"]:
		return "%sはオプションでは探せません" % _cat_name(q.cat)
	if q.base != "" and not q.base in base_names(q.cat, q.slot if q.cat == "gear" else ""):
		return "「%s」という%sはありません" % [q.base, _cat_name(q.cat) if q.cat != "gear" or q.slot == "" else Data.SLOT_INFO[q.slot].name]
	for m in q.mods:
		if not m.k in mod_keys(q.cat):
			return "%sに「%s」は付きません" % [_cat_name(q.cat), mod_name(m.k)]
	match q.cat:
		"gear":
			return _check_gear(q, level)
		"tablet":
			if q.rarity >= 0:
				return "ルーンタブレットにはレア度がありません"
			if q.mods.size() > 3:
				return "ルーンタブレットの行は最大 3 行です"
			# the biggest piece carries the biggest line
			var t := {"shape": _shape_id(q.base) if q.base != "" else "slab6", "ilvl": _ilvl_hi(q, level)}
			if q.mods.size() > Tablets.max_mods(t):
				return "%sに刻めるのは %d 行までです" % [q.base, Tablets.max_mods(t)]
			for m in q.mods:
				if Tablets.value_at(t, m.k, 1.2) < m.min:
					return _too_high(m, Tablets.value_at(t, m.k, 1.2))
		"jewel":
			if q.rarity == 3:
				return "ジュエルにユニークはありません"
			if q.rarity == 0 and not q.mods.is_empty():
				return "ノーマルのジュエルにはオプションが付きません"
			if q.rarity == 1 and q.mods.size() > Data.RARITY[1].aff[1]:
				return "マジックのジュエルに付くオプションは %d つまでです" % Data.RARITY[1].aff[1]
			for m in q.mods:
				var best := Jewels.value_at({"ilvl": _ilvl_hi(q, level)}, Jewels.affix(m.k), 1.0)
				if best < m.min:
					return _too_high(m, best)
		"ring":
			if q.rarity == 0 or q.rarity == 3:
				return "リングジュエルはマジックかレアだけです"
		_:
			if q.rarity >= 0:
				return "%sにはレア度がありません" % _cat_name(q.cat)
	if q.unique != "" and q.cat != "gear":
		return "ユニーク名で探せるのは装備だけです"
	return ""


static func _check_gear(q: Dictionary, level: int) -> String:
	var slots := _gear_slots(q)
	if q.unique != "":
		var l := Data.legend(q.unique)
		if l.is_empty():
			return "「%s」というユニークはありません" % q.unique
		if q.rarity >= 0 and q.rarity != 3:
			return "ユニークを探すときはレア度をレジェンドにしてください"
		if q.slot != "" and l.slot != q.slot:
			return "%s は%sです" % [q.unique, Data.SLOT_INFO[l.slot].name]
		if q.base != "" and Items.base_name(l.slot, l.base) != q.base:
			return "%s のベースは%sです" % [q.unique, Items.base_name(l.slot, l.base)]
		for m in q.mods:
			if m.k.begins_with(SP):
				return "ユニークに刻紋は刻めません"
			if l.has("mods") and not l.mods.has(m.k):
				return "%s に「%s」は付きません" % [q.unique, mod_name(m.k)]
			if not l.has("mods") and not l.slot in Data.affix(m.k).slots:
				return "%s に「%s」は付きません" % [q.unique, mod_name(m.k)]
			var it := {"ilvl": _ilvl_hi(q, level), "rarity": 3, "name": q.unique, "slot": l.slot}
			var best := _gear_value(it, m.k, 1.0)
			if best < m.min:
				return _too_high(m, best)
		return ""
	if slots.is_empty():
		var names := PackedStringArray(q.mods.map(func(m): return "「%s」" % mod_name(m.k)))
		if q.slot != "" or q.base != "":
			return "%sに%sは付きません" % [Data.SLOT_INFO[_base_slot(q)].name if q.base != "" else Data.SLOT_INFO[q.slot].name, "".join(names)]
		return "%sが同時に付く部位はありません" % "".join(names)
	if _rarities(q, slots).is_empty():
		if q.rarity == 0:
			return "ノーマルにはオプションが付きません"
		if q.rarity == 1:
			return "マジックに付くオプションは %d つまで（刻紋はレアだけ）です" % Data.RARITY[1].aff[1]
		if q.rarity == 3:
			return "その条件に合うユニークはありません（ユニークのオプションはユニーク名を指定して探せます）"
		return "その条件に合うレア度がありません"
	for m in q.mods:
		var best := 0
		for s in slots:
			best = maxi(best, _gear_value({"ilvl": _ilvl_hi(q, level), "rarity": 2, "name": "", "slot": s}, m.k, 1.0))
		if best < m.min:
			return _too_high(m, best)
	return ""


static func _too_high(m: Dictionary, best: int) -> String:
	return "「%s」は最大でも %d までです（アイテムレベルを上げると伸びます）" % [mod_name(m.k), best]


static func _cat_name(cat: String) -> String:
	for c in CATEGORIES:
		if c[0] == cat:
			return c[1]
	return cat


static func _base_slot(q: Dictionary) -> String:
	for s in Data.SLOTS:
		if Data.BASES[s].any(func(b): return b.name == q.base):
			return s
	return ""


## the slots a gear query can be met on: the asked slot (or the base's), narrowed to those every asked line rolls on
static func _gear_slots(q: Dictionary) -> Array:
	var slots: Array = [q.slot] if q.slot != "" else Data.SLOTS.duplicate()
	if q.base != "":
		slots = [_base_slot(q)]
	return slots.filter(func(s): return q.mods.all(func(m): return m.k.begins_with(SP) or s in Data.affix(m.k).slots))


## the rarities a gear query (without a unique name) can be met with
static func _rarities(q: Dictionary, slots: Array) -> Array:
	var plain: Array = q.mods.filter(func(m): return not m.k.begins_with(SP))
	var special: bool = plain.size() < q.mods.size()
	var out := []
	for r in ([q.rarity] if q.rarity >= 0 else [0, 1, 2, 3]):
		if r == 0 and not q.mods.is_empty():
			continue
		if r == 1 and (special or plain.size() > Data.RARITY[1].aff[1]):
			continue
		if r == 3 and (not q.mods.is_empty() or not slots.any(func(s): return _legends(s, q.base).size() > 0)):
			continue   # a unique's lines are its own: ask for them by its name
		out.append(r)
	return out


static func _legends(slot: String, base: String) -> Array:
	return Data.LEGENDARY.filter(func(l): return l.slot == slot and (base == "" or Items.base_name(l.slot, l.base) == base))


static func _ilvl_lo(q: Dictionary, level: int) -> int:
	return maxi(1, q.ilvl if q.ilvl > 0 else level)


static func _ilvl_hi(q: Dictionary, level: int) -> int:
	return _ilvl_lo(q, level) + ILVL_SPREAD


static func _shape_id(shape_name: String) -> String:
	for s in Tablets.SHAPES:
		if s.name == shape_name:
			return s.id
	return ""


## the fixed list a charm, gem or currency search draws from; [] for the generated categories
static func _lots(q: Dictionary) -> Array:
	match q.cat:
		"charm":
			return Charms.all_ids().filter(func(id): return q.base == "" or Charms.name_of(id) == q.base)
		"gem":
			var out := []
			for id in Data.SKILL_ORDER:
				if q.base == "" or Data.SKILLS[id].name == q.base:
					out.append({"skill": true, "id": id})
			for g in Data.SUPPORTS if q.base == "" else Data.all_supports():
				if q.base == "" or g.name == q.base:
					out.append({"skill": false, "id": g.id})
			if q.base == "":
				# seeded by the search: an open search mixes skill and support gems with a few awakened ones
				out.shuffle()
				var aw: Array = Data.awakened().duplicate()
				aw.shuffle()
				for g in aw.slice(0, AWAKE_OPEN):
					out.insert(randi_range(0, RESULTS - AWAKE_OPEN), {"skill": false, "id": g.id})
			return out
		"currency":
			return currency_keys().filter(func(k): return q.base == "" or Data.currency(k).name == q.base)
		"map":
			var ids: Array = Maps.LIST.filter(func(m): return q.base == "" or m.name == q.base).map(func(m): return m.id)
			ids.shuffle()   # seeded by the search
			return ids
	return []


## the lowest tier a map search lists: the tier asked, or a little under the best cleared (the hideout level)
static func map_tier_lo(q: Dictionary, level: int) -> int:
	return Maps.clamp_tier(int(q.ilvl) if int(q.ilvl) > 0 else level - 1)


# =================== making listings ===================
## one listing for the query (try `n`), or {} when the fixed list has run out
static func _make(q: Dictionary, level: int, lots: Array, n: int) -> Dictionary:
	var lvl := randi_range(_ilvl_lo(q, level), _ilvl_hi(q, level))
	var l := {}
	var qs := []   # how far up its range each asked line's minimum is, in order
	match q.cat:
		"gear":
			l = {"kind": "gear", "item": _make_gear(q, lvl, qs)}
		"tablet":
			l = {"kind": "tablet", "item": _make_tablet(q, lvl, qs)}
		"jewel":
			l = {"kind": "jewel", "item": _make_jewel(q, lvl, qs)}
		"ring":
			var r: int = q.rarity if q.rarity >= 0 else (2 if randf() < 0.4 else 1)
			var size := ""
			for s in Jewels.SIZES:
				if s.name == q.base:
					size = s.id
			l = {"kind": "ring", "item": Jewels.generate_ring(lvl, r, size)}
		"charm":
			if lots.is_empty():
				return {}
			l = {"kind": "charm", "id": lots[(n - 1) % lots.size()], "n": CHARM_LOTS.pick_random()}
		"gem":
			if n > lots.size():
				return {}
			l = {"kind": "gem", "id": lots[n - 1].id, "skill": lots[n - 1].skill, "n": 1, "glv": gem_lv_roll(q.glv)}
		"currency":
			if lots.is_empty():
				return {}
			l = {"kind": "currency", "id": lots[(n - 1) % lots.size()], "n": CURRENCY_LOTS.pick_random()}
		"map":
			if lots.is_empty():
				return {}
			var lo := map_tier_lo(q, level)
			l = {"kind": "map", "id": Maps.key(lots[(n - 1) % lots.size()], Maps.clamp_tier(randi_range(lo, lo + MAP_SPREAD))), "n": 1}
	if l.has("item") and l.item.is_empty():
		return {}
	l.price = price(l, q, qs, level)
	l.fee = Market.fee(l.price)
	return l


## the line's value on gear at `t` of its range: a unique's own line against its fixed range, else the affix
static func _gear_value(it: Dictionary, k: String, t: float) -> int:
	if k.begins_with(SP):
		return Items.special_at(it, Data.special_mod(k.trim_prefix(SP)), t)
	if int(it.rarity) == 3:
		var fixed: Dictionary = Data.legend(it.name).get("mods", {})
		if fixed.has(k):
			return Items.fixed_at(it, k, fixed[k], t)
	return Items.value_at(it, Data.affix(k), t)


## the least t (0..1) at which `f(t)` reaches `need`, or -1 if even t = 1 falls short
static func min_t(f: Callable, need: int) -> float:
	if f.call(1.0) < need:
		return -1.0
	if f.call(0.0) >= need:
		return 0.0
	var lo := 0.0
	var hi := 1.0
	for i in 14:
		var mid := (lo + hi) * 0.5
		if f.call(mid) >= need:
			hi = mid
		else:
			lo = mid
	return hi


## roll each asked line at or over its minimum into `mods` (or a 刻紋 into the item), noting how high each asked; false if one can't reach
static func _force(x: Dictionary, q: Dictionary, f: Callable, qs: Array) -> bool:
	for m in q.mods:
		var t0 := min_t(f.bind(x, m.k), m.min)
		if t0 < 0.0:
			return false
		var t := randf_range(t0, 1.0)
		var v: int = f.call(t, x, m.k)
		if v < m.min:
			v = f.call(1.0, x, m.k)
		if m.k.begins_with(SP):
			x.special = {"k": m.k.trim_prefix(SP), "v": v}
		else:
			x.mods[m.k] = v
		qs.append(t0)
	return true


static func _make_gear(q: Dictionary, lvl: int, qs: Array) -> Dictionary:
	var f := func(t: float, it: Dictionary, k: String) -> int: return _gear_value(it, k, t)
	if q.unique != "":
		var l := Data.legend(q.unique)
		var it := Items.generate(lvl, 0.0, 3, l.slot, q.unique)
		if l.has("mods"):
			return it if _force(it, q, f, qs) else {}
		return it if _refill(it, q, f, qs, Data.RARITY[3].aff) else {}
	var slots := _gear_slots(q)
	var slot: String = slots.pick_random()
	var rs := _rarities(q, [slot])
	if rs.is_empty():
		rs = _rarities(q, slots)
		slot = slots.filter(func(s): return not _rarities(q, [s]).is_empty()).pick_random()
	var r := _pick_rarity(rs)
	var it := Items.generate(lvl, 0.0, r, slot, "", q.base)
	if r == 0 or r == 3:
		return it
	if not _refill(it, q, f, qs, Data.RARITY[r].aff):
		return {}
	Items.name_item(it)
	return it


## clear the random lines, force the asked ones, then roll the rest up to a count the rarity allows
static func _refill(it: Dictionary, q: Dictionary, f: Callable, qs: Array, aff: Array) -> bool:
	it.mods = {}
	it.erase("special")
	if not _force(it, q, f, qs):
		return false
	var plain: int = it.mods.size()
	Items.add_affixes(it, maxi(randi_range(aff[0], aff[1]), plain) - plain)
	return true


static func _pick_rarity(rs: Array) -> int:
	var w: Array = Data.SHOP_GEAR_RARITY
	var total := 0.0
	for r in rs:
		total += w[r]
	var roll := randf() * total
	for r in rs:
		roll -= w[r]
		if roll <= 0.0:
			return r
	return rs.back()


static func _make_tablet(q: Dictionary, lvl: int, qs: Array) -> Dictionary:
	var shapes: Array = Tablets.SHAPES.filter(func(s): return (q.base == "" or s.name == q.base) and q.mods.size() <= Tablets.max_mods({"shape": s.id}))
	if shapes.is_empty():
		return {}
	var t := Tablets.generate(lvl, shapes.pick_random().id, 0)
	var f := func(x: float, tb: Dictionary, k: String) -> int: return Tablets.value_at(tb, k, 0.8 + 0.4 * x)
	if not _force(t, q, f, qs):
		return {}
	Tablets.add_mods(t, randi_range(0, Tablets.max_mods(t) - t.mods.size()))
	return t


static func _make_jewel(q: Dictionary, lvl: int, qs: Array) -> Dictionary:
	var base_id := ""
	for b in Jewels.BASES:
		if b.name == q.base:
			base_id = b.id
	var rs: Array = [q.rarity] if q.rarity >= 0 else [0, 1, 2]
	rs = rs.filter(func(r): return (r > 0 or q.mods.is_empty()) and q.mods.size() <= Data.RARITY[r].aff[1])
	var r: int = rs.pick_random()
	var j := Jewels.generate(lvl, r, base_id)
	if r == 0:
		return j
	j.mods = {}
	var f := func(t: float, jw: Dictionary, k: String) -> int: return Jewels.value_at(jw, Jewels.affix(k), t)
	if not _force(j, q, f, qs):
		return {}
	Jewels.add_affixes(j, maxi(randi_range(Data.RARITY[r].aff[0], Data.RARITY[r].aff[1]), j.mods.size()) - j.mods.size())
	Jewels.name_jewel(j)
	return j


# =================== prices ===================
## what the listing is worth before any premium (c)
static func worth(l: Dictionary) -> float:
	match l.kind:
		"gear":
			return maxf(Trade.base_value(l.item), Items.sell_price(l.item) / float(Items.EMBER_PER_CHAOS))
		"tablet":
			return Tablets.shard_value(l.item) / float(Items.EMBER_PER_CHAOS) * (1.0 + 0.3 * l.item.mods.size())
		"jewel", "ring":
			return Jewels.shard_value(l.item) / float(Items.EMBER_PER_CHAOS) * 1.5
		"charm":
			return Charms.value(l.id) * l.n / float(Items.EMBER_PER_CHAOS)
		"gem":
			var up := 1.0 + GEM_LV_WORTH * (int(l.get("glv", 1)) - 1)
			if not l.skill and Data.is_awakened(l.id):   # priced off its base gem, times the awakened premium
				return (300 + 45 * Data.support(Data.base_gem(l.id)).lvl) / float(Items.EMBER_PER_CHAOS) * Data.AWAKE_PRICE * up
			var lvl: int = Data.SKILLS[l.id].lvl if l.skill else Data.support(l.id).lvl
			return (300 + 45 * lvl) / float(Items.EMBER_PER_CHAOS) * up
		"currency":
			return unit_price(l.id) * l.n
		"map":
			return Maps.value(Maps.parse(l.id).get("tier", 1)) * l.n / float(Items.EMBER_PER_CHAOS)
	return 0.0


## a currency's chaos price: the market's, or for 刻紋の熾石 (not traded there) its value against chaos
static func unit_price(k: String) -> float:
	if Market.PARAMS.has(k):
		return Market.price(price_league, k)
	return float(Data.currency(k).get("value", 25)) / float(Data.currency("chaos").value)


## the most selling the listing back can pay (c): the dealer or the merchant for gear, breaking down for tablets and
## jewels (ember at the merchant's rate), the market's buy side for currency
static func resale(l: Dictionary) -> float:
	match l.kind:
		"gear":
			var dealer := Trade.base_value(l.item) * Trade.DEALER * 1.4   # the season stage pays up to 1.4 early on
			return maxf(dealer, Items.sell_price(l.item) / float(Items.EMBER_PER_CHAOS))
		"tablet":
			return Tablets.shard_value(l.item) / float(Items.EMBER_PER_CHAOS)
		"jewel", "ring":
			return Jewels.shard_value(l.item) / float(Items.EMBER_PER_CHAOS)
		"currency":
			return unit_price(l.id) * l.n
		"map":   # the map device's buy-back
			return Maps.sell_price(Maps.parse(l.id).get("tier", 1)) * l.n / float(Items.EMBER_PER_CHAOS)
	return 0.0


## the gem level of a gem listing: at least `want` (0: mostly Lv 1, now and then a little higher)
static func gem_lv_roll(want: int) -> int:
	if want > 0:
		return mini(Data.GEM_MAX_LV, randi_range(want, want + GEM_LV_SPREAD))
	return randi_range(2, GEM_LV_TOP) if randf() < GEM_LV_ODDS else 1


## the multiplier the query's filters put on a listing; `qs` how far up its range each asked line's minimum is
static func constraint_mult(q: Dictionary, qs: Array, level := 0) -> float:
	var m := 1.0
	if q.get("base", "") != "":
		m *= 1.0 + PICK.base
	elif q.get("slot", "") != "":
		m *= 1.0 + PICK.slot
	if int(q.get("rarity", -1)) >= 0:
		m *= 1.0 + PICK.rarity
	if q.get("unique", "") != "":
		m *= 1.0 + PICK.unique
	if int(q.get("ilvl", 0)) > level and level > 0 and q.get("cat", "") != "map":   # a map's tier is in its worth already
		m *= 1.0 + ILVL_STEP * (int(q.ilvl) - level)
	var mods: Array = q.get("mods", [])
	for i in mods.size():
		var qi: float = qs[i] if i < qs.size() else 0.0
		m *= (1.0 + MOD_BASE * mod_rarity(mods[i].k) * (1.0 + QUALITY * qi)) * (1.0 + MOD_STACK * i)
	return m


static func price(l: Dictionary, q: Dictionary, qs: Array, level := 0) -> int:
	var p := worth(l) * PREMIUM * randf_range(0.9, 1.25) * constraint_mult(q, qs, level)
	return maxi(1, ceili(maxf(p, resale(l) * RESALE_GUARD)))


## pay for a listing from the wallet (chaos and the ember fee) and mark it bought; "" or why not
static func pay(l: Dictionary, wallet: Dictionary) -> String:
	if l.get("sold", false) or sold.has(l.get("key", "")):
		return "その出品はもう売れました"
	if wallet.get(Market.BASE, 0) < l.price:
		return "混沌の残光が足りない（%d 必要）" % l.price
	if wallet.get("ember", 0) < l.fee:
		return "手数料の灰燼の欠片が足りない（%d 必要）" % l.fee
	wallet[Market.BASE] -= l.price
	wallet.ember -= l.fee
	l.sold = true
	sold[l.key] = true
	return ""
