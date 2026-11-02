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
var talents_refunded := false   # the loaded save still had talents; they came back as passive points
var smoke := false
var smoke_checks := 0            # `--smoke`: expectations tested so far, and the names of those that failed
var smoke_failed: Array = []
var portal: Dictionary = {}
var atlas := Atlas.new()
var area: Dictionary = Data.HIDEOUT   # current atlas node, or the hideout
var run_mods: Array = []
var mod_fx := Atlas.effects([])
var shop := {}
var interacts: Array = []   # hideout objects and dormant altars: {kind, name, pos, r}
var altars: Array = []      # cinder altars in this map (see Farm)
var seals: Array = []       # sealed monoliths in this map (see Seal)
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
		Profiles.read_only = true
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
		if talents_refunded:
			hud.message("タレントはパッシブツリーに変わりました。振っていたポイントはパッシブポイントとして戻っています（%s）" % Keybinds.text("talents"), Color("#ffe27a"))
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
			if kind in ["exchange_gear", "exchange_requests"]:   # the gear and request pages, with a few things in the bag to trade
				player.cur.ember = 2000
				player.cur.chaos = 40
				player.bag.append_array([Items.generate(12, 0.0, 3), Items.generate(12, 0.0, 2), Items.generate(12, 0.0, 1, "ring")])
				open_interact("exchange")
				hud.exchange_ui.page = "gear" if kind == "exchange_gear" else "requests"
				if kind == "exchange_gear":
					hud.exchange_ui.pick_bag(player.bag.size() - 3)
				hud.exchange_ui.refresh()
			if kind in ["merchant", "device", "stash", "exchange"]:
				open_interact(kind)
			if kind == "exchange":
				hud.exchange_ui.select("divine")
			elif kind == "skills":
				player.level = 8   # totem needs Lv 8
				player.gems.append_array(["multi", "totem"])
				player.links[1] = ["totem", "multi"]
				hud.skill_ui.open_slot(1)
			elif kind in ["talents", "status", "filter", "passives", "ascend", "ascend_pick"]:
				atlas.cleared = ["ash", "bone"]
				if kind == "talents":   # a level 24 character partway to the class's notable, a few points left
					player.level = 24
					for goal in _view_tree_goals(2):
						player.tree.append_array(PassiveTree.path_to(player.tree, player.cls, goal))
					player.recalc(true)
				if kind == "ascend":
					player.level = 14
					if cls_arg == "":
						player.set_class("sigil")
					player.asc = "storm"
					player.asc_ranks = {"storm_elem": 3, "storm_sight": 2, "storm_step": 1}
					player.asc_cores = ["shock", "crit_arc", ""]
					player.recalc(true)
				hud.toggle({"talents": hud.tree_ui, "status": hud.status_ui, "filter": hud.filter_ui, "passives": hud.passive_ui,
					"ascend": hud.asc_ui, "ascend_pick": hud.asc_ui}[kind])
			elif kind == "unique_tip":   # one unique of each drop tier in the bag, the rarest one's tooltip up
				var top := {}
				for t in Data.UNIQUE_TIERS.size():
					var l: Dictionary = Data.LEGENDARY.filter(func(q): return Data.unique_tier(q.name) == t and q.has("mods"))[0]
					top = Items.generate(20, 0.0, 3, "", l.name)
					player.bag.append(top)
				hud.toggle_inventory()
				get_tree().create_timer(2.0).timeout.connect(func(): hud.show_tip(Items.lines(top)))
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
			elif kind in ["tree_all", "jewels", "jewel_craft"]:   # the whole tree; a tree with jewels in and a ring jewel's ring grown; the jewel side with currencies
				_view_jewels(kind)
			elif kind.begins_with("tablets"):   # the board with a few tablets set and one picked: `tablets_full` with all 36 cells taken
				_view_tablets(kind)
			elif kind.begins_with("seal"):   # a sealed monolith next to the player: `seal_open` with its wardens out
				enter_map("ash")
				player.invuln = 1e9
				var sl := place_seal(_free_spot(player.pos, 5.0))
				if kind == "seal_open":
					get_tree().create_timer(1.0).timeout.connect(func(): break_seal(sl))
			elif kind == "line_craft":   # the inventory in one-line crafting with a rare ring picked
				var it := Items.generate(20, 0.0, 2, "ring")
				player.bag.append(it)
				for k in ["divine", "chaos", "whet", "transmute"]:
					player.cur[k] = 6
				hud.toggle_inventory()
				hud.inventory._pick_currency("line")
				hud.inventory._on_bag_click(player.bag.size() - 1)
			elif kind == "brand_tip":   # a rare chest with a special modifier, its tooltip up
				var it := Items.generate(20, 0.0, 2, "armor")
				Items.brand(it)
				player.bag.append(it)
				hud.toggle_inventory()
				get_tree().create_timer(2.0).timeout.connect(func(): hud.show_tip(Items.lines(it)))
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


## a smoke expectation group: each entry of `checks` must be true; a false one prints `SMOKE FAIL <tag> <name>`
## and fails the run (see the SMOKE RESULT line and the exit code at the end of `_smoke_test`)
func _expect(tag: String, checks: Dictionary) -> void:
	for k in checks:
		smoke_checks += 1
		if not checks[k]:
			smoke_failed.append("%s.%s" % [tag, k])
			print("SMOKE FAIL %s %s" % [tag, k])


## the data reference (docs/db): every unique, affix, class, ascendancy node, passive node and gem is in it,
## each unique on its own slot's page, and no line is left with an unfilled number
func _smoke_docs() -> void:
	var files := DataDocs.files()
	var pages := DataDocs.pages()
	var html: String = files["index.html"]
	var missing := []
	for l in Data.LEGENDARY:
		if not "| %s |" % l.name in files["uniques-%s.md" % l.slot] or not l.name in html:
			missing.append(l.name)
	var names := []
	for a in Data.AFFIXES.filter(func(x): return not x.slots.is_empty()):
		names.append(a.word)
	for bc in Data.CLASSES:
		names.append(bc.name)
		for k in bc.ascs:
			var a := Data.ascendancy(k)
			names.append(a.name)
			names.append_array(a.minors.map(func(n): return n.name))
			for tier in a.cores:
				names.append_array(tier.map(func(c): return c.name))
	for id in PassiveTree.order():
		names.append(PassiveTree.node(id).name)
	for id in Data.SKILL_ORDER:
		names.append(Data.SKILLS[id].name)
	names.append_array(Data.SUPPORTS.map(func(g): return g.name))
	var md := "".join(PackedStringArray(files.values()))
	for n in names:
		if not n in md:
			missing.append(n)
	var leftover := ["%d", "{v}", "+-", "%%"].filter(func(t): return t in md)
	var unique_rows: int = pages.filter(func(p): return p.file.begins_with("uniques-")).reduce(func(a, p): return a + p.sections.reduce(func(b, s): return b + s.rows.size(), 0), 0)
	var tree_rows: int = pages.filter(func(p): return p.file == "passives.md")[0].sections.reduce(func(b, s): return b + s.rows.size(), 0)
	print("SMOKE docs files=%d uniques=%d tree=%d/%d names=%d missing=%s leftover=%s" % [files.size(), unique_rows, tree_rows,
		PassiveTree.nodes().size(), names.size(), missing.slice(0, 5), leftover])
	_expect("docs", {"uniques": unique_rows == Data.LEGENDARY.size(), "tree": tree_rows == PassiveTree.nodes().size(),
		"missing": missing.is_empty(), "leftover": leftover.is_empty()})


## skill gems: a new character owns only the class's starting bar, other skills are found or bought, skills
## and support gems wait for their level, drops follow the area level, and older saves keep what their level taught
## unique drop tiers: every tier has uniques, the rarer tiers drop less often, roll stronger stat lines
## and sell for more
func _smoke_unique_tiers() -> void:
	var n := Data.UNIQUE_TIERS.size()
	var count := []
	var drops := []
	count.resize(n)
	count.fill(0)
	drops.resize(n)
	drops.fill(0)
	var pick := []
	pick.resize(n)
	for l in Data.LEGENDARY:
		var t := Data.unique_tier(l.name)
		count[t] += 1
		if pick[t] == null and l.has("mods"):
			pick[t] = l
	for i in 6000:
		drops[Data.unique_tier(Items.pick_legend(Data.LEGENDARY).name)] += 1
	var rate_down := true
	var stronger := true
	var dearer := true
	var share_drops := true
	for t in range(1, n):
		var now := float(drops[t]) / maxi(1, count[t])
		var before := float(drops[t - 1]) / maxi(1, count[t - 1])
		rate_down = rate_down and now < before
		share_drops = share_drops and drops[t] < drops[t - 1]
		var hi := {"name": pick[t].name, "ilvl": 1, "rarity": 3}
		var lo := {"name": pick[t - 1].name, "ilvl": 1, "rarity": 3}
		stronger = stronger and Items.roll_fixed(hi, "life", [20, 20]) > Items.roll_fixed(lo, "life", [20, 20]) 			and Items.roll_fixed(hi, "life", [-20, -20]) == Items.roll_fixed(lo, "life", [-20, -20])
		dearer = dearer and Trade.unique_tier(hi.name).base > Trade.unique_tier(lo.name).base 			and Items.sell_price(hi) > Items.sell_price(lo)
	var top := Items.generate(20, 0.0, 3)
	var tip: Array = Items.lines(top)
	print("SMOKE unique tiers count=%s drops=%s rate_down=%s share_down=%s stronger=%s dearer=%s tip=%s" % [count, drops,
		rate_down, share_drops, stronger, dearer, tip[1][0].begins_with("希少度：")])
	_expect("unique_tiers", {"all_tiers": not count.has(0), "rate_down": rate_down, "share_down": share_drops, "stronger": stronger,
		"dearer": dearer, "tip": tip[1][0].begins_with("希少度：")})


func _smoke_gems() -> void:
	var p := player
	var keep := [p.level, p.slots.duplicate(), p.links.duplicate(true), p.gems.duplicate(), p.skills.duplicate(), p.cur.ember, p.cls]
	p.set_class("sigil", true)
	p.level = 1
	var lv1 := Data.SKILL_ORDER.filter(func(id): return Data.SKILLS[id].lvl == 1)
	print("SMOKE gems kit owned=%s kit_ok=%s lv1_skills=%d all_kits_lv1=%s gem_lvls=%s" % [p.skills.size(), p.skills == Data.base_class("sigil").slots,
		lv1.size(), Data.CLASSES.all(func(c): return c.slots.all(func(id): return Data.SKILLS[id].lvl == 1) and c.gems.all(func(g): return Data.support(g).lvl == 1)),
		Data.SUPPORTS.all(func(g): return g.lvl >= 1 and g.lvl <= 18)])
	_expect("gems_kit", {"kit": p.skills == Data.base_class("sigil").slots, "kits_lv1": Data.CLASSES.all(func(c): return c.slots.all(func(id): return Data.SKILLS[id].lvl == 1)),
		"gem_lvls": Data.SUPPORTS.all(func(g): return g.lvl >= 1 and g.lvl <= 18)})
	# the panel refuses a skill gem not owned, then one owned but above the level, until the level is reached
	hud.skill_ui.open_slot(0)
	hud.skill_ui._assign("whirl")   # Lv 4
	var unowned_refused: bool = p.slots[0] == "firebolt"
	learn_skill("whirl")
	hud.skill_ui._assign("whirl")
	var low_refused: bool = p.slots[0] == "firebolt"
	p.level = 4
	hud.skill_ui._assign("whirl")
	print("SMOKE gems skill unowned_refused=%s low_refused=%s at_level=%s" % [unowned_refused, low_refused, p.slots[0]])
	_expect("gems_skill", {"unowned_refused": unowned_refused, "low_refused": low_refused, "at_level": p.slots[0] == "whirl"})
	# support gems: owned but under-levelled is refused, then links at its level
	unlock_gem("echo")   # Lv 10
	hud.skill_ui._toggle_gem("echo")
	var gem_low: bool = p.links[0].is_empty()
	p.level = 10
	p.recalc()
	hud.skill_ui._toggle_gem("echo")
	print("SMOKE gems support low_refused=%s at_level=%s" % [gem_low, p.links[0]])
	_expect("gems_support", {"low_refused": gem_low, "at_level": p.links[0] == ["echo"]})
	hud.close_panels()
	# drops: a gem the player lacks, needing at most the area level + GEM_DROP_AHEAD; picking it up owns it
	var lvls := []
	var got := 0
	for i in 30:
		_drop_gem(p.pos, 3)
		var dr: Dictionary = drops[-1]
		lvls.append((Data.SKILLS[dr.gem] if dr.skill else Data.support(dr.gem)).lvl)
		var had: bool = dr.gem in (p.skills if dr.skill else p.gems)
		_take(dr)
		drops.erase(dr)
		if not had and dr.gem in (p.skills if dr.skill else p.gems):
			got += 1
	print("SMOKE gems drop n=30 max_lvl=%d new=%d skills=%d gems=%d" % [lvls.max(), got, p.skills.size(), p.gems.size()])
	_expect("gems_drop", {"max_lvl": lvls.max() <= 3 + GEM_DROP_AHEAD, "new": got == 30})
	# the merchant: only gems up to level + GEM_AHEAD, priced by level, bought into the owned list
	p.level = 2
	p.cur.ember = 5000
	open_interact("merchant")
	var listed := Data.missing_gems(p.skills, p.gems, p.level + ShopUI.GEM_AHEAD)
	var want: String = listed.filter(func(g): return g.skill)[0].id
	hud.shop_ui._buy_skill(want)
	print("SMOKE gems shop listed_max=%d buttons=%d bought=%s paid=%d price_lv1=%d price_lv10=%d" % [listed.map(func(g): return Data.gem_info(g.skill, g.id).lvl).max(),
		hud.shop_ui.gem_grid.get_child_count(), want in p.skills, 5000 - p.cur.ember, Items.gem_price(1), Items.gem_price(10)])
	_expect("gems_shop", {"listed_max": listed.all(func(g): return Data.gem_info(g.skill, g.id).lvl <= p.level + ShopUI.GEM_AHEAD), "bought": want in p.skills,
		"paid": 5000 - p.cur.ember == Items.gem_price(Data.SKILLS[want].lvl), "price_rises": Items.gem_price(10) > Items.gem_price(1)})
	hud.close_panels()
	# saves: skills round-trip; a save from before skill gems keeps every skill its level taught,
	# and links above the level come off (the gems stay owned)
	p.level = 10
	var sd := save_data()
	apply_save(JSON.parse_string(JSON.stringify(sd)))
	var round_ok: bool = p.skills == sd.skills
	sd = save_data()
	sd.erase("skills")
	sd.level = 7
	sd.links = [["echo", "power"], [], [], [], [], []]
	apply_save(sd)
	print("SMOKE gems save round=%s migrated=%d expected=%d whirl=%s links0=%s echo_owned=%s" % [round_ok, p.skills.size(),
		Data.SKILL_ORDER.filter(func(id): return Data.SKILLS[id].lvl <= 7).size(), "whirl" in p.skills, p.links[0], "echo" in p.gems])
	_expect("gems_save", {"round": round_ok, "migrated": p.skills.size() == Data.SKILL_ORDER.filter(func(id): return Data.SKILLS[id].lvl <= 7).size(),
		"whirl": "whirl" in p.skills, "links_trimmed": p.links[0] == ["power"], "echo_owned": "echo" in p.gems})
	p.set_class(keep[6])
	p.level = keep[0]
	p.slots = keep[1]
	p.links = keep[2]
	p.gems = keep[3]
	p.skills = keep[4]
	p.cur.ember = keep[5]
	p.recalc(true)


