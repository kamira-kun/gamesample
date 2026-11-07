extends RefCounted
## Checks the unique table: `godot --headless --path . -s tools/run_check.gd`
## Every entry has a valid base and known stats, names never repeat, legendary drops only give uniques
## from the table and every unique can drop (a tier with a drop weight), and each one's tooltip and the
## stats it grants compute; the combinations (Data.COMBOS), unique ascendancies and unique jewels and tablets all fit
## together and every effect they name is one the game reads. Exits 1 on any failure.

# effect keys the game checks (legendary effects, ascendancy cores, unique-only keystones)
const KNOWN_FX := ["fireball_multi", "dash_nova", "chain_plus", "slash_wave", "kill_heal", "meteor_shower", "nova_on_hit",
	"swift_blade", "spell_blade", "elem_unity", "armor_life", "life_to_mana", "no_crit"]


func run() -> int:
	var bad := []
	var known := KNOWN_FX.duplicate()
	for a in Data.ASCENDANCIES:
		for tier in a.cores:
			for c in tier:
				known.append(c.id)
	var names := {}
	for l in Data.LEGENDARY:
		if names.has(l.name):
			bad.append("duplicate name " + l.name)
		names[l.name] = true
		if not Data.SLOTS.has(l.slot) or l.base >= Data.BASES[l.slot].size():
			bad.append("bad slot/base " + l.name)
		if l.has("effect") and not l.effect in known:
			bad.append("unknown effect %s on %s" % [l.effect, l.name])
		for k in l.get("mods", {}):
			if Data.affix(k).is_empty():
				bad.append("unknown stat %s on %s" % [k, l.name])
		if Data.unique_weight(l.name) <= 0.0:
			bad.append("never drops " + l.name)
	# drops: legendary rolls give known uniques; then each unique's tooltip and stats work
	var seen := {}
	for i in 20000:
		var it := Items.generate(randi_range(1, 60), 0.0, 3)
		if not names.has(it.name):
			bad.append("dropped unknown " + it.name)
		seen[it.name] = true
	var p := Player.new()
	var sword: Dictionary = p.equip.weapon
	for l in Data.LEGENDARY:
		var it := Items.generate(randi_range(1, 60), 0.0, 3, "", l.name)
		if it.name != l.name:
			bad.append("could not roll " + l.name)
		for ln in Items.lines(it):
			if "+-" in ln[0]:
				bad.append("bad tooltip line on %s: %s" % [it.name, ln[0]])
		p.equip = {"weapon": sword}
		p.equip[it.slot] = it
		p.level = it.ilvl  # drops roll item level from the area, close to the character's level
		p.recalc(true)
		if not (p.s.max_life > 0 and p.s.max_mana > 0 and p.s.attack_rate > 0 and p.s.dr < 1.0):
			bad.append("broken stats with %s (lv%d life %d mana %d)" % [it.name, it.ilvl, p.s.max_life, p.s.max_mana])
		if Items.craft("divine", it) != "" and it.mods.size() > 0:
			bad.append("divine failed on " + it.name)
	p.free()
	bad.append_array(_check_combos())
	bad.append_array(_check_pieces())
	print("UNIQUES count=%d names=%d dropped=%d problems=%d" % [Data.LEGENDARY.size(), names.size(), seen.size(), bad.size()])
	for b in bad.slice(0, 20):
		print("  ", b)
	return 1 if not bad.is_empty() or Data.LEGENDARY.size() != 1015 else 0


## #77: each combination's needs exist, and each unique ascendancy has one that names it and a partner its text gives
func _check_combos() -> Array:
	var bad := []
	var ids := {}
	for c in Data.COMBOS:
		if ids.has(c.id) or c.name == "" or c.desc == "" or c.stats.is_empty():
			bad.append("incomplete combo " + c.id)
		ids[c.id] = true
		if c.needs.get("cores", []).size() + c.needs.get("uniques", []).size() < 2:
			bad.append("combo %s needs two things" % c.id)
		if c.needs.has("cls") and Data.base_class(c.needs.cls).is_empty():
			bad.append("unknown class in " + c.id)
		for k in c.stats:
			if not PassiveTree.FMT.has(k):
				bad.append("combo %s stat %s has no text" % [c.id, k])
		for k in c.needs.get("cores", []):
			if not Data.any_core(k).get("unique", false):
				bad.append("combo %s core %s is not a unique ascendancy" % [c.id, k])
		for n in c.needs.get("uniques", []):
			if Data.legend(n).is_empty() and Jewels.unique_def(n).is_empty() and Tablets.unique_def(n).is_empty():
				bad.append("combo %s names no unique %s" % [c.id, n])
	for a in Data.ASCENDANCIES:
		var top: Array = a.cores.back().filter(func(c): return c.get("unique", false))
		if top.size() != 1:
			bad.append("%s has %d unique ascendancies" % [a.k, top.size()])
		for c in top:
			var cbs := Data.combos_of(c.id)
			if c.get("stats", {}).is_empty() or cbs.is_empty():
				bad.append("unique ascendancy %s gives nothing" % c.id)
			elif not cbs[0].needs.uniques.all(func(n): return n in c.desc):
				bad.append("unique ascendancy %s doesn't name its partner" % c.id)
	return bad


## #77: the unique jewels and tablets are well formed, no name is used twice, and every effect of the hand-made uniques
## is one the game's code reads (a stats-only core's id would set a flag nothing looks at)
func _check_pieces() -> Array:
	var bad := []
	var code := ""
	for f in ["main", "player", "ally"]:
		code += FileAccess.get_file_as_string("res://scripts/%s.gd" % f)
	var names := {}
	for l in Data.LEGENDARY:
		names[l.name] = true
	var fx := Data.LEGENDARY.filter(func(l): return l.has("tier") and l.has("effect")).map(func(l): return l.effect)
	for u in Jewels.UNIQUES + Tablets.UNIQUES:
		if names.has(u.name):
			bad.append("duplicate name " + u.name)
		names[u.name] = true
		if u.tier >= Data.UNIQUE_TIERS.size() or u.mods.is_empty() or u.flavor == "":
			bad.append("incomplete unique " + u.name)
		if u.has("effect"):
			fx.append(u.effect)
			if not u.has("desc"):
				bad.append("no text for the effect of " + u.name)
	for k in fx:
		if not ('has("%s")' % k) in code:
			bad.append("effect %s is read nowhere" % k)
	for u in Jewels.UNIQUES:
		if (Jewels.size_def(u.base) if u.kind == "ring" else Jewels.base(u.base)).is_empty():
			bad.append("bad base " + u.name)
		for k in u.mods:
			if not PassiveTree.FMT.has(k):
				bad.append("no text for %s on %s" % [k, u.name])
		for id in u.get("notables", []):
			if Jewels.ring_notable(id).is_empty():
				bad.append("unknown notable %s on %s" % [id, u.name])
		if u.kind == "ring" and (Jewels.theme(u.theme).is_empty() or u.notables.size() > Jewels.size_def(u.base).notables):
			bad.append("bad ring " + u.name)
	for u in Tablets.UNIQUES:
		if Tablets.shape(u.shape).is_empty():
			bad.append("bad shape " + u.name)
		for k in u.mods:
			if Data.affix(k).is_empty():
				bad.append("no text for %s on %s" % [k, u.name])
	return bad
