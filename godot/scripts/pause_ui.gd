class_name PauseUI
extends BasePanel
## Esc with nothing else open: resume, give up the current map, the key config, the options and the key list.

var leave := Button.new()
var map_alpha := HSlider.new()   # options: the map overlay's transparency and zoom, in percent
var map_zoom := HSlider.new()
var hurt_fx := HSlider.new()     # options: how strong the hit-taken feedback is, in percent
var controls := VBoxContainer.new()   # the key list, rebuilt as the bindings change


func _title() -> String:
	return "一時停止"


func _build() -> void:
	var resume := Button.new()
	resume.text = "再開する"
	resume.custom_minimum_size = Vector2(320, 40)
	resume.pressed.connect(open_close)
	body.add_child(resume)
	leave.text = "隠れ家に戻る（マップを放棄）"
	leave.custom_minimum_size = Vector2(320, 40)
	leave.pressed.connect(func():
		open_close()
		hud.main.abandon_map())
	body.add_child(leave)
	var chars := Button.new()
	chars.text = "キャラクター選択に戻る（セーブします）"
	chars.custom_minimum_size = Vector2(320, 40)
	chars.pressed.connect(func(): hud.main.switch_char())
	body.add_child(chars)
	var keys := Button.new()
	keys.text = "キー設定"
	keys.custom_minimum_size = Vector2(320, 40)
	keys.pressed.connect(func(): hud.toggle(hud.keyconfig_ui))
	body.add_child(keys)
	body.add_child(sub("オプション", 14, Color("#f0d8a0")))
	body.add_child(_slider_row("マップの透過率", map_alpha, Settings.TRANSPARENCY, 5, func(v):
		Settings.set_transparency(int(v))
		hud.map_overlay.apply_settings()))
	body.add_child(_slider_row("マップの拡大率", map_zoom, Settings.ZOOM, 10, func(v):
		Settings.set_zoom(int(v))
		hud.map_overlay.apply_settings()))
	body.add_child(_slider_row("被ダメージ演出の強さ", hurt_fx, Settings.HURT_FX, 10, func(v):
		Settings.set_hurt_fx(int(v))))
	body.add_child(sub("操作", 14, Color("#f0d8a0")))
	body.add_child(controls)


## a labelled slider with its value in percent beside it; `changed` gets the new value as it moves
func _slider_row(text: String, s: HSlider, range_: Array, step: int, changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var lbl := sub(text, 14, Color("#c8b898"))
	lbl.custom_minimum_size.x = 120
	row.add_child(lbl)
	s.min_value = range_[0]
	s.max_value = range_[1]
	s.step = step
	s.custom_minimum_size = Vector2(160, 24)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var val := sub("", 14, Color("#e8d8b0"))
	val.custom_minimum_size.x = 50
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	s.value_changed.connect(func(v):
		val.text = "%d%%" % int(v)
		changed.call(v))
	s.set_meta("value_label", val)
	return row


func refresh() -> void:
	leave.visible = not hud.main.in_hideout()
	for pair in [[map_alpha, Settings.map_transparency], [map_zoom, Settings.map_zoom], [hurt_fx, Settings.hurt_fx]]:
		pair[0].set_value_no_signal(pair[1])
		pair[0].get_meta("value_label").text = "%d%%" % pair[1]
	clear(controls)
	var k := func(a): return Keybinds.text(a)
	var skills := PackedStringArray(range(Data.SLOT_COUNT).map(func(i): return k.call(Keybinds.skill_action(i))))
	for line in ["%s：移動　%s：スキル" % [hud.main.move_keys(), "・".join(skills)],
			"%s：回復薬　%s：近くの祭壇・商人・スタッシュを使う" % [k.call("potion"), k.call("interact")],
			"%s：インベントリ　%s：スキル　%s：パッシブツリー　%s：アセンダンシー" % [k.call("inventory"), k.call("skills"), k.call("talents"), k.call("ascendancy")],
			"%s：ステータス　%s：ルートフィルタ　%s：遠征パッシブ　%s：キー設定" % [k.call("status"), k.call("filter"), k.call("passives"), k.call("keyconfig")],
			"%s：石板盤　%s：マップ（オーバーレイ。透過率と拡大率は上のオプションで）" % [k.call("tablets"), k.call("map")]]:
		controls.add_child(sub(line, 13, Color("#c8b898")))
