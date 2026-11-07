class_name ShopUI
extends PanelContainer
## The hideout merchant: buy gear, rune tablets, jewels, ember shells, gems, potions and currency with ember shards,
## sell gear from the bag. The stock sits under tabs; only the open tab's wares are built.

var hud: Hud
var gold := Label.new()
var stock_grid := GridContainer.new()   # gear
var ware_grid := GridContainer.new()    # tablets, jewels or ember shells, whichever tab is open
var bag_grid := GridContainer.new()
var cur_grid := GridContainer.new()
var gem_grid := GridContainer.new()
var potion_btn := Button.new()
var reroll_btn := Button.new()
var bag_count := Label.new()
var scroll := ScrollContainer.new()
var note := Label.new()
var filter_row := HBoxContainer.new()
var slot_pick := OptionButton.new()
var rarity_pick := OptionButton.new()
var tab_btns := {}
var tab := "gear"
var slot_filter := ""     # "" = every slot
var rarity_filter := -1   # -1 = every rarity
const GEM_AHEAD := 3   # the merchant stocks gems needing at most the character's level + this
const TABS := [["gear", "装備"], ["tablets", "ルーンタブレット"], ["jewels", "ジュエル"], ["charms", "コンパス"], ["gems", "ジェム"], ["currency", "カレンシー"]]



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
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	left.add_child(tabs)
	var group := ButtonGroup.new()
	for t in TABS:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = t[0] == tab
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(set_tab.bind(t[0]))
		tabs.add_child(b)
		tab_btns[t[0]] = b
	filter_row.add_theme_constant_override("separation", 6)
	left.add_child(filter_row)
	slot_pick.add_item("全部位")
	for k in Data.SLOTS:
		slot_pick.add_item(Data.SLOT_INFO[k].name)
	slot_pick.item_selected.connect(func(i: int):
		slot_filter = "" if i == 0 else Data.SLOTS[i - 1]
		_show_tab(true))
	rarity_pick.add_item("全レアリティ")
	for r in Data.RARITY:
		rarity_pick.add_item(r.name)
	rarity_pick.item_selected.connect(func(i: int):
		rarity_filter = i - 1
		_show_tab(true))
	for o in [slot_pick, rarity_pick]:
		o.add_theme_font_size_override("font_size", 13)
		filter_row.add_child(o)
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color("#b8a888"))
	left.add_child(note)
	var inner := VBoxContainer.new()
	for g in [stock_grid, ware_grid, gem_grid, cur_grid]:
		g.add_theme_constant_override("h_separation", 6)
		g.add_theme_constant_override("v_separation", 4)
		inner.add_child(g)
	stock_grid.columns = 7
	gem_grid.columns = 2
	cur_grid.columns = 2
	scroll.custom_minimum_size = Vector2(500, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(inner)
	left.add_child(scroll)
	for b in [potion_btn, reroll_btn]:
		b.custom_minimum_size = Vector2(0, 32)
		left.add_child(b)
	potion_btn.pressed.connect(_buy_potion)
	reroll_btn.pressed.connect(_reroll)

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


## switch the stock tab (装備 / ルーンタブレット / ジュエル / コンパス / ジェム / カレンシー)
func set_tab(k: String) -> void:
	tab = k
	if tab_btns.has(k):
		tab_btns[k].set_pressed_no_signal(true)
	hud.hide_tip()
	_show_tab(true)


func refresh() -> void:
	if not visible:
		return
	var m = hud.main
	var p: Player = m.player
	var lvl: int = m.shop.level
	gold.text = "◆ %d" % p.cur.ember
	var counts := {"gear": m.shop.items.size(), "tablets": m.shop.get("tablets", []).size(), "jewels": m.shop.get("jewels", []).size(),
		"charms": Charms.count(m.shop.get("charms", {})), "gems": Data.missing_gems(p.skills, p.gems, p.level + GEM_AHEAD).size()}
	for t in TABS:
		tab_btns[t[0]].text = t[1] + (" %d" % counts[t[0]] if counts.has(t[0]) else "")
	var pp := Items.potion_price(lvl)
	potion_btn.text = "回復薬を買う（◆ %d）　所持 %d/%d" % [pp, p.potions, p.max_potions()]
	potion_btn.disabled = p.cur.ember < pp or p.potions >= p.max_potions()
	var rp := Items.reroll_price(lvl)
	reroll_btn.text = "品揃えを入れ替える（◆ %d）" % rp
	reroll_btn.disabled = p.cur.ember < rp
	_show_tab(false)
	BasePanel.clear(bag_grid)
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


## build the open tab's grid and empty the others; `top` scrolls back to the top (a new tab or filter)
func _show_tab(top: bool) -> void:
	if not visible:
		return
	for g in [stock_grid, ware_grid, gem_grid, cur_grid]:
		BasePanel.clear(g)
	filter_row.visible = tab == "gear"
	stock_grid.visible = tab == "gear"
	ware_grid.visible = tab in ["tablets", "jewels", "charms"]
	gem_grid.visible = tab == "gems"
	cur_grid.visible = tab == "currency"
	match tab:
		"gear":
			_fill_gear()
		"tablets":
			_fill_tablets()
		"jewels":
			_fill_jewels()
		"charms":
			_fill_charms()
		"gems":
			_fill_gems()
		"currency":
			_fill_currency()
	if top:
		scroll.scroll_vertical = 0


## a priced cell: the ware's square with its price under it
func _cell(sq: Control, cost: int) -> VBoxContainer:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 1)
	cell.add_child(sq)
	var price := Label.new()
	price.text = "◆ %d" % cost
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.add_theme_font_size_override("font_size", 12)
	price.add_theme_color_override("font_color", Color("#ffb35a") if hud.main.player.cur.ember >= cost else Color("#8a5a40"))
	cell.add_child(price)
	return cell


