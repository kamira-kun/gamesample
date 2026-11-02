extends Node3D
## Game root: builds the dungeon, runs the combat loop and drives the camera.
## Logic works on the flat grid (Vector2 = ground x/z); nodes only mirror it.

const T := Dungeon.T
const CAM_PITCH := 0.96      # ~55 degrees above the ground
const CAM_YAW := PI / 4.0
const CAM_DIST := 36.0

var map: Dungeon
var floor_level := 1
var theme: Dictionary
var player: Player
var pet: Pet
var enemies: Array[Enemy] = []
var projs: Array = []        # player projectiles
var eprojs: Array = []       # enemy projectiles
var teles: Array = []        # telegraphed circles that resolve after a delay
var hazards: Array = []      # burning ground
var storms: Array = []       # thunder clouds
var zones: Array = []        # ticking areas from skill effect blocks
var proj_spawn: Array = []   # projectiles made while the list is being walked; joined after
var minions: Array[Ally] = []
var totems: Array[Ally] = []
var no_sup := Data.build_sup("", [])
var sup := no_sup            # support modifiers of the skill being resolved right now
var texts: Array = []        # floating damage numbers, drawn by the HUD
var ground: Array = []       # items lying on the floor
var drops: Array = []        # currency lying on the floor
var save_t := 0.0
var smoke := false
var portal: Dictionary = {}
var atlas := Atlas.new()
var area: Dictionary = Data.HIDEOUT   # current atlas node, or the hideout
var run_mods: Array = []
var mod_fx := Atlas.effects([])
var shop := {}
var interacts: Array = []   # hideout objects and dormant altars: {kind, name, pos, r}
var altars: Array = []      # cinder altars in this map (see Farm)
var boss: Enemy = null
var flow_t := 0.0
var time := 0.0
var shake := 0.0
var level_root: Node3D
var cam: Camera3D
var cam_target := Vector3.ZERO
var hud: Hud
var mouse_ground := Vector2.ZERO
var lmb := false      # a left click that reached the world (for clicking the merchant, the altars...)
var pressed := {}     # actions (and "cancel" for Esc) pressed this frame
var held := {}        # actions held down since a press that reached the world
var oom_t := -10.0
var held_prev := []         # skill keys held last frame: auras toggle on a fresh press only
var force_crit := false     # "three strikes": the attack being resolved always crits


func _ready() -> void:
	randomize()
	_setup_environment()
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.far = 300.0
	add_child(cam)
	player = Player.new()
	player.atlas = atlas
	add_child(player)
	pet = Pet.new()
	add_child(pet)
	hud = Hud.new()
	hud.main = self
	add_child(hud)
	var args := Array(OS.get_cmdline_user_args())
	# dev runs: `--smoke` plays a scripted test, `--view=<panel>` opens a panel, `--view=colossus|witch` a boss fight or `--view=imp` a few imps; neither touches the save
	smoke = "--smoke" in args or args.any(func(x): return x.begins_with("--view="))
	for x in args:
		if x.begins_with("--date="):   # dev runs: pretend it is another day, to test a season ending
			Data.date_override = x.trim_prefix("--date=")
	if smoke:
		Keybinds.reset()
		hud.keyconfig_ui.save_path = ""
	else:
		Keybinds.load_file()
	var notes := [] if smoke else Profiles.load_all()
	if smoke:
		Profiles.data = Profiles.fresh()
	# the base class comes from the profile; a new character (and a `--class=<k>` view) gets its starting kit
	var cls_arg := ""
	for x in args:
		if x.begins_with("--class="):
			cls_arg = x.trim_prefix("--class=")
	player.set_class(cls_arg if cls_arg != "" else str(Profiles.current().get("cls", Data.DEFAULT_CLASS)), not smoke or cls_arg != "")
	var loaded := false if smoke else load_game()
	passives_changed()
	enter_hideout()
	if not smoke and Profiles.current().is_empty():
		hud.char_ui.open(notes)
	elif loaded:
		hud.message("%s（%s）を読み込みました" % [Profiles.current().name, Profiles.league_name(league())], Color("#e8d8b0"))
		var got := Profiles.take_stash_cur(league(), player.cur)
		if got > 0:
			hud.message("スタッシュに戻っていた通貨 %d 個を受け取った" % got, Color("#e8d8b0"))
		market_notes()   # left over if the game closed before they were shown
	else:
		hud.message("%sで移動、%sで斬撃、%sでファイアボール" % [move_keys(), Keybinds.text("skill_1"), Keybinds.text("skill_2")], Color("#e8d8b0"))
	hud.message("　".join(PackedStringArray(PANEL_ACTIONS.map(func(a): return "%s：%s" % [Keybinds.text(a), Keybinds.action(a).name]))), Color("#b8a888"))
	for x in args:
		if x.begins_with("--view="):
			var kind: String = x.trim_prefix("--view=")
			if kind == "exchange":   # a few market days in, with an order out and a limit sell being set up
				player.cur.ember = 2000
				player.cur.chaos = 40
				player.cur.divine = 9
				for i in 64:
					Market.tick(league(), {})
				Market.place_limit(league(), "divine", "sell", Market.price(league(), "divine") * 1.1, 6, player.cur)
				Market.take_notes(league())
				hud.exchange_ui.side = "sell"
				hud.exchange_ui.mode = "limit"
			if kind == "chars":   # the character screen over a few sample characters, one of each base class
				for c in [["ミナ", "ashblade", "blade", 24], ["ルカ", "sigil", "storm", 31], ["ソラ", "lantern", "", 7]]:
					var ch := Profiles.add_char(c[0], Profiles.STANDARD, c[1])
					ch.data = {"level": c[3], "asc": c[2]}
				hud.char_ui.open([])
				if cls_arg != "":
					hud.char_ui.pick_class(cls_arg)
			if kind in ["merchant", "device", "stash", "exchange"]:
				open_interact(kind)
			if kind == "exchange":
				hud.exchange_ui.select("divine")
			elif kind == "skills":
				player.level = 6
				player.gems.append_array(["multi", "totem"])
				player.links[1] = ["totem", "multi"]
				hud.skill_ui.open_slot(1)
			elif kind in ["talents", "status", "filter", "passives", "ascend", "ascend_pick"]:
				player.talent_pts = 3
				atlas.cleared = ["ash", "bone"]
				if kind == "ascend":
					player.level = 14
					if cls_arg == "":
						player.set_class("sigil")
					player.asc = "storm"
					player.asc_ranks = {"storm_elem": 3, "storm_sight": 2, "storm_step": 1}
					player.asc_cores = ["shock", "crit_arc", ""]
					player.recalc(true)
				hud.toggle({"talents": hud.talent_ui, "status": hud.status_ui, "filter": hud.filter_ui, "passives": hud.passive_ui,
					"ascend": hud.asc_ui, "ascend_pick": hud.asc_ui}[kind])
			elif kind in ["colossus", "witch"]:   # a boss next to the player
				enter_map("ash")
				var b := _make_enemy(kind, player.pos + Vector2(5, -5), 999)
				b.sync_node(0.0, false)
			elif kind == "imp":   # a few imps and the fox right next to the player
				enter_map("ash")
				for i in 3:
					_make_enemy("imp", player.pos + Vector2(2.5 + i * 1.2, -2.5 + i * 0.8), 999)
			elif kind.begins_with("keys"):   # key config: `keys_swap` just after a swap, `keys_dup` with a duplicate from a hand-edited file
				if kind == "keys_dup":
					Keybinds.binds.potion[1] = {"key": KEY_Q}
					Keybinds.apply()
				hud.toggle(hud.keyconfig_ui)
				if kind == "keys_swap":
					hud.keyconfig_ui.bind_to("skill_3", 0, {"key": KEY_F})
				elif kind == "keys":
					hud.keyconfig_ui.listen("skill_4", 0)
			elif kind.begins_with("altar") or kind == "forge":
				_view_altar(kind)
			elif kind.begins_with("aura"):   # auras on the bar: `aura0` none on, `aura` three on and a fourth refused, `aura_off` one switched off again
				enter_map("ash")
				player.invuln = 1e9
				player.level = 14
				player.slots = ["slash", "ember_heart", "frost_veil", "gale_hymn", "crimson_pact", "hearth_ward"]
				player.recalc(true)
				get_tree().create_timer(3.0).timeout.connect(func():   # a moment in, so the messages are still up for a screenshot
					if kind != "aura0":
						for i in [1, 2, 3, 4, 5]:
							player.action_t = 0.0
							_try_cast(i)
					if kind == "aura_off":
						player.action_t = 0.0
						_try_cast(1))
	for x in args:
		if x.begins_with("--shot="):   # dev runs: save what the window shows a few seconds in, then quit
			get_tree().create_timer(4.5).timeout.connect(func():
				get_viewport().get_texture().get_image().save_png(x.trim_prefix("--shot="))
				get_tree().quit())
	if "--smoke" in args:
		_smoke_test()


## base classes: three ascendancies each, every ascendancy in exactly one class, the starting kit, only the
## class's own lineages can be taken, and characters from before classes get one from their ascendancy
func _smoke_classes() -> void:
	var p := player
	var keep := [p.level, p.equip, p.slots, p.links, p.gems]
	var owned := {}
	for bc in Data.CLASSES:
		for k in bc.ascs:
			owned[k] = owned.get(k, 0) + 1
	print("SMOKE classes n=%d per=%s ascs=%d each_once=%s" % [Data.CLASSES.size(), Data.CLASSES.map(func(c): return c.ascs.size()),
		Data.ASCENDANCIES.size(), Data.ASCENDANCIES.all(func(a): return owned.get(a.k, 0) == 1)])
	# every core's stats and effects compute
	var cores_ok := true
	for a in Data.ASCENDANCIES:
		p.set_class(Data.class_of_asc(a.k))
		p.asc = a.k
		for i in a.cores.size():
			for c in a.cores[i]:
				p.asc_cores = ["", "", ""]
				p.asc_cores[i] = c.id
				p.recalc(true)
				cores_ok = cores_ok and p.effects.has(c.id) and p.s.max_life > 0 and p.s.max_mana > 0
	p.asc = ""
	p.asc_cores = ["", "", ""]
	var kits := []
	for bc in Data.CLASSES:
		p.set_class(bc.k, true)
		kits.append("%s:%s/%s/life%d/mana%d" % [bc.k, p.equip.weapon.base, p.slots[0], p.s.max_life, p.s.max_mana])
	print("SMOKE classes kits=%s cores_ok=%s" % [kits, cores_ok])
	# the ascendancy screen offers only the class's three and refuses another class's
	p.set_class("lantern")
	p.level = 4
	hud.toggle(hud.asc_ui)
	hud.asc_ui._choose("pyre")
	var refused := p.asc == ""
	hud.asc_ui._choose("shade")
	print("SMOKE classes restrict refused_other=%s took=%s offered=%s" % [refused, p.asc, Data.class_ascs(p.cls).map(func(a): return a.k)])
	hud.close_panels()
	# a save whose ascendancy is not the class's own comes back without it
	var sd := save_data()
	sd.asc = "blade"
	apply_save(sd)
	print("SMOKE classes load_foreign asc='%s' cls=%s" % [p.asc, p.cls])
	p.asc = ""
	p.asc_ranks = {}
	# migration: old characters get the class of their ascendancy, else the default; seasons keep it
	var d := Profiles.fresh()
	Profiles.data = d
	var sid: String = Data.SEASONS[0].id
	var olds := []
	for asc in ["necro", "storm", "bulwark", ""]:
		var c := Profiles.add_char("old_" + asc, sid if asc == "storm" else Profiles.STANDARD)
		c.erase("cls")
		c.data = {"level": 12, "asc": asc}
		olds.append(c)
	var odd := Profiles.add_char("odd", Profiles.STANDARD, "sigil")
	odd.data = {"asc": "shade"}   # hand-edited: the ascendancy decides
	var bad := Profiles.add_char("bad", Profiles.STANDARD, "nope")
	var file = JSON.parse_string(JSON.stringify(d))
	Profiles.normalize(file)
	print("SMOKE classes migrate=%s odd=%s bad=%s" % [file.chars.slice(0, 4).map(func(c): return c.cls), file.chars[4].cls, file.chars[5].cls])
	Profiles.migrate(file, Data.SEASONS[0].end)
	var moved: Dictionary = file.chars[1]
	print("SMOKE classes season_end league=%s from=%s cls=%s" % [moved.league, moved.from_season, moved.cls])
	Profiles.data = Profiles.fresh()
	p.level = keep[0]
	p.equip = keep[1]
	p.slots = keep[2]
	p.links = keep[3]
	p.gems = keep[4]
	p.set_class(Data.DEFAULT_CLASS)


## season leagues and the stash, on an in-memory profile file (the real one is never touched)
func _smoke_seasons() -> void:
	var p := player
	var sid: String = Data.SEASONS[0].id
	var d := Profiles.fresh()
	Profiles.data = d
	var sc := Profiles.add_char("s", sid)
	Profiles.add_char("n", Profiles.STANDARD)
	Profiles.stash_tabs(sid)[0].items.append(Items.generate(3, 1.0, 1))
	Profiles.stash_tabs(Profiles.STANDARD)
	var running := Profiles.migrate(d, Data.SEASONS[0].start)
	print("SMOKE season running moved=%d league=%s" % [running.size(), sc.league])
	var notes := Profiles.migrate(d, Data.SEASONS[0].end)
	print("SMOKE season ended notes=%d league=%s from=%s std_tabs=%d season_stash=%s" % [notes.size(), sc.league, sc.from_season,
		d.stash[Profiles.STANDARD].size(), d.stash.has(sid)])
	Profiles.data = Profiles.fresh()
	hud.toggle(hud.stash_ui)
	p.bag.append(Items.generate(3, 1.0, 1))
	var n := p.bag.size()
	hud.stash_ui._put(0)
	var put: int = Profiles.stash_tabs(Profiles.STANDARD)[0].items.size()
	hud.stash_ui._take(0)
	print("SMOKE stash put=%d back=%s open=%s" % [put, p.bag.size() == n, hud.stash_ui.visible])
	hud.close_panels()


## key config: rebinding through the panel, a duplicate swapped (and one detected), the HUD labels,
## a real key press reaching the rebound action, and a save/load round trip through a scratch file
func _smoke_keys() -> void:
	Keybinds.reset()
	var ui: KeyconfigUI = hud.keyconfig_ui
	hud.toggle(ui)
	ui.listen("inventory", 0)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_J
	ev.pressed = true
	ui._input(ev)
	print("SMOKE keys rebound=%s text='%s' inputmap=%s" % [Keybinds.binds.inventory[0] == {"key": KEY_J}, Keybinds.text("inventory"),
		ev.is_action_pressed("inventory")])
	ui.listen("skill_4", 0)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_MIDDLE
	mb.pressed = true
	ui._input(mb)
	print("SMOKE keys mouse=%s short='%s'" % [Keybinds.text("skill_4"), Keybinds.short("skill_4")])
	# F is the potion's: binding it to slot 3 swaps, so the potion takes Q and no duplicate is left
	var lost := Keybinds.assign("skill_3", 0, {"key": KEY_F})
	print("SMOKE keys swap lost=%s potion='%s' skill_3='%s' conflicts=%d" % [lost, Keybinds.text("potion"), Keybinds.text("skill_3"),
		Keybinds.conflicts().size()])
	Keybinds.binds.talents[1] = {"key": KEY_J}   # as a hand-edited file could have it
	Keybinds.apply()
	print("SMOKE keys duplicate detected=%s flagged=%s" % [Keybinds.conflicts().size() == 1, Keybinds.conflicted("inventory", 0)])
	Keybinds.assign("talents", 1, {})
	hud.close_panels()
	hud.refresh()
	hud.pause_ui.refresh()
	print("SMOKE keys hud potion='%s' slot3='%s' tip=%s pause=%s" % [hud.potion.text, Keybinds.short("skill_3"),
		hud.skill_ui.skill_tip(player.slots[2], 2)[1][0].contains("F"), hud.pause_ui.controls.get_child(1).text.begins_with("Q：回復薬")])
	# a real J press now opens the inventory; I no longer does
	for k in [KEY_I, KEY_J]:
		var press := InputEventKey.new()
		press.physical_keycode = k
		press.pressed = true
		Input.parse_input_event(press)
		await get_tree().process_frame
		await get_tree().process_frame
		var up := press.duplicate()
		up.pressed = false
		Input.parse_input_event(up)
		print("SMOKE keys press %s inventory_open=%s" % [OS.get_keycode_string(k), hud.inventory.visible])
	hud.close_panels()
	# save, scramble, load: the same bindings come back (an unknown action and a junk entry are ignored)
	var path := "user://smoke_keys.cfg"
	var before := Keybinds.binds.duplicate(true)
	Keybinds.save(path)
	var cf := ConfigFile.new()
	cf.load(path)
	cf.set_value("keys", "no_such_action", [{"key": KEY_Z}, {}])
	cf.set_value("keys", "filter", "junk")
	cf.save(path)
	Keybinds.reset()
	Keybinds.load_file(path)
	var ev2 := InputEventKey.new()
	ev2.physical_keycode = KEY_F
	print("SMOKE keys saved roundtrip=%s inputmap=%s filter='%s'" % [Keybinds.binds == before, ev2.is_action("skill_3"), Keybinds.text("filter")])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	ui.open_close()
	ui.bind_to("potion", 0, {"key": KEY_G})
	ui.reset.pressed.emit()
	print("SMOKE keys reset=%s potion='%s'" % [Keybinds.binds == Keybinds.defaults(), Keybinds.text("potion")])
	hud.close_panels()


## auras: toggling, reservation and its cap, stacking and refusal, gems that change the reservation,
## allies inside the reach, the HUD orbs and a save round trip
func _smoke_auras() -> void:
	var p := player
	var keep_slots := p.slots.duplicate()
	var keep_links := p.links.duplicate(true)
	var keep_level := p.level
	p.auras.clear()
	p.level = 14
	p.slots = ["slash", "ember_heart", "frost_veil", "gale_hymn", "crimson_pact", "hearth_ward"]
	p.links = [[], [], [], [], [], []]
	p.recalc(true)
	var toggle := func(i: int):
		p.action_t = 0.0
		_try_cast(i)
	var mx: float = p.s.max_mana
	var dmg0 := p.bonus("dmg")
	toggle.call(1)
	await get_tree().create_timer(0.2).timeout
	print("SMOKE aura on=%s reserved=%d cap=%d/%d mana_capped=%s dmg+%.0f ring=%s" % [p.auras, p.reserved("mana"), p.cap("mana"), mx,
		p.mana <= p.cap("mana"), p.bonus("dmg") - dmg0, p.aura_fx != null and p.aura_fx.get_child_count() == 1])
	toggle.call(1)
	print("SMOKE aura off=%s reserved=%d cap=%d" % [p.auras, p.reserved("mana"), p.cap("mana")])
	# stack three mana auras (80% of the pool); the flat 30 of the fourth would pass the max and is refused
	for i in [1, 2, 3, 5]:
		toggle.call(i)
	print("SMOKE aura stack on=%s reserved=%d/%d refused=%s" % [p.auras, p.reserved("mana"), mx, not "hearth_ward" in p.auras])
	toggle.call(4)
	print("SMOKE aura life on=%s reserved_life=%d cap_life=%d/%d life_capped=%s" % ["crimson_pact" in p.auras, p.reserved("life"), p.cap("life"),
		p.s.max_life, p.life <= p.cap("life")])
	# 効率化 shrinks the flat 30 enough to fit; unlinking it again switches off the aura that no longer fits
	p.links[5] = ["efficient"]
	var cut := p.aura_reserve("hearth_ward", "mana")
	toggle.call(5)
	print("SMOKE aura gem reserve=%d on=%s total=%d/%d" % [cut, "hearth_ward" in p.auras, p.reserved("mana"), mx])
	p.links[5] = []
	var off := p.fix_auras()
	print("SMOKE aura overflow off=%s left=%d" % [off, p.auras.size()])
	# an ally inside the reach shares the auras, one far away does not
	var near := Ally.new()
	near.pos = p.pos + Vector2(2, 0)
	var far := Ally.new()
	far.pos = p.pos + Vector2(30, 0)
	print("SMOKE aura allies near=%s far=%s dr=%.0f" % [in_aura(near), in_aura(far), p.astat("dr")])
	near.free()
	far.free()
	hud.refresh()
	await get_tree().process_frame
	print("SMOKE aura hud mana_reserve=%.2f text='%s' life_reserve=%.2f text='%s'" % [hud.mana_orb.reserve, hud.mana_orb.text,
		hud.life_orb.reserve, hud.life_orb.reserve_text])
	# save round trip: the auras that were on come back on, with the same reservation
	var held := [p.reserved("life"), p.reserved("mana")]
	var on := p.auras.duplicate()
	var data = JSON.parse_string(JSON.stringify(save_data()))
	p.auras.clear()
	p.recalc(true)
	apply_save(data)
	print("SMOKE aura save restored=%s same=%s mana_capped=%s life_capped=%s" % [p.auras == on, held == [p.reserved("life"), p.reserved("mana")],
		p.mana <= p.cap("mana"), p.life <= p.cap("life")])
	p.auras.clear()
	p.slots = keep_slots
	p.links = keep_links
	p.level = keep_level
	p.recalc(true)


