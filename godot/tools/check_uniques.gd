extends RefCounted
## Checks the unique table: `godot --headless --path . -s tools/run_check.gd`
## Every entry has a valid base and known stats, names never repeat, legendary drops only give uniques
## from the table and every unique can drop (a tier with a drop weight), and each one's tooltip and the
## stats it grants compute. Exits 1 on any failure.

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
	print("UNIQUES count=%d names=%d dropped=%d problems=%d" % [Data.LEGENDARY.size(), names.size(), seen.size(), bad.size()])
	for b in bad.slice(0, 20):
		print("  ", b)
	return 1 if not bad.is_empty() or Data.LEGENDARY.size() != 1000 else 0
