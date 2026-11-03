class_name StashUI
extends BasePanel
## The hideout stash: tabs shared by every character of the same league (season or standard).
## Click a bag item to put it in the open tab, click a stash item to take it into the bag.

var league_label := Label.new()
var tab_row := HBoxContainer.new()
var stash_grid := GridContainer.new()
var bag_grid := GridContainer.new()
var bag_count := Label.new()
var charm_stash := HFlowContainer.new()
var charm_bag := HFlowContainer.new()
var tab := 0


func _title() -> String:
	return "スタッシュ"


func _hint() -> String:
	return "クリック：所持品 ⇄ スタッシュ"


func _build() -> void:
	league_label.add_theme_font_size_override("font_size", 13)
	body.add_child(league_label)
	tab_row.add_theme_constant_override("separation", 4)
	body.add_child(tab_row)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	body.add_child(row)
	stash_grid.columns = 8
	stash_grid.add_theme_constant_override("h_separation", 4)
	stash_grid.add_theme_constant_override("v_separation", 4)
	row.add_child(stash_grid)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	bag_count.add_theme_font_size_override("font_size", 13)
	bag_count.add_theme_color_override("font_color", Color("#b8a888"))
	right.add_child(bag_count)
	bag_grid.columns = 6
	bag_grid.add_theme_constant_override("h_separation", 4)
	bag_grid.add_theme_constant_override("v_separation", 4)
	right.add_child(bag_grid)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 22)
	body.add_child(crow)
	for pair in [["コンパス（スタッシュ・クリックで全部／右クリックで1つ取り出す）", charm_stash], ["コンパス（所持・クリックで全部／右クリックで1つ預ける）", charm_bag]]:
		var box := VBoxContainer.new()
		var l := Label.new()
		l.text = pair[0]
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Charms.COLOR)
		box.add_child(l)
		pair[1].custom_minimum_size = Vector2(420, 52)
		pair[1].add_theme_constant_override("h_separation", 4)
		box.add_child(pair[1])
		crow.add_child(box)


func tabs() -> Array:
	return Profiles.stash_tabs(hud.main.league())


func refresh() -> void:
	if not visible:
		return
	var p: Player = hud.main.player
	var lg: String = hud.main.league()
	var ts := tabs()
	tab = clampi(tab, 0, ts.size() - 1)
	league_label.text = "%s のキャラクターで共有" % Profiles.league_name(lg)
	league_label.add_theme_color_override("font_color", Data.season(lg).get("color", Color("#c8b898")))
	clear(tab_row)
	for i in ts.size():
		var b := Button.new()
		b.text = "%s（%d）" % [ts[i].name, ts[i].items.size()]
		b.toggle_mode = true
		b.button_pressed = i == tab
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func():
			tab = i
			refresh())
		tab_row.add_child(b)
	var items: Array = ts[tab].items
	clear(stash_grid)
	for i in Profiles.TAB_SIZE:
		var sl := ItemSlot.new()
		sl.custom_minimum_size = Vector2(52, 52)
		sl.hud = hud
		if i < items.size():
			sl.item = items[i]
			sl.compare = true
		sl.clicked.connect(_take.bind(i))
		stash_grid.add_child(sl)
	clear(bag_grid)
	for i in Player.BAG_SIZE:
		var sl := ItemSlot.new()
		sl.custom_minimum_size = Vector2(52, 52)
		sl.hud = hud
		if i < p.bag.size():
			sl.item = p.bag[i]
			sl.compare = true
		sl.clicked.connect(_put.bind(i))
		bag_grid.add_child(sl)
	bag_count.text = "所持品 %d / %d" % [p.bag.size(), Player.BAG_SIZE]
	var sc := Profiles.stash_charms(lg)
	for pair in [[charm_stash, sc, false], [charm_bag, p.charms, true]]:
		clear(pair[0])
		for id in Charms.all_ids():
			if pair[1].get(id, 0) > 0:
				var sl := Charms.Slot.new(id, pair[1][id], hud)
				sl.clicked.connect(move_charm.bind(id, pair[2], true))
				sl.right_clicked.connect(move_charm.bind(id, pair[2], false))
				pair[0].add_child(sl)


## a stack of ember shells (or one of it, without `all`) between the stash and the character
func move_charm(id: String, to_stash: bool, all: bool) -> void:
	var p: Player = hud.main.player
	var sc := Profiles.stash_charms(hud.main.league())
	var src: Dictionary = p.charms if to_stash else sc
	var have := int(src.get(id, 0))
	if to_stash:   # a shell set into the atlas stays with the character
		have -= p.charm_slots.count(id)
	var n := have if all else mini(1, have)
	if n <= 0:
		return
	src[id] -= n
	if src[id] <= 0:
		src.erase(id)
	Charms.add(sc if to_stash else p.charms, id, n)
	hud.refresh_inventory()
	_moved()


## bag item i into the open tab
func _put(i: int) -> void:
	var p: Player = hud.main.player
	var items: Array = tabs()[tab].items
	if i >= p.bag.size():
		return
	if items.size() >= Profiles.TAB_SIZE:
		hud.message("このタブは一杯です", Color("#ff8080"))
		return
	items.append(p.bag[i])
	p.bag.remove_at(i)
	_moved()


## stash item i into the bag
func _take(i: int) -> void:
	var p: Player = hud.main.player
	var items: Array = tabs()[tab].items
	if i >= items.size():
		return
	if p.bag.size() >= Player.BAG_SIZE:
		hud.message("インベントリが一杯です", Color("#ff8080"))
		return
	p.bag.append(items[i])
	items.remove_at(i)
	_moved()


## the stash is shared, so every move is written at once (with the character, so nothing duplicates)
func _moved() -> void:
	hud.hide_tip()
	hud.main.save_game()
	refresh()