## the currency exchange, on an in-memory profile file (docs/economy-design.md section 9)
func _smoke_market() -> void:
	var sid: String = Data.SEASONS[0].id
	var d := Profiles.fresh()
	Profiles.data = d
	var std := Profiles.STANDARD
	var w := {}
	for i in 300:
		Market.tick(sid, w)
		Market.tick(std, w)
	var inside := true
	for lg in [sid, std]:
		for k in Market.keys():
			var pr := Market.price(lg, k)
			inside = inside and pr >= Market.floor_price(k) - 1e-6 and pr <= Market.ceil_price(k) + 1e-6
	print("SMOKE market drift ticks=%d in_range=%s hist=%d" % [Market.state(sid).tick, inside, Market.history(sid, "whet", 60).size()])
	var ev := Market.events(sid)
	print("SMOKE market events n=%d same=%s std=%d" % [ev.size(), ev == Market.events(sid), Market.events(std).size()])
	w = {"chaos": 100, "ember": 1000}
	var err := Market.market_trade(std, "whet", "buy", 20, w)
	var got: int = w.get("whet", 0)
	var err2 := Market.market_trade(std, "whet", "sell", got, w)
	print("SMOKE market roundtrip ok=%s chaos=%d lost=%s whet=%d" % [err == "" and err2 == "", w.chaos, w.chaos < 100, w.get("whet", 0)])
	w = {"chaos": 0, "ember": 1000, "divine": 10}
	var lim := Market.price(std, "divine") * 1.05
	var est := Market.limit_estimate(std, "divine", "sell", lim, 10)
	err = Market.place_limit(std, "divine", "sell", lim, 10, w)
	var held: int = w.divine
	for i in 30:
		Market.state(std).prices.divine = lim / 1.05   # hold the price so the test does not hang on luck
		Market.tick(std, w)
	var notes := Market.take_notes(std)
	print("SMOKE market limit ok=%s held=%d chaos=%d notes=%d orders=%d est_ticks=%d" % [err == "", held, w.chaos, notes.size(),
		Market.orders(std).size(), est.ticks])
	w = {"chaos": 50, "ember": 1000, "whet": 5}
	Market.place_limit(sid, "whet", "sell", Market.price(sid, "whet") * 3.0, 5, w)
	Market.place_limit(sid, "whet", "buy", Market.price(sid, "whet") * 0.3, 10, w)
	var mig := Profiles.migrate(d, Data.SEASONS[0].end)
	var sc := Profiles.stash_cur(std)
	print("SMOKE market season end notes=%d market_gone=%s std_whet=%d std_chaos=%d" % [mig.size(), not d.market.has(sid),
		sc.get("whet", 0), sc.get("chaos", 0)])
	var into := {}
	Profiles.take_stash_cur(std, into)
	print("SMOKE market stash taken whet=%d left=%d" % [into.get("whet", 0), Profiles.stash_cur(std).size()])
	Profiles.data = Profiles.fresh()


## the merchant's currency prices follow the exchange, and the exchange screen trades (docs/economy-design.md sections 4 and 7)
func _smoke_exchange() -> void:
	var p := player
	var lg := league()
	var chaos_cost := Items.currency_price(Data.currency("chaos"), lg)
	var whet_ok := Items.currency_price(Data.currency("whet"), lg) == roundi(Market.price(lg, "whet") * 250 * Items.discount)
	var d0 := Items.discount
	Items.discount = 0.9
	var haggled := Items.currency_price(Data.currency("chaos"), lg)
	Items.discount = d0
	print("SMOKE merchant chaos=%d want=%d haggled=%d whet_ok=%s" % [chaos_cost, roundi(250 * d0), haggled, whet_ok])
	p.cur.ember = 2000
	p.cur.chaos = 30
	p.cur.whet = 0
	open_interact("exchange")
	await get_tree().create_timer(0.3).timeout
	var ex := hud.exchange_ui
	print("SMOKE exchange open=%s rows=%d board=%d orders_box=%d" % [ex.visible, ex.price_grid.get_child_count() / 4 - 1,
		ex.board_box.get_child_count(), ex.order_box.get_child_count()])
	ex.select("whet")
	ex.side = "buy"
	ex.mode = "market"
	ex.qty.value = 3
	var quoted := Market.quote(lg, "whet", "buy", 3)
	ex.execute()
	print("SMOKE exchange market buy whet=%d chaos=%d paid=%d err='%s'" % [p.cur.whet, p.cur.chaos, 30 - p.cur.chaos, ex.error.text])
	print("SMOKE exchange quote_matches=%s" % (30 - p.cur.chaos == quoted.chaos))
	ex.qty.value = 500
	ex.execute()
	print("SMOKE exchange refused err=%s whet=%d" % [ex.error.text != "", p.cur.whet])
	ex.side = "sell"
	ex.mode = "limit"
	ex.qty.value = 2
	ex.limit.value = snappedf(Market.price(lg, "whet") * 1.1, 0.01)
	ex.refresh()
	var est_lines := ex.est_box.get_children().map(func(l): return l.text)
	ex.execute()
	var orders := Market.orders(lg)
	print("SMOKE exchange limit placed=%d whet=%d rows=%d est=%s" % [orders.size(), p.cur.whet, ex.order_box.get_child_count(),
		est_lines.any(func(t): return "ティックで成立しそう" in t)])
	ex.cancel(orders[0].id if orders.size() > 0 else -1)
	print("SMOKE exchange cancelled orders=%d whet=%d" % [Market.orders(lg).size(), p.cur.whet])
	hud.close_panels()
	Market.state(lg).pending.append("テスト通知")
	var msgs0 := hud.messages.get_child_count()
	market_notes()
	print("SMOKE exchange notes shown=%s left=%d" % [hud.messages.get_child_count() > msgs0 or msgs0 >= 5, Market.state(lg).pending.size()])


## `--view=altar` a dormant altar beside the player, `altar_vow` its vow panel, `altar_wave` kindled with a vow
## and fighting, `altar_reward` every wave cleared and the reward on the ground, `forge` the hideout forge with crystals
func _view_altar(kind: String) -> void:
	var f := Farm.state(league())
	f.renown = Farm.rank_need(4)
	if kind == "forge":
		f.cinder = 180
		player.pos = interacts[4].pos + Vector2(0, 3)
		open_interact("forge")
		return
	enter_map("ash")
	player.invuln = 1e9
	var a := place_altar(_free_spot(player.pos, 5.0))
	if kind == "altar_vow":
		open_interact("altar", {"altar": a})
	elif kind != "altar":
		await get_tree().create_timer(1.0).timeout
		kindle_altar(a, "fury")
		while kind == "altar_reward" and a.state == "active":
			await get_tree().create_timer(0.3).timeout
			for e in a.spawned:
				if is_instance_valid(e) and not e.dead:
					hit_enemy(e, {"dmg": 999999, "crit": false, "type": "fire"})


## a free spot about `d` away from `c` that the player can see
func _free_spot(c: Vector2, d: float) -> Vector2:
	for k in 32:
		var at := c + Vector2.from_angle(k * TAU / 32.0 - PI / 2) * (d + k / 8)
		if not map.circle_hits(at, 1.6) and map.los(c, at):
			return at
	return c


## cinder altars: placement and beacons, kindling with a vow, the waves and the guardian, the reward,
## a trial running out, the forge, and the league split with the season-end handover (an in-memory profile file)
func _smoke_farm() -> void:
	var p := player
	p.invuln = 1e9
	Profiles.data = Profiles.fresh()
	var f := Farm.state(league())
	enter_map("ash")
	var placed := altars.size()
	var dormant := interacts.filter(func(o): return o.kind == "altar").size()
	var on_floor := altars.all(func(a): return not map.solid_at(a.pos + Vector2(1.6, 0)) or not map.solid_at(a.pos - Vector2(1.6, 0)))
	f.beacons = 1
	enter_map("ash")
	print("SMOKE farm placed=%d labels=%d floor=%s beacon_map=%d beacons_left=%d" % [placed, dormant, on_floor, altars.size(), f.beacons])
	# a locked vow is refused; 烈火の誓約 kindles the first altar
	var a: Dictionary = altars[0]
	p.pos = map.move_circle(a.pos + Vector2(0, 2.0), p.r, Vector2.ZERO)
	open_interact("altar", {"altar": a})
	hud.cinder_ui.choose("trial")
	var refused: bool = a.state == "dormant" and hud.cinder_ui.visible
	hud.cinder_ui.choose("fury")
	var first: int = a.spawned.size()
	var boosted: bool = a.spawned.all(func(e): return e.aggro and e.has_meta("cinder"))
	print("SMOKE farm kindle refused=%s state=%s panel_closed=%s wave=%d first=%d planned=%d boosted=%s label_gone=%s" % [refused, a.state,
		not hud.cinder_ui.visible, a.wave, first, a.plan.waves[0], boosted, not interacts.any(func(o): return o.get("altar") == a)])
	var guards := 0
	for i in 120:
		if a.state != "active":
			break
		for e in a.spawned:
			if is_instance_valid(e) and not e.dead:
				guards += 1 if e.display_name == "燼魂の守り手" else 0
				hit_enemy(e, {"dmg": 999999, "crit": false, "type": "phys"})
		await get_tree().create_timer(0.1).timeout
	var reward: Dictionary = a.get("reward", {})
	var crystals: int = drops.filter(func(d): return d.k == Farm.KEY).map(func(d): return d.n).reduce(func(x, y): return x + y, 0)
	print("SMOKE farm waves=%d/%d killed=%d guards=%d state=%s renown=%d lit=%d rank=%d on_ground=%d reward=%d" % [a.wave,
		a.plan.waves.size(), a.spawned.size(), guards, a.state, f.renown, f.lit, Farm.rank(f), crystals, reward.get("cinder", -1)])
	p.pos = a.pos + Vector2(0, 2.0)
	_collect_nearby(60.0)
	print("SMOKE farm collected cinder=%d char_cur_clean=%s status='%s'" % [f.cinder, not p.cur.has(Farm.KEY), altar_status()])
	# 灼刻の誓約 opens at rank 2; running out of time leaves the altar cold and pays nothing
	if altars.size() < 2:
		place_altar(_free_spot(p.pos, 6.0))
	f.renown = Farm.rank_need(2)
	var b: Dictionary = altars[1]
	kindle_altar(b, "trial")
	var r0: int = f.renown
	b.t = Farm.TRIAL_TIME + 1.0
	await get_tree().create_timer(0.2).timeout
	print("SMOKE farm trial state=%s renown_same=%s status='%s'" % [b.state, f.renown == r0, altar_status()])
	for e in b.spawned:
		hit_enemy(e, {"dmg": 999999, "crit": false, "type": "phys"})
	# the forge in the hideout: crystals buy loot, gated by renown
	enter_hideout()
	f.cinder = 200
	f.renown = 0
	var bag0 := p.bag.size()
	open_interact("forge")
	hud.cinder_ui.buy("rare")
	var after_rare: int = f.cinder
	hud.cinder_ui.buy("legend")
	var refused_legend: String = hud.cinder_ui.error.text
	f.renown = Farm.rank_need(4)
	hud.cinder_ui.buy("legend")
	hud.cinder_ui.buy("beacon")
	var legends := p.bag.slice(bag0).filter(func(it): return it.rarity == 3).size()
	print("SMOKE farm forge open=%s bag+%d cinder=%d->%d->%d locked='%s' legends=%d beacons=%d cards=%d" % [hud.cinder_ui.visible,
		p.bag.size() - bag0, 200, after_rare, f.cinder, refused_legend, legends, f.beacons, hud.cinder_ui.cards.get_child_count()])
	hud.close_panels()
	# leagues keep their own progress; a finished season hands its crystals and the higher renown to standard
	var sid: String = Data.SEASONS[0].id
	var sf := Farm.state(sid)
	var split: bool = sf.cinder == 0 and sf.renown == 0
	sf.cinder = 70
	sf.renown = Farm.rank_need(6)
	sf.beacons = 2
	var d = JSON.parse_string(JSON.stringify(Profiles.data))
	Profiles.normalize(d)
	var round_trip: bool = d.farm[sid].cinder == 70 and typeof(d.farm[sid].cinder) == TYPE_INT
	var std0: int = f.cinder
	var notes := Profiles.migrate(Profiles.data, Data.SEASONS[0].end)
	var std := Farm.state(Profiles.STANDARD)
	print("SMOKE farm leagues split=%s json=%s season_end cinder=%d->%d rank=%d beacons=%d season_gone=%s note=%s" % [split, round_trip,
		std0, std.cinder, Farm.rank(std), std.beacons, not Profiles.data.farm.has(sid), notes.any(func(t): return "燼晶" in t)])
	Profiles.data = Profiles.fresh()


## automated run used during development: `godot -- --smoke`
func _smoke_test() -> void:
	var p := player
	p.invuln = 1e9
	# hideout: merchant and atlas
	print("SMOKE hideout=%s interacts=%d stock=%d" % [in_hideout(), interacts.size(), shop.items.size()])
	await get_tree().create_timer(0.5).timeout
	p.cur.ember = 2000
	open_interact("merchant")
	await get_tree().create_timer(0.3).timeout
	var pots := p.potions
	hud.shop_ui._buy(shop.items[0])
	hud.shop_ui._buy_potion()
	hud.shop_ui._buy_currency("chaos", Items.currency_price(Data.currency("chaos"), league()))
	print("SMOKE bought bag=%d stock=%d potions+%d chaos=%d ember=%d" % [p.bag.size(), shop.items.size(), p.potions - pots, p.cur.chaos, p.cur.ember])
	hud.shop_ui._buy_gem("leech")
	print("SMOKE shop gem gems=%s" % [p.gems])
	hud.shop_ui._sell(0)
	print("SMOKE shop sold bag=%d" % p.bag.size())
	hud.close_panels()
	await _smoke_exchange()
	_smoke_seasons()
	_smoke_classes()
	_smoke_market()
	await _smoke_keys()
	open_interact("device")
	await get_tree().create_timer(0.4).timeout
	enter_map("wail")
	print("SMOKE locked map ignored=%s" % in_hideout())
	enter_map("ash")
	print("SMOKE entered=%s level=%d atlas_open=%s" % [area.id, floor_level, hud.atlas_ui.visible])
	var e: Enemy = enemies.filter(func(q): return not q.boss)[0]
	p.pos = map.move_circle(e.pos + Vector2(-4, -4), p.r, Vector2.ZERO)
	await get_tree().create_timer(0.3).timeout
	mouse_ground = e.pos
	p.level = 10
	p.recalc(true)
	p.gems = Data.SUPPORTS.map(func(g): return g.id)
	for id in Data.SKILL_ORDER:
		p.slots[0] = id
		p.action_t = 0.0
		p.cds.clear()
		p.mana = p.s.max_mana
		_try_cast(0)
		await get_tree().create_timer(0.4).timeout
	print("SMOKE skills minions=%d storms=%d hazards=%d auras=%s" % [minions.size(), storms.size(), hazards.size(), p.auras])
	await _smoke_auras()
	# effect-block skills with supports that change projectiles, repeat the cast or set traps
	p.links[0] = ["fork", "pchain", "echo"]
	for id in ["firebolt", "frost_axe", "fire_rain", "hex_frail", "tailwind", "spirit_wolves"]:
		p.slots[0] = id
		p.action_t = 0.0
		p.mana = p.s.max_mana
		_try_cast(0)
		await get_tree().create_timer(0.35).timeout
	print("SMOKE fx zones=%d projs=%d minions=%d buffs=%s sup0=%s" % [zones.size(), projs.size(), minions.size(), p.tbuffs.keys(), slot_sup(0).ids])
	p.slots[0] = "ice_shards"
	p.links[0] = ["trap"]
	p.action_t = 0.0
	_try_cast(0)
	print("SMOKE trap placed=%d" % totems.filter(func(t): return t.trap).size())
	p.links[0] = []
	p.invuln = 1e9
	p.invuln = 1e9   # the dash cast above replaced it
	# a fireball totem with extra projectiles, and the skill panel swapping slots
	p.slots[1] = "fireball"
	p.links[1] = ["totem", "multi", "power"]
	p.action_t = 0.0
	p.mana = p.s.max_mana
	_try_cast(1)
	print("SMOKE totem totems=%d sup=%s cost=%d" % [totems.size(), slot_sup(1).ids, slot_cost(1)])
	await get_tree().create_timer(1.0).timeout
	print("SMOKE totem fired projs=%d" % projs.size())
	hud.skill_ui.open_slot(0)
	hud.skill_ui._assign("fireball")
	hud.skill_ui._toggle_gem("multi")
	print("SMOKE panel slot0=%s slot1=%s links0=%s" % [p.slots[0], p.slots[1], p.links[0]])
	hud.close_panels()
	p.slots = Data.DEFAULT_SLOTS.duplicate()
	p.links = [[], [], [], [], [], []]
	# support gem energy: 2 + level shared by the bar, at most 6 links a skill, linking past the pool is refused
	print("SMOKE energy max=%d base=%d used=%d link_max=%d" % [p.energy_max(), Data.energy_base(p.level), p.energy_used(), Data.LINK_MAX])
	hud.skill_ui.open_slot(0)
	for gid in ["leech", "frostbite", "mleech", "loh", "hexhit", "cull", "efficient"]:   # 7 one-energy gems
		hud.skill_ui._toggle_gem(gid)
	hud.skill_ui.open_slot(1)
	for gid in ["power", "haste", "heavy"]:   # 3 each: the third one is past the pool
		hud.skill_ui._toggle_gem(gid)
	print("SMOKE energy links0=%d links1=%s used=%d/%d" % [p.links[0].size(), p.links[1], p.energy_used(), p.energy_max()])
	hud.skill_ui._toggle_gem("power")
	hud.skill_ui._toggle_gem("leech")
	print("SMOKE energy unlink links1=%s used=%d" % [p.links[1], p.energy_used()])
	hud.skill_ui._toggle_gem("leech")
	hud.skill_ui._toggle_gem("power")
	# the pool shrinks: links power up in bar order and those past it go dark
	p.level = 5
	p.recalc()
	print("SMOKE energy shrunk max=%d active0=%d active1=%s sup1=%s" % [p.energy_max(), p.active_links(0).size(), p.active_links(1), slot_sup(1).ids])
	p.level = 10
	p.recalc()
	print("SMOKE energy restored active1=%s sup1=%s" % [p.active_links(1), slot_sup(1).ids])
	hud.close_panels()
	p.links = [[], [], [], [], [], []]
	# every support gem changes some skill it fits
	var unused := Data.SUPPORTS.filter(func(g): return not Data.SKILL_ORDER.any(func(id): return g.id in Data.build_sup(id, [g.id]).ids))
	print("SMOKE supports=%d skills=%d unused=%s" % [Data.SUPPORTS.size(), Data.SKILL_ORDER.size(), unused.map(func(g): return g.id)])
	# talents, the loot filter and the pet
	p.talent_pts = 2
	var dmg0: int = p.s.inc_dmg
	hud.toggle(hud.talent_ui)
	hud.talent_ui._spend("might")
	hud.talent_ui._spend("fireball")
	print("SMOKE talents pts=%d inc_dmg+%d fireball=%d" % [p.talent_pts, p.s.inc_dmg - dmg0, p.talents.fireball])
	# ascendancy: pick the fire lineage, open two core tiers, then start over
	p.set_class("sigil")
	hud.toggle(hud.asc_ui)
	var fire0: int = p.s.fire_dmg
	var cost0 := slot_cost(1)
	hud.asc_ui._choose("pyre")
	for id in ["pyre_heat", "pyre_heat", "pyre_chant", "pyre_chant", "pyre_heat", "pyre_mantle"]:
		hud.asc_ui._rank_up(id)
	hud.asc_ui._pick_core(0, "fire_cost")
	hud.asc_ui._pick_core(1, "kill_burst")
	hud.asc_ui._pick_core(2, "inferno")
	print("SMOKE ascend free=%d fire+%d cores=%s cost %d->%d" % [p.asc_free(), p.s.fire_dmg - fire0, p.asc_cores, cost0, slot_cost(1)])
	# a second lineage is refused while one is held; at Lv16 the third core tier opens
	hud.asc_ui._choose(Data.ASCENDANCIES[1].k)
	var aoe0: float = slot_sup(1).aoe
	p.level = 16
	for id in ["pyre_heat", "pyre_chant", "pyre_mantle", "pyre_mantle"]:   # pyre_heat is already at its max
		hud.asc_ui._rank_up(id)
	hud.asc_ui._pick_core(2, "inferno")
	print("SMOKE ascend lv16 asc=%s ranks=%s cores=%s fire_aoe x%.2f" % [p.asc, p.asc_ranks, p.asc_cores, slot_sup(1).aoe / aoe0])
	p.level = 10
	var em_asc: int = p.cur.ember
	hud.asc_ui._reset()
	hud.asc_ui._reset()
	print("SMOKE ascend reset asc='%s' free=%d cores=%s ember-%d" % [p.asc, p.asc_free(), p.asc_cores, em_asc - p.cur.ember])
	hud.close_panels()
	hud.toggle(hud.filter_ui)
	hud.filter_ui._set_rarity(0, "hide")
	hud.filter_ui._set_rarity(1, "sell")
	hud.filter_ui._set_rarity(3, "sell")
	var em0: int = p.cur.ember
	var g0 := ground.size()
	drop_item(Items.generate(3, 0.0, 0), p.pos)
	print("SMOKE filter hidden ground+%d ember+%d legend_pending=%s" % [ground.size() - g0, p.cur.ember - em0, p.filter.rarity[3]])
	var bag0 := p.bag.size()
	pickup_item(Items.generate(3, 0.0, 1), p.pos)
	print("SMOKE filter autosell bag+%d" % (p.bag.size() - bag0))
	hud.close_panels()
	p.filter = Player.default_filter()
	var fetch := map.move_circle(p.pos, 0.2, Vector2(6, 0))
	_drop_currency("chaos", 1, fetch)
	var chaos0: int = p.cur.chaos
	await get_tree().create_timer(2.0).timeout
	print("SMOKE pet fetched=%s pet_dist=%.1f" % [p.cur.chaos > chaos0, pet.pos.distance_to(p.pos)])
	hud.toggle(hud.status_ui)
	await get_tree().create_timer(0.2).timeout
	print("SMOKE status open=%s rows=%d" % [hud.status_ui.visible, hud.status_ui.stats.get_child_count()])
	hud.toggle(hud.pause_ui)
	print("SMOKE pause open=%s status_closed=%s" % [hud.pause_ui.visible, not hud.status_ui.visible])
	hud.close_panels()
	await get_tree().create_timer(1.0).timeout
	var killed_before := enemies.size()
	if boss:   # a totem or minion left from the tests above may already have finished it
		hit_enemy(boss, {"dmg": 999999, "crit": false, "type": "phys"})
	print("SMOKE enemies=%d level=%d portal=%s" % [killed_before, p.level, not portal.is_empty()])
	p.pos = portal.pos
	await get_tree().create_timer(0.3).timeout
	print("SMOKE completed hideout=%s cleared=%s bone_unlocked=%s wail_unlocked=%s" % [in_hideout(), atlas.cleared, atlas.is_unlocked(Data.atlas_node("bone")), atlas.is_unlocked(Data.atlas_node("wail"))])
	hud.toggle(hud.passive_ui)
	hud.passive_ui._rank_up("find")   # locked until 黄金の嗅覚 has a rank
	hud.passive_ui._rank_up("gold")
	hud.passive_ui._rank_up("flask")  # no points left
	print("SMOKE passives free=%d gold=%d find=%d flask=%d gold_fx=%.2f" % [atlas.points_free(), atlas.rank("gold"), atlas.rank("find"), atlas.rank("flask"), atlas.map_effects([]).gold])
	hud.close_panels()
	atlas.mods["wail"] = ["life", "swarm"]
	enter_map("wail")
	print("SMOKE wail level=%d mods=%s enemies=%d rarity=%.2f" % [floor_level, run_mods, enemies.size(), mod_fx.rarity])
	# the colossus and the witch go through their moves
	for kind in ["colossus", "witch"]:
		var spot := p.pos
		for k in 32:
			var at := p.pos + Vector2.from_angle(k * TAU / 32.0) * (9.0 + k / 8)
			if not map.circle_hits(at, 2.2) and map.los(p.pos, at):
				spot = at
				break
		var b := _make_enemy(kind, spot, 999)
		b.aggro = true
		var chill := 0.0
		var shots := 0
		for i in 8:
			b.act_t = 0.0
			b.atk_cd = 9.0
			for k in 10:
				await get_tree().create_timer(0.1).timeout
				chill = maxf(chill, p.chill)
				shots = maxi(shots, eprojs.size())
		if kind == "colossus":
			await get_tree().create_timer(1.0).timeout
			var hz0 := hazards.size()
			b.windup = 0.0
			b.act_t = 9.0
			b.charge = {"dir": (p.pos - b.pos).normalized(), "left": 8.0, "hit": false, "trail": 0.0}
			await get_tree().create_timer(0.6).timeout
			print("SMOKE charge done=%s trail+%d" % [b.charge.is_empty(), hazards.size() - hz0])
		b.life = b.max_life * 0.4
		for k in 30:
			if b.enraged:
				break
			await get_tree().create_timer(0.1).timeout
		print("SMOKE %s alive=%s enraged=%s max_shots=%d max_chill=%.1f" % [kind, not b.dead, b.enraged, shots, chill])
		hit_enemy(b, {"dmg": 999999, "crit": false, "type": "phys"})
		await get_tree().create_timer(0.3).timeout
	p.invuln = 0.0
	damage_player(1e9)
	await get_tree().create_timer(1.2).timeout
	print("SMOKE dead=%s death_screen=%s" % [p.dead, hud.death.visible])
	retry_floor()
	hud.death.visible = false
	print("SMOKE retry dead=%s life=%d" % [p.dead, p.life])
	# loot, inventory, crafting and save round trip
	for i in 3:
		drop_item(Items.generate(3, 1.0, 1), p.pos)
	_drop_currency("chaos", 2, p.pos)
	_drop_currency("ember", 50, p.pos)
	await get_tree().create_timer(0.6).timeout
	for g in ground.duplicate():
		p.pos = g.pos
		await get_tree().create_timer(0.1).timeout
	print("SMOKE bag=%d chaos=%d ember=%d ground=%d" % [p.bag.size(), p.cur.chaos, p.cur.ember, ground.size()])
	hud.toggle_inventory()
	var mi := p.bag.find(p.bag.filter(func(x): return x.rarity == 1)[0])
	var before: Dictionary = p.bag[mi].mods.duplicate()
	hud.inventory._pick_currency("chaos")
	hud.inventory._on_bag_click(mi)
	print("SMOKE chaos rerolled=%s left=%d" % [before != p.bag[mi].mods or p.bag[mi].mods.size() != before.size(), p.cur.chaos])
	hud.inventory._cancel_craft()
	var slot: String = p.bag[0].slot
	hud.inventory._on_bag_click(0)
	print("SMOKE equipped=%s life=%d" % [p.equip.has(slot), p.s.max_life])
	var e0: int = p.cur.ember
	hud.inventory._on_bag_right(0)
	print("SMOKE sold ember+%d" % (p.cur.ember - e0))
	var it := Items.generate(5, 2.0, 2)
	var back := Items.normalize(JSON.parse_string(JSON.stringify(it)))
	print("SMOKE json roundtrip=%s" % (back == it))
	await get_tree().create_timer(0.5).timeout
	hud.toggle_inventory()
	await _smoke_farm()
	get_tree().quit()


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.012, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.46, 0.52)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.6, 0.85)
	moon.light_energy = 0.18
	moon.rotation = Vector3(deg_to_rad(-65), deg_to_rad(25), 0)
	add_child(moon)