## base classes: three ascendancies each, every ascendancy in exactly one class, the starting kit, only the
## class's own lineages can be taken, and characters from before classes get one from their ascendancy
func _smoke_classes() -> void:
	var p := player
	var keep := [p.level, p.equip, p.slots, p.links, p.gems, p.skills]
	var owned := {}
	for bc in Data.CLASSES:
		for k in bc.ascs:
			owned[k] = owned.get(k, 0) + 1
	print("SMOKE classes n=%d per=%s ascs=%d each_once=%s" % [Data.CLASSES.size(), Data.CLASSES.map(func(c): return c.ascs.size()),
		Data.ASCENDANCIES.size(), Data.ASCENDANCIES.all(func(a): return owned.get(a.k, 0) == 1)])
	_expect("classes", {"three": Data.CLASSES.size() == 3 and Data.CLASSES.all(func(c): return c.ascs.size() == 3),
		"each_once": Data.ASCENDANCIES.all(func(a): return owned.get(a.k, 0) == 1)})
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
	_expect("classes_kits", {"cores_ok": cores_ok, "kits": kits.size() == Data.CLASSES.size()})
	# the ascendancy screen offers only the class's three and refuses another class's
	p.set_class("lantern")
	p.level = 4
	hud.toggle(hud.asc_ui)
	hud.asc_ui._choose("pyre")
	var refused := p.asc == ""
	hud.asc_ui._choose("shade")
	print("SMOKE classes restrict refused_other=%s took=%s offered=%s" % [refused, p.asc, Data.class_ascs(p.cls).map(func(a): return a.k)])
	_expect("classes_restrict", {"refused_other": refused, "took": p.asc == "shade"})
	hud.close_panels()
	# a save whose ascendancy is not the class's own comes back without it
	var sd := save_data()
	sd.asc = "blade"
	apply_save(sd)
	print("SMOKE classes load_foreign asc='%s' cls=%s" % [p.asc, p.cls])
	_expect("classes_load_foreign", {"asc": p.asc == "", "cls": p.cls == "lantern"})
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
	_expect("classes_migrate", {"inferred": file.chars.slice(0, 4).map(func(c): return c.cls) == ["lantern", "sigil", "ashblade", Data.DEFAULT_CLASS],
		"odd": file.chars[4].cls == "lantern", "bad": file.chars[5].cls == Data.DEFAULT_CLASS})
	Profiles.migrate(file, Data.SEASONS[0].end)
	var moved: Dictionary = file.chars[1]
	print("SMOKE classes season_end league=%s from=%s cls=%s" % [moved.league, moved.from_season, moved.cls])
	_expect("classes_season_end", {"league": moved.league == Profiles.STANDARD, "from": moved.from_season == sid, "cls": moved.cls == "sigil"})
	Profiles.data = Profiles.fresh()
	p.level = keep[0]
	p.equip = keep[1]
	p.slots = keep[2]
	p.links = keep[3]
	p.gems = keep[4]
	p.skills = keep[5]
	p.set_class(Data.DEFAULT_CLASS)


## season leagues and the stash, on an in-memory profile file (the real one is never touched)
## passive tree: exactly PassiveTree.TOTAL nodes, the web is whole and laid out without overlaps, points follow the
## level, far nodes are taken along the shortest way, nodes only go back while the rest stays joined, saves are
## cleaned up, and old talents come back as points
func _smoke_tree() -> void:
	var p := player
	var keep := [p.level, p.tree.duplicate(), p.cls, p.jewels]
	p.jewels = []
	p.recalc()
	var all := PassiveTree.nodes()
	var kinds := {}
	for id in all:
		kinds[all[id].kind] = kinds.get(all[id].kind, 0) + 1
	var sym: bool = all.keys().all(func(id): return all[id].links.all(func(nb): return id in all[nb].links))
	var reach: bool = Data.CLASSES.all(func(c): return _tree_dist(c.k).size() == all.size() - Data.CLASSES.size() + 1)
	var names := {}
	for id in all:
		if all[id].kind in ["notable", "keystone"]:
			names[all[id].name] = true
	var tight := INF
	var ids: Array = all.keys()
	for i in ids.size():
		var a: Vector2 = all[ids[i]].pos
		for k in range(i + 1, ids.size()):
			var d2: float = a.distance_squared_to(all[ids[k]].pos)
			if d2 < tight:
				tight = d2
	var ks: Array = ids.filter(func(id): return all[id].kind == "keystone")
	var ks_trade: bool = ks.all(func(id): return all[id].stats.values().any(func(v): return v > 0) and all[id].stats.values().any(func(v): return v < 0))
	print("SMOKE tree nodes=%d kinds=%s symmetric=%s reach_all=%s unique_names=%s closest=%.2f keystones_trade=%s" % [all.size(), kinds, sym, reach,
		names.size() == kinds.get("notable", 0) + kinds.get("keystone", 0), sqrt(tight), ks_trade])
	_expect("tree", {"count": all.size() == PassiveTree.TOTAL and PassiveTree.TOTAL == 2000, "symmetric": sym, "reach_all": reach,
		"starts": kinds.get("start", 0) == Data.CLASSES.size(), "unique_names": names.size() == kinds.get("notable", 0) + kinds.get("keystone", 0),
		"spaced": sqrt(tight) > 0.6, "keystones": ks.size() >= 24 and ks_trade, "sockets": kinds.get("socket", 0) >= 12 and kinds.get("ring_socket", 0) == 6})
	p.set_class("ashblade")
	p.level = 20
	p.tree = []
	p.recalc(true)
	hud.toggle(hud.tree_ui)
	var dist := _tree_dist(p.cls)
	var goal := _nearest(dist, "notable", "atk_dmg")
	var atk0: float = p.s.atk_dmg
	var path := PassiveTree.path_to(p.tree, p.cls, goal)
	var took: bool = hud.tree_ui._take(goal)
	print("SMOKE tree take %s path=%d took=%s free=%d atk+%d" % [goal, path.size(), took, p.tree_free(), p.s.atk_dmg - atk0])
	_expect("tree_take", {"took": took, "path_taken": p.tree.size() == path.size() and path.size() == dist[goal], "free": p.tree_free() == p.tree_points() - path.size(),
		"atk": p.s.atk_dmg > atk0})
	var far: bool = hud.tree_ui._take("k_starlore")   # too many points for what is left
	var other: bool = hud.tree_ui._take(PassiveTree.start_id("sigil"))
	var mid: bool = hud.tree_ui._refund(p.tree[0])   # would cut the notable off
	var leaf: bool = hud.tree_ui._refund(goal)
	print("SMOKE tree refused far=%s other_start=%s mid=%s leaf=%s size=%d" % [far, other, mid, leaf, p.tree.size()])
	_expect("tree_refused", {"far": not far, "other_start": not other, "mid": not mid, "leaf": leaf, "size": p.tree.size() == path.size() - 1})
	# a keystone's percentage life, out on the edge; and how long the far searches take on the whole web
	p.level = 100
	p.tree = []
	p.recalc(true)
	var life0: float = p.s.max_life
	var t0 := Time.get_ticks_usec()
	var kpath := PassiveTree.path_to(p.tree, p.cls, "k_ironheart")
	var path_ms := (Time.get_ticks_usec() - t0) / 1000.0
	hud.tree_ui._take("k_ironheart")
	t0 = Time.get_ticks_usec()
	var refundable := p.tree.filter(func(id): return PassiveTree.can_refund(p.tree, p.cls, id))
	var refund_ms := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	for i in 200:
		hud.tree_ui.view.node_at(Vector2(randf() * 860, randf() * 620))
	var hit_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("SMOKE tree keystone path=%d life=%.2f move=%d refundable=%s path_ms=%.1f refund_all_ms=%.1f hit200_ms=%.1f" % [kpath.size(), p.s.max_life / life0,
		PassiveTree.stats(p.tree).move_spd, refundable, path_ms, refund_ms, hit_ms])
	_expect("tree_keystone", {"life": p.s.max_life > life0, "drawback": PassiveTree.stats(p.tree).move_spd < 0, "only_tip": refundable == ["k_ironheart"],
		"path_fast": path_ms < 250.0, "hit_fast": hit_ms < 250.0})
	hud.tree_ui._reset()
	print("SMOKE tree reset size=%d life_back=%s" % [p.tree.size(), is_equal_approx(p.s.max_life, life0)])
	_expect("tree_reset", {"empty": p.tree.is_empty(), "life_back": is_equal_approx(p.s.max_life, life0)})
	# saves: round trip, junk dropped, cut off or over-budget nodes pruned, another class's tree emptied
	p.level = 20
	p.recalc(true)
	hud.tree_ui._take(goal)
	var d := save_data()
	var want: Array = p.tree.duplicate()
	apply_save(JSON.parse_string(JSON.stringify(d)))
	var rt: bool = p.tree == want
	var junk := PassiveTree.sanitize(want + ["nope", "s_sigil", want[0], "k_starlore"], "ashblade", 40)
	var over := PassiveTree.sanitize(want, "ashblade", 2)
	var foreign := PassiveTree.sanitize(want, "sigil", 40)
	d.erase("tree")
	d.talents = {"might": 3}
	apply_save(d)
	print("SMOKE tree save round=%s junk=%d over=%s foreign=%d migrated=%s free=%d" % [rt, junk.size(), over == want.slice(0, 2), foreign.size(),
		talents_refunded, p.tree_free()])
	_expect("tree_save", {"round": rt, "junk": junk.size() == want.size(), "over": over == want.slice(0, 2), "foreign": foreign.is_empty(), "migrated": talents_refunded,
		"free": p.tree_free() == p.tree_points()})
	talents_refunded = false
	hud.close_panels()
	p.level = keep[0]
	p.tree = keep[1]
	p.jewels = keep[3]
	p.set_class(keep[2])


## steps from class `cls`'s start to every node it can reach (other classes' starts are walls)
func _tree_dist(cls: String) -> Dictionary:
	var st := PassiveTree.start_id(cls)
	var dist := {st: 0}
	var queue := [st]
	var head := 0
	while head < queue.size():
		var cur: String = queue[head]
		head += 1
		for nb in PassiveTree.node(cur).links:
			if not dist.has(nb) and PassiveTree.node(nb).kind != "start":
				dist[nb] = dist[cur] + 1
				queue.append(nb)
	return dist


## the closest node of `kind` (giving stat `stat`, if one is named) by steps in `dist`
func _nearest(dist: Dictionary, kind: String, stat := "") -> String:
	var best := ""
	for id in dist:
		var n := PassiveTree.node(id)
		if n.kind == kind and (stat == "" or n.stats.has(stat)) and (best == "" or dist[id] < dist[best]):
			best = id
	return best


## the `n` notables nearest the player's start, for views of a tree partly taken
func _view_tree_goals(n: int) -> Array:
	var dist := _tree_dist(player.cls)
	var ids := dist.keys().filter(func(id): return PassiveTree.node(id).kind == "notable")
	ids.sort_custom(func(x, y): return dist[x] < dist[y])
	return ids.slice(0, n)


