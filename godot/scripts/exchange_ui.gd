class_name ExchangeUI
extends BasePanel
## The hideout currency exchange (docs/economy-design.md section 7): prices in chaos with a 14-day
## sparkline, market and limit orders with a quote before trading, the open orders and the notice board.

const UP := Color("#8ad08a")
const DOWN := Color("#ff8a7a")
const DIM := Color("#8a7a60")

var wallet_label := Label.new()
var day_label := Label.new()
var price_grid := GridContainer.new()
var pick_label := Label.new()
var side_row := HBoxContainer.new()
var mode_row := HBoxContainer.new()
var qty := SpinBox.new()
var limit := SpinBox.new()
var limit_row := HBoxContainer.new()
var est_box := VBoxContainer.new()
var go := Button.new()
var error := Label.new()
var order_box := VBoxContainer.new()
var board_box := VBoxContainer.new()
var k := ""
var side := "buy"
var mode := "market"


func _title() -> String:
	return "取引所"


func _hint() -> String:
	return "相場はすべて混沌の残光（c）建て。手数料は灰燼の欠片"


func _build() -> void:
	var top := HBoxContainer.new()
	body.add_child(top)
	day_label.add_theme_font_size_override("font_size", 13)
	day_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(day_label)
	wallet_label.add_theme_font_size_override("font_size", 14)
	wallet_label.add_theme_color_override("font_color", Color("#e8d8b0"))
	top.add_child(wallet_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	body.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	left.add_child(sub("相場一覧（クリックで売買する通貨を選ぶ）"))
	price_grid.columns = 4
	price_grid.add_theme_constant_override("h_separation", 12)
	price_grid.add_theme_constant_override("v_separation", 4)
	left.add_child(price_grid)
	left.add_child(sub("相場掲示板"))
	board_box.add_theme_constant_override("separation", 3)
	left.add_child(board_box)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size = Vector2(360, 0)
	row.add_child(right)
	right.add_child(sub("売買"))
	pick_label.add_theme_font_size_override("font_size", 16)
	right.add_child(pick_label)
	for r in [side_row, mode_row]:
		r.add_theme_constant_override("separation", 4)
		right.add_child(r)
	for s in [["buy", "買う"], ["sell", "売る"]]:
		side_row.add_child(_toggle(s[1], func():
			side = s[0]
			_reset_limit()
			refresh()))
	for s in [["market", "成行（すぐに成立）"], ["limit", "指値（出品して待つ）"]]:
		mode_row.add_child(_toggle(s[1], func():
			mode = s[0]
			refresh()))
	var qty_row := HBoxContainer.new()
	qty_row.add_child(sub("数量", 14))
	qty.min_value = 1
	qty.max_value = 999
	qty.value = 1
	qty.custom_minimum_size = Vector2(110, 0)
	qty.value_changed.connect(func(_v): _estimate())
	qty_row.add_child(qty)
	right.add_child(qty_row)
	limit_row.add_child(sub("指値（1個あたり c）", 14))
	limit.min_value = 0.01
	limit.max_value = 999
	limit.step = 0.01
	limit.custom_minimum_size = Vector2(110, 0)
	limit.value_changed.connect(func(_v): _estimate())
	limit_row.add_child(limit)
	right.add_child(limit_row)
	est_box.add_theme_constant_override("separation", 2)
	est_box.custom_minimum_size = Vector2(0, 84)
	right.add_child(est_box)
	go.custom_minimum_size = Vector2(0, 34)
	go.pressed.connect(execute)
	right.add_child(go)
	error.add_theme_font_size_override("font_size", 13)
	error.add_theme_color_override("font_color", Color("#ff8080"))
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(error)
	right.add_child(sub("注文一覧（最大 %d 件、%d ティックで期限切れ）" % [Market.MAX_ORDERS, Market.ORDER_LIFE]))
	order_box.add_theme_constant_override("separation", 4)
	right.add_child(SkillUI._scroll(order_box, Vector2(360, 150)))


func _toggle(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.add_theme_font_size_override("font_size", 13)
	b.custom_minimum_size = Vector2(0, 28)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(on_press)
	return b


func league() -> String:
	return hud.main.league()


func wallet() -> Dictionary:
	return hud.main.player.cur


func open_close() -> void:
	if not visible and k == "":
		select(Market.keys()[0])
	error.text = ""
	super.open_close()


## pick the currency to trade; the limit price starts just past the current price
func select(key: String) -> void:
	k = key
	error.text = ""
	_reset_limit()
	refresh()


func _reset_limit() -> void:
	if k == "":
		return
	var p := Market.price(league(), k)
	limit.value = snappedf(p * (1.05 if side == "sell" else 0.95), 0.01)


func refresh() -> void:
	if not visible:
		return
	var lg := league()
	var w := wallet()
	var m := Market.state(lg)
	day_label.text = "%s の相場　市場日 %d（ティック %d）　マップを1つ踏破するごとに 1 ティック進む" % [Profiles.league_name(lg), int(Market.day(m)), m.tick]
	day_label.add_theme_color_override("font_color", Data.season(lg).get("color", Color("#c8b898")))
	wallet_label.text = "◆ %d　✺ %d" % [w.get("ember", 0), w.get(Market.BASE, 0)]
	clear(price_grid)
	for h in ["通貨", "現在価格", "前日比", "直近 14 市場日"]:
		price_grid.add_child(sub(h, 12, DIM))
	for key in Market.keys():
		var c := Data.currency(key)
		var b := Button.new()
		b.text = "%s %s" % [c.icon, c.name]
		b.toggle_mode = true
		b.button_pressed = key == k
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", c.color)
		b.add_theme_font_size_override("font_size", 13)
		b.custom_minimum_size = Vector2(150, 28)
		b.tooltip_text = "%s\n所持数 %d" % [c.desc, w.get(key, 0)]
		b.pressed.connect(select.bind(key))
		price_grid.add_child(b)
		var p := Market.price(lg, key)
		var pl := sub("%.2fc" % p, 14, Color("#f0e0c0"))
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price_grid.add_child(pl)
		var ch := Market.day_change(lg, key)
		var cl := sub("%+.1f%%" % (ch * 100.0), 13, UP if ch > 0.0005 else (DOWN if ch < -0.0005 else DIM))
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price_grid.add_child(cl)
		var sp := Spark.new()
		sp.values = Market.history(lg, key) + [p]
		sp.color = c.color
		price_grid.add_child(sp)
	clear(board_box)
	var board := Market.board(lg)
	if board.is_empty():
		board_box.add_child(sub("いまは知らせはない" if Market.is_season(lg) else "スタンダードリーグには相場の出来事はない", 13, DIM))
	for e in board:
		var active: bool = e.state == "active"
		board_box.add_child(sub(("【開催中】" if active else "【明日から】") + e.text, 13,
			(UP if e.mult >= 1.0 else DOWN) if active else Color("#e8d8b0")))
	for i in 2:
		side_row.get_child(i).button_pressed = side == ["buy", "sell"][i]
		mode_row.get_child(i).button_pressed = mode == ["market", "limit"][i]
	var pc := Data.currency(k)
	pick_label.text = "%s %s　所持 %d　現在 %.2fc" % [pc.icon, pc.name, w.get(k, 0), Market.price(lg, k)]
	pick_label.add_theme_color_override("font_color", pc.color)
	limit_row.visible = mode == "limit"
	clear(order_box)
	var orders := Market.orders(lg)
	if orders.is_empty():
		order_box.add_child(sub("出している注文はない", 13, DIM))
	for o in orders:
		order_box.add_child(_order_row(o))
	_estimate()


func _order_row(o: Dictionary) -> Control:
	var c := Data.currency(o.k)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var l := sub("%s %s を %.2fc で%s　%d / %d 個　残り %d ティック" % [c.icon, c.name, o.limit, "買い" if o.side == "buy" else "売り",
		o.filled, o.qty, o.ticks_left], 13, c.color)
	col.add_child(l)
	var bar := Hud.Bar.new()
	bar.custom_minimum_size = Vector2(0, 5)
	bar.fill = c.color
	bar.value = o.filled / float(o.qty)
	col.add_child(bar)
	var x := Button.new()
	x.text = "取り消す"
	x.add_theme_font_size_override("font_size", 12)
	x.pressed.connect(cancel.bind(o.id))
	row.add_child(x)
	return row


## the quote for what is set up now, and the trade button's label
func _estimate() -> void:
	if k == "" or not is_node_ready():
		return
	clear(est_box)
	var lg := league()
	var w := wallet()
	var n := int(qty.value)
	var verb := "買う" if side == "buy" else "売る"
	var fee := 0
	if mode == "market":
		var q := Market.quote(lg, k, side, n)
		fee = q.fee
		est_box.add_child(sub("%s混沌：✺ %d（平均 %.2fc／個）" % ["払う" if side == "buy" else "受け取る", q.chaos, q.avg], 14, Color("#f0e0c0")))
		est_box.add_child(sub("取引後の相場：%.2fc（%+.1f%%）" % [q.end_price, (q.end_price / Market.price(lg, k) - 1.0) * 100.0], 13))
		go.text = "成行で %d 個%s" % [n, verb]
	else:
		var e := Market.limit_estimate(lg, k, side, limit.value, n)
		fee = e.fee
		if e.instant:
			est_box.add_child(sub("現在価格を越えているので、成行としてすぐに成立する", 14, Color("#ffd36a")))
			var q := Market.quote(lg, k, side, n)
			fee = q.fee
			est_box.add_child(sub("%s混沌：✺ %d" % ["払う" if side == "buy" else "受け取る", q.chaos], 13))
		else:
			est_box.add_child(sub("預ける：%s" % ("✺ %d 混沌" % e.cost if side == "buy" else "%s %d 個" % [Data.currency(k).name, e.cost]), 14, Color("#f0e0c0")))
			est_box.add_child(sub("1 ティックで残りの %.1f%% が成立" % (e.rate * 100.0), 13))
			est_box.add_child(sub("約 %d ティックで成立しそう" % e.ticks if e.ticks > 0 else "期限（%d ティック）内に全部成立するのは難しい" % Market.ORDER_LIFE,
				14, Color("#c070ff") if e.ticks > 0 else DOWN))
		go.text = "指値で %d 個%s注文を出す" % [n, "買い" if side == "buy" else "売り"]
	est_box.add_child(sub("手数料：◆ %d 灰燼の欠片%s" % [fee, "" if mode == "market" else "（預けて、成立した分だけ払う）"], 13,
		Data.currency("ember").color if w.get("ember", 0) >= fee else DOWN))


func execute() -> void:
	var lg := league()
	var n := int(qty.value)
	var before := Market.orders(lg).size()
	var err := Market.market_trade(lg, k, side, n, wallet()) if mode == "market" \
		else Market.place_limit(lg, k, side, limit.value, n, wallet())
	error.text = err
	if err != "":
		hud.message(err, Color("#ff8080"))
		return
	var cname: String = Data.currency(k).name
	if Market.orders(lg).size() > before:
		hud.message("%s %d 個の%s注文を %.2fc で出した" % [cname, n, "買い" if side == "buy" else "売り", limit.value], Color("#c070ff"))
	else:
		hud.message("%s %d 個を%s" % [cname, n, "買った" if side == "buy" else "売った"], Color("#c070ff"))
	_traded()


func cancel(id: int) -> void:
	if Market.cancel(league(), id, wallet()):
		hud.message("注文を取り消し、預けていた分を受け取った", Color("#e8d8b0"))
		_traded()


## the market is shared by the league, so every trade is written at once with the character
func _traded() -> void:
	hud.main.save_game()
	hud.refresh_inventory()
	refresh()


## a 14-day price line; the last point is the current price
class Spark extends Control:
	var values: Array = []
	var color := Color.WHITE

	func _init() -> void:
		custom_minimum_size = Vector2(110, 26)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#1a1610"))
		if values.size() < 2:
			return
		var lo: float = values.min()
		var hi: float = values.max()
		var span := maxf(hi - lo, hi * 0.02)
		var pts := PackedVector2Array()
		for i in values.size():
			pts.append(Vector2(2 + (size.x - 4) * i / (values.size() - 1), size.y - 3 - (size.y - 6) * (values[i] - lo) / span))
		draw_polyline(pts, color, 1.5, true)
		draw_circle(pts[-1], 2.2, color)
