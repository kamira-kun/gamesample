class_name CinderUI
extends BasePanel
## Cinder altars (see Farm). Two faces of one panel: at an altar in a map, pick the vow to kindle it with;
## at the cinder forge in the hideout, trade the league's crystals for loot. Both show the league's renown.

var mode := "forge"        # "altar" or "forge"
var altar := {}            # the altar being kindled (an entry of main.altars)
var title_label := Label.new()
var league_label := Label.new()
var status := Label.new()
var cards := GridContainer.new()
var error := Label.new()


func _title() -> String:
	return "燼火"


func _hint() -> String:
	return "燼晶と位階はリーグのキャラクターで共有"


func _build() -> void:
	title_label.add_theme_font_size_override("font_size", 17)
	title_label.add_theme_color_override("font_color", Farm.COLOR)
	body.add_child(title_label)
	league_label.add_theme_font_size_override("font_size", 13)
	body.add_child(league_label)
	status.add_theme_font_size_override("font_size", 14)
	status.add_theme_color_override("font_color", Color("#ffd8a0"))
	body.add_child(status)
	cards.columns = 2
	cards.add_theme_constant_override("h_separation", 8)
	cards.add_theme_constant_override("v_separation", 8)
	body.add_child(cards)
	error.add_theme_font_size_override("font_size", 13)
	error.add_theme_color_override("font_color", Color("#ff8a70"))
	body.add_child(error)


## open at an altar, to choose its vow
func open_altar(a: Dictionary) -> void:
	mode = "altar"
	altar = a
	error.text = ""
	_show()


## open at the hideout forge
func open_forge() -> void:
	mode = "forge"
	altar = {}
	error.text = ""
	_show()


func _show() -> void:
	if visible:
		refresh()
	else:
		hud.toggle(self)


func farm() -> Dictionary:
	return Farm.state(hud.main.league())


func refresh() -> void:
	if not visible:
		return
	var f := farm()
	var lg: String = hud.main.league()
	var r := Farm.rank(f)
	league_label.text = "%s のリーグ" % Profiles.league_name(lg)
	league_label.add_theme_color_override("font_color", Data.season(lg).get("color", Color("#c8b898")))
	var next := "（最大）" if r >= Farm.MAX_RANK else "　次の位階まで %d" % (Farm.rank_need(r + 1) - f.renown)
	status.text = "%s %d 個　｜　燼火の位階 %d%s　｜　点火した祭壇 %d　｜　導標 %d" % [Farm.CURRENCY.icon + " 燼晶", f.cinder, r, next, f.lit, f.beacons]
	clear(cards)
	if mode == "altar":
		title_label.text = "燼火の祭壇 — 誓約を選んで点火する"
		for v in Farm.VOWS:
			var ok: bool = r >= v.rank
			var text: String = "%s\n%s" % [v.name, v.desc] if ok else "%s（位階 %d で解放）\n%s" % [v.name, v.rank, v.desc]
			var card := SkillUI.card(text, Color("#2a120a") if ok else Color("#120e0a"), Farm.COLOR if ok else Color("#3a3024"),
				Color("#ffe0c0") if ok else Color("#6a5e50"))
			card.custom_minimum_size = Vector2(300, 74)
			card.disabled = not ok
			card.pressed.connect(choose.bind(v.id))
			cards.add_child(card)
	else:
		title_label.text = "燼火の炉 — 燼晶と交換する"
		for o in Farm.OFFERS:
			var ok: bool = r >= o.rank
			var text: String = "%s　%s %d\n%s" % [o.name, Farm.CURRENCY.icon, o.cost, o.desc]
			if not ok:
				text += "（位階 %d で解放）" % o.rank
			var afford: bool = ok and f.cinder >= o.cost
			var card := SkillUI.card(text, Color("#2a120a") if afford else Color("#120e0a"), Farm.COLOR if afford else Color("#3a3024"),
				Color("#ffe0c0") if ok else Color("#6a5e50"))
			card.custom_minimum_size = Vector2(300, 60)
			card.pressed.connect(buy.bind(o.id))
			cards.add_child(card)


## kindle the altar with this vow
func choose(vow_id: String) -> void:
	if altar.is_empty() or Farm.rank(farm()) < Farm.vow(vow_id).rank:
		return
	var a := altar
	open_close()
	hud.main.kindle_altar(a, vow_id)


func buy(id: String) -> void:
	error.text = hud.main.forge_buy(id)
	refresh()
