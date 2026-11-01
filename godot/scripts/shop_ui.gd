class_name ShopUI
extends PanelContainer
## The hideout merchant: buy items, potions and currency with ember shards, sell from the bag.

var hud: Hud
var gold := Label.new()
var stock_grid := GridContainer.new()
var bag_grid := GridContainer.new()
var cur_grid := GridContainer.new()
var gem_grid := GridContainer.new()
var potion_btn := Button.new()
var reroll_btn := Button.new()
var bag_count := Label.new()



func _ready() -> void:
	add_theme_stylebox_override("panel", Hud.panel_box())
	visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := Label.new()
	title.text = "商人"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#f0d8a0"))
	head.add_child(title)
	gold.add_theme_color_override("font_color", Data.currency("ember").color)
	gold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(gold)
	var close := Button.new()
	close.text = "×"
	close.pressed.connect(open_close)
	head.add_child(close)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	col.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	left.add_child(_sub("品揃え（クリックで購入）"))
	stock_grid.columns = 4
	stock_grid.add_theme_constant_override("h_separation", 6)
	stock_grid.add_theme_constant_override("v_separation", 4)
	left.add_child(stock_grid)
	for b in [potion_btn, reroll_btn]:
		b.custom_minimum_size = Vector2(0, 32)
		left.add_child(b)
	potion_btn.pressed.connect(_buy_potion)
	reroll_btn.pressed.connect(_reroll)
	left.add_child(_sub("カレンシー交換"))
	cur_grid.columns = 2
	cur_grid.add_theme_constant_override("h_separation", 4)
	cur_grid.add_theme_constant_override("v_separation", 4)
	left.add_child(cur_grid)
	left.add_child(_sub("サポートジェム"))
	gem_grid.columns = 2
	gem_grid.add_theme_constant_override("h_separation", 4)
	gem_grid.add_theme_constant_override("v_separation", 4)
	left.add_child(gem_grid)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	right.add_child(_sub("所持品（クリックで売却）"))
	bag_grid.columns = 6
	bag_grid.add_theme_constant_override("h_separation", 4)
	bag_grid.add_theme_constant_override("v_separation", 4)
	right.add_child(bag_grid)
	bag_count.add_theme_font_size_override("font_size", 13)
	bag_count.add_theme_color_override("font_color", Color("#b8a888"))
	right.add_child(bag_count)


func _sub(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color("#b8a888"))
	return l


func open_close() -> void:
	visible = not visible
	hud.hide_tip()
	if visible:
		refresh()
		_center.call_deferred()


func _center() -> void:
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


