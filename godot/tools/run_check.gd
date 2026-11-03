extends SceneTree
## Runs tools/check_uniques.gd once the autoloads are up (a -s script can't name them directly), then
## checks that the data reference in docs/db matches the game data (regenerate with tools/gen_docs.gd).


func _process(_delta: float) -> bool:
	var code: int = load("res://tools/check_uniques.gd").new().run()
	var docs = load("res://scripts/data_docs.gd")   # loaded here: it names autoloads
	var files: Dictionary = docs.files()
	var stale := []
	for name in files:
		# a checkout may turn LF into CRLF, in the docs and in the scripts' multi-line templates
		if FileAccess.get_file_as_string(docs.DIR + name).replace("\r\n", "\n") != files[name].replace("\r\n", "\n"):
			stale.append(name)
	print("DOCS files=%d stale=%s" % [files.size(), stale])
	if not stale.is_empty():
		print("  docs/db is out of date: run `godot --headless --path . -s tools/gen_docs.gd`")
	# #64: the retired item-kind words (Data.OLD_KIND_WORDS) stay out of the scripts, scenes, README and docs
	var old: Dictionary = load("res://scripts/data.gd").OLD_KIND_WORDS
	var paths := ["res://README.md", "res://../docs/economy-design.md"]
	for dir in ["res://scripts/", "res://scenes/", "res://tools/"]:
		for f in DirAccess.get_files_at(dir):
			if f.get_extension() in ["gd", "tscn"]:
				paths.append(dir + f)
	for name in files:
		paths.append(docs.DIR + name)
	var hits := []
	for path in paths:
		var text := FileAccess.get_file_as_string(path)
		for w in old:
			if w in text:
				hits.append("%s: %s" % [path, w])
	print("OLD_NAMES files=%d hits=%s" % [paths.size(), hits])
	if not hits.is_empty():
		print("  rename these to %s" % [old.values()])
	quit(code if stale.is_empty() and hits.is_empty() else 1)
	return true
