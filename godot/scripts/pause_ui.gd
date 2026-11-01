class_name PauseUI
extends BasePanel
## Esc with nothing else open: resume, give up the current map, and the key list.

var leave := Button.new()


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
	body.add_child(sub("操作", 14, Color("#f0d8a0")))
	for line in ["WASD：移動　左/右クリック・Q・E・R・Space：スキル", "F：回復薬　B：近くの祭壇や商人を使う",
			"I / Tab：インベントリ　K：スキル　T：タレント", "C：ステータス　L：ルートフィルタ　P：遠征パッシブ"]:
		body.add_child(sub(line, 13, Color("#c8b898")))


func refresh() -> void:
	leave.visible = not hud.main.in_hideout()
