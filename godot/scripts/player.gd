class_name Player
extends Actor

var cls := Data.DEFAULT_CLASS   # base class (Data.CLASSES): the stat lean, the look and the three ascendancies on offer
var level := 1
var xp := 0
var tree: Array = []         # passive tree nodes taken (PassiveTree), in the order they were taken
# ascendancy: the chosen lineage, ranks of its minor nodes, the core talent picked in each tier
var asc := ""
var asc_ranks := {}
var asc_cores: Array = ["", "", ""]
var buffs := {}              # stacking timed buffs from core talents: key -> {"n", "t"}
var combo := 0               # attack skills used, for "three strikes"
var tbuffs := {}             # timed self buffs from buff skills: skill id -> {"t", "stats"}
var auras: Array = []        # aura skills switched on, in the order they were switched on
var aura_fx: Node3D          # the ground marks of the active auras
var _aura_key := ""
var atlas: Atlas             # for the atlas passives that change stats
var chill := 0.0             # slowed by the witch's frost
var life := 100.0
var mana := 60.0
var s := {}                 # derived stats
var cds := {}
var action_t := 0.0
var swing_t := 0.0
var invuln := 0.0
var aim := 0.0
var dash := {}
var potions := 3
var potion_prog := 0
var torch: OmniLight3D
var act_left := 0.0          # time the current one-shot animation still owns the body
# inventory
const BAG_SIZE := 30
const BASE_POTIONS := 5
var equip := {}              # slot -> item
var bag: Array = []
var cur := {}                # currency key -> count
var effects := {}            # legendary effects granted by gear
# skills: the skill in each skill bar slot, the support gems linked to each slot, and the gems owned
var slots: Array = Data.DEFAULT_SLOTS.duplicate()
var links: Array = [[], [], [], [], [], []]
var gems: Array = Data.DEFAULT_GEMS.duplicate()
# the weapon in hand per weapon base: a mesh already on the Knight rig or a KayKit glTF; two-handers drop the shield
const WEAPON_MODELS := {
	"片手剣": {"rig": "1H_Sword"}, "戦斧": {"gltf": "axe_1handed"}, "大槌": {"gltf": "axe_2handed", "two": true},
	"ルーンの杖": {"gltf": "staff", "two": true}, "短剣": {"gltf": "dagger"},
}
var _gear_key := "-"          # weapon base last shown; "-" forces the first refresh
var _held: Node3D
# loot filter: per rarity "pick" | "sell" (sold on pickup) | "hide" (sold the moment it drops);
# unchecked equipment slots are hidden too, except legendaries
var filter := default_filter()


func _init() -> void:
	super()
	for c in Data.CURRENCIES:
		cur[c.k] = 0
	var sword := Items.generate(1, 0.0, 0, "weapon")
	sword.merge({"base": "片手剣", "name": "片手剣", "min": 5, "max": 9, "aps": 1.5}, true)
	equip.weapon = sword


func _ready() -> void:
	r = 0.45
	use_rig(Assets.ADVENTURERS + "Knight.glb", 1.0, ["1H_Sword", "Round_Shield"])
	Heroine.dress(self, cls)
	torch = OmniLight3D.new()
	torch.position = Vector3(0, 3.2, 0)
	torch.omni_range = 15.0
	torch.light_energy = 2.2
	torch.shadow_enabled = true
	add_child(torch)
	recalc(true)


## become base class `k`; with `kit`, also take its starting weapon, skill bar and gems (a new character)
func set_class(k: String, kit := false) -> void:
	cls = k if not Data.base_class(k).is_empty() else Data.DEFAULT_CLASS
	var bc := Data.base_class(cls)
	if kit:
		var b: Dictionary = Data.BASES.weapon.filter(func(x): return x.name == bc.weapon)[0]
		var w := Items.generate(1, 0.0, 0, "weapon")
		w.merge({"base": b.name, "name": b.name, "min": b.min + 1, "max": b.max + 1, "aps": b.aps,
			"implicit": b.get("implicit", {}).duplicate()}, true)
		equip = {"weapon": w}
		slots = bc.slots.duplicate()
		links = [[], [], [], [], [], []]
		gems = bc.gems.duplicate()
	if rig:
		Heroine.paint(self, cls)
	recalc(true)


static func default_filter() -> Dictionary:
	var sl := {}
	for k in Data.SLOTS:
		sl[k] = true
	return {"rarity": ["pick", "pick", "pick", "pick"], "slots": sl}


