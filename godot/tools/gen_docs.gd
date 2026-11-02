extends SceneTree
## Writes the game-data reference to docs/db (see scripts/data_docs.gd):
## `godot --headless --path . -s tools/gen_docs.gd`


func _process(_delta: float) -> bool:
	var docs = load("res://scripts/data_docs.gd")   # loaded here: it names autoloads
	var files: Dictionary = docs.files()
	var dir := ProjectSettings.globalize_path(docs.DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	for name in files:
		var f := FileAccess.open(dir + name, FileAccess.WRITE)
		f.store_string(files[name])
		f.close()
	print("DOCS wrote %d files to %s" % [files.size(), dir.simplify_path()])
	quit(0)
	return true