# =================== input ===================
const PANEL_ACTIONS := ["inventory", "skills", "talents", "ascendancy", "status", "filter", "passives", "keyconfig"]


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		lmb = e.pressed
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_ESCAPE:
		pressed["cancel"] = true
		return
	for a in Keybinds.ids():
		if e.is_action_pressed(a):
			pressed[a] = true
			held[a] = true


## the four movement bindings for messages, e.g. "WASD" ("W/A/S/D" when they aren't single letters)
func move_keys() -> String:
	var k := ["move_up", "move_left", "move_down", "move_right"].map(func(a): return Keybinds.short(a))
	return "".join(PackedStringArray(k)) if k.all(func(x): return x.length() == 1) else "/".join(PackedStringArray(k))


func _update_mouse() -> void:
	var mp := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	if absf(dir.y) > 0.001:
		var hit := from + dir * (-from.y / dir.y)
		mouse_ground = Vector2(hit.x, hit.z)


static func to3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


# =================== level ===================
## clear the world and drop the player at the new map's start room
func _reset_world(new_map: Dungeon, new_theme: Dictionary) -> void:
	if level_root:
		level_root.queue_free()
	for list in [projs, proj_spawn, eprojs, teles, hazards, storms, zones, texts, ground, drops, interacts, altars]:
		list.clear()
	enemies.clear()
	minions.clear()
	totems.clear()
	portal = {}
	boss = null
	level_root = Node3D.new()
	add_child(level_root)
	map = new_map
	theme = new_theme
	LevelBuilder.build(map, theme, level_root)
	player.pos = map.tile_center(map.start.cx, map.start.cy)
	player.dead = false
	player.dash = {}
	player.recalc(true)
	player.chill = 0.0
	player.torch.light_color = theme.torch
	_place_pet()
	cam_target = to3(player.pos)
	hud.set_boss(null)
	hud.close_panels()


func in_hideout() -> bool:
	return area.get("hideout", false)


func spawn_floor() -> void:
	_reset_world(Dungeon.new(72, 72, floor_level), Data.THEMES[atlas.node_theme(area)])
	_spawn_enemies()
	_place_altars()
	hud.message("%s — エリアレベル %d" % [area.name, floor_level], Color("#e8d8b0"))
	for k in run_mods:
		hud.message("◆ " + Data.map_mod(k).name, Color("#ff9a7a"))
	if altars.size() > 0:
		hud.message("燼火の祭壇が %d つ眠っている" % altars.size(), Farm.COLOR)
	save_game()


# =================== hideout and atlas ===================
## a safe hall between runs: the only place with the merchant, and where maps are chosen
func enter_hideout() -> void:
	area = Data.HIDEOUT
	floor_level = atlas.hideout_level()
	run_mods = []
	mod_fx = atlas.map_effects([])
	_reset_world(Dungeon.new(28, 26, 1, "hideout"), Data.HIDEOUT_THEME)
	var r := map.start
	var c := map.tile_center(r.cx, r.cy)
	player.pos = c + Vector2(0, 3 * T)
	cam_target = to3(player.pos)
	_place_pet()
	_dress_hideout(r)
	interacts.append({"kind": "device", "name": "遠征図の祭壇", "pos": c + Vector2(0, -2.5 * T), "r": 1.6})
	interacts.append({"kind": "merchant", "name": "商人", "pos": c + Vector2(-4 * T, 0), "r": 1.0})
	interacts.append({"kind": "stash", "name": "スタッシュ", "pos": map.tile_center(r.x + r.w - 1, r.y + 6), "r": 1.0})
	interacts.append({"kind": "exchange", "name": "取引所", "pos": map.tile_center(r.x + 3, r.y), "r": 1.2})
	interacts.append({"kind": "forge", "name": "燼火の炉", "pos": c + Vector2(4 * T, 0), "r": 1.2})
	_build_device(interacts[0].pos)
	_build_altar(interacts[4].pos, true)
	var merchant := Actor.new()
	merchant.pos = interacts[1].pos
	merchant.face = 0.0
	level_root.add_child(merchant)
	merchant.use_rig(Assets.ADVENTURERS + "Rogue_Hooded.glb", 1.0)
	merchant.sync_node(0.0, false)
	merchant.play("Idle")
	for o in interacts:
		var t := Vector2i(floori(o.pos.x / T), floori(o.pos.y / T))
		map.blocked[map.idx(t.x, t.y)] = 1
	if shop.is_empty() or shop.level != floor_level:
		shop = Items.gen_shop(floor_level)
	hud.message("隠れ家 — 遠征図の祭壇で行き先を選ぼう", Color("#e8d8b0"))
	save_game()


## furniture along the hideout walls (blocking their tiles) and braziers in the corners
func _dress_hideout(r: Dictionary) -> void:
	var decor := [["table_long_decorated_A", r.x + 3, r.y, 0.0], ["shelf_large", r.x + r.w - 4, r.y, 0.0],
		["chest_gold", r.x + r.w - 1, r.y + 6, -PI / 2], ["barrel_large_decorated", r.x + r.w - 1, r.y + r.h - 1, 0.0],
		["crates_stacked", r.x, r.y + r.h - 1, 0.5], ["keg_decorated", r.x, r.y + 2, PI / 2], ["table_small_decorated_A", r.x + 2, r.cy, 0.0]]
	for d in decor:
		var node := Assets.piece(d[0])
		node.position = to3(map.tile_center(d[1], d[2]))
		node.rotation.y = d[3]
		level_root.add_child(node)
		map.blocked[map.idx(d[1], d[2])] = 1
	for corner in [Vector2i(r.x + 1, r.y + 1), Vector2i(r.x + r.w - 2, r.y + 1), Vector2i(r.x + 1, r.y + r.h - 2), Vector2i(r.x + r.w - 2, r.y + r.h - 2)]:
		var at := map.tile_center(corner.x, corner.y)
		var torch := Assets.piece("torch_lit")
		torch.position = to3(at)
		torch.scale = Vector3.ONE * 1.6
		level_root.add_child(torch)
		var light := OmniLight3D.new()
		light.light_color = Color("#ffb070")
		light.light_energy = 1.8
		light.omni_range = 9.0
		light.position = to3(at, 2.2)
		level_root.add_child(light)
		map.blocked[map.idx(corner.x, corner.y)] = 1


## the atlas device: a stone plinth with a floating, slowly turning ring
func _build_device(at: Vector2) -> void:
	var root := Node3D.new()
	root.position = to3(at)
	level_root.add_child(root)
	var plinth := CylinderMesh.new()
	plinth.top_radius = 1.1
	plinth.bottom_radius = 1.4
	plinth.height = 0.6
	Fx.mesh(root, plinth, Fx.mat(Color("#4a4038")), Vector3(0, 0.3, 0))
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.75
	ring_mesh.outer_radius = 0.9
	var ring := Fx.mesh(root, ring_mesh, Fx.mat(Color("#ffc870"), 4.0, true), Vector3(0, 2.0, 0))
	ring.rotation.x = PI / 2
	var orb := Fx.mesh(root, Fx.sphere(0.3), Fx.mat(Color("#ffe0a0"), 6.0, true), Vector3(0, 2.0, 0))
	var light := OmniLight3D.new()
	light.light_color = Color("#ffc070")
	light.light_energy = 2.5
	light.omni_range = 8.0
	light.position.y = 2.0
	root.add_child(light)
	var tw := ring.create_tween().set_loops()
	tw.tween_property(ring, "rotation:y", TAU, 6.0).as_relative()
	var bob := orb.create_tween().set_loops()
	bob.tween_property(orb, "position:y", 2.3, 1.2).set_trans(Tween.TRANS_SINE)
	bob.tween_property(orb, "position:y", 1.9, 1.2).set_trans(Tween.TRANS_SINE)


## click (or press B) near the merchant or the atlas device; returns true when one opened
func _update_interact() -> bool:
	for o in interacts:
		var near: bool = player.pos.distance_to(o.pos) < 4.0 and pressed.has("interact")
		var clicked: bool = lmb and mouse_ground.distance_to(o.pos) < o.r + 0.6 and player.pos.distance_to(o.pos) < 14.0
		if not near and not clicked:
			continue
		lmb = false
		for a in held.keys():   # the click opened something: it doesn't also cast the skill on that button
			if Keybinds.binds[a].any(func(b): return b.get("mouse", -1) == MOUSE_BUTTON_LEFT):
				held.erase(a)
		open_interact(o.kind, o)
		return true
	return false


func open_interact(kind: String, o := {}) -> void:
	if kind == "merchant":
		hud.shop_ui.open_close()
	elif kind == "stash":
		hud.stash_ui.open_close()
	elif kind == "exchange":
		hud.exchange_ui.open_close()
	elif kind == "forge":
		hud.cinder_ui.open_forge()
	elif kind == "altar":
		hud.cinder_ui.open_altar(o.altar)
	else:
		hud.atlas_ui.open_close()


func enter_map(id: String) -> void:
	var n := Data.atlas_node(id)
	if n.is_empty() or not atlas.is_unlocked(n):
		return
	area = n
	floor_level = atlas.node_level(n)
	run_mods = atlas.node_mods(n).duplicate()
	mod_fx = atlas.map_effects(run_mods)
	spawn_floor()


func complete_map() -> void:
	var n := area
	var was_cleared := atlas.is_cleared(n)
	if not was_cleared:
		atlas.cleared.append(n.id)
	var newly: Array = n.links.filter(func(id): return not atlas.is_cleared(Data.atlas_node(id))).map(func(id): return Data.atlas_node(id).name)
	if n.get("endless", false):
		atlas.abyss += 1
	atlas.mods.erase(n.id)
	shop = {}   # the merchant restocks after every run
	Market.tick(league(), player.cur)   # one market tick per map completed
	enter_hideout()
	hud.message("%s を踏破した！" % n.name, Color("#ffd36a"))
	market_notes()
	if not newly.is_empty():
		hud.message("新たな地点が開放：%s" % "、".join(newly), Color("#e8d8b0"))
	if n.get("endless", false):
		hud.message("残り火の深淵が Lv %d に深まった" % atlas.node_level(n), Color("#b48cff"))


## what the exchange did while the player was away (fills, expired orders, the notice board), once each
func market_notes() -> void:
	for line in Market.take_notes(league()):
		hud.message(line, Color("#c070ff"))


func abandon_map() -> void:
	enter_hideout()
	hud.message("隠れ家に帰還した", Color("#e8d8b0"))


func _spawn_enemies() -> void:
	var f := floor_level
	var pool := [{"k": "imp", "w": 3.0}, {"k": "ghoul", "w": 4.0}, {"k": "archer", "w": 2.0},
		{"k": "brute", "w": 1.5 if f >= 2 else 0.4}, {"k": "shaman", "w": 1.5 if f >= 2 else 0.5}]
	var pack_id := 0
	for room in map.rooms:
		if room == map.start:
			continue
		pack_id += 1
		if room == map.boss_room:
			var bt: Dictionary = Data.BOSS_ROTATION[atlas.node_theme(area)]
			boss = _make_enemy(bt.type, map.tile_center(room.cx, room.cy), pack_id)
			boss.max_life *= 1.0 + 0.12 * (f - 1)
			boss.life = boss.max_life
			for g in bt.guards:
				_make_enemy(g, map.random_floor_in(room), pack_id)
			continue
		var packs := clampi(roundi(room.w * room.h / 25.0 * mod_fx.swarm), 2, 7)
		for k in packs:
			pack_id += 1
			_spawn_pack(map.random_floor_in(room), pack_id, roundi((randi_range(4, 8) + f / 2) * mod_fx.swarm), pool)
	# ambush packs scattered through the corridors, away from the entrance and the boss
	var br: Dictionary = map.boss_room
	var placed := 0
	for tries in 300:
		if placed >= 6 + f / 2:
			break
		var tx := randi_range(1, map.w - 2)
		var ty := randi_range(1, map.h - 2)
		if map.is_wall(tx, ty):
			continue
		var c := map.tile_center(tx, ty)
		if c.distance_to(player.pos) < 28.0:
			continue
		if tx >= br.x - 2 and tx < br.x + br.w + 2 and ty >= br.y - 2 and ty < br.y + br.h + 2:
			continue
		pack_id += 1
		_spawn_pack(c, pack_id, randi_range(3, 5), [{"k": "imp", "w": 2.0}, {"k": "ghoul", "w": 2.0}, {"k": "archer", "w": 1.0}])
		placed += 1


static func _weighted(list: Array) -> Dictionary:
	var total := 0.0
	for e in list:
		total += e.w
	var roll := randf() * total
	for e in list:
		roll -= e.w
		if roll <= 0.0:
			return e
	return list[-1]


func _spawn_pack(c: Vector2, pack_id: int, n: int, pool: Array) -> void:
	var main_kind: String = _weighted(pool).k
	if randf() < (0.13 + floor_level * 0.01) * mod_fx.elite:
		_make_enemy(main_kind, c, pack_id, Data.ELITE_AFFIXES.pick_random())
	for i in n:
		var kind: String = main_kind if randf() < 0.7 else _weighted(pool).k
		var at := c + Vector2(randf_range(-2.5, 2.5), randf_range(-2.5, 2.5))
		if map.circle_hits(at, Data.ENEMY_TYPES[kind].r):
			at = c
		_make_enemy(kind, at, pack_id)


func _make_enemy(kind: String, at: Vector2, pack_id: int, affix: Dictionary = {}) -> Enemy:
	var e := Enemy.new()
	level_root.add_child(e)
	e.setup(kind, at, floor_level, pack_id, affix)
	e.max_life *= mod_fx.life
	e.life = e.max_life
	e.dmg *= mod_fx.dmg
	e.speed *= mod_fx.speed
	e.sync_node(0.0, false)
	enemies.append(e)
	return e


# =================== main loop ===================
func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_update_mouse()
	for a in PANEL_ACTIONS:
		if pressed.has(a):
			hud.toggle(hud.panel_for(a))
	if pressed.has("cancel"):
		if hud.any_open():
			hud.close_panels()
		elif not player.dead and not hud.char_ui.visible:
			hud.pause_ui.open_close()
	if not hud.blocking() and not player.dead:
		_update_interact()
	if not hud.blocking():
		time += delta
		_update_player(delta)
		_update_pet(delta)
		_update_minions(delta)
		_update_totems(delta)
		flow_t -= delta
		if flow_t <= 0.0:
			flow_t = 0.25
			map.compute_flow(player.pos)
		for e in enemies:
			var d2 := e.pos.distance_squared_to(player.pos)
			if not e.dead and d2 < 60.0 * 60.0:
				_update_enemy(e, delta)
			if not e.dead:
				e.animate(delta, e.aggro and e.windup <= 0.0 and e.frozen <= 0.0, d2 < 45.0 * 45.0)
		_separate_enemies()
		_remove_dead()
		_update_projectiles(delta)
		_update_eprojs(delta)
		_update_teles(delta)
		_update_hazards(delta)
		_update_storms(delta)
		_update_zones(delta)
		_update_loot(delta)
		_update_portal(delta)
		_update_altars(delta)
		save_t += delta
		if save_t > 20.0 and not player.dead:
			save_t = 0.0
			save_game()
		for tx in texts:
			tx.t += delta
			tx.z += delta * 1.6
		texts = texts.filter(func(tx): return tx.t < 0.9)
	_update_camera(delta)
	hud.refresh()
	pressed.clear()
	lmb = lmb and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	for a in held.keys():   # releases can land on the UI, so ask the Input state
		if not Input.is_action_pressed(a):
			held.erase(a)


func _update_camera(delta: float) -> void:
	cam_target = cam_target.lerp(to3(player.pos), minf(1.0, delta * 8.0))
	var off := Vector3(cos(CAM_PITCH) * sin(CAM_YAW), sin(CAM_PITCH), cos(CAM_PITCH) * cos(CAM_YAW)) * CAM_DIST
	var jitter := Vector3(randf_range(-shake, shake), 0, randf_range(-shake, shake)) * 0.04
	cam.position = cam_target + off + jitter
	cam.look_at(cam_target + jitter, Vector3.UP)
	shake = maxf(0.0, shake - delta * 30.0)


func _remove_dead() -> void:
	for e in enemies:
		if e.dead:
			e.die()
	enemies = enemies.filter(func(e): return not e.dead)