## jewels: a 燈晶 in a socket gives its lines only while the socket is taken and comes out with it, wrong-kind sockets
## refuse, the currencies craft jewels the way they craft gear (and not while socketed), a 環晶 in a large socket
## grows its ring (taken, refunded and saved like the rest, with a 燈晶 in its small socket), and drops reach the collection
func _smoke_jewels() -> void:
	var p := player
	var keep := [p.level, p.tree.duplicate(), p.cls, p.jewels, p.cur.duplicate()]
	p.set_class("sigil")
	p.level = 100
	p.tree = []
	p.jewels = []
	p.recalc(true)
	hud.toggle(hud.tree_ui)
	var ui: TreeUI = hud.tree_ui
	var dist := _tree_dist(p.cls)
	var sock := _nearest(dist, "socket")
	var j := Jewels.generate(20, 2, "ash")
	j.mods = {"life": 50, "spell_dmg": 9}
	var ring := Jewels.generate_ring(30, 2, "l", "vital")
	p.jewels = [j, ring]
	ui._take(sock)
	var life1: float = p.s.max_life
	var spell1: float = p.s.spell_dmg
	var wrong := ui.socket_jewel(ring.uid, sock)
	ui.pick(j.uid)
	ui.click(sock)
	var life2: float = p.s.max_life
	print("SMOKE jewels socket %s at=%s wrong='%s' life %d->%d spell+%d" % [sock, j.socket, wrong, life1, life2, p.s.spell_dmg - spell1])
	_expect("jewels_socket", {"in": j.socket == sock, "wrong_kind": wrong != "" and ring.socket == "", "life": life2 > life1,
		"spell": is_equal_approx(p.s.spell_dmg - spell1, 9.0), "stats": Jewels.stats(p.jewels, p.tree).get("life", 0) == 58})
	var refunded := ui._refund(sock)
	print("SMOKE jewels refund socket=%s out=%s life_back=%s" % [refunded, j.socket == "", p.s.max_life < life2])
	_expect("jewels_refund", {"refund": refunded, "out": j.socket == "", "life_back": p.s.max_life < life2, "spell_back": is_equal_approx(p.s.spell_dmg, spell1)})
	# crafting with the gear currencies
	var cj := Jewels.generate(15, 0, "cinder")
	p.jewels.append(cj)
	ui.pick(cj.uid)
	for k in ["transmute", "ascend", "chaos", "whet", "purify", "divine"]:
		p.cur[k] = 5
	ui.craft("transmute")
	var magic := [int(cj.rarity), cj.mods.size()]
	ui.craft("ascend")
	var rare := [int(cj.rarity), cj.mods.size()]
	while cj.mods.size() < 4 and p.cur.whet > 0:
		ui.craft("whet")
	var whet_full := Jewels.craft("whet", cj)
	var keys0: Array = cj.mods.keys()
	ui.craft("divine")
	var divine_same: bool = cj.mods.keys() == keys0
	ui.craft("chaos")
	var chaos_n: int = cj.mods.size()
	ui._take(sock)
	ui.socket_jewel(cj.uid, sock)
	var locked := Jewels.craft("chaos", cj)
	ui.unsocket(cj.uid)
	ui.craft("purify")
	print("SMOKE jewels craft magic=%s rare=%s whet_full='%s' divine_same=%s chaos=%d locked='%s' purified=%d/%d spent=%s" % [magic, rare, whet_full,
		divine_same, chaos_n, locked, cj.rarity, cj.mods.size(), [p.cur.transmute, p.cur.ascend, p.cur.purify]])
	_expect("jewels_craft", {"magic": magic[0] == 1 and magic[1] >= 1 and magic[1] <= 2, "rare": rare[0] == 2 and rare[1] >= 3, "whet_full": whet_full != "",
		"divine": divine_same, "chaos": chaos_n >= 3 and chaos_n <= 4, "locked": locked != "", "purify": int(cj.rarity) == 0 and cj.mods.is_empty(),
		"spent": p.cur.transmute == 4 and p.cur.ascend == 4 and p.cur.purify == 4})
	var cr := Jewels.generate_ring(10, 0, "m", "blade")
	var cr_rolls := [Jewels.craft("transmute", cr), cr.notables.size(), Jewels.craft("ascend", cr), cr.notables.size(), Jewels.craft("whet", cr)]
	var th0: String = cr.theme
	Jewels.craft("chaos", cr)
	print("SMOKE jewels craft_ring rolls=%s theme %s->%s notables=%s" % [cr_rolls, th0, cr.theme, cr.notables])
	_expect("jewels_craft_ring", {"magic": cr_rolls[0] == "" and cr_rolls[1] == 1, "rare": cr_rolls[2] == "" and cr_rolls[3] == 2, "full": cr_rolls[4] != "",
		"chaos": cr.theme != th0 and cr.notables.size() == 2 and cr.notables.all(func(id): return Jewels.theme(cr.theme).notables.any(func(x): return x.id == id))})
	# a ring jewel grows the tree, and the growth survives a save
	p.tree = []
	j.socket = ""
	p.jewels = [j, ring]
	p.recalc(true)
	var big := _nearest(dist, "ring_socket")
	var n0 := PassiveTree.nodes().size()
	var ring_err := ui.socket_jewel(ring.uid, big)
	var ids := PassiveTree.ring_ids(big)
	var grown := PassiveTree.nodes().size() - n0
	var rn: Array = ids.filter(func(id): return PassiveTree.node(id).kind == "notable")
	var rs: Array = ids.filter(func(id): return PassiveTree.node(id).kind == "socket")
	var lifep0: float = p.s.max_life
	for id in rn:
		ui._take(id)
	var small_err := ui.socket_jewel(j.uid, rs[0]) if not rs.is_empty() else "none"
	var life_r: float = p.s.max_life
	var tree_r: Array = p.tree.duplicate()
	print("SMOKE jewels ring %s err='%s' path=%d grown=%d notables=%d socket=%d took=%s small_jewel='%s' life %d->%d" % [big, ring_err, dist.get(big, -1), grown, rn.size(),
		rs.size(), rn.all(func(id): return id in p.tree), small_err, lifep0, life_r])
	_expect("jewels_ring", {"in": ring.socket == big, "grown": grown == 8 + 3 + 1 and ids.size() == grown, "notables": rn.size() == 3, "small_socket": rs.size() == 1,
		"took": rn.all(func(id): return id in p.tree), "small_jewel": small_err == "" and j.socket == rs[0], "life": life_r > lifep0,
		"linked": PassiveTree.node(big).links.any(func(x): return x in ids)})
	var d := save_data()
	apply_save(JSON.parse_string(JSON.stringify(d)))
	var ring2: Dictionary = p.jewels.filter(func(x): return x.kind == "ring")[0]
	var j2: Dictionary = p.jewels.filter(func(x): return x.kind == "jewel")[0]
	print("SMOKE jewels ring_save nodes=%d tree_same=%s ring_at=%s small_at=%s life_same=%s" % [PassiveTree.nodes().size(), p.tree == tree_r, ring2.socket,
		j2.socket, is_equal_approx(p.s.max_life, life_r)])
	_expect("jewels_ring_save", {"nodes": PassiveTree.nodes().size() == n0 + grown, "tree": p.tree == tree_r, "ring": ring2.socket == big, "small": j2.socket == rs[0],
		"life": is_equal_approx(p.s.max_life, life_r), "same_json": JSON.stringify(save_data().jewels) == JSON.stringify(d.jewels)})
	# a hand-edited save: the ring moved to a small socket, a second jewel in the same small socket, an unknown base
	var junk = JSON.parse_string(JSON.stringify(d))
	var ri: int = junk.jewels.map(func(x): return x.kind).find("ring")
	junk.jewels[ri].socket = sock
	var dup: Dictionary = junk.jewels[1 - ri].duplicate()
	dup.uid = "dup"
	junk.jewels.append(dup)
	junk.jewels.append({"kind": "jewel", "base": "nope"})
	apply_save(junk)
	var at_sock := p.jewels.filter(func(x): return x.socket != "")
	print("SMOKE jewels ring_junk kept=%d ring_out=%s socketed=%d ring_nodes_left=%d" % [p.jewels.size(), p.jewels[ri].socket == "", at_sock.size(),
		p.tree.filter(func(id): return id.begins_with("x")).size()])
	_expect("jewels_ring_junk", {"kept": p.jewels.size() == 3, "ring_out": p.jewels[ri].socket == "", "small_gone": at_sock.is_empty(),
		"nodes_back": PassiveTree.nodes().size() == n0, "pruned": p.tree.all(func(id): return not id.begins_with("x"))})
	apply_save(JSON.parse_string(JSON.stringify(d)))
	ring2 = p.jewels.filter(func(x): return x.kind == "ring")[0]
	var free0 := p.tree_free()
	ui.unsocket(ring2.uid)
	print("SMOKE jewels ring_out nodes=%d refunded=%d all_out=%s" % [PassiveTree.nodes().size(), p.tree_free() - free0, p.jewels.all(func(x): return x.socket == "")])
	_expect("jewels_ring_out", {"nodes": PassiveTree.nodes().size() == n0, "refunded": p.tree_free() - free0 == tree_r.filter(func(id): return id in ids).size(), "all_out": p.jewels.all(func(x): return x.socket == "")})
	# drops reach the collection
	p.jewels = []
	_drop_jewel(p.pos, 12, true)
	_drop_jewel(p.pos, 12)
	for g in drops.filter(func(g): return g.k == "jewel"):
		_take(g)
	drops = drops.filter(func(g): return not g.get("taken", false))
	print("SMOKE jewels drop owned=%d ring=%d" % [p.jewels.size(), p.jewels.filter(func(x): return x.kind == "ring").size()])
	_expect("jewels_drop", {"owned": p.jewels.size() == 2, "ring": p.jewels.filter(func(x): return x.kind == "ring").size() == 1})
	hud.close_panels()
	p.level = keep[0]
	p.jewels = keep[3]
	p.tree = keep[1]
	p.cur = keep[4]
	p.set_class(keep[2])
	p.fix_jewels()
	p.recalc(true)


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
	_expect("season_running", {"moved": running.is_empty(), "league": sc.league == sid})
	var notes := Profiles.migrate(d, Data.SEASONS[0].end)
	print("SMOKE season ended notes=%d league=%s from=%s std_tabs=%d season_stash=%s" % [notes.size(), sc.league, sc.from_season,
		d.stash[Profiles.STANDARD].size(), d.stash.has(sid)])
	_expect("season_ended", {"notes": not notes.is_empty(), "league": sc.league == Profiles.STANDARD, "from": sc.from_season == sid,
		"tabs_moved": d.stash[Profiles.STANDARD].size() > Profiles.TABS, "season_stash_gone": not d.stash.has(sid)})
	Profiles.data = Profiles.fresh()
	hud.toggle(hud.stash_ui)
	p.bag.append(Items.generate(3, 1.0, 1))
	var n := p.bag.size()
	hud.stash_ui._put(0)
	var put: int = Profiles.stash_tabs(Profiles.STANDARD)[0].items.size()
	hud.stash_ui._take(0)
	print("SMOKE stash put=%d back=%s open=%s" % [put, p.bag.size() == n, hud.stash_ui.visible])
	_expect("stash", {"put": put == 1, "back": p.bag.size() == n, "open": hud.stash_ui.visible})
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
	_expect("keys_rebind", {"rebound": Keybinds.binds.inventory[0] == {"key": KEY_J}, "inputmap": ev.is_action_pressed("inventory")})
	ui.listen("skill_4", 0)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_MIDDLE
	mb.pressed = true
	ui._input(mb)
	print("SMOKE keys mouse=%s short='%s'" % [Keybinds.text("skill_4"), Keybinds.short("skill_4")])
	_expect("keys_mouse", {"bound": Keybinds.binds.skill_4[0] == {"mouse": MOUSE_BUTTON_MIDDLE}})
	# F is the potion's: binding it to slot 3 swaps, so the potion takes Q and no duplicate is left
	var lost := Keybinds.assign("skill_3", 0, {"key": KEY_F})
	print("SMOKE keys swap lost=%s potion='%s' skill_3='%s' conflicts=%d" % [lost, Keybinds.text("potion"), Keybinds.text("skill_3"),
		Keybinds.conflicts().size()])
	_expect("keys_swap", {"lost": lost == "potion", "potion": Keybinds.text("potion") == "Q", "skill_3": Keybinds.text("skill_3") == "F",
		"no_conflict": Keybinds.conflicts().is_empty()})
	Keybinds.binds.talents[1] = {"key": KEY_J}   # as a hand-edited file could have it
	Keybinds.apply()
	print("SMOKE keys duplicate detected=%s flagged=%s" % [Keybinds.conflicts().size() == 1, Keybinds.conflicted("inventory", 0)])
	_expect("keys_duplicate", {"detected": Keybinds.conflicts().size() == 1, "flagged": Keybinds.conflicted("inventory", 0)})
	Keybinds.assign("talents", 1, {})
	hud.close_panels()
	hud.refresh()
	hud.pause_ui.refresh()
	print("SMOKE keys hud potion='%s' slot3='%s' tip=%s pause=%s" % [hud.potion.text, Keybinds.short("skill_3"),
		hud.skill_ui.skill_tip(player.slots[2], 2)[1][0].contains("F"), hud.pause_ui.controls.get_child(1).text.begins_with("Q：回復薬")])
	_expect("keys_hud", {"potion": hud.potion.text.ends_with("[Q]"), "slot3": Keybinds.short("skill_3") == "F",
		"tip": hud.skill_ui.skill_tip(player.slots[2], 2)[1][0].contains("F"), "pause": hud.pause_ui.controls.get_child(1).text.begins_with("Q：回復薬")})
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
		_expect("keys_press_" + OS.get_keycode_string(k), {"inventory": hud.inventory.visible == (k == KEY_J)})
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
	_expect("keys_saved", {"roundtrip": Keybinds.binds == before, "inputmap": ev2.is_action("skill_3"), "junk_ignored": Keybinds.text("filter") == "L"})
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	ui.open_close()
	ui.bind_to("potion", 0, {"key": KEY_G})
	ui.reset.pressed.emit()
	print("SMOKE keys reset=%s potion='%s'" % [Keybinds.binds == Keybinds.defaults(), Keybinds.text("potion")])
	_expect("keys_reset", {"reset": Keybinds.binds == Keybinds.defaults(), "potion": Keybinds.text("potion") == "F"})
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
	_expect("aura_on", {"on": p.auras == ["ember_heart"], "reserved": p.reserved("mana") > 0, "mana_capped": p.mana <= p.cap("mana"),
		"dmg": p.bonus("dmg") > dmg0, "ring": p.aura_fx != null and p.aura_fx.get_child_count() == 1})
	toggle.call(1)
	print("SMOKE aura off=%s reserved=%d cap=%d" % [p.auras, p.reserved("mana"), p.cap("mana")])
	_expect("aura_off", {"off": p.auras.is_empty(), "reserved": p.reserved("mana") == 0, "cap": is_equal_approx(p.cap("mana"), mx)})
	# stack three mana auras (80% of the pool); the flat 30 of the fourth would pass the max and is refused
	for i in [1, 2, 3, 5]:
		toggle.call(i)
	print("SMOKE aura stack on=%s reserved=%d/%d refused=%s" % [p.auras, p.reserved("mana"), mx, not "hearth_ward" in p.auras])
	_expect("aura_stack", {"three": p.auras.size() == 3, "within": p.reserved("mana") <= mx, "refused": not "hearth_ward" in p.auras})
	toggle.call(4)
	print("SMOKE aura life on=%s reserved_life=%d cap_life=%d/%d life_capped=%s" % ["crimson_pact" in p.auras, p.reserved("life"), p.cap("life"),
		p.s.max_life, p.life <= p.cap("life")])
	_expect("aura_life", {"on": "crimson_pact" in p.auras, "reserved": p.reserved("life") > 0, "life_capped": p.life <= p.cap("life")})
	# 効率化 shrinks the flat 30 enough to fit; unlinking it again switches off the aura that no longer fits
	p.links[5] = ["efficient"]
	var cut := p.aura_reserve("hearth_ward", "mana")
	toggle.call(5)
	print("SMOKE aura gem reserve=%d on=%s total=%d/%d" % [cut, "hearth_ward" in p.auras, p.reserved("mana"), mx])
	_expect("aura_gem", {"on": "hearth_ward" in p.auras, "within": p.reserved("mana") <= mx})
	p.links[5] = []
	var off := p.fix_auras()
	print("SMOKE aura overflow off=%s left=%d" % [off, p.auras.size()])
	_expect("aura_overflow", {"off": off == ["hearth_ward"], "within": p.reserved("mana") <= mx})
	# an ally inside the reach shares the auras, one far away does not
	var near := Ally.new()
	near.pos = p.pos + Vector2(2, 0)
	var far := Ally.new()
	far.pos = p.pos + Vector2(30, 0)
	print("SMOKE aura allies near=%s far=%s dr=%.0f" % [in_aura(near), in_aura(far), p.astat("dr")])
	_expect("aura_allies", {"near": in_aura(near), "far": not in_aura(far)})
	near.free()
	far.free()
	hud.refresh()
	await get_tree().process_frame
	print("SMOKE aura hud mana_reserve=%.2f text='%s' life_reserve=%.2f text='%s'" % [hud.mana_orb.reserve, hud.mana_orb.text,
		hud.life_orb.reserve, hud.life_orb.reserve_text])
	_expect("aura_hud", {"mana": hud.mana_orb.reserve > 0.0, "life": hud.life_orb.reserve > 0.0 and hud.life_orb.reserve_text != ""})
	# save round trip: the auras that were on come back on, with the same reservation
	var held := [p.reserved("life"), p.reserved("mana")]
	var on := p.auras.duplicate()
	var data = JSON.parse_string(JSON.stringify(save_data()))
	p.auras.clear()
	p.recalc(true)
	apply_save(data)
	print("SMOKE aura save restored=%s same=%s mana_capped=%s life_capped=%s" % [p.auras == on, held == [p.reserved("life"), p.reserved("mana")],
		p.mana <= p.cap("mana"), p.life <= p.cap("life")])
	_expect("aura_save", {"restored": p.auras == on, "same": held == [p.reserved("life"), p.reserved("mana")], "mana_capped": p.mana <= p.cap("mana"),
		"life_capped": p.life <= p.cap("life")})
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
	_expect("market_drift", {"ticks": Market.state(sid).tick == 300, "in_range": inside, "hist": Market.history(sid, "whet", 60).size() > 0})
	var ev := Market.events(sid)
	print("SMOKE market events n=%d same=%s std=%d" % [ev.size(), ev == Market.events(sid), Market.events(std).size()])
	_expect("market_events", {"some": ev.size() > 0, "same": ev == Market.events(sid), "std_none": Market.events(std).is_empty()})
	w = {"chaos": 100, "ember": 1000}
	var err := Market.market_trade(std, "whet", "buy", 20, w)
	var got: int = w.get("whet", 0)
	var err2 := Market.market_trade(std, "whet", "sell", got, w)
	print("SMOKE market roundtrip ok=%s chaos=%d lost=%s whet=%d" % [err == "" and err2 == "", w.chaos, w.chaos < 100, w.get("whet", 0)])
	_expect("market_roundtrip", {"ok": err == "" and err2 == "", "spread_lost": w.chaos < 100, "sold_all": w.get("whet", 0) == 0})
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
	_expect("market_limit", {"ok": err == "", "escrowed": held == 0, "filled": w.chaos > 0 and Market.orders(std).is_empty(), "noted": notes.size() > 0})
	w = {"chaos": 50, "ember": 1000, "whet": 5}
	Market.place_limit(sid, "whet", "sell", Market.price(sid, "whet") * 3.0, 5, w)
	Market.place_limit(sid, "whet", "buy", Market.price(sid, "whet") * 0.3, 10, w)
	var mig := Profiles.migrate(d, Data.SEASONS[0].end)
	var sc := Profiles.stash_cur(std)
	print("SMOKE market season end notes=%d market_gone=%s std_whet=%d std_chaos=%d" % [mig.size(), not d.market.has(sid),
		sc.get("whet", 0), sc.get("chaos", 0)])
	_expect("market_season_end", {"gone": not d.market.has(sid), "whet_back": sc.get("whet", 0) == 5, "chaos_back": sc.get("chaos", 0) > 0})
	var into := {}
	Profiles.take_stash_cur(std, into)
	print("SMOKE market stash taken whet=%d left=%d" % [into.get("whet", 0), Profiles.stash_cur(std).size()])
	_expect("market_stash", {"taken": into.get("whet", 0) == 5, "emptied": Profiles.stash_cur(std).is_empty()})
	Profiles.data = Profiles.fresh()