## "pick" | "sell" | "hide" for an item under the loot filter
func item_action(it: Dictionary) -> String:
	if it.rarity < 3 and not filter.slots.get(it.slot, true):
		return "hide"
	return filter.rarity[it.rarity]


func max_potions() -> int:
	return BASE_POTIONS + (roundi(atlas.val("flask")) if atlas else 0)


## derived stats from level, the passive tree and gear
func recalc(full := false) -> void:
	var L := level
	var old_l: float = life / s.max_life if s else 1.0
	var old_m: float = mana / s.max_mana if s else 1.0
	var st := {
		"max_life": 90.0 + L * 12, "max_mana": 60.0 + L * 5, "life_regen": 1.5 + L * 0.25, "mana_regen": 5.0 + L * 0.3,
		"dmg_min": 2.0 + L, "dmg_max": 4.0 + L * 2, "aps": 1.3, "crit": 5.0, "crit_multi": 150.0,
		"inc_dmg": 0, "flat_dmg": 0, "atk_spd": 0, "cast_spd": 0, "move_spd": 0, "armor": 0, "fire_dmg": 0, "cold_dmg": 0,
		"light_dmg": 0, "spell_dmg": 0, "life_on_kill": 0, "cdr": 0, "life": 0, "mana": 0,
		"atk_dmg": 0, "ally_dmg": 0, "ally_life": 0, "energy": 0, "chaos_dmg": 0, "dr_pct": 0,
		"life_pct": 0, "mana_pct": 0,
	}
	var bc := Data.base_class(cls)
	for k in bc.get("stats", {}):
		st[k] += bc.stats[k]
	effects = {}
	for slot in equip:
		var it: Dictionary = equip[slot]
		if slot == "weapon":
			st.dmg_min += it.min
			st.dmg_max += it.max
			st.aps = it.aps
		st.armor += it.get("armor", 0)
		for src in [it.implicit, it.mods]:
			for k in src:
				st[k] = st.get(k, 0) + src[k]
		if it.has("effect"):
			effects[it.effect] = true
	var ts := PassiveTree.stats(tree)
	for k in ts:
		st[k] = st.get(k, 0) + ts[k]
	var a := Data.ascendancy(asc)
	if not a.is_empty():
		for n in a.minors:
			for k in n.stats:
				st[k] = st.get(k, 0) + n.stats[k] * asc_rank(n.id)
		for k in asc_cores:
			if k != "":
				effects[k] = true
				var c := Data.asc_core(a, k)
				for sk in c.get("stats", {}):
					st[sk] = st.get(sk, 0) + c.stats[sk]
	st.dmg_min += st.flat_dmg
	st.dmg_max += st.flat_dmg
	st.max_life = (st.max_life + st.life) * (1.0 + st.life_pct / 100.0)
	st.max_mana = (st.max_mana + st.mana) * (1.0 + st.mana_pct / 100.0)
	st.life_regen += atlas.val("ward") if atlas else 0.0
	if effects.has("chant_power"):
		st.spell_dmg += st.cast_spd
	# unique-item keystones that reshape the stats above
	if effects.has("swift_blade"):
		st.atk_spd += st.move_spd
	if effects.has("spell_blade"):
		st.atk_dmg += st.spell_dmg
	if effects.has("elem_unity"):
		var top: float = maxf(st.fire_dmg, maxf(st.cold_dmg, st.light_dmg))
		st.fire_dmg = top
		st.cold_dmg = top
		st.light_dmg = top
	if effects.has("armor_life"):
		st.max_life += st.armor * 0.2
	if effects.has("life_to_mana"):
		st.max_mana += st.max_life * 0.2
		st.max_life *= 0.8
	if effects.has("no_crit"):
		st.crit = 0.0
		st.inc_dmg += 45
	# stacked unique drawbacks must never empty the pools
	st.max_life = maxf(1.0, st.max_life)
	st.max_mana = maxf(1.0, st.max_mana)
	st.move_speed = 8.5 * (1.0 + st.move_spd / 100.0)
	st.attack_rate = st.aps * (1.0 + st.atk_spd / 100.0)
	st.dr = minf(0.75, st.armor / (st.armor + 60.0 + L * 10.0))
	st.cdr = mini(40, st.cdr)
	s = st
	life = s.max_life if full else s.max_life * old_l
	mana = s.max_mana if full else s.max_mana * old_m
	fix_auras()
	life = minf(life, cap("life"))
	mana = minf(mana, cap("mana"))
	refresh_gear()