# =================== player ===================
func _update_player(delta: float) -> void:
	var p := player
	if p.dead:
		p.animate(delta, false)
		return
	var s := p.s
	for id in p.fix_auras():
		hud.message("「%s」が解除された（リザーブが足りない）" % Data.SKILLS[id].name, Color("#ff9a80"))
	p.life = minf(p.cap("life"), p.life + (s.life_regen + s.max_life * p.bonus("regen") / 100.0) * delta)
	p.mana = minf(p.cap("mana"), p.mana + s.mana_regen * delta)
	p.update_aura_fx(delta)
	for k in p.cds.keys():
		p.cds[k] -= delta
	p.tick_buffs(delta)
	p.action_t -= delta
	p.swing_t -= delta
	p.invuln -= delta
	p.chill -= delta
	p.frosted = p.chill > 0.0
	p.aim = (mouse_ground - p.pos).angle()
	if not p.dash.is_empty():
		_update_dash(delta)
		p.animate(delta, true)
		return

	var mv := Vector2.ZERO
	if Input.is_action_pressed("move_up"): mv.y -= 1
	if Input.is_action_pressed("move_down"): mv.y += 1
	if Input.is_action_pressed("move_left"): mv.x -= 1
	if Input.is_action_pressed("move_right"): mv.x += 1
	var moving := mv != Vector2.ZERO
	if moving:
		# keys move along the screen axes; turn that into a ground direction via the camera
		var fwd := -cam.global_transform.basis.z
		var right := cam.global_transform.basis.x
		fwd.y = 0
		right.y = 0
		var d3 := (right.normalized() * mv.x - fwd.normalized() * mv.y).normalized()
		var sp: float = s.move_speed * (1.0 + p.bonus("move") / 100.0) * (0.5 if p.action_t > 0.0 else 1.0) * (0.6 if p.chill > 0.0 else 1.0)
		p.pos = map.move_circle(p.pos, p.r, Vector2(d3.x, d3.z) * sp * delta)
	var down := range(Data.SLOT_COUNT).map(func(i): return held.has(Keybinds.skill_action(i)))
	for i in down.size():
		var aura: bool = Data.SKILLS[p.slots[i]].has("aura")
		if down[i] and not (aura and i < held_prev.size() and held_prev[i]):
			_try_cast(i)
	held_prev = down
	if pressed.has("potion"): _use_potion()
	p.animate(delta, moving)


func _use_potion() -> void:
	var p := player
	if p.potions <= 0:
		hud.message("回復薬がない", Color("#ff8080"))
		return
	if p.life >= p.cap("life"):
		return
	p.potions -= 1
	var heal: float = p.s.max_life * 0.5
	p.life = minf(p.cap("life"), p.life + heal)
	Fx.burst(level_root, to3(p.pos, 1.0), 20, Color("#ff5a5a"), 4.0)
	add_text(p.pos, "+%d" % heal, Color("#66ff66"), 20)


func damage_player(amount: float) -> void:
	var p := player
	if p.dead or p.invuln > 0.0:
		return
	var d := maxi(1, roundi(amount * (1.0 - p.s.dr) * (0.85 if p.effects.has("iron_stance") else 1.0) * (1.0 - p.bonus("dr") / 100.0)
		* (1.0 - p.s.dr_pct / 100.0)))
	p.life -= d
	p.hit_t = 0.15
	add_text(p.pos, str(d), Color("#ff5050"), 18)
	shake = maxf(shake, 4.0)
	hud.flash()
	if p.effects.has("nova_on_hit") and randf() < 0.2:
		_cast_nova(_player_caster(), true)
	if p.life <= 0.0:
		p.life = 0.0
		p.dead = true
		Fx.burst(level_root, to3(p.pos, 1.0), 40, Color("#a01010"), 5.0)
		get_tree().create_timer(0.9).timeout.connect(hud.show_death)


func retry_floor() -> void:
	player.xp = int(player.xp * 0.7)
	if in_hideout():
		enter_hideout()
	else:
		spawn_floor()


func gain_xp(v: int) -> void:
	var p := player
	p.xp += v
	while p.xp >= Data.xp_need(p.level):
		p.xp -= Data.xp_need(p.level)
		p.level += 1
		p.talent_pts += 1
		p.recalc(true)
		add_text(p.pos, "LEVEL UP!", Color("#ffe27a"), 28)
		Fx.ring(level_root, to3(p.pos), 5.0, Color("#ffe27a"), 0.6, false)
		Fx.burst(level_root, to3(p.pos, 1.0), 40, Color("#ffe27a"), 6.0)
		hud.message("レベル %d に到達！ タレントポイント +1（%s）" % [p.level, Keybinds.text("talents")], Color("#ffe27a"))
		if Data.asc_points(p.level) > Data.asc_points(p.level - 1):
			hud.message("アセンダンシーポイント +1（%s）" % Keybinds.text("ascendancy"), Data.ascendancy(p.asc).get("color", Color("#ffcf7a")))
		hud.message("エネルギー上限 +1（%d）" % p.energy_max(), Data.GEM_COLOR)
		for id in Data.SKILL_ORDER:
			if Data.SKILLS[id].lvl == p.level:
				hud.message("新スキル「%s」を習得！（%sで付け替え）" % [Data.SKILLS[id].name, Keybinds.text("skills")], Data.SKILLS[id].color)
		hud.skill_ui.refresh()
		hud.talent_ui.refresh()
		hud.asc_ui.refresh()


# =================== combat ===================
func roll_damage(coef: float, type: String, spell := false) -> Dictionary:
	var s := player.s
	var d: float = randf_range(s.dmg_min, s.dmg_max) * coef
	if sup.conv != "" and (type == "phys" or sup.conv == "chaos"):
		type = sup.conv
	var elem: float = {"fire": s.fire_dmg, "cold": s.cold_dmg, "light": s.light_dmg, "chaos": s.chaos_dmg}.get(type, 0)
	var ally: bool = sup.totem > 0 or "minion" in Data.SKILLS.get(sup.skill, {}).get("tags", [])
	var inc: float = s.inc_dmg + (s.spell_dmg if spell else s.atk_dmg) + elem + (s.ally_dmg if ally else 0) + player.tstat("dmg")
	# auras reach the player's own skills everywhere, allies only while they stand inside them
	if not ally or sup.get("aura", false):
		inc += player.astat("dmg")
	if ally and player.effects.has("lich_lord"):
		inc += 50
	if player.low_life():
		inc += 40
	d *= (1.0 + inc / 100.0) * sup.dmg * sup.get("m_" + type, 1.0) * (1.0 + 0.15 * player.talents.get(sup.skill, 0))
	if sup.lowlife > 0.0 and player.life <= player.s.max_life * 0.5:
		d *= 1.0 + sup.lowlife
	var crit: bool = force_crit or (randf() * 100.0 < s.crit + sup.crit and not player.effects.has("no_crit"))
	if crit:
		d *= (s.crit_multi + sup.critm) / 100.0
	return {"dmg": maxi(1, roundi(d)), "crit": crit, "type": type, "spell": spell}


func hit_enemy(e: Enemy, hit: Dictionary, freeze := 0.0) -> void:
	if e.dead:
		return
	var fx := player.effects
	var mul := 1.0
	if fx.has("executioner") and e.life <= e.max_life * 0.35:
		mul += 0.8
	if e.shock > 0.0:
		mul += 0.2
	if fx.has("frostbite") and e.frozen > 0.0:
		mul += 0.25
	if sup.elite > 0.0 and (e.boss or not e.elite.is_empty()):
		mul += sup.elite
	if sup.close > 0.0 and e.pos.distance_to(player.pos) < 4.5:
		mul += sup.close
	if sup.vsfrozen > 0.0 and (e.frozen > 0.0 or e.slow > 0.0):
		mul += sup.vsfrozen
	if e.vuln_t > 0.0:
		mul += e.vuln + (0.3 if fx.has("hex_deep") else 0.0)
	if mul > 1.0:
		hit = hit.merged({"dmg": roundi(hit.dmg * mul)}, true)
	e.life -= hit.dmg
	e.hit_t = 0.12
	freeze = maxf(freeze, sup.freeze) * (1.5 if fx.has("frostbite") else 1.0)
	if sup.leech > 0.0:
		player.life = minf(player.cap("life"), player.life + hit.dmg * sup.leech)
	_asc_on_hit(e, hit)
	_sup_on_hit(e, hit)
	if not e.aggro:
		_alert_pack(e)
	add_text(e.pos, str(hit.dmg) + ("!" if hit.crit else ""), Color("#ffe040") if hit.crit else Data.DMG_COLORS[hit.type], 26 if hit.crit else 18)
	if freeze > 0.0:
		if e.boss:
			e.slow = maxf(e.slow, freeze)
		else:
			e.frozen = maxf(e.frozen, freeze)
	if e.life <= 0.0:
		_asc_on_kill(e, hit)
		_sup_on_kill(e, hit)
		_kill_enemy(e)


## support gems of the skill being resolved, on a hit landing
func _sup_on_hit(e: Enemy, hit: Dictionary) -> void:
	var p := player
	if sup.burn > 0.0 and randf() < sup.burn:
		_apply_burn(e, hit.dmg * 0.5 / 3.0)
	if sup.shock > 0.0 and randf() < sup.shock:
		e.shock = maxf(e.shock, 4.0)
	if sup.chill > 0.0:
		e.slow = maxf(e.slow, sup.chill)
	if sup.bleed > 0.0 and randf() < sup.bleed:
		e.bleed_dps = maxf(e.bleed_dps if e.bleed_t > 0.0 else 0.0, hit.dmg * 0.6 / 4.0)
		e.bleed_t = 4.0
	if sup.poison > 0.0 and randf() < sup.poison:
		# poison stacks: every new dose adds to what is still ticking
		e.poison_dps = (e.poison_dps if e.poison_t > 0.0 else 0.0) + hit.dmg * 0.3 / 3.0
		e.poison_t = 3.0
	if sup.stun > 0.0 and not e.boss and randf() < sup.stun:
		e.stun = maxf(e.stun, 0.4)
	if sup.hex > 0.0:
		e.vuln = maxf(e.vuln if e.vuln_t > 0.0 else 0.0, sup.hex)
		e.vuln_t = maxf(e.vuln_t, 3.0)
	if sup.mleech > 0.0:
		p.mana = minf(p.cap("mana"), p.mana + hit.dmg * sup.mleech)
	if sup.loh > 0.0:
		p.life = minf(p.cap("life"), p.life + sup.loh)
	if sup.knock > 0.0 and not e.boss:
		e.pos = map.move_circle(e.pos, e.r, (e.pos - p.pos).normalized() * sup.knock)
	if sup.cull > 0.0 and not e.boss and e.life > 0.0 and e.life <= e.max_life * sup.cull:
		e.life = 0.0
		add_text(e.pos, "処刑", Color("#ff6060"), 20)


## support gems of the skill being resolved, on an enemy dying from a hit
func _sup_on_kill(e: Enemy, hit: Dictionary) -> void:
	if sup.kboom > 0 and not hit.get("kb", false):
		var at := e.pos
		var s := sup
		var t: String = hit.type
		add_tele(at, 2.8, 0.15, false, func(): _with_sup(s, func():
			_explosion(at, 2.8, Data.DMG_COLORS[t])
			for o in enemies_in_radius(at, 2.8):
				hit_enemy(o, roll_damage(0.6, t, true).merged({"kb": true}, true))))


## a burn replaces a weaker one and refreshes a stronger one
func _apply_burn(e: Enemy, dps: float) -> void:
	if e.burn_t <= 0.0 or dps >= e.burn_dps:
		e.burn_dps = dps
	e.burn_t = 3.0


## core talents that react to a hit landing
func _asc_on_hit(e: Enemy, hit: Dictionary) -> void:
	var p := player
	var fx := p.effects
	var spell: bool = hit.get("spell", true)
	if not spell and fx.has("blood_oath"):
		p.life = minf(p.cap("life"), p.life + hit.dmg * 0.03)
	if not spell and fx.has("fervor"):
		p.add_buff("fervor", 15, 3.0)
	if not spell and fx.has("ember_edge"):
		_apply_burn(e, hit.dmg * 0.25 / 3.0)
	if hit.type == "chaos" and fx.has("soul_drain"):
		p.life = minf(p.cap("life"), p.life + hit.dmg * 0.05)
	# hexing cores mark the enemy as cursed for a while, without cutting short a stronger curse
	var mark := 0.0
	if spell and fx.has("hex_touch"):
		mark = 0.12
	if hit.crit and fx.has("shade_mark"):
		mark = 0.15
	if mark > 0.0 and (e.vuln_t <= 0.0 or e.vuln <= mark):
		e.vuln = mark
		e.vuln_t = 4.0
	if hit.type == "light" and fx.has("shock"):
		e.shock = 4.0
	if hit.type == "fire" and fx.has("ignite"):
		# 40% of the hit over 3 seconds; a weaker hit refreshes the burn without lowering it
		var dps: float = hit.dmg * 0.4 / 3.0
		if e.burn_t <= 0.0 or dps >= e.burn_dps:
			e.burn_dps = dps
		e.burn_t = 3.0
	if hit.crit and fx.has("crit_mana"):
		p.mana = minf(p.cap("mana"), p.mana + 4.0)
	if hit.crit and fx.has("crit_arc") and not hit.get("arc", false):
		var o: Enemy = null
		var bd := 9.0 * 9.0
		for q in enemies:
			var dq := q.pos.distance_squared_to(e.pos)
			if q != e and not q.dead and dq < bd:
				bd = dq
				o = q
		if o:
			Fx.bolt(level_root, to3(e.pos, 1.0), to3(o.pos, 1.0), Color("#d9c2ff"), 0.15)
			hit_enemy(o, {"dmg": maxi(1, roundi(hit.dmg * 0.5)), "crit": false, "type": "light", "spell": true, "arc": true})


## core talents that react to an enemy dying from a hit
func _asc_on_kill(e: Enemy, hit: Dictionary) -> void:
	var fx := player.effects
	if fx.has("spell_frenzy") and hit.get("spell", true):
		player.add_buff("spell_frenzy", 8, 4.0)
	if fx.has("rage_kill") and not hit.get("spell", true):
		player.add_buff("rage_kill", 5, 4.0)
	var at := e.pos
	var s := sup
	if fx.has("kill_burst") and hit.type == "fire" and not hit.get("burst", false):
		add_tele(at, 3.0, 0.15, false, func(): _with_sup(s, func():
			_explosion(at, 3.0, Color("#ff6e28"))
			for o in enemies_in_radius(at, 3.0):
				hit_enemy(o, roll_damage(0.8, "fire", true).merged({"burst": true}, true))))
	if fx.has("shatter") and e.frozen > 0.0 and not hit.get("shard", false):
		add_tele(at, 3.5, 0.15, false, func(): _with_sup(s, func():
			Fx.ring(level_root, to3(at), 3.5, Color("#aee8ff"), 0.35)
			Fx.burst(level_root, to3(at, 0.6), 24, Color("#d8f6ff"), 9.0, 0.4, 0.0)
			for o in enemies_in_radius(at, 3.5):
				hit_enemy(o, roll_damage(1.0, "cold", true).merged({"shard": true}, true), 1.2)))


func enemies_in_radius(c: Vector2, rad: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in enemies:
		if not e.dead and e.pos.distance_to(c) < rad + e.r:
			out.append(e)
	return out


func _kill_enemy(e: Enemy) -> void:
	e.dead = true
	var p := player
	gain_xp(roundi(e.xp * mod_fx.xp))
	p.life = minf(p.cap("life"), p.life + p.s.life_on_kill + (p.s.max_life * 0.03 if p.effects.has("kill_heal") else 0.0))
	_drop_loot(e)
	if p.effects.has("soul_feed"):
		for a in _allies():
			a.life = minf(a.max_life, a.life + a.max_life * 0.1)
	if e.has_meta("cinder") and randf() < 0.3:
		_drop_currency(Farm.KEY, randi_range(1, 2), e.pos)
	p.potion_prog += 1
	if p.potion_prog >= 14:
		p.potion_prog = 0
		if p.potions < p.max_potions():
			p.potions += 1
			add_text(p.pos, "回復薬 +1", Color("#ff7070"), 16)
	Fx.burst(level_root, to3(e.pos, 0.8), 60 if e.boss else 12, e.t.color, 8.0 if e.boss else 5.0)
	if e.elite.get("k", "") == "volatile":
		var at := e.pos
		var dmg := e.dmg * 1.5
		add_tele(at, 3.2, 0.8, true, func():
			_explosion(at, 3.2, Color("#ff7840"))
			_damage_area(at, 3.2, dmg))
	if e.boss:
		boss = null
		hud.set_boss(null)
		_open_portal(e.pos)
		hud.message("%sを討伐した！ ポータルで隠れ家に帰還できる" % e.display_name, Color("#ff9a4a"))


func _explosion(at: Vector2, rad: float, color: Color) -> void:
	Fx.ring(level_root, to3(at), rad, color, 0.35)
	Fx.burst(level_root, to3(at, 0.5), int(rad * 8), color, rad * 3.0)
	shake = maxf(shake, rad * 2.5)


func add_text(at: Vector2, text: String, color: Color, size := 18) -> void:
	texts.append({"pos": to3(at + Vector2(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4)), 1.8), "str": text, "color": color, "size": size, "t": 0.0, "z": 0.0})


func add_tele(at: Vector2, rad: float, dur: float, hostile: bool, on_done: Callable) -> void:
	var c := Color(1.0, 0.2, 0.15) if hostile else Color(1.0, 0.6, 0.15)
	var root := Node3D.new()
	root.position = to3(at, 0.04)
	level_root.add_child(root)
	var outer := Fx.mesh(root, Fx.disc(), Fx.mat(Color(c, 0.18), 1.0, true))
	outer.scale = Vector3(rad, 1, rad)
	Fx.mesh(root, Fx.arc_mesh(rad - 0.08, rad, 0, TAU, 48), Fx.mat(Color(c, 0.85), 2.0, true), Vector3(0, 0.01, 0))
	var inner := Fx.mesh(root, Fx.disc(), Fx.mat(Color(c, 0.3), 1.5, true), Vector3(0, 0.02, 0))
	inner.scale = Vector3(0.01, 1, 0.01)
	teles.append({"node": root, "inner": inner, "r": rad, "t": 0.0, "max": dur, "done": on_done})


## a telegraphed lane (the colossus charge) that fills from the start toward the far end
func add_line_tele(at: Vector2, angle: float, length: float, width: float, dur: float) -> void:
	var c := Color(1.0, 0.2, 0.15)
	var root := Node3D.new()
	root.position = to3(at, 0.04)
	root.rotation.y = atan2(-cos(angle), -sin(angle))   # local -Z points along `angle`
	level_root.add_child(root)
	Fx.mesh(root, Fx.box(Vector3(width, 0.01, length)), Fx.mat(Color(c, 0.18), 1.0, true), Vector3(0, 0, -length / 2.0))
	var inner := Fx.mesh(root, Fx.box(Vector3(width, 0.01, length)), Fx.mat(Color(c, 0.35), 1.5, true), Vector3(0, 0.01, 0))
	inner.scale = Vector3(1, 1, 0.01)
	teles.append({"node": root, "inner": inner, "len": length, "t": 0.0, "max": dur, "done": func(): pass})


func _update_teles(delta: float) -> void:
	for tl in teles:
		tl.t += delta
		var k := minf(1.0, tl.t / tl.max)
		if tl.has("len"):
			tl.inner.scale = Vector3(1, 1, k + 0.01)
			tl.inner.position.z = -tl.len * k / 2.0
		else:
			tl.inner.scale = Vector3(tl.r * k + 0.01, 1, tl.r * k + 0.01)
		if tl.t >= tl.max:
			tl.node.queue_free()
			tl.done.call()
	teles = teles.filter(func(tl): return tl.t < tl.max)


# =================== skills ===================
## resolve `fn` with a skill's support modifiers active (totems, minions and projectiles keep theirs)
func _with_sup(s: Dictionary, fn: Callable) -> void:
	var prev := sup
	sup = s
	fn.call()
	sup = prev


func slot_sup(i: int) -> Dictionary:
	var p := player
	var s := Data.build_sup(p.slots[i], p.active_links(i))
	if p.effects.has("inferno") and "fire" in Data.SKILLS[p.slots[i]].tags:
		s.aoe *= 1.3
	return s


func slot_cost(i: int) -> int:
	var s := slot_sup(i)
	var id: String = player.slots[i]
	var fx := player.effects
	var m: float = (0.65 if fx.has("fire_cost") and "fire" in Data.SKILLS[id].tags else 1.0) * (0.7 if fx.has("bone_march") and id == "skeleton" else 1.0)
	return roundi(Data.SKILLS[id].mana * s.mana * m * (2.5 if s.totem else (1.5 if s.trap else 1.0)))


## who is casting: the player, or a totem acting for them
func _player_caster() -> Dictionary:
	return {"pos": player.pos, "aim": player.aim, "to": mouse_ground, "player": true}


static func _fan(n: int, step: float) -> Array:
	var out := []
	for i in n:
		out.append((i - (n - 1) / 2.0) * step)
	return out


## a point toward the caster's target, no farther than `max_d`
static func _aim_point(c: Dictionary, max_d: float) -> Vector2:
	return c.pos + (c.to - c.pos).limit_length(max_d)