## gear trading and buy requests (docs/economy-design.md phases 2 and 3), on an in-memory profile file
func _smoke_trade() -> void:
	var sid: String = Data.SEASONS[0].id
	var d := Profiles.fresh()
	Profiles.data = d
	var std := Profiles.STANDARD
	Trade.ensure(std, 20)
	var m := Market.state(std)
	var tagged := Trade.tags({"rarity": 3, "name": "", "desc": "骸骨を召喚する", "mods": {"fire_dmg": 10, "life": -5}})
	print("SMOKE trade setup offers=%d requests=%d tags=%s events=%d same=%s std_events=%d" % [m.offers.size(), m.requests.size(), tagged,
		Trade.events(sid).size(), Trade.events(sid) == Trade.events(sid), Trade.events(std).size()])
	_expect("trade_setup", {"offers": m.offers.size() > 0, "requests": m.requests.size() > 0, "tags": "fire" in tagged and "minion" in tagged,
		"std_events": Trade.events(std).is_empty()})
	# a unique worth a few chaos (and so likely to sell at its value), a rare, a normal item
	var uq := {}
	for i in 400:
		uq = Items.generate(20, 0.0, 3)
		if Trade.value(std, uq) >= 2.0:
			break
	var rare := Items.generate(20, 0.0, 2)
	var normal := Items.generate(20, 0.0, 0)
	var v := Trade.value(std, uq)
	print("SMOKE trade value unique=%.2f rare=%s normal=%s" % [v, Trade.value(std, rare) > 0.0, Trade.value(std, normal) == 0.0])
	_expect("trade_value", {"unique": v > 0.0, "rare": Trade.value(std, rare) > 0.0, "normal": Trade.value(std, normal) == 0.0})
	var w := {"chaos": 0, "ember": 100000}
	var bag := [normal, uq, rare]
	var refused := Trade.list_item(std, bag, 0, 5, w)
	var ask := maxi(1, floori(v))
	var err := Trade.list_item(std, bag, 1, ask, w)
	var paid: int = 100000 - w.ember
	var err2 := Trade.list_item(std, bag, 1, 999, w)   # the rare, far over its value
	for i in 40:
		if m.listings.size() < 2:
			break
		Market.tick(std, w)
	var notes := Market.take_notes(std)
	print("SMOKE trade listing refused=%s ok=%s fee=%d bag=%d sold=%s chaos=%d noted=%s" % [refused != "", err == "" and err2 == "", paid,
		bag.size(), m.listings.size() == 1, w.chaos, notes.any(func(t): return "売れました" in t)])
	_expect("trade_listing", {"refused_normal": refused != "", "ok": err == "" and err2 == "", "fee": paid > 0, "bag": bag.size() == 1,
		"sold": m.listings.size() == 1, "noted": notes.any(func(t): return "売れました" in t)})
	for i in Trade.LISTING_LIFE:
		Market.tick(std, w)
	var expired: bool = m.listings.is_empty() and m.held.size() == 1
	var took := Trade.take_held(std, 0, bag, Player.BAG_SIZE)
	print("SMOKE trade expired=%s took=%s bag=%d offers=%d" % [expired, took == "", bag.size(), m.offers.size()])
	_expect("trade_expired", {"expired": expired, "took": took == "", "bag": bag.size() == 2})
	# the dealer, and another adventurer's offer
	w = {"chaos": 999, "ember": 5000}
	bag = [uq]
	var dealer := Trade.dealer_price(std, uq)
	err = Trade.dealer_sell(std, bag, 0, w)
	print("SMOKE trade dealer ok=%s got=%d below_value=%s" % [err == "", w.chaos - 999, dealer < Trade.value(std, uq)])
	_expect("trade_dealer", {"ok": err == "", "below_value": dealer < Trade.value(std, uq), "bag": bag.is_empty()})
	var o: Dictionary = m.offers[0]
	var c0: int = w.chaos
	var e0: int = w.ember
	err = Trade.buy_offer(std, o.id, bag, Player.BAG_SIZE, w)
	print("SMOKE trade bought ok=%s paid=%s fee=%s bag=%d" % [err == "", c0 - w.chaos == o.price, e0 - w.ember == Market.fee(o.price), bag.size()])
	_expect("trade_bought", {"ok": err == "", "paid": c0 - w.chaos == o.price, "fee": e0 - w.ember == Market.fee(o.price), "bag": bag.size() == 1})
	# buy requests: a fitting rare is taken for the reward, nothing fitting is refused
	var ring := Items.generate(20, 0.0, 2, "ring")
	ring.mods.life = 999
	m.requests = [{"id": 9001, "kind": "affix", "slot": "ring", "k": "life", "need": 40, "tag": "", "reward": 3, "who": "テスト", "placed_tick": m.tick},
		{"id": 9002, "kind": "unique", "slot": "", "k": "", "need": 0, "tag": "minion", "reward": 2, "who": "テスト", "placed_tick": m.tick}]
	bag = [ring]
	c0 = w.chaos
	var no := Trade.deliver(std, 9002, bag, w)
	err = Trade.deliver(std, 9001, bag, w)
	print("SMOKE trade request refused=%s ok=%s reward=%d bag=%d left=%d" % [no != "", err == "", w.chaos - c0, bag.size(), m.requests.size()])
	_expect("trade_request", {"refused": no != "", "ok": err == "", "reward": w.chaos - c0 == 3, "bag": bag.is_empty(), "left": m.requests.size() == 1})
	for i in Trade.REQUEST_LIFE + 1:
		Market.tick(std, w)
	print("SMOKE trade requests kept=%d max=%d" % [m.requests.size(), Trade.MAX_REQUESTS])
	_expect("trade_requests", {"kept": m.requests.size() > 0 and m.requests.size() <= Trade.MAX_REQUESTS})
	# a save round trip keeps the gear and the integer fields
	Trade.list_item(std, [rare], 0, 3, w)
	var back = JSON.parse_string(JSON.stringify(m))
	Market.normalize(std, back)
	print("SMOKE trade save listings=%d offers=%d int_ask=%s" % [back.listings.size(), back.offers.size(), typeof(back.listings[0].ask) == TYPE_INT])
	_expect("trade_save", {"listings": back.listings.size() == m.listings.size(), "offers": back.offers.size() == m.offers.size(),
		"int_ask": typeof(back.listings[0].ask) == TYPE_INT})
	# a season ends: its listed gear and pickup box go to a standard stash tab
	var ms := Market.state(sid)
	Trade.ensure(sid, 5)
	Trade.list_item(sid, [Items.generate(5, 0.0, 2)], 0, 50, w)
	ms.held.append(Items.generate(5, 0.0, 3))
	var mig := Profiles.migrate(d, Data.SEASONS[0].end)
	var tab: Array = Profiles.stash_tabs(std).filter(func(t): return t.name.ends_with("取引所"))
	print("SMOKE trade season end tab=%d items=%d noted=%s" % [tab.size(), tab[0].items.size() if tab.size() > 0 else 0,
		mig.any(func(t): return "装備" in t)])
	_expect("trade_season_end", {"tab": tab.size() == 1, "items": tab.size() == 1 and tab[0].items.size() == 2, "noted": mig.any(func(t): return "装備" in t)})
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
	_expect("merchant", {"chaos": chaos_cost == roundi(Market.price(lg, "chaos") * 250 * d0), "haggled": haggled < chaos_cost, "whet": whet_ok})
	p.cur.ember = 2000
	p.cur.chaos = 30
	p.cur.whet = 0
	open_interact("exchange")
	await get_tree().create_timer(0.3).timeout
	var ex := hud.exchange_ui
	print("SMOKE exchange open=%s rows=%d board=%d orders_box=%d" % [ex.visible, ex.price_grid.get_child_count() / 4 - 1,
		ex.board_box.get_child_count(), ex.order_box.get_child_count()])
	_expect("exchange_open", {"open": ex.visible, "rows": ex.price_grid.get_child_count() / 4 - 1 == Market.keys().size()})
	ex.select("whet")
	ex.side = "buy"
	ex.mode = "market"
	ex.qty.value = 3
	var quoted := Market.quote(lg, "whet", "buy", 3)
	ex.execute()
	print("SMOKE exchange market buy whet=%d chaos=%d paid=%d err='%s'" % [p.cur.whet, p.cur.chaos, 30 - p.cur.chaos, ex.error.text])
	print("SMOKE exchange quote_matches=%s" % (30 - p.cur.chaos == quoted.chaos))
	_expect("exchange_market", {"bought": p.cur.whet == 3, "quote": 30 - p.cur.chaos == quoted.chaos, "no_error": ex.error.text == ""})
	ex.qty.value = 500
	ex.execute()
	print("SMOKE exchange refused err=%s whet=%d" % [ex.error.text != "", p.cur.whet])
	_expect("exchange_refused", {"error": ex.error.text != "", "unchanged": p.cur.whet == 3})
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
	_expect("exchange_limit", {"placed": orders.size() == 1, "escrowed": p.cur.whet == 1, "row": ex.order_box.get_child_count() == 1})
	ex.cancel(orders[0].id if orders.size() > 0 else -1)
	print("SMOKE exchange cancelled orders=%d whet=%d" % [Market.orders(lg).size(), p.cur.whet])
	_expect("exchange_cancel", {"gone": Market.orders(lg).is_empty(), "refunded": p.cur.whet == 3})
	# the gear page: list a unique from the bag, buy another adventurer's offer
	ex.page = "gear"
	ex.refresh()
	p.cur.chaos = 500
	var uq := Items.generate(10, 0.0, 3)
	p.bag.append(uq)
	ex.pick_bag(p.bag.size() - 1)
	var bag0 := p.bag.size()
	ex.list_picked()
	var mk := Market.state(lg)
	print("SMOKE exchange gear offers=%d listed=%d bag=%d err='%s' rows=%d" % [ex.offer_grid.get_child_count(), mk.listings.size(),
		bag0 - p.bag.size(), ex.gear_error.text, ex.listing_box.get_child_count()])
	_expect("exchange_gear", {"offers": ex.offer_grid.get_child_count() > 0, "listed": mk.listings.size() == 1, "left_bag": bag0 - p.bag.size() == 1,
		"no_error": ex.gear_error.text == ""})
	var offer: Dictionary = mk.offers[0]
	var chaos0: int = p.cur.chaos
	ex.buy_offer(offer.id)
	print("SMOKE exchange gear bought=%s paid=%s" % [p.bag.has(offer.item), chaos0 - p.cur.chaos == offer.price])
	_expect("exchange_gear_buy", {"bought": p.bag.has(offer.item), "paid": chaos0 - p.cur.chaos == offer.price})
	ex.unlist(mk.listings[0].id if mk.listings.size() > 0 else -1)
	print("SMOKE exchange gear unlisted back=%s" % p.bag.has(uq))
	_expect("exchange_unlist", {"back": p.bag.has(uq)})
	# the requests page: a request the bag can fill is delivered for its reward
	var ring := Items.generate(10, 0.0, 2, "ring")
	ring.mods.life = 999
	p.bag.append(ring)
	mk.requests = [{"id": 9000, "kind": "affix", "slot": "ring", "k": "life", "need": 30, "tag": "", "reward": 4, "who": "テスト", "placed_tick": mk.tick}]
	ex.page = "requests"
	ex.refresh()
	var rows := ex.req_box.get_child_count()
	chaos0 = p.cur.chaos
	ex.deliver(9000)
	print("SMOKE exchange request rows=%d delivered=%s reward=%d" % [rows, not p.bag.has(ring), p.cur.chaos - chaos0])
	_expect("exchange_request", {"rows": rows > 0, "delivered": not p.bag.has(ring), "reward": p.cur.chaos - chaos0 == 4})
	ex.page = "currency"
	hud.close_panels()
	Market.state(lg).pending.append("テスト通知")
	var msgs0 := hud.messages.get_child_count()
	market_notes()
	print("SMOKE exchange notes shown=%s left=%d" % [hud.messages.get_child_count() > msgs0 or msgs0 >= 5, Market.state(lg).pending.size()])
	_expect("exchange_notes", {"taken": Market.state(lg).pending.is_empty()})


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


func _view_jewels(kind: String) -> void:
	var p := player
	p.level = 90 if kind != "tree_all" else 40
	for k in ["transmute", "ascend", "chaos", "whet", "purify", "divine"]:
		p.cur[k] = 7
	var dist := _tree_dist(p.cls)
	var j := Jewels.generate(24, 2)
	var ring := Jewels.generate_ring(30, 2, "l")
	var spare := Jewels.generate(18, 1)
	p.jewels = [j, ring, spare, Jewels.generate_ring(12, 1, "s"), Jewels.generate(10, 0)]
	p.tree = []
	for goal in _view_tree_goals(3):
		p.tree.append_array(PassiveTree.path_to(p.tree, p.cls, goal))
	p.recalc(true)
	hud.toggle(hud.tree_ui)
	var ui: TreeUI = hud.tree_ui
	if kind != "tree_all":
		var big := _nearest(dist, "ring_socket")
		ui.socket_jewel(ring.uid, big)
		var ids := PassiveTree.ring_ids(big)
		for id in ids.filter(func(x): return PassiveTree.node(x).kind == "notable"):
			ui._take(id)
		ui.socket_jewel(j.uid, ids.filter(func(x): return PassiveTree.node(x).kind == "socket")[0])
		ui.socket_jewel(spare.uid, _nearest(dist, "socket"))
		ui.pick(p.jewels[3 if kind == "jewel_craft" else 1].uid)
	await get_tree().process_frame
	if kind == "tree_all":
		ui.view.fit_all()
	else:
		var at: Vector2 = PassiveTree.node(_nearest(dist, "ring_socket")).pos
		ui.view.zoom = 0.75
		ui.view.pan = -at.lerp(Vector2.ZERO, 0.3) * TreeUI.TreeView.UNIT * ui.view.zoom
	ui.view.queue_redraw()


