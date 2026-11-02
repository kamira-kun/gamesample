class_name Profiles
## Every character and the stashes, in one JSON file. A character belongs to a league: "standard",
## or a season id from Data.SEASONS. Each league shares one stash between its characters.
## When a season ends its characters and stash tabs move to standard (see `migrate`).
## Each league also has a currency exchange (`market`, see Market) and a stash currency pool
## (`stash_cur`) that holds currency handed back while no character was there to take it,
## and its cinder altar progress (`farm`, see Farm).

const PATH := "user://emberfall_profiles.json"
const OLD_PATH := "user://emberfall_save.json"   # v1: the single character before seasons; left in place as a backup
const VERSION := 2
const STANDARD := "standard"
const TAB_SIZE := 48
const TABS := 4

static var data := {}
static var active := ""        # id of the character being played; survives the scene reload that starts it
static var read_only := false   # dev runs (`--smoke`, `--view=`): never write the file


## read the file (or turn a v1 save into the first standard character), then end finished seasons;
## returns the lines to tell the player about anything that moved
static func load_all(today := Data.today()) -> Array:
	data = {}
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(d) == TYPE_DICTIONARY:
			data = d
	if data.is_empty():
		data = fresh()
		if FileAccess.file_exists(OLD_PATH):
			var old = JSON.parse_string(FileAccess.get_file_as_string(OLD_PATH))
			if typeof(old) == TYPE_DICTIONARY:
				var c := add_char("放浪者", STANDARD)
				c.data = old
	normalize(data)
	var notes := migrate(data, today)
	save_all()
	return notes


static func fresh() -> Dictionary:
	return {"version": VERSION, "next_id": 1, "chars": [], "stash": {}, "market": {}, "stash_cur": {}, "farm": {}}


## fill in anything an older or hand-edited file lacks
static func normalize(d: Dictionary) -> void:
	d.version = VERSION
	d.next_id = int(d.get("next_id", 1))
	if typeof(d.get("chars")) != TYPE_ARRAY:
		d.chars = []
	d.chars = d.chars.filter(func(c): return typeof(c) == TYPE_DICTIONARY and c.has("id"))
	for c in d.chars:
		c.name = str(c.get("name", "名無し"))
		c.league = str(c.get("league", STANDARD))
		c.from_season = str(c.get("from_season", ""))
		if typeof(c.get("data")) != TYPE_DICTIONARY:
			c.data = {}
		c.cls = infer_class(c)
	if typeof(d.get("stash")) != TYPE_DICTIONARY:
		d.stash = {}
	for lg in d.stash.keys():
		var tabs = d.stash[lg]
		if typeof(tabs) != TYPE_ARRAY:
			d.stash.erase(lg)
			continue
		d.stash[lg] = tabs.filter(func(t): return typeof(t) == TYPE_DICTIONARY).map(func(t):
			return {"name": str(t.get("name", "")), "items": Array(t.get("items", [])).map(func(it): return Items.normalize(it))})
	if typeof(d.get("market")) != TYPE_DICTIONARY:
		d.market = {}
	for lg in d.market.keys():
		if typeof(d.market[lg]) != TYPE_DICTIONARY:
			d.market.erase(lg)
		else:
			Market.normalize(lg, d.market[lg])
	if typeof(d.get("stash_cur")) != TYPE_DICTIONARY:
		d.stash_cur = {}
	for lg in d.stash_cur.keys():
		var w = d.stash_cur[lg]
		if typeof(w) != TYPE_DICTIONARY:
			d.stash_cur.erase(lg)
			continue
		for k in w.keys():
			w[k] = int(w[k])
	Farm.normalize(d)


## the base class of a character: the one it was made with, or for a character from before base classes
## (or a hand-edited one that does not match its ascendancy) the class its chosen ascendancy belongs to,
## else the default one
static func infer_class(c: Dictionary) -> String:
	var asc := str(c.data.get("asc", ""))
	var by_asc := Data.class_of_asc(asc)
	for k in [str(c.get("cls", "")), str(c.data.get("cls", ""))]:
		if not Data.base_class(k).is_empty() and (by_asc == "" or by_asc == k):
			return k
	return by_asc if by_asc != "" else Data.DEFAULT_CLASS