func _try_cast(i: int) -> void:
	var p := player
	var id: String = p.slots[i]
	var sk: Dictionary = Data.SKILLS[id]
	var s := slot_sup(i)
	if p.action_t > 0.0 and not "movement" in sk.tags:
		return
	if p.cds.get(id, 0.0) > 0.0:
		return
	if sk.has("aura"):
		_toggle_aura(id)
		return
	var cost := slot_cost(i)
	if p.mana < cost:
		if time - oom_t > 1.2:
			oom_t = time
			hud.message("マナが足りない", Color("#7fa8ff"))
		return
	var c := _player_caster()
	if not s.totem and id == "chain" and _chain_target(c) == null:
		return
	p.mana -= cost
	# only movement skills keep a cooldown; everything else is paced by attack / cast speed
	if sk.cd > 0.0:
		p.cds[id] = sk.cd * (1.0 - p.s.cdr / 100.0)
	if sk.get("attack", false):
		p.action_t = 1.0 / p.attack_rate_now() / s.speed
	elif sk.has("cast"):
		p.action_t = sk.cast / p.cast_speed_now() / s.speed
	if s.totem or s.trap:
		p.act("Spellcast_Raise" if s.totem else "Interact", 2.0, p.action_t)
		_place_totem(id, s, c)
	else:
		if sk.get("attack", false) and p.effects.has("third_strike"):
			p.combo = (p.combo + 1) % 3
			force_crit = p.combo == 0
		_with_sup(s, func(): _cast(id, c))
		force_crit = false
		if s.echo > 0:
			# "echo": the skill goes off once more from wherever the player is then, a little weaker
			var es := s.duplicate()
			es.dmg *= 0.7
			es.echo = 0
			get_tree().create_timer(0.25).timeout.connect(func():
				if not p.dead:
					_with_sup(es, func(): _cast(id, _player_caster())))


## switch an aura on or off; switching on is refused when the reservation would not fit
func _toggle_aura(id: String) -> void:
	var p := player
	var sk: Dictionary = Data.SKILLS[id]
	var on: bool = not id in p.auras
	if p.toggle_aura(id) != "":
		var pool: String = sk.aura.pool
		hud.message("「%s」を発動できない：%sのリザーブが上限を超える（必要 %d／空き %d）" % [sk.name, "ライフ" if pool == "life" else "マナ",
			p.aura_reserve(id, pool), p.cap(pool) - (1 if pool == "life" else 0)], Color("#ff8080"))
		return
	p.action_t = sk.cast / p.cast_speed_now()
	var an: Array = sk.anim
	p.act(an[0], an[1], p.action_t)
	var col: Color = sk.color
	if on:
		Fx.ring(level_root, to3(p.pos), sk.aura.r, col, 0.7)
		Fx.burst(level_root, to3(p.pos, 1.0), 28, col, 5.0)
		hud.message("オーラ「%s」を発動" % sk.name, col)
	else:
		Fx.burst(level_root, to3(p.pos, 0.6), 14, col.darkened(0.3), 3.0)
		hud.message("オーラ「%s」を解除" % sk.name, col.darkened(0.2))


## allies inside the reach of any active aura share its effects
func in_aura(a: Ally) -> bool:
	return player.auras.any(func(id): return a.pos.distance_to(player.pos) <= Data.SKILLS[id].aura.r)


## an ally's support modifiers, marked when it stands inside the player's auras
func _ally_sup(a: Ally) -> Dictionary:
	return a.sup.merged({"aura": true}) if in_aura(a) else a.sup


## resolve a skill: its own `_cast_<id>` when it has one, else its effect blocks
func _cast(id: String, c: Dictionary) -> void:
	if has_method("_cast_" + id):
		call("_cast_" + id, c)
	else:
		_cast_fx(id, c)


# =================== skills built from effect blocks ===================
func _cast_fx(id: String, c: Dictionary) -> void:
	var sk: Dictionary = Data.SKILLS[id]
	if c.player:
		var an: Array = sk.get("anim", ["Spellcast_Shoot", 2.0])
		player.act(an[0], an[1] * sup.speed, maxf(player.action_t, 0.3))
		if sk.get("attack", false):
			player.swing_t = 0.2
	var spell: bool = not sk.get("attack", false)
	for b in sk.fx:
		if b.has("wait"):
			# a later beat of the same skill (a second swing) comes from where the caster is by then
			var s := sup
			var cc := c.duplicate()
			get_tree().create_timer(b.wait).timeout.connect(func():
				if cc.player:
					if player.dead:
						return
					cc.pos = player.pos
					cc.aim = player.aim
				_with_sup(s, func(): _fx_block(id, b, cc, spell)))
		else:
			_fx_block(id, b, c, spell)


func _fx_block(id: String, b: Dictionary, c: Dictionary, spell: bool) -> void:
	var col: Color = Data.SKILLS[id].color
	var type: String = b.get("type", "phys")
	var coef: float = b.get("coef", 1.0)
	var fr: float = b.get("freeze", 0.0)
	match b.k:
		"arc":
			var reach: float = b.reach * sup.aoe
			for e in enemies:
				if e.dead:
					continue
				var d := e.pos.distance_to(c.pos)
				if d > reach + e.r:
					continue
				if absf(angle_difference(c.aim, (e.pos - c.pos).angle())) > b.half and d > e.r + 0.6:
					continue
				hit_enemy(e, roll_damage(coef, type, spell), fr)
			_swing_arc(c.pos, 1.0, reach, c.aim - b.half, c.aim + b.half, 0.18, Color(col.lightened(0.3), 0.7))
		"slam":
			var at := map.move_circle(c.pos, 0.3, Vector2.from_angle(c.aim) * b.dist)
			_fx_burst(at, b.r * sup.aoe, coef, type, spell, fr, col)
			if sup.after > 0:
				_aftershock(at, b.r * sup.aoe, coef, type, spell, fr, col)
		"nova":
			_fx_burst(c.pos, b.r * sup.aoe, coef, type, spell, fr, col)
			if sup.after > 0:
				_aftershock(c.pos, b.r * sup.aoe, coef, type, spell, fr, col)
		"line":
			_fx_line(c, b.len, b.w * sup.aoe, coef, type, spell, fr, col)
		"area":
			var center: Vector2 = c.pos if b.get("at", "") == "self" else _aim_point(c, b.get("range", 18.0))
			for i in b.get("n", 1) + sup.extra:
				var at := center
				if b.has("scatter") or i > 0:
					at += Vector2.from_angle(randf() * TAU) * randf() * b.get("scatter", 2.5)
				_fx_area(at, b.r * sup.aoe, b.delay, coef, type, spell, fr, col, b.get("bolt", false))
		"proj":
			_fx_proj(c, b, coef, type, spell, col)
		"chain":
			_fx_chain(c, b.n + sup.chain, coef, type, spell, col)
		"zone":
			_fx_zone(c, b, coef, type, spell, col)
		"buff":
			var stats := {}
			for k in b.stats:
				stats[k] = b.stats[k] * sup.beff
			player.add_tbuff(id, b.dur * sup.dur, stats)
			Fx.ring(level_root, to3(player.pos), 2.6, col, 0.5)
			Fx.burst(level_root, to3(player.pos, 1.0), 24, col, 5.0)
		"curse":
			var at := _aim_point(c, 18.0)
			var r: float = b.r * sup.aoe
			for e in enemies_in_radius(at, r):
				e.vuln = maxf(e.vuln if e.vuln_t > 0.0 else 0.0, b.vuln * sup.ceff)
				e.vuln_t = b.dur * sup.dur
				if b.get("slow", false):
					e.slow = maxf(e.slow, b.dur * sup.dur)
				if not e.aggro:
					_alert_pack(e)
			Fx.ring(level_root, to3(at), r, col, 0.6)
			Fx.burst(level_root, to3(at, 0.5), 30, col, r * 1.5, 0.6, 0.0)
		"summon":
			_fx_summon(id, c, b, col)
		"move":
			var to: Vector2 = c.to - c.pos
			var dist: float = clampf(to.length(), 3.0, b.dist) * sup.mdist
			player.dash = {"dir": to.normalized() if to.length() > 0.01 else Vector2.from_angle(c.aim), "left": dist, "hit": {}, "sup": sup,
				"speed": b.speed, "coef": b.coef, "type": type, "land": b.get("land", {}), "spell": spell}
			player.invuln = maxf(player.invuln, dist / b.speed + 0.1)


## hit everything in a circle
func _fx_burst(at: Vector2, r: float, coef: float, type: String, spell: bool, fr: float, col: Color) -> void:
	_explosion(at, r, col)
	for e in enemies_in_radius(at, r):
		hit_enemy(e, roll_damage(coef, type, spell), fr)


## "aftershock": a smaller, weaker repeat of a burst half a second later
func _aftershock(at: Vector2, r: float, coef: float, type: String, spell: bool, fr: float, col: Color) -> void:
	var s := sup
	add_tele(at, r * 0.7, 0.5, false, func(): _with_sup(s, func(): _fx_burst(at, r * 0.7, coef * 0.5, type, spell, fr, col)))


func _fx_area(at: Vector2, r: float, delay: float, coef: float, type: String, spell: bool, fr: float, col: Color, bolt: bool) -> void:
	var s := sup
	add_tele(at, r, delay, false, func(): _with_sup(s, func():
		if bolt:
			Fx.bolt(level_root, to3(at, 8.0), to3(at, 0.1), col, 0.25)
		_fx_burst(at, r, coef, type, spell, fr, col)
		if s.after > 0:
			_aftershock(at, r, coef, type, spell, fr, col)))


## a lane from the caster toward its aim, stopped by walls
func _fx_line(c: Dictionary, length: float, w: float, coef: float, type: String, spell: bool, fr: float, col: Color) -> void:
	var dir := Vector2.from_angle(c.aim)
	var reach := 0.0
	while reach < length and not map.solid_at(c.pos + dir * (reach + 0.5)):
		reach += 0.5
	reach = maxf(reach, 1.0)
	for e in enemies:
		if e.dead:
			continue
		var rel: Vector2 = e.pos - c.pos
		var along := rel.dot(dir)
		if along < -e.r or along > reach + e.r or absf(rel.cross(dir)) > w / 2.0 + e.r:
			continue
		hit_enemy(e, roll_damage(coef, type, spell), fr)
	var root := Node3D.new()
	root.position = to3(c.pos, 0.9)
	root.rotation.y = atan2(-cos(c.aim), -sin(c.aim))   # local -Z points along the aim
	level_root.add_child(root)
	var m := Fx.mat(Color(col, 0.8), 3.0, true)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	Fx.mesh(root, Fx.box(Vector3(w, 0.12, reach)), m, Vector3(0, 0, -reach / 2.0))
	Fx.fade_out(root, m, 0.25)


func _fx_proj(c: Dictionary, b: Dictionary, coef: float, type: String, spell: bool, col: Color) -> void:
	var n: int = b.get("n", 1) + sup.proj
	var angles: Array = []
	if b.get("ring", false):
		for i in n:
			angles.append(TAU * i / n)
	else:
		angles = _fan(n, b.get("spread", 0.15))
	for da in angles:
		var a: float = c.aim + da
		_spawn_proj(c.pos + Vector2.from_angle(a) * 0.6, a, b.speed * sup.pspeed, b, coef, type, spell, col, {})


func _spawn_proj(at: Vector2, a: float, speed: float, b: Dictionary, coef: float, type: String, spell: bool, col: Color, hit: Dictionary) -> void:
	var size: float = b.get("size", 0.25)
	var root := Node3D.new()
	root.position = to3(at, 1.0)
	root.rotation.y = -a - PI / 2.0
	level_root.add_child(root)
	var m := Fx.mat(col, 5.0, true)
	match b.get("shape", "orb"):
		"spear":
			var sp := Fx.mesh(root, Fx.cone(0.12, 1.0), m)
			sp.rotation.x = -PI / 2.0
		"blade":
			Fx.mesh(root, Fx.box(Vector3(0.55, 0.05, 0.16)), m)
		"wave":
			var wm := Fx.mat(Color(col, 0.8), 3.0, true)
			wm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			wm.cull_mode = BaseMaterial3D.CULL_DISABLED
			var wave := Fx.mesh(root, Fx.arc_mesh(0.5, 1.1, -0.8, 0.8), wm)
			wave.rotation.y = PI / 2.0
		_:
			Fx.mesh(root, Fx.sphere(size), m)
	proj_spawn.append({"node": root, "kind": "fx", "pos": at, "vel": Vector2.from_angle(a) * speed, "r": maxf(size, 0.3), "t": 0.0, "max": b.life,
		"hit": hit, "sup": sup, "b": b, "coef": coef, "type": type, "spell": spell, "col": col,
		"pierce": b.get("pierce", false) or sup.pierce > 0, "home": b.get("homing", 0.0) + sup.homing,
		"forked": not hit.is_empty(), "bounce": sup.pchain, "pulse_t": 0.0})


func _update_fx_proj(pr: Dictionary, delta: float) -> void:
	var b: Dictionary = pr.b
	if pr.home > 0.0:
		var tg := _nearest_enemy(pr.pos, 12.0)
		if tg:
			pr.vel = Vector2.from_angle(rotate_toward(pr.vel.angle(), (tg.pos - pr.pos).angle(), pr.home * delta)) * pr.vel.length()
	if b.has("wander"):
		pr.vel = pr.vel.rotated(randf_range(-1.0, 1.0) * b.wander * delta)
	pr.node.rotation.y = -pr.vel.angle() - PI / 2.0
	if b.get("shape", "") == "blade":
		pr.node.rotate_y(pr.t * 20.0)
	if b.has("pulse"):
		pr.pulse_t -= delta
		if pr.pulse_t <= 0.0:
			pr.pulse_t = b.pulse.every
			var near := enemies_in_radius(pr.pos, b.pulse.r * sup.aoe)
			near.shuffle()
			for e in near.slice(0, 3):
				Fx.bolt(level_root, to3(pr.pos, 1.0), to3(e.pos, 1.0), pr.col, 0.15)
				hit_enemy(e, roll_damage(b.pulse.coef, pr.type, pr.spell))
	var boom: float = b.get("boom", 0.0) * sup.aoe
	var fr: float = b.get("freeze", 0.0)
	var end: bool = pr.t > pr.max or map.solid_at(pr.pos)
	if not end and pr.coef > 0.0:
		for e in enemies:
			if e.dead or pr.hit.has(e) or e.pos.distance_to(pr.pos) > e.r + pr.r:
				continue
			pr.hit[e] = true
			if boom > 0.0:
				_fx_burst(pr.pos, boom, pr.coef, pr.type, pr.spell, fr, pr.col)
			else:
				hit_enemy(e, roll_damage(pr.coef, pr.type, pr.spell), fr)
			if sup.fork > 0 and not pr.forked:
				# "fork": two copies split off to the sides, and won't hit this enemy again
				pr.forked = true
				for da in [-0.5, 0.5]:
					_spawn_proj(pr.pos, pr.vel.angle() + da, pr.vel.length(), b, pr.coef, pr.type, pr.spell, pr.col, pr.hit.duplicate())
				end = not pr.pierce
			elif pr.bounce > 0:
				# "ricochet": turn toward the nearest enemy not hit yet
				pr.bounce -= 1
				var nx: Enemy = null
				var bd := 100.0
				for o in enemies:
					var dq := o.pos.distance_squared_to(pr.pos)
					if not o.dead and not pr.hit.has(o) and dq < bd:
						bd = dq
						nx = o
				if nx:
					pr.vel = (nx.pos - pr.pos).normalized() * pr.vel.length()
					pr.t = minf(pr.t, pr.max * 0.5)
				else:
					end = not pr.pierce
			elif not pr.pierce:
				end = true
			if end:
				break
	if end:
		if boom > 0.0 and pr.hit.is_empty():
			_fx_burst(pr.pos, boom, pr.coef, pr.type, pr.spell, fr, pr.col)
		pr.t = pr.max + 1.0
		pr.node.queue_free()


func _fx_chain(c: Dictionary, n: int, coef: float, type: String, spell: bool, col: Color) -> void:
	var target: Variant = _chain_target(c)
	var hit := {}
	var src := to3(c.pos, 1.2)
	while target != null and n > 0:
		n -= 1
		var e: Enemy = target
		hit[e] = true
		var dst := to3(e.pos, 1.0)
		Fx.bolt(level_root, src, dst, col)
		hit_enemy(e, roll_damage(coef, type, spell))
		src = dst
		target = null
		var bd := 9.0 * 9.0
		for o in enemies:
			var d := o.pos.distance_squared_to(e.pos)
			if not o.dead and not hit.has(o) and d < bd and map.los(e.pos, o.pos):
				bd = d
				target = o


func _fx_zone(c: Dictionary, b: Dictionary, coef: float, type: String, spell: bool, col: Color) -> void:
	var where: String = b.get("at", "")
	var follow: bool = where == "follow" and c.player
	var at: Vector2 = c.pos if where in ["self", "follow"] else _aim_point(c, b.get("range", 18.0))
	var r: float = b.r * sup.aoe
	for i in 1 + (0 if where == "follow" else sup.extra):
		var p0 := at if i == 0 else at + Vector2.from_angle(randf() * TAU) * r * 0.8
		var root := Node3D.new()
		root.position = to3(p0, 0.05)
		level_root.add_child(root)
		var disc := Fx.mesh(root, Fx.disc(), Fx.mat(Color(col, 0.16), 1.5, true))
		disc.scale = Vector3(r, 1, r)
		Fx.mesh(root, Fx.arc_mesh(r - 0.1, r, 0, TAU, 48), Fx.mat(Color(col, 0.6), 2.0, true), Vector3(0, 0.01, 0))
		if follow:
			# three blades circling the player
			for k in 3:
				var a := TAU * k / 3.0
				Fx.mesh(root, Fx.box(Vector3(0.7, 0.05, 0.16)), Fx.mat(col, 4.0, true), Vector3(cos(a) * r * 0.7, 0.9, sin(a) * r * 0.7))
		zones.append({"node": root, "pos": p0, "r": r, "t": 0.0, "max": b.dur * sup.dur, "tick": 0.0, "every": b.every, "coef": coef,
			"type": type, "spell": spell, "sup": sup, "follow": follow, "slow": b.get("slow", 0.0), "strike": b.get("strike", false), "col": col})


func _update_zones(delta: float) -> void:
	for z in zones:
		z.t += delta
		z.tick -= delta
		if z.follow:
			z.pos = player.pos
			z.node.position = to3(z.pos, 0.05)
			z.node.rotation.y += delta * 8.0
		if z.tick <= 0.0:
			z.tick = z.every
			_with_sup(z.sup, func():
				if z.strike:
					# raining strikes: one small blast per tick, on an enemy inside when there is one
					var near := enemies_in_radius(z.pos, z.r)
					var at: Vector2 = near.pick_random().pos if not near.is_empty() else z.pos + Vector2.from_angle(randf() * TAU) * randf() * z.r
					Fx.ring(level_root, to3(at), 1.5, z.col, 0.25)
					Fx.burst(level_root, to3(at, 0.3), 10, z.col, 5.0)
					for e in enemies_in_radius(at, 1.5):
						hit_enemy(e, roll_damage(z.coef, z.type, z.spell))
				else:
					Fx.burst(level_root, to3(z.pos, 0.4), 6, z.col, z.r * 1.5, 0.4, 0.0)
					for e in enemies_in_radius(z.pos, z.r):
						hit_enemy(e, roll_damage(z.coef, z.type, z.spell))
						if z.slow > 0.0:
							e.slow = maxf(e.slow, z.slow))
		if z.t >= z.max:
			z.node.queue_free()
	zones = zones.filter(func(z): return z.t < z.max)


func _fx_summon(id: String, c: Dictionary, b: Dictionary, col: Color) -> void:
	var p := player
	var mine := minions.filter(func(m): return m.skill == id)
	for i in b.n:
		if mine.size() >= b.max + sup.mcount:
			var old: Ally = mine.pop_front()
			_kill_ally(old)
			minions.erase(old)
		var at: Vector2 = c.pos + Vector2.from_angle(randf() * TAU) * 1.6
		if map.circle_hits(at, 0.45):
			at = c.pos
		var m := Ally.new()
		level_root.add_child(m)
		m.setup_minion(at, (50.0 + p.level * 12) * b.life * sup.mlife * (1.0 + p.s.ally_life / 100.0), sup, col)
		m.skill = id
		m.coef = b.coef
		m.max_t = b.dur * sup.dur
		m.model.scale *= b.get("scale", 1.0)
		m.face = c.aim
		m.sync_node(0.0, false)
		minions.append(m)
		mine.append(m)
		Fx.burst(level_root, to3(at, 0.5), 14, col, 4.0)


func _cast_slash(c: Dictionary) -> void:
	var p := player
	var reach := 3.2
	p.swing_t = 0.2
	p.act("1H_Melee_Attack_Slice_Horizontal", 2.2 * sup.speed, p.action_t)
	for e in enemies:
		if e.dead:
			continue
		var d := e.pos.distance_to(c.pos)
		if d > reach + e.r:
			continue
		if absf(angle_difference(c.aim, (e.pos - c.pos).angle())) > 1.15 and d > e.r + p.r:
			continue
		hit_enemy(e, roll_damage(1.0, "phys"))
	_swing_arc(c.pos, 1.0, reach, c.aim - 1.1, c.aim + 1.1, 0.18)
	if p.effects.has("slash_wave"):
		var wave := MeshInstance3D.new()
		wave.mesh = Fx.arc_mesh(0.6, 1.4, -0.9, 0.9)
		var wm := Fx.mat(Color(1.0, 0.9, 0.7, 0.8), 3.0, true)
		wm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		wm.cull_mode = BaseMaterial3D.CULL_DISABLED
		wave.material_override = wm
		wave.rotation.y = -c.aim
		level_root.add_child(wave)
		projs.append({"node": wave, "kind": "wave", "pos": c.pos, "vel": Vector2.from_angle(c.aim) * 26.0, "r": 1.0, "t": 0.0, "max": 0.55, "hit": {}, "sup": sup})


