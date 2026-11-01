extends SceneTree
## Runs tools/check_uniques.gd once the autoloads are up (a -s script can't name them directly).


func _process(_delta: float) -> bool:
	quit(load("res://tools/check_uniques.gd").new().run())
	return true