func _view_tablets(kind: String) -> void:
	var p := player
	p.cur.whet = 4
	p.cur.chaos = 2
	if kind == "tablets_full":
		for i in 6:
			var t := Tablets.generate(14, "slab6", 3)
			p.tablets.append(t)
			Tablets.place(p.tablets, t, (i % 2) * 3, (i / 2) * 2, 0)
	else:
		for s in [["cross5", 0, 0, 0], ["line4", 3, 0, 1], ["square4", 4, 4, 0], ["hook4", 0, 3, 3], ["pair", 2, 5, 0]]:
			var t := Tablets.generate(14, s[0], 2)
			p.tablets.append(t)
			Tablets.place(p.tablets, t, s[1], s[2], s[3])
		for s in ["gate6", "tee4", "mono", "flag5"]:
			p.tablets.append(Tablets.generate(14, s, 0 if s == "mono" else 1))
	p.recalc(true)
	hud.toggle(hud.tablet_ui)
	hud.tablet_ui.pick(p.tablets[-1].uid)
	hud.tablet_ui.board.hover = Vector2i(3, 2)


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
	_expect("farm_placed", {"labels": dormant == placed, "floor": on_floor, "beacon_map": altars.size() > placed or altars.size() >= 3, "beacon_spent": f.beacons == 0})
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
	_expect("farm_kindle", {"refused": refused, "active": a.state == "active", "panel_closed": not hud.cinder_ui.visible, "first": first == a.plan.waves[0],
		"boosted": boosted, "label_gone": not interacts.any(func(o): return o.get("altar") == a)})
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
	_expect("farm_waves", {"all": a.wave == a.plan.waves.size(), "guard": guards >= 1, "done": a.state == "done", "renown": f.renown > 0, "lit": f.lit == 1,
		"reward": reward.get("cinder", 0) > 0})
	p.pos = a.pos + Vector2(0, 2.0)
	_collect_nearby(60.0)
	print("SMOKE farm collected cinder=%d char_cur_clean=%s status='%s'" % [f.cinder, not p.cur.has(Farm.KEY), altar_status()])
	_expect("farm_collected", {"cinder": f.cinder >= reward.get("cinder", 1), "char_cur_clean": not p.cur.has(Farm.KEY)})
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
	_expect("farm_trial", {"failed": b.state == "failed", "renown_same": f.renown == r0})
	for e in b.spawned:
		hit_enemy(e, {"dmg": 999999, "crit": false, "type": "phys"})
	# the forge in the hideout: crystals buy loot, gated by renown
	enter_hideout()
	f.cinder = 200
	f.renown = 0
	var keep_bag := p.bag   # the loot run before leaves the bag full; the forge needs room
	p.bag = []
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
	_expect("farm_forge", {"open": hud.cinder_ui.visible, "bought": p.bag.size() - bag0 == 2, "paid": after_rare < 200, "locked": refused_legend != "",
		"legend": legends == 1, "beacon": f.beacons > 0})
	p.bag = keep_bag
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
	_expect("farm_leagues", {"split": split, "json": round_trip, "cinder_added": std.cinder == std0 + 70, "rank": Farm.rank(std) == 6,
		"season_gone": not Profiles.data.farm.has(sid), "note": notes.any(func(t): return "燼晶" in t)})
	Profiles.data = Profiles.fresh()


## rune tablets: the shapes turn true, the board takes them without overlap or overhang up to all 36 cells,
## the panel sets and lifts them, their lines reach the stats, crafting carves within each tablet's limit,
## a boss drops one, and a save keeps them (an overlapping hand-edited placement comes off the board)
func _smoke_tablets() -> void:
	var p := player
	p.tablets = []
	p.recalc(true)
	var turns_ok := Tablets.SHAPES.all(func(sh):
		var a: Array = Tablets.turned(sh.id, 0)
		a.sort()
		var b: Array = Tablets.turned(sh.id, 4)
		b.sort()
		return a == b and a.size() == sh.cells.size())
	var tall: Array = Tablets.turned("line4", 1)
	print("SMOKE tablets shapes=%d sizes=%d-%d turns=%s line4_upright=%s" % [Tablets.SHAPES.size(),
		Tablets.SHAPES.map(func(sh): return sh.cells.size()).min(), Tablets.SHAPES.map(func(sh): return sh.cells.size()).max(), turns_ok,
		tall.all(func(c): return c.x == 0) and tall.size() == 4])
	_expect("tablets_shapes", {"turns": turns_ok, "line4_upright": tall.all(func(c): return c.x == 0) and tall.size() == 4})
	# nothing may hang off the edge, a tablet may turn over its own cells, and six 3x2 slabs fill the whole board
	var probe := Tablets.generate(10, "slab6", 0)
	var edge_err := Tablets.fit([probe], probe, 4, 0, 0)
	Tablets.place([probe], probe, 0, 0, 0)
	var turned_fit := Tablets.fit([probe], probe, 0, 0, 1) == ""
	var slabs := []
	for i in 6:
		var t := Tablets.generate(10, "slab6", 0)
		p.tablets.append(t)
		slabs.append(t)
	var errs := []
	for i in 6:
		errs.append(Tablets.place(p.tablets, slabs[i], (i % 2) * 3, (i / 2) * 2, 0))
	var extra := Tablets.generate(10, "mono", 1)
	p.tablets.append(extra)
	var full_err := Tablets.place(p.tablets, extra, 2, 2, 0)
	print("SMOKE tablets board used=%d/36 all_set=%s overlap='%s' edge='%s' turned_over_own=%s" % [Tablets.used_cells(p.tablets),
		errs.all(func(e): return e == ""), full_err, edge_err, turned_fit])
	_expect("tablets_board", {"full": Tablets.used_cells(p.tablets) == 36, "all_set": errs.all(func(e): return e == ""), "overlap": full_err != "",
		"edge": edge_err != "", "turned_over_own": turned_fit})
	# lines reach the stats only while the tablet is on the board
	p.tablets = []
	var life_t := Tablets.generate(10, "cross5", 0)
	life_t.mods = {"life": 40}
	p.tablets.append(life_t)
	p.recalc(true)
	var life0: float = p.s.max_life
	hud.toggle(hud.tablet_ui)
	var ui: TabletUI = hud.tablet_ui
	ui.pick(life_t.uid)
	ui.turn_picked()
	ui.click_cell(Vector2i(1, 1))
	var life1: float = p.s.max_life
	var cells := Tablets.cells_at(life_t, life_t.x, life_t.y, life_t.rot)
	ui.right_cell(cells[0])
	print("SMOKE tablets panel open=%s placed_rot=%d life %d->%d->%d cards=%d off=%s" % [ui.visible, life_t.rot, life0, life1,
		p.s.max_life, ui.list.get_child_count(), not life_t.placed])
	_expect("tablets_panel", {"open": ui.visible, "rot": life_t.rot == 1, "life_on": life1 > life0, "life_off": is_equal_approx(p.s.max_life, life0),
		"lifted": not life_t.placed})
	# carving: 鍛錬の砥石 adds lines up to the limit, 混沌の残光 recarves them, both spend the currency
	var blank := Tablets.generate(12, "hook5", 0)
	p.tablets.append(blank)
	p.cur.whet = 5
	p.cur.chaos = 2
	ui.pick(blank.uid)
	for i in 4:
		ui.craft("whet")
	var carved: int = blank.mods.size()
	var limit_err: String = ui.error.text
	var before: Dictionary = blank.mods.duplicate()
	ui.craft("chaos")
	print("SMOKE tablets craft lines=%d/%d whet_left=%d limit='%s' chaos_kept=%d chaos_left=%d mono_max=%d" % [carved, Tablets.max_mods(blank),
		p.cur.whet, limit_err, blank.mods.size(), p.cur.chaos, Tablets.max_mods(Tablets.generate(1, "mono", 0))])
	_expect("tablets_craft", {"to_limit": carved == Tablets.max_mods(blank), "whet_spent": p.cur.whet == 5 - carved, "limit": limit_err != "",
		"chaos_kept": blank.mods.size() == carved, "chaos_spent": p.cur.chaos == 1})
	ui.shatter()
	print("SMOKE tablets shatter gone=%s" % [not p.tablets.has(blank)])
	_expect("tablets_shatter", {"gone": not p.tablets.has(blank)})
	hud.close_panels()
	# a save keeps them; a hand-edited overlap comes off the board
	life_t.placed = false
	Tablets.place(p.tablets, life_t, 0, 0, 2)
	var raw = JSON.parse_string(JSON.stringify(save_data()))
	var clash := {"uid": "x", "shape": "mono", "ilvl": 3, "mods": {"armor": 9, "bogus": 3}, "placed": true, "x": 1, "y": 0, "rot": 0}
	var back := Tablets.normalize(raw.tablets + [clash, {"shape": "nope"}])
	var kept: Dictionary = back[0]
	print("SMOKE tablets save kept=%d same=%s rot=%d clash_off=%s bogus_gone=%s" % [back.size(), kept.mods == life_t.mods and kept.placed,
		kept.rot, not back[1].placed, not back[1].mods.has("bogus")])
	_expect("tablets_save", {"kept": back.size() == 2, "same": kept.mods == life_t.mods and kept.placed, "rot": kept.rot == 2, "clash_off": not back[1].placed,
		"bogus_gone": not back[1].mods.has("bogus")})
	# a boss drops one
	enter_map("ash")
	var n0 := p.tablets.size()
	hit_enemy(boss, {"dmg": 999999, "crit": false, "type": "phys"})
	await get_tree().create_timer(0.2).timeout
	for d in drops.filter(func(d): return d.k == "tablet"):
		_take(d)
	print("SMOKE tablets boss_drop owned+%d" % (p.tablets.size() - n0))
	_expect("tablets_boss_drop", {"owned": p.tablets.size() - n0 == 1})
	enter_hideout()


## special modifiers: 刻紋の熾石 carves one into a rare item only, beside its affixes; it reaches the stats,
## survives 混沌の残光 and a save, and a second stone carves a different one
func _smoke_brand() -> void:
	var p := player
	var magic := Items.generate(10, 0.0, 1, "armor")
	var rare := Items.generate(10, 0.0, 2, "armor")
	var magic_err := Items.craft("brand", magic)
	var n0 := Items.affix_count(rare)
	p.bag = [rare]
	p.cur.brand = 2
	hud.toggle_inventory()
	hud.inventory._pick_currency("brand")
	hud.inventory._on_bag_click(0)
	var first: String = rare.get("special", {}).get("k", "")
	hud.inventory._on_bag_click(0)
	var second: String = rare.get("special", {}).get("k", "")
	hud.inventory._cancel_craft()
	hud.toggle_inventory()
	Items.brand(rare, "s_life")
	var pct0: int = p.s.life_pct
	var old = p.equip.get("armor")
	p.equip.armor = rare
	p.recalc()
	var pct_up: bool = p.s.life_pct - pct0 == rare.special.v
	Items.craft("chaos", rare)
	var back := Items.normalize(JSON.parse_string(JSON.stringify(rare)))
	var tip := Items.lines(rare).any(func(l): return "灯心の紋" in str(l[0]))
	print("SMOKE brand magic='%s' first=%s second_differs=%s affixes_same=%s left=%d life_pct_up=%s after_chaos=%s json=%s tip=%s" % [magic_err,
		first != "", second != first and second != "", Items.affix_count(rare) <= Data.RARITY[2].aff[1] and n0 > 0, p.cur.brand, pct_up,
		rare.has("special"), back.get("special") == rare.special, tip])
	_expect("brand", {"magic_refused": magic_err != "", "first": first != "", "second_differs": second != first and second != "",
		"affixes": Items.affix_count(rare) <= Data.RARITY[2].aff[1] and n0 > 0, "spent": p.cur.brand == 0, "stats": pct_up,
		"after_chaos": rare.has("special"), "json": back.get("special") == rare.special, "tip": tip})
	if old:
		p.equip.armor = old
	else:
		p.equip.erase("armor")
	p.bag = []
	p.recalc()


## one-line crafting: the cost climbs with item level and changes currency by band without ever getting cheaper,
## and on gear (through the inventory) and on a tablet (through the board) a line is swapped or retuned on its own:
## the other lines, their order and the line count stay, the currency is spent, and the wrong targets are refused
func _smoke_line_craft() -> void:
	var p := player
	var worth := func(c: Dictionary) -> float: return float(Data.currency(c.k).value) * c.n
	var rising: bool = true
	var kinds := {}
	for act in ["swap", "tune"]:
		for lv in range(1, 60):
			rising = rising and worth.call(LineCraft.cost(lv, act)) >= worth.call(LineCraft.cost(lv - 1, act))
			kinds[LineCraft.cost(lv, act).k] = true
	print("SMOKE line_craft cost lv1=%s lv8=%s lv9=%s lv17=%s lv40=%s rising=%s kinds=%d" % [LineCraft.cost_text(LineCraft.cost(1, "swap")),
		LineCraft.cost_text(LineCraft.cost(8, "swap")), LineCraft.cost_text(LineCraft.cost(9, "swap")), LineCraft.cost_text(LineCraft.cost(17, "swap")),
		LineCraft.cost_text(LineCraft.cost(40, "swap")), rising, kinds.size()])
	_expect("line_craft_cost", {"rising": rising, "kinds": kinds.size() >= 3})
	# gear, through the inventory panel
	var rare := Items.generate(20, 0.0, 2, "amulet")
	p.bag = [rare]
	for k in ["divine", "chaos", "whet", "transmute"]:
		p.cur[k] = 20
	hud.toggle_inventory()
	var inv := hud.inventory
	inv._pick_currency("line")
	inv._on_bag_click(0)
	var picked: bool = is_same(inv.line_item, rare) and inv.line_box.visible
	var keys0: Array = rare.mods.keys()
	var mods0: Dictionary = rare.mods.duplicate()
	var sc := LineCraft.cost(20, "swap")
	var have: int = p.cur[sc.k]
	inv.line_box.craft(keys0[1], "swap")
	var keys1: Array = rare.mods.keys()
	var others: bool = range(keys0.size()).filter(func(i): return i != 1).all(func(i): return keys1[i] == keys0[i] and rare.mods[keys0[i]] == mods0[keys0[i]])
	var swapped: bool = keys1[1] != keys0[1] and not rare.mods.has(keys0[1]) and keys1.size() == keys0.size()
	var spent: int = have - p.cur[sc.k]
	var tc := LineCraft.cost(20, "tune")
	var have_t: int = p.cur[tc.k]
	var before: Dictionary = rare.mods.duplicate()
	for i in 3:
		inv.line_box.craft(keys1[0], "tune")
	var tuned_only: bool = rare.mods.keys() == keys1 and keys1.slice(1).all(func(k): return rare.mods[k] == before[k])
	var still_rows: int = inv.line_box.get_child_count()
	inv._cancel_craft()
	hud.toggle_inventory()
	# the wrong targets and too little currency
	var normal := Items.generate(5, 0.0, 0, "ring")
	var uq := Items.generate(5, 0.0, 3)
	var poor := Items.generate(30, 0.0, 2, "ring")
	var magic := Items.generate(3, 0.0, 1, "boots")
	var mk: String = magic.mods.keys()[0]
	var cur := {"whet": 5}
	var magic_err := LineCraft.apply(magic, mk, "swap", cur)
	var renamed: bool = magic.name.begins_with(Data.affix(magic.mods.keys()[0]).word)
	print("SMOKE line_craft gear picked=%s swapped=%s others_kept=%s spent=%d/%d %s tune_spent=%d/%d tuned_only=%s rows=%d normal='%s' unique='%s' poor='%s' magic='%s' renamed=%s" % [
		picked, swapped, others, spent, sc.n, sc.k, have_t - p.cur[tc.k], tc.n * 3, tuned_only, still_rows,
		LineCraft.can(normal, "life", "swap"), LineCraft.can(uq, uq.mods.keys()[0] if not uq.mods.is_empty() else "life", "swap"),
		LineCraft.apply(poor, poor.mods.keys()[0], "swap", {}), magic_err, renamed])
	_expect("line_craft_gear", {"picked": picked, "swapped": swapped, "others_kept": others, "spent": spent == sc.n, "tune_spent": have_t - p.cur[tc.k] == tc.n * 3,
		"tuned_only": tuned_only, "normal_refused": LineCraft.can(normal, "life", "swap") != "", "poor_refused": LineCraft.apply(poor, poor.mods.keys()[0], "swap", {}) != "",
		"magic": magic_err == "", "renamed": renamed})
	p.bag = []
	# a tablet, through the board
	p.tablets = []
	var t := Tablets.generate(10, "cross5", 3)
	p.tablets.append(t)
	Tablets.place(p.tablets, t, 0, 0, 0)
	p.recalc(true)
	hud.toggle(hud.tablet_ui)
	var ui: TabletUI = hud.tablet_ui
	ui.pick(t.uid)
	var tk0: Array = t.mods.keys()
	var stat0: int = Tablets.stats(p.tablets).get(tk0[2], 0)
	var tsc := LineCraft.cost(10, "swap")
	var th: int = p.cur[tsc.k]
	ui.line_box.craft(tk0[2], "swap")
	var tk1: Array = t.mods.keys()
	print("SMOKE line_craft tablet box=%s swapped=%s kept=%s lines=%d/%d spent=%d/%d stat_moved=%s" % [ui.line_box.visible, tk1[2] != tk0[2],
		tk1[0] == tk0[0] and tk1[1] == tk0[1], t.mods.size(), Tablets.max_mods(t), th - p.cur[tsc.k], tsc.n,
		stat0 > 0 and not Tablets.stats(p.tablets).has(tk0[2])])
	_expect("line_craft_tablet", {"box": ui.line_box.visible, "swapped": tk1[2] != tk0[2], "kept": tk1[0] == tk0[0] and tk1[1] == tk0[1],
		"spent": th - p.cur[tsc.k] == tsc.n, "stat_moved": stat0 > 0 and not Tablets.stats(p.tablets).has(tk0[2])})
	hud.close_panels()
	p.tablets = []
	p.recalc(true)