## a fading additive crescent on the ground plane, for melee swings
func _swing_arc(at: Vector2, r0: float, r1: float, a0: float, a1: float, dur: float, color := Color(1.0, 0.94, 0.82, 0.7)) -> void:
	var arc := MeshInstance3D.new()
	arc.mesh = Fx.arc_mesh(r0, r1, a0, a1, 48)
	var m := Fx.mat(color, 2.0, true)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	arc.material_override = m
	arc.position = to3(at, 0.9)
	level_root.add_child(arc)
	Fx.fade_out(arc, m, dur)


func _cast_whirl(c: Dictionary) -> void:
	var p := player
	var rad: float = 4.2 * sup.aoe
	p.swing_t = 0.2
	p.act("2H_Melee_Attack_Spin", 2.4 * sup.speed, p.action_t)
	for e in enemies_in_radius(c.pos, rad):
		hit_enemy(e, roll_damage(0.85, "phys"))
	_swing_arc(c.pos, rad * 0.35, rad, 0.0, TAU, 0.22, Color(1.0, 0.85, 0.5, 0.6))


func _cast_fireball(c: Dictionary) -> void:
	if c.player:
		player.act("Spellcast_Shoot", 2.0, player.action_t)
	var base := 3 if player.effects.has("fireball_multi") else 1
	for da in _fan(base + sup.proj, 0.2):
		var dir := Vector2.from_angle(c.aim + da)
		var root := Node3D.new()
		root.position = to3(c.pos + dir * 0.6, 1.0)
		level_root.add_child(root)
		Fx.mesh(root, Fx.sphere(0.28), Fx.mat(Color("#ffa040"), 6.0, true))
		var light := OmniLight3D.new()
		light.light_color = Color("#ff8a30")
		light.light_energy = 2.0
		light.omni_range = 6.0
		root.add_child(light)
		projs.append({"node": root, "kind": "fireball", "pos": c.pos + dir * 0.6, "vel": dir * 24.0, "r": 0.3, "t": 0.0, "max": 1.4, "sup": sup, "boom": 2.8 * sup.aoe})


func _cast_ice_spear(c: Dictionary) -> void:
	if c.player:
		player.act("Spellcast_Shoot", 2.2, player.action_t)
	for da in _fan(1 + sup.proj, 0.14):
		var a: float = c.aim + da
		var dir := Vector2.from_angle(a)
		var root := Node3D.new()
		root.position = to3(c.pos + dir * 0.6, 1.0)
		root.rotation.y = -a - PI / 2.0
		level_root.add_child(root)
		var spear := Fx.mesh(root, Fx.cone(0.12, 1.1), Fx.mat(Color("#bff4ff"), 5.0, true))
		spear.rotation.x = -PI / 2.0
		var light := OmniLight3D.new()
		light.light_color = Color("#7fd4ff")
		light.light_energy = 1.2
		light.omni_range = 4.0
		root.add_child(light)
		projs.append({"node": root, "kind": "spear", "pos": c.pos + dir * 0.6, "vel": dir * 32.0, "r": 0.36, "t": 0.0, "max": 0.8, "hit": {}, "sup": sup})


func _cast_nova(c: Dictionary, free := false) -> void:
	if c.player and not free:
		player.act("Spellcast_Raise", 2.2, player.action_t)
	var rad: float = 8.0 * sup.aoe
	Fx.ring(level_root, to3(c.pos), rad, Color("#8cdcff"), 0.4)
	Fx.burst(level_root, to3(c.pos, 0.6), 50, Color("#aee8ff"), 14.0, 0.5, 0.0)
	for e in enemies_in_radius(c.pos, rad):
		hit_enemy(e, roll_damage(0.8 if free else 1.3, "cold", true), 1.8)


func _chain_target(c: Dictionary) -> Variant:
	var best: Enemy = null
	var bd := INF
	for e in enemies:
		if e.dead or e.pos.distance_to(c.pos) > 18.0:
			continue
		var d := e.pos.distance_squared_to(c.to)
		if d < bd and map.los(c.pos, e.pos):
			bd = d
			best = e
	return best


func _cast_chain(c: Dictionary) -> void:
	if c.player:
		player.act("Spellcast_Shoot", 2.0, player.action_t)
	var target: Variant = _chain_target(c)
	var hit := {}
	var src := to3(c.pos, 1.2)
	var n: int = 5 + (4 if player.effects.has("chain_plus") else 0) + sup.chain
	while target != null and n > 0:
		n -= 1
		var e: Enemy = target
		hit[e] = true
		var dst := to3(e.pos, 1.0)
		Fx.bolt(level_root, src, dst)
		Fx.burst(level_root, dst, 6, Color("#d9c2ff"), 4.0)
		hit_enemy(e, roll_damage(1.15, "light", true))
		src = dst
		target = null
		var bd := 9.0 * 9.0
		for o in enemies:
			if o.dead or hit.has(o):
				continue
			var d := o.pos.distance_squared_to(e.pos)
			if d < bd and map.los(e.pos, o.pos):
				bd = d
				target = o


func _cast_storm(c: Dictionary) -> void:
	if c.player:
		player.act("Spellcast_Long", 2.0, player.action_t)
	var at := _aim_point(c, 19.0)
	var rad: float = 6.8 * sup.aoe
	var root := Node3D.new()
	root.position = to3(at, 0.05)
	level_root.add_child(root)
	var disc := Fx.mesh(root, Fx.disc(), Fx.mat(Color(0.55, 0.45, 1.0, 0.18), 1.5, true))
	disc.scale = Vector3(rad, 1, rad)
	Fx.mesh(root, Fx.arc_mesh(rad - 0.1, rad, 0, TAU, 48), Fx.mat(Color(0.75, 0.65, 1.0, 0.6), 2.0, true), Vector3(0, 0.01, 0))
	var cloud := Fx.mesh(root, Fx.sphere(1.0), Fx.mat(Color(0.18, 0.16, 0.3, 0.7), 0.4, true), Vector3(0, 7.0, 0))
	cloud.scale = Vector3(rad * 0.8, 0.5, rad * 0.8)
	var light := OmniLight3D.new()
	light.light_color = Color("#b0a0ff")
	light.light_energy = 0.0
	light.omni_range = rad * 2.0
	light.position.y = 4.0
	root.add_child(light)
	var eye := player.effects.has("storm_eye")
	storms.append({"node": root, "light": light, "pos": at, "r": rad, "t": 0.0, "max": 6.0 if eye else 3.0, "tick": 0.1,
		"every": 0.154 if eye else 0.22, "sup": sup})


func _update_storms(delta: float) -> void:
	for st in storms:
		st.t += delta
		st.tick -= delta
		st.light.light_energy = maxf(0.0, st.light.light_energy - delta * 20.0)
		if st.tick <= 0.0:
			st.tick = st.every
			var near := enemies_in_radius(st.pos, st.r)
			var tgt: Enemy = near.pick_random() if not near.is_empty() else null
			var at: Vector2 = tgt.pos if tgt else st.pos + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * st.r * 0.8
			Fx.bolt(level_root, to3(at, 7.0), to3(at, 0.1), Color("#e0d0ff"), 0.18)
			Fx.burst(level_root, to3(at, 0.3), 8, Color("#d9c2ff"), 5.0)
			st.light.light_energy = 3.0
			if tgt:
				_with_sup(st.sup, func(): hit_enemy(tgt, roll_damage(0.9, "light", true)))
		if st.t >= st.max:
			st.node.queue_free()
	storms = storms.filter(func(st): return st.t < st.max)


func _cast_meteor(c: Dictionary) -> void:
	if c.player:
		player.act("Spellcast_Long", 2.0, player.action_t)
	var at := _aim_point(c, 20.0)
	_drop_meteor(at, 0.75)
	if player.effects.has("meteor_shower"):
		_drop_meteor(at + Vector2(randf_range(-5, 5), randf_range(-5, 5)), 1.0)
		_drop_meteor(at + Vector2(randf_range(-5, 5), randf_range(-5, 5)), 1.25)


func _drop_meteor(at: Vector2, delay: float) -> void:
	var s := sup
	var rad: float = 4.6 * s.aoe
	add_tele(at, rad, delay, false, func(): _with_sup(s, func():
		_explosion(at, rad, Color("#ff6e28"))
		for e in enemies_in_radius(at, rad):
			hit_enemy(e, roll_damage(3.6, "fire", true))
		_add_hazard(at, rad * 0.83, 3.5)))


func _cast_dash(c: Dictionary) -> void:
	var p := player
	var to: Vector2 = c.to - c.pos
	p.dash = {"dir": to.normalized() if to.length() > 0.01 else Vector2.from_angle(c.aim), "left": clampf(to.length(), 5.0, 11.0) * sup.mdist, "hit": {}, "sup": sup}
	p.invuln = 0.3


func _update_dash(delta: float) -> void:
	var p := player
	var d := p.dash
	var step := minf(d.left, d.get("speed", 60.0) * delta)
	d.left -= step
	while step > 0.0:
		var sub := minf(0.3, step)
		step -= sub
		var before := p.pos
		p.pos = map.move_circle(p.pos, p.r, d.dir * sub)
		if before.distance_to(p.pos) < 0.01:
			d.left = 0.0
			break
	var coef: float = d.get("coef", 0.9)
	if coef > 0.0:
		_with_sup(d.sup, func():
			for e in enemies:
				if e.dead or d.hit.has(e) or e.pos.distance_to(p.pos) > e.r + p.r + 0.6:
					continue
				d.hit[e] = true
				hit_enemy(e, roll_damage(coef, d.get("type", "phys"), d.get("spell", false))))
	Fx.burst(level_root, to3(p.pos, 0.8), 3, Color("#8c78ff"), 1.0, 0.3, 0.0)
	if d.left <= 0.0:
		p.dash = {}
		# a landing blow, and "impact" from a linked support
		var land: Dictionary = d.get("land", {})
		var col: Color = Data.SKILLS[d.sup.skill].color
		_with_sup(d.sup, func():
			if not land.is_empty():
				_fx_burst(p.pos, land.r * sup.aoe, land.coef, land.type, d.get("spell", false), 0.0, col)
			if sup.mland > 0:
				_fx_burst(p.pos, 3.0 * sup.aoe, 0.8, "phys", false, 0.0, col))
		if p.effects.has("dash_nova"):
			_cast_nova(_player_caster(), true)


func _cast_skeleton(c: Dictionary) -> void:
	var p := player
	if c.player:
		p.act("Spellcast_Raise", 2.0, p.action_t)
	var most: int = 3 + sup.mcount + (2 if p.effects.has("bone_legion") else 0)
	var mine := minions.filter(func(m): return m.skill == "skeleton")
	for i in (3 if p.effects.has("bone_march") else 2):
		if mine.size() >= most:
			var old: Ally = mine.pop_front()   # the oldest crumbles to make room
			_kill_ally(old)
			minions.erase(old)
		var at: Vector2 = c.pos + Vector2.from_angle(randf() * TAU) * 1.6
		if map.circle_hits(at, 0.45):
			at = c.pos
		var m := Ally.new()
		level_root.add_child(m)
		m.setup_minion(at, (50.0 + p.level * 12) * sup.mlife * (1.0 + p.s.ally_life / 100.0), sup)
		m.skill = "skeleton"
		m.face = c.aim
		m.sync_node(0.0, false)
		minions.append(m)
		mine.append(m)
		Fx.burst(level_root, to3(at, 0.5), 14, Color("#e8e0c8"), 4.0)


## burning ground; with `hostile_dmg` it is the bosses' fire and hurts the player and allies instead
func _add_hazard(at: Vector2, rad: float, dur: float, hostile_dmg := 0.0) -> void:
	var root := Node3D.new()
	root.position = to3(at, 0.05)
	level_root.add_child(root)
	var disc := Fx.mesh(root, Fx.disc(), Fx.mat(Color(1.0, 0.35, 0.08, 0.45), 2.5, true))
	disc.scale = Vector3(rad, 1, rad)
	var fire := CPUParticles3D.new()
	fire.amount = 40
	fire.lifetime = 0.7
	fire.mesh = Fx.sphere(0.08)
	fire.material_override = Fx.mat(Color("#ff8a30"), 5.0, true)
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = rad * 0.8
	fire.scale = Vector3(1, 0.05, 1)
	fire.direction = Vector3.UP
	fire.gravity = Vector3(0, 40, 0)
	fire.initial_velocity_min = 0.5
	fire.initial_velocity_max = 1.5
	root.add_child(fire)
	var light := OmniLight3D.new()
	light.light_color = Color("#ff7a30")
	light.light_energy = 2.0
	light.omni_range = rad * 2.0
	light.position.y = 1.0
	root.add_child(light)
	if hostile_dmg <= 0.0 and player.effects.has("inferno"):
		dur *= 2.0
	hazards.append({"node": root, "pos": at, "r": rad, "t": 0.0, "max": dur, "tick": 0.0, "sup": sup, "hostile": hostile_dmg})


func _update_hazards(delta: float) -> void:
	for hz in hazards:
		hz.t += delta
		hz.tick -= delta
		if hz.tick <= 0.0 and hz.hostile > 0.0:
			hz.tick = 0.3
			_damage_area(hz.pos, hz.r, hz.hostile)
		elif hz.tick <= 0.0:
			hz.tick = 0.5
			_with_sup(hz.sup, func():
				for e in enemies_in_radius(hz.pos, hz.r):
					hit_enemy(e, roll_damage(0.35, "fire", true)))
		if hz.t >= hz.max:
			hz.node.queue_free()
	hazards = hazards.filter(func(hz): return hz.t < hz.max)


func _update_projectiles(delta: float) -> void:
	for pr in projs:
		sup = pr.sup
		pr.t += delta
		pr.pos += pr.vel * delta
		pr.node.position = to3(pr.pos, 1.0)
		if pr.kind == "fx":
			_update_fx_proj(pr, delta)
			continue
		if pr.kind == "wave" or pr.kind == "spear":
			var spear: bool = pr.kind == "spear"
			for e in enemies:
				if not e.dead and not pr.hit.has(e) and e.pos.distance_to(pr.pos) < e.r + pr.r:
					pr.hit[e] = true
					if spear:
						hit_enemy(e, roll_damage(1.1, "cold", true), 0.6)
					else:
						hit_enemy(e, roll_damage(0.7, "phys"))
			if pr.t > pr.max or map.solid_at(pr.pos):
				pr.t = pr.max + 1.0
				pr.node.queue_free()
				if spear:
					Fx.burst(level_root, to3(pr.pos, 1.0), 10, Color("#bff4ff"), 4.0)
			continue
		var boom: bool = pr.t > pr.max or map.solid_at(pr.pos)
		if not boom:
			for e in enemies:
				if not e.dead and e.pos.distance_to(pr.pos) < e.r + pr.r:
					boom = true
					break
		if boom:
			pr.t = pr.max + 1.0
			pr.node.queue_free()
			_explosion(pr.pos, pr.boom, Color("#ff8c32"))
			for e in enemies_in_radius(pr.pos, pr.boom):
				hit_enemy(e, roll_damage(1.5, "fire", true))
	sup = no_sup
	projs = projs.filter(func(pr): return pr.t <= pr.max)
	projs.append_array(proj_spawn)
	proj_spawn.clear()


# =================== totems and minions ===================
const TOTEM_MAX := 2
const TRAP_MAX := 3


func _place_totem(id: String, s: Dictionary, c: Dictionary) -> void:
	var p := player
	var at := _aim_point(c, 15.0)
	var back := (at - p.pos).normalized()
	for k in 20:
		if not map.circle_hits(at, 0.5):
			break
		at -= back * 0.8
	var trap: bool = s.trap > 0 and s.totem == 0
	var mine := totems.filter(func(t): return t.skill == id and t.trap == trap)
	if mine.size() >= (TRAP_MAX if trap else TOTEM_MAX + (1 if p.effects.has("twin_totems") else 0)):
		mine[0].life = 0.0
	var t := Ally.new()
	level_root.add_child(t)
	t.setup_totem(at, id, (60.0 + p.level * 15) * (1.0 + p.s.ally_life / 100.0), s)
	if trap:
		t.trap = true
		t.max_t = 12.0
		t.model.scale = Vector3(0.45, 0.45, 0.45)
	t.sync_node(0.0, false)
	totems.append(t)
	Fx.burst(level_root, to3(at, 1.0), 20, Data.SKILLS[id].color, 5.0)


func _nearest_enemy(from: Vector2, max_d: float, near_to := Vector2.INF, near_d := INF) -> Enemy:
	var best: Enemy = null
	var bd := max_d * max_d
	for e in enemies:
		if e.dead or (near_to.x != INF and e.pos.distance_to(near_to) > near_d):
			continue
		var d := e.pos.distance_squared_to(from)
		if d < bd and map.los(from, e.pos):
			bd = d
			best = e
	return best


func _update_totems(delta: float) -> void:
	for t in totems:
		t.t += delta
		t.cast_t -= delta
		t.animate(delta, false)
		if t.t >= t.max_t or t.life <= 0.0:
			t.life = 0.0
			continue
		if t.cast_t > 0.0:
			continue
		if t.trap:
			# a trap springs once, when an enemy comes close
			var near := _nearest_enemy(t.pos, 4.5)
			if near:
				t.life = 0.0
				var tc := {"pos": t.pos, "aim": (near.pos - t.pos).angle(), "to": near.pos, "player": false}
				_with_sup(t.sup, func(): _cast(t.skill, tc))
			continue
		var best := _nearest_enemy(t.pos, 20.0)
		if best == null:
			t.cast_t = 0.3
			continue
		var sk: Dictionary = Data.SKILLS[t.skill]
		var ts := _ally_sup(t)
		t.cast_t = maxf(0.45, sk.get("cast", 0.4) * 1.5 / t.sup.speed) / (1.25 if player.effects.has("lich_lord") else 1.0)
		if ts.has("aura"):
			t.cast_t /= 1.0 + player.astat("cast_spd") / 100.0
		t.face = (best.pos - t.pos).angle()
		var c := {"pos": t.pos, "aim": t.face, "to": best.pos, "player": false}
		_with_sup(ts, func(): _cast(t.skill, c))
	for t in totems:
		if t.life <= 0.0:
			_kill_ally(t)
	totems = totems.filter(func(t): return t.life > 0.0)


func _update_minions(delta: float) -> void:
	var p := player
	for m in minions:
		if m.life <= 0.0:
			continue
		m.t += delta
		if m.max_t > 0.0 and m.t >= m.max_t:   # summoned for a while only
			m.life = 0.0
			continue
		m.atk_cd -= delta
		m.scan_t -= delta
		var ms := _ally_sup(m)
		if ms.has("aura"):
			m.life = minf(m.max_life, m.life + m.max_life * p.astat("regen") / 100.0 * delta)
		var dp := m.pos.distance_to(p.pos)
		if dp > 28.0:
			m.pos = p.pos
			m.target = null
		if m.target and m.target.dead:
			m.target = null
		if m.scan_t <= 0.0:
			m.scan_t = 0.3
			m.target = _nearest_enemy(m.pos, 16.8, p.pos, 20.0)
		var goal := p.pos
		var sp := 12.0 if dp > 10.0 else 8.4
		var moving := true
		if m.target:
			var e := m.target
			m.face = (e.pos - m.pos).angle()
			goal = e.pos
			sp = 8.8
			if m.pos.distance_to(e.pos) < e.r + m.r + 0.5:
				moving = false
				if m.atk_cd <= 0.0:
					m.atk_cd = 0.9 / m.sup.speed / (1.25 if p.effects.has("lich_lord") else 1.0)
					if ms.has("aura"):
						m.atk_cd /= 1.0 + p.astat("atk_spd") / 100.0
					m.swing_t = 0.3
					_with_sup(ms, func(): hit_enemy(e, roll_damage(m.coef, "phys", true)))
		elif dp < 3.2:
			moving = false
		if moving:
			var dir := (goal - m.pos).normalized()
			if ms.has("aura"):
				sp *= 1.0 + p.astat("move") / 100.0
			m.pos = map.move_circle(m.pos, m.r, dir * sp * delta)
			m.face = dir.angle()
		m.animate(delta, moving)
	for m in minions:
		if m.life <= 0.0:
			if p.effects.has("death_pact"):
				_death_pact(m)
			_kill_ally(m)
	minions = minions.filter(func(m): return m.life > 0.0)


## "death pact": a fallen skeleton bursts
func _death_pact(m: Ally) -> void:
	var at := m.pos
	_with_sup(m.sup, func():
		_explosion(at, 3.2, Color("#c8b0f0"))
		for e in enemies_in_radius(at, 3.2):
			hit_enemy(e, roll_damage(1.0, "phys", true)))


func _kill_ally(a: Ally) -> void:
	a.life = 0.0
	a.dead = true
	Fx.burst(level_root, to3(a.pos, 0.8), 16, Color("#d8d0b8") if a.kind == "minion" else Color("#8a6a3a"), 4.0)
	a.queue_free()


## enemies hit minions and totems too
func damage_ally(a: Actor, amount: float) -> void:
	if a == player:
		damage_player(amount)
		return
	var al := a as Ally
	if al.dead:
		return
	if in_aura(al):
		amount *= 1.0 - player.astat("dr") / 100.0
	al.life -= amount
	al.hit_t = 0.12
	add_text(al.pos, str(roundi(amount)), Color("#b0b0b0"), 15)


func _allies() -> Array[Ally]:
	var out: Array[Ally] = []
	out.append_array(minions)
	out.append_array(totems)
	return out


## damage the player and every ally inside a circle
func _damage_area(at: Vector2, rad: float, amount: float) -> void:
	if player.pos.distance_to(at) < rad + player.r:
		damage_player(amount)
	for a in _allies():
		if a.pos.distance_to(at) < rad + a.r:
			damage_ally(a, amount)


## regular monsters go for whoever is closest, with a slight preference for the player
func _pick_target(e: Enemy) -> Actor:
	var best: Actor = player
	var bd := e.pos.distance_to(player.pos) * 0.85
	for a in _allies():
		var d := e.pos.distance_to(a.pos)
		if d < bd and d < 16.0:
			bd = d
			best = a
	return best


