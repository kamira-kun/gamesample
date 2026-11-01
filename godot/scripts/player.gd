class_name Player
extends Actor

var level := 1
var xp := 0
var talent_pts := 0
var talents := {}            # talent key -> rank
# ascendancy: the chosen lineage, ranks of its minor nodes, the core talent picked in each tier
var asc := ""
var asc_ranks := {}
var asc_cores: Array = ["", "", ""]
var buffs := {}              # stacking timed buffs from core talents: key -> {"n", "t"}
var combo := 0               # attack skills used, for "three strikes"
var tbuffs := {}             # timed self buffs from buff skills: skill id -> {"t", "stats"}
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
# loot filter: per rarity "pick" | "sell" (sold on pickup) | "hide" (sold the moment it drops);
# unchecked equipment slots are hidden too, except legendaries
var filter := default_filter()


func _init() -> void:
	super()
	for t in Data.talents():
		talents[t.k] = 0
	for c in Data.CURRENCIES:
		cur[c.k] = 0
	var sword := Items.generate(1, 0.0, 0, "weapon")
	sword.merge({"base": "片手剣", "name": "片手剣", "min": 5, "max": 9, "aps": 1.5}, true)
	equip.weapon = sword


func _ready() -> void:
	r = 0.45
	use_rig(Assets.ADVENTURERS + "Knight.glb", 1.0, ["1H_Sword", "Round_Shield"])
	torch = OmniLight3D.new()
	torch.position = Vector3(0, 3.2, 0)
	torch.omni_range = 15.0
	torch.light_energy = 2.2
	torch.shadow_enabled = true
	add_child(torch)
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


## derived stats from level, talents and gear
func recalc(full := false) -> void:
	var L := level
	var old_l: float = life / s.max_life if s else 1.0
	var old_m: float = mana / s.max_mana if s else 1.0
	var st := {
		"max_life": 90.0 + L * 12, "max_mana": 60.0 + L * 5, "life_regen": 1.5 + L * 0.25, "mana_regen": 5.0 + L * 0.3,
		"dmg_min": 2.0 + L, "dmg_max": 4.0 + L * 2, "aps": 1.3, "crit": 5.0, "crit_multi": 150.0,
		"inc_dmg": 0, "flat_dmg": 0, "atk_spd": 0, "cast_spd": 0, "move_spd": 0, "armor": 0, "fire_dmg": 0, "cold_dmg": 0,
		"light_dmg": 0, "spell_dmg": 0, "life_on_kill": 0, "cdr": 0, "life": 0, "mana": 0,
		"atk_dmg": 0, "ally_dmg": 0, "ally_life": 0, "energy": 0,
	}
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
	var a := Data.ascendancy(asc)
	if not a.is_empty():
		for n in a.minors:
			for k in n.stats:
				st[k] = st.get(k, 0) + n.stats[k] * asc_rank(n.id)
		for k in asc_cores:
			if k != "":
				effects[k] = true
	st.dmg_min += st.flat_dmg
	st.dmg_max += st.flat_dmg
	var tl := talents
	st.max_life += st.life + tl.vitality * 20
	st.max_mana += st.mana + tl.spirit * 12
	st.mana_regen += tl.spirit * 0.5
	st.life_regen += atlas.val("ward") if atlas else 0.0
	st.inc_dmg += tl.might * 8
	st.move_spd += tl.swift * 3
	st.atk_spd += tl.swift * 3
	st.crit += tl.precision * 1.5
	st.crit_multi += tl.precision * 8
	if effects.has("chant_power"):
		st.spell_dmg += st.cast_spd
	st.move_speed = 8.5 * (1.0 + st.move_spd / 100.0)
	st.attack_rate = st.aps * (1.0 + st.atk_spd / 100.0)
	st.dr = minf(0.75, st.armor / (st.armor + 60.0 + L * 10.0))
	st.cdr = mini(40, st.cdr)
	s = st
	life = s.max_life if full else s.max_life * old_l
	mana = s.max_mana if full else s.max_mana * old_m


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


func low_life() -> bool:
	return effects.has("deathline") and life <= s.max_life * 0.5


## attacks per second right now, with the core talents' temporary boosts
func attack_rate_now() -> float:
	return s.aps * (1.0 + (s.atk_spd + buff("fervor") * 2 + (20 if low_life() else 0) + tstat("atk_spd")) / 100.0)


func cast_speed_now() -> float:
	return 1.0 + (s.cast_spd + buff("spell_frenzy") * 5 + tstat("cast_spd")) / 100.0


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