func refresh() -> void:
	if not visible:
		return
	var m = hud.main
	var p: Player = m.player
	var lvl: int = m.shop.level
	gold.text = "◆ %d" % p.cur.ember
	for c in stock_grid.get_children():
		c.free()
	for it in m.shop.items:
		var cost := Items.buy_price(it)
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 1)
		var sl := ItemSlot.new()
		sl.custom_minimum_size = Vector2(60, 60)
		sl.item = it
		sl.hud = hud
		sl.compare = true
		sl.extra = [["価格 %d 灰燼の欠片" % cost, Color("#ffcf3a"), 13]]
		sl.clicked.connect(_buy.bind(it))
		cell.add_child(sl)
		var price := Label.new()
		price.text = "◆ %d" % cost
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price.add_theme_font_size_override("font_size", 12)
		price.add_theme_color_override("font_color", Color("#ffb35a") if p.cur.ember >= cost else Color("#8a5a40"))
		cell.add_child(price)
		stock_grid.add_child(cell)
	var pp := Items.potion_price(lvl)
	potion_btn.text = "回復薬を買う（◆ %d）　所持 %d/%d" % [pp, p.potions, p.max_potions()]
	potion_btn.disabled = p.cur.ember < pp or p.potions >= p.max_potions()
	var rp := Items.reroll_price(lvl)
	reroll_btn.text = "品揃えを入れ替える（◆ %d）" % rp
	reroll_btn.disabled = p.cur.ember < rp
	for c in cur_grid.get_children():
		c.free()
	for cdef in Data.CURRENCIES:
		if cdef.w <= 0.0:
			continue
		var cost := Items.currency_price(cdef)
		var b := Button.new()
		b.text = "%s %s  ◆%d" % [cdef.icon, cdef.name, cost]
		b.add_theme_color_override("font_color", cdef.color)
		b.add_theme_font_size_override("font_size", 13)
		b.custom_minimum_size = Vector2(170, 28)
		b.disabled = p.cur.ember < cost
		b.tooltip_text = "%s\n所持数 %d" % [cdef.desc, p.cur[cdef.k]]
		b.pressed.connect(_buy_currency.bind(cdef.k, cost))
		cur_grid.add_child(b)
	for c in gem_grid.get_children():
		c.free()
	var missing := Data.SUPPORTS.filter(func(g): return not g.id in p.gems)
	if missing.is_empty():
		gem_grid.add_child(_sub("すべて入手済み"))
	for g in missing:
		var b := Button.new()
		b.text = "◇ %s  ◆%d" % [g.name, Items.gem_price()]
		b.add_theme_color_override("font_color", g.color)
		b.add_theme_font_size_override("font_size", 13)
		b.custom_minimum_size = Vector2(170, 28)
		b.disabled = p.cur.ember < Items.gem_price()
		b.mouse_entered.connect(func(): hud.show_tip(SkillUI.gem_tip(g)))
		b.mouse_exited.connect(func(): hud.hide_tip())
		b.pressed.connect(_buy_gem.bind(g.id))
		gem_grid.add_child(b)
	for c in bag_grid.get_children():
		c.free()
	for i in Player.BAG_SIZE:
		var sl := ItemSlot.new()
		sl.custom_minimum_size = Vector2(52, 52)
		sl.hud = hud
		if i < p.bag.size():
			sl.item = p.bag[i]
			sl.compare = true
			sl.extra = [["売却額 %d 灰燼の欠片" % Items.sell_price(p.bag[i]), Color("#ffcf3a"), 13]]
		sl.clicked.connect(_sell.bind(i))
		bag_grid.add_child(sl)
	bag_count.text = "所持品 %d / %d" % [p.bag.size(), Player.BAG_SIZE]


func _buy(it: Dictionary) -> void:
	var m = hud.main
	var p: Player = m.player
	var cost := Items.buy_price(it)
	if p.cur.ember < cost:
		hud.message("灰燼の欠片が足りない", Color("#ff8080"))
		return
	if p.bag.size() >= Player.BAG_SIZE:
		hud.message("インベントリが一杯です", Color("#ff8080"))
		return
	p.cur.ember -= cost
	m.shop.items.erase(it)
	p.bag.append(it)
	hud.message("%s を購入（%d 灰燼の欠片）" % [it.name, cost], Data.RARITY[it.rarity].color)
	hud.hide_tip()
	refresh()


func _sell(i: int) -> void:
	var p: Player = hud.main.player
	if i >= p.bag.size():
		return
	var it: Dictionary = p.bag[i]
	var g := Items.sell_price(it)
	p.bag.remove_at(i)
	p.cur.ember += g
	hud.message("%s を売却（%d 灰燼の欠片）" % [it.name, g], Color("#ffcf3a"))
	hud.hide_tip()
	refresh()


func _buy_potion() -> void:
	var p: Player = hud.main.player
	var cost := Items.potion_price(hud.main.shop.level)
	if p.cur.ember < cost or p.potions >= p.max_potions():
		return
	p.cur.ember -= cost
	p.potions += 1
	refresh()


func _reroll() -> void:
	var m = hud.main
	var p: Player = m.player
	var cost := Items.reroll_price(m.shop.level)
	if p.cur.ember < cost:
		return
	p.cur.ember -= cost
	m.shop = Items.gen_shop(m.shop.level)
	refresh()


func _buy_currency(k: String, cost: int) -> void:
	var p: Player = hud.main.player
	if p.cur.ember < cost:
		return
	p.cur.ember -= cost
	p.cur[k] += 1
	refresh()


func _buy_gem(id: String) -> void:
	var p: Player = hud.main.player
	if p.cur.ember < Items.gem_price() or id in p.gems:
		return
	p.cur.ember -= Items.gem_price()
	hud.main.unlock_gem(id)
	hud.hide_tip()
	refresh()
