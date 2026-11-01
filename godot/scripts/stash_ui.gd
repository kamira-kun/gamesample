class_name StashUI
extends BasePanel
## The hideout stash: tabs shared by every character of the same league (season or standard).
## Click a bag item to put it in the open tab, click a stash item to take it into the bag.

var league_label := Label.new()
var tab_row := HBoxContainer.new()
var stash_grid := GridContainer.new()
var bag_grid := GridContainer.new()
var bag_count := Label.new()
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
