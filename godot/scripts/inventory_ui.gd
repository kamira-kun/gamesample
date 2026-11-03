class_name InventoryUI
extends PanelContainer
## Inventory panel: equipment, bag, stats and currency crafting.
## Click a bag item to equip, click equipment to take it off, right-click to sell.
## Click a crafting currency, then click items to use it (right-click cancels). 一行クラフト picks an item
## instead and lists its lines to work one at a time (LineCraft).

var hud: Hud
var equip_grid := GridContainer.new()
var bag_grid := GridContainer.new()
var stats := Label.new()
var cur_grid := GridContainer.new()
var charm_grid := HFlowContainer.new()
var banner := Label.new()
var bag_count := Label.new()
var craft_key := ""           # a currency, or "line" for one-line crafting
var line_item := {}            # the item one-line crafting works on
var line_box := LineCraft.Box.new()

const EQUIP_LAYOUT := ["", "helm", "amulet", "weapon", "armor", "gloves", "ring", "boots", ""]


func _ready() -> void:
	add_theme_stylebox_override("panel", Hud.panel_box())
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	visible = false

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := Label.new()
	title.text = "インベントリ"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#f0d8a0"))
	head.add_child(title)
	var hint := Label.new()
	hint.text = "   クリック：装備／外す　右クリック：売却"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color("#998a70"))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hint)
	var close := Button.new()
	close.text = "×"
	close.pressed.connect(hud.toggle_inventory)
	head.add_child(close)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	col.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	body.add_child(left)
	equip_grid.columns = 3
	equip_grid.add_theme_constant_override("h_separation", 6)
	equip_grid.add_theme_constant_override("v_separation", 6)
	left.add_child(equip_grid)
	stats.add_theme_font_size_override("font_size", 13)
	stats.custom_minimum_size = Vector2(200, 0)
	left.add_child(stats)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	right.add_child(_sub("カレンシー（クリックしてからアイテムをクリック）"))
	cur_grid.columns = 4
	cur_grid.add_theme_constant_override("h_separation", 4)
	cur_grid.add_theme_constant_override("v_separation", 4)
	right.add_child(cur_grid)
	right.add_child(_sub("コンパス（遠征図で出撃前にはめる）"))
	charm_grid.add_theme_constant_override("h_separation", 4)
	charm_grid.custom_minimum_size = Vector2(330, 0)
	right.add_child(charm_grid)
	banner.add_theme_font_size_override("font_size", 12)
	banner.add_theme_color_override("font_color", Color("#ffd36a"))
	banner.visible = false
	right.add_child(banner)
	line_box.crafted.connect(_on_line_crafted)
	right.add_child(line_box)
	right.add_child(bag_count)
	bag_count.add_theme_font_size_override("font_size", 13)
	bag_count.add_theme_color_override("font_color", Color("#b8a888"))
	bag_grid.columns = 6
	bag_grid.add_theme_constant_override("h_separation", 4)
	bag_grid.add_theme_constant_override("v_separation", 4)
	right.add_child(bag_grid)


func _sub(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color("#b8a888"))
	return l


func open_close() -> void:
	visible = not visible
	craft_key = ""
	hud.hide_tip()
	if visible:
		refresh()
		_center.call_deferred()


## center on screen once the contents have a size
func _center() -> void:
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


func refresh() -> void:
	if not visible:
		return
	var p: Player = hud.main.player
	BasePanel.clear(equip_grid)
	for slot in EQUIP_LAYOUT:
		if slot == "":
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(60, 60)
			equip_grid.add_child(gap)
			continue
		var sl := ItemSlot.new()
		sl.custom_minimum_size = Vector2(60, 60)
		sl.item = p.equip.get(slot, {})
		sl.empty_text = Data.SLOT_INFO[slot].name
		sl.hud = hud
		sl.glow = craft_key != ""
		sl.clicked.connect(_on_equipped_click.bind(slot))
		sl.right_clicked.connect(_cancel_craft)
		equip_grid.add_child(sl)
	BasePanel.clear(bag_grid)
	for i in Player.BAG_SIZE:
		var sl := ItemSlot.new()
		sl.custom_minimum_size = Vector2(52, 52)
		sl.item = p.bag[i] if i < p.bag.size() else {}
		sl.hud = hud
		sl.compare = true
		sl.glow = craft_key != ""
		sl.clicked.connect(_on_bag_click.bind(i))
		sl.right_clicked.connect(_on_bag_right.bind(i))
		bag_grid.add_child(sl)
	bag_count.text = "所持品 %d / %d" % [p.bag.size(), Player.BAG_SIZE]
	BasePanel.clear(charm_grid)
	for id in Charms.all_ids():
		if p.charms.get(id, 0) > 0:
			charm_grid.add_child(Charms.Slot.new(id, p.charms[id], hud))
	if p.charms.is_empty():
		charm_grid.add_child(_sub("なし（マップの敵が落とす）"))
	BasePanel.clear(cur_grid)
	for cdef in Data.CURRENCIES:
		var b := Button.new()
		var craftable: bool = cdef.k not in ["ember", "compass"]
		b.text = "%s %d" % [cdef.icon, p.cur[cdef.k]]
		b.add_theme_color_override("font_color", cdef.color)
		b.add_theme_font_size_override("font_size", 14)
		b.custom_minimum_size = Vector2(76, 30)
		b.toggle_mode = true
		b.button_pressed = craft_key == cdef.k
		b.disabled = not craftable
		b.tooltip_text = "%s\n%s\n所持数 %d" % [cdef.name, cdef.desc, p.cur[cdef.k]]
		b.pressed.connect(_pick_currency.bind(cdef.k))
		cur_grid.add_child(b)
	var lb := Button.new()
	lb.text = "一行クラフト"
	lb.add_theme_color_override("font_color", Color("#ffd36a"))
	lb.add_theme_font_size_override("font_size", 13)
	lb.custom_minimum_size = Vector2(76, 30)
	lb.toggle_mode = true
	lb.button_pressed = craft_key == "line"
	lb.tooltip_text = "アイテムの1行だけを付け替える・数値を磨き直す。