## move the characters and stash of every season that is no longer running into standard
static func migrate(d: Dictionary, today: String) -> Array:
	var notes := []
	for c in d.chars:
		if c.league != STANDARD and not Data.season_running(c.league, today):
			notes.append("%s はシーズン終了によりスタンダードへ移行しました" % c.name)
			c.from_season = c.league
			c.league = STANDARD
	for lg in d.stash.keys():
		if lg == STANDARD or Data.season_running(lg, today):
			continue
		var sname: String = Data.season(lg).get("name", lg)
		var dest := stash_tabs(STANDARD, d)
		var n := 0
		for t in d.stash[lg]:
			if t.items.is_empty():
				continue
			n += 1
			dest.append({"name": "%s %d" % [sname, n], "items": t.items})
		d.stash.erase(lg)
		if n > 0:
			notes.append("%s のスタッシュをスタンダードのタブ %d 枚に移しました" % [sname, n])
	# a finished season's market is thrown away; what its orders still held goes to standard's stash currency,
	# and the gear listed or waiting in its pickup box to a standard stash tab
	for lg in d.get("market", {}).keys():
		if lg == STANDARD or Data.season_running(lg, today):
			continue
		var back := Market.dissolve(d.market[lg])
		var gear := Trade.dissolve_items(d.market[lg])
		d.market.erase(lg)
		var sname: String = Data.season(lg).get("name", lg)
		var dest := stash_tabs(STANDARD, d)
		for i in range(0, gear.size(), TAB_SIZE):
			dest.append({"name": "%s 取引所" % sname, "items": gear.slice(i, i + TAB_SIZE)})
		if not gear.is_empty():
			notes.append("%s の取引所の出品と受け取り箱の装備 %d 個をスタンダードのスタッシュに移しました" % [sname, gear.size()])
		var w := stash_cur(STANDARD, d)
		var n := 0
		for k in back:
			if back[k] > 0:
				w[k] = w.get(k, 0) + back[k]
				n += back[k]
		if n > 0:
			notes.append("%s の取引所の注文を取り消し、通貨をスタンダードのスタッシュに戻しました" % sname)
	for lg in d.get("stash_cur", {}).keys():
		if lg == STANDARD or Data.season_running(lg, today):
			continue
		var w := stash_cur(STANDARD, d)
		for k in d.stash_cur[lg]:
			w[k] = w.get(k, 0) + d.stash_cur[lg][k]
		d.stash_cur.erase(lg)
	notes.append_array(Farm.migrate(d, today))
	return notes


static func save_all() -> void:
	if read_only:
		return
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if not f:
		return
	f.store_string(JSON.stringify(data))
	f.close()
	DirAccess.rename_absolute(tmp, PATH)


static func chars() -> Array:
	return data.get("chars", [])


static func find(id: String) -> Dictionary:
	for c in chars():
		if c.id == id:
			return c
	return {}


static func current() -> Dictionary:
	return find(active)


static func add_char(cname: String, league: String, cls := Data.DEFAULT_CLASS) -> Dictionary:
	var c := {"id": "c%d" % data.next_id, "name": cname, "league": league, "from_season": "", "cls": cls,
		"created": int(Time.get_unix_time_from_system()), "data": {}}
	data.next_id += 1
	data.chars.append(c)
	return c


static func remove_char(id: String) -> void:
	data.chars = chars().filter(func(c): return c.id != id)


## the stash tabs a league shares, made on first use
static func stash_tabs(league: String, d := data) -> Array:
	if not d.stash.has(league):
		var tabs := []
		for i in TABS:
			tabs.append({"name": str(i + 1), "items": []})
		d.stash[league] = tabs
	return d.stash[league]


## the currency a league's stash holds (from orders closed by a season ending), made on first use
static func stash_cur(league: String, d := data) -> Dictionary:
	if typeof(d.get("stash_cur")) != TYPE_DICTIONARY:
		d.stash_cur = {}
	if not d.stash_cur.has(league):
		d.stash_cur[league] = {}
	return d.stash_cur[league]


## move a league's stash currency into `wallet`; returns how many pieces moved
static func take_stash_cur(league: String, wallet: Dictionary, d := data) -> int:
	var w := stash_cur(league, d)
	var n := 0
	for k in w:
		wallet[k] = wallet.get(k, 0) + w[k]
		n += w[k]
	w.clear()
	return n


static func league_name(league: String) -> String:
	return "スタンダード" if league == STANDARD else Data.season(league).get("name", league)
