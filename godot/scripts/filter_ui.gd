class_name FilterUI
extends BasePanel
## Loot filter (L): per rarity pick up, pick up and sell at once, or hide (sold as it drops);
## unchecked equipment slots are hidden too, except legendaries.

const OPTS := [["pick", "拾う"], ["sell", "拾って売却"], ["hide", "非表示（即売却）"]]
const OPT_COLORS := {"pick": Color("#8fd18f"), "sell": Color("#ffcf3a"), "hide": Color("#ff8a6a")}

var rows := VBoxContainer.new()
var slot_grid := GridContainer.new()
var confirm := ""    # a legendary setting waiting for a second click


func _title() -> String:
	return "ルートフィルタ"


func _hint() -> String:
	return "売却した分の灰燼の欠片は自動で入る"


func _build() -> void:
	body.add_child(sub("レア度ごとの扱い"))
	rows.add_theme_constant_override("separation", 6)
	body.add_child(rows)
	body.add_child(sub("拾う装備の部位（チェックを外した部位はレジェンド以外非表示）"))
	slot_grid.columns = 4
	slot_grid.add_theme_constant_override("h_separation", 14)
	body.add_child(slot_grid)


func refresh() -> void:
	if not visible:
		return
	var f: Dictionary = hud.main.player.filter
	clear(rows)
	for i in Data.RARITY.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var lbl := sub(Data.RARITY[i].name, 14, Data.RARITY[i].color)
		lbl.custom_minimum_size = Vector2(100, 0)
		row.add_child(lbl)
		for o in OPTS:
			var on: bool = f.rarity[i] == o[0]
			var pending := confirm == "%d:%s" % [i, o[0]]
			var col: Color = OPT_COLORS[o[0]]
			var b := SkillUI.card("もう一度押すと確定" if pending else o[1], col.darkened(0.7) if on else Color("#120e0a"),
				col if on or pending else Color("#3a3024"), col if on else Color("#a89878"), 2 if on else 1)
			b.alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.custom_minimum_size = Vector2(150, 30)
			b.pressed.connect(_set_rarity.bind(i, o[0]))
			row.add_child(b)
		rows.add_child(row)
	clear(slot_grid)
	for k in Data.SLOTS:
		var cb := CheckBox.new()
		cb.text = Data.SLOT_INFO[k].name
		cb.button_pressed = f.slots[k]
		cb.toggled.connect(func(v):
			f.slots[k] = v
			_changed())
		slot_grid.add_child(cb)


func _set_rarity(i: int, v: String) -> void:
	var key := "%d:%s" % [i, v]
	# selling legendaries automatically is easy to regret, so it takes a second click
	if i == 3 and v != "pick" and confirm != key:
		confirm = key
		refresh()
		return
	confirm = ""
	hud.main.player.filter.rarity[i] = v
	_changed()


func _changed() -> void:
	hud.main.sell_hidden_ground()
	hud.main.save_game()
	refresh()
