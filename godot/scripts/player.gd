class_name Player
extends Actor

var level := 1
var xp := 0
var life := 100.0
var mana := 60.0
var s := {}                 # derived stats
var cds := {}
var action_t := 0.0
var swing_t := 0.0
var invuln := 0.0
var aim := 0.0
var dash := {}
var dead := false
var potions := 3
var potion_prog := 0
var torch: OmniLight3D
var act_left := 0.0          # time the current one-shot animation still owns the body
# inventory
const BAG_SIZE := 30
const MAX_POTIONS := 5
var equip := {}              # slot -> item
var bag: Array = []
var cur := {}                # currency key -> count
var effects := {}            # legendary effects granted by gear


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
	torch = OmniLight3D.new()
	torch.position = Vector3(0, 3.2, 0)
	torch.omni_range = 15.0
	torch.light_energy = 2.2
	torch.shadow_enabled = true
	add_child(torch)
	recalc(true)


## derived stats from level and gear
func recalc(full := false) -> void:
	var L := level
	var old_l: float = life / s.max_life if s else 1.0
	var old_m: float = mana / s.max_mana if s else 1.0
	var st := {
		"max_life": 90.0 + L * 12, "max_mana": 60.0 + L * 5, "life_regen": 1.5 + L * 0.25, "mana_regen": 5.0 + L * 0.3,
		"dmg_min": 2.0 + L, "dmg_max": 4.0 + L * 2, "aps": 1.3, "crit": 5.0, "crit_multi": 150.0,
		"inc_dmg": 0, "flat_dmg": 0, "atk_spd": 0, "cast_spd": 0, "move_spd": 0, "armor": 0, "fire_dmg": 0, "cold_dmg": 0,
		"light_dmg": 0, "spell_dmg": 0, "life_on_kill": 0, "cdr": 0, "life": 0, "mana": 0,
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
	st.dmg_min += st.flat_dmg
	st.dmg_max += st.flat_dmg
	st.max_life += st.life
	st.max_mana += st.mana
	st.move_speed = 8.5 * (1.0 + st.move_spd / 100.0)
	st.attack_rate = st.aps * (1.0 + st.atk_spd / 100.0)
	st.dr = minf(0.75, st.armor / (st.armor + 60.0 + L * 10.0))
	st.cdr = mini(40, st.cdr)
	s = st
	life = s.max_life if full else s.max_life * old_l
	mana = s.max_mana if full else s.max_mana * old_m


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