必要なカレンシーはアイテムレベルで変わり、高いほど多く要る。"
	lb.pressed.connect(_pick_currency.bind("line"))
	cur_grid.add_child(lb)
	if craft_key != "line" or not _holds(line_item):
		line_item = {}
	line_box.show_for(p, line_item)
	banner.visible = craft_key != ""
	if craft_key == "line":
		banner.text = "一行クラフト：アイテムをクリックして行を選ぶ。右クリックで解除" if line_item.is_empty() else "一行クラフト：行ごとにボタンで加工。別のアイテムをクリックで切り替え"
	elif craft_key != "":
		var cd := Data.currency(craft_key)
		banner.text = "%s %s を使用中（残り %d）：アイテムをクリック。右クリックで解除" % [cd.icon, cd.name, p.cur[craft_key]]
	var s := p.s
	stats.text = "\n".join([
		"ダメージ　%d–%d" % [s.dmg_min, s.dmg_max], "攻撃/秒　%.2f" % s.attack_rate,
		"ダメージ増加　%d%%" % s.inc_dmg, "スキルダメージ　%d%%" % s.spell_dmg,
		"乗算　%s" % StatusUI.more_text(s),
		"クリティカル　%.0f%% / %d%%" % [s.crit, s.crit_multi], "詠唱速度　+%d%%" % s.cast_spd,
		"火炎/冷気/雷　%d/%d/%d%%" % [s.fire_dmg, s.cold_dmg, s.light_dmg],
		"アーマー　%d（軽減 %d%%）" % [s.armor, roundi(s.dr * 100)], "移動速度　+%d%%" % s.move_spd,
		"クールダウン短縮　%d%%" % s.cdr, "ライフ回復　%.1f/秒" % s.life_regen, "マナ回復　%.1f/秒" % s.mana_regen,
	])


## whether the player still has item `it` in the bag or wears it
func _holds(it: Dictionary) -> bool:
	var p: Player = hud.main.player
	return p.bag.any(func(x): return is_same(x, it)) or p.equip.values().any(func(x): return is_same(x, it))


func _pick_currency(k: String) -> void:
	var p: Player = hud.main.player
	if k == "line":
		craft_key = "" if craft_key == k else k
	elif p.cur[k] <= 0:
		hud.message("%sを持っていない" % Data.currency(k).name, Color("#ff8080"))
		craft_key = ""
	else:
		craft_key = "" if craft_key == k else k
	refresh()


func _cancel_craft() -> void:
	if craft_key != "":
		craft_key = ""
		refresh()


## returns true when the click was spent on crafting
func _try_craft(it: Dictionary) -> bool:
	if craft_key == "" or it.is_empty():
		return false
	if craft_key == "line":
		line_item = it
		refresh()
		hud.show_tip(Items.lines(it))
		return true
	var p: Player = hud.main.player
	var err := Items.craft(craft_key, it)
	if err != "":
		hud.message(err, Color("#ff8080"))
		return true
	p.cur[craft_key] -= 1
	if p.cur[craft_key] <= 0:
		craft_key = ""
	p.recalc()
	refresh()
	hud.show_tip(Items.lines(it))
	return true


func _on_line_crafted() -> void:
	hud.main.player.recalc()
	refresh()
	hud.show_tip(Items.lines(line_item))


func _on_bag_click(i: int) -> void:
	var p: Player = hud.main.player
	if i >= p.bag.size() or _try_craft(p.bag[i]):
		return
	var it: Dictionary = p.bag[i]
	var old = p.equip.get(it.slot)
	p.equip[it.slot] = it
	p.bag.remove_at(i)
	if old:
		p.bag.append(old)
	p.recalc()
	hud.hide_tip()
	refresh()


func _on_bag_right(i: int) -> void:
	var p: Player = hud.main.player
	if craft_key != "":
		_cancel_craft()
		return
	if i >= p.bag.size():
		return
	var it: Dictionary = p.bag[i]
	var g := Items.sell_price(it)
	p.bag.remove_at(i)
	p.cur.ember += g
	hud.message("%s を売却（%d 灰燼の欠片）" % [it.name, g], Color("#ffcf3a"))
	hud.hide_tip()
	refresh()


func _on_equipped_click(slot: String) -> void:
	var p: Player = hud.main.player
	if not p.equip.has(slot) or _try_craft(p.equip[slot]):
		return
	if p.bag.size() >= Player.BAG_SIZE:
		hud.message("インベントリが一杯です", Color("#ff8080"))
		return
	p.bag.append(p.equip[slot])
	p.equip.erase(slot)
	p.recalc()
	hud.hide_tip()
	refresh()

