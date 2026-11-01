class_name Market
## The currency exchange (docs/economy-design.md, phase 1). Every league has one market, kept in
## Profiles.data.market[league] so it saves with the league stash. Prices are in chaos ("c");
## ember is never traded here, it only pays the fees. Time is play: one tick per map completed.
## A `wallet` is a currency dictionary like `player.cur` that trades take from and pay into.

const TICKS_PER_DAY := 10
const HISTORY_DAYS := 60
const MAX_ORDERS := 8
const ORDER_LIFE := 50          # ticks before what is left of an order goes back
const STAGE_DAYS := 30.0        # market days from `early` to `late`
const PULL := 0.15              # share of the gap to the target closed each tick
const NOISE := 0.03
const IMPACT := 0.5
const FILL_BASE := 0.3
const FILL_FALLOFF := 8.0
const FEE_MIN := 5
const FEE_PER_C := 8.0
const BASE := "chaos"

# per traded currency: early/late season multipliers, market depth, spread
const PARAMS := {
	"transmute": {"early": 1.5, "late": 0.7, "depth": 300.0, "spread": 0.06},
	"purify": {"early": 1.5, "late": 0.7, "depth": 150.0, "spread": 0.06},
	"compass": {"early": 1.2, "late": 0.9, "depth": 150.0, "spread": 0.08},
	"whet": {"early": 1.2, "late": 0.9, "depth": 150.0, "spread": 0.08},
	"ascend": {"early": 1.2, "late": 0.9, "depth": 100.0, "spread": 0.08},
	"divine": {"early": 0.8, "late": 1.6, "depth": 30.0, "spread": 0.12},
}

static var rng := RandomNumberGenerator.new()


# =================== state ===================
## the currencies the exchange trades, in CURRENCIES order (no ember, no chaos)
static func keys() -> Array:
	return Data.CURRENCIES.filter(func(c): return PARAMS.has(c.k)).map(func(c): return c.k)


## the league's market, made on first use
static func state(league: String, d := Profiles.data) -> Dictionary:
	if typeof(d.get("market")) != TYPE_DICTIONARY:
		d.market = {}
	if typeof(d.market.get(league)) != TYPE_DICTIONARY:
		d.market[league] = fresh(league)
	return d.market[league]


## a new market: every price starts at its day-0 target (a season's `early`, standard's `late`)
static func fresh(league: String) -> Dictionary:
	var m := {"tick": 0, "next_id": 1, "prices": {}, "orders": [], "history": {}, "pending": []}
	for k in keys():
		m.prices[k] = target(league, k, 0.0)
		m.history[k] = []
	return m


## fill in anything an older or hand-edited save lacks (JSON turns ints into floats)
static func normalize(league: String, m: Dictionary) -> void:
	m.tick = int(m.get("tick", 0))
	m.next_id = int(m.get("next_id", 1))
	if typeof(m.get("prices")) != TYPE_DICTIONARY:
		m.prices = {}
	if typeof(m.get("history")) != TYPE_DICTIONARY:
		m.history = {}
	for k in keys():
		m.prices[k] = clampf(float(m.prices.get(k, target(league, k, day(m)))), floor_price(k), ceil_price(k))
		m.history[k] = Array(m.history.get(k, [])).map(func(v): return float(v))
	m.orders = Array(m.get("orders", [])).filter(func(o): return typeof(o) == TYPE_DICTIONARY and PARAMS.has(o.get("k", ""))).map(func(o):
		return {"id": int(o.get("id", 0)), "side": "buy" if o.get("side") == "buy" else "sell", "k": o.k,
			"qty": int(o.get("qty", 0)), "filled": int(o.get("filled", 0)), "limit": float(o.get("limit", 1.0)),
			"placed_tick": int(o.get("placed_tick", 0)), "escrow": int(o.get("escrow", 0)), "fee_escrow": int(o.get("fee_escrow", 0)),
			"value": float(o.get("value", 0.0)), "paid": int(o.get("paid", 0))})
	m.pending = Array(m.get("pending", [])).map(func(s): return str(s))


static func day(m: Dictionary) -> float:
	return m.tick / float(TICKS_PER_DAY)


static func is_season(league: String) -> bool:
	return league != Profiles.STANDARD and not Data.season(league).is_empty()


