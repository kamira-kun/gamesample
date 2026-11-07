extends SceneTree
## Runs tools/check_uniques.gd once the autoloads are up (a -s script can't name them directly), then
## checks that the data reference in docs/db matches the game data (regenerate with tools/gen_docs.gd).


var _icons_drawn := -1


func _process(_delta: float) -> bool:
	if _icons_drawn < 0:   # #71: draw every compass icon on a canvas first; the checks run on the next frame
		_icons_drawn = 0
		var cv := Control.new()
		cv.size = Vector2(64, 64)
		cv.draw.connect(func():
			for id in load("res://scripts/charms.gd").all_ids():
				load("res://scripts/charms.gd").draw_icon(cv, Vector2(32, 32), 32.0, id)
				_icons_drawn += 1)
		root.add_child(cv)
		return false
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
	var glv := _check_gem_levels()
	print("GEM_LEVELS problems=%s" % [glv])
	var icons := _check_compass_icons()
	print("COMPASS_ICONS drawn=%d problems=%s" % [_icons_drawn, icons])
	var tiers := _check_map_tiers()
	print("MAP_TIERS problems=%s" % [tiers])
	var regular := _check_regular_enemies()
	print("REGULAR_ENEMIES problems=%s" % [regular])
	quit(code if stale.is_empty() and hits.is_empty() and awake.is_empty() and glv.is_empty() and icons.is_empty() and tiers.is_empty() and regular.is_empty() else 1)
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


## #68: gem levels run 1..20 on a rising curve, experience levels a gem up only as far as the character's level lets
## it and never past 20, every level is at least as strong as the one before (and Lv 20 does more damage than Lv 1),
## and the character level a gem asks for rises with its level and gates using it
func _check_gem_levels() -> Array:
	var data = load("res://scripts/data.gd")
	var bad := []
	var top: int = data.GEM_MAX_LV
	if top != 20:
		bad.append("max")
	for lv in range(1, top + 1):
		if data.gem_level(data.gem_xp_at(lv)) != lv or (lv > 1 and data.gem_level(data.gem_xp_at(lv) - 1) != lv - 1):
			bad.append("curve:%d" % lv)
		if lv < top - 1 and data.gem_xp_need(lv + 1) <= data.gem_xp_need(lv):
			bad.append("need:%d" % lv)
	if data.gem_level(1 << 40) != top:
		bad.append("level_cap")
	for g in data.all_supports():
		var sk: String = data.SKILL_ORDER.filter(func(id): return data.support_fits(g, id))[0]
		var prev: Dictionary = data.build_sup(sk, [g.id])
		for lv in range(2, top + 1):
			var cur: Dictionary = data.build_sup(sk, [g.id], {g.id: lv})
			for k in cur:
				if (cur[k] is float or cur[k] is int) and ((prev[k] - cur[k]) if k == "mana" else (cur[k] - prev[k])) < -0.0001:
					bad.append("weaker:%s@%d.%s" % [g.id, lv, k])
			prev = cur
		if prev.dmg <= data.build_sup(sk, [g.id]).dmg:
			bad.append("flat:" + g.id)
		if data.gem_req(false, g.id, top) != g.lvl + (top - 1) * data.GEM_LV_REQ:
			bad.append("req:" + g.id)
	for id in data.SKILL_ORDER:
		if data.build_sup(id, [], {data.gem_key(true, id): top}).dmg <= data.build_sup(id, []).dmg:
			bad.append("skill_flat:" + id)
	var p = load("res://scripts/player.gd").new()
	p.gems = ["power", data.AWAKE_ID + "power"]
	p.level = 1
	p.add_gem_xp(false, "power", 1 << 30)
	if p.gem_lv(false, "power") != 1 or not p.gem_waiting(false, "power"):
		bad.append("gate_growth")
	p.level = 10
	if p.add_gem_xp(false, "power", 1 << 30) != 5:
		bad.append("grow_to_req")
	p.level = 200
	p.add_gem_xp(false, "power", 1 << 30)
	p.add_gem_xp(false, "power", 1 << 30)
	if p.gem_lv(false, "power") != top or p.gem_xp.power != data.gem_xp_at(top):
		bad.append("cap")
	# awakened gems level too, from their own higher requirement
	var a_id: String = data.AWAKE_ID + "power"
	p.set_gem_lv(false, a_id, 5)
	var need: int = data.support(a_id).lvl + 4 * data.GEM_LV_REQ
	p.level = need - 1
	var low: bool = p.can_use_gem(a_id)
	p.level = need
	if low or not p.can_use_gem(a_id) or p.gem_req(false, a_id) != need or need <= data.gem_req(false, "power", 5):
		bad.append("awake_req")
	p.free()
	return bad


## #71: every compass drew its icon, and each one reads apart: the families by colour, the tiers by dial ticks and bezel studs
func _check_compass_icons() -> Array:
	var ch = load("res://scripts/charms.gd")
	var bad := []
	if _icons_drawn != ch.all_ids().size():
		bad.append("drawn")
	var seen := {}
	for f in ch.FAMILIES:
		var prev := {}
		for t in f.tiers.size():
			var sp: Dictionary = ch.icon_spec(ch.id_of(f.k, t))
			if sp.fam != f.shell:
				bad.append("colour:" + f.k)
			if not prev.is_empty() and (sp.ticks <= prev.ticks or sp.studs <= prev.studs):
				bad.append("tier:%s_%d" % [f.k, t + 1])
			if sp.ticks % 4 != 0:
				bad.append("cardinals:%s_%d" % [f.k, t + 1])
			prev = sp
		if seen.has(f.shell.to_html()):
			bad.append("same_colour:" + f.k)
		seen[f.shell.to_html()] = true
	if ch.ICON != "⊕":
		bad.append("glyph")
	return bad