## show the equipped weapon in hand and the shield with one-handers
func refresh_gear() -> void:
	if rig == null:
		return
	var base: String = equip.get("weapon", {}).get("base", "")
	if base == _gear_key:
		return
	_gear_key = base
	var m: Dictionary = WEAPON_MODELS.get(base, {})
	rig.find_child("1H_Sword", true, false).visible = m.get("rig", "") == "1H_Sword"
	rig.find_child("Round_Shield", true, false).visible = not m.is_empty() and not m.get("two", false)
	if _held:
		for mi in _held.find_children("*", "MeshInstance3D", true, false):
			rig_meshes.erase(mi)
		_held.queue_free()
		_held = null
	if m.has("gltf"):
		var att := BoneAttachment3D.new()
		att.bone_name = "handslot.r"
		rig.find_child("Skeleton3D", true, false).add_child(att)
		att.add_child(Assets.scene(Assets.ADVENTURER_GEAR + m.gltf + ".gltf").instantiate())
		for mi in att.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mi.material_overlay = rig_meshes[0].material_overlay if not rig_meshes.is_empty() else null
			rig_meshes.append(mi)
		_held = att


# ---- support gem energy ----
func energy_max() -> int:
	return Data.energy_base(level) + int(s.get("energy", 0))


func energy_used() -> int:
	var n := 0
	for l in links:
		for gid in l:
			n += Data.support(gid).get("energy", 0)
	return n


## the gems of slot `i` the pool still powers: slots draw in bar order, so if gear that raised
## the pool comes off, the last links on the bar go dark first
func active_links(i: int) -> Array:
	var left := energy_max()
	for j in links.size():
		var on := []
		for gid in links[j]:
			var e: int = Data.support(gid).get("energy", 0)
			if e <= left:
				left -= e
				on.append(gid)
		if j == i:
			return on
	return []


# ---- passive tree ----
## one point per level after the first
func tree_points() -> int:
	return maxi(0, level - 1)


func tree_free() -> int:
	return tree_points() - tree.size()


# ---- ascendancy ----
func asc_rank(id: String) -> int:
	return int(asc_ranks.get(id, 0))


func asc_spent() -> int:
	var n := 0
	for id in asc_ranks:
		n += int(asc_ranks[id])
	return n


func asc_free() -> int:
	return Data.asc_points(level) - asc_spent()


func asc_reset_price() -> int:
	return asc_spent() * 25


func add_buff(k: String, max_n: int, dur: float) -> void:
	var b: Dictionary = buffs.get(k, {"n": 0, "t": 0.0})
	b.n = mini(max_n, b.n + 1)
	b.t = dur
	buffs[k] = b


func buff(k: String) -> int:
	return int(buffs[k].n) if buffs.has(k) else 0


func tick_buffs(delta: float) -> void:
	for list in [buffs, tbuffs]:
		for k in list.keys():
			list[k].t -= delta
			if list[k].t <= 0.0:
				list.erase(k)


func add_tbuff(id: String, dur: float, stats: Dictionary) -> void:
	tbuffs[id] = {"t": dur, "stats": stats}


## a stat summed over the active buff skills: dmg, atk_spd, cast_spd, move, dr (all %) and regen (% life per second)
func tstat(k: String) -> float:
	var v := 0.0
	for id in tbuffs:
		v += tbuffs[id].stats.get(k, 0.0)
	return v


# ---- auras and reservation ----
## the support modifiers of an aura on the bar (its reservation scales with their mana multiplier)
func aura_sup(id: String) -> Dictionary:
	var i := slots.find(id)
	return Data.build_sup(id, active_links(i) if i >= 0 else [])


## how much of `pool` ("life" | "mana") aura `id` holds while it is on
func aura_reserve(id: String, pool: String) -> float:
	var a: Dictionary = Data.SKILLS[id].aura
	if a.pool != pool:
		return 0.0
	var mx: float = s.max_life if pool == "life" else s.max_mana
	return ceilf((mx * a.pct / 100.0 + a.flat) * aura_sup(id).mana)


## the part of a pool the auras in `list` hold
func reserved(pool: String, list: Array = auras) -> float:
	var n := 0.0
	for id in list:
		n += aura_reserve(id, pool)
	return n