## sealed monoliths: one sits in the map with its label, breaking it frees the wardens and wakes the rune blasts,
## and felling them all drops 刻紋の熾石
func _smoke_seal() -> void:
	var p := player
	p.invuln = 1e9
	enter_map("ash")
	if seals.is_empty():
		place_seal(_free_spot(p.pos, 6.0))
	var sl: Dictionary = seals[0]
	var label := interacts.any(func(o): return o.get("seal") == sl)
	p.pos = map.move_circle(sl.pos + Vector2(0, 2.0), p.r, Vector2.ZERO)
	open_interact("seal", {"seal": sl})
	var wardens: int = sl.spawned.size()
	var named: bool = sl.spawned.all(func(e): return e.display_name == "封碑の番人" and e.aggro and not e.elite.is_empty())
	var status := seal_status()
	sl.pulse = Seal.PULSE
	var t0 := teles.size()
	await get_tree().create_timer(0.1).timeout
	var blasted := teles.size() > t0
	var c0: int = p.cur.brand
	for e in sl.spawned:
		hit_enemy(e, {"dmg": 999999, "crit": false, "type": "phys"})
	await get_tree().create_timer(0.2).timeout
	var stones: int = sl.get("reward", {}).get("brand", 0)
	_collect_nearby(30.0)
	print("SMOKE seal label=%s wardens=%d/%d named=%s status='%s' blast=%s state=%s stones=%d got=%d label_gone=%s no_shop=%s" % [label, wardens,
		Seal.wardens(floor_level), named, status, blasted, sl.state, stones, p.cur.brand - c0, not interacts.any(func(o): return o.get("seal") == sl),
		Data.currency("brand").w == 0.0])
	_expect("seal", {"label": label, "wardens": wardens == Seal.wardens(floor_level), "named": named, "status": status != "", "blast": blasted,
		"done": sl.state == "done", "stones": stones > 0 and p.cur.brand - c0 == stones, "label_gone": not interacts.any(func(o): return o.get("seal") == sl),
		"no_shop": Data.currency("brand").w == 0.0})
	enter_hideout()


## levelling, potions and damage: experience carries over several level-ups, each level adds a passive point
## and energy; a potion heals half the life up to the cap, is kept at full life and refused when none are left;
## damage is taken unless invulnerable, and retrying a floor costs 30% of the experience
func _smoke_progress() -> void:
	var p := player
	var keep := [p.level, p.xp, p.potions, p.invuln]
	p.level = 3
	p.xp = 0
	p.recalc(true)
	var pts0 := p.tree_points()
	var en0 := p.energy_max()
	gain_xp(Data.xp_need(3) + Data.xp_need(4) + 5)
	print("SMOKE progress level=%d xp=%d points+%d energy+%d" % [p.level, p.xp, p.tree_points() - pts0, p.energy_max() - en0])
	_expect("progress_level", {"two_levels": p.level == 5, "carry": p.xp == 5, "points": p.tree_points() == pts0 + 2, "energy": p.energy_max() == en0 + 2})
	p.potions = 2
	p.life = p.cap("life")
	_use_potion()
	var kept := p.potions == 2
	p.life = 1.0
	_use_potion()
	var healed := is_equal_approx(p.life, minf(p.cap("life"), 1.0 + p.s.max_life * 0.5))
	p.potions = 0
	p.life = 1.0
	_use_potion()
	print("SMOKE progress potion kept_at_full=%s healed=%s left=%d refused=%s" % [kept, healed, p.potions, p.life == 1.0])
	_expect("progress_potion", {"kept_at_full": kept, "healed": healed, "never_negative": p.potions == 0, "refused": p.life == 1.0})
	p.life = p.cap("life")
	p.invuln = 1e9
	damage_player(30.0)
	var shielded := p.life == p.cap("life")
	p.invuln = 0.0
	damage_player(30.0)
	var hurt := p.cap("life") - p.life
	p.invuln = 1e9
	p.xp = 100
	retry_floor()
	print("SMOKE progress damage shielded=%s hurt=%.0f retry_xp=%d" % [shielded, hurt, p.xp])
	_expect("progress_damage", {"shielded": shielded, "hurt": hurt >= 1.0 and hurt <= 30.0, "retry_xp": p.xp == 70})
	p.level = keep[0]
	p.xp = keep[1]
	p.potions = keep[2]
	p.invuln = keep[3]
	p.recalc(true)


## currency on items (Items.craft): each currency's rarity rules and affix counts, the cap on 鍛錬の砥石,
## 神聖の核 rerolling values only (a unique's lines stay in their fixed ranges), and refusals leave the item alone
func _smoke_craft() -> void:
	var aff := func(r: int, it: Dictionary) -> bool: return it.mods.size() >= Data.RARITY[r].aff[0] and it.mods.size() <= Data.RARITY[r].aff[1]
	var it := Items.generate(10, 0.0, 0, "ring")
	var errs := {}
	errs.ascend_normal = Items.craft("ascend", it)
	errs.chaos_normal = Items.craft("chaos", it)
	errs.transmute = Items.craft("transmute", it)
	var magic_ok: bool = it.rarity == 1 and aff.call(1, it)
	errs.transmute_again = Items.craft("transmute", it)
	errs.ascend = Items.craft("ascend", it)
	var rare_ok: bool = it.rarity == 2 and aff.call(2, it)
	for i in 3:
		errs["whet%d" % i] = Items.craft("whet", it)
	var whet_capped: bool = it.mods.size() == Data.RARITY[2].aff[1]
	var keys: Array = it.mods.keys()
	errs.divine = Items.craft("divine", it)
	var divine_keys: bool = it.mods.keys() == keys
	errs.chaos = Items.craft("chaos", it)
	var chaos_ok: bool = it.rarity == 2 and aff.call(2, it)
	var snap := it.duplicate(true)
	errs.not_item = Items.craft("ember", it)
	var untouched: bool = it == snap
	Items.brand(it)
	errs.purify = Items.craft("purify", it)
	var purified: bool = it.rarity == 0 and it.mods.is_empty() and not it.has("special")
	errs.divine_normal = Items.craft("divine", it)
	var uq := {}
	for l in Data.LEGENDARY:
		if l.has("mods") and not l.mods.is_empty():
			uq = Items.generate(10, 0.0, 3, "", l.name)
			break
	var fixed: Dictionary = Data.legend(uq.name).mods
	errs.divine_unique = Items.craft("divine", uq)
	var in_range: bool = fixed.keys().all(func(k): return not uq.mods.has(k) or (uq.mods[k] >= Items.roll_fixed(uq, k, [mini(fixed[k][0], fixed[k][1]), mini(fixed[k][0], fixed[k][1])])
		and uq.mods[k] <= Items.roll_fixed(uq, k, [maxi(fixed[k][0], fixed[k][1]), maxi(fixed[k][0], fixed[k][1])])))
	var refused := ["ascend_normal", "chaos_normal", "transmute_again", "not_item", "divine_normal"]
	var ok := ["transmute", "ascend", "divine", "chaos", "purify", "divine_unique"]
	print("SMOKE craft magic=%s rare=%s whet_capped=%s cap_err='%s' divine_keys=%s chaos=%s untouched=%s purified=%s unique_in_range=%s refused=%s" % [
		magic_ok, rare_ok, whet_capped, errs.whet2 if errs.whet2 != "" else errs.whet1, divine_keys, chaos_ok, untouched, purified, in_range,
		errs.keys().filter(func(k): return errs[k] != "")])
	_expect("craft", {"magic": magic_ok, "rare": rare_ok, "whet_capped": whet_capped, "cap_refused": errs.whet0 != "" or errs.whet1 != "" or errs.whet2 != "",
		"divine_keys": divine_keys, "chaos": chaos_ok, "untouched": untouched, "purified": purified, "unique_in_range": in_range,
		"refused": refused.all(func(k): return errs[k] != ""), "ok": ok.all(func(k): return errs[k] == "")})


## the whole character save: a JSON round trip gives back the same save, field by field, and a hand-broken
## save (unknown skills, gems and lineages, bad filter values, numbers as strings) loads without breaking anything
func _smoke_save() -> void:
	var p := player
	var sd := save_data()
	var text := JSON.stringify(sd)
	apply_save(JSON.parse_string(text))
	var again := save_data()
	var differs := sd.keys().filter(func(k): return JSON.stringify(again[k]) != JSON.stringify(sd[k]))
	print("SMOKE save fields=%d differs=%s" % [sd.size(), differs])
	_expect("save_roundtrip", {"same": differs.is_empty(), "all_fields": again.keys() == sd.keys()})
	var junk = JSON.parse_string(text)
	junk.level = "12"
	junk.slots = ["nope", "slash", "slash", "slash", "slash", "slash"]
	junk.links = [["nope", "power"], [], [], [], [], []]
	junk.gems = ["power", "nope"]
	junk.skills = ["slash", "nope"]
	junk.asc = "nope"
	junk.filter = {"rarity": ["pick", "eat", "pick", "pick"], "slots": {"ring": false, "nope": true}}
	junk.auras = ["nope", "slash"]
	apply_save(junk)
	print("SMOKE save junk level=%d slots_kept=%s gems=%s skills=%s asc='%s' filter=%s ring_hidden=%s auras=%s" % [p.level, p.slots == sd.slots, p.gems,
		p.skills.size(), p.asc, p.filter.rarity, not p.filter.slots.ring, p.auras])
	_expect("save_junk", {"level": p.level == 12, "slots_kept": p.slots == sd.slots, "links": p.links[0] == ["power"], "gems": not "nope" in p.gems,
		"skills": not "nope" in p.skills and p.slots.all(func(id): return id in p.skills), "asc": p.asc == "", "filter_kept": p.filter.rarity == sd.filter.rarity,
		"ring_hidden": not p.filter.slots.ring, "no_unknown_slot": not p.filter.slots.has("nope"), "auras": p.auras.is_empty()})
	apply_save(JSON.parse_string(text))


## generated maps: every floor tile can be walked to from the start, the boss room is the farthest room,
## and the hideout is a single hall
func _smoke_dungeon() -> void:
	var cut := 0
	var boss_far := true
	var sizes := []
	for i in 12:
		var m := Dungeon.new(72, 72, 1 + i * 2)
		m.compute_flow(m.tile_center(m.start.cx, m.start.cy), 99999)
		for t in m.tiles.size():
			if m.tiles[t] == 1 and m.flow[t] == -1:
				cut += 1
		var far: int = m.flow[m.idx(m.boss_room.cx, m.boss_room.cy)]
		boss_far = boss_far and far > 0 and m.rooms.all(func(r): return m.flow[m.idx(r.cx, r.cy)] <= far)
		sizes.append(m.rooms.size())
	var h := Dungeon.new(28, 26, 1, "hideout")
	print("SMOKE dungeon maps=12 unreachable=%d boss_farthest=%s rooms=%d-%d hideout_rooms=%d" % [cut, boss_far, sizes.min(), sizes.max(), h.rooms.size()])
	_expect("dungeon", {"connected": cut == 0, "boss_farthest": boss_far, "rooms": sizes.min() >= 2, "hideout": h.rooms.size() == 1 and h.start == h.boss_room})


## the character screen, on an in-memory profile file: a row per character, the base class picked for a new one
## (an unknown one falls back to the default), and deleting takes a second press
func _smoke_chars() -> void:
	Profiles.data = Profiles.fresh()
	Profiles.add_char("one", Profiles.STANDARD, "sigil")
	var two := Profiles.add_char("two", Profiles.STANDARD, "lantern")
	var ui: CharUI = hud.char_ui
	ui.open(["テスト通知"])
	var rows := ui.list.get_child_count()
	ui.pick_class("lantern")
	var picked := ui.cls
	ui.pick_class("nope")
	var fallback := ui.cls
	var del: Button = ui.list.get_child(1).get_child(2)
	del.pressed.emit()
	var after_one := Profiles.chars().size()
	del = ui.list.get_child(1).get_child(2)
	del.pressed.emit()
	print("SMOKE chars rows=%d picked=%s fallback=%s first_press_kept=%s deleted=%s left=%d" % [rows, picked, fallback, after_one == 2,
		Profiles.find(two.id).is_empty(), Profiles.chars().size()])
	_expect("chars", {"rows": rows == 2, "picked": picked == "lantern", "fallback": fallback == Data.DEFAULT_CLASS, "confirm": after_one == 2,
		"deleted": Profiles.find(two.id).is_empty() and Profiles.chars().size() == 1, "notes": ui.notes_box.get_child_count() == 1})
	ui.visible = false
	Profiles.data = Profiles.fresh()


