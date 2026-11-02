class_name PauseUI
extends BasePanel
## Esc with nothing else open: resume, give up the current map, the key config, and the key list.

var leave := Button.new()
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
	body.add_child(sub("操作", 14, Color("#f0d8a0")))
	body.add_child(controls)


func refresh() -> void:
	leave.visible = not hud.main.in_hideout()
	clear(controls)
	var k := func(a): return Keybinds.text(a)
	var skills := PackedStringArray(range(Data.SLOT_COUNT).map(func(i): return k.call(Keybinds.skill_action(i))))
	for line in ["%s：移動　%s：スキル" % [hud.main.move_keys(), "・".join(skills)],
			"%s：回復薬　%s：近くの祭壇・商人・スタッシュを使う" % [k.call("potion"), k.call("interact")],
			"%s：インベントリ　%s：スキル　%s：タレント　%s：アセンダンシー" % [k.call("inventory"), k.call("skills"), k.call("talents"), k.call("ascendancy")],
			"%s：ステータス　%s：ルートフィルタ　%s：遠征パッシブ　%s：キー設定" % [k.call("status"), k.call("filter"), k.call("passives"), k.call("keyconfig")]]:
		controls.add_child(sub(line, 13, Color("#c8b898")))
