class_name Trade
## Gear trading on the exchange (docs/economy-design.md phases 2 and 3). It lives in the league's market
## (Market.state) next to the currency book: the player's own listings, the gear other adventurers have
## up for sale, the NPC buy requests, and a pickup box for what came back. Prices are whole chaos;
## the season's item trends (tags such as fire or minion) move what gear is worth.

const MAX_LISTINGS := 8
const LISTING_LIFE := 50        # ticks before an unsold listing comes back
const SELL_BASE := 0.25
const SELL_FALLOFF := 6.0
const SELL_CAP := 0.6
const DEALER := 0.6             # the dealer takes gear at once for this share of its value
const OFFERS := 10
const OFFER_LIFE := 30
const OFFER_TAKEN := 0.12       # chance a tick that someone else buys an offer
const MAX_REQUESTS := 3
const REQUEST_LIFE := 30
const REQUEST_CHANCE := 0.5     # chance a tick that a new request is posted while there is room
const BASE := Market.BASE

## item tags the season trends and the requests aim at: positive stat lines, or words in a unique's effect
const TAGS := {
	"fire": {"name": "火炎", "mods": ["fire_dmg"], "words": ["火", "炎", "燃", "焼"]},
	"cold": {"name": "冷気", "mods": ["cold_dmg"], "words": ["冷", "氷", "凍", "霜"]},
	"lightning": {"name": "雷", "mods": ["light_dmg"], "words": ["雷", "稲妻", "感電"]},
	"minion": {"name": "召喚", "mods": ["ally_dmg", "ally_life"], "words": ["ミニオン", "骸骨", "召喚", "トーテム"]},
	"attack": {"name": "攻撃", "mods": ["atk_dmg", "atk_spd", "flat_dmg"], "words": ["攻撃", "斬撃", "武器"]},
	"spell": {"name": "呪文", "mods": ["spell_dmg", "cast_spd"], "words": ["スキルダメージ", "詠唱", "呪文"]},
	"life": {"name": "ライフ", "mods": ["life", "life_regen", "life_on_kill"], "words": ["ライフ"]},
	"crit": {"name": "クリティカル", "mods": ["crit", "crit_multi"], "words": ["クリティカル"]},
	"speed": {"name": "速度", "mods": ["move_spd"], "words": ["移動速度"]},
}

## how much buyers care about each stat line on a rare (anything not listed: 0.4)
const AFFIX_WEIGHT := {
	"life": 1.0, "inc_dmg": 1.0, "atk_spd": 1.0, "cast_spd": 1.0, "crit_multi": 0.9, "spell_dmg": 0.9,
	"fire_dmg": 0.8, "cold_dmg": 0.8, "light_dmg": 0.8, "move_spd": 1.5, "energy": 1.2, "crit": 0.8,
}

# season stage per rarity, as for currencies: scarce gear early, plenty once the league matures
const STAGE := {2: {"early": 1.4, "late": 0.8}, 3: {"early": 1.3, "late": 0.9}}

const BUYERS := ["鍛冶屋のグレン", "傭兵のミラ", "収集家のオルド", "見習い術師のティカ", "隊商のバルト", "墓守のセイ"]


# =================== state ===================
## fill in the trading part of a market (new, older or hand-edited save)
static func normalize(m: Dictionary) -> void:
	m.ilvl = maxi(1, int(m.get("ilvl", 1)))
	m.listings = _dicts(m.get("listings")).filter(func(l): return typeof(l.get("item")) == TYPE_DICTIONARY).map(func(l):
		return {"id": int(l.get("id", 0)), "item": Items.normalize(l.item), "ask": maxi(1, int(l.get("ask", 1))),
			"placed_tick": int(l.get("placed_tick", 0))})
	m.offers = _dicts(m.get("offers")).filter(func(o): return typeof(o.get("item")) == TYPE_DICTIONARY).map(func(o):
		return {"id": int(o.get("id", 0)), "item": Items.normalize(o.item), "price": maxi(1, int(o.get("price", 1))),
			"placed_tick": int(o.get("placed_tick", 0))})
	m.requests = _dicts(m.get("requests")).filter(func(r): return r.get("kind") in ["affix", "unique"]).map(func(r):
		return {"id": int(r.get("id", 0)), "kind": r.kind, "slot": str(r.get("slot", "")), "k": str(r.get("k", "")),
			"need": int(r.get("need", 0)), "tag": str(r.get("tag", "")), "reward": maxi(1, int(r.get("reward", 1))),
			"who": str(r.get("who", BUYERS[0])), "placed_tick": int(r.get("placed_tick", 0))})
	m.held = _dicts(m.get("held")).map(func(it): return Items.normalize(it))


