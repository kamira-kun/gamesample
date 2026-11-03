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
	var awake := _check_awakened()
	print("AWAKENED problems=%s" % [awake])
	quit(code if stale.is_empty() and hits.is_empty() and awake.is_empty() else 1)
	return true


## #63: one awakened gem per support gem, each stronger than its base and needing a higher level (which blocks
## linking it), never in the merchant's gem pool, in the drop chances of deep elites and bosses and in the exchange's lists
func _check_awakened() -> Array:
	var data = load("res://scripts/data.gd")
	var bad := []
	var aw: Array = data.awakened()
	if aw.size() != data.SUPPORTS.size() or data.AWAKE_DESC.size() != data.SUPPORTS.size():
		bad.append("count")
	for g in data.SUPPORTS:
		var a: Dictionary = data.support(data.AWAKE_ID + g.id)
		var sk: String = data.SKILL_ORDER.filter(func(id): return data.support_fits(g, id))[0]
		var sb: Dictionary = data.build_sup(sk, [g.id])
		var sa: Dictionary = data.build_sup(sk, [a.id])
		var better := false
		for k in sb:
			if sb[k] is float or sb[k] is int:
				var d: float = (sb[k] - sa[k]) if k == "mana" else (sa[k] - sb[k])
				if d < -0.0001:
					bad.append("weaker:%s.%s" % [g.id, k])
				better = better or d > 0.0001
		if not better:
			bad.append("not_stronger:" + g.id)
		if a.lvl <= g.lvl or a.lvl < data.AWAKE_LVL_MIN or a.desc == g.desc or not a.name.begins_with(data.AWAKE_NAME):
			bad.append("data:" + g.id)
	if data.missing_gems([], [], 999).any(func(g): return data.is_awakened(g.id)) or data.SUPPORTS.any(func(g): return data.is_awakened(g.id)):
		bad.append("merchant")
	var p = load("res://scripts/player.gd").new()
	var a_id: String = data.AWAKE_ID + "power"
	p.gems = [a_id]
	p.level = data.support(a_id).lvl - 1
	var low: bool = p.can_use_gem(a_id)
	p.level += 1
	if low or not p.can_use_gem(a_id):
		bad.append("level")
	p.free()
	var main = load("res://scripts/main.gd")
	if main.awake_chance(data.AWAKE_DROP_ILVL, true, false) <= 0.0 or main.awake_chance(data.AWAKE_DROP_ILVL - 1, true, false) != 0.0 			or main.awake_chance(data.AWAKE_DROP_ILVL, false, false) != 0.0:
		bad.append("drops")
	var ex = load("res://scripts/exchange.gd")
	var open: Array = ex._lots(ex._clean({"cat": "gem"})).slice(0, ex.RESULTS)
	if open.filter(func(l): return data.is_awakened(l.id)).size() != ex.AWAKE_OPEN 			or not aw.all(func(a): return a.name in ex.base_names("gem") and ex._lots(ex._clean({"cat": "gem", "base": a.name}))[0].id == a.id):
		bad.append("exchange")
	return bad