func _price_line(cost: int) -> Array:
	return ["価格 %d 灰燼の欠片" % cost, Color("#ffcf3a"), 13]


## a ware button: its name and price, its tooltip on hover
func _ware_btn(text: String, color: Color, cost: int, tip: Array, buy: Callable) -> Button:
	var b := Button.new()
	b.text = "%s  ◆%d" % [text, cost]
	b.add_theme_color_override("font_color", color)
	b.add_theme_font_size_override("font_size", 13)
	b.custom_minimum_size = Vector2(245, 30)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.disabled = hud.main.player.cur.ember < cost
	var lines := tip + [_price_line(cost)]
	b.mouse_entered.connect(func(): hud.show_tip(lines))
	b.mouse_exited.connect(func(): hud.hide_tip())
	b.pressed.connect(buy)
	return b


## the gear the slot and rarity filters let through
func gear_shown() -> Array:
	return hud.main.shop.items.filter(func(it): return (slot_filter == "" or it.slot == slot_filter) and (rarity_filter < 0 or int(it.rarity) == rarity_filter))


func _fill_gear() -> void:
	var shown := gear_shown()
	note.text = "装備 %d 点（クリックで購入。絞り込み %d 点）" % [hud.main.shop.items.size(), shown.size()]
	for it in shown:
		var cost := Items.buy_price(it)
		var sl := ItemSlot.new()
		sl.custom_minimum_size = Vector2(60, 60)
		sl.item = it
		sl.hud = hud
		sl.compare = true
		sl.extra = [_price_line(cost)]
		sl.clicked.connect(_buy.bind(it))
		stock_grid.add_child(_cell(sl, cost))


func _fill_tablets() -> void:
	var p: Player = hud.main.player
	ware_grid.columns = 2
	note.text = "ルーンタブレット（クリックで購入。所持 %d / %d）" % [Tablets.plain_count(p.tablets), Tablets.MAX_OWNED]
	for t in hud.main.shop.get("tablets", []):
		ware_grid.add_child(_ware_btn("▦ %s %dマス %d行" % [Tablets.name_of(t), Tablets.cell_count(t), t.mods.size()], Tablets.COLOR,
			Items.tablet_price(t), Tablets.lines(t), _buy_tablet.bind(t)))


func _fill_jewels() -> void:
	var p: Player = hud.main.player
	ware_grid.columns = 2
	note.text = "ジュエル（クリックで購入。所持 %d / %d）" % [Jewels.plain_count(p.jewels), Jewels.MAX_OWNED]
	for j in hud.main.shop.get("jewels", []):
		ware_grid.add_child(_ware_btn("%s %s" % ["◎" if Jewels.is_ring(j) else "◆", j.name], Data.RARITY[j.rarity].color,
			Items.jewel_price(j), Jewels.lines(j), _buy_jewel.bind(j)))


func _fill_charms() -> void:
	var stock: Dictionary = hud.main.shop.get("charms", {})
	ware_grid.columns = 7
	note.text = "コンパス（クリックで1つ購入。遠征図の祭壇で地図に嵌める）"
	for id in Charms.all_ids():
		if int(stock.get(id, 0)) <= 0:
			continue
		var cost := Items.charm_price(id)
		var sl := Charms.Slot.new(id, int(stock[id]), hud)
		sl.custom_minimum_size = Vector2(60, 60)
		sl.extra = [_price_line(cost), ["在庫 %d" % stock[id], Color("#b8a888"), 12]]
		sl.clicked.connect(_buy_charm.bind(id))
		ware_grid.add_child(_cell(sl, cost))