## #74: tiers have no cap: monster life, damage, ember and map value rise every tier, the life step widens with depth and
## is steeper than the area level alone gave; low tiers stay close to before; keys past the old cap are valid; every
## number stays finite and in range up to TIER_LIMIT; the device buys back for less than it sells
func _check_map_tiers() -> Array:
	var M = load("res://scripts/maps.gd")
	var out := []
	var prev_step := 0.0
	for t in range(1, 2001):
		if not (M.life_mult(t + 1) > M.life_mult(t) or M.life_mult(t) >= M.POWER_MAX):
			out.append("life T%d" % t)
		if not (M.dmg_mult(t + 1) > M.dmg_mult(t) or M.life_mult(t) >= M.POWER_MAX):
			out.append("dmg T%d" % t)
		if M.value(t + 1) <= M.value(t):
			out.append("value T%d" % t)
		var step: float = M.life_mult(t + 1) / M.life_mult(t)
		if M.life_mult(t + 1) < M.POWER_MAX and step < prev_step - 1e-9:
			out.append("step T%d" % t)
		prev_step = step
		for v in [M.life_mult(t), M.dmg_mult(t), M.gold_mult(t), M.quantity_bonus(t), M.rarity_bonus(t)]:
			if is_nan(v) or is_inf(v) or v < 0.0:
				out.append("number T%d" % t)
	for t in [M.TIER_LIMIT - 1, M.TIER_LIMIT]:
		if M.value(t) <= 0 or M.value(t) > (1 << 60) or M.sell_price(t) <= 0 or M.sell_price(t) >= M.value(t):
			out.append("value range T%d" % t)
	if M.value(M.TIER_LIMIT) <= M.value(M.TIER_LIMIT - 1):
		out.append("value at the limit")
	if M.life_mult(16) < 2.0 or M.life_mult(26) / M.life_mult(16) < 2.5:
		out.append("not steeper")
	if M.life_mult(2) > 1.05 or M.dmg_mult(3) > 1.06 or M.value(1) != 40 or M.quantity_bonus(1) != 0.0:
		out.append("low tiers moved")
	for k in ["ash:17", "ash:26", "ash:100", "ash:%d" % M.TIER_LIMIT]:
		if not M.valid(k):
			out.append("invalid " + k)
	for k in ["ash:0", "ash:%d" % (M.TIER_LIMIT + 1), "ash:-1"]:
		if M.valid(k):
			out.append("valid " + k)
	if M.level_of(1 << 40) != M.TIER_LIMIT or M.tier_from(1e300) != M.TIER_LIMIT or M.tier_from(NAN) != 0 or M.tier_from("x") != 0:
		out.append("clamps")
	var top := 0
	for i in 400:
		top = maxi(top, M.parse(M.roll(M.OLD_MAX_TIER + 10, true)).tier)
	if top != M.OLD_MAX_TIER + 12:
		out.append("boss drop top %d" % top)
	return out


## #79: every regular kind is in the floor spawns and the ambush packs, each has a telegraph and one pattern of its
## own (the three new kinds: a lunge, a fuse, a mend), and brute and shaman take a steady share of the floor-1 rooms
func _check_regular_enemies() -> Array:
	var D = load("res://scripts/data.gd")
	var out := []
	var kinds: Array = D.REGULAR_KINDS
	var spawn_kinds := []
	var total := 0.0
	for q in D.spawn_pool():
		spawn_kinds.append(q.k)
		total += q.w
	var ambush_kinds := []
	for q in D.ambush_pool():
		ambush_kinds.append(q.k)
	for k in kinds:
		var t: Dictionary = D.ENEMY_TYPES.get(k, {})
		if t.is_empty() or t.get("boss", false):
			out.append("type %s" % k)
			continue
		if not spawn_kinds.has(k):
			out.append("spawn %s" % k)
		if not ambush_kinds.has(k):
			out.append("ambush %s" % k)
		if float(t.get("windup", 0.0)) <= 0.0:
			out.append("telegraph %s" % k)
	for k in spawn_kinds:
		if not kinds.has(k):
			out.append("unlisted spawn %s" % k)
	for k in ambush_kinds:
		if not kinds.has(k):
			out.append("unlisted ambush %s" % k)
	for k in ["charger", "bomber", "healer"]:
		var t: Dictionary = D.ENEMY_TYPES.get(k, {})
		var own := ["dash", "fuse", "heal"].filter(func(f): return t.has(f))
		if own.size() != 1 or t.has("ranged") or t.has("caster"):
			out.append("pattern %s %s" % [k, own])
	for k in ["brute", "shaman"]:
		for q in D.spawn_pool():
			if q.k == k and q.w / total < 0.08:
				out.append("floor1 share %s %.3f" % [k, q.w / total])
	return out