# =================== enemies ===================
func _alert_pack(e: Enemy) -> void:
	e.aggro = true
	for o in enemies:
		if o.pack == e.pack and not o.aggro and o.pos.distance_to(e.pos) < 20.0:
			o.aggro = true


func _update_enemy(e: Enemy, delta: float) -> void:
	var p := player
	e.atk_cd -= delta
	e.slow -= delta
	e.shock -= delta
	e.vuln_t -= delta
	if e.burn_t > 0.0 or e.bleed_t > 0.0 or e.poison_t > 0.0:
		_update_dots(e, delta)
		if e.dead:
			return
	if e.stun > 0.0:
		e.stun -= delta
		return
	if e.frozen > 0.0:
		e.frozen -= delta
		return
	var d := e.pos.distance_to(p.pos)
	e.los_t -= delta
	if e.los_t <= 0.0:
		e.los_t = 0.2 + randf() * 0.1
		e.sees = d < 30.0 and map.los(e.pos, p.pos)
	if not e.aggro:
		if (d < 15.0 or (e.boss and d < 20.0)) and e.sees:
			_alert_pack(e)
		else:
			e.wander_t -= delta
			if e.wander_t < 0.0:
				e.wander_t = randf_range(1.5, 4.0)
				e.face = randf() * TAU
				e.wandering = randf_range(0.3, 0.9)
			if e.wandering > 0.0:
				e.wandering -= delta
				e.pos = map.move_circle(e.pos, e.r, Vector2.from_angle(e.face) * e.speed * 0.3 * delta)
			return
	if p.dead:
		return
	if e.windup > 0.0:
		e.windup -= delta
		if e.windup <= 0.0 and e.pending.is_valid():
			var fn := e.pending
			e.pending = Callable()
			fn.call()
		return
	if e.boss:
		_update_boss(e, delta, d)
		return
	# regular monsters fight whoever is closest: the player, a minion or a totem
	e.tgt_t -= delta
	if e.tgt_t <= 0.0 or not is_instance_valid(e.tgt) or e.tgt.dead:
		e.tgt_t = 0.5
		e.tgt = _pick_target(e)
	var tg := e.tgt
	var td := e.pos.distance_to(tg.pos)
	var sees: bool = e.sees if tg == p else td < 20.0
	var t := e.t
	var move := true
	if t.get("ranged", false) or t.get("caster", false):
		if td < t.range and sees:
			move = false
			if t.get("ranged", false) and td < 5.0:
				e.pos = map.move_circle(e.pos, e.r, (e.pos - tg.pos).normalized() * e.speed * 0.7 * delta)
			if e.atk_cd <= 0.0:
				_start_attack(e, tg)
	elif td < t.atk_range + e.r + tg.r:
		move = false
		if e.atk_cd <= 0.0:
			_start_attack(e, tg)
	if move:
		_chase(e, delta, tg)
	e.face = (tg.pos - e.pos).angle()


const DOTS := {"burn": ["fire", Color("#ff9a50")], "bleed": ["phys", Color("#d04040")], "poison": ["chaos", Color("#90d060")]}


## burning, bleeding and poison lose life over time, shown as one number every half second
func _update_dots(e: Enemy, delta: float) -> void:
	var d := 0.0
	var last := "burn"
	for k in DOTS:
		var left: float = e.get(k + "_t")
		if left > 0.0:
			d += e.get(k + "_dps") * minf(delta, left)
			e.set(k + "_t", left - delta)
			last = k
	e.life -= d
	e.burn_acc += d
	e.burn_show -= delta
	if e.burn_show <= 0.0:
		e.burn_show = 0.5
		if e.burn_acc >= 1.0:
			add_text(e.pos, str(roundi(e.burn_acc)), DOTS[last][1], 14)
			e.burn_acc = 0.0
	if e.life <= 0.0:
		_asc_on_kill(e, {"type": DOTS[last][0], "spell": true})
		_kill_enemy(e)


func _chase(e: Enemy, delta: float, tg: Actor = null) -> void:
	if tg == null:
		tg = player
	var target := tg.pos
	if tg == player and not e.sees:
		target = map.flow_next(e.pos)
		if target.x == INF:
			return
	var dir := (target - e.pos).normalized()
	e.pos = map.move_circle(e.pos, e.r, dir * e.speed * (0.5 if e.slow > 0.0 else 1.0) * delta)


func _start_attack(e: Enemy, tg: Actor) -> void:
	var t := e.t
	e.atk_cd = t.atk_cd * e.atk_cd_mul
	e.windup = t.windup
	if t.get("ranged", false):
		e.pending = func():
			if not e.dead and is_instance_valid(tg):
				_enemy_shot(e.pos, (tg.pos - e.pos).angle(), 16.0, e.dmg, Color("#e8e0b0"))
	elif t.get("caster", false):
		var at := tg.pos
		var dmg := e.dmg
		add_tele(at, 2.6, t.windup + 0.15, true, func():
			_explosion(at, 2.6, Color("#5adcf0"))
			_damage_area(at, 2.6, dmg))
		e.pending = func(): pass
	elif t.has("aoe"):
		var rad: float = t.aoe
		add_tele(e.pos, rad, t.windup, true, func():
			if e.dead or e.frozen > 0.0:
				return
			_explosion(e.pos, rad, Color("#c88cff"))
			_damage_area(e.pos, rad, e.dmg))
		e.pending = func(): pass
	else:
		e.pending = func():
			if not e.dead and is_instance_valid(tg) and not tg.dead and tg.pos.distance_to(e.pos) < t.atk_range + e.r + tg.r + 0.5:
				damage_ally(tg, e.dmg)


## `chill` seconds of slow on the player when it hits
func _enemy_shot(from: Vector2, angle: float, speed: float, dmg: float, color: Color, chill := 0.0) -> void:
	var node := Fx.mesh(level_root, Fx.sphere(0.2), Fx.mat(color, 5.0, true), to3(from, 1.0))
	eprojs.append({"node": node, "pos": from, "vel": Vector2.from_angle(angle) * speed, "r": 0.25, "dmg": dmg, "t": 0.0, "max": 3.0, "chill": chill})


func _update_eprojs(delta: float) -> void:
	var p := player
	for pr in eprojs:
		pr.t += delta
		pr.pos += pr.vel * delta
		pr.node.position = to3(pr.pos, 1.0)
		var gone: bool = pr.t > pr.max or map.solid_at(pr.pos)
		if not gone and not p.dead and p.invuln <= 0.0 and pr.pos.distance_to(p.pos) < pr.r + p.r:
			gone = true
			damage_player(pr.dmg)
			p.chill = maxf(p.chill, pr.chill)
		if not gone:
			for a in _allies():
				if pr.pos.distance_to(a.pos) < pr.r + a.r:
					gone = true
					damage_ally(a, pr.dmg)
					break
		if gone:
			pr.t = pr.max + 1.0
			pr.node.queue_free()
	eprojs = eprojs.filter(func(pr): return pr.t <= pr.max)


func _update_boss(e: Enemy, delta: float, d: float) -> void:
	var p := player
	if hud.boss != e:
		hud.set_boss(e)
		hud.message("%s が目覚めた！" % e.display_name, Color("#ff6040"))
	if not e.charge.is_empty():
		_update_charge(e, delta)
		return
	var enraged := e.life < e.max_life * 0.5
	if enraged and not e.enraged:
		e.enraged = true
		hud.message("%s が激昂した！" % e.display_name, Color("#ff6040"))
		Fx.burst(level_root, to3(e.pos, 1.5), 50, e.t.color.lightened(0.4), 8.0)
		shake = maxf(shake, 8.0)
	e.act_t -= delta
	if e.act_t <= 0.0:
		call("_boss_" + e.type, e, d, enraged)
		return
	if e.type == "witch":
		# keeps her distance and pelts the player from range
		var sp: float = e.speed * (0.5 if e.slow > 0.0 else 1.0)
		if d < 8.8:
			e.pos = map.move_circle(e.pos, e.r, (e.pos - p.pos).normalized() * sp * delta)
		elif d > 15.2 or not e.sees:
			_chase(e, delta)
	elif d > e.r + p.r + 1.2:
		_chase(e, delta)
	elif e.atk_cd <= 0.0:
		e.atk_cd = 1.6
		e.windup = 0.4
		e.pending = func():
			if p.pos.distance_to(e.pos) < e.r + p.r + 1.6:
				damage_player(e.dmg)
	e.face = (p.pos - e.pos).angle()


## the deep warden: ground slam, a ring of fire bolts, or summoned imps
func _boss_boss(e: Enemy, d: float, enraged: bool) -> void:
	e.act_t = 2.2 if enraged else 3.0
	var roll := randf()
	if d < 9.0 and roll < 0.45:
		e.windup = 1.0
		e.pending = func(): pass
		add_tele(e.pos, 7.0, 1.0, true, func():
			if e.dead:
				return
			_explosion(e.pos, 7.0, Color("#ff4632"))
			_damage_area(e.pos, 7.0, e.dmg * 1.7))
	elif roll < 0.8:
		e.windup = 0.7
		e.pending = func():
			var n := 26 if enraged else 18
			var off := randf() * TAU
			for i in n:
				_enemy_shot(e.pos, off + float(i) / n * TAU, 10.0, e.dmg * 0.8, Color("#ff5040"))
		Fx.burst(level_root, to3(e.pos, 1.5), 20, Color("#ff4030"), 6.0)
	else:
		e.windup = 0.6
		e.pending = func(): _summon_around(e, "imp", 6 if enraged else 4, 2.8)


## the burning colossus: a charge that leaves fire behind, meteor rain, or an eruption
func _boss_colossus(e: Enemy, d: float, enraged: bool) -> void:
	var p := player
	e.act_t = 2.0 if enraged else 2.8
	var roll := randf()
	if roll < 0.35 and d > 4.8:
		var a := (p.pos - e.pos).angle()
		var length := minf(22.4, d + 5.6)
		e.windup = 0.8
		e.pending = func(): e.charge = {"dir": Vector2.from_angle(a), "left": length, "hit": false, "trail": 0.0}
		add_line_tele(e.pos, a, length, e.r * 2.0, 0.8)
	elif roll < 0.7:
		for i in (8 if enraged else 5):
			var at := p.pos + (Vector2(randf_range(-9.2, 9.2), randf_range(-9.2, 9.2)) if i > 0 else Vector2.ZERO)
			var dmg := e.dmg
			add_tele(at, 3.0, 1.0 + i * 0.15, true, func():
				_explosion(at, 3.0, Color("#ff6e28"))
				_damage_area(at, 3.0, dmg * 1.1)
				_add_hazard(at, 2.4, 2.5, dmg * 0.3))
		e.windup = 0.5
		e.pending = func(): pass
		Fx.burst(level_root, to3(e.pos, 3.0), 30, Color("#ff7030"), 8.0)
	else:
		e.windup = 0.9
		e.pending = func(): pass
		add_tele(e.pos, 6.6, 0.9, true, func():
			if e.dead:
				return
			_explosion(e.pos, 6.6, Color("#ff5a1e"))
			_damage_area(e.pos, 6.6, e.dmg * 1.5)
			var n := 16 if enraged else 10
			var off := randf() * TAU
			for i in n:
				_enemy_shot(e.pos, off + float(i) / n * TAU, 12.0, e.dmg * 0.6, Color("#ff7828")))


func _update_charge(e: Enemy, delta: float) -> void:
	var p := player
	var c := e.charge
	var step := minf(c.left, 30.4 * delta)
	c.left -= step
	while step > 0.0:
		var s := minf(0.32, step)
		step -= s
		var before := e.pos
		e.pos = map.move_circle(e.pos, e.r, c.dir * s)
		if e.pos.distance_to(before) < 0.02:
			c.left = 0.0   # ran into a wall
			break
		c.trail += s
		if c.trail > 1.8:
			c.trail = 0.0
			_add_hazard(e.pos, 1.7, 2.2, e.dmg * 0.3)
	e.face = c.dir.angle()
	if not c.hit and e.pos.distance_to(p.pos) < e.r + p.r + 0.25:
		c.hit = true
		damage_player(e.dmg * 1.4)
	if c.left <= 0.0:
		e.charge = {}
		_explosion(e.pos, 3.6, Color("#ff6e28"))
		if not c.hit and e.pos.distance_to(p.pos) < 3.6 + p.r:
			damage_player(e.dmg * 0.8)


## the frost witch: blinks around, throws fans of chilling shards, freezes the ground, calls archers
func _boss_witch(e: Enemy, d: float, enraged: bool) -> void:
	var p := player
	e.act_t = 1.7 if enraged else 2.4
	var roll := randf()
	if roll < 0.25:
		for i in 25:
			var at := p.pos + Vector2.from_angle(randf() * TAU) * randf_range(9.2, 13.2)
			if map.circle_hits(at, e.r) or not map.los(at, p.pos):
				continue
			Fx.burst(level_root, to3(e.pos, 1.2), 30, Color("#9fe8ff"), 6.0)
			e.pos = at
			Fx.burst(level_root, to3(at, 1.2), 30, Color("#9fe8ff"), 6.0)
			break
		e.act_t = 0.6
	elif roll < 0.6:
		e.windup = 0.5
		e.pending = func():
			var n := 11 if enraged else 7
			var base := (p.pos - e.pos).angle()
			for i in n:
				_enemy_shot(e.pos, base + (i - (n - 1) / 2.0) * 0.13, 15.6, e.dmg * 0.7, Color("#96e6ff"), 2.0)
		Fx.burst(level_root, to3(e.pos, 1.5), 15, Color("#bff4ff"), 4.0)
	elif roll < 0.88:
		for i in (5 if enraged else 3):
			var at := p.pos + (Vector2(randf_range(-6.8, 6.8), randf_range(-6.8, 6.8)) if i > 0 else Vector2.ZERO)
			var dmg := e.dmg
			add_tele(at, 3.6, 1.1, true, func():
				_explosion(at, 3.6, Color("#8cdcff"))
				if at.distance_to(p.pos) < 3.6 + p.r:
					damage_player(dmg)
					p.chill = 2.5)
		e.windup = 0.4
		e.pending = func(): pass
	else:
		e.windup = 0.6
		e.pending = func(): _summon_around(e, "archer", 5 if enraged else 3, 3.2)


func _summon_around(e: Enemy, kind: String, n: int, radius: float) -> void:
	if e.dead:
		return
	for i in n:
		var at := e.pos + Vector2.from_angle(randf() * TAU) * radius
		if map.circle_hits(at, Data.ENEMY_TYPES[kind].r):
			continue
		var m := _make_enemy(kind, at, e.pack)
		m.aggro = true
		Fx.burst(level_root, to3(at, 0.5), 10, Data.ENEMY_TYPES[kind].color, 4.0)


func _separate_enemies() -> void:
	var p := player
	var n := enemies.size()
	for i in n:
		var a := enemies[i]
		if a.dead or not a.aggro:
			continue
		for j in range(i + 1, n):
			var b := enemies[j]
			if b.dead:
				continue
			var diff := b.pos - a.pos
			var rr := a.r + b.r
			var d2 := diff.length_squared()
			if d2 >= rr * rr or d2 == 0.0:
				continue
			var dd := sqrt(d2)
			var push := diff / dd * (rr - dd) / 2.0
			a.pos = map.move_circle(a.pos, a.r, -push)
			b.pos = map.move_circle(b.pos, b.r, push)
		var dp := a.pos - p.pos
		var pr := a.r + p.r
		if dp.length_squared() < pr * pr and dp.length_squared() > 0.0:
			var dl := dp.length()
			a.pos = map.move_circle(a.pos, a.r, dp / dl * (pr - dl))


# =================== cinder altars ===================
## a few dormant altars in the rooms of a new map (more with renown, and two more per league beacon)
func _place_altars() -> void:
	var f := Farm.state(league())
	var n := Farm.altars_for_map(f)
	var rooms := map.rooms.filter(func(r): return r != map.start and r != map.boss_room)
	rooms.shuffle()
	for room in rooms:
		if altars.size() >= n:
			break
		for tries in 12:
			var tx: int = randi_range(room.x + 2, room.x + room.w - 3) if tries > 0 else int(room.cx)
			var ty: int = randi_range(room.y + 2, room.y + room.h - 3) if tries > 0 else int(room.cy)
			if map.is_wall(tx, ty) or map.circle_hits(map.tile_center(tx, ty), 1.4):
				continue
			place_altar(map.tile_center(tx, ty))
			break


## a dormant altar at `at`, kindled from its [B] label
func place_altar(at: Vector2) -> Dictionary:
	var a := {"pos": at, "state": "dormant", "vow": "", "wave": 0, "spawned": [], "t": 0.0, "wave_t": 0.0, "plan": {}}
	a.merge(_build_altar(at, false))
	altars.append(a)
	interacts.append({"kind": "altar", "name": "燼火の祭壇", "pos": at, "r": 1.4, "altar": a})
	var t := Vector2i(floori(at.x / T), floori(at.y / T))
	map.blocked[map.idx(t.x, t.y)] = 1
	return a


## a dark stone dais with four standing stones and a brazier; `lit` for the hideout forge
func _build_altar(at: Vector2, lit: bool) -> Dictionary:
	var root := Node3D.new()
	root.position = to3(at)
	level_root.add_child(root)
	var dais := CylinderMesh.new()
	dais.top_radius = 1.25
	dais.bottom_radius = 1.5
	dais.height = 0.35
	dais.radial_segments = 8
	Fx.mesh(root, dais, Fx.mat(Color("#2e2622")), Vector3(0, 0.17, 0))
	for k in 4:
		var stone := Fx.mesh(root, Fx.box(Vector3(0.32, 1.5, 0.32)), Fx.mat(Color("#3a302a")), to3(Vector2.from_angle(k * PI / 2 + PI / 4) * 1.15, 0.9))
		stone.rotation.y = k * PI / 2 + PI / 4
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.6
	bowl.bottom_radius = 0.25
	bowl.height = 0.5
	Fx.mesh(root, bowl, Fx.mat(Color("#4a3a30")), Vector3(0, 0.6, 0))
	var flame_mat := Fx.mat(Farm.COLOR, 5.0 if lit else 0.6, true)
	var flame := Fx.mesh(root, Fx.sphere(0.42), flame_mat, Vector3(0, 1.05, 0))
	flame.scale = Vector3(1.0, 1.4, 1.0) if lit else Vector3(0.6, 0.4, 0.6)
	var light := OmniLight3D.new()
	light.light_color = Farm.COLOR
	light.light_energy = 2.6 if lit else 0.7
	light.omni_range = 9.0 if lit else 4.0
	light.position.y = 1.6
	root.add_child(light)
	if lit:
		var tw := flame.create_tween().set_loops()
		tw.tween_property(flame, "scale:y", 1.7, 0.5).set_trans(Tween.TRANS_SINE)
		tw.tween_property(flame, "scale:y", 1.3, 0.5).set_trans(Tween.TRANS_SINE)
	return {"node": root, "flame": flame, "flame_mat": flame_mat, "light": light}


## light the altar with a vow: a ring marks the ground and the first wave comes in
func kindle_altar(a: Dictionary, vow_id: String) -> void:
	if a.state != "dormant":
		return
	var v := Farm.vow(vow_id)
	a.state = "active"
	a.vow = vow_id
	a.plan = Farm.plan(floor_level, vow_id)
	interacts = interacts.filter(func(o): return o.get("altar") != a)
	a.flame.scale = Vector3(1.2, 1.8, 1.2)
	a.flame_mat.emission_energy_multiplier = 6.0
	a.light.light_energy = 3.2
	a.light.omni_range = 12.0
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = Farm.RADIUS - 0.12
	ring_mesh.outer_radius = Farm.RADIUS
	ring_mesh.rings = 64
	a.ring = Fx.mesh(a.node, ring_mesh, Fx.mat(Color(Farm.COLOR, 0.7), 3.0, true), Vector3(0, 0.05, 0))
	Fx.ring(level_root, to3(a.pos), Farm.RADIUS, Farm.COLOR, 0.6, false)
	Fx.burst(level_root, to3(a.pos, 1.2), 40, Farm.COLOR, 7.0)
	shake = maxf(shake, 5.0)
	hud.message("燼火の祭壇に点火した — %s" % v.name, Farm.COLOR)
	if a.plan.timer > 0.0:
		hud.message("%d秒以内にすべての波を倒せ！" % int(a.plan.timer), Color("#ffb070"))
	_altar_wave(a)


## the next wave around the altar; the last one brings the guardians
func _altar_wave(a: Dictionary) -> void:
	var v := Farm.vow(a.vow)
	var last: bool = a.wave == a.plan.waves.size() - 1
	var pool := [{"k": "imp", "w": 3.0}, {"k": "ghoul", "w": 3.0}, {"k": "archer", "w": 2.0}, {"k": "shaman", "w": 1.2},
		{"k": "brute", "w": 0.8 if floor_level >= 2 else 0.3}]
	var pid: int = 10000 + altars.find(a) * 100 + a.wave
	var count: int = a.plan.waves[a.wave]
	for i in count + (int(a.plan.guards) if last else 0):
		var guard: bool = i >= count
		var at := _altar_spot(a.pos)
		var e := _make_enemy("brute" if guard else _weighted(pool).k, at, pid, Data.ELITE_AFFIXES.pick_random() if guard else {})
		e.set_meta("cinder", true)
		e.max_life *= float(v.get("life", 1.0)) * (3.0 if guard else 1.15)
		e.life = e.max_life
		e.dmg *= float(v.get("dmg", 1.0))
		e.aggro = true
		if guard:
			e.display_name = "燼魂の守り手"
			e.xp *= 2.0
		Fx.burst(level_root, to3(at, 0.6), 10, Farm.COLOR, 4.0)
		a.spawned.append(e)
	a.wave += 1
	a.wave_t = 0.0
	hud.message("第%d波（全%d波）%s" % [a.wave, a.plan.waves.size(), "　燼魂の守り手が現れた！" if last else ""], Farm.COLOR)