# =================== prices ===================
static func base_value(k: String) -> float:
	if k == BASE:
		return 1.0
	return float(Data.currency(k).get("value", 0)) / float(Data.currency(BASE).value)


static func floor_price(k: String) -> float:
	return 0.25 * base_value(k)


static func ceil_price(k: String) -> float:
	return 4.0 * base_value(k)


## season stage multiplier: `early` moving smoothly to `late` over the first 30 market days; standard is always `late`
static func stage_mult(league: String, k: String, d: float) -> float:
	var pr: Dictionary = PARAMS[k]
	if not is_season(league):
		return pr.late
	return lerpf(pr.early, pr.late, smoothstep(0.0, STAGE_DAYS, d))


## product of the multipliers of the season events running on market day `d`
static func event_mult(league: String, k: String, d: float) -> float:
	var mult := 1.0
	for e in events(league):
		if e.k == k and d >= e.start and d < e.start + e.days:
			mult *= e.mult
	return mult


## P* = base value × stage × events
static func target(league: String, k: String, d: float) -> float:
	if k == BASE:
		return 1.0
	return base_value(k) * stage_mult(league, k, d) * event_mult(league, k, d)


static func _set_price(m: Dictionary, k: String, p: float) -> void:
	m.prices[k] = clampf(p, floor_price(k), ceil_price(k))


## the price move of the player trading `q` units (positive buys, negative sells)
static func _impact(m: Dictionary, k: String, q: float) -> void:
	_set_price(m, k, m.prices[k] * (1.0 + IMPACT * q / PARAMS[k].depth))


# =================== season events ===================
## 3-5 events fixed by the season id: {k, mult, start, days}; standard has none
static func events(league: String) -> Array:
	if not is_season(league):
		return []
	var r := RandomNumberGenerator.new()
	r.seed = league.hash()
	var ks := keys()
	var out := []
	for i in r.randi_range(3, 5):
		out.append({"k": ks[r.randi() % ks.size()], "mult": snappedf(r.randf_range(0.6, 1.8), 0.05),
			"start": r.randi_range(2, 40), "days": r.randi_range(3, 8)})
	out.sort_custom(func(a, b): return a.start < b.start)
	return out


# =================== time ===================
## one market tick: prices drift to their targets, limit orders fill or expire, and a market day may close.
## What fills is paid into `wallet` right away; the lines for the player pile up in `pending`.
static func tick(league: String, wallet: Dictionary, m := state(league)) -> void:
	m.tick += 1
	var d := day(m)
	for k in keys():
		var p: float = m.prices[k]
		_set_price(m, k, p + PULL * (target(league, k, d) - p) + NOISE * p * rng.randfn(0.0, 1.0))
	for o in m.orders.duplicate():
		_fill_tick(m, o, wallet)
	for o in m.orders.duplicate():
		if o.filled >= o.qty:
			_close(m, o, wallet)
			m.pending.append("%s の%s注文 %d 個がすべて成立しました" % [Data.currency(o.k).name, _side_name(o.side), o.qty])
		elif m.tick - o.placed_tick >= ORDER_LIFE:
			var left: int = o.qty - o.filled
			_close(m, o, wallet)
			m.pending.append("%s の%s注文が期限切れ：成立 %d 個、残り %d 個を返却しました" % [Data.currency(o.k).name, _side_name(o.side), o.filled, left])
	if m.tick % TICKS_PER_DAY == 0:
		for k in keys():
			m.history[k].append(m.prices[k])
			if m.history[k].size() > HISTORY_DAYS:
				m.history[k] = m.history[k].slice(-HISTORY_DAYS)
	for e in events(league):
		if int(d) == e.start - 1 and m.tick % TICKS_PER_DAY == 0:
			m.pending.append("相場掲示板：明日から %s" % event_text(e))


static func _side_name(side: String) -> String:
	return "買い" if side == "buy" else "売り"


static func event_text(e: Dictionary) -> String:
	var cname: String = Data.currency(e.k).name
	return "%s%s：市場日 %d〜%d、需要 ×%.2f" % [cname, "ブーム" if e.mult >= 1.0 else "暴落", e.start, e.start + e.days - 1, e.mult]