static func _dicts(v) -> Array:
	return Array(v if typeof(v) == TYPE_ARRAY else []).filter(func(x): return typeof(x) == TYPE_DICTIONARY)


static func _next_id(m: Dictionary) -> int:
	m.next_id = int(m.get("next_id", 1)) + 1
	return m.next_id - 1


## the hideout level the market's gear is made at; the offers fill up if they ran out
static func ensure(league: String, ilvl: int, m := Market.state(league)) -> void:
	m.ilvl = maxi(1, ilvl)
	_refill(league, m)


# =================== tags and value ===================
static func tags(it: Dictionary) -> Array:
	var out := []
	var text: String = str(it.get("desc", ""))
	for t in TAGS:
		var hit: bool = TAGS[t].mods.any(func(k): return int(it.get("mods", {}).get(k, 0)) > 0)
		if not hit and int(it.get("rarity", 0)) == 3:
			hit = TAGS[t].words.any(func(w): return w in text)
		if hit:
			out.append(t)
	return out


static func tag_names(ts: Array) -> String:
	return "・".join(PackedStringArray(ts.map(func(t): return TAGS[t].name)))


## a unique's standing among buyers, by its drop tier (Data.UNIQUE_TIERS) and fixed by its name: {tier, base (c)};
## a unique jewel or tablet says its `tier` (its table's), not being in the gear list
static func unique_tier(uname: String, tier := -1) -> Dictionary:
	var t: Dictionary = Data.UNIQUE_TIERS[tier if tier >= 0 else Data.unique_tier(uname)]
	var r := RandomNumberGenerator.new()
	r.seed = ("unique-price/" + uname).hash()
	return {"tier": t.name, "base": r.randf_range(t.base[0], t.base[1])}


## how good a stat line rolled, 0..1, for the item's level (unique lines against their fixed range)
static func roll_quality(it: Dictionary, k: String) -> float:
	var a := Data.affix(k)
	var scale: float = 1.0 + int(it.ilvl) * float(a.get("sc", 0.0))
	var v := float(it.mods[k]) / scale
	var lo := float(a.get("min", 0))
	var hi := float(a.get("max", 1))
	if int(it.rarity) == 3:
		var fixed: Dictionary = Data.legend(it.name).get("mods", {})
		var power := Data.unique_pow(it.name)
		if fixed.has(k):
			lo = fixed[k][0]
			hi = fixed[k][1]
			if lo > 0:
				v /= power
		else:
			v /= 1.2 * power
	return clampf((v - lo) / maxf(hi - lo, 0.001), 0.0, 1.0)


## what buyers pay for the item itself, before the season stage and trends (c)
static func base_value(it: Dictionary) -> float:
	var r := int(it.get("rarity", 0))
	var ilvl := int(it.get("ilvl", 1))
	if r == 3:
		var q := 0.5
		if not it.mods.is_empty():
			q = 0.0
			for k in it.mods:
				q += roll_quality(it, k)
			q /= it.mods.size()
		return unique_tier(it.name).base * (0.75 + 0.5 * q) * (0.8 + 0.4 * clampf(ilvl / 40.0, 0.0, 1.0))
	if r == 2:
		var s := 0.0
		for k in it.mods:
			if int(it.mods[k]) > 0:
				s += AFFIX_WEIGHT.get(k, 0.4) * pow(roll_quality(it, k), 2.0)
		return (0.1 + 0.3 * s) * (0.6 + ilvl / 25.0)
	return 0.0


static func tradeable(it: Dictionary) -> bool:
	return int(it.get("rarity", 0)) >= 2