## the most life or mana the player can have right now
func cap(pool: String) -> float:
	return maxf(0.0, (s.max_life if pool == "life" else s.max_mana) - reserved(pool))


## the auras in `list` fit if they leave at least 1 life (mana may be reserved in full)
func reserve_fits(list: Array) -> bool:
	return reserved("life", list) <= s.max_life - 1.0 and reserved("mana", list) <= s.max_mana


## switch aura `id` on or off; "" when done, else why it was refused
func toggle_aura(id: String) -> String:
	if id in auras:
		auras.erase(id)
		return ""
	if not reserve_fits(auras + [id]):
		return "full"
	auras.append(id)
	life = minf(life, cap("life"))
	mana = minf(mana, cap("mana"))
	return ""


## drop auras that left the bar, then the latest ones while the reservation no longer fits
## (lost gear, unlinked gems); returns the ids switched off
func fix_auras() -> Array:
	var off := auras.filter(func(id): return not id in slots or not Data.SKILLS[id].has("aura"))
	auras = auras.filter(func(id): return not id in off)
	while not auras.is_empty() and not reserve_fits(auras):
		off.append(auras.pop_back())
	return off


## a stat summed over the active auras, in the same keys as tstat; `beff` gems strengthen them
func astat(k: String) -> float:
	var v := 0.0
	for id in auras:
		v += Data.SKILLS[id].aura.stats.get(k, 0.0) * aura_sup(id).beff
	return v


## buffs and auras together, for the player
func bonus(k: String) -> float:
	return tstat(k) + astat(k)


## a dashed band at the edge of each active aura's reach and a glowing sigil at the feet, turning slowly
func update_aura_fx(delta: float) -> void:
	var key := ",".join(PackedStringArray(auras))
	if key != _aura_key:
		_aura_key = key
		if aura_fx:
			aura_fx.queue_free()
		aura_fx = Node3D.new()
		add_child(aura_fx)
		for i in auras.size():
			var sk: Dictionary = Data.SKILLS[auras[i]]
			var col: Color = sk.color
			var spin := Node3D.new()
			spin.position.y = 0.05 + i * 0.01
			aura_fx.add_child(spin)
			var r: float = sk.aura.r - i * 0.35
			var m := Fx.mat(Color(col, 0.55), 2.5, true)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			for k in 12:
				var a0 := TAU * k / 12.0
				Fx.mesh(spin, Fx.arc_mesh(r - 0.12, r, a0, a0 + TAU / 20.0, 6), m)
			var mi := Fx.mat(Color(col, 0.35), 2.0, true)
			mi.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mi.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			var rr := 0.9 + i * 0.28
			Fx.mesh(spin, Fx.arc_mesh(rr - 0.07, rr, 0.0, TAU, 32), mi)
			for k in 3:
				var a0 := TAU * k / 3.0 + i * 0.5
				Fx.mesh(spin, Fx.arc_mesh(rr + 0.06, rr + 0.2, a0, a0 + 0.5, 6), mi)
	if aura_fx:
		for i in aura_fx.get_child_count():
			aura_fx.get_child(i).rotation.y += delta * (0.35 if i % 2 == 0 else -0.28)


func low_life() -> bool:
	return effects.has("deathline") and life <= s.max_life * 0.5


## attacks per second right now, with the core talents' temporary boosts
func attack_rate_now() -> float:
	return s.aps * (1.0 + (s.atk_spd + buff("fervor") * 2 + buff("rage_kill") * 4 + (20 if low_life() else 0) + bonus("atk_spd")) / 100.0)


func cast_speed_now() -> float:
	return 1.0 + (s.cast_spd + buff("spell_frenzy") * 5 + bonus("cast_spd")) / 100.0


## play an attack/cast clip that holds for `hold` seconds before locomotion resumes
func act(clip: String, speed: float, hold: float) -> void:
	play(clip, speed, true, 0.05)
	act_left = hold


func animate(delta: float, moving: bool) -> void:
	face = aim
	sync_node(delta, moving)
	act_left -= delta
	if dead:
		play("Death_A", 1.0, false, 0.1)
	elif not dash.is_empty():
		play("Dodge_Forward", 2.0)
	elif act_left > 0.0:
		pass
	elif moving:
		play("Running_A", 1.2)
	else:
		play("Idle")