## automated run used during development: `godot -- --smoke`
func _smoke_test() -> void:
	var p := player
	p.invuln = 1e9
	# hideout: merchant and atlas
	print("SMOKE hideout=%s interacts=%d stock=%d" % [in_hideout(), interacts.size(), shop.items.size()])
	_expect("hideout", {"in": in_hideout(), "interacts": interacts.size() == 5, "stock": shop.items.size() > 0})
	await get_tree().create_timer(0.5).timeout
	p.cur.ember = 2000
	open_interact("merchant")
	await get_tree().create_timer(0.3).timeout
	var pots := p.potions
	hud.shop_ui._buy(shop.items[0])
	hud.shop_ui._buy_potion()
	hud.shop_ui._buy_currency("chaos", Items.currency_price(Data.currency("chaos"), league()))
	print("SMOKE bought bag=%d stock=%d potions+%d chaos=%d ember=%d" % [p.bag.size(), shop.items.size(), p.potions - pots, p.cur.chaos, p.cur.ember])
	_expect("shop_buy", {"bag": p.bag.size() == 1, "potion": p.potions - pots == 1, "chaos": p.cur.chaos == 1, "paid": p.cur.ember < 2000})
	hud.shop_ui._buy_gem("leech")
	print("SMOKE shop gem gems=%s" % [p.gems])
	_expect("shop_gem", {"bought": "leech" in p.gems})
	hud.shop_ui._sell(0)
	print("SMOKE shop sold bag=%d" % p.bag.size())
	_expect("shop_sell", {"sold": p.bag.is_empty()})
	hud.close_panels()
	await _smoke_exchange()
	_smoke_seasons()
	_smoke_classes()
	_smoke_gems()
	_smoke_docs()
	_smoke_unique_tiers()
	_smoke_market()
	_smoke_trade()
	await _smoke_keys()
	open_interact("device")
	await get_tree().create_timer(0.4).timeout
	enter_map("wail")
	print("SMOKE locked map ignored=%s" % in_hideout())
	_expect("atlas_locked", {"ignored": in_hideout()})
	enter_map("ash")
	print("SMOKE entered=%s level=%d atlas_open=%s" % [area.id, floor_level, hud.atlas_ui.visible])
	_expect("atlas_enter", {"entered": area.id == "ash", "closed": not hud.atlas_ui.visible, "boss": boss != null})
	var e: Enemy = enemies.filter(func(q): return not q.boss)[0]
	p.pos = map.move_circle(e.pos + Vector2(-4, -4), p.r, Vector2.ZERO)
	await get_tree().create_timer(0.3).timeout
	mouse_ground = e.pos
	p.level = 10
	p.recalc(true)
	p.gems = Data.SUPPORTS.map(func(g): return g.id)
	p.skills = Data.SKILL_ORDER.duplicate()
	for id in Data.SKILL_ORDER:
		p.slots[0] = id
		p.action_t = 0.0
		p.cds.clear()
		p.mana = p.s.max_mana
		_try_cast(0)
		await get_tree().create_timer(0.4).timeout
	print("SMOKE skills minions=%d storms=%d hazards=%d auras=%s" % [minions.size(), storms.size(), hazards.size(), p.auras])
	_expect("skills_all", {"minions": minions.size() > 0})
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
	_expect("fx", {"zones": zones.size() > 0, "buffs": "tailwind" in p.tbuffs})
	p.slots[0] = "ice_shards"
	p.links[0] = ["trap"]
	p.action_t = 0.0
	_try_cast(0)
	print("SMOKE trap placed=%d" % totems.filter(func(t): return t.trap).size())
	_expect("trap", {"placed": totems.filter(func(t): return t.trap).size() == 1})
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
	_expect("totem", {"placed": totems.any(func(t): return t.skill == "fireball" and not t.trap), "sup": slot_sup(1).ids == ["totem", "multi", "power"]})
	# a sturdy target in its sight: the fireballs in flight can only be the totem's (the player cast none)
	var tot: Ally = totems.filter(func(t): return t.skill == "fireball" and not t.trap)[-1]
	tot.max_life = 1e7   # the pack around it must not fell it first
	tot.life = 1e7
	var dummy := _make_enemy("ghoul", _free_spot(tot.pos, 5.0), 999)
	dummy.max_life = 1e7
	dummy.life = 1e7
	var balls := 0
	var until := Time.get_ticks_msec() + 1500
	while balls == 0 and Time.get_ticks_msec() < until:   # every frame: a ball may hit a close enemy within a few
		await get_tree().process_frame
		balls = projs.filter(func(q): return q.kind == "fireball").size()
	print("SMOKE totem fired fireballs=%d alive=%s t=%.1f/%.1f target_dist=%.1f los=%s" % [balls, tot.life > 0.0, tot.t, tot.max_t,
		tot.pos.distance_to(dummy.pos), map.los(tot.pos, dummy.pos)])
	_expect("totem_fired", {"fired": balls > 0})
	hit_enemy(dummy, {"dmg": 1e9, "crit": false, "type": "phys"})
	hud.skill_ui.open_slot(0)
	hud.skill_ui._assign("fireball")
	hud.skill_ui._toggle_gem("multi")
	print("SMOKE panel slot0=%s slot1=%s links0=%s" % [p.slots[0], p.slots[1], p.links[0]])
	_expect("skill_panel", {"slot0": p.slots[0] == "fireball", "swapped": p.slots[1] == "ice_shards", "links_moved": p.links[0] == ["totem", "power"]})
	hud.close_panels()
	p.slots = Data.DEFAULT_SLOTS.duplicate()
	p.links = [[], [], [], [], [], []]
	# support gem energy: 2 + level shared by the bar, at most 6 links a skill, linking past the pool is refused
	print("SMOKE energy max=%d base=%d used=%d link_max=%d" % [p.energy_max(), Data.energy_base(p.level), p.energy_used(), Data.LINK_MAX])
	_expect("energy", {"max": p.energy_max() == 2 + p.level, "used": p.energy_used() == 0, "link_max": Data.LINK_MAX == 6})
	hud.skill_ui.open_slot(0)
	for gid in ["leech", "frostbite", "mleech", "loh", "hexhit", "cull", "efficient"]:   # 7 one-energy gems
		hud.skill_ui._toggle_gem(gid)
	hud.skill_ui.open_slot(1)
	for gid in ["power", "haste", "heavy"]:   # 3 each: the third one is past the pool
		hud.skill_ui._toggle_gem(gid)
	print("SMOKE energy links0=%d links1=%s used=%d/%d" % [p.links[0].size(), p.links[1], p.energy_used(), p.energy_max()])
	_expect("energy_links", {"six": p.links[0].size() == Data.LINK_MAX, "over_refused": p.links[1].size() == 2, "within": p.energy_used() <= p.energy_max()})
	hud.skill_ui._toggle_gem("power")
	hud.skill_ui._toggle_gem("leech")
	print("SMOKE energy unlink links1=%s used=%d" % [p.links[1], p.energy_used()])
	_expect("energy_unlink", {"power_off": not "power" in p.links[1], "within": p.energy_used() <= p.energy_max()})
	hud.skill_ui._toggle_gem("leech")
	hud.skill_ui._toggle_gem("power")
	# the pool shrinks: links power up in bar order and those past it go dark
	p.level = 5
	p.recalc()
	print("SMOKE energy shrunk max=%d active0=%d active1=%s sup1=%s" % [p.energy_max(), p.active_links(0).size(), p.active_links(1), slot_sup(1).ids])
	_expect("energy_shrunk", {"dark": p.active_links(1).is_empty() and slot_sup(1).ids.is_empty(), "first_kept": p.active_links(0).size() > 0})
	p.level = 10
	p.recalc()
	print("SMOKE energy restored active1=%s sup1=%s" % [p.active_links(1), slot_sup(1).ids])
	_expect("energy_restored", {"active": p.active_links(1).size() == 2 and slot_sup(1).ids.size() == 2})
	hud.close_panels()
	p.links = [[], [], [], [], [], []]
	# every support gem changes some skill it fits
	var unused := Data.SUPPORTS.filter(func(g): return not Data.SKILL_ORDER.any(func(id): return g.id in Data.build_sup(id, [g.id]).ids))
	print("SMOKE supports=%d skills=%d unused=%s" % [Data.SUPPORTS.size(), Data.SKILL_ORDER.size(), unused.map(func(g): return g.id)])
	_expect("supports", {"all_used": unused.is_empty()})
	# the passive tree, the loot filter and the pet
	_smoke_tree()
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
	_expect("ascend", {"took": p.asc == "pyre", "spent": p.asc_free() == 0, "fire": p.s.fire_dmg > fire0, "cores": p.asc_cores == ["fire_cost", "kill_burst", ""],
		"cost_down": slot_cost(1) < cost0})
	# a second lineage is refused while one is held; at Lv16 the third core tier opens
	hud.asc_ui._choose(Data.ASCENDANCIES[1].k)
	var aoe0: float = slot_sup(1).aoe
	p.level = 16
	for id in ["pyre_heat", "pyre_chant", "pyre_mantle", "pyre_mantle"]:   # pyre_heat is already at its max
		hud.asc_ui._rank_up(id)
	hud.asc_ui._pick_core(2, "inferno")
	print("SMOKE ascend lv16 asc=%s ranks=%s cores=%s fire_aoe x%.2f" % [p.asc, p.asc_ranks, p.asc_cores, slot_sup(1).aoe / aoe0])
	_expect("ascend_lv16", {"second_refused": p.asc == "pyre", "third_core": p.asc_cores[2] == "inferno", "aoe": slot_sup(1).aoe > aoe0,
		"capped": Data.ascendancy("pyre").minors.all(func(n): return p.asc_rank(n.id) <= n.max)})
	p.level = 10
	var em_asc: int = p.cur.ember
	hud.asc_ui._reset()
	hud.asc_ui._reset()
	print("SMOKE ascend reset asc='%s' free=%d cores=%s ember-%d" % [p.asc, p.asc_free(), p.asc_cores, em_asc - p.cur.ember])
	_expect("ascend_reset", {"asc": p.asc == "", "cores": p.asc_cores == ["", "", ""], "paid": em_asc - p.cur.ember > 0})
	hud.close_panels()
	hud.toggle(hud.filter_ui)
	hud.filter_ui._set_rarity(0, "hide")
	hud.filter_ui._set_rarity(1, "sell")
	hud.filter_ui._set_rarity(3, "sell")
	var em0: int = p.cur.ember
	var g0 := ground.size()
	drop_item(Items.generate(3, 0.0, 0), p.pos)
	print("SMOKE filter hidden ground+%d ember+%d legend_pending=%s" % [ground.size() - g0, p.cur.ember - em0, p.filter.rarity[3]])
	_expect("filter_hide", {"not_dropped": ground.size() == g0, "legend_never_sold": p.filter.rarity[3] == "pick"})
	var bag0 := p.bag.size()
	pickup_item(Items.generate(3, 0.0, 1), p.pos)
	print("SMOKE filter autosell bag+%d" % (p.bag.size() - bag0))
	_expect("filter_autosell", {"not_bagged": p.bag.size() == bag0})
	hud.close_panels()
	p.filter = Player.default_filter()
	var fetch := map.move_circle(p.pos, 0.2, Vector2(6, 0))
	_drop_currency("chaos", 1, fetch)
	var chaos0: int = p.cur.chaos
	for i in 30:   # it may be busy with another drop first
		await get_tree().create_timer(0.2).timeout
		if p.cur.chaos > chaos0:
			break
	print("SMOKE pet fetched=%s pet_dist=%.1f" % [p.cur.chaos > chaos0, pet.pos.distance_to(p.pos)])
	_expect("pet", {"fetched": p.cur.chaos > chaos0})
	hud.toggle(hud.status_ui)
	await get_tree().create_timer(0.2).timeout
	print("SMOKE status open=%s rows=%d" % [hud.status_ui.visible, hud.status_ui.stats.get_child_count()])
	_expect("status", {"open": hud.status_ui.visible, "rows": hud.status_ui.stats.get_child_count() > 0})
	hud.toggle(hud.pause_ui)
	print("SMOKE pause open=%s status_closed=%s" % [hud.pause_ui.visible, not hud.status_ui.visible])
	_expect("pause", {"open": hud.pause_ui.visible, "status_closed": not hud.status_ui.visible})
	hud.close_panels()
	await get_tree().create_timer(1.0).timeout
	var killed_before := enemies.size()
	if boss:   # a totem or minion left from the tests above may already have finished it
		hit_enemy(boss, {"dmg": 999999, "crit": false, "type": "phys"})
	print("SMOKE enemies=%d level=%d portal=%s" % [killed_before, p.level, not portal.is_empty()])
	_expect("boss_kill", {"portal": not portal.is_empty()})
	p.pos = portal.pos
	await get_tree().create_timer(0.3).timeout
	print("SMOKE completed hideout=%s cleared=%s bone_unlocked=%s wail_unlocked=%s" % [in_hideout(), atlas.cleared, atlas.is_unlocked(Data.atlas_node("bone")), atlas.is_unlocked(Data.atlas_node("wail"))])
	_expect("completed", {"hideout": in_hideout(), "cleared": "ash" in atlas.cleared, "bone": atlas.is_unlocked(Data.atlas_node("bone")),
		"wail": atlas.is_unlocked(Data.atlas_node("wail"))})
	hud.toggle(hud.passive_ui)
	hud.passive_ui._rank_up("find")   # locked until 黄金の嗅覚 has a rank
	hud.passive_ui._rank_up("gold")
	hud.passive_ui._rank_up("flask")  # no points left
	print("SMOKE passives free=%d gold=%d find=%d flask=%d gold_fx=%.2f" % [atlas.points_free(), atlas.rank("gold"), atlas.rank("find"), atlas.rank("flask"), atlas.map_effects([]).gold])
	_expect("atlas_passives", {"gold": atlas.rank("gold") == 1, "locked": atlas.rank("find") == 0, "no_points": atlas.rank("flask") == 0, "gold_fx": atlas.map_effects([]).gold > 1.0})
	hud.close_panels()
	atlas.mods["wail"] = ["life", "swarm"]
	enter_map("wail")
	print("SMOKE wail level=%d mods=%s enemies=%d rarity=%.2f" % [floor_level, run_mods, enemies.size(), mod_fx.rarity])
	_expect("map_mods", {"mods": run_mods == ["life", "swarm"], "rarity": mod_fx.rarity > 0.0, "enemies": enemies.size() > 0})
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
			var hz_old := hazards.duplicate()   # its own earlier fire may burn out meanwhile: count the new patches only
			b.pos = spot   # its moves above may have left it against a wall; the spawn spot sees the player
			b.windup = 0.0
			b.act_t = 9.0
			b.charge = {"dir": (p.pos - b.pos).normalized(), "left": 8.0, "hit": false, "trail": 0.0}
			await get_tree().create_timer(0.6).timeout
			var trail := hazards.filter(func(h): return not hz_old.any(func(o): return is_same(o, h))).size()
			print("SMOKE charge done=%s trail+%d" % [b.charge.is_empty(), trail])
			_expect("colossus_charge", {"done": b.charge.is_empty(), "trail": trail > 0})
		b.life = b.max_life * 0.4
		for k in 30:
			if b.enraged:
				break
			await get_tree().create_timer(0.1).timeout
		print("SMOKE %s alive=%s enraged=%s max_shots=%d max_chill=%.1f" % [kind, not b.dead, b.enraged, shots, chill])
		_expect("boss_" + kind, {"alive": not b.dead, "enraged": b.enraged, "shots": shots > 0})   # the chill is printed only: it needs a random shard to land
		hit_enemy(b, {"dmg": 999999, "crit": false, "type": "phys"})
		await get_tree().create_timer(0.3).timeout
	p.invuln = 0.0
	damage_player(1e9)
	await get_tree().create_timer(1.2).timeout
	print("SMOKE dead=%s death_screen=%s" % [p.dead, hud.death.visible])
	_expect("death", {"dead": p.dead, "screen": hud.death.visible})
	retry_floor()
	hud.death.visible = false
	print("SMOKE retry dead=%s life=%d" % [p.dead, p.life])
	_expect("retry", {"alive": not p.dead, "life": p.life > 0.0})
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
	_expect("loot", {"picked": p.bag.size() >= 3, "ground": ground.is_empty()})
	hud.toggle_inventory()
	var mi := p.bag.find(p.bag.filter(func(x): return x.rarity == 1)[0])
	var before: Dictionary = p.bag[mi].mods.duplicate()
	hud.inventory._pick_currency("chaos")
	hud.inventory._on_bag_click(mi)
	print("SMOKE chaos rerolled=%s left=%d" % [before != p.bag[mi].mods or p.bag[mi].mods.size() != before.size(), p.cur.chaos])
	_expect("chaos", {"rerolled": before != p.bag[mi].mods or p.bag[mi].mods.size() != before.size()})
	hud.inventory._cancel_craft()
	var slot: String = p.bag[0].slot
	hud.inventory._on_bag_click(0)
	print("SMOKE equipped=%s life=%d" % [p.equip.has(slot), p.s.max_life])
	_expect("equip", {"equipped": p.equip.has(slot)})
	var e0: int = p.cur.ember
	hud.inventory._on_bag_right(0)
	print("SMOKE sold ember+%d" % (p.cur.ember - e0))
	_expect("inv_sell", {"ember": p.cur.ember > e0})
	var it := Items.generate(5, 2.0, 2)
	var back := Items.normalize(JSON.parse_string(JSON.stringify(it)))
	print("SMOKE json roundtrip=%s" % (back == it))
	_expect("item_json", {"roundtrip": back == it})
	await get_tree().create_timer(0.5).timeout
	hud.toggle_inventory()
	await _smoke_farm()
	await _smoke_tablets()
	_smoke_brand()
	_smoke_line_craft()
	await _smoke_seal()
	_smoke_progress()
	_smoke_craft()
	_smoke_jewels()
	_smoke_save()
	_smoke_dungeon()
	_smoke_chars()
	print("SMOKE RESULT checks=%d failed=%d %s" % [smoke_checks, smoke_failed.size(), smoke_failed])
	get_tree().quit(1 if smoke_failed.size() > 0 else 0)


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
const PANEL_ACTIONS := ["inventory", "skills", "talents", "ascendancy", "status", "filter", "passives", "tablets", "keyconfig"]


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
	for list in [projs, proj_spawn, eprojs, teles, hazards, storms, zones, texts, ground, drops, interacts, altars, seals]:
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
	if randf() < Seal.CHANCE:
		_place_seal()
	hud.message("%s — エリアレベル %d" % [area.name, floor_level], Color("#e8d8b0"))
	for k in run_mods:
		hud.message("◆ " + Data.map_mod(k).name, Color("#ff9a7a"))
	if altars.size() > 0:
		hud.message("燼火の祭壇が %d つ眠っている" % altars.size(), Farm.COLOR)
	if seals.size() > 0:
		hud.message("刻紋の封碑の気配がする", Seal.COLOR)
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
	elif kind == "seal":
		break_seal(o.seal)
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
	Trade.ensure(league(), atlas.hideout_level())   # the gear others put up is made at the hideout level
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
		_update_seals(delta)
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
		p.recalc(true)
		add_text(p.pos, "LEVEL UP!", Color("#ffe27a"), 28)
		Fx.ring(level_root, to3(p.pos), 5.0, Color("#ffe27a"), 0.6, false)
		Fx.burst(level_root, to3(p.pos, 1.0), 40, Color("#ffe27a"), 6.0)
		hud.message("レベル %d に到達！ パッシブポイント +1（%s）" % [p.level, Keybinds.text("talents")], Color("#ffe27a"))
		if Data.asc_points(p.level) > Data.asc_points(p.level - 1):
			hud.message("アセンダンシーポイント +1（%s）" % Keybinds.text("ascendancy"), Data.ascendancy(p.asc).get("color", Color("#ffcf7a")))
		hud.message("エネルギー上限 +1（%d）" % p.energy_max(), Data.GEM_COLOR)
		for id in p.skills:
			if Data.SKILLS[id].lvl == p.level:
				hud.message("スキル「%s」が使えるようになった（%sで付け替え）" % [Data.SKILLS[id].name, Keybinds.text("skills")], Data.SKILLS[id].color)
		for gid in p.gems:
			if Data.support(gid).lvl == p.level:
				hud.message("サポートジェム「%s」をリンクできるようになった" % Data.support(gid).name, Data.support(gid).color)
		hud.skill_ui.refresh()
		hud.tree_ui.refresh()
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
	d *= (1.0 + inc / 100.0) * sup.dmg * sup.get("m_" + type, 1.0)
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
		_drop_tablet(e.pos, floor_level + 2)
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