## a free floor spot on the ring around an altar
func _altar_spot(c: Vector2) -> Vector2:
	for k in 16:
		var at := c + Vector2.from_angle(randf() * TAU) * randf_range(4.0, Farm.RADIUS)
		if not map.circle_hits(at, 0.9) and map.los(c, at):
			return at
	return map.move_circle(c, 0.6, Vector2.from_angle(randf() * TAU) * 2.5)


func altar_alive(a: Dictionary) -> int:
	return a.spawned.filter(func(e): return is_instance_valid(e) and not e.dead).size()


func _update_altars(delta: float) -> void:
	for a in altars:
		if a.state != "active":
			continue
		a.t += delta
		a.wave_t += delta
		a.ring.rotate_y(delta * 0.4)
		var alive := altar_alive(a)
		if a.plan.timer > 0.0 and a.t > a.plan.timer and alive > 0:
			_end_altar(a, false)
		elif a.wave < a.plan.waves.size() and (alive <= 2 or a.wave_t >= Farm.WAVE_TIME):
			_altar_wave(a)
		elif a.wave >= a.plan.waves.size() and alive == 0:
			_end_altar(a, true)


## every wave down: crystals, items and renown; a trial run out of time leaves the altar cold
func _end_altar(a: Dictionary, won: bool) -> void:
	a.state = "done" if won else "failed"
	a.ring.queue_free()
	a.flame.scale = Vector3(0.5, 0.3, 0.5)
	a.flame_mat.emission_energy_multiplier = 0.4
	a.light.light_energy = 0.4
	if not won:
		for e in a.spawned:
			if is_instance_valid(e) and not e.dead:
				e.remove_meta("cinder")   # the stragglers stay, but drop no crystals
		hud.message("燼火が燃え尽きた……（時間切れ）", Color("#ff8a70"))
		return
	var f := Farm.state(league())
	var rw := Farm.reward(floor_level, a.vow, f)
	var left: int = rw.cinder
	while left > 0:
		var n := mini(left, 5)
		_drop_currency(Farm.KEY, n, a.pos + Vector2.from_angle(randf() * TAU) * 1.6)
		left -= n
	for i in rw.items:
		drop_item(Items.generate(floor_level + 1, rw.rarity, 2 if i == 0 else -1), a.pos + Vector2.from_angle(randf() * TAU) * 1.8)
	_drop_currency("ember", roundi(randf_range(8, 14) * floor_level * mod_fx.gold), a.pos + Vector2(0, 1.8))
	a.reward = rw
	var up := Farm.credit(f, rw.renown)
	Fx.burst(level_root, to3(a.pos, 1.4), 60, Color("#ffd27a"), 9.0)
	Fx.ring(level_root, to3(a.pos), 6.0, Color("#ffd27a"), 0.7, false)
	hud.message("燼火の祭壇を鎮めた！ %s 燼晶 ×%d　位階 +%d" % [Farm.CURRENCY.icon, rw.cinder, rw.renown], Color("#ffd27a"))
	if up:
		hud.message("燼火の位階が %d に上がった（隠れ家の燼火の炉で確認）" % Farm.rank(f), Color("#ffe27a"))
	save_game()


## one line for the HUD while an altar burns
func altar_status() -> String:
	for a in altars:
		if a.state == "active":
			var s := "燼火の祭壇 第%d/%d波 残り%d体" % [a.wave, a.plan.waves.size(), altar_alive(a)]
			if a.plan.timer > 0.0:
				s += " ⏱%d秒" % ceili(maxf(0.0, a.plan.timer - a.t))
			return s
	return ""


## the cinder forge: spend the league's crystals; "" when it went through, else why not
func forge_buy(id: String) -> String:
	var f := Farm.state(league())
	var p := player
	var lvl := maxi(floor_level, atlas.hideout_level())
	if id in ["rare", "legend"] and p.bag.size() >= Player.BAG_SIZE:
		return "インベントリが一杯です"
	var missing := Data.SUPPORTS.filter(func(g): return not g.id in p.gems)
	if id == "gem" and missing.is_empty():
		return "サポートジェムはすべて持っている"
	var err := Farm.buy(f, id)
	if err != "":
		return err
	match id:
		"rare":
			pickup_item(Items.generate(lvl + 1, 1.0, 2), p.pos)
		"legend":
			pickup_item(Items.generate(lvl + 1, 0.0, 3), p.pos)
		"chaos":
			p.cur.chaos += 3
		"divine":
			p.cur.divine += 1
		"gem":
			unlock_gem(missing.pick_random().id)
		"beacon":
			f.beacons += 1
	hud.message("燼火の炉：%s と交換した" % Farm.offer(id).name, Farm.COLOR)
	hud.refresh_inventory()
	save_game()
	return ""


# =================== portal ===================
func _open_portal(at: Vector2) -> void:
	var root := Node3D.new()
	root.position = to3(at)
	level_root.add_child(root)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.9
	ring_mesh.outer_radius = 1.1
	var ring := Fx.mesh(root, ring_mesh, Fx.mat(Color("#9a70ff"), 5.0, true), Vector3(0, 1.4, 0))
	ring.rotation.x = PI / 2
	ring.rotation.y = CAM_YAW
	var light := OmniLight3D.new()
	light.light_color = Color("#a080ff")
	light.light_energy = 3.0
	light.omni_range = 8.0
	light.position.y = 1.5
	root.add_child(light)
	portal = {"node": root, "pos": at, "ring": ring}


func _update_portal(delta: float) -> void:
	if portal.is_empty():
		return
	portal.ring.rotate_object_local(Vector3.UP, delta * 2.0)
	if not player.dead and player.pos.distance_to(portal.pos) < 1.3:
		_collect_nearby(28.0)
		complete_map()


# =================== loot ===================
func _drop_loot(e: Enemy) -> void:
	var ilvl := floor_level + (1 if not e.elite.is_empty() else 0) + (2 if e.boss else 0)
	var n := 0
	var boost: float = mod_fx.rarity
	if e.boss:
		n = 4
		boost += 2.5
	elif not e.elite.is_empty():
		n = randi_range(1, 2)
		boost += 1.2
	elif randf() < 0.13 * mod_fx.quantity:
		n = 1
	for i in n:
		var force := (3 if randf() < 0.35 + mod_fx.legend else 2) if e.boss and i == 0 else -1
		drop_item(Items.generate(ilvl, boost, force), e.pos)
	if randf() < (1.0 if e.boss or not e.elite.is_empty() else 0.25):
		for i in (6 if e.boss else 3 if not e.elite.is_empty() else 1):
			_drop_currency("ember", roundi(randf_range(2, 6) * floor_level * (2 if not e.elite.is_empty() else 1) * mod_fx.gold), e.pos)
	var cn := randi_range(3, 5) if e.boss else (randi_range(1, 2) if not e.elite.is_empty() and randf() < 0.5 else (1 if randf() < 0.035 else 0))
	for i in cn:
		_drop_currency(_weighted(Data.CURRENCIES.filter(func(c): return c.w > 0.0)).k, 1, e.pos)
	if randf() < (0.8 if e.boss else (0.25 if not e.elite.is_empty() else 0.01)):
		_drop_gem(e.pos)


## a support gem the player doesn't own yet
func _drop_gem(at: Vector2) -> void:
	var missing := Data.SUPPORTS.filter(func(g): return not g.id in player.gems)
	if missing.is_empty():
		return
	var pos := _scatter(at)
	var node := Fx.mesh(level_root, Fx.box(Vector3(0.3, 0.3, 0.3)), Fx.mat(Data.GEM_COLOR, 4.0), to3(pos, 0.35))
	node.rotation = Vector3(0.7, 0.0, 0.7)
	drops.append({"k": "gem", "n": 1, "gem": missing.pick_random().id, "pos": pos, "node": node})


func unlock_gem(id: String) -> void:
	var p := player
	if id in p.gems:
		p.cur.ember += 40 * floor_level
		return
	p.gems.append(id)
	var g := Data.support(id)
	hud.message("サポートジェム「%s」を入手！（%sでリンク）" % [g.name, Keybinds.text("skills")], g.color)
	hud.skill_ui.refresh()


func _scatter(at: Vector2) -> Vector2:
	var p := at + Vector2.from_angle(randf() * TAU) * randf_range(0.4, 1.8)
	return at if map.solid_at(p) else p


func drop_item(it: Dictionary, at: Vector2) -> void:
	if player.item_action(it) == "hide":
		_sell_hidden(it, at)
		return
	var pos := _scatter(at)
	var col: Color = Data.RARITY[it.rarity].color
	var root := Node3D.new()
	root.position = to3(pos)
	level_root.add_child(root)
	var gem := Fx.mesh(root, Fx.box(Vector3(0.35, 0.35, 0.35)), Fx.mat(col, 1.5), Vector3(0, 0.3, 0))
	gem.rotation = Vector3(0.6, 0.4, 0.6)
	if it.rarity >= 2:
		var beam := CylinderMesh.new()
		beam.top_radius = 0.05
		beam.bottom_radius = 0.12
		beam.height = 4.0
		var bm := Fx.mat(Color(col, 0.35), 3.0, true)
		bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		Fx.mesh(root, beam, bm, Vector3(0, 2.0, 0))
		var light := OmniLight3D.new()
		light.light_color = col
		light.light_energy = 1.0
		light.omni_range = 3.0
		light.position.y = 0.6
		root.add_child(light)
	ground.append({"item": it, "pos": pos, "node": root, "gem": gem})


func _drop_currency(k: String, n: int, at: Vector2) -> void:
	if n <= 0:
		return
	var c := Farm.CURRENCY if k == Farm.KEY else Data.currency(k)
	var pos := _scatter(at)
	var shard := SphereMesh.new()
	shard.radius = 0.14 if k == "ember" else 0.2
	shard.height = shard.radius * 2.6
	shard.radial_segments = 4
	shard.rings = 1
	var node := Fx.mesh(level_root, shard, Fx.mat(c.color, 3.0), to3(pos, 0.3))
	drops.append({"k": k, "n": n, "pos": pos, "node": node})


func _update_loot(delta: float) -> void:
	var p := player
	if p.dead:
		return
	for g in ground:
		g.gem.rotate_y(delta * 1.5)
		if g.pos.distance_to(p.pos) > 1.3:
			continue
		if not pickup_item(g.item, g.pos):
			if time - g.get("full_t", -9.0) > 2.0:
				g.full_t = time
				hud.message("インベントリが一杯です（%s）" % Keybinds.text("inventory"), Color("#ff8080"))
			continue
		_take(g)
	ground = ground.filter(func(g): return not g.get("taken", false))
	for d in drops:
		d.node.rotate_y(delta * 3.0)
		var dist: float = d.pos.distance_to(p.pos)
		if dist < 4.5:
			d.pos = d.pos.move_toward(p.pos, delta * 14.0)
			d.node.position = to3(d.pos, 0.3)
		if dist < 0.8:
			_take(d)
	drops = drops.filter(func(d): return not d.get("taken", false))


## take an item into the bag, or sell it on the spot if the filter says so; false when the bag is full
func pickup_item(it: Dictionary, at: Vector2, by_pet := false, quiet := false) -> bool:
	var p := player
	if p.item_action(it) == "sell":
		var g := Items.sell_price(it)
		p.cur.ember += g
		add_text(at, "自動売却 +%d" % g, Color("#ffcf3a"), 13)
		return true
	if p.bag.size() >= Player.BAG_SIZE:
		return false
	p.bag.append(it)
	if not quiet or it.rarity >= 2:
		hud.message(("%sが %s を拾ってきた" % [Pet.NAME, it.name]) if by_pet else ("%s を拾った" % it.name), Data.RARITY[it.rarity].color)
	hud.refresh_inventory()
	return true


## remove a ground item or currency drop from the world; currency and gems are credited here
func _take(g: Dictionary) -> void:
	g.taken = true
	g.node.queue_free()
	if g.has("item"):
		return
	if g.k == "gem":
		unlock_gem(g.gem)
		return
	if g.k == Farm.KEY:   # cinder crystals belong to the league, not the character
		Farm.state(league()).cinder += g.n
		hud.message("%s %s ×%d を拾った（所持 %d）" % [Farm.CURRENCY.icon, Farm.CURRENCY.name, g.n, Farm.state(league()).cinder], Farm.COLOR)
		return
	player.cur[g.k] += g.n
	if g.k != "ember":
		var c := Data.currency(g.k)
		hud.message("%s を拾った" % c.name, c.color)


## items the filter hides never reach the ground: they are sold as they drop
func _sell_hidden(it: Dictionary, at: Vector2) -> void:
	var g := Items.sell_price(it)
	player.cur.ember += g
	add_text(at, "+%d" % g, Color("#b8a060"), 12)


## after the filter changes, sell whatever on the floor is now hidden
func sell_hidden_ground() -> void:
	for g in ground:
		if player.item_action(g.item) == "hide":
			_sell_hidden(g.item, g.pos)
			_take(g)
	ground = ground.filter(func(g): return not g.get("taken", false))


## stepping into the portal also gathers the loot left around the map
func _collect_nearby(radius: float) -> void:
	var p := player
	var n := 0
	var cur := 0
	for d in drops:
		if d.pos.distance_to(p.pos) < radius:
			_take(d)
			cur += 1
	var left := 0
	for g in ground:
		if g.pos.distance_to(p.pos) > radius:
			continue
		if pickup_item(g.item, g.pos, false, true):
			_take(g)
			n += 1
		else:
			left += 1
	drops = drops.filter(func(d): return not d.get("taken", false))
	ground = ground.filter(func(g): return not g.get("taken", false))
	if n > 0 or cur > 0:
		hud.message("ポータル周辺のアイテム %d 点とカレンシー %d 個を回収した" % [n, cur], Color("#ffd36a"))
	if left > 0:
		hud.message("インベントリが一杯で %d 点を拾えなかった" % left, Color("#ff8080"))


# =================== pet ===================
func _place_pet() -> void:
	pet.pos = player.pos + Vector2(-1.2, 0.4)
	if map.circle_hits(pet.pos, pet.r):
		pet.pos = player.pos
	pet.target = {}
	pet.home = Vector2.INF
	pet.sync_node(0.0, false)


## the fox wanders around the player and fetches currency and items it can see
func _update_pet(delta: float) -> void:
	var p := player
	if p.dead:
		pet.moving = false
		pet.animate(delta)
		return
	var dp := pet.pos.distance_to(p.pos)
	if dp > 26.0:
		Fx.burst(level_root, to3(pet.pos, 0.5), 12, Color("#ffd36a"), 4.0)
		pet.pos = p.pos
		pet.target = {}
		Fx.burst(level_root, to3(pet.pos, 0.5), 12, Color("#ffd36a"), 4.0)
	if pet.target.get("taken", false):
		pet.target = {}
	pet.scan_t -= delta
	if pet.target.is_empty() and pet.scan_t <= 0.0:
		pet.scan_t = 0.3
		var bag_full := p.bag.size() >= Player.BAG_SIZE
		var reach := 15.2 * (1.0 + atlas.val("fox") / 100.0)
		var best := {}
		var bd := INF
		var cands := drops.duplicate()
		for g in ground:
			if not bag_full or p.item_action(g.item) == "sell":
				cands.append(g)
		for g in cands:
			if g.get("pet_skip", false) or g.pos.distance_to(p.pos) > reach:
				continue
			var d: float = g.pos.distance_squared_to(pet.pos) * (1.0 if g.has("item") else 0.6)
			if d < bd and map.los(pet.pos, g.pos):
				bd = d
				best = g
		pet.target = best
		pet.stuck_t = 0.0
	var to: Vector2
	var sp: float
	if not pet.target.is_empty():
		to = pet.target.pos
		sp = 13.2
	else:
		pet.wander_t -= delta
		if pet.wander_t <= 0.0 or pet.home.x == INF:
			pet.wander_t = randf_range(1.2, 2.6)
			pet.home = Vector2.from_angle(randf() * TAU) * randf_range(1.6, 4.4)
		to = p.pos + pet.home
		sp = 13.2 if dp > 8.0 else 5.6
	var diff := to - pet.pos
	var d := diff.length()
	pet.moving = d > 0.16
	if pet.moving:
		var s := minf(d, sp * delta)
		var before := pet.pos
		pet.pos = map.move_circle(pet.pos, pet.r, diff / d * s)
		pet.face = diff.angle()
		pet.stuck_t = pet.stuck_t + delta if pet.pos.distance_to(before) < s * 0.3 else 0.0
		if pet.stuck_t > 1.0:
			if not pet.target.is_empty():
				pet.target.pet_skip = true
			pet.target = {}
			pet.home = Vector2.INF
			pet.stuck_t = 0.0
	pet.animate(delta)
	var g := pet.target
	if not g.is_empty() and g.pos.distance_to(pet.pos) < 0.7:
		pet.target = {}
		if g.has("item"):
			if not pickup_item(g.item, pet.pos, true):
				return
			_take(g)
			ground = ground.filter(func(q): return not q.get("taken", false))
		else:
			_take(g)
			drops = drops.filter(func(q): return not q.get("taken", false))
		Fx.burst(level_root, to3(pet.pos, 0.6), 8, Color("#ffe8a0"), 3.0)


# =================== progression ===================
## re-apply what the atlas passives change outside a run
func passives_changed() -> void:
	Items.discount = 1.0 - atlas.val("haggle") / 100.0
	player.recalc()


# =================== save ===================
## each character's state lives in Profiles (one file for every character and the league stashes)


## the league of the character being played; smoke runs play standard
func league() -> String:
	return Profiles.current().get("league", Profiles.STANDARD)


## leave the current character for the character screen (or straight into `id`): the scene restarts clean
func switch_char(id := "") -> void:
	save_game()
	Profiles.active = id
	get_tree().reload_current_scene()


func save_game() -> void:
	var ch := Profiles.current()
	if smoke or ch.is_empty():
		return
	ch.data = save_data()
	Profiles.save_all()


## the playing character's state, as saved in their profile
func save_data() -> Dictionary:
	var p := player
	return {"floor": floor_level, "level": p.level, "xp": p.xp, "potions": p.potions,
		"equip": p.equip, "bag": p.bag, "cur": p.cur, "atlas": atlas.to_dict(), "shop": shop,
		"slots": p.slots, "links": p.links, "gems": p.gems, "talent_pts": p.talent_pts, "talents": p.talents, "filter": p.filter,
		"cls": p.cls, "asc": p.asc, "asc_ranks": p.asc_ranks, "asc_cores": p.asc_cores, "auras": p.auras}


func load_game() -> bool:
	var data = Profiles.current().get("data", {})
	if typeof(data) != TYPE_DICTIONARY or data.is_empty():
		return false
	apply_save(data)
	return true


func apply_save(data: Dictionary) -> void:
	var p := player
	floor_level = int(data.get("floor", 1))
	p.level = int(data.get("level", 1))
	p.xp = int(data.get("xp", 0))
	p.potions = int(data.get("potions", 3))
	p.equip = {}
	for slot in data.get("equip", {}):
		p.equip[slot] = Items.normalize(data.equip[slot])
	p.bag = data.get("bag", []).map(func(it): return Items.normalize(it))
	for k in data.get("cur", {}):
		p.cur[k] = int(data.cur[k])
	var sl: Array = data.get("slots", [])
	if sl.size() == Data.SLOT_COUNT and sl.all(func(id): return Data.SKILLS.has(id)):
		p.slots = sl
	var ln: Array = data.get("links", [])
	if ln.size() == Data.SLOT_COUNT:
		p.links = ln.map(func(l): return Array(l).filter(func(id): return not Data.support(id).is_empty()))
	p.gems = Array(data.get("gems", Data.DEFAULT_GEMS)).filter(func(id): return not Data.support(id).is_empty())
	p.talent_pts = int(data.get("talent_pts", 0))
	var tl: Dictionary = data.get("talents", {})
	for t in Data.talents():
		p.talents[t.k] = clampi(int(tl.get(t.k, 0)), 0, t.max)
	# only an ascendancy of the character's base class comes back (Profiles.normalize keeps them matched)
	var a := Data.ascendancy(str(data.get("asc", "")))
	p.asc = ""
	p.asc_ranks = {}
	p.asc_cores = ["", "", ""]
	if not a.is_empty() and a.k in Data.base_class(p.cls).ascs:
		p.asc = a.k
		var ar: Dictionary = data.get("asc_ranks", {})
		for n in a.minors:
			if ar.has(n.id):
				p.asc_ranks[n.id] = clampi(int(ar[n.id]), 0, n.max)
		var ac: Array = data.get("asc_cores", [])
		for i in mini(ac.size(), a.cores.size()):
			if a.cores[i].any(func(c): return c.id == ac[i]):
				p.asc_cores[i] = ac[i]
	var fl: Dictionary = data.get("filter", {})
	var fr: Array = fl.get("rarity", [])
	if fr.size() == Data.RARITY.size() and fr.all(func(v): return v in ["pick", "sell", "hide"]):
		p.filter.rarity = fr
	var fs: Dictionary = fl.get("slots", {})
	for k in fs:
		if p.filter.slots.has(k):
			p.filter.slots[k] = bool(fs[k])
	atlas.from_dict(data.get("atlas", {}))
	var sd: Dictionary = data.get("shop", {})
	if sd.has("items"):
		shop = {"level": int(sd.level), "items": sd.items.map(func(it): return Items.normalize(it))}
	# auras that were on come back on; recalc drops any that left the bar or no longer fit
	p.auras = Array(data.get("auras", [])).filter(func(id): return Data.SKILLS.has(id) and Data.SKILLS[id].has("aura") and id in p.slots)
	p.recalc(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