func _fill_gems() -> void:
	var p: Player = hud.main.player
	note.text = "ジェム（◈ スキル　◇ サポート。必要レベルが Lv+%d までのものが並ぶ）" % GEM_AHEAD
	var missing := Data.missing_gems(p.skills, p.gems, p.level + GEM_AHEAD)
	if missing.is_empty():
		gem_grid.add_child(_sub("いま並ぶジェムはすべて入手済み"))
	for m_gem in missing:
		var gi := Data.gem_info(m_gem.skill, m_gem.id)
		var cost := Items.gem_price(gi.lvl)
		var b := Button.new()
		b.text = "%s %s Lv%d  ◆%d" % ["◈" if m_gem.skill else "◇", gi.name, gi.lvl, cost]
		b.add_theme_color_override("font_color", gi.color)
		b.add_theme_font_size_override("font_size", 13)
		b.custom_minimum_size = Vector2(245, 28)
		b.disabled = p.cur.ember < cost
		var tip: Array = hud.skill_ui.skill_tip(m_gem.id, -1, 1) if m_gem.skill else SkillUI.gem_tip(Data.support(m_gem.id), p.level)
		b.mouse_entered.connect(func(): hud.show_tip(tip))
		b.mouse_exited.connect(func(): hud.hide_tip())
		b.pressed.connect((_buy_skill if m_gem.skill else _buy_gem).bind(m_gem.id))
		gem_grid.add_child(b)


func _fill_currency() -> void:
	var m = hud.main
	var p: Player = m.player
	note.text = "カレンシー（相場 × %d 灰燼。買い取りはしない）" % Items.EMBER_PER_CHAOS
	for cdef in Data.CURRENCIES:
		if cdef.w <= 0.0:
			continue
		var cost := Items.currency_price(cdef, m.league())
		var b := Button.new()
		b.text = "%s %s  ◆%d" % [cdef.icon, cdef.name, cost]
		b.add_theme_color_override("font_color", cdef.color)
		b.add_theme_font_size_override("font_size", 13)
		b.custom_minimum_size = Vector2(245, 28)
		b.disabled = p.cur.ember < cost
		b.tooltip_text = "%s\n所持数 %d" % [cdef.desc, p.cur[cdef.k]]
		b.pressed.connect(_buy_currency.bind(cdef.k, cost))
		cur_grid.add_child(b)


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
	var cost := Items.gem_price(Data.support(id).lvl)
	if p.cur.ember < cost or id in p.gems:
		return
	p.cur.ember -= cost
	hud.main.unlock_gem(id)
	hud.hide_tip()
	refresh()


func _buy_skill(id: String) -> void:
	var p: Player = hud.main.player
	var cost := Items.gem_price(Data.SKILLS[id].lvl)
	if p.cur.ember < cost or id in p.skills:
		return
	p.cur.ember -= cost
	hud.main.learn_skill(id)
	hud.hide_tip()
	refresh()


func _buy_tablet(t: Dictionary) -> void:
	var m = hud.main
	var p: Player = m.player
	var cost := Items.tablet_price(t)
	if p.cur.ember < cost or not t in m.shop.get("tablets", []):
		return
	if Tablets.is_full(p.tablets, t):
		hud.message("ルーンタブレットが一杯です（%d）" % Tablets.MAX_OWNED, Color("#ff8080"))
		return
	p.cur.ember -= cost
	m.shop.tablets.erase(t)
	m.gain_tablet(t)
	hud.hide_tip()
	refresh()


func _buy_jewel(j: Dictionary) -> void:
	var m = hud.main
	var p: Player = m.player
	var cost := Items.jewel_price(j)
	if p.cur.ember < cost or not j in m.shop.get("jewels", []):
		return
	if Jewels.is_full(p.jewels, j):
		hud.message("ジュエルが一杯です（%d）" % Jewels.MAX_OWNED, Color("#ff8080"))
		return
	p.cur.ember -= cost
	m.shop.jewels.erase(j)
	m.gain_jewel(j)
	hud.hide_tip()
	refresh()


func _buy_charm(id: String) -> void:
	var m = hud.main
	var p: Player = m.player
	var stock: Dictionary = m.shop.get("charms", {})
	var cost := Items.charm_price(id)
	if p.cur.ember < cost or int(stock.get(id, 0)) <= 0:
		return
	p.cur.ember -= cost
	stock[id] -= 1
	if stock[id] <= 0:
		stock.erase(id)
	Charms.add(p.charms, id)
	hud.message("%s %s を購入（%d 灰燼の欠片、所持 %d）" % [Charms.ICON, Charms.name_of(id), cost, p.charms[id]], Charms.color_of(id))
	refresh()
