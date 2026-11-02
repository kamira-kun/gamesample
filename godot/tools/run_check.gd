extends SceneTree
## Runs tools/check_uniques.gd once the autoloads are up (a -s script can't name them directly), then
## checks that the data reference in docs/db matches the game data (regenerate with tools/gen_docs.gd).


func _process(_delta: float) -> bool:
	var code: int = load("res://tools/check_uniques.gd").new().run()
	var docs = load("res://scripts/data_docs.gd")   # loaded here: it names autoloads
	var files: Dictionary = docs.files()
	var stale := []
	for name in files:
		# a checkout may turn LF into CRLF
		if FileAccess.get_file_as_string(docs.DIR + name).replace("\r\n", "\n") != files[name]:
			stale.append(name)
	print("DOCS files=%d stale=%s" % [files.size(), stale])
	if not stale.is_empty():
		print("  docs/db is out of date: run `godot --headless --path . -s tools/gen_docs.gd`")
	quit(code if stale.is_empty() else 1)
	return true