# =================== sealed monoliths ===================
## one monolith in a room away from the start, the boss and the altars
func _place_seal() -> void:
	var rooms := map.rooms.filter(func(r): return r != map.start and r != map.boss_room)
	rooms.shuffle()
	for room in rooms:
		for tries in 12:
			var tx: int = randi_range(room.x + 2, room.x + room.w - 3) if tries > 0 else int(room.cx)
			var ty: int = randi_range(room.y + 2, room.y + room.h - 3) if tries > 0 else int(room.cy)
			var at := map.tile_center(tx, ty)
			if map.is_wall(tx, ty) or map.circle_hits(at, 1.4) or altars.any(func(a): return a.pos.distance_to(at) < 12.0):
				continue
			place_seal(at)
			return


## a sealed monolith at `at`, broken open from its [B] label
func place_seal(at: Vector2) -> Dictionary:
	var sl := {"pos": at, "state": "sealed", "spawned": [], "pulse": 0.0}
	sl.merge(_build_seal(at))
	seals.append(sl)
	interacts.append({"kind": "seal", "name": "刻紋の封碑", "pos": at, "r": 1.2, "seal": sl})
	var t := Vector2i(floori(at.x / T), floori(at.y / T))
	map.blocked[map.idx(t.x, t.y)] = 1
	return sl


## a tall dark obelisk on a square plinth, its carved runes glowing faintly until the seal breaks
func _build_seal(at: Vector2) -> Dictionary:
	var root := Node3D.new()
	root.position = to3(at)
	level_root.add_child(root)
	Fx.mesh(root, Fx.box(Vector3(1.9, 0.3, 1.9)), Fx.mat(Color("#26302e")), Vector3(0, 0.15, 0))
	var pillar := Fx.mesh(root, Fx.box(Vector3(0.8, 3.2, 0.8)), Fx.mat(Color("#1e2624")), Vector3(0, 1.9, 0))
	pillar.rotation.y = PI / 4
	var rune_mat := Fx.mat(Seal.COLOR, 1.2, true)
	for k in 4:
		var face := Vector2.from_angle(k * PI / 2) * 0.58
		for j in 3:
			var rune := Fx.mesh(root, Fx.box(Vector3(0.22, 0.32, 0.22)), rune_mat, to3(face, 1.0 + j * 0.85))
			rune.rotation.y = k * PI / 2 + PI / 4
	var light := OmniLight3D.new()
	light.light_color = Seal.COLOR
	light.light_energy = 0.9
	light.omni_range = 5.0
	light.position.y = 2.4
	root.add_child(light)
	return {"node": root, "rune_mat": rune_mat, "light": light}


## break the seal: the wardens come out around the monolith and it wakes
func break_seal(sl: Dictionary) -> void:
	if sl.state != "sealed":
		return
	sl.state = "active"
	interacts = interacts.filter(func(o): return o.get("seal") != sl)
	sl.rune_mat.emission_energy_multiplier = 5.0
	sl.light.light_energy = 3.0
	sl.light.omni_range = 10.0
	var kinds := ["brute", "shaman", "ghoul", "archer"]
	for i in Seal.wardens(floor_level):
		var at := _altar_spot(sl.pos)
		var e := _make_enemy(kinds[i % kinds.size()], at, 20000 + seals.find(sl), Data.ELITE_AFFIXES.pick_random())
		e.set_meta("seal", true)
		e.display_name = "封碑の番人"
		e.max_life *= 2.2
		e.life = e.max_life
		e.aggro = true
		e.xp *= 2.0
		Fx.burst(level_root, to3(at, 0.6), 14, Seal.COLOR, 5.0)
		sl.spawned.append(e)
	Fx.ring(level_root, to3(sl.pos), Seal.RADIUS, Seal.COLOR, 0.6, false)
	shake = maxf(shake, 4.0)
	hud.message("封碑の封印が解けた — 番人 %d 体をすべて倒せ！" % sl.spawned.size(), Seal.COLOR)


func seal_alive(sl: Dictionary) -> int:
	return sl.spawned.filter(func(e): return is_instance_valid(e) and not e.dead).size()


## while wardens stand, the monolith hurls rune blasts at the player; the last one down ends it
func _update_seals(delta: float) -> void:
	for sl in seals:
		if sl.state != "active":
			continue
		if seal_alive(sl) == 0:
			_end_seal(sl)
			continue
		sl.pulse += delta
		if sl.pulse >= Seal.PULSE and player.pos.distance_to(sl.pos) < 22.0:
			sl.pulse = 0.0
			var at := player.pos
			var dmg: float = Seal.blast_dmg(floor_level) * mod_fx.dmg
			Fx.burst(level_root, to3(sl.pos, 3.4), 8, Seal.COLOR, 4.0)
			add_tele(at, Seal.BLAST_R, 1.1, true, func():
				_explosion(at, Seal.BLAST_R, Seal.COLOR)
				_damage_area(at, Seal.BLAST_R, dmg))


## every warden down: the monolith goes dark and pays its stones
func _end_seal(sl: Dictionary) -> void:
	sl.state = "done"
	sl.rune_mat.emission_energy_multiplier = 0.2
	sl.light.light_energy = 0.3
	var rw := Seal.reward(floor_level)
	_drop_currency("brand", rw.brand, sl.pos + Vector2(0, 1.6))
	for i in rw.items:
		drop_item(Items.generate(floor_level + 1, rw.rarity, 2), sl.pos + Vector2.from_angle(randf() * TAU) * 1.8)
	_drop_currency("ember", roundi(randf_range(6, 10) * floor_level * mod_fx.gold), sl.pos + Vector2(1.6, 0))
	sl.reward = rw
	Fx.burst(level_root, to3(sl.pos, 2.0), 50, Seal.COLOR, 8.0)
	hud.message("刻紋の封碑を鎮めた！ %s 刻紋の熾石 ×%d" % [Data.currency("brand").icon, rw.brand], Seal.COLOR)


func seal_status() -> String:
	for sl in seals:
		if sl.state == "active":
			return "刻紋の封碑 番人 残り%d体" % seal_alive(sl)
	return ""


# =================== tablets ===================
## a boss's tablet, lying on the floor as a flat glowing slab until picked up
func _drop_tablet(at: Vector2, ilvl: int) -> void:
	var t := Tablets.generate(ilvl)
	var pos := _scatter(at)
	var node := Fx.mesh(level_root, Fx.box(Vector3(0.55, 0.12, 0.42)), Fx.mat(Tablets.COLOR, 3.0), to3(pos, 0.3))
	drops.append({"k": "tablet", "n": 1, "tablet": t, "pos": pos, "node": node})


## a tablet joins the character's collection (broken down into ember once the collection is full)
func gain_tablet(t: Dictionary) -> void:
	var p := player
	if p.tablets.size() >= Tablets.MAX_OWNED:
		p.cur.ember += Tablets.shard_value(t)
		hud.message("石板が一杯のため %s を砕いた（+%d 灰燼の欠片）" % [Tablets.name_of(t), Tablets.shard_value(t)], Color("#ffcf3a"))
		return
	p.tablets.append(t)
	hud.message("石板「%s」（%dマス）を手に入れた（%s）" % [Tablets.name_of(t), Tablets.cell_count(t), Keybinds.text("tablets")], Tablets.COLOR)
	hud.tablet_ui.refresh()


# =================== jewels ===================
## a jewel (or, with `ring`, a ring jewel) lying on the floor as a small glowing gem until picked up
func _drop_jewel(at: Vector2, ilvl: int, ring := false) -> void:
	var j := Jewels.generate_ring(ilvl) if ring else Jewels.generate(ilvl)
	var pos := _scatter(at)
	var node := Fx.mesh(level_root, Fx.box(Vector3.ONE * (0.34 if ring else 0.26)), Fx.mat(Jewels.RING_COLOR if ring else Jewels.COLOR, 4.0), to3(pos, 0.35))
	node.rotation = Vector3(0.0, 0.7, 0.7)
	drops.append({"k": "jewel", "n": 1, "jewel": j, "pos": pos, "node": node})


## a jewel joins the character's collection (broken down into ember once the collection is full)
func gain_jewel(j: Dictionary) -> void:
	var p := player
	if p.jewels.size() >= Jewels.MAX_OWNED:
		p.cur.ember += Jewels.shard_value(j)
		hud.message("ジュエルが一杯のため %s を砕いた（+%d 灰燼の欠片）" % [j.name, Jewels.shard_value(j)], Color("#ffcf3a"))
		return
	p.jewels.append(j)
	hud.message("%s「%s」を手に入れた（%s）" % ["環晶" if Jewels.is_ring(j) else "燈晶", j.name, Keybinds.text("talents")], Jewels.RING_COLOR if Jewels.is_ring(j) else Jewels.COLOR)
	hud.tree_ui.refresh()


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
	if randf() < (0.8 if e.boss else (0.3 if not e.elite.is_empty() else 0.02)):
		_drop_gem(e.pos, ilvl)
	if randf() < (0.6 if e.boss else (0.12 if not e.elite.is_empty() else 0.006)):
		_drop_jewel(e.pos, ilvl, randf() < (0.4 if e.boss else 0.15))


## a skill gem or support gem the player doesn't own yet, mostly ones the area level is close to
## (up to GEM_DROP_AHEAD levels past it); once those are all owned, any missing one
const GEM_DROP_AHEAD := 2
func _drop_gem(at: Vector2, ilvl: int) -> void:
	var missing := Data.missing_gems(player.skills, player.gems, ilvl + GEM_DROP_AHEAD)
	if missing.is_empty():
		missing = Data.missing_gems(player.skills, player.gems)
	if missing.is_empty():
		return
	var pick: Dictionary = missing.pick_random()
	var pos := _scatter(at)
	# skill gems are larger and glow in the skill's own color; support gems are the green cube
	var col: Color = Data.SKILLS[pick.id].color if pick.skill else Data.GEM_COLOR
	var node := Fx.mesh(level_root, Fx.box(Vector3.ONE * (0.4 if pick.skill else 0.3)), Fx.mat(col, 4.0), to3(pos, 0.35))
	node.rotation = Vector3(0.7, 0.0, 0.7)
	drops.append({"k": "gem", "n": 1, "gem": pick.id, "skill": pick.skill, "pos": pos, "node": node})


func unlock_gem(id: String) -> void:
	var p := player
	if id in p.gems:
		p.cur.ember += 40 * floor_level
		return
	p.gems.append(id)
	var g := Data.support(id)
	var when := "%sでリンク" % Keybinds.text("skills") if p.level >= g.lvl else "Lv %d からリンクできる" % g.lvl
	hud.message("サポートジェム「%s」を入手！（%s）" % [g.name, when], g.color)
	hud.skill_ui.refresh()


## a skill gem: the skill joins the list the bar can take from (a duplicate turns into ember shards)
func learn_skill(id: String) -> void:
	var p := player
	if id in p.skills:
		p.cur.ember += 40 * floor_level
		return
	p.skills.append(id)
	var sk: Dictionary = Data.SKILLS[id]
	var when := "%sで付け替え" % Keybinds.text("skills") if p.level >= sk.lvl else "Lv %d から使える" % sk.lvl
	hud.message("スキルジェム「%s」を入手！（%s）" % [sk.name, when], sk.color)
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
	if g.k == "tablet":
		gain_tablet(g.tablet)
		return
	if g.k == "jewel":
		gain_jewel(g.jewel)
		return
	if g.k == "gem":
		if g.get("skill", false):
			learn_skill(g.gem)
		else:
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
		"slots": p.slots, "links": p.links, "gems": p.gems, "skills": p.skills, "tree": p.tree, "filter": p.filter,
		"cls": p.cls, "asc": p.asc, "asc_ranks": p.asc_ranks, "asc_cores": p.asc_cores, "auras": p.auras, "tablets": p.tablets, "jewels": p.jewels}


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
	# skill gems: characters from before skill gems keep every skill their level had taught them
	if data.has("skills"):
		p.skills = Array(data.skills).filter(func(id): return Data.SKILLS.has(id))
	else:
		p.skills = Data.SKILL_ORDER.filter(func(id): return Data.SKILLS[id].lvl <= p.level)
	for id in p.slots:
		if not id in p.skills:
			p.skills.append(id)
	# links that need more level than the character has come off (the gems stay owned)
	p.links = p.links.map(func(l): return l.filter(func(id): return p.level >= Data.support(id).lvl))
	# talents came before the passive tree: their points come back as passive points
	# jewels first: a ring jewel's nodes have to be in the tree before the saved tree is checked against it
	p.jewels = Jewels.normalize(data.get("jewels", []))
	var rt = data.get("tree", [])
	p.tree = rt if typeof(rt) == TYPE_ARRAY else []
	p.fix_jewels()
	var tl = data.get("talents", {})
	talents_refunded = not data.has("tree") and typeof(tl) == TYPE_DICTIONARY and tl.values().any(func(v): return int(v) > 0)
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
	p.tablets = Tablets.normalize(data.get("tablets", []))
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