static func stage_mult(league: String, rarity: int, d: float) -> float:
	var st: Dictionary = STAGE.get(rarity, {"early": 1.0, "late": 1.0})
	if not Market.is_season(league):
		return st.late
	return lerpf(st.early, st.late, smoothstep(0.0, Market.STAGE_DAYS, d))


## product of the item trends running on market day `d` that touch any of `ts`
static func trend_mult(league: String, ts: Array, d: float) -> float:
	var mult := 1.0
	for e in events(league):
		if e.tag in ts and d >= e.start and d < e.start + e.days:
			mult *= e.mult
	return mult


## the item's market value now (c)
static func value(league: String, it: Dictionary, m := Market.state(league)) -> float:
	var d := Market.day(m)
	return base_value(it) * stage_mult(league, int(it.rarity), d) * trend_mult(league, tags(it), d)


## 2-3 item trends fixed by the season id: {tag, mult, start, days}; standard has none
static func events(league: String) -> Array:
	if not Market.is_season(league):
		return []
	var r := RandomNumberGenerator.new()
	r.seed = (league + "/items").hash()
	var ts := TAGS.keys()
	var out := []
	for i in r.randi_range(2, 3):
		var boom := r.randf() < 0.7
		out.append({"tag": ts[r.randi() % ts.size()], "mult": snappedf(r.randf_range(1.3, 2.0) if boom else r.randf_range(0.6, 0.8), 0.05),
			"start": r.randi_range(1, 40), "days": r.randi_range(4, 8)})
	out.sort_custom(func(a, b): return a.start < b.start)
	return out


static func event_text(e: Dictionary) -> String:
	var tname: String = TAGS[e.tag].name
	return "%s装備の%s：市場日 %d〜%d、%sタグのユニーク・レアの需要 ×%.2f" % [tname, "流行" if e.mult >= 1.0 else "不人気",
		e.start, e.start + e.days - 1, tname, e.mult]


# =================== time ===================
## the trading part of a market tick (Market.tick calls it after the tick count moved)
static func tick(league: String, wallet: Dictionary, m: Dictionary) -> void:
	var d := Market.day(m)
	for l in m.listings.duplicate():
		var f := sell_rate(league, l.item, l.ask, m)
		if Market.rng.randf() < f:
			m.listings.erase(l)
			wallet[BASE] = wallet.get(BASE, 0) + l.ask
			m.pending.append("出品していた %s が ✺ %d で売れました" % [l.item.name, l.ask])
		elif m.tick - l.placed_tick >= LISTING_LIFE:
			m.listings.erase(l)
			m.held.append(l.item)
			m.pending.append("%s は売れずに出品の期限が切れました（取引所の受け取り箱へ）" % l.item.name)
	for o in m.offers.duplicate():
		if m.tick - o.placed_tick >= OFFER_LIFE or Market.rng.randf() < OFFER_TAKEN:
			m.offers.erase(o)
	for r in m.requests.duplicate():
		if m.tick - r.placed_tick >= REQUEST_LIFE:
			m.requests.erase(r)
			m.pending.append("%s の買取依頼が締め切られました" % r.who)
	if m.requests.size() < MAX_REQUESTS and Market.rng.randf() < REQUEST_CHANCE:
		var r := _new_request(league, m)
		m.requests.append(r)
		m.pending.append("新しい買取依頼：%s（報酬 ✺ %d）" % [request_text(r), r.reward])
	_refill(league, m)
	if m.tick % Market.TICKS_PER_DAY == 0:
		for e in events(league):
			if int(d) == e.start - 1:
				m.pending.append("相場掲示板：明日から %s" % event_text(e))


static func _refill(league: String, m: Dictionary) -> void:
	while m.offers.size() < OFFERS:
		m.offers.append(_new_offer(league, m))
	if m.requests.is_empty():   # a new market (or one whose requests all ran out) starts with a full board
		while m.requests.size() < MAX_REQUESTS:
			m.requests.append(_new_request(league, m))


## gear another adventurer puts up: a unique, or the best of a few rares; priced around its value
static func _new_offer(league: String, m: Dictionary) -> Dictionary:
	var it: Dictionary
	if Market.rng.randf() < 0.4:
		it = Items.generate(m.ilvl, 0.0, 3)
	else:
		for i in 4:
			var c := Items.generate(m.ilvl, 0.0, 2)
			if it.is_empty() or base_value(c) > base_value(it):
				it = c
	var price := maxi(1, ceili(value(league, it, m) * Market.rng.randf_range(0.95, 1.5)))
	return {"id": _next_id(m), "item": it, "price": price, "placed_tick": m.tick}