# =================== market orders ===================
## quote a market buy or sell of `qty`, unit by unit as the price moves: {total (c), avg, chaos, fee, end_price}
## `chaos` is what changes hands: buys round the cost up, sells round the proceeds down
static func quote(league: String, k: String, side: String, qty: int, m := state(league)) -> Dictionary:
	var s: float = PARAMS[k].spread / 2.0
	var p: float = m.prices[k]
	var total := 0.0
	for i in qty:
		total += p * (1.0 + s if side == "buy" else 1.0 - s)
		p = clampf(p * (1.0 + IMPACT * (1.0 if side == "buy" else -1.0) / PARAMS[k].depth), floor_price(k), ceil_price(k))
	var chaos := ceili(total - 1e-9) if side == "buy" else floori(total + 1e-9)
	return {"total": total, "avg": total / maxf(qty, 1), "chaos": chaos, "fee": fee(total), "end_price": p}


static func fee(value_c: float) -> int:
	return maxi(FEE_MIN, ceili(value_c * FEE_PER_C - 1e-9))


## trade at once; returns "" on success or why it could not
static func market_trade(league: String, k: String, side: String, qty: int, wallet: Dictionary, m := state(league)) -> String:
	if not PARAMS.has(k) or qty <= 0:
		return "取引できません"
	var q := quote(league, k, side, qty, m)
	if wallet.get("ember", 0) < q.fee:
		return "手数料の灰燼の欠片が足りない（%d 必要）" % q.fee
	if side == "buy":
		if wallet.get(BASE, 0) < q.chaos:
			return "混沌の残光が足りない（%d 必要）" % q.chaos
		wallet[BASE] -= q.chaos
		wallet[k] = wallet.get(k, 0) + qty
	else:
		if wallet.get(k, 0) < qty:
			return "%s が足りない" % Data.currency(k).name
		wallet[k] -= qty
		wallet[BASE] = wallet.get(BASE, 0) + q.chaos
	wallet.ember -= q.fee
	m.prices[k] = q.end_price
	return ""


# =================== limit orders ===================
## share of what is left that fills in one tick at price `limit` (1 means it trades at once)
static func fill_rate(league: String, k: String, side: String, limit: float, m := state(league)) -> float:
	var p: float = m.prices[k]
	var over := limit / p - 1.0 if side == "sell" else p / limit - 1.0
	if over <= 0.0:
		return 1.0
	return FILL_BASE * exp(-FILL_FALLOFF * over)


## what the order screen shows before placing: {rate, ticks (-1: unlikely before it expires), fee, cost, instant}
static func limit_estimate(league: String, k: String, side: String, limit: float, qty: int, m := state(league)) -> Dictionary:
	var f := fill_rate(league, k, side, limit, m)
	var ticks := 0 if f >= 1.0 else ceili(log(0.5 / maxf(qty, 1)) / log(1.0 - f))
	if f < 1.0 and ticks < 1:
		ticks = 1
	if ticks > ORDER_LIFE:
		ticks = -1
	return {"rate": f, "ticks": ticks, "fee": fee(limit * qty), "cost": ceili(limit * qty - 1e-9) if side == "buy" else qty,
		"instant": f >= 1.0}


## place an order: the currency (or chaos for a buy) and the full fee are held until it closes;
## an order at or through the current price trades at once as a market order. Returns "" or why not.
static func place_limit(league: String, k: String, side: String, limit: float, qty: int, wallet: Dictionary, m := state(league)) -> String:
	if not PARAMS.has(k) or qty <= 0 or limit <= 0.0:
		return "注文できません"
	if fill_rate(league, k, side, limit, m) >= 1.0:
		return market_trade(league, k, side, qty, wallet, m)
	if m.orders.size() >= MAX_ORDERS:
		return "注文は %d 件までです" % MAX_ORDERS
	var fe := fee(limit * qty)
	var escrow := ceili(limit * qty - 1e-9) if side == "buy" else qty
	var pay := BASE if side == "buy" else k
	if wallet.get("ember", 0) < fe:
		return "手数料の灰燼の欠片が足りない（%d 必要）" % fe
	if wallet.get(pay, 0) < escrow:
		return "%s が足りない（%d 必要）" % [Data.currency(pay).name, escrow]
	wallet[pay] -= escrow
	wallet.ember -= fe
	m.orders.append({"id": m.next_id, "side": side, "k": k, "qty": qty, "filled": 0, "limit": limit,
		"placed_tick": m.tick, "escrow": escrow, "fee_escrow": fe, "value": 0.0, "paid": 0})
	m.next_id += 1
	return ""