## an NPC buy request: a magic or rare item of a slot with a stat line at least `need`,
## or any unique with a tag. The reward is above what such gear sells for.
static func _new_request(league: String, m: Dictionary) -> Dictionary:
	var r := {"id": _next_id(m), "slot": "", "k": "", "need": 0, "tag": "", "who": BUYERS[Market.rng.randi() % BUYERS.size()],
		"placed_tick": m.tick}
	var ilvl: int = m.ilvl
	if Market.rng.randf() < 0.65:
		r.kind = "affix"
		r.slot = Data.SLOTS[Market.rng.randi() % Data.SLOTS.size()]
		var pool := Data.AFFIXES.filter(func(a): return r.slot in a.slots)
		var a: Dictionary = pool[Market.rng.randi() % pool.size()]
		r.k = a.k
		r.need = maxi(1, roundi((a.min + 0.5 * (a.max - a.min)) * (1.0 + ilvl * a.sc)))
		r.reward = clampi(ceili(0.5 + (1.0 + ilvl / 20.0) * AFFIX_WEIGHT.get(a.k, 0.4)), 1, 10)
	else:
		r.kind = "unique"
		r.tag = TAGS.keys()[Market.rng.randi() % TAGS.size()]
		r.reward = maxi(1, roundi((2 + Market.rng.randi_range(0, 2)) * trend_mult(league, [r.tag], Market.day(m))))
	return r


# =================== the player's listings ===================
## share of the chance a listing at `ask` sells in one tick
static func sell_rate(league: String, it: Dictionary, ask: int, m := Market.state(league)) -> float:
	var v := value(league, it, m)
	if v <= 0.0:
		return 0.0
	return minf(SELL_CAP, SELL_BASE * exp(-SELL_FALLOFF * (ask / v - 1.0)))


## what the listing screen shows: {value, rate, ticks (-1: unlikely before it expires), fee, dealer}
static func list_estimate(league: String, it: Dictionary, ask: int, m := Market.state(league)) -> Dictionary:
	var f := sell_rate(league, it, ask, m)
	var ticks := -1
	if f > 0.0:
		ticks = maxi(1, ceili(log(0.5) / log(1.0 - f)))
		if ticks > LISTING_LIFE:
			ticks = -1
	return {"value": value(league, it, m), "rate": f, "ticks": ticks, "fee": Market.fee(ask), "dealer": dealer_price(league, it, m)}


static func dealer_price(league: String, it: Dictionary, m := Market.state(league)) -> int:
	return floori(value(league, it, m) * DEALER + 1e-9)


## put bag item `i` up at `ask` chaos; the listing fee (ember) is paid now and not returned. "" or why not.
static func list_item(league: String, bag: Array, i: int, ask: int, wallet: Dictionary, m := Market.state(league)) -> String:
	if i < 0 or i >= bag.size() or not tradeable(bag[i]):
		return "出品できるのはレアとレジェンドの装備だけです"
	if ask < 1:
		return "値段は ✺ 1 以上にしてください"
	if m.listings.size() >= MAX_LISTINGS:
		return "出品は %d 件までです" % MAX_LISTINGS
	var fe := Market.fee(ask)
	if wallet.get("ember", 0) < fe:
		return "手数料の灰燼の欠片が足りない（%d 必要）" % fe
	wallet.ember -= fe
	m.listings.append({"id": _next_id(m), "item": bag[i], "ask": ask, "placed_tick": m.tick})
	bag.remove_at(i)
	return ""


## sell bag item `i` to the dealer at once for part of its value. "" or why not.
static func dealer_sell(league: String, bag: Array, i: int, wallet: Dictionary, m := Market.state(league)) -> String:
	if i < 0 or i >= bag.size() or not tradeable(bag[i]):
		return "業者が引き取るのはレアとレジェンドの装備だけです"
	var pay := dealer_price(league, bag[i], m)
	if pay < 1:
		return "業者は値が付かないと言っている（商人に売ろう）"
	wallet[BASE] = wallet.get(BASE, 0) + pay
	bag.remove_at(i)
	return ""


## take a listing down: the item goes back to the bag, or to the pickup box when the bag is full
static func unlist(league: String, id: int, bag: Array, bag_size: int, m := Market.state(league)) -> bool:
	for l in m.listings:
		if l.id == id:
			m.listings.erase(l)
			if bag.size() < bag_size:
				bag.append(l.item)
			else:
				m.held.append(l.item)
			return true
	return false


static func take_held(league: String, i: int, bag: Array, bag_size: int, m := Market.state(league)) -> String:
	if i < 0 or i >= m.held.size():
		return "受け取るものがありません"
	if bag.size() >= bag_size:
		return "インベントリが一杯です"
	bag.append(m.held[i])
	m.held.remove_at(i)
	return ""


# =================== other adventurers' offers ===================
## buy an offer: its price in chaos and the fee in ember. "" or why not.
static func buy_offer(league: String, id: int, bag: Array, bag_size: int, wallet: Dictionary, m := Market.state(league)) -> String:
	for o in m.offers:
		if o.id != id:
			continue
		var fe := Market.fee(o.price)
		if bag.size() >= bag_size:
			return "インベントリが一杯です"
		if wallet.get(BASE, 0) < o.price:
			return "混沌の残光が足りない（%d 必要）" % o.price
		if wallet.get("ember", 0) < fe:
			return "手数料の灰燼の欠片が足りない（%d 必要）" % fe
		wallet[BASE] -= o.price
		wallet.ember -= fe
		bag.append(o.item)
		m.offers.erase(o)
		return ""
	return "その出品はもうありません"


# =================== buy requests ===================
static func request_text(r: Dictionary) -> String:
	if r.kind == "unique":
		return "%sタグのユニーク（どれでも）" % TAGS[r.tag].name
	var a := Data.affix(r.k)
	return "%s（マジックかレア）で「%s」" % [Data.SLOT_INFO[r.slot].name, a.fmt % r.need + " 以上"]


static func matches(r: Dictionary, it: Dictionary) -> bool:
	if r.kind == "unique":
		return int(it.rarity) == 3 and r.tag in tags(it)
	return it.slot == r.slot and int(it.rarity) in [1, 2] and int(it.mods.get(r.k, 0)) >= r.need


## the bag item a request would take: the least valuable one that fits, or -1
static func match_index(league: String, r: Dictionary, bag: Array) -> int:
	var best := -1
	for i in bag.size():
		if matches(r, bag[i]) and (best < 0 or base_value(bag[i]) < base_value(bag[best])):
			best = i
	return best


## hand over a fitting bag item for the reward (no fee: the buyer pays). "" or why not.
static func deliver(league: String, id: int, bag: Array, wallet: Dictionary, m := Market.state(league)) -> String:
	for r in m.requests:
		if r.id != id:
			continue
		var i := match_index(league, r, bag)
		if i < 0:
			return "条件に合う装備を持っていない"
		bag.remove_at(i)
		wallet[BASE] = wallet.get(BASE, 0) + r.reward
		m.requests.erase(r)
		return ""
	return "その依頼はもうありません"


# =================== views ===================
static func listings(league: String) -> Array:
	var m := Market.state(league)
	return m.listings.map(func(l):
		var v: Dictionary = l.duplicate()
		v.ticks_left = LISTING_LIFE - (m.tick - l.placed_tick)
		return v)


static func board(league: String) -> Array:
	var d := floorf(Market.day(Market.state(league)))
	var out := []
	for e in events(league):
		var st := "active" if d >= e.start and d < e.start + e.days else ("soon" if d == e.start - 1 else "")
		if st != "":
			var v: Dictionary = e.duplicate()
			v.state = st
			v.text = event_text(e)
			out.append(v)
	return out


## a market that is being thrown away: the gear it still holds for the player (listings and the pickup box)
static func dissolve_items(m: Dictionary) -> Array:
	var out := []
	for l in Array(m.get("listings", [])):
		out.append(l.item)
	out.append_array(Array(m.get("held", [])))
	return out