static func _fill_tick(m: Dictionary, o: Dictionary, wallet: Dictionary) -> void:
	var left: int = o.qty - o.filled
	if left <= 0:
		return
	var p: float = m.prices[o.k]
	var over: float = o.limit / p - 1.0 if o.side == "sell" else p / o.limit - 1.0
	var f := 1.0 if over <= 0.0 else FILL_BASE * exp(-FILL_FALLOFF * over)
	var want := left * f
	var n := mini(left, int(want) + (1 if rng.randf() < want - int(want) else 0))
	if n <= 0:
		return
	o.filled += n
	o.value += n * o.limit
	_impact(m, o.k, n if o.side == "buy" else -n)
	if o.side == "sell":
		var due := floori(o.value + 1e-9) - int(o.paid)
		wallet[BASE] = wallet.get(BASE, 0) + due
		o.paid += due
		m.pending.append("%s %d 個が %.2fc で売れました（+%d 混沌）" % [Data.currency(o.k).name, n, o.limit, due])
	else:
		wallet[o.k] = wallet.get(o.k, 0) + n
		m.pending.append("%s %d 個を %.2fc で買えました" % [Data.currency(o.k).name, n, o.limit])


## what an order hands back when it closes: the unfilled currency (or unspent chaos) and the unused fee
static func _refund(o: Dictionary) -> Dictionary:
	var spent_fee := fee(o.value) if o.filled > 0 else 0
	var back := {"ember": maxi(0, o.fee_escrow - spent_fee)}
	if o.side == "sell":
		back[o.k] = o.qty - o.filled
	else:
		back[BASE] = maxi(0, o.escrow - ceili(o.value - 1e-9))
	return back


static func _close(m: Dictionary, o: Dictionary, wallet: Dictionary) -> void:
	var back := _refund(o)
	for c in back:
		wallet[c] = wallet.get(c, 0) + back[c]
	m.orders.erase(o)


## take an order down; its held currency goes back to `wallet`. Returns false if there is no such order.
static func cancel(league: String, id: int, wallet: Dictionary, m := state(league)) -> bool:
	for o in m.orders:
		if o.id == id:
			_close(m, o, wallet)
			return true
	return false


## a market that is being thrown away (its season ended): everything its orders still hold, as one currency dictionary
static func dissolve(m: Dictionary) -> Dictionary:
	var out := {}
	for o in Array(m.get("orders", [])):
		var r := _refund(o)
		for c in r:
			out[c] = out.get(c, 0) + r[c]
	return out


# =================== views for the screens ===================
static func price(league: String, k: String) -> float:
	return 1.0 if k == BASE else float(state(league).prices[k])


## change since the last market day's close, as a fraction (0.05 = +5%); 0 before the first close
static func day_change(league: String, k: String) -> float:
	var h: Array = state(league).history.get(k, [])
	if h.is_empty():
		return 0.0
	return price(league, k) / h[-1] - 1.0


## the closing prices of the last `days` market days, oldest first
static func history(league: String, k: String, days := 14) -> Array:
	var h: Array = state(league).history.get(k, [])
	return h.slice(-days) if h.size() > days else h.duplicate()


## the open orders, with `left` and `ticks_left` added
static func orders(league: String) -> Array:
	var m := state(league)
	return m.orders.map(func(o):
		var v: Dictionary = o.duplicate()
		v.left = o.qty - o.filled
		v.ticks_left = ORDER_LIFE - (m.tick - o.placed_tick)
		return v)


## events for the notice board: running ones and those starting tomorrow, each with `state` "active" or "soon" and `text`
static func board(league: String) -> Array:
	var d := floorf(day(state(league)))
	var out := []
	for e in events(league):
		var st := "active" if d >= e.start and d < e.start + e.days else ("soon" if d == e.start - 1 else "")
		if st != "":
			var v: Dictionary = e.duplicate()
			v.state = st
			v.text = event_text(e)
			out.append(v)
	return out


## the fill lines piled up since the player last came back; clears them
static func take_notes(league: String) -> Array:
	var m := state(league)
	var out: Array = m.pending.duplicate()
	m.pending.clear()
	return out
